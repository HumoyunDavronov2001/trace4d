import XCTest
import YerostiGeometriya
import YerostiSimulyatsiya

/// DS-04: kechikishni xom ma'lumotdan baholash. SUN'IY dala simulyatsiyasi.
final class KechikishTests: XCTestCase {
    func testUTCSoniya() {
        XCTAssertEqual(Kechikish.utcSoniya("101503.40")!, 36_903.4, accuracy: 1e-9)
        XCTAssertNil(Kechikish.utcSoniya("10"))
        let u = Kechikish.uzluksiz([86_399.8, 86_400 - 0.0, 0.2, nil, 0.4])
        XCTAssertEqual(u[2]!, 86_400.2, accuracy: 1e-9)
        XCTAssertEqual(u[4]!, 86_400.4, accuracy: 1e-9)
    }

    func testPozaIziInterpolyatsiya() {
        let q0 = Kvaternion.birlik, q1 = Kvaternion(oq: Vektor3(0, 1, 0), burchak: 0.4)
        let iz = PozaIzi([PozaNamuna(t: 1, p: Vektor3(0, 0, 0), q: q0), PozaNamuna(t: 2, p: Vektor3(1, 0, 0), q: q1)])
        XCTAssertNil(iz.poza(1.5), "namunalar orasidagi 1 s bo'shliq — standart chegara 0,5 s dan katta")
        let o = iz.poza(1.5, boshliqS: 2)!
        XCTAssertEqual(o.p.x, 0.5, accuracy: 1e-12)
        let kutilgan = Kvaternion(oq: Vektor3(0, 1, 0), burchak: 0.2)
        XCTAssertEqual(o.q.y, kutilgan.y, accuracy: 1e-9)
        XCTAssertNil(iz.poza(2.2), "izdan tashqarida taxmin qilinmaydi")
        let m = Kvaternion(Kvaternion(oq: Vektor3(1, 2, 3), burchak: 2.5).matritsa)
        let r = Kvaternion(oq: Vektor3(1, 2, 3), burchak: 2.5)
        XCTAssertEqual(abs(m.x * r.x + m.y * r.y + m.z * r.z + m.w * r.w), 1, accuracy: 1e-9, "matritsa ↔ kvaternion")
    }

    /// Qabul mezoni: sun'iy kechikish 120 ms → topiladi ± 10 ms.
    func testKechikish120ms() {
        var s = DalaSimulyatsiya.Sozlama()
        s.kechikishS = 0.120
        let sim = DalaSimulyatsiya(s)
        let n = Kechikish.baho(iz: sim.iz, epoxalar: sim.epoxalar, ofset: s.ofset)
        print("DS-04 120 ms:", n.kechikishS.map { String(format: "%.1f ms", $0 * 1000) } ?? "-", "rms",
              n.rmsM.map { String(format: "%.2f sm", $0 * 100) } ?? "-", "usul", n.usul, "o'rtacha", n.ortachaS ?? -1)
        XCTAssertTrue(n.ishonchli, n.sabab ?? "")
        XCTAssertEqual(n.usul, "utc")
        XCTAssertEqual(n.kechikishS!, 0.120, accuracy: 0.010)
        XCTAssertLessThan(n.rmsM!, 0.015)
    }

    func testKechikishTurliQiymatlar() {
        for (L, urug) in [(0.040, UInt64(3)), (0.200, 4), (0.260, 5)] {
            var s = DalaSimulyatsiya.Sozlama()
            s.kechikishS = L
            s.urug = urug
            let sim = DalaSimulyatsiya(s)
            let n = Kechikish.baho(iz: sim.iz, epoxalar: sim.epoxalar, ofset: s.ofset)
            XCTAssertTrue(n.ishonchli, "\(L): \(n.sabab ?? "")")
            XCTAssertEqual(n.kechikishS ?? -1, L, accuracy: 0.010, "\(L)")
        }
    }

    /// GNSS vaqtisiz (faqat kelish vaqti) — tebranish chiqarilmaydi: o'rtacha kechikish topiladi.
    func testFaqatKelishVaqti() {
        let sim = DalaSimulyatsiya()
        let e = sim.epoxalar.map { RTKEpoxasi(g: $0.g, utcS: nil, te: $0.te, rasmiy: true) }
        let n = Kechikish.baho(iz: sim.iz, epoxalar: e, ofset: sim.s.ofset)
        XCTAssertEqual(n.usul, "kelish")
        XCTAssertEqual(n.kechikishS ?? -1, 0.135, accuracy: 0.012, "120 ms + o'rtacha tebranish 15 ms")
    }

    /// Bir tekis to'g'ri yurish: kechikish siljish bilan aralashadi — ishonchli emas deb aytiladi.
    func testBirTekisYurishIshonchsiz() {
        var s = DalaSimulyatsiya.Sozlama()
        s.birTekis = true
        let sim = DalaSimulyatsiya(s)
        let n = Kechikish.baho(iz: sim.iz, epoxalar: sim.epoxalar, ofset: s.ofset)
        XCTAssertFalse(n.ishonchli, "egri: \(n.egri.prefix(3))")
        XCTAssertNotNil(n.sabab)
    }

    func testKelishVaqtiYoq() {
        let sim = DalaSimulyatsiya()
        let e = sim.epoxalar.map { RTKEpoxasi(g: $0.g, utcS: $0.utcS, te: nil, rasmiy: true) }
        let n = Kechikish.baho(iz: sim.iz, epoxalar: e, ofset: sim.s.ofset)
        XCTAssertNil(n.kechikishS)
        XCTAssertTrue(n.sabab?.contains("DS-03") ?? false)
    }
}
