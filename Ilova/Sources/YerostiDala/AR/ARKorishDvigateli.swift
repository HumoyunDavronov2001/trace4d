import ARKit
import Foundation
import Observation
import RealityKit
import UIKit
import YerostiDrayver
import YerostiGeometriya
import YerostiHUD
import YerostiTahlil

/// AR ko'rish ekrani holati (D-10).
@MainActor @Observable
final class ARKorishHolati {
    enum Rejim: String, CaseIterable, Identifiable {
        case korish = "Ko'rish", chuqur = "Virtual chuqur", xavf = "Xavf zonasi"
        var id: String { rawValue }
    }

    var rejim: Rejim = .korish
    var juftSoni = 0
    var yoyilishM = 0.0
    var rmsM: Double?
    var boglangan = false
    var tarmoqlar: [MahalliyTarmoq] = []
    var pudratchiSoni = 0
    var yuklash: String?
    var nishon: NishonNatija?
    var xavf: [XavfNatija] = []
    var poligonSoni = 0
    var xabar: String?
    var kuzatuv: Kuzatuv = .normal
    /// UI-14: faqat ko'rinish filtri. Nishon va xavf zonasi BARCHA tarmoqlarni hisobga oladi (xavfsizlik).
    var yashirinTurlar: Set<String> = []
    var faqatRasmiy = false
    /// UI-15: eng yaqin quvur ekrandan tashqarida bo'lsa — yo'nalish (radian, + o'ngda), masofa, turi.
    var chet: ChetKorsatkich?

    struct ChetKorsatkich: Equatable {
        var burchak: Double
        var masofaM: Double
        var turi: String
    }

    /// Sahnadagi tarmoq turlari (filtr chiplari uchun), tartiblangan.
    var turlar: [String] { Array(Set(tarmoqlar.map(\.turi))).sorted() }

    func korinadimi(_ t: MahalliyTarmoq) -> Bool {
        !yashirinTurlar.contains(t.turi) && (!faqatRasmiy || t.sifat == "RASMIY")
    }
}

/// AR-01…AR-08: RTK traektoriyasidan bog'lash → serverdan shahar reestri (K-09) → quvurlarni kamera ustida ko'rsatish.
@MainActor
final class ARKorishDvigateli: NSObject, ARSessionDelegate, ARDvigatel {
    let holat = ARKorishHolati()
    private let rtk: RTKBoshqaruv
    private let sozlama: Sozlamalar
    private var georefY: GeorefYiguvchi
    private weak var arView: ARView?

    private let ildiz = AnchorEntity(world: .zero)
    private let chuqurIldiz = AnchorEntity(world: .zero)
    private let xavfIldiz = AnchorEntity(world: .zero)
    private var tarmoqEntity: [Int: ModelEntity] = [:]
    private var yorliqlar: [Entity] = []
    private var global: [GlobalTarmoq] = []
    private var oxirgiYuklash: (lat: Double, lon: Double)?
    private var chizilganJuft = 0
    private var poligon: [Vektor3] = []
    private var oxirgiNishon: TimeInterval = 0
    private var oxirgiYorliq: TimeInterval = 0

    init(rtk: RTKBoshqaruv, sozlama: Sozlamalar) {
        self.rtk = rtk
        self.sozlama = sozlama
        georefY = GeorefYiguvchi(sozlama: sozlama)
        super.init()
    }

    // MARK: ARDvigatel

    func ulan(_ v: ARView) {
        arView = v
        v.session.delegate = self
        v.scene.addAnchor(ildiz)
        v.scene.addAnchor(chuqurIldiz)
        v.scene.addAnchor(xavfIldiz)
        let c = ARWorldTrackingConfiguration()
        c.worldAlignment = .gravity
        c.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { c.sceneReconstruction = .mesh }
        c.environmentTexturing = .none
        v.session.run(c, options: [.resetTracking, .removeExistingAnchors])
        rtk.epoxaKeldi = { [weak self] h, t in self?.epoxa(h, t) }
        if !rtk.ulangan {
            holat.xabar = "RTK ulanmagan — AR joylashuvi bir necha metr xato bo'ladi, qazish uchun yaroqsiz. Ulanish → Emlid."
        }
    }

    func toxtat() {
        rtk.epoxaKeldi = nil
        arView?.session.pause()
    }

    func bosildi(_ nuqta: CGPoint) {
        guard holat.rejim != .korish else { return }
        guard let v = arView, let r = v.raycast(from: nuqta, allowing: .estimatedPlane, alignment: .horizontal).first else {
            holat.xabar = "Yer sirti topilmadi — telefonni yerga qarating"; return
        }
        let p = vektor(r.worldTransform.columns.3)
        switch holat.rejim {
        case .chuqur: chuqurQur(p)
        case .xavf:
            poligon.append(p)
            holat.poligonSoni = poligon.count
            xavfYangila()
        case .korish: break
        }
    }

