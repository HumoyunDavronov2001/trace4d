import ARKit
import AVFoundation
import UIKit
import CoreImage
import ImageIO
import Foundation
import Observation
import RealityKit
import YerostiDrayver
import YerostiGeometriya
import YerostiHUD
import YerostiMuhr
import YerostiQaytaHisob
import YerostiTahlil

/// Skan ekrani ko'radigan holat.
@MainActor @Observable
final class SkanHolati {
    enum Asbob { case yoq, arNuqta, quvur }

    var yozilmoqda = false
    var boshlanganVaqt: Date?
    var kadrSoni = 0
    var rasmiyKadr = 0
    var masofaM = 0.0
    var meshMaydoniM2 = 0.0
    var kuzatuv: Kuzatuv = .normal
    var asbob: Asbob = .yoq
    var meshKorinadi = true
    var fonar = false
    var tahlil: String?
    var oxirgiQuvur: TopilganQuvur?
    var belgiSoni = 0
    var georefRmsM: Double?
    var georefJuft = 0
    var xabar: String?
    var tugadi: SkanYozuvi?
    var lidarBor = true
    /// UI-09: haptika tetiklari — quvur topilganda va jiddiy xatoda o'sadi.
    var quvurTopildi = 0
    var xatoHisob = 0
}

/// Kadr metama'lumoti — kadrlar.jsonl va muhr jurnaliga yoziladi.
struct KadrMeta: Codable {
    var i: Int
    var t: Double
    var fayl: String
    var jpeg: String?
    var kamera: [Float]      // 4×4, ustun bo'yicha
    var ichki: [Float]       // 3×3 kamera ichki parametrlari
    var olcham: [Int]
    var rtk: RTKSnapshot?
    var sifat: String
}

struct RTKSnapshot: Codable {
    var lat: Double
    var lon: Double
    var h: Double?
    var rtk: String
    var sigmaH: Double?
    var sigmaV: Double?
    var tuzatmaYoshi: Double?
}

/// ARKit LiDAR skan dvigateli: jonli mesh qoplamasi (qamrov), kalit kadrlar, RTK juftlari (georeferens),
/// muhr jurnali (K-05), quvurni avtomatik aniqlash (K-01…K-04).
@MainActor
final class SkanDvigateli: NSObject, ARSessionDelegate, ARDvigatel {
    let holat = SkanHolati()
    let loyiha: Loyiha
    let skanId = UUID()
    let papka: URL
    private let rtk: RTKBoshqaruv
    private let sozlama: Sozlamalar
    private weak var arView: ARView?

    private let meshIldiz = AnchorEntity(world: .zero)
    private let belgiIldiz = AnchorEntity(world: .zero)
    private var meshEntity: [UUID: ModelEntity] = [:]
    private var meshYangilangan: [UUID: TimeInterval] = [:]
    private var meshMaydon: [UUID: Double] = [:]

    private var muhr: MuhrYozuvchi?
    private var kadrlarJSONL: FileHandle?
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private var kodlanmoqda = false
    private var oxirgiKadrT: simd_float4x4?
    private var oxirgiKadrVaqt: TimeInterval = 0
    private var oxirgiPoz: SIMD3<Float>?
    private let georefY: GeorefYiguvchi
    /// UI-08: 0…3 (`ProcessInfo.ThermalState`). Qizisa mesh qoplamasi siyrakroq yangilanadi.
    var termal = 0
    /// DS-03: poza izi buferi (1 s lik to'plam bilan muhrlanadi).
    private var izBufer: [PozaNamuna] = []
    /// DS-06: zich bulut fon oqimida; navbat 3 kadrdan oshsa yangi kadr tashlanadi (asosiy oqim to'xtamasin).
    private let zich = ZichYiguvchi()
    private var zichVazifalar: [Task<Void, Never>] = []
    private var zichNavbat = 0
    private var chuqurlikI = 0
    private var oxirgiChuqurlikVaqt: TimeInterval = 0
    private var oxirgiChuqurlikT: simd_float4x4?
    /// Yakunlashda fon kadrlari tugaguncha muhr hali ochiq.
    private var yakunlanmoqda = false

