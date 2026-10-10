import Foundation
import XCTest
import YerostiDrayver
import YerostiGeometriya
import YerostiMuhr
import YerostiQaytaHisob
import YerostiSimulyatsiya
import YerostiTahlil

/// DS-03…DS-06 uchma-uch: telefon yozadigan xom jurnal (poza izi, GGA kelish vaqti, profil, vaqtli zich bulut) →
/// server mustaqil qayta hisobi. FAQAT SUN'IY ma'lumot (DalaSimulyatsiya), haqiqiy skan emas.
final class XomTests: XCTestCase {
    struct Natija { var jurnal: [UInt8]; var ply: Data; var sim: DalaSimulyatsiya; var haqiqiyOq: (Double) -> Vektor3 }

    /// 30 m transheya, Ø110 quvur tubida; ARKit suzishi 1 %, kechikish 120 ms. `zichVaqtsiz` — eski usul (vaqtsiz bulut).
    static func yasa(suzish: Double = 0.01, kechikish: Double = 0.120, zichVaqtsiz: Bool = false, profil: Bool = true,
                     profilOfset: [Double]? = nil) -> Natija {
        var s = DalaSimulyatsiya.Sozlama()
        s.suzishMasshtab = suzish
        s.suzishYawGrad30m = suzish > 0 ? 0.5 : 0
        s.suzishVertikal = suzish > 0 ? 0.003 : 0
        s.kechikishS = kechikish
        let sim = DalaSimulyatsiya(s)
        var jurnal = MuhrZanjir.jurnalSarlavha
        var z = MuhrZanjir()
        func yoz(_ t: YozuvTuri, _ d: [UInt8]) { jurnal += z.qosh(t, d) }
        func yozJ<T: Encodable>(_ t: YozuvTuri, _ v: T) {
            let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
            yoz(t, Array(try! e.encode(v)))
        }
        yozJ(.izoh, ["loyiha": "sinov", "order": "", "tarmoq": "kanalizatsiya", "qurilma": "sinov", "rtk": "",
                     "boshlandi": "2026-10-05T10:00:00Z", "yadro": YadroVersiya.matn])
        if profil {
            yozJ(.izoh, ProfilYozuvi(qabulQilgich: "Reach RX2", seriya: "SINOV-0001", iphone: "iPhone16,1", dastak: "emlid-skan",
                                     tomon: "o'ng", antennaOfset: profilOfset ?? s.ofset, kechikishS: 0.08, manba: "qo'lda"))
        }
        // poza izi 1 s lik to'plamlarda; epoxalar o'z vaqtida orasiga (telefon tartibi: vaqt bo'yicha)
        let pozalar = sim.iz.namunalar
        var pi = 0
        var h = QabulQilgichHolati()
        var juftM: [Vektor3] = [], juftG: [Vektor3] = []
        let geoid = -30.0
        func dm(_ v: Double, _ w: Int) -> String {
            let d = floor(abs(v)), m = (abs(v) - d) * 60
            return String(format: "%0\(w)d%010.7f", Int(d), m)
        }
        func hms(_ u: Double) -> String {
            let s = Int(u)
            return String(format: "%02d%02d%05.2f", s / 3600, (s / 60) % 60, Double(s % 60) + u - floor(u))
        }
        var oxirgiGST = -10.0
        for e in sim.epoxalar {
            // shu epoxa kelgunicha bo'lgan pozalar
            var to: [PozaNamuna] = []
            while pi < pozalar.count, pozalar[pi].t <= e.te! { to.append(pozalar[pi]); pi += 1 }
            var k = 0
            while k < to.count { yozJ(.kadr, IzYozuvi(Array(to[k..<min(to.count, k + 60)]))); k += 60 }
            if e.utcS! - oxirgiGST >= 1 {
                let st = NMEAGap.yasa("GNGST,\(hms(e.utcS! - 0.1)),0.012,0.010,0.008,45.0,0.009,0.009,0.015")
                yoz(.nmea, Array(st.utf8)); h.qabul(try! NMEAXabar.ajrat(st), hozir: Date(timeIntervalSince1970: e.te!))
                oxirgiGST = e.utcS!
            }
            let (lat, lon) = UTM.dan(UTMNuqta(zona: 42, shimoliy: true, x: e.g.x, y: e.g.y))
            let gga = NMEAGap.yasa("GNGGA,\(hms(e.utcS!)),\(dm(lat, 2)),N,\(dm(lon, 3)),E,4,24,0.6,"
                                   + String(format: "%.4f", e.g.z - geoid) + ",M," + String(format: "%.3f", geoid) + ",M,1.0,0000")
            yoz(.nmea, Array(gga.utf8))
            yozJ(.nuqta, NMEAVaqtYozuvi(te: e.te!))
            let hozir = Date(timeIntervalSince1970: e.te!)
            h.qabul(try! NMEAXabar.ajrat(gga), hozir: hozir)
            // telefon qoidasi: RASMIY epoxa, poza = kelish − sozlama (80 ms)
            if h.sifat(hozir: hozir) == .rasmiy, let p = sim.iz.poza(e.te! - 0.08) {
                let gp = UTM.ga(lat: h.lat!, lon: h.lon!, zona: 42)
                let j = JuftYozuvi(m: Antenna.enu(p, ofset: s.ofset), g: Vektor3(gp.x, gp.y, h.balandlikEllipsoid!), zona: 42,
                                   t: e.te! - 0.08, te: e.te!)
                yozJ(.nuqta, j)
                juftM.append(j.mahalliy); juftG.append(j.global)
            }
        }
        if pi < pozalar.count { yozJ(.kadr, IzYozuvi(Array(pozalar[pi...]))) }

        // Transheya va Ø110 (W ramka, ENU: sharq bo'ylab); nuqta kamera ustidan o'tgan paytda kuzatilgan (ARKit A ramka)
        let r = 0.055, tub = -1.2
        var xt: [(t: Double, x: Double)] = []
        for k in 0...Int(s.davomiylikS * 20) {
            let t = sim.t0 + Double(k) / 20
            xt.append((t, ARKitRamka.enu(DalaSimulyatsiya.haqiqiy(s, sim.t0, t).p).x))
        }
        func vaqt(_ x: Double) -> Double {
            var lo = 0, hi = xt.count - 1
            while hi - lo > 1 { let o = (lo + hi) / 2; if xt[o].x <= x { lo = o } else { hi = o } }
            return xt[lo].t
        }
        var rnd = Tasodifiy(urug: 7)
        var bulut: [BulutNuqtasi] = []
        func qosh(_ enuW: Vektor3, _ rang: Rang) {
            let qW = ARKitRamka.arkit(enuW + Vektor3(rnd.normal(sigma: 0.002), rnd.normal(sigma: 0.002), rnd.normal(sigma: 0.002)))
            let t = vaqt(enuW.x)
            bulut.append(BulutNuqtasi(sim.kuzatilgan(qW, vaqt: t), rang: zichVaqtsiz ? nil : rang, t: zichVaqtsiz ? nil : t))
        }
        // DS-07 (sun'iy ranglar): quvur — kulrang-ko'k PVX, tub — tuproq, devor — ochroq tuproq
        var x = 0.5
        while x <= 29.5 {
            for a in stride(from: 15.0, through: 165.0, by: 9.0) {   // ustki yoy, 9° ≈ 0,86 sm
                let f = a * .pi / 180
                qosh(Vektor3(x, r * cos(f), tub + r + r * sin(f)), Rang(96, 112, 128))
            }
            for y in stride(from: -0.4, through: 0.4, by: 0.02) where abs(y) > r * 0.9 { qosh(Vektor3(x, y, tub), Rang(112, 86, 60)) }
            for zz in stride(from: tub, through: 0.0, by: 0.03) {
                qosh(Vektor3(x, -0.4, zz), Rang(150, 118, 84)); qosh(Vektor3(x, 0.4, zz), Rang(150, 118, 84))
            }
            x += 0.01
        }
        let ply = PLY.yoz(bulut, izoh: "YEROSTI zich bulut (SUN'IY sinov)")
        yozJ(.fayl, ["nomi": zichVaqtsiz ? "mesh.ply" : "zich.ply", "sha256": SHA256.hex(SHA256.xesh(ply)), "hajm": "\(ply.count)"])
        var qs = QuvurTopishSozlamalari()
        qs.tarmoqTuri = "kanalizatsiya"
        // telefon ham quvurni PLY dagi (float32) nuqtalardan topadi — server bilan kirish bir xil bo'lsin
        for q in QuvurTopish(qs).topish(PLY.oqi(ply)!.nuqtalar) { yozJ(.belgi, QuvurYozuvi(q)) }
        if juftM.count >= 20, let g = try? Georeferens.gravitatsiyaBilan(mahalliyENU: juftM, global: juftG) {
            yozJ(.izoh, GeorefYozuvi(g, zona: 42))
        }
        return Natija(jurnal: jurnal, ply: ply, sim: sim, haqiqiyOq: { x in sim.utm(ARKitRamka.arkit(Vektor3(x, 0, tub + r))) })
    }

