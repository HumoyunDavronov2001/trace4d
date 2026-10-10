import Foundation
import XCTest
@testable import YerostiTahlil
import YerostiGeometriya

/// KU-05 sinov sahnalari (SUN'IY geometriya, faqat algoritmni o'lchash uchun).
extension Sahna {
    /// QuvurTopishTests.dn160Sahna bilan bir xil: DN160, nishab 1 %, 4 m transheya, 10 % axlat.
    static func dn160(normalBilan: Bool = true, urug: UInt64 = 11) -> Sahna {
        var s = Sahna(sigma: 0.005, normalBilan: normalBilan, urug: urug)
        let r = 0.08
        let tub: (Double) -> Double = { z in -1.85 + 0.01 * z }
        s.transheya(kenglik: 0.8, uzunlik: 4, tub: tub, yashirin: { x, _ in abs(x) < r })
        s.quvur(bosh: Vektor3(0, tub(0.2) + r, 0.2), yonalish: Vektor3(0, 0.01, 1), uzunlik: 3.6, radius: { _ in r })
        s.axlat(s.nuqtalar.count / 10, min: Vektor3(-0.4, -1.9, 0), max: Vektor3(0.4, 0, 4))
        return s
    }

    /// Qiyin sahna: uzun transheyada qisqa kichik quvur (bulutning ~1–2 % i), shovqinli nuqtalar.
    struct Qiyin { var sahna: Sahna; var bosh: Vektor3; var yonalish: Vektor3; var dMm: Double; var uzunlik: Double }

    static func qiyin(_ tur: Int, urug: UInt64) -> Qiyin {
        switch tur {
        case 0:   // DN63, 1,2 m, 8 m transheya
            var s = Sahna(sigma: 0.005, normalBilan: true, urug: urug)
            let r = 0.0315, bosh = Vektor3(0.1, -1.6 + r, 3.0)
            s.transheya(kenglik: 0.8, uzunlik: 8, tub: { _ in -1.6 }, yerKeng: 2.5,
                        yashirin: { x, z in abs(x - 0.1) < r && z >= 3.0 && z <= 4.2 })
            s.quvur(bosh: bosh, yonalish: Vektor3(0, 0, 1), uzunlik: 1.2, radius: { _ in r })
            s.axlat(s.nuqtalar.count * 15 / 100, min: Vektor3(-0.4, -1.65, 0), max: Vektor3(0.4, 0, 8))
            return Qiyin(sahna: s, bosh: bosh, yonalish: Vektor3(0, 0, 1), dMm: 63, uzunlik: 1.2)
        case 1:   // xuddi shu, lekin normalsiz bulut (tashqi LiDAR kabi), shovqin 6 mm
            var s = Sahna(sigma: 0.006, normalBilan: false, urug: urug)
            let r = 0.0315, bosh = Vektor3(0.1, -1.6 + r, 3.0)
            s.transheya(kenglik: 0.8, uzunlik: 8, tub: { _ in -1.6 }, yerKeng: 2.5,
                        yashirin: { x, z in abs(x - 0.1) < r && z >= 3.0 && z <= 4.2 })
            s.quvur(bosh: bosh, yonalish: Vektor3(0, 0, 1), uzunlik: 1.2, radius: { _ in r })
            s.axlat(s.nuqtalar.count * 15 / 100, min: Vektor3(-0.4, -1.65, 0), max: Vektor3(0.4, 0, 8))
            return Qiyin(sahna: s, bosh: bosh, yonalish: Vektor3(0, 0, 1), dMm: 63, uzunlik: 1.2)
        case 2:   // DN110 yarim ko'milgan: faqat yuqori 120° ko'rinadi, transheyaga 25° burchakda
            var s = Sahna(sigma: 0.005, normalBilan: true, urug: urug)
            let r = 0.055
            let yo = Vektor3(sin(25 * Double.pi / 180), 0, cos(25 * Double.pi / 180))
            let bosh = Vektor3(-0.25, -1.5 + 0.02, 0.6)
            s.transheya(kenglik: 1.2, uzunlik: 5, tub: { _ in -1.5 }, yerKeng: 2.5)
            s.quvur(bosh: bosh, yonalish: yo, uzunlik: 1.1, radius: { _ in r }, yarimYoy: 60)
            s.axlat(s.nuqtalar.count * 15 / 100, min: Vektor3(-0.6, -1.55, 0), max: Vektor3(0.6, 0, 5))
            return Qiyin(sahna: s, bosh: bosh, yonalish: yo, dMm: 110, uzunlik: 1.1)
        default:  // DN160, kuchli shovqin 9 mm (ARKit yomon yorug'likda)
            var s = Sahna(sigma: 0.009, normalBilan: true, urug: urug)
            let r = 0.08, bosh = Vektor3(0, -1.85 + r, 0.2)
            s.transheya(kenglik: 0.8, uzunlik: 4, tub: { _ in -1.85 }, yashirin: { x, _ in abs(x) < r })
            s.quvur(bosh: bosh, yonalish: Vektor3(0, 0, 1), uzunlik: 3.6, radius: { _ in r })
            s.axlat(s.nuqtalar.count * 15 / 100, min: Vektor3(-0.4, -1.9, 0), max: Vektor3(0.4, 0, 4))
            return Qiyin(sahna: s, bosh: bosh, yonalish: Vektor3(0, 0, 1), dMm: 160, uzunlik: 3.6)
        }
    }
}