    // MARK: Kadr

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated { self.kadr(frame) }
    }

    private func kadr(_ f: ARFrame) {
        georefY.poza(f.timestamp, f.camera.transform)
        let k = Kuzatuv(f.camera.trackingState)
        if holat.kuzatuv != k { holat.kuzatuv = k }
        // UI-16: joy qayta aniqlanayotganda virtual obyektlar yashiriladi (HIG: miltillamasin)
        let korinsin = !(k == .qaytaAniqlash || k == .sozlanmoqda || k == .cheklangan)
        if ildiz.isEnabled != korinsin {
            ildiz.isEnabled = korinsin; chuqurIldiz.isEnabled = korinsin; xavfIldiz.isEnabled = korinsin
        }
        if f.timestamp - oxirgiNishon > 0.1 { oxirgiNishon = f.timestamp; nishonYangila(f); chetYangila(f) }
        if f.timestamp - oxirgiYorliq > 0.25 { oxirgiYorliq = f.timestamp; yorliqlarniBur(f.camera.transform) }
    }

    // MARK: Ekrandan tashqaridagi quvur (UI-15)

    private func chetYangila(_ f: ARFrame) {
        guard holat.boglangan, holat.rejim == .korish, ildiz.isEnabled, let v = arView else { holat.chet = nil; return }
        let T = f.camera.transform
        let kam = Vektor3(Double(T.columns.3.x), Double(T.columns.3.y), Double(T.columns.3.z))
        var eng: (d: Double, q: Vektor3, turi: String)?
        for t in holat.tarmoqlar where holat.korinadimi(t) {
            guard let q = Yonalish.engYaqin(kamera: kam, oqlar: [t.oq]) else { continue }
            let d = (q.x - kam.x) * (q.x - kam.x) + (q.z - kam.z) * (q.z - kam.z)
            if d < (eng?.d ?? .infinity) { eng = (d, q, t.turi) }
        }
        guard let e = eng else { holat.chet = nil; return }
        if let s = v.project(f3(e.q)), v.bounds.insetBy(dx: 24, dy: 80).contains(s) { holat.chet = nil; return }
        let oldi = Vektor3(Double(-T.columns.2.x), Double(-T.columns.2.y), Double(-T.columns.2.z))
        let n = Yonalish.nisbiy(kamera: kam, oldinga: oldi, nuqta: e.q)
        holat.chet = .init(burchak: n.burchak, masofaM: n.masofa, turi: e.turi)
    }

    // MARK: Qayta bog'lash (UI-16, HIG: foydalanuvchi qayta boshlay olsin)

    func qaytaBoglash() {
        georefY = GeorefYiguvchi(sozlama: sozlama)
        holat.boglangan = false
        holat.juftSoni = 0
        holat.yoyilishM = 0
        holat.rmsM = nil
        holat.nishon = nil
        holat.chet = nil
        chizilganJuft = 0
        ildiz.children.removeAll()
        tarmoqEntity = [:]
        yorliqlar = []
        holat.xabar = "Qayta bog'lash: RTK FIX holatida 2–3 m yuring"
    }

    /// UI-14: filtr o'zgarganda sahna qayta chiziladi.
    func filtrniQolla() { chiz() }

    // MARK: Bog'lash (AR-01)

    private func epoxa(_ h: QabulQilgichHolati, _ t: TimeInterval) {
        guard georefY.epoxa(h, t) else { return }
        holat.juftSoni = georefY.juftSoni
        holat.yoyilishM = georefY.yoyilishM
        holat.rmsM = georefY.rmsM
        guard georefY.natija != nil, georefY.juftSoni >= 20, georefY.yoyilishM >= 0.5 else { return }
        holat.boglangan = true
        if let lat = h.lat, let lon = h.lon,
           oxirgiYuklash.map({ Geodeziya.masofa(lat1: $0.lat, lon1: $0.lon, lat2: lat, lon2: lon) > 30 }) ?? true {
            oxirgiYuklash = (lat, lon)
            Task { await yukla(lat: lat, lon: lon) }
        }
        if georefY.juftSoni != chizilganJuft {  // georef har 10 juftda yangilanadi — sahna qayta joylanadi
            chizilganJuft = georefY.juftSoni
            chiz()
        }
    }

    // MARK: Shahar reestri (AR-02, K-09)

    private func yukla(lat: Double, lon: Double) async {
        holat.yuklash = "Atrofdagi tarmoqlar yuklanmoqda…"
        do {
            let m = try ServerMijoz(manzil: sozlama.serverManzil, token: sozlama.dalaToken)
            global = try await m.atrof(lat: lat, lon: lon, r: 80)
            AtrofKesh.saqla(global, lat: lat, lon: lon)
            holat.yuklash = nil
        } catch {
            if let k = AtrofKesh.oqi(lat: lat, lon: lon) {
                global = k.tarmoqlar
                holat.yuklash = "Oflayn: \(k.yoshi) yuklangan ma'lumot"
            } else {
                holat.yuklash = "Serverga ulanib bo'lmadi: \(error.localizedDescription)"
            }
        }
        holat.pudratchiSoni = Set(global.compactMap { $0.pudratchi }.filter { !$0.isEmpty }).count
        chiz()
    }

    /// Yer sirti balandligi (ARKit y): yuqoridan pastga nur; topilmasa — telefon balandligidan 1,4 m past (taxmin).
    private func yerBalandligi(_ x: Double, _ z: Double) -> Double? {
        guard let v = arView, let kam = v.session.currentFrame?.camera.transform.columns.3 else { return nil }
        let q = ARRaycastQuery(origin: SIMD3<Float>(Float(x), kam.y + 1, Float(z)), direction: SIMD3<Float>(0, -1, 0),
                               allowing: .estimatedPlane, alignment: .horizontal)
        if let r = v.session.raycast(q).first { return Double(r.worldTransform.columns.3.y) }
        return Double(kam.y) - 1.4
    }

    // MARK: Chizish (AR-04, AR-07)

    private func chiz() {
        guard let g = georefY.natija, let zona = georefY.zona else { return }
        ildiz.children.removeAll()
        tarmoqEntity = [:]
        yorliqlar = []
        let tarmoqlar = global.compactMap {
            ARJoylashuv.tarmoq($0, georef: g.transformatsiya, zona: zona, yerBalandligi: { [weak self] x, z in self?.yerBalandligi(x, z) })
        }
        holat.tarmoqlar = tarmoqlar
        for t in tarmoqlar where holat.korinadimi(t) {
            if let m = Mesh.naycha(t.oq.map(f3), radius: Float(t.radius)) {
                let e = ModelEntity(mesh: m, materials: [material(t, xavfli: false)])
                ildiz.addChild(e)
                tarmoqEntity[t.id] = e
            }
            let tur = TarmoqTuri.top(t.turi)
            // UI-12/13: yer yuzasida bo'yoq belgisiga o'xshash punktir va noaniqlik yo'lagi
            let sigma = Noaniqlik.liniyaSigma(sigmaHSm: t.sigmaHSm, sifat: t.sifat)
            let yarim = Noaniqlik.yarimKenglik(liniyaSigmaM: sigma.m, bogRmsM: holat.rmsM)
            let aniqlik = sigma.malum ? " · ±" + Format.son(yarim * 100, raqam: 0) + " sm" : " · aniqlik noma'lum"
            let yer = yerProyeksiyasi(t)
            if let m = Mesh.lenta(yer, yarimKenglik: Float(yarim), punktir: nil) {
                var mat = UnlitMaterial(color: tur.uiRang)
                mat.blending = .transparent(opacity: .init(floatLiteral: sigma.malum ? 0.2 : 0.12))
                ildiz.addChild(ModelEntity(mesh: m, materials: [mat]))
            }
            if let m = Mesh.lenta(yer.map { $0 + SIMD3<Float>(0, 0.004, 0) }, yarimKenglik: 0.025, punktir: (0.3, 0.2)) {
                ildiz.addChild(ModelEntity(mesh: m, materials: [UnlitMaterial(color: tur.uiRang)]))
            }
            for (k, q) in ARChizish.qoziqlar(t, oraliq: 2, yerBalandligi: { [weak self] x, z in self?.yerBalandligi(x, z) }).enumerated()
            where q.chuqurlikM > 0.05 {
                if let m = Mesh.naycha([f3(q.yer), f3(q.quvurUsti)], radius: 0.005, halqa: 6) {
                    ildiz.addChild(ModelEntity(mesh: m, materials: [UnlitMaterial(color: UIColor.white.withAlphaComponent(0.85))]))
                }
                if k % 3 == 0 {
                    let matn = "\(tur.nomi) Ø\(t.diametrMm) · \(Format.m(q.chuqurlikM))" + aniqlik + (t.sifat == "RASMIY" ? "" : " · \(t.sifat)")
                    let y = yorliq(matn, rang: tur.uiRang)
                    y.position = f3(q.yer) + SIMD3<Float>(0, 0.12, 0)
                    ildiz.addChild(y)
                    yorliqlar.append(y)
                }
            }
        }
        xavfYangila()
    }

    private func material(_ t: MahalliyTarmoq, xavfli: Bool) -> UnlitMaterial {
        var m = UnlitMaterial(color: xavfli ? UIColor.systemRed : TarmoqTuri.top(t.turi).uiRang)
        let shaffoflik: Float = t.sifat == "RASMIY" ? 0.92 : (t.sifat == "SKAN" ? 0.55 : 0.75)
        m.blending = .transparent(opacity: .init(floatLiteral: shaffoflik))
        return m
    }

    private func yorliq(_ matn: String, rang: UIColor) -> Entity {
        let mesh = MeshResource.generateText(matn, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.07, weight: .semibold),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping)
        let ichki = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: rang)])
        let b = mesh.bounds
        ichki.position = SIMD3<Float>(-b.center.x, -b.center.y, 0)
        let fon = ModelEntity(mesh: .generatePlane(width: b.extents.x + 0.04, height: b.extents.y + 0.03),
                              materials: [UnlitMaterial(color: UIColor.black.withAlphaComponent(0.6))])
        fon.position = SIMD3<Float>(0, 0, -0.002)
        let ota = Entity()
        ota.addChild(fon)
        ota.addChild(ichki)
        return ota
    }

    /// Yorliqlar doim kameraga qarab turadi (iOS 17 da billboard yo'q).
    private func yorliqlarniBur(_ T: simd_float4x4) {
        let kam = SIMD3<Float>(T.columns.3.x, T.columns.3.y, T.columns.3.z)
        for y in yorliqlar {
            let p = y.position(relativeTo: nil)
            y.look(at: 2 * p - kam, from: p, relativeTo: nil)
        }
    }

    // MARK: Nishon (AR-05)

    private func nishonYangila(_ f: ARFrame) {
        guard holat.boglangan, !holat.tarmoqlar.isEmpty, let v = arView else { holat.nishon = nil; return }
        let markaz = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
        guard let r = v.raycast(from: markaz, allowing: .estimatedPlane, alignment: .horizontal).first else { holat.nishon = nil; return }
        let T = f.camera.transform
        let oldi = Vektor3(Double(-T.columns.2.x), 0, Double(-T.columns.2.z))
        holat.nishon = Nishon.top(yerNuqtasi: vektor(r.worldTransform.columns.3), kameraOldi: oldi, tarmoqlar: holat.tarmoqlar)
    }

    // MARK: Virtual chuqur (AR-03)

    private func chuqurQur(_ p: Vektor3) {
        chuqurIldiz.children.removeAll()
        let tub = ARChizish.chuqurTubi(markaz: p, olcham: 1.0, tarmoqlar: holat.tarmoqlar)
        if let m = Mesh.chuqur(markaz: f3(p), olcham: 1.0, tubY: Float(tub)) {
            var mat = UnlitMaterial(color: UIColor(red: 0.32, green: 0.23, blue: 0.15, alpha: 1))
            mat.blending = .transparent(opacity: .init(floatLiteral: 0.82))
            chuqurIldiz.addChild(ModelEntity(mesh: m, materials: [mat]))
        }
        // har 0,5 m da chuqurlik chizig'i
        var d = 0.5
        while p.y - d > tub {
            let y = Float(p.y - d)
            let c = f3(p)
            let burchaklar = [SIMD3<Float>(c.x - 0.5, y, c.z - 0.5), SIMD3<Float>(c.x + 0.5, y, c.z - 0.5),
                              SIMD3<Float>(c.x + 0.5, y, c.z + 0.5), SIMD3<Float>(c.x - 0.5, y, c.z + 0.5), SIMD3<Float>(c.x - 0.5, y, c.z - 0.5)]
            if let m = Mesh.naycha(burchaklar, radius: 0.003, halqa: 4) {
                chuqurIldiz.addChild(ModelEntity(mesh: m, materials: [UnlitMaterial(color: UIColor.white.withAlphaComponent(0.6))]))
            }
            d += 0.5
        }
        holat.xabar = "Virtual chuqur 1×1 m, tubi \(Format.m(p.y - tub)) — ichidagi quvurlarni yon tomondan ko'ring"
    }

    // MARK: Xavf zonasi (AR-06)

    private func xavfYangila() {
        xavfIldiz.children.removeAll()
        for p in poligon {
            let e = ModelEntity(mesh: .generateSphere(radius: 0.03), materials: [UnlitMaterial(color: .systemRed)])
            e.position = f3(p)
            xavfIldiz.addChild(e)
        }
        if poligon.count >= 2 {
            let yopiq = poligon.count >= 3 ? poligon + [poligon[0]] : poligon
            if let m = Mesh.naycha(yopiq.map(f3), radius: 0.01, halqa: 6) {
                xavfIldiz.addChild(ModelEntity(mesh: m, materials: [UnlitMaterial(color: .systemRed)]))
            }
        }
        let n = QazishXavfi.tekshir(poligon: poligon, tarmoqlar: holat.tarmoqlar)
        holat.xavf = n
        let xavfli = Set(n.map { $0.tarmoqId })
        for t in holat.tarmoqlar {
            tarmoqEntity[t.id]?.model?.materials = [material(t, xavfli: xavfli.contains(t.id))]
        }
    }

    func xavfTozala() {
        poligon = []
        holat.poligonSoni = 0
        xavfYangila()
    }

    func chuqurTozala() { chuqurIldiz.children.removeAll() }

    /// Quvur o'qining yer yuzasidagi izi: har 0,25 m da yer balandligi (topilmagan joy tashlanadi), +1 sm yuqorida.
    private func yerProyeksiyasi(_ t: MahalliyTarmoq) -> [SIMD3<Float>] {
        var natija: [SIMD3<Float>] = []
        for i in 1..<t.oq.count {
            let a = t.oq[i - 1], b = t.oq[i]
            let L = ((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot()
            let n = max(1, Int(L / 0.25))
            for k in (i == 1 ? 0 : 1)...n {
                let q = a + (b - a) * (Double(k) / Double(n))
                if let y = yerBalandligi(q.x, q.z) { natija.append(SIMD3<Float>(Float(q.x), Float(y) + 0.01, Float(q.z))) }
            }
        }
        return natija
    }

    // MARK: Yordamchilar

    private func vektor(_ c: SIMD4<Float>) -> Vektor3 { Vektor3(Double(c.x), Double(c.y), Double(c.z)) }
    private func f3(_ v: Vektor3) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z)) }
}