    func testJurnalOqiladi() throws {
        let x = XomTests.yasa()
        let j = try QaytaHisob.jurnalOqi(x.jurnal)
        XCTAssertEqual(j.iz.count, x.sim.iz.namunalar.count)
        XCTAssertEqual(j.epoxalar.filter { $0.te != nil }.count, x.sim.epoxalar.count)
        XCTAssertEqual(j.epoxalar.first!.utcS!, 36_000, accuracy: 1e-6)
        XCTAssertEqual(j.profil?.qabulQilgich, "Reach RX2")
        XCTAssertNotNil(j.plyFayllar["zich.ply"])
        // poza ixcham yozuvi aniqligi: 0,1 mm va 10⁻⁶
        let a = j.iz[1234], b = x.sim.iz.namunalar[1234]
        XCTAssertEqual((a.p - b.p).uzunlik, 0, accuracy: 1e-4)
        XCTAssertEqual(a.t, b.t, accuracy: 2e-6)
        // hajm: 1 daqiqa xom yozuv (poza 60 Hz + GGA/GST + juft)
        let daqiqa = Double(x.jurnal.count) / (x.sim.s.davomiylikS / 60) / 1024
        print(String(format: "DS-03: jurnal %d yozuv, %.0f KB/daqiqa (zich bulut alohida: %.1f MB)", j.soni, daqiqa,
                     Double(x.ply.count) / 1_048_576))
        XCTAssertLessThan(daqiqa, 800)
    }