/// To'g'ri topilgan: standart diametr mos, o'qning hamma cho'qqisi haqiqiy o'qdan ≤ 2 sm, uzunlik ±25 %.
func topildi(_ q: [TopilganQuvur], _ x: Sahna.Qiyin) -> Bool {
    q.contains { p in
        p.standart?.tashqiMm == x.dMm && p.oq.allSatisfy { chiziqMasofa($0, x.bosh, x.yonalish) < 0.02 }
            && abs(p.uzunlikM - x.uzunlik) < 0.25 * x.uzunlik
    }
}

final class QuvurHoughTests: XCTestCase {
    /// KU-05: tekis transheyada Hough gipotezasi to'g'ridan-to'g'ri haqiqiy quvurga tushadi (LM aniqlashtirishsiz ham).
    func testHoughGipotezasiDN160() throws {
        let s = Sahna.dn160()
        let g = QuvurTopish().houghSinov(s.nuqtalar)
        XCTAssertFalse(g.isEmpty, "Hough gipotezasi bo'lishi shart")
        let haqiqiyBosh = Vektor3(0, -1.85 + 0.002 + 0.08, 0.2), yo = Vektor3(0, 0.01, 1).birlik!
        let eng = try XCTUnwrap(g.min { chiziqMasofa($0.c, haqiqiyBosh, yo) < chiziqMasofa($1.c, haqiqiyBosh, yo) })
        XCTAssertLessThan(chiziqMasofa(eng.c, haqiqiyBosh, yo), 0.015, "o'q ≤ 1,5 sm")
        XCTAssertGreaterThan(abs(eng.a.nuqta(yo)), cos(2 * Double.pi / 180), "yo'nalish ≤ 2°")
        XCTAssertEqual(eng.r, 0.08, accuracy: 0.006, "radius ≤ 6 mm")
        let birinchi = try XCTUnwrap(g.first)
        XCTAssertLessThan(chiziqMasofa(birinchi.c, haqiqiyBosh, yo), 0.015, "eng kuchli cho'qqi — quvur (burchak emas)")
    }

    /// Hough faqat qo'shimcha manba: o'chirilsa ham toza sahnada natija bir xil sifatda.
    func testHoughOchiqVaYopiqToza() throws {
        let s = Sahna.dn160()
        var yopiq = QuvurTopishSozlamalari(); yopiq.hough = false
        for q in [QuvurTopish().topish(s.nuqtalar), QuvurTopish(yopiq).topish(s.nuqtalar)] {
            XCTAssertEqual(q.count, 1)
            XCTAssertEqual(q.first?.standart?.tashqiMm, 160)
        }
    }

