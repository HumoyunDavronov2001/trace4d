import XCTest
@testable import YerostiTahlil
import YerostiGeometriya

/// Sinov sahnasi: ochiq transheya geometriyasi (ARKit ramkasi, y — yuqori), LiDAR'ga o'xshash shovqin.
/// Bu faqat algoritmni o'lchash uchun birlik-test geometriyasi; mahsulotga kirmaydi.
struct Sahna {
    var nuqtalar: [BulutNuqtasi] = []
    var t: Tasodifiy
    let sigma: Double
    let normalBilan: Bool
    static let yuqori = Vektor3(0, 1, 0)

    init(sigma: Double = 0.005, normalBilan: Bool = true, urug: UInt64 = 1) {
        self.sigma = sigma; self.normalBilan = normalBilan; t = Tasodifiy(urug: urug)
    }

    mutating func qosh(_ p: Vektor3, _ n: Vektor3) {
        let q = p + Vektor3(t.normal(sigma: sigma), t.normal(sigma: sigma), t.normal(sigma: sigma))
        var nn: Vektor3?
        if normalBilan { nn = (n + Vektor3(t.normal(sigma: 0.05), t.normal(sigma: 0.05), t.normal(sigma: 0.05))).birlik }
        nuqtalar.append(BulutNuqtasi(q, n: nn))
    }

    /// Transheya: yer sirti y=0, devorlar x=±k/2, tub y=tub(z). `yashirin(x,z)` — quvur ostidagi tub nuqtalari.
    mutating func transheya(kenglik k: Double, uzunlik L: Double, tub: (Double) -> Double, yerKeng: Double = 2.0,
                            qadam: Double = 0.025, yashirin: (Double, Double) -> Bool = { _, _ in false }) {
        for z in stride(from: 0.0, through: L, by: qadam) {
            for x in stride(from: -yerKeng, through: yerKeng, by: qadam) where abs(x) > k / 2 {
                qosh(Vektor3(x, 0, z), Sahna.yuqori)
            }
            for y in stride(from: tub(z), through: 0, by: qadam) {
                qosh(Vektor3(-k / 2, y, z), Vektor3(1, 0, 0))
                qosh(Vektor3(k / 2, y, z), Vektor3(-1, 0, 0))
            }
            for x in stride(from: -k / 2 + qadam, to: k / 2, by: qadam) where !yashirin(x, z) {
                qosh(Vektor3(x, tub(z), z), Sahna.yuqori)
            }
        }
    }

    /// To'g'ri quvur bo'lagi: `bosh` dan `yonalish` bo'ylab `L` metr; yuqori tomondan ±`yarimYoy` gradus ko'rinadi.
    mutating func quvur(bosh: Vektor3, yonalish: Vektor3, uzunlik L: Double, radius r: (Double) -> Double,
                        yarimYoy: Double = 100, qadam: Double = 0.01) {
        let a = yonalish.birlik!
        let yon = a.kross(Sahna.yuqori).birlik!
        let yuq = yon.kross(a)
        for s in stride(from: 0.0, through: L, by: qadam) {
            let rr = r(s)
            let dTeta = qadam / rr
            for teta in stride(from: -yarimYoy * .pi / 180, through: yarimYoy * .pi / 180, by: dTeta) {
                let n = yon * sin(teta) + yuq * cos(teta)
                qosh(bosh + a * s + n * rr, n)
            }
        }
    }

    mutating func axlat(_ soni: Int, min mn: Vektor3, max mx: Vektor3) {
        for _ in 0..<soni {
            let p = Vektor3(mn.x + (mx.x - mn.x) * t.birlik(), mn.y + (mx.y - mn.y) * t.birlik(), mn.z + (mx.z - mn.z) * t.birlik())
            let n = Vektor3(t.normal(), t.normal(), t.normal()).birlik ?? Sahna.yuqori
            nuqtalar.append(BulutNuqtasi(p, n: normalBilan ? n : nil))
        }
    }
}

/// Nuqtadan chiziqqacha masofa.
func chiziqMasofa(_ p: Vektor3, _ a: Vektor3, _ d: Vektor3) -> Double {
    let u = d.birlik!
    let v = p - a
    return (v - u * v.nuqta(u)).uzunlik
}