    /// Qabul mezonlari: DS-04 (kechikish 120 ms ± 10) va DS-05 (1 % suzish, 30 m, quvur o'qi UTM da ≤ 3 sm).
    func testServerKechikishVaBolakliGeoreferens() throws {
        let x = XomTests.yasa()
        let (n, kor) = QaytaHisob.tekshir(jurnal: x.jurnal, ply: [UInt8](x.ply), korinishMaks: 200_000)
        let k = try XCTUnwrap(n.kechikish)
        XCTAssertTrue(k.ishonchli, k.sabab ?? "")
        XCTAssertEqual(k.kechikishS ?? -1, 0.120, accuracy: 0.010)
        let b = try XCTUnwrap(n.bolakli)
        XCTAssertEqual(b.pastBolaklar, 0, "\(b.bolaklar.map { $0.sabab ?? "-" })")
        XCTAssertEqual(b.kechikishManba, "xom ma'lumotdan (DS-04)")
        XCTAssertTrue(b.enuTuzatilgan)
        let q = try XCTUnwrap(n.quvurlar.first { ($0.standartMm ?? 0) == 110 }, "\(n.quvurlar.map(\.diametrMm))")
        XCTAssertEqual(q.georefUsul, "bolakli")
        XCTAssertEqual(q.oqPast?.contains(true), false)
        let utm = try XCTUnwrap(q.oqUtm)
        // haqiqiy o'q: x bo'ylab — har UTM nuqtaning haqiqiy o'qqa masofasi (W→UTM, o'q chizig'i)
        let a = x.haqiqiyOq(0), c = x.haqiqiyOq(30), d = (c - a).birlik!
        let xato = utm.map { u -> Double in let p = Vektor3(u[0], u[1], u[2]) - a; return (p - d * p.nuqta(d)).uzunlik }.max()!
        let qattiq = n.georef!.server!
        print(String(format: "DS-05 server: o'q xatosi maks %.1f sm; kechikish %.1f ms; bo'laklar %d; eng katta tuzatish %.1f sm; qattiq RMS %.1f sm",
                     xato * 100, (k.kechikishS ?? 0) * 1000, b.bolaklar.count, b.maksTuzatishM * 100, qattiq.gorizontalRmsM * 100))
        XCTAssertLessThanOrEqual(xato, 0.03)
        XCTAssertGreaterThan(b.maksTuzatishM, 0.05, "suzish haqiqatan tuzatildi")
        XCTAssertEqual(n.xom?.plyNomi, "zich.ply")
        XCTAssertNotNil(kor)
        XCTAssertNoThrow(try QaytaHisob.json(n))
        XCTAssertTrue(n.ogohlantirishlar.contains { $0.contains("RTK kechikishi: telefon sozlamasi 80 ms") }, "\(n.ogohlantirishlar)")
        XCTAssertEqual(n.xulosa, "MOS", "\(n.sabablar)")
        XCTAssertLessThan(n.taqqos.compactMap(\.oqFarqiM).max() ?? 1, 0.002, "telefon va server bir xil float32 bulutdan")
        XCTAssertTrue(n.ogohlantirishlar.contains { $0.contains("bo'lakli georeferens bilan tuzatildi") }, "\(n.ogohlantirishlar)")
    }