    init(loyiha: Loyiha, rtk: RTKBoshqaruv, sozlama: Sozlamalar) {
        self.loyiha = loyiha
        self.rtk = rtk
        self.sozlama = sozlama
        georefY = GeorefYiguvchi(sozlama: sozlama)
        papka = Papkalar.skan(loyiha, skanId)
        super.init()
    }

    // MARK: ARView ulash

    func ulan(_ v: ARView) {
        arView = v
        v.session.delegate = self
        v.scene.addAnchor(meshIldiz)
        v.scene.addAnchor(belgiIldiz)
        let c = ARWorldTrackingConfiguration()
        c.worldAlignment = .gravity
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            c.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            c.sceneReconstruction = .mesh
        } else {
            holat.lidarBor = false
            holat.xabar = "Bu qurilmada LiDAR yo'q — iPhone Pro/Pro Max kerak"
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { c.frameSemantics.insert(.sceneDepth) }
        c.environmentTexturing = .none
        v.session.run(c, options: [.resetTracking, .removeExistingAnchors])
        rtk.epoxaKeldi = { [weak self] h, t in self?.epoxa(h, t) }
        rtk.satrKeldi = { [weak self] s, te in
            guard let self, self.holat.yozilmoqda else { return }
            self.muhr?.yoz(.nmea, matn: s)
            // DS-03: GGA satri telefonga kelgan vaqt — server kechikishni xom ma'lumotdan baholaydi (DS-04)
            if s.count > 6, s.dropFirst(3).hasPrefix("GGA") { self.muhr?.yoz(.nuqta, json: NMEAVaqtYozuvi(te: te)) }
        }
        rtk.tuzatmaKeldi = { [weak self] d in
            guard let self, self.holat.yozilmoqda else { return }
            self.muhr?.yoz(.rtcm, matn: Xesh.hex(d) + " \(d.count)")
        }
    }

    func toxtat() {
        rtk.epoxaKeldi = nil; rtk.satrKeldi = nil; rtk.tuzatmaKeldi = nil
        arView?.session.pause()
        if holat.fonar { fonar(false) }
    }

    /// UI-07: yozishni bekor qilish — jurnal yopiladi va skan papkasi o'chiriladi (serverga hech narsa ketmagan).
    func bekorQil() {
        holat.yozilmoqda = false
        holat.boshlanganVaqt = nil
        muhr?.yop()
        muhr = nil
        try? kadrlarJSONL?.close()
        kadrlarJSONL = nil
        try? FileManager.default.removeItem(at: papka)
    }

    // MARK: Yozish

    func yozishniBoshla() {
        guard !holat.yozilmoqda else { return }
        do {
            muhr = try MuhrYozuvchi(papka: papka)
            let kadrlar = papka.appendingPathComponent("kadrlar", isDirectory: true)
            try FileManager.default.createDirectory(at: kadrlar, withIntermediateDirectories: true)
            let j = papka.appendingPathComponent("kadrlar.jsonl")
            FileManager.default.createFile(atPath: j.path, contents: nil)
            kadrlarJSONL = try FileHandle(forWritingTo: j)
        } catch {
            holat.xabar = "Skan papkasi yaratilmadi: \(error.localizedDescription)"
            holat.xatoHisob += 1
            return
        }
        muhr?.yoz(.izoh, json: [
            "loyiha": loyiha.nomi, "order": loyiha.orderRaqami, "order_sana": loyiha.orderSana ?? "", "tarmoq": loyiha.tarmoqTuri,
            "qurilma": UIDevice.current.model + " " + Qurilma.model, "rtk": rtk.qurilmaSeriya ?? "",
            "boshlandi": ISO8601DateFormatter().string(from: Date()), "yadro": YadroVersiya.matn,
        ])
        // DS-02: qurilma va dastak profili — antenna ofseti va kechikish qayerdan olingani muhrlanadi
        muhr?.yoz(.izoh, json: ProfilYozuvi(
            qabulQilgich: rtk.moslik?.model.rawValue ?? rtk.qurilmaNomi ?? "noma'lum", seriya: rtk.qurilmaSeriya,
            iphone: Qurilma.model, dastak: sozlama.dastak, tomon: sozlama.dastakTomoni,
            antennaOfset: sozlama.antennaOfset.count == 3 ? sozlama.antennaOfset : [0, 0, 0],
            kechikishS: sozlama.rtkKechikishS, manba: sozlama.ofsetManba))
        holat.yozilmoqda = true
        holat.boshlanganVaqt = Date()
    }

