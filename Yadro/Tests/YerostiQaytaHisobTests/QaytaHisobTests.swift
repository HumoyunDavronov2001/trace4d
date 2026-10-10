import Foundation
import XCTest
import YerostiDrayver
import YerostiGeometriya
import YerostiMuhr
import YerostiQaytaHisob
import YerostiTahlil

/// Telefon `SkanDvigateli` bilan bir xil tartibda muhr jurnali + mesh.ply yasaydi.
/// FAQAT SINOV GEOMETRIYASI — haqiqiy skan emas, mahsulot bazasiga kirmaydi.
struct SinovSkan {
    var jurnal: [UInt8] = MuhrZanjir.jurnalSarlavha
    var zanjir = MuhrZanjir()
    var ply = Data()
    var telefonQuvurlar: [TopilganQuvur] = []

    struct Buzish {
        var quvurSurish = Vektor3.nol
        var plyBuzish = false
        var soxtaJuft = false
        var floatJuft = false
        var georefSurish = Vektor3.nol
    }

    mutating func yoz(_ tur: YozuvTuri, _ d: [UInt8]) { jurnal += zanjir.qosh(tur, d) }
    mutating func yoz<T: Encodable>(_ tur: YozuvTuri, json: T) {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        yoz(tur, Array(try! e.encode(json)))
    }

    /// Haqiqiy transform: mahalliy ENU → UTM 42N (Jizzax atrofi).
    static let T = GorizontalTransformatsiya(burchak: 0.6, t: Vektor3(401_336.53, 4_441_252.38, 402.0))
    static let geoid = -30.0

    static func gga(_ vaqt: Double, lat: Double, lon: Double, h: Double, sifat: Int) -> String {
        func dm(_ v: Double, _ w: Int) -> String {
            let d = floor(abs(v)), m = (abs(v) - d) * 60
            return String(format: "%0\(w)d%010.7f", Int(d), m)
        }
        let s = Int(vaqt)
        let hms = String(format: "%02d%02d%05.2f", 10 + s / 3600, (s / 60) % 60, Double(s % 60) + vaqt - floor(vaqt))
        let tana = "GNGGA,\(hms),\(dm(lat, 2)),N,\(dm(lon, 3)),E,\(sifat),24,0.6,"
            + String(format: "%.4f", h - geoid) + ",M," + String(format: "%.3f", geoid) + ",M,1.0,0000"
        return NMEAGap.yasa(tana)
    }

    static func gst(_ vaqt: Double) -> String {
        let s = Int(vaqt)
        let hms = String(format: "%02d%02d%05.2f", 10 + s / 3600, (s / 60) % 60, Double(s % 60) + vaqt - floor(vaqt))
        return NMEAGap.yasa("GNGST,\(hms),0.012,0.010,0.008,45.0,0.009,0.009,0.015")
    }

    /// Transheya + DN160 (ARKit ramkasi, y yuqori) va telefonning yakuniy aniqlashi.
    static let sahna: (ply: Data, quvurlar: [TopilganQuvur]) = {
        var sahna = SinovSahna(urug: 5)
        let r = 0.08
        let tub: (Double) -> Double = { z in -1.85 + 0.01 * z }
        sahna.transheya(kenglik: 0.8, uzunlik: 3, tub: tub, yashirin: { x, _ in abs(x) < r })
        sahna.quvur(bosh: Vektor3(0, tub(0) + r, 0), yonalish: Vektor3(0, 0.01, 1), uzunlik: 3, radius: r)
        var qs = QuvurTopishSozlamalari()
        qs.tarmoqTuri = "suv"
        return (PLY.yoz(sahna.nuqtalar, izoh: "YEROSTI ARKit mahalliy ramka (y yuqori)"), QuvurTopish(qs).topish(sahna.nuqtalar))
    }()