    /// DS-02: profildagi ofset noto'g'ri ([0,0,0]) — xom ma'lumotdan baholangan ofset farqni ko'rsatadi.
    func testNotogriOfsetOgohlantiradi() throws {
        let x = XomTests.yasa(profilOfset: [0, 0, 0])
        let (n, _) = QaytaHisob.tekshir(jurnal: x.jurnal, ply: [UInt8](x.ply))
        let o = try XCTUnwrap(n.ofset)
        XCTAssertTrue(o.kuzatiladi)
        XCTAssertGreaterThan(o.profildanFarqM ?? 0, 0.1)
        XCTAssertTrue(n.ogohlantirishlar.contains { $0.contains("antenna ofseti") }, "\(n.ogohlantirishlar)")
        // to'g'ri profil — ogohlantirish yo'q
        let y = XomTests.yasa()
        let (m, _) = QaytaHisob.tekshir(jurnal: y.jurnal, ply: [UInt8](y.ply))
        XCTAssertLessThan(m.ofset?.profildanFarqM ?? 1, 0.02)
        XCTAssertFalse(m.ogohlantirishlar.contains { $0.contains("antenna ofseti") })
    }

    /// Vaqtsiz bulut (eski mesh.ply): nuqta vaqti eng yaqin kamera pozasidan — baribir suzish tuzatiladi.
    func testVaqtsizBulutPozaIzidan() throws {
        let x = XomTests.yasa(zichVaqtsiz: true)
        let (n, _) = QaytaHisob.tekshir(jurnal: x.jurnal, ply: [UInt8](x.ply))
        let q = try XCTUnwrap(n.quvurlar.first { ($0.standartMm ?? 0) == 110 })
        let utm = try XCTUnwrap(q.oqUtm)
        let a = x.haqiqiyOq(0), c = x.haqiqiyOq(30), d = (c - a).birlik!
        let xato = utm.map { u -> Double in let p = Vektor3(u[0], u[1], u[2]) - a; return (p - d * p.nuqta(d)).uzunlik }.max()!
        XCTAssertLessThanOrEqual(xato, 0.04, "kamera eng yaqin turgan vaqt — taxminiy, shuning uchun 4 sm")
        XCTAssertEqual(n.xom?.plyNomi, "mesh.ply")
    }

    /// Server sinovi uchun to'plam (SINOV_TOPLAM_XOM=<papka>): jurnal.ymj + zich.ply (rang va vaqt bilan).
    func testXomToplamniYoz() throws {
        guard let papka = ProcessInfo.processInfo.environment["SINOV_TOPLAM_XOM"] else { throw XCTSkip("SINOV_TOPLAM_XOM berilmagan") }
        let u = URL(fileURLWithPath: papka, isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        let x = XomTests.yasa()
        try Data(x.jurnal).write(to: u.appendingPathComponent("jurnal.ymj"))
        try x.ply.write(to: u.appendingPathComponent("zich.ply"))
        try Data("SUN'IY sinov to'plami (DalaSimulyatsiya): 30 m transheya, Ø110, ARKit suzishi 1 %, RTK kechikishi 120 ms. Haqiqiy skan emas.\n".utf8)
            .write(to: u.appendingPathComponent("IZOH.txt"))
    }

    /// Eski jurnal (DS-03 dan oldin): xom bo'limlari yo'q, natija avvalgidek.
    func testEskiJurnalOzgarmaydi() {
        let s = SinovSkan.yasa()
        let (n, _) = QaytaHisob.tekshir(jurnal: s.jurnal, ply: [UInt8](s.ply))
        XCTAssertEqual(n.xulosa, "MOS", "\(n.sabablar)")
        XCTAssertNil(n.xom)
        XCTAssertNil(n.kechikish)
        XCTAssertNil(n.bolakli)
        XCTAssertTrue(n.quvurlar.allSatisfy { $0.georefUsul == "qattiq" })
    }
}