    // MARK: ARSessionDelegate (asosiy oqimda chaqiriladi)

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated { self.kadr(frame) }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        MainActor.assumeIsolated { self.meshYangila(anchors, majburiy: true) }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        MainActor.assumeIsolated { self.meshYangila(anchors, majburiy: false) }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        MainActor.assumeIsolated {
            for a in anchors { self.meshEntity.removeValue(forKey: a.identifier)?.removeFromParent(); self.meshMaydon[a.identifier] = nil }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated { self.holat.xabar = "AR sessiya xatosi: \(error.localizedDescription)" }
    }

    private func kadr(_ f: ARFrame) {
        let T = f.camera.transform
        georefY.poza(f.timestamp, T)

        let k = Kuzatuv(f.camera.trackingState)
        if holat.kuzatuv != k { holat.kuzatuv = k }

        guard holat.yozilmoqda, case .normal = f.camera.trackingState else { return }
        // DS-03: poza izi — har kadr (60 Hz), 1 s lik to'plam bilan muhrlanadi
        let kq = simd_quatf(T)
        izBufer.append(PozaNamuna(t: f.timestamp, p: Vektor3(Double(T.columns.3.x), Double(T.columns.3.y), Double(T.columns.3.z)),
                                  q: Kvaternion(Double(kq.imag.x), Double(kq.imag.y), Double(kq.imag.z), Double(kq.real))))
        if izBufer.count >= 60 {
            muhr?.yoz(.kadr, json: IzYozuvi(izBufer))
            izBufer.removeAll(keepingCapacity: true)
        }
        if sozlama.zichBulut { chuqurlikOl(f, T) }
        let p = SIMD3<Float>(T.columns.3.x, T.columns.3.y, T.columns.3.z)
        if let o = oxirgiPoz {
            let d = simd_distance(p, o)
            if d > 0.01 { holat.masofaM += Double(d); oxirgiPoz = p }
        } else { oxirgiPoz = p }

        guard !kodlanmoqda, f.timestamp - oxirgiKadrVaqt >= 0.25 else { return }
        if let o = oxirgiKadrT {
            let siljish = simd_distance(p, SIMD3(o.columns.3.x, o.columns.3.y, o.columns.3.z))
            let q1 = simd_quatf(T), q0 = simd_quatf(o)
            let burchak = 2 * acos(min(1, abs(simd_dot(q1.vector, q0.vector))))
            guard siljish >= 0.10 || burchak >= 8 * .pi / 180 else { return }
        }
        kadrOl(f, T)
    }

    /// DS-06/07: chuqurlik kadri ≤ 5 Hz va faqat telefon siljiganda (≥ 2 sm yoki ≥ 2°); rang shu kadrning tasviridan.
    private func chuqurlikOl(_ f: ARFrame, _ T: simd_float4x4) {
        guard f.timestamp - oxirgiChuqurlikVaqt >= 0.2, zichNavbat < 3 else { return }
        if let o = oxirgiChuqurlikT {
            let siljish = simd_distance(SIMD3(T.columns.3.x, T.columns.3.y, T.columns.3.z), SIMD3(o.columns.3.x, o.columns.3.y, o.columns.3.z))
            let burchak = 2 * acos(min(1, abs(simd_dot(simd_quatf(T).vector, simd_quatf(o).vector))))
            guard siljish >= 0.02 || burchak >= 2 * .pi / 180 else { return }
        }
        guard let (k, sha) = ChuqurlikOlish.kadr(f) else { return }
        oxirgiChuqurlikVaqt = f.timestamp
        oxirgiChuqurlikT = T
        let i = chuqurlikI
        chuqurlikI += 1
        zichNavbat += 1
        let z = zich
        zichVazifalar.append(Task { [weak self] in
            let n = await z.qosh(k)
            await MainActor.run {
                guard let self else { return }
                self.zichNavbat -= 1
                if self.holat.yozilmoqda || self.yakunlanmoqda {
                    self.muhr?.yoz(.kadr, json: ChuqurlikYozuvi(i: i, t: k.t, n: n, sha256: sha))
                }
            }
        })
    }