    static func yasa(_ b: Buzish = .init()) -> SinovSkan {
        var s = SinovSkan()
        s.yoz(.izoh, json: ["loyiha": "sinov", "order": "", "tarmoq": "suv", "qurilma": "sinov", "rtk": "",
                            "boshlandi": "2026-09-27T10:00:00Z", "yadro": YadroVersiya.matn])

        // RTK epoxalari (10 Hz) va telefon qoidasi bo'yicha juftlar (GeorefYiguvchi.epoxa bilan bir xil)
        var rnd = Tasodifiy(urug: 99)
        var h = QabulQilgichHolati()
        var mahalliy: [Vektor3] = [], global: [Vektor3] = []
        for k in 0..<90 {
            let vaqt = Double(k) * 0.1
            let ar = Vektor3(0.6 + 0.3 * sin(Double(k) * 0.07), 1.3, -0.5 + Double(k) * 0.045)
            let enu = ARKitRamka.enu(ar)
            let g = T.qolla(enu) + Vektor3(rnd.normal(sigma: 0.006), rnd.normal(sigma: 0.006), rnd.normal(sigma: 0.01))
            let (lat, lon) = UTM.dan(UTMNuqta(zona: 42, shimoliy: true, x: g.x, y: g.y))
            let sifatKodi = (k % 15 == 7) ? 5 : 4
            let gSatr = gga(vaqt, lat: lat, lon: lon, h: g.z, sifat: sifatKodi)
            s.yoz(.nmea, Array(gSatr.utf8))
            let hozir = Date(timeIntervalSince1970: 1_000 + vaqt)
            h.qabul(try! NMEAXabar.ajrat(gSatr), hozir: hozir)
            let rasmiy = h.sifat(hozir: hozir) == .rasmiy
            if rasmiy || (b.floatJuft && sifatKodi == 5) {
                let gp = UTM.ga(lat: h.lat!, lon: h.lon!, zona: 42)
                let juft = JuftYozuvi(m: enu, g: Vektor3(gp.x, gp.y, h.balandlikEllipsoid!), zona: 42)
                s.yoz(.nuqta, json: juft)
                mahalliy.append(juft.mahalliy); global.append(juft.global)
            }
            let st = gst(vaqt + 0.05)
            s.yoz(.nmea, Array(st.utf8))
            h.qabul(try! NMEAXabar.ajrat(st), hozir: hozir.addingTimeInterval(0.05))
        }
        if b.soxtaJuft {
            let soxta = JuftYozuvi(m: Vektor3(0.2, -1.0, 1.3), g: T.qolla(Vektor3(0.2, -1.0, 1.3)) + Vektor3(0.05, 0, 0), zona: 42)
            s.yoz(.nuqta, json: soxta)
            mahalliy.append(soxta.mahalliy); global.append(soxta.global)
        }

        // Transheya + DN160: telefon yakunidagi tahlil (bir marta hisoblanadi, variantlar faqat jurnalda farqlanadi)
        s.telefonQuvurlar = sahna.quvurlar
        s.ply = sahna.ply
        s.yoz(.fayl, json: ["nomi": "mesh.ply", "sha256": SHA256.hex(SHA256.xesh(s.ply)), "hajm": "\(s.ply.count)"])
        for q in s.telefonQuvurlar {
            var y = QuvurYozuvi(q)
            y.oq = q.oq.map { [$0.x + b.quvurSurish.x, $0.y + b.quvurSurish.y, $0.z + b.quvurSurish.z] }
            s.yoz(.belgi, json: y)
        }
        if mahalliy.count >= 20, let g = try? Georeferens.gravitatsiyaBilan(mahalliyENU: mahalliy, global: global) {
            var y = GeorefYozuvi(g, zona: 42)
            y.t = [y.t[0] + b.georefSurish.x, y.t[1] + b.georefSurish.y, y.t[2] + b.georefSurish.z]
            s.yoz(.izoh, json: y)
        }
        if b.plyBuzish {
            var p = [UInt8](s.ply)
            p[p.count - 7] ^= 0x40
            s.ply = Data(p)
        }
        return s
    }
}

/// Transheya va quvur sirti (YerostiTahlilTests dagi sahnaning ixcham nusxasi — test maqsadlari farq qiladi).
struct SinovSahna {
    var nuqtalar: [BulutNuqtasi] = []
    var t: Tasodifiy
    let sigma = 0.004
    static let yuqori = Vektor3(0, 1, 0)

    init(urug: UInt64) { t = Tasodifiy(urug: urug) }

    mutating func qosh(_ p: Vektor3, _ n: Vektor3) {
        let q = p + Vektor3(t.normal(sigma: sigma), t.normal(sigma: sigma), t.normal(sigma: sigma))
        let nn = (n + Vektor3(t.normal(sigma: 0.05), t.normal(sigma: 0.05), t.normal(sigma: 0.05))).birlik
        nuqtalar.append(BulutNuqtasi(q, n: nn))
    }