/// Oxirgi yuklangan atrof — internet yo'q joyda (200 m ichida) ishlatiladi.
enum AtrofKesh {
    struct Yozuv: Codable {
        var lat: Double
        var lon: Double
        var vaqt: Date
        var tarmoqlar: [GlobalTarmoq]
    }

    private static var fayl: URL { Papkalar.ichki.appendingPathComponent("atrof_kesh.json") }

    static func saqla(_ t: [GlobalTarmoq], lat: Double, lon: Double) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let d = try? e.encode(Yozuv(lat: lat, lon: lon, vaqt: Date(), tarmoqlar: t)) {
            try? d.write(to: fayl, options: [.atomic, .completeFileProtection])
        }
    }

    static func oqi(lat: Double, lon: Double) -> (tarmoqlar: [GlobalTarmoq], yoshi: String)? {
        let dek = JSONDecoder(); dek.dateDecodingStrategy = .iso8601
        guard let d = try? Data(contentsOf: fayl), let y = try? dek.decode(Yozuv.self, from: d),
              Geodeziya.masofa(lat1: y.lat, lon1: y.lon, lat2: lat, lon2: lon) <= 200 else { return nil }
        let daq = Int(Date().timeIntervalSince(y.vaqt) / 60)
        return (y.tarmoqlar, daq < 60 ? "\(daq) daqiqa oldin" : "\(daq / 60) soat oldin")
    }
}

extension Mesh {
    /// Virtual chuqur: 4 devor va tub, ikki tomonlama (ichidan va tashqaridan ko'rinadi).
    static func chuqur(markaz c: SIMD3<Float>, olcham: Float, tubY: Float) -> MeshResource? {
        let h = olcham / 2
        let yer = c.y
        let b: [SIMD3<Float>] = [[c.x - h, yer, c.z - h], [c.x + h, yer, c.z - h], [c.x + h, yer, c.z + h], [c.x - h, yer, c.z + h]]
        var pos: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        func tortburchak(_ p: [SIMD3<Float>]) {
            let a = UInt32(pos.count)
            pos += p
            idx += [a, a + 1, a + 2, a, a + 2, a + 3,  a, a + 2, a + 1, a, a + 3, a + 2]
        }
        for i in 0..<4 {
            let p = b[i], q = b[(i + 1) % 4]
            tortburchak([p, q, SIMD3(q.x, tubY, q.z), SIMD3(p.x, tubY, p.z)])
        }
        tortburchak(b.map { SIMD3($0.x, tubY, $0.z) })
        var d = MeshDescriptor(name: "chuqur")
        d.positions = MeshBuffers.Positions(pos)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }
}
