import XCTest
import YerostiGeometriya
import YerostiHUD

final class HUDTests: XCTestCase {
    // MARK: UI-07, UI-19

    func testSifatPogonalari() {
        XCTAssertEqual(SifatPogonasi.ulush(foiz: 100), .yaxshi)
        XCTAssertEqual(SifatPogonasi.ulush(foiz: 90), .yaxshi)
        XCTAssertEqual(SifatPogonasi.ulush(foiz: 89.9), .orta)
        XCTAssertEqual(SifatPogonasi.ulush(foiz: 50), .orta)
        XCTAssertEqual(SifatPogonasi.ulush(foiz: 49.9), .past)
        XCTAssertEqual(SifatPogonasi.aniqlik(sm: 2.9), .yaxshi)
        XCTAssertEqual(SifatPogonasi.aniqlik(sm: 3), .orta)
        XCTAssertEqual(SifatPogonasi.aniqlik(sm: 6), .orta)
        XCTAssertEqual(SifatPogonasi.aniqlik(sm: 6.1), .past)
    }

    // MARK: UI-01

    func kirish(_ o: (inout TayyorlikKirish) -> Void = { _ in }) -> TayyorlikKirish {
        var k = TayyorlikKirish(lidarBor: true, rtkUlangan: true, rtkHolat: "FIX", rasmiy: true, sigmaHSm: 1.2, tuzatmaYoshiS: 1,
                                bazaMasofaKm: 8, antennaOfsetKiritilgan: true, boshXotiraBayt: 40_000_000_000, batareya: 0.8, termal: 0)
        o(&k)
        return k
    }

    func holat(_ b: [TayyorlikBandi], _ id: String) -> TayyorlikBandi.Holat? { b.first { $0.id == id }?.holat }

    func testTayyorlikHammasiJoyida() {
        let b = Tayyorlik.baholash(kirish())
        XCTAssertTrue(Tayyorlik.boshlashMumkin(b))
        XCTAssertTrue(b.allSatisfy { $0.holat == .ok }, "\(b)")
        XCTAssertEqual(b.first { $0.id == "rtk" }?.qiymat, "FIX · 1,2 sm")
        XCTAssertEqual(b.first { $0.id == "xotira" }?.qiymat, "40,0 GB")
    }

    func testTayyorlikToxtatuvchilar() {
        XCTAssertFalse(Tayyorlik.boshlashMumkin(Tayyorlik.baholash(kirish { $0.lidarBor = false })))
        let x = Tayyorlik.baholash(kirish { $0.boshXotiraBayt = 500_000_000 })
        XCTAssertEqual(holat(x, "xotira"), .toxtat)
        XCTAssertFalse(Tayyorlik.boshlashMumkin(x))
        XCTAssertEqual(holat(Tayyorlik.baholash(kirish { $0.boshXotiraBayt = 3_000_000_000 }), "xotira"), .ogoh)
        let t = Tayyorlik.baholash(kirish { $0.termal = 3 })
        XCTAssertEqual(holat(t, "harorat"), .toxtat)
        XCTAssertFalse(Tayyorlik.boshlashMumkin(t))
    }

    func testTayyorlikOgohlantirishlarBoshlashniTosmaydi() {
        let b = Tayyorlik.baholash(kirish { $0.rtkUlangan = false })
        XCTAssertEqual(holat(b, "rtk"), .ogoh)
        XCTAssertNil(holat(b, "tuzatma"), "RTK yo'q — tuzatma bandi ma'nosiz")
        XCTAssertTrue(Tayyorlik.boshlashMumkin(b), "RTK siz ham boshlash mumkin, ogohlantirish bilan")
        XCTAssertNotNil(b.first { $0.id == "rtk" }?.izoh)
        XCTAssertEqual(holat(Tayyorlik.baholash(kirish { $0.rasmiy = false; $0.rtkHolat = "FLOAT" }), "rtk"), .ogoh)
        XCTAssertEqual(holat(Tayyorlik.baholash(kirish { $0.tuzatmaYoshiS = nil }), "tuzatma"), .ogoh)
        XCTAssertEqual(holat(Tayyorlik.baholash(kirish { $0.tuzatmaYoshiS = 11 }), "tuzatma"), .ogoh)
        XCTAssertEqual(holat(Tayyorlik.baholash(kirish { $0.bazaMasofaKm = 25 }), "baza"), .ogoh)
        XCTAssertEqual(holat(Tayyorlik.baholash(kirish { $0.antennaOfsetKiritilgan = false }), "antenna"), .ogoh)
        XCTAssertEqual(holat(Tayyorlik.baholash(kirish { $0.batareya = 0.1 }), "batareya"), .ogoh)
        XCTAssertNil(holat(Tayyorlik.baholash(kirish { $0.batareya = nil }), "batareya"))
        XCTAssertEqual(holat(Tayyorlik.baholash(kirish { $0.termal = 2 }), "harorat"), .ogoh)
    }