final class QuvurTopishTests: XCTestCase {
    /// DN160, nishab 1 %, tub bo'ylab; yer sirti y=0 → qoplama chuqurligi z da: 1,69 − 0,01·z.
    func dn160Sahna(normalBilan: Bool = true, quvurBor: Bool = true) -> Sahna {
        var s = Sahna(sigma: 0.005, normalBilan: normalBilan, urug: 11)
        let r = 0.08
        let tub: (Double) -> Double = { z in -1.85 + 0.01 * z }
        s.transheya(kenglik: 0.8, uzunlik: 4, tub: tub, yashirin: { x, _ in quvurBor && abs(x) < r })
        if quvurBor {
            s.quvur(bosh: Vektor3(0, tub(0.2) + r, 0.2), yonalish: Vektor3(0, 0.01, 1), uzunlik: 3.6, radius: { _ in r })
        }
        s.axlat(s.nuqtalar.count / 10, min: Vektor3(-0.4, -1.9, 0), max: Vektor3(0.4, 0, 4))
        return s
    }

    func testBittaQuvurDN160() throws {
        let s = dn160Sahna()
        let q = QuvurTopish().topish(s.nuqtalar)
        XCTAssertEqual(q.count, 1, "aynan bitta quvur")
        let p = try XCTUnwrap(q.first)
        XCTAssertEqual(p.standart?.tashqiMm, 160)
        XCTAssertEqual(p.tashqiDiametrMm, 160, accuracy: 10, "diametr ≤ 1 sm")
        // o'q aniqligi: har bir uch haqiqiy o'qdan ≤ 1,5 sm
        let haqiqiyBosh = Vektor3(0, -1.85 + 0.002 + 0.08, 0.2), yo = Vektor3(0, 0.01, 1)
        for u in p.oq { XCTAssertLessThan(chiziqMasofa(u, haqiqiyBosh, yo), 0.015) }
        XCTAssertEqual(p.qiyalikFoiz, 1.0, accuracy: 0.3)
        XCTAssertEqual(p.uzunlikM, 3.6, accuracy: 0.1)
        XCTAssertGreaterThan(p.oq.first!.y, p.oq.last!.y, "oq oqim bo'yicha: balanddan pastga")
        let ch = try XCTUnwrap(p.qoplamaChuqurligiM, "yer sirti skanda bor — chuqurlik hisoblanishi shart")
        XCTAssertEqual(ch, 1.67, accuracy: 0.03)
        for st in p.chuqurlikStansiyalari {
            XCTAssertEqual(st.chuqurlikM, 1.69 - 0.01 * st.nuqta.z, accuracy: 0.03)
        }
        XCTAssertTrue(p.muftalar.isEmpty, "muftasiz quvurda soxta mufta bo'lmasin")
        XCTAssertGreaterThan(p.ishonch, 0.7)
        XCTAssertGreaterThanOrEqual(p.yoyGrad, 150)
    }

    func testQuvursizSahnadaSoxtaQuvurYoq() {
        let s = dn160Sahna(quvurBor: false)
        let q = QuvurTopish().topish(s.nuqtalar)
        XCTAssertEqual(q.count, 0, "tekisliklar, devor-tub burchagi va axlatdan quvur 'o'ylab topilmasin': \(q.map { $0.tashqiDiametrMm })")
    }

    func testIkkiQuvurYonmaYon() {
        var s = Sahna(sigma: 0.005, urug: 21)
        let tub: (Double) -> Double = { _ in -1.6 }
        s.transheya(kenglik: 0.9, uzunlik: 4, tub: tub, yashirin: { x, _ in abs(x + 0.2) < 0.055 || abs(x - 0.18) < 0.08 })
        s.quvur(bosh: Vektor3(-0.2, -1.6 + 0.055, 0.3), yonalish: Vektor3(0, 0, 1), uzunlik: 3.4, radius: { _ in 0.055 })
        s.quvur(bosh: Vektor3(0.18, -1.6 + 0.08, 0.2), yonalish: Vektor3(0, 0, 1), uzunlik: 3.6, radius: { _ in 0.08 })
        s.axlat(s.nuqtalar.count / 10, min: Vektor3(-0.45, -1.65, 0), max: Vektor3(0.45, 0, 4))
        let q = QuvurTopish().topish(s.nuqtalar)
        XCTAssertEqual(q.count, 2)
        XCTAssertEqual(Set(q.compactMap { $0.standart?.tashqiMm }), [110, 160])
        for p in q {
            let x = p.standart?.tashqiMm == 110 ? -0.2 : 0.18
            for u in p.oq { XCTAssertEqual(u.x, x, accuracy: 0.015) }
        }
    }

