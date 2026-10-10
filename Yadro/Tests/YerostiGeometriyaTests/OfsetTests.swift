import XCTest
import YerostiGeometriya
import YerostiSimulyatsiya

/// DS-02: antenna ofsetini xom ma'lumotdan baholash. SUN'IY simulyatsiya.
final class OfsetTests: XCTestCase {
    func testOfsetTopiladi() {
        var s = DalaSimulyatsiya.Sozlama()
        s.suzishMasshtab = 0.01
        let sim = DalaSimulyatsiya(s)
        let k = Kechikish.baho(iz: sim.iz, epoxalar: sim.epoxalar, ofset: [0, 0, 0])
        let c = Kechikish.soatBoglanishi(sim.epoxalar)
        let b = AntennaOfset.baho(iz: sim.iz, epoxalar: sim.epoxalar, L: k.kechikishS ?? 0.1, c: c, profil: [0, 0, 0])
        print("DS-02 ofset:", b.ofset.map { String(format: "%.3f", $0) }, "σ", b.sigma.map { String(format: "%.3f", $0) },
              "profil farqi", b.profildanFarqM ?? -1)
        XCTAssertTrue(b.kuzatiladi, b.sabab ?? "")
        for i in 0..<3 { XCTAssertEqual(b.ofset[i], s.ofset[i], accuracy: 0.01, "o'q \(i)") }
        XCTAssertGreaterThan(b.profildanFarqM ?? 0, 0.1, "profil [0,0,0] noto'g'ri ekani ko'rinadi")
    }

    func testBirTekisYurishdaKuzatilmaydi() {
        var s = DalaSimulyatsiya.Sozlama()
        s.birTekis = true
        let sim = DalaSimulyatsiya(s)
        let b = AntennaOfset.baho(iz: sim.iz, epoxalar: sim.epoxalar, L: 0.12, c: Kechikish.soatBoglanishi(sim.epoxalar))
        XCTAssertFalse(b.kuzatiladi)
    }
}
