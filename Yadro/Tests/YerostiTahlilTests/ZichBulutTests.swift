import XCTest
import YerostiGeometriya
import YerostiSimulyatsiya
@testable import YerostiTahlil

/// DS-06/07: LiDAR chuqurlik kadrlaridan zich rangli bulut. SUN'IY sahna (nur kesishuvi), haqiqiy skan emas.
final class ZichBulutTests: XCTestCase {
    func testKalitQaytadi() {
        for (i, j, k) in [(0, 0, 0), (-1, 2, -3), (1_000_000, -1_000_000, 524_287)] as [(Int64, Int64, Int64)] {
            let (a, b, c) = ZichBulut.indeks(ZichBulut.kalit(i, j, k))
            XCTAssertEqual([a, b, c], [i, j, k])
        }
    }

    /// Qabul mezoni (sun'iy): chuqurlik kadrlaridan Ø63 quvur topiladi, o'q xatosi ≤ 2 sm; rang va vaqt saqlanadi.
    func testO63ChuqurlikdanTopiladi() throws {
        let sahna = TransheyaSahnasi()
        var zb = ZichBulut()
        let t0 = Date()
        for k in sahna.yurish() { zb.qosh(k) }
        let nuqtalar = zb.nuqtalar()
        let birlashtirish = Date().timeIntervalSince(t0)
        var qs = QuvurTopishSozlamalari()
        qs.tarmoqTuri = "suv"
        let t1 = Date()
        let quvurlar = QuvurTopish(qs).topish(nuqtalar)
        print(String(format: "DS-06: %d kadr, %d piksel → %d nuqta (%.1f s), quvur topish %.1f s, topildi %d",
                     zb.kadrSoni, zb.piksellar, nuqtalar.count, birlashtirish, Date().timeIntervalSince(t1), quvurlar.count),
              quvurlar.map { "\($0.standart?.tashqiMm ?? $0.tashqiDiametrMm) mm, \(String(format: "%.2f", $0.uzunlikM)) m" })
        let q = try XCTUnwrap(quvurlar.first { ($0.standart?.tashqiMm ?? 0) == 63 }, "Ø63 topilmadi")
        let yc = sahna.quvurMarkazY
        let oqXato = q.oq.map { ((($0.y - yc) * ($0.y - yc) + ($0.z - sahna.quvurZ) * ($0.z - sahna.quvurZ))).squareRoot() }.max()!
        XCTAssertLessThanOrEqual(oqXato, 0.02, "o'q xatosi \(oqXato)")
        XCTAssertGreaterThan(q.uzunlikM, 4.5)

        // DS-07: quvur sirtidagi nuqtalar ko'k (sahna rangi), yer jigarrang
        let quvurdagi = nuqtalar.filter { abs((($0.p.y - yc) * ($0.p.y - yc) + $0.p.z * $0.p.z).squareRoot() - sahna.quvurRadius) < 0.006 && $0.p.x > 0.5 && $0.p.x < 5.5 }
        XCTAssertGreaterThan(quvurdagi.count, 500)
        let kok = quvurdagi.filter { ($0.rang?.b ?? 0) > 150 && ($0.rang?.r ?? 255) < 90 }
        XCTAssertGreaterThan(Double(kok.count) / Double(quvurdagi.count), 0.8)
        XCTAssertTrue(nuqtalar.allSatisfy { $0.t != nil && $0.rang != nil })
        // vaqt: x = 3 m dagi nuqta kamera shu joydan o'tgan payt atrofida (kadr 0,2 s, yurish 15 s)
        let orta = nuqtalar.filter { abs($0.p.x - 3) < 0.05 && $0.p.y < -1.0 }.compactMap(\.t)
        let tOrta = orta.reduce(0, +) / Double(orta.count)
        XCTAssertEqual(tOrta, 1000 + 0.2 * 74 * (3.0 + 0.3) / 6.6, accuracy: 2.0)
    }

    func testPLYRangVaVaqtBilanQaytadi() throws {
        let n = [BulutNuqtasi(Vektor3(1, 2, 3), rang: Rang(10, 20, 30), t: 123_456.789_012),
                 BulutNuqtasi(Vektor3(-1, 0.5, 2), rang: Rang(255, 0, 7), t: 123_457.5)]
        let d = PLY.yoz(n, boshlangich: Vektor3(1, 1, 1))
        let o = try XCTUnwrap(PLY.oqi(d))
        XCTAssertEqual(o.nuqtalar.count, 2)
        XCTAssertEqual(o.nuqtalar[0].rang, Rang(10, 20, 30))
        XCTAssertEqual(o.nuqtalar[1].rang, Rang(255, 0, 7))
        XCTAssertEqual(o.nuqtalar[0].t!, 123_456.789_012, accuracy: 1e-9)
        XCTAssertEqual(o.nuqtalar[1].p.x, -1, accuracy: 1e-6)
        // eski PLY (faqat x y z) ham o'qiladi
        let eski = PLY.yoz([BulutNuqtasi(Vektor3(1, 2, 3))])
        let e = try XCTUnwrap(PLY.oqi(eski))
        XCTAssertNil(e.nuqtalar[0].rang)
        XCTAssertNil(e.nuqtalar[0].t)
    }

    /// Past ishonchli va chegara piksellari olinmaydi.
    func testIshonchVaChegara() {
        let poza = PozaNamuna(t: 0, p: .nol, q: .birlik)
        var d = [Float](repeating: 1.0, count: 16 * 12)
        var c = [UInt8](repeating: 2, count: 16 * 12)
        for i in 0..<(16 * 6) { c[i] = 0 }         // yuqori yarmi past ishonch
        d[8 * 16 + 8] = 2.0                         // bitta keskin piksel — o'zi va qo'shnilari chegara
        var zb = ZichBulut()
        let k = ChuqurlikKadri(t: 0, en: 16, boy: 12, chuqurlik: d, ishonch: c, fx: 10, fy: 10, cx: 7.5, cy: 5.5, kamera: poza)
        let qoshildi = zb.qosh(k)
        // ichki piksellar 14×10 = 140; past ishonch qatorlari 1…5 (5×14 = 70); ularga qo'shni 6-qator ham (ikkinchi farq
        // hisoblanmaydi, 14); siluet: keskin piksel + 4 qo'shni = 5
        XCTAssertEqual(qoshildi, 140 - 70 - 14 - 5)
        // qiya tekislik (chuqurlik qatordan qatorga chiziqli o'sadi) siluet deb olinmaydi
        var q = [Float](repeating: 0, count: 16 * 12)
        for v in 0..<12 { for u in 0..<16 { q[v * 16 + u] = 1.0 + 0.03 * Float(v) + 0.02 * Float(u) } }
        var zb2 = ZichBulut()
        XCTAssertEqual(zb2.qosh(ChuqurlikKadri(t: 0, en: 16, boy: 12, chuqurlik: q, fx: 10, fy: 10, cx: 7.5, cy: 5.5, kamera: poza)), 140)
    }
}