    func testEgilganQuvurBittaPolilinya() throws {
        var s = Sahna(sigma: 0.005, urug: 31)
        let r = 0.055, y0 = -1.5 + r
        let burilish = Vektor3(0, y0, 2.0)
        let d2 = Vektor3(sin(30 * Double.pi / 180), 0, cos(30 * Double.pi / 180))
        for z in stride(from: -0.5, through: 4.2, by: 0.025) {
            for x in stride(from: -0.6, through: 1.6, by: 0.025) { s.qosh(Vektor3(x, -1.5, z), Sahna.yuqori) }
        }
        s.quvur(bosh: Vektor3(0, y0, 0), yonalish: Vektor3(0, 0, 1), uzunlik: 2.0, radius: { _ in r })
        s.quvur(bosh: burilish, yonalish: d2, uzunlik: 2.0, radius: { _ in r })
        s.axlat(3000, min: Vektor3(-0.6, -1.5, -0.5), max: Vektor3(1.6, -1.0, 4.2))
        let q = QuvurTopish().topish(s.nuqtalar)
        XCTAssertEqual(q.count, 1, "ikki segment bitta quvurga ulanishi kerak")
        let p = try XCTUnwrap(q.first)
        XCTAssertEqual(p.oq.count, 3)
        XCTAssertLessThan(p.oq[1].masofa(burilish), 0.05, "burilish nuqtasi ≤ 5 sm")
        XCTAssertEqual(p.standart?.tashqiMm, 110)
        XCTAssertEqual(p.uzunlikM, 4.0, accuracy: 0.12)
    }

    func testMuftaNomzodi() throws {
        var s = Sahna(sigma: 0.004, urug: 41)
        let r = 0.055
        s.transheya(kenglik: 0.7, uzunlik: 4, tub: { _ in -1.4 }, yashirin: { x, _ in abs(x) < r })
        let muftaS = 2.0
        s.quvur(bosh: Vektor3(0, -1.4 + r, 0.1), yonalish: Vektor3(0, 0, 1), uzunlik: 3.8,
                radius: { t in abs(t - muftaS) < 0.07 ? r + 0.012 : r })
        s.axlat(s.nuqtalar.count / 20, min: Vektor3(-0.35, -1.45, 0), max: Vektor3(0.35, 0, 4))
        let q = QuvurTopish().topish(s.nuqtalar)
        let p = try XCTUnwrap(q.first)
        XCTAssertEqual(p.standart?.tashqiMm, 110)
        let haqiqiy = Vektor3(0, -1.4 + r, 0.1 + muftaS)
        let eng = try XCTUnwrap(p.muftalar.min { $0.masofa(haqiqiy) < $1.masofa(haqiqiy) }, "mufta topilishi shart")
        XCTAssertLessThan(abs(eng.z - haqiqiy.z), 0.05)
        XCTAssertEqual(p.muftalar.count, 1)
    }

    func testNormalsizBulut() throws {
        let s = dn160Sahna(normalBilan: false)
        let q = QuvurTopish().topish(s.nuqtalar)
        let p = try XCTUnwrap(q.first)
        XCTAssertEqual(q.count, 1)
        XCTAssertEqual(p.standart?.tashqiMm, 160)
        XCTAssertEqual(p.tashqiDiametrMm, 160, accuracy: 15)
        let haqiqiyBosh = Vektor3(0, -1.85 + 0.002 + 0.08, 0.2), yo = Vektor3(0, 0.01, 1)
        for u in p.oq { XCTAssertLessThan(chiziqMasofa(u, haqiqiyBosh, yo), 0.02) }
    }