    private func rtkSnapshot() -> RTKSnapshot? {
        let h = rtk.holat
        guard rtk.ulangan, let lat = h.lat, let lon = h.lon, !h.eskirganmi() else { return nil }
        return RTKSnapshot(lat: lat, lon: lon, h: h.balandlikEllipsoid, rtk: h.rtk.rawValue, sigmaH: h.sigmaHSm,
                           sigmaV: h.sigmaVSm, tuzatmaYoshi: h.tuzatmaYoshiS)
    }

    private func kadrOl(_ f: ARFrame, _ T: simd_float4x4) {
        let i = holat.kadrSoni
        let nomi = String(format: "kadr_%05d.jpg", i)
        let url = papka.appendingPathComponent("kadrlar/\(nomi)")
        let snap = rtkSnapshot()
        let sifat = snap == nil ? "YOQ" : rtk.sifat.rawValue
        let K = f.camera.intrinsics
        let meta = KadrMeta(
            i: i, t: f.timestamp, fayl: nomi, jpeg: nil,
            kamera: [T.columns.0, T.columns.1, T.columns.2, T.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] },
            ichki: [K.columns.0, K.columns.1, K.columns.2].flatMap { [$0.x, $0.y, $0.z] },
            olcham: [Int(f.camera.imageResolution.width), Int(f.camera.imageResolution.height)],
            rtk: snap, sifat: sifat)
        oxirgiKadrT = T
        oxirgiKadrVaqt = f.timestamp
        kodlanmoqda = true
        let pb = f.capturedImage
        let ctx = ci
        Task.detached(priority: .userInitiated) {
            let rasm = CIImage(cvPixelBuffer: pb)
            let jpeg = ctx.jpegRepresentation(of: rasm, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8])
            try? jpeg?.write(to: url, options: .atomic)
            let sha = jpeg.map { Xesh.hex($0) }
            await MainActor.run {
                var m = meta
                m.jpeg = sha
                self.kadrSaqlandi(m)
            }
        }
    }

    private func kadrSaqlandi(_ meta: KadrMeta) {
        kodlanmoqda = false
        guard holat.yozilmoqda else { return }
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        if let d = try? e.encode(meta) {
            muhr?.yoz(.kadr, d)
            try? kadrlarJSONL?.write(contentsOf: d + Data("\n".utf8))
        }
        holat.kadrSoni += 1
        if meta.sifat == Sifat.rasmiy.rawValue { holat.rasmiyKadr += 1 }
    }

    // MARK: Georeferens juftlari (Pix4D usuli: har epoxada antenna pozasi ↔ RTK)

    private func epoxa(_ h: QabulQilgichHolati, _ uptime: TimeInterval) {
        guard holat.yozilmoqda, georefY.epoxa(h, uptime) else { return }
        // DM-02: har juft muhrlanadi — data markaz uni xom NMEA bilan solishtiradi va georeferensni qayta hisoblaydi
        if let j = georefY.oxirgiJuft { muhr?.yoz(.nuqta, json: j) }
        holat.georefJuft = georefY.juftSoni
        holat.georefRmsM = georefY.rmsM
    }

    // MARK: Mesh qoplamasi (qamrov)

    private static let meshMaterial: UnlitMaterial = {
        var m = UnlitMaterial(color: UIColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.28))
        return m
    }()

    private func meshYangila(_ anchors: [ARAnchor], majburiy: Bool) {
        let hozir = ProcessInfo.processInfo.systemUptime
        for case let a as ARMeshAnchor in anchors {
            if !majburiy, hozir - (meshYangilangan[a.identifier] ?? 0) < (termal >= 2 ? 1.5 : 0.6) { continue }
            meshYangilangan[a.identifier] = hozir
            guard let natija = Mesh.resurs(a.geometry) else { continue }
            let (resurs, maydon) = natija
            meshMaydon[a.identifier] = maydon
            if let e = meshEntity[a.identifier] {
                e.model?.mesh = resurs
                e.transform = Transform(matrix: a.transform)
            } else {
                let e = ModelEntity(mesh: resurs, materials: [SkanDvigateli.meshMaterial])
                e.transform = Transform(matrix: a.transform)
                meshIldiz.addChild(e)
                meshEntity[a.identifier] = e
            }
        }
        holat.meshMaydoniM2 = meshMaydon.values.reduce(0, +)
    }

    func meshKorsat(_ ha: Bool) { holat.meshKorinadi = ha; meshIldiz.isEnabled = ha }

    func fonar(_ yoq: Bool) {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch else { return }
        try? d.lockForConfiguration()
        d.torchMode = yoq ? .on : .off
        d.unlockForConfiguration()
        holat.fonar = yoq
    }

    // MARK: Ekranga bosish: AR nuqta yoki quvur (urug' nuqta)

    func bosildi(_ nuqta: CGPoint) {
        guard let v = arView, holat.asbob != .yoq else { return }
        guard let r = v.raycast(from: nuqta, allowing: .estimatedPlane, alignment: .any).first else {
            holat.xabar = "Sirt topilmadi — kamerani sirtga yaqinroq tuting"; return
        }
        let p = SIMD3<Float>(r.worldTransform.columns.3.x, r.worldTransform.columns.3.y, r.worldTransform.columns.3.z)
        switch holat.asbob {
        case .arNuqta:
            let e = ModelEntity(mesh: .generateSphere(radius: 0.02), materials: [UnlitMaterial(color: .systemYellow)])
            e.position = p
            belgiIldiz.addChild(e)
            holat.belgiSoni += 1
            muhr?.yoz(.belgi, json: ["tur": "nuqta", "n": "\(holat.belgiSoni)", "x": "\(p.x)", "y": "\(p.y)", "z": "\(p.z)"])
        case .quvur:
            quvurniTop(urug: Vektor3(Double(p.x), Double(p.y), Double(p.z)))
        case .yoq:
            break
        }
    }

    /// K-01: operator bosgan joy atrofidagi mesh nuqtalaridan quvurni qurilmaning o'zida topish.
    func quvurniTop(urug: Vektor3?) {
        guard let v = arView, let kadr = v.session.currentFrame else { return }
        let meshlar = kadr.anchors.compactMap { $0 as? ARMeshAnchor }
        let markaz = urug.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
        let nuqtalar = Mesh.nuqtalar(meshlar, markaz: markaz, radius: 1.6)
        guard nuqtalar.count > 200 else { holat.xabar = "Bu joyda mesh yetarli emas — quvur ustidan sekin o'ting"; return }
        holat.tahlil = "Quvur aniqlanmoqda…"
        var qs = QuvurTopishSozlamalari()
        qs.tarmoqTuri = loyiha.tarmoqTuri
        let sozlamalar = qs
        Task.detached(priority: .userInitiated) {
            let natija = QuvurTopish(sozlamalar).topish(nuqtalar, urugNuqta: urug)
            await MainActor.run {
                self.holat.tahlil = nil
                guard let q = natija.first else {
                    self.holat.xabar = "Quvur topilmadi — aniqroq bosing yoki qo'lda belgilang"
                    return
                }
                self.holat.oxirgiQuvur = q
                self.holat.quvurTopildi += 1
                self.quvurChiz(q)
                self.muhr?.yoz(.belgi, json: QuvurYozuvi(q))
            }
        }
    }

    private func quvurChiz(_ q: TopilganQuvur) {
        let rang = TarmoqTuri.top(loyiha.tarmoqTuri).uiRang
        guard let m = Mesh.naycha(q.oq.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }, radius: Float(q.radius) + 0.004) else { return }
        var mat = UnlitMaterial(color: rang)
        mat.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        belgiIldiz.addChild(ModelEntity(mesh: m, materials: [mat]))
    }

    // MARK: Tugatish

    func tugat() async {
        guard holat.yozilmoqda, let muhr else { return }
        holat.yozilmoqda = false
        yakunlanmoqda = true
        holat.tahlil = "Skan yakunlanmoqda…"
        if !izBufer.isEmpty { muhr.yoz(.kadr, json: IzYozuvi(izBufer)); izBufer.removeAll() }
        for v in zichVazifalar { await v.value }
        zichVazifalar.removeAll()
        let meshlar = arView?.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        let nuqtalar = Mesh.nuqtalar(meshlar, markaz: nil, radius: .infinity)
        let plyURL = papka.appendingPathComponent("mesh.ply")
        let ply = PLY.yoz(nuqtalar, izoh: "TRACE4D ARKit mahalliy ramka (y yuqori)")
        try? ply.write(to: plyURL, options: .atomic)
        muhr.yoz(.fayl, json: ["nomi": "mesh.ply", "sha256": Xesh.hex(ply), "hajm": "\(ply.count)"])

        // DS-06/07: zich rangli bulut (chuqurlik kadrlaridan) — quvur shundan topiladi; mesh faqat jonli qamrov uchun edi
        var quvurBulut = nuqtalar
        var plyNomi = "mesh.ply"
        if sozlama.zichBulut {
            holat.tahlil = "Zich bulut yozilmoqda…"
            let zn = await zich.nuqtalar()
            if zn.count >= 2000 {
                let zp = PLY.yoz(zn, izoh: "TRACE4D zich bulut ARKit mahalliy ramka (y yuqori), rang va vaqt")
                try? zp.write(to: papka.appendingPathComponent("zich.ply"), options: .atomic)
                muhr.yoz(.fayl, json: ["nomi": "zich.ply", "sha256": Xesh.hex(zp), "hajm": "\(zp.count)"])
                // server PLY dagi float32 nuqtalar bilan ishlaydi — telefon ham aynan shu nuqtalardan topadi (DM-02: farq 0)
                quvurBulut = PLY.oqi(zp)?.nuqtalar ?? zn
                plyNomi = "zich.ply"
            }
        }

        holat.tahlil = "Quvurlar aniqlanmoqda…"
        var qs = QuvurTopishSozlamalari()
        qs.tarmoqTuri = loyiha.tarmoqTuri
        let sozlamalar = qs
        let bulut = quvurBulut
        let quvurlar = await Task.detached(priority: .userInitiated) { QuvurTopish(sozlamalar).topish(bulut) }.value
        for q in quvurlar { muhr.yoz(.belgi, json: QuvurYozuvi(q)) }
        if georefY.juftSoni >= 20 { georefY.hisobla() }
        let georef = georefY.natija
        let utmZona = georefY.zona
        if let g = georef { muhr.yoz(.izoh, json: GeorefYozuvi(g, zona: utmZona ?? 42)) }
        muhr.yop()
        yakunlanmoqda = false
        try? kadrlarJSONL?.close()

        // DS-04/05: muhrlangan jurnal bo'yicha telefonning o'zida qayta hisob (server bilan bir xil yadro):
        // kechikish, bo'lakli georeferens, quvur o'qlari WGS84 da — yuklashda liniya shulardan
        holat.tahlil = "Georeferens tekshirilmoqda…"
        let jURL = papka.appendingPathComponent("jurnal.ymj"), pURL = papka.appendingPathComponent(plyNomi)
        let nomi = plyNomi
        let xom = await Task.detached(priority: .userInitiated) { () -> XomSkanXulosa? in
            guard let jb = try? Data(contentsOf: jURL), let pb = try? Data(contentsOf: pURL, options: .mappedIfSafe) else { return nil }
            let (n, _) = QaytaHisob.tekshir(jurnal: [UInt8](jb), ply: [UInt8](pb))
            return XomSkanXulosa(n, plyNomi: nomi)
        }.value

        let yozuv = SkanYozuvi(
            id: skanId, papka: papka.path.replacingOccurrences(of: Papkalar.hujjatlar.path + "/", with: ""),
            boshlandi: holat.boshlanganVaqt ?? Date(), tugadi: Date(), kadrSoni: holat.kadrSoni, masofaM: holat.masofaM,
            meshMaydoniM2: holat.meshMaydoniM2,
            rasmiyKadrFoiz: holat.kadrSoni > 0 ? 100 * Double(holat.rasmiyKadr) / Double(holat.kadrSoni) : nil,
            yozuvSoni: muhr.zanjir.soni, zanjirBoshi: muhr.zanjir.boshHex,
            georef: georef.map { GeorefXulosa(burchak: $0.transformatsiya.burchak,
                                               t: [$0.transformatsiya.t.x, $0.transformatsiya.t.y, $0.transformatsiya.t.z],
                                               gorizontalRmsM: $0.gorizontalRmsM, vertikalRmsM: $0.vertikalRmsM,
                                               juftSoni: $0.soni, utmZona: utmZona ?? 42) },
            quvurlar: quvurlar.map { QuvurXulosa($0) }, xom: xom)
        holat.tahlil = nil
        holat.tugadi = yozuv
    }
}

