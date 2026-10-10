import XCTest
import YerostiGeometriya
import YerostiSimulyatsiya

/// DS-05: bo'lakli georeferens. SUN'IY dala simulyatsiyasi (haqiqiy skan emas).
final class BolakliTests: XCTestCase {
    struct Xato { var bolakliMaks = 0.0; var qattiqMaks = 0.0; var bolakliRms = 0.0 }

    /// Transheya tubidagi quvur o'qi nuqtalari (W ramka): kamera ostida 1,2 m, sharq bo'ylab.
    func xatolar(_ sim: DalaSimulyatsiya, _ bg: BolakliGeoreferens) -> Xato {
        var x = Xato(), kv = 0.0, n = 0.0
        for k in 0...58 {
            let qW = ARKitRamka.arkit(Vektor3(1.0 + Double(k) * 0.5, 0, 0))
            let t = sim.engYaqinVaqt(qW)
            let enu = ARKitRamka.enu(sim.kuzatilgan(qW, vaqt: t))
            let haq = sim.utm(qW)
            let eb = (bg.qolla(enu, vaqt: t) - haq).uzunlik
            let eq = (bg.umumiy.transformatsiya.qolla(enu) - haq).uzunlik
            x.bolakliMaks = max(x.bolakliMaks, eb)
            x.qattiqMaks = max(x.qattiqMaks, eq)
            kv += eb * eb; n += 1
        }
        x.bolakliRms = (kv / n).squareRoot()
        return x
    }

    func hisobla(_ s: DalaSimulyatsiya.Sozlama, epoxaFiltr: (RTKEpoxasi) -> Bool = { _ in true }) throws
        -> (DalaSimulyatsiya, BolakliGeoreferens) {
        let sim = DalaSimulyatsiya(s)
        let e = sim.epoxalar.filter(epoxaFiltr)
        let L = Kechikish.baho(iz: sim.iz, epoxalar: e, ofset: s.ofset)
        let c = Kechikish.soatBoglanishi(e)
        let j = Kechikish.juftlar(iz: sim.iz, epoxalar: e, ofset: s.ofset, L: L.kechikishS ?? 0.1, c: c)
        return (sim, try BolakliGeoreferens.hisobla(j))
    }

    /// Qabul mezoni: sun'iy suzish 1 % → 30 m da xato ≤ 3 sm.
    func testSuzish1Foiz30m() throws {
        var s = DalaSimulyatsiya.Sozlama()
        s.suzishMasshtab = 0.01
        s.suzishYawGrad30m = 0.5
        s.suzishVertikal = 0.003
        let (sim, bg) = try hisobla(s)
        let x = xatolar(sim, bg)
        print(String(format: "DS-05 1 %%: bo'lakli maks %.1f sm (RMS %.1f sm), bitta qattiq maks %.1f sm; bo'laklar %d, PAST %d, qoldiq H %.1f / V %.1f sm",
                     x.bolakliMaks * 100, x.bolakliRms * 100, x.qattiqMaks * 100, bg.bolaklar.count,
                     bg.bolaklar.filter(\.past).count, bg.rmsH * 100, bg.rmsV * 100))
        XCTAssertLessThanOrEqual(x.bolakliMaks, 0.03)
        XCTAssertGreaterThan(x.qattiqMaks, 0.06, "bitta qattiq transformatsiya suzishni tuzata olmaydi — sinov sezgir")
        XCTAssertGreaterThanOrEqual(bg.bolaklar.count, 3)
        XCTAssertTrue(bg.bolaklar.allSatisfy { !$0.past }, "\(bg.bolaklar.map { $0.sabab ?? "-" })")
    }

    func testSuzishsizIkkalasiBirXil() throws {
        let (sim, bg) = try hisobla(DalaSimulyatsiya.Sozlama())
        let x = xatolar(sim, bg)
        XCTAssertLessThanOrEqual(x.bolakliMaks, 0.02)
        XCTAssertLessThanOrEqual(x.qattiqMaks, 0.02)
    }

    /// RTK FIX 15 s uzilsa — o'sha bo'lak PAST, sababi yozilgan.
    func testRTKUzilishiPast() throws {
        var s = DalaSimulyatsiya.Sozlama()
        s.suzishMasshtab = 0.01
        let b0 = s.gnssBoshS
        let (_, bg) = try hisobla(s) { e in !((b0 + 30)...(b0 + 45)).contains(e.utcS!) }
        let past = bg.bolaklar.filter(\.past)
        XCTAssertFalse(past.isEmpty)
        XCTAssertTrue(past.contains { $0.sabab?.contains("uzilishi") ?? false }, "\(bg.bolaklar.map { $0.sabab ?? "-" })")
        // uzilish vaqtidagi nuqta PAST bo'lakka tushadi
        let t = s.gnssBoshS + s.soatS + 38
        XCTAssertTrue(bg.bolak(t)?.past ?? true)
    }

    /// RTK shovqini katta (5 sm) — bo'laklar qoldig'i 3 sm dan oshadi, PAST.
    func testKattaShovqinPast() throws {
        var s = DalaSimulyatsiya.Sozlama()
        s.sigmaH = 0.06
        s.sigmaV = 0.06
        let (_, bg) = try hisobla(s)
        XCTAssertTrue(bg.bolaklar.contains { $0.past && ($0.sabab?.contains("qoldiq") ?? false) },
                      "\(bg.bolaklar.map { String(format: "%.1f", max($0.rmsH, $0.rmsV) * 100) })")
    }

    func testJuftKam() {
        XCTAssertThrowsError(try BolakliGeoreferens.hisobla([]))
    }
}
