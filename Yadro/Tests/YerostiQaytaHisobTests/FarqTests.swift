import XCTest
import YerostiGeometriya
@testable import YerostiQaytaHisob

/// KU-04: M3C2 usuli — tekis sirt 5 sm ko'tarilsa masofa +5 sm (ahamiyatli), o'zgarmagan joy LoD ichida (ahamiyatsiz).
final class FarqTests: XCTestCase {
    func sirt(_ ko: (Double, Double) -> Double, shovqin: Double, urug: UInt64) -> [Vektor3] {
        var t = Tasodifiy(urug: urug)
        var P: [Vektor3] = []
        for i in 0...80 { for j in 0...80 {
            let x = Double(i) * 0.025, y = Double(j) * 0.025
            P.append(Vektor3(x, y, ko(x, y) + t.normal(sigma: shovqin)))
        } }
        return P
    }

    func testKotarilganQismAhamiyatli() {
        let A = sirt({ _, _ in 0 }, shovqin: 0.004, urug: 1)
        let B = sirt({ x, _ in x > 1.0 ? 0.05 : 0 }, shovqin: 0.004, urug: 2)
        var s = Farq.Sozlama()
        s.registratsiyaM = 0.0
        let (n, x) = Farq.hisobla(A, B, s)
        XCTAssertGreaterThan(x.baholangan, 100)
        // x < 0,8 — o'zgarmagan: |masofa| ≤ 1 sm, ahamiyatsiz; x > 1,2 — +5 sm, ahamiyatli
        let ozgarmagan = n.filter { $0.p[0] < 0.8 && $0.masofa != nil }
        let kotarilgan = n.filter { $0.p[0] > 1.2 && $0.masofa != nil }
        XCTAssertFalse(ozgarmagan.isEmpty); XCTAssertFalse(kotarilgan.isEmpty)
        // LoD95 ta'rifi bo'yicha o'zgarmagan joyning ~5 % i tasodifan "ahamiyatli" chiqishi mumkin — ≥ 90 % talab qilinadi
        XCTAssertTrue(ozgarmagan.allSatisfy { abs($0.masofa!) < 0.01 }, "\(ozgarmagan.prefix(3))")
        XCTAssertGreaterThan(Double(ozgarmagan.filter { !$0.ahamiyatli }.count) / Double(ozgarmagan.count), 0.9)
        XCTAssertTrue(kotarilgan.allSatisfy { abs($0.masofa! - 0.05) < 0.01 }, "\(kotarilgan.prefix(3))")
        XCTAssertGreaterThan(Double(kotarilgan.filter(\.ahamiyatli).count) / Double(kotarilgan.count), 0.9)
        XCTAssertLessThan(x.lod95OrtachaM, 0.01)
        XCTAssertEqual(x.maksAbsM, 0.05, accuracy: 0.012)
    }

    func testRegistratsiyaXatosiLoDniOshiradi() {
        let A = sirt({ _, _ in 0 }, shovqin: 0.004, urug: 3)
        let B = sirt({ _, _ in 0.015 }, shovqin: 0.004, urug: 4)   // 1,5 sm siljish
        var s = Farq.Sozlama()
        s.registratsiyaM = 0.0
        let aniq = Farq.hisobla(A, B, s)
        s.registratsiyaM = 0.02
        let qopol = Farq.hisobla(A, B, s)
        XCTAssertGreaterThan(aniq.xulosa.ahamiyatli, qopol.xulosa.ahamiyatli)   // 2 sm registratsiya xatosi 1,5 sm ni yashiradi
        XCTAssertEqual(aniq.xulosa.ortachaM, 0.015, accuracy: 0.003)
        XCTAssertEqual(qopol.xulosa.ahamiyatli, 0)
    }

    /// Mahalliy o'zgarish: 2×2 m sirtda 0,4 m lik (2,5 sm katakda 0,425 m) bo'lak 10 sm ko'tarilgan — ahamiyatli yadro nuqtalar
    /// ulushi < 5 % (eski "ulush > 5 %" qoidasi buni "o'zgarmagan" derdi). Dog' qoidasi: maydon ≥ 0,05 m² → OZGARISH.
    /// Kutilgan maydon ≈ 0,20 m²: silindr (d = 20 sm) chegarani ~1,5 sm yoyadi, yadro 5 sm katakda 9 × 9.
    func testMahalliyDogOzgarish() throws {
        let A = sirt({ _, _ in 0 }, shovqin: 0.004, urug: 11)
        let B = sirt({ x, y in (0.8...1.2).contains(x) && (0.8...1.2).contains(y) ? 0.10 : 0 }, shovqin: 0.004, urug: 12)
        let (_, x) = Farq.hisobla(A, B)   // standart sozlama: registratsiya 2 sm
        XCTAssertLessThan(x.ahamiyatliUlush, 0.05, "ulush qoidasi yolg'iz yetmasligi isboti")
        XCTAssertEqual(x.xulosa, "OZGARISH")
        XCTAssertEqual(x.dogMaydonM2, 0.20, accuracy: 0.05, "dog' maydoni (yadro ikki qavat bo'lsa ham)")
        XCTAssertEqual(x.dogOrtachaM, 0.10, accuracy: 0.03)
        let m = try XCTUnwrap(x.dogMarkaz)
        XCTAssertEqual(m[0], 1.0, accuracy: 0.05); XCTAssertEqual(m[1], 1.0, accuracy: 0.05)
        XCTAssertEqual(x.p95AhamiyatliAbsM, 0.10, accuracy: 0.02)
        XCTAssertEqual(x.dogP95AbsM, 0.10, accuracy: 0.02, "3D shkalasi asosiy dog' bo'yicha")
    }