    // MARK: UI-05

    func testYoriqnomaUstuvorligi() {
        var h = HUDHolati()
        XCTAssertEqual(YoriqnomaTanlov.tanla(h).tur, .maslahat)
        XCTAssertTrue(YoriqnomaTanlov.tanla(h).matn.contains("boshlash"))

        h.yozilmoqda = true; h.rtkUlangan = true; h.rasmiy = true; h.georefJuft = 5
        XCTAssertTrue(YoriqnomaTanlov.tanla(h).matn.contains("5/20"), "bog'lanish jarayoni ko'rinadi")
        h.georefJuft = 25
        XCTAssertTrue(YoriqnomaTanlov.tanla(h).matn.contains("sekin yuring"))

        h.asbob = .quvur
        XCTAssertTrue(YoriqnomaTanlov.tanla(h).matn.contains("Quvur ustiga"))
        h.xabar = "Quvur topilmadi"
        XCTAssertEqual(YoriqnomaTanlov.tanla(h).matn, "Quvur topilmadi", "dvigatel xabari maslahatdan ustun")
        h.kuzatuv = .sekinroq
        XCTAssertTrue(YoriqnomaTanlov.tanla(h).matn.contains("sekinroq"), "kuzatuv muammosi xabardan ustun")
        h.rasmiy = false
        XCTAssertEqual(YoriqnomaTanlov.tanla(h).tur, .xavf, "FIX yo'qolishi kuzatuvdan ustun")
        XCTAssertTrue(YoriqnomaTanlov.tanla(h).matn.contains("FIX"))
        h.batareya = 0.12
        XCTAssertTrue(YoriqnomaTanlov.tanla(h).matn.contains("Batareya 12 %"))
        XCTAssertEqual(YoriqnomaTanlov.tanla(h).tur, .ogoh)
        h.batareya = 0.08
        XCTAssertEqual(YoriqnomaTanlov.tanla(h).tur, .xavf)
        h.termal = 2
        XCTAssertTrue(YoriqnomaTanlov.tanla(h).matn.contains("qizimoqda"), "qizish hammasidan ustun")
        h.termal = 3
        XCTAssertEqual(YoriqnomaTanlov.tanla(h).tur, .xavf)
    }

    func testYoriqnomaYozilmayotgandaBatareyaVaFIXniAytmaydi() {
        var h = HUDHolati()
        h.batareya = 0.05; h.rtkUlangan = true; h.rasmiy = false
        XCTAssertEqual(YoriqnomaTanlov.tanla(h).tur, .maslahat, "yozish boshlanmagan — faqat maslahat (tayyorlik varag'i aytadi)")
    }

    // MARK: UI-13

    func testNoaniqlikYolagi() {
        let a = Noaniqlik.liniyaSigma(sigmaHSm: 1.4, sifat: "SKAN")
        XCTAssertEqual(a.m, 0.014, accuracy: 1e-12)
        XCTAssertTrue(a.malum)
        XCTAssertEqual(Noaniqlik.liniyaSigma(sigmaHSm: nil, sifat: "RASMIY").m, 0.02)
        let b = Noaniqlik.liniyaSigma(sigmaHSm: nil, sifat: "PAST")
        XCTAssertFalse(b.malum, "σ yo'q va RASMIY emas — noma'lum deb yoziladi")
        XCTAssertEqual(Noaniqlik.yarimKenglik(liniyaSigmaM: 0.02, bogRmsM: 0.015), 0.05, accuracy: 1e-12)
        XCTAssertEqual(Noaniqlik.yarimKenglik(liniyaSigmaM: 0.03, bogRmsM: nil), 0.06, accuracy: 1e-12)
    }

    // MARK: UI-15