    func testUrugNuqtaTanlanganQuvur() throws {
        var s = Sahna(sigma: 0.005, urug: 51)
        s.transheya(kenglik: 0.9, uzunlik: 4, tub: { _ in -1.6 }, yashirin: { x, _ in abs(x + 0.2) < 0.055 || abs(x - 0.18) < 0.08 })
        s.quvur(bosh: Vektor3(-0.2, -1.545, 0.3), yonalish: Vektor3(0, 0, 1), uzunlik: 3.4, radius: { _ in 0.055 })
        s.quvur(bosh: Vektor3(0.18, -1.52, 0.2), yonalish: Vektor3(0, 0, 1), uzunlik: 3.6, radius: { _ in 0.08 })
        // operator DN110 ning ustini bosdi
        let q = QuvurTopish().topish(s.nuqtalar, urugNuqta: Vektor3(-0.2, -1.545 + 0.055, 1.5))
        XCTAssertEqual(q.count, 1)
        XCTAssertEqual(try XCTUnwrap(q.first).standart?.tashqiMm, 110)
    }

    func testDeterministik() {
        let s = dn160Sahna()
        let a = QuvurTopish().topish(s.nuqtalar), b = QuvurTopish().topish(s.nuqtalar)
        XCTAssertEqual(a.count, b.count)
        XCTAssertEqual(a.first?.oq, b.first?.oq)
    }

    func testStandartDiametr() {
        // 158 mm ga eng yaqini po'lat 159 — shuning uchun tarmoq turi (qator) muhim
        XCTAssertEqual(StandartDiametrlar.moslash(158), StandartDiametr(seriya: "Po'lat", tashqiMm: 159))
        XCTAssertEqual(StandartDiametrlar.moslash(158, seriyalar: StandartDiametrlar.seriyalar(tarmoqTuri: "suv")),
                       StandartDiametr(seriya: "PE/PVX", tashqiMm: 160))
        XCTAssertEqual(StandartDiametrlar.moslash(107)?.tashqiMm, 108, "eng yaqini po'lat 108")
        XCTAssertEqual(StandartDiametrlar.moslash(107, seriyalar: [("PE/PVX", StandartDiametrlar.pePvx)])?.tashqiMm, 110)
        XCTAssertNil(StandartDiametrlar.moslash(700), "standartdan uzoq — faqat o'lchov ko'rsatiladi")
        XCTAssertEqual(StandartDiametrlar.moslash(64)?.tashqiMm, 63)
    }

    /// UI-17: bo'ylama profil — stansiya 0 yuqori uchda, gorizontal uzunlik, yer sirti y≈0, quvur usti = markaz + r.
    func testBoylamaProfil() throws {
        let q = try XCTUnwrap(QuvurTopish().topish(dn160Sahna().nuqtalar).first)
        let p = BoylamaProfil(q)
        XCTAssertEqual(p.oq.count, q.oq.count)
        XCTAssertEqual(p.oq.first?[0], 0)
        XCTAssertEqual(try XCTUnwrap(p.oq.last?[0]), 3.6, accuracy: 0.1, "gorizontal uzunlik")
        XCTAssertGreaterThan(p.oq.first![1], p.oq.last![1], "stansiya 0 — balandroq uch")
        XCTAssertEqual(p.oq.first![1] - p.oq.last![1], 0.036, accuracy: 0.012, "1 % nishab 3,6 m da")
        XCTAssertFalse(p.yer.isEmpty, "yer sirti skanda bor")
        for y in p.yer {
            XCTAssertEqual(y[1], 0, accuracy: 0.03, "sinov sahnasida yer sirti y=0")
            XCTAssertTrue((0...3.7).contains(y[0]))
        }
        XCTAssertEqual(try XCTUnwrap(p.quvurUsti(0)), p.oq[0][1] + q.radius, accuracy: 1e-9)
        let orta = try XCTUnwrap(p.quvurUsti(1.8))
        XCTAssertEqual(orta, -1.85 + 0.01 * 2.0 + 0.16, accuracy: 0.03, "o'rtadagi quvur usti")
        XCTAssertEqual(try XCTUnwrap(p.yer.first)[1] - (p.quvurUsti(p.yer.first![0]) ?? 0), 1.69 - 0.01 * 3.7, accuracy: 0.05,
                       "yer − quvur usti = qoplama chuqurligi")
        let saqlangan = BoylamaProfil(oq: p.oq, yer: p.yer, radius: p.radius)
        XCTAssertEqual(saqlangan, p, "ilova saqlagan massivlardan tiklangan profil bir xil")
        XCTAssertEqual(saqlangan.quvurUsti(1.8), p.quvurUsti(1.8))
    }
}