    mutating func transheya(kenglik k: Double, uzunlik L: Double, tub: (Double) -> Double, qadam: Double = 0.025,
                            yashirin: (Double, Double) -> Bool) {
        for z in stride(from: 0.0, through: L, by: qadam) {
            for x in stride(from: -1.6, through: 1.6, by: qadam) where abs(x) > k / 2 { qosh(Vektor3(x, 0, z), Self.yuqori) }
            for y in stride(from: tub(z), through: 0, by: qadam) {
                qosh(Vektor3(-k / 2, y, z), Vektor3(1, 0, 0))
                qosh(Vektor3(k / 2, y, z), Vektor3(-1, 0, 0))
            }
            for x in stride(from: -k / 2 + qadam, to: k / 2, by: qadam) where !yashirin(x, z) {
                qosh(Vektor3(x, tub(z), z), Self.yuqori)
            }
        }
    }

    mutating func quvur(bosh: Vektor3, yonalish: Vektor3, uzunlik L: Double, radius r: Double, qadam: Double = 0.01) {
        let a = yonalish.birlik!
        let yon = a.kross(Self.yuqori).birlik!
        let yuq = yon.kross(a)
        for s in stride(from: 0.0, through: L, by: qadam) {
            for teta in stride(from: -100 * Double.pi / 180, through: 100 * Double.pi / 180, by: qadam / r) {
                let n = yon * sin(teta) + yuq * cos(teta)
                qosh(bosh + a * s + n * r, n)
            }
        }
    }
}

final class QaytaHisobTests: XCTestCase {
    static let asosiy = SinovSkan.yasa()

    func tekshir(_ s: SinovSkan) -> QaytaHisob.Natija {
        QaytaHisob.tekshir(jurnal: s.jurnal, ply: [UInt8](s.ply)).natija
    }

    func testTozaSkanMos() throws {
        let s = Self.asosiy
        XCTAssertEqual(s.telefonQuvurlar.count, 1, "sinov sahnasida telefon bitta quvur topishi kerak")
        let n = tekshir(s)
        XCTAssertEqual(n.xulosa, "MOS", "\(n.sabablar)")
        let j = try XCTUnwrap(n.jurnal)
        XCTAssertEqual(j.bosh, s.zanjir.boshHex)
        XCTAssertEqual(j.yozuvlar, s.zanjir.soni)
        XCTAssertTrue(j.plyMuhrlangan)
        XCTAssertEqual(j.tarmoq, "suv")
        XCTAssertGreaterThanOrEqual(j.juftlar, 20)
        XCTAssertLessThan(j.rasmiyEpoxalar, j.ggaEpoxalar, "FLOAT epoxalar ham bor")
        let g = try XCTUnwrap(n.georef)
        XCTAssertEqual(g.juftlarNmeadaTopildi, j.juftlar)
        XCTAssertEqual(g.juftlarRasmiy, j.juftlar)
        XCTAssertLessThan(try XCTUnwrap(g.siljishFarqiM), 1e-6)
        XCTAssertLessThan(try XCTUnwrap(g.burchakFarqiGrad), 1e-6)
        XCTAssertEqual(n.quvurlar.count, 1)
        let t = try XCTUnwrap(n.taqqos.first)
        XCTAssertTrue(t.mos)
        XCTAssertLessThan(try XCTUnwrap(t.oqFarqiM), 0.002, "bir xil yadro: float32 yaxlitlashdan boshqa farq bo'lmasligi kerak")
        // server o'z georeferensi bilan UTM/WGS84 beradi — haqiqiy transformdan ≤ 3 sm (RTK shovqini 6 mm, sinov)
        let q = n.quvurlar[0]
        let utm = try XCTUnwrap(q.oqUtm)
        let ilk = Vektor3(utm[0][0], utm[0][1], utm[0][2])
        let enu = Vektor3(q.oqEnu[0][0], q.oqEnu[0][1], q.oqEnu[0][2])
        XCTAssertLessThan((ilk - SinovSkan.T.qolla(enu)).uzunlik, 0.03)
        XCTAssertEqual(try XCTUnwrap(q.oqWgs84).count, utm.count)
    }

    func testSurilganQuvurFarq() throws {
        let n = tekshir(SinovSkan.yasa(.init(quvurSurish: Vektor3(0.05, 0, 0))))
        XCTAssertEqual(n.xulosa, "FARQ")
        let t = try XCTUnwrap(n.taqqos.first)
        XCTAssertFalse(t.mos)
        let oq = try XCTUnwrap(t.oqFarqiM)
        XCTAssertEqual(oq, 0.05, accuracy: 0.01, "o'q farqi surilgan masofani ko'rsatishi kerak")
        XCTAssertTrue(n.sabablar.contains { $0.contains("mos emas") }, "\(n.sabablar)")
    }