    func testNisbiyYonalish() {
        let k = Vektor3.nol, oldi = Vektor3(0, -0.7, -1)   // yerga qiya qaragan telefon: gorizontal proyeksiya −z
        XCTAssertEqual(Yonalish.nisbiy(kamera: k, oldinga: oldi, nuqta: Vektor3(0, -1.5, -2)).burchak, 0, accuracy: 1e-12)
        XCTAssertEqual(Yonalish.nisbiy(kamera: k, oldinga: oldi, nuqta: Vektor3(0, -1.5, -2)).masofa, 2, accuracy: 1e-12)
        XCTAssertEqual(Yonalish.nisbiy(kamera: k, oldinga: oldi, nuqta: Vektor3(1, 0, 0)).burchak, .pi / 2, accuracy: 1e-12, "o'ngda +")
        XCTAssertEqual(Yonalish.nisbiy(kamera: k, oldinga: oldi, nuqta: Vektor3(-1, 0, 0)).burchak, -.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(abs(Yonalish.nisbiy(kamera: k, oldinga: oldi, nuqta: Vektor3(0, 0, 3)).burchak), .pi, accuracy: 1e-12, "orqada")
    }

    func testEngYaqinNuqta() throws {
        let a = [Vektor3(5, -1, -10), Vektor3(5, -1, 10)]
        let b = [Vektor3(-2, -1.5, -10), Vektor3(-2, -1.5, 10)]
        let q = try XCTUnwrap(Yonalish.engYaqin(kamera: Vektor3(0, 0, 3), oqlar: [a, b]))
        XCTAssertEqual(q.x, -2, accuracy: 1e-12)
        XCTAssertEqual(q.z, 3, accuracy: 1e-12, "perpendikulyar asosi")
        XCTAssertNil(Yonalish.engYaqin(kamera: .nol, oqlar: [[Vektor3.nol]]))
    }

    func testEkranChetiNuqtasi() {
        let (w, h, c) = (400.0, 800.0, 30.0)
        var p = Yonalish.chetNuqtasi(burchak: 0, kenglik: w, balandlik: h, chet: c)
        XCTAssertEqual(p.x, 200, accuracy: 1e-9); XCTAssertEqual(p.y, 30, accuracy: 1e-9)
        p = Yonalish.chetNuqtasi(burchak: .pi / 2, kenglik: w, balandlik: h, chet: c)
        XCTAssertEqual(p.x, 370, accuracy: 1e-9); XCTAssertEqual(p.y, 400, accuracy: 1e-9)
        p = Yonalish.chetNuqtasi(burchak: .pi, kenglik: w, balandlik: h, chet: c)
        XCTAssertEqual(p.x, 200, accuracy: 1e-9); XCTAssertEqual(p.y, 770, accuracy: 1e-9)
        p = Yonalish.chetNuqtasi(burchak: .pi / 4, kenglik: w, balandlik: h, chet: c)
        XCTAssertEqual(p.x, 370, accuracy: 1e-9, "tor ekranda 45° — o'ng chetga tegadi")
        XCTAssertEqual(p.y, 400 - 170, accuracy: 1e-9)
    }

    func testBaytFormati() {
        XCTAssertEqual(Son.bayt(12_400_000_000), "12,4 GB")
        XCTAssertEqual(Son.bayt(850_000_000), "850 MB")
    }

    /// LK-05: geodezik asos bandi — punkt yo'q va tekshiruvsiz kun ogohlantiradi, o'tmagan tekshiruv skanni to'xtatadi.
    func testNazoratBandi() {
        func band(_ n: NazoratHolati?) -> TayyorlikBandi? {
            Tayyorlik.baholash(TayyorlikKirish(lidarBor: true, rtkUlangan: true, rtkHolat: "FIX", rasmiy: true, sigmaHSm: 1,
                                               tuzatmaYoshiS: 1, bazaMasofaKm: 3, antennaOfsetKiritilgan: true,
                                               boshXotiraBayt: 50_000_000_000, batareya: 0.9, termal: 0, nazorat: n))
                .first { $0.id == "nazorat" }
        }
        XCTAssertNil(band(nil))
        XCTAssertEqual(band(.punktYoq)?.holat, .ogoh)
        XCTAssertEqual(band(.bugunYoq)?.holat, .ogoh)
        XCTAssertEqual(band(.bugunOtdi(0.012))?.holat, .ok)
        XCTAssertEqual(band(.bugunOtdi(0.012))?.qiymat, "1,2 sm")
        let yomon = band(.bugunOtmadi(0.051))
        XCTAssertEqual(yomon?.holat, .toxtat)
        XCTAssertFalse(Tayyorlik.boshlashMumkin([yomon!]))
    }
}