    /// Quvur 5 sm yonga surilgan (Ø160, tub ustida): ko'p masshtabli normal quvur yonida o'q yo'nalishiga tik chiqadi va
    /// siljishni ko'radi (+x yonda musbat, −x yonda manfiy dog'). 30 sm yagona sferada normal tubga og'ib, siljish ko'rinmasdi.
    func testQuvurYongaSurilgan() throws {
        func sahna(_ dx: Double, _ urug: UInt64) -> [Vektor3] {
            var t = Tasodifiy(urug: urug)
            var P: [Vektor3] = []
            let r = 0.08
            for i in 0...160 {
                let y = Double(i) * 0.0125
                for k in 0...64 {   // quvurning yuqori 200° i
                    let th = (-100.0 + Double(k) * 200.0 / 64) * Double.pi / 180
                    let rr = r + t.normal(sigma: 0.003)
                    P.append(Vektor3(dx + rr * sin(th), y, r + rr * cos(th)))
                }
                for j in 0...48 {   // tub z = 0, quvur ostidan tashqari
                    let x = -0.6 + Double(j) * 0.025
                    if abs(x - dx) > r { P.append(Vektor3(x, y, t.normal(sigma: 0.003))) }
                }
            }
            return P
        }
        let (n, x) = Farq.hisobla(sahna(0, 31), sahna(0.05, 32))
        XCTAssertEqual(x.xulosa, "OZGARISH")
        let yon = n.filter { $0.p[2] > 0.05 && $0.p[2] < 0.11 && $0.p[0] > 0.06 && $0.masofa != nil }   // +x yon sirt
        XCTAssertGreaterThan(yon.count, 20)
        let ortacha = yon.map { $0.masofa! * ($0.n[0] >= 0 ? 1 : -1) }.reduce(0, +) / Double(yon.count)
        XCTAssertEqual(ortacha, 0.05, accuracy: 0.015, "yon sirtda normal bo'ylab ≈ 5 sm")
        XCTAssertGreaterThan(Double(yon.filter(\.ahamiyatli).count) / Double(yon.count), 0.8)
    }

    /// Tor transheya (0,8 m): devor yadro nuqtasining silindri qarshi devorga yetmasligi kerak (1 m chuqurlikda yetib,
    /// σ va LoD ni o'nlab sm ga shishirardi). O'zgarmagan sahna — OZGARMAGAN, devorlarda LoD95 < 5 sm.
    func testTorTransheyaQarshiDevor() {
        func transheya(_ urug: UInt64) -> [Vektor3] {
            var t = Tasodifiy(urug: urug)
            var P: [Vektor3] = []
            for i in 0...80 {
                let y = Double(i) * 0.025
                for j in 0...60 { let z = -1.5 + Double(j) * 0.025
                    P.append(Vektor3(t.normal(sigma: 0.004), y, z)); P.append(Vektor3(0.8 + t.normal(sigma: 0.004), y, z)) }
                for j in 1...31 { P.append(Vektor3(Double(j) * 0.025, y, -1.5 + t.normal(sigma: 0.004))) }
            }
            return P
        }
        let (n, x) = Farq.hisobla(transheya(21), transheya(22))
        XCTAssertEqual(x.xulosa, "OZGARMAGAN")
        let devor = n.filter { ($0.p[0] < 0.05 || $0.p[0] > 0.75) && $0.p[2] > -1.2 && $0.lod95 != nil }
        XCTAssertGreaterThan(devor.count, 100)
        XCTAssertGreaterThan(Double(devor.filter { $0.lod95! < 0.05 }.count) / Double(devor.count), 0.95,
                             "devor LoD95 o'rtacha \(devor.map { $0.lod95! }.reduce(0, +) / Double(devor.count))")
    }

    func testPLYvaJSON() throws {
        let A = sirt({ _, _ in 0 }, shovqin: 0.003, urug: 5)
        let (n, x) = Farq.hisobla(A, A)
        let d = Farq.ply(n)
        XCTAssertTrue(String(decoding: d.prefix(200), as: UTF8.self).contains("property float farq"))
        let j = String(decoding: try Farq.json(x), as: UTF8.self)
        XCTAssertTrue(j.contains("\"yadro_soni\"") && j.contains("\"p95_abs_m\"") && j.contains("\"dog_maydon_m2\"")
                      && j.contains("\"xulosa\":\"OZGARMAGAN\""), j)
        XCTAssertEqual(x.ortachaAbsM, 0, accuracy: 1e-9)
    }
}