extension QuvurXulosa {
    init(_ q: TopilganQuvur) {
        let profil = BoylamaProfil(q)
        self.init(tashqiDiametrMm: q.tashqiDiametrMm, standartMm: q.standart?.tashqiMm, seriya: q.standart?.seriya,
                  chuqurlikM: q.qoplamaChuqurligiM, qiyalikFoiz: q.qiyalikFoiz, uzunlikM: q.uzunlikM, ishonch: q.ishonch,
                  muftaSoni: q.muftalar.count, oqMahalliy: q.oq.map { [$0.x, $0.y, $0.z] },
                  profilOq: profil.oq, profilYer: profil.yer)
    }
}

extension XomSkanXulosa {
    /// Server natijasi bilan bir xil shakl; σ — bo'lak qoldig'i + LiDAR (1 sm / 1,5 sm), PAST bo'lak — 10 sm (T-103 da PAST).
    init(_ n: QaytaHisob.Natija, plyNomi: String) {
        let b = n.bolakli
        func bolak(_ t: Double) -> GeorefBolak? { b?.bolaklar.first { t >= $0.boshT - 1e-6 && t <= $0.oxirT + 1e-6 } }
        let q: [QuvurGeo] = n.quvurlar.compactMap { q in
            guard q.georefUsul == "bolakli", let w = q.oqWgs84, let vt = q.oqVaqt else { return nil }
            let past = q.oqPast ?? Array(repeating: true, count: w.count)
            var sh: [Double] = [], sv: [Double] = []
            for (k, t) in vt.enumerated() {
                if k < past.count, past[k] { sh.append(10); sv.append(10); continue }
                let bo = t >= 0 ? bolak(t) : nil
                sh.append(((bo?.rmsH ?? 0.03) * 100 * (bo?.rmsH ?? 0.03) * 100 + 1).squareRoot())
                sv.append(((bo?.rmsV ?? 0.03) * 100 * (bo?.rmsV ?? 0.03) * 100 + 2.25).squareRoot())
            }
            return QuvurGeo(tashqiDiametrMm: q.diametrMm, standartMm: q.standartMm, chuqurlikM: q.chuqurlikM, ishonch: q.ishonch,
                            wgs84: w, past: past, sigmaHSm: sh, sigmaVSm: sv)
        }
        self.init(plyNomi: plyNomi, kechikishMs: n.kechikish?.kechikishS.map { $0 * 1000 },
                  kechikishIshonchli: n.kechikish?.ishonchli ?? false, bolaklar: b?.bolaklar.count ?? 0,
                  pastBolaklar: b?.pastBolaklar ?? 0, maksTuzatishSm: b.map { $0.maksTuzatishM * 100 },
                  ofsetFarqSm: n.ofset?.profildanFarqM.map { $0 * 100 }, ogohlantirishlar: n.ogohlantirishlar, quvurlar: q)
    }
}