    func testBuzilganPLYFarq() {
        let n = tekshir(SinovSkan.yasa(.init(plyBuzish: true)))
        XCTAssertEqual(n.xulosa, "FARQ")
        XCTAssertEqual(n.jurnal?.plyMuhrlangan, false)
        XCTAssertTrue(n.sabablar.contains { $0.contains("PLY jurnalda muhrlangan fayl emas") }, "\(n.sabablar)")
    }

    func testNMEAdaYoqJuftFarq() {
        let n = tekshir(SinovSkan.yasa(.init(soxtaJuft: true)))
        XCTAssertEqual(n.xulosa, "FARQ")
        XCTAssertTrue(n.sabablar.contains { $0.contains("xom NMEA da topilmadi") }, "\(n.sabablar)")
    }

    func testFloatEpoxadanJuftFarq() {
        let n = tekshir(SinovSkan.yasa(.init(floatJuft: true)))
        XCTAssertEqual(n.xulosa, "FARQ")
        XCTAssertTrue(n.sabablar.contains { $0.contains("RASMIY bo'lmagan") }, "\(n.sabablar)")
    }

    func testSoxtaGeorefFarq() throws {
        let n = tekshir(SinovSkan.yasa(.init(georefSurish: Vektor3(0.03, 0, 0))))
        XCTAssertEqual(n.xulosa, "FARQ")
        XCTAssertEqual(try XCTUnwrap(n.georef?.siljishFarqiM), 0.03, accuracy: 1e-6)
    }

    func testKesilganJurnalXato() {
        var s = Self.asosiy
        s.jurnal.removeLast(3)
        let n = tekshir(s)
        XCTAssertEqual(n.xulosa, "XATO")
        XCTAssertTrue(n.sabablar.first?.contains("kesilgan") ?? false, "\(n.sabablar)")
        var b = Self.asosiy
        b.jurnal[0] = 0x58
        XCTAssertEqual(tekshir(b).xulosa, "XATO")
    }

    func testKorinishBulutiENUvaChek() throws {
        let s = Self.asosiy
        let (n, d) = QaytaHisob.tekshir(jurnal: s.jurnal, ply: [UInt8](s.ply), korinishMaks: 20_000)
        let k = try XCTUnwrap(n.korinish)
        XCTAssertLessThanOrEqual(k.nuqtalar, 20_000)
        let o = try XCTUnwrap(PLY.oqi(try XCTUnwrap(d)))
        XCTAssertEqual(o.nuqtalar.count, k.nuqtalar)
        // ENU: z yuqori — yer sirti z≈0, transheya tubi ≈ −1,85 m
        XCTAssertEqual(k.max[2], 0, accuracy: 0.03)
        XCTAssertEqual(k.min[2], -1.85, accuracy: 0.05)
    }

    func testJSONsnakeCase() throws {
        let n = tekshir(Self.asosiy)
        let j = try JSONSerialization.jsonObject(with: try QaytaHisob.json(n)) as? [String: Any]
        XCTAssertEqual(j?["xulosa"] as? String, "MOS")
        XCTAssertNotNil(j?["vaqt_s"])
        XCTAssertNotNil((j?["georef"] as? [String: Any])?["juftlar_nmeada_topildi"])
    }

    /// Server sinovlari uchun to'plam (FAQAT sinov geometriyasi): SINOV_TOPLAM=<papka> swift test --filter ToplamniYoz
    func testToplamniYoz() throws {
        guard let papka = ProcessInfo.processInfo.environment["SINOV_TOPLAM"] else { throw XCTSkip("SINOV_TOPLAM berilmagan") }
        let u = URL(fileURLWithPath: papka, isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        let mos = Self.asosiy
        try Data(mos.jurnal).write(to: u.appendingPathComponent("jurnal.ymj"))
        try mos.ply.write(to: u.appendingPathComponent("mesh.ply"))
        let farq = SinovSkan.yasa(.init(quvurSurish: Vektor3(0.05, 0, 0)))
        XCTAssertEqual(farq.ply, mos.ply)
        try Data(farq.jurnal).write(to: u.appendingPathComponent("jurnal_surilgan.ymj"))
    }
}