    /// KU-05: kichik quvur katta bulutda (bulutning ~1 % i) — RANSAC juftlari deyarli topmaydi (20 dan 1), Hough topadi.
    func testKichikQuvurKattaBulut() throws {
        for u: UInt64 in [1, 2] {
            let x = Sahna.qiyin(0, urug: u)
            var sz = QuvurTopishSozlamalari(); sz.urug = 77 + u; sz.tarmoqTuri = "suv"
            let q = QuvurTopish(sz).topish(x.sahna.nuqtalar)
            XCTAssertTrue(topildi(q, x), "DN63 topilishi shart (urug' \(u)): \(q.map { ($0.tashqiDiametrMm, $0.uzunlikM) })")
            XCTAssertEqual(q.count, 1, "soxta quvur bo'lmasin")
        }
    }

    /// KU-05 fizik cheklov: kuchli shovqinda (9 mm) haqiqiy quvurning ichki/tashqi qobig'i alohida "quvur" bo'lib chiqmaydi
    /// (tuzatishdan oldin shu urug'larda DN125 va DN200 o'qdosh soxta quvurlar chiqardi).
    func testShovqinQobigiAlohidaQuvurEmas() throws {
        for u: UInt64 in [3, 4] {
            let x = Sahna.qiyin(3, urug: 3000 + u)
            var sz = QuvurTopishSozlamalari(); sz.urug = 77 + u; sz.tarmoqTuri = "suv"
            let q = QuvurTopish(sz).topish(x.sahna.nuqtalar)
            XCTAssertEqual(q.count, 1, "faqat bitta quvur: \(q.map { $0.tashqiDiametrMm })")
            XCTAssertTrue(topildi(q, x))
        }
    }

    /// O'lchov (faqat YEROSTI_TAJRIBA=1 bilan, release rejimda): qiyin sahnalarda RANSAC va RANSAC+Hough.
    func testTajriba() throws {
        guard ProcessInfo.processInfo.environment["YEROSTI_TAJRIBA"] == "1" else { throw XCTSkip("faqat o'lchov uchun") }
        let urugSoni = Int(ProcessInfo.processInfo.environment["YEROSTI_URUG"] ?? "10") ?? 10
        for tur in 0..<4 {
            var ok = [0, 0], vaqt = [0.0, 0.0], soxta = [0, 0]
            for u in 1...urugSoni {
                let x = Sahna.qiyin(tur, urug: UInt64(1000 * tur + u))
                for (i, h) in [false, true].enumerated() {
                    var sz = QuvurTopishSozlamalari(); sz.hough = h; sz.urug = UInt64(77 + u); sz.tarmoqTuri = "suv"
                    let t0 = Date()
                    let q = QuvurTopish(sz).topish(x.sahna.nuqtalar)
                    vaqt[i] += Date().timeIntervalSince(t0)
                    if topildi(q, x) { ok[i] += 1 }
                    soxta[i] += q.filter { p in !(p.standart?.tashqiMm == x.dMm && p.oq.allSatisfy { chiziqMasofa($0, x.bosh, x.yonalish) < 0.05 }) }.count
                }
            }
            print(String(format: "TAJRIBA sahna %d: nuqta %d | RANSAC %d/%d (soxta %d, %.2f s) | RANSAC+Hough %d/%d (soxta %d, %.2f s)",
                         tur, Sahna.qiyin(tur, urug: 1).sahna.nuqtalar.count, ok[0], urugSoni, soxta[0], vaqt[0] / Double(urugSoni),
                         ok[1], urugSoni, soxta[1], vaqt[1] / Double(urugSoni)))
        }
    }
}