/// Muhrga yoziladigan quvur natijasi.
enum Qurilma {
    static var model: String {
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { p in String(decoding: p.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

/// ARMeshGeometry → RealityKit mesh, maydon va nuqta buluti; o'q bo'ylab naycha.
enum Mesh {
    private static func uch(_ s: ARGeometrySource, _ i: Int) -> SIMD3<Float> {
        let t = s.buffer.contents().advanced(by: s.offset + s.stride * i).assumingMemoryBound(to: (Float, Float, Float).self).pointee
        return SIMD3(t.0, t.1, t.2)
    }

    private static func indekslar(_ f: ARGeometryElement) -> [UInt32] {
        let n = f.count * f.indexCountPerPrimitive
        var idx = [UInt32](); idx.reserveCapacity(n)
        let p = f.buffer.contents()
        for i in 0..<n {
            let a = p.advanced(by: i * f.bytesPerIndex)
            idx.append(f.bytesPerIndex == 4 ? a.assumingMemoryBound(to: UInt32.self).pointee
                       : UInt32(a.assumingMemoryBound(to: UInt16.self).pointee))
        }
        return idx
    }

    static func resurs(_ g: ARMeshGeometry) -> (MeshResource, Double)? {
        let v = g.vertices
        guard v.count > 2, g.faces.count > 0 else { return nil }
        let pos = (0..<v.count).map { uch(v, $0) }
        let idx = indekslar(g.faces)
        var maydon = 0.0
        var k = 0
        while k + 2 < idx.count {
            let a = pos[Int(idx[k])], b = pos[Int(idx[k + 1])], c = pos[Int(idx[k + 2])]
            maydon += Double(simd_length(simd_cross(b - a, c - a))) / 2
            k += 3
        }
        var d = MeshDescriptor(name: "skan")
        d.positions = MeshBuffers.Positions(pos)
        d.primitives = .triangles(idx)
        guard let m = try? MeshResource.generate(from: [d]) else { return nil }
        return (m, maydon)
    }

    /// Mesh uchlari dunyo ramkasida, normallari bilan (quvur aniqlash va PLY uchun).
    static func nuqtalar(_ meshlar: [ARMeshAnchor], markaz: SIMD3<Float>?, radius: Float) -> [BulutNuqtasi] {
        var natija: [BulutNuqtasi] = []
        for a in meshlar {
            let g = a.geometry, T = a.transform
            for i in 0..<g.vertices.count {
                let p = uch(g.vertices, i), n = uch(g.normals, i)
                let w = T * SIMD4<Float>(p, 1)
                let w3 = SIMD3<Float>(w.x, w.y, w.z)
                if let m = markaz, simd_distance(w3, m) > radius { continue }
                let wn = T * SIMD4<Float>(n, 0)
                natija.append(BulutNuqtasi(Vektor3(Double(w.x), Double(w.y), Double(w.z)),
                                           n: Vektor3(Double(wn.x), Double(wn.y), Double(wn.z))))
            }
        }
        return natija
    }

    /// Polilinya bo'ylab naycha (quvurni AR da ko'rsatish).
    static func naycha(_ oq: [SIMD3<Float>], radius r: Float, halqa: Int = 20) -> MeshResource? {
        guard oq.count >= 2 else { return nil }
        var pos: [SIMD3<Float>] = [], nor: [SIMD3<Float>] = [], idx: [UInt32] = []
        for s in 1..<oq.count {
            let a = oq[s - 1], b = oq[s]
            let yo = simd_normalize(b - a)
            let yordam: SIMD3<Float> = abs(yo.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
            let e1 = simd_normalize(simd_cross(yo, yordam)), e2 = simd_cross(yo, e1)
            let asos = UInt32(pos.count)
            for uchi in [a, b] {
                for k in 0..<halqa {
                    let teta = Float(k) / Float(halqa) * 2 * .pi
                    let n = cos(teta) * e1 + sin(teta) * e2
                    pos.append(uchi + n * r); nor.append(n)
                }
            }
            for k in 0..<UInt32(halqa) {
                let k2 = (k + 1) % UInt32(halqa)
                let a0 = asos + k, a1 = asos + k2, b0 = asos + UInt32(halqa) + k, b1 = asos + UInt32(halqa) + k2
                idx += [a0, b0, a1, a1, b0, b1]
            }
        }
        var d = MeshDescriptor(name: "quvur")
        d.positions = MeshBuffers.Positions(pos)
        d.normals = MeshBuffers.Normals(nor)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }
}

extension Kuzatuv {
    /// ARKit kuzatuv holati → yo'riqnoma turi (UI-05). Matnlar yadroda (YoriqnomaTanlov).
    init(_ t: ARCamera.TrackingState) {
        switch t {
        case .normal: self = .normal
        case .notAvailable: self = .cheklangan
        case .limited(let s):
            switch s {
            case .excessiveMotion: self = .sekinroq
            case .insufficientFeatures: self = .teksturaKam
            case .initializing: self = .sozlanmoqda
            case .relocalizing: self = .qaytaAniqlash
            @unknown default: self = .cheklangan
            }
        }
    }
}
