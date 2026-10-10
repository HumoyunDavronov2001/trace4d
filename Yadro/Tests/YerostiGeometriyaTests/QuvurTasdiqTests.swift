import XCTest
@testable import YerostiGeometriya

/// TQ: Swift tasdiq bahosi server `yerosti_tasdiq.py` bilan bir xil (sinov/tasdiq_sinov.py dagi qiymatlar).
final class QuvurTasdiqTests: XCTestCase {
    // L shaklli o'q: (0,0) → (30,0) → (30,30), h = 100, D 160 → radius 0,08
    let oq = [QuvurTasdiq.Nuqta(e: 0, n: 0, h: 100), QuvurTasdiq.Nuqta(e: 30, n: 0, h: 100), QuvurTasdiq.Nuqta(e: 30, n: 30, h: 100)]

    func testBaholashUstiVaOq() throws {
        let b = try XCTUnwrap(QuvurTasdiq.baholash(oq: oq, radiusM: 0.08, nuqta: .init(e: 10, n: 0.03, h: 100.10)))
        XCTAssertEqual(b.stansiya, 10, accuracy: 1e-9)
        XCTAssertEqual(b.dGor, 0.03, accuracy: 1e-9)
        XCTAssertEqual(b.dVer ?? 0, 0.02, accuracy: 1e-9)
        XCTAssertTrue(b.otdi)
        let c = try XCTUnwrap(QuvurTasdiq.baholash(oq: oq, radiusM: 0.08, nuqta: .init(e: 30, n: 30.2, h: 100.0), usti: false))
        XCTAssertEqual(c.stansiya, 60, accuracy: 1e-9)      // oxiridan tashqarida — oxiriga bog'lanadi
        XCTAssertEqual(c.dGor, 0.2, accuracy: 1e-9)
        XCTAssertFalse(c.otdi)
        XCTAssertTrue(c.sabab.contains("gorizontal"))
        let d = try XCTUnwrap(QuvurTasdiq.baholash(oq: oq, radiusM: 0.08, nuqta: .init(e: 5, n: 0.01, h: 100.20)))
        XCTAssertFalse(d.otdi)                              // vertikal +12 sm > 8
        XCTAssertTrue(d.sabab.contains("vertikal"))
    }

    func testBurilishVaHolat() throws {
        XCTAssertEqual(QuvurTasdiq.burilishlar(oq), [30])
        let b0 = try XCTUnwrap(QuvurTasdiq.baholash(oq: oq, radiusM: 0.08, nuqta: .init(e: 0.2, n: 0, h: 100.08)))
        let b60 = try XCTUnwrap(QuvurTasdiq.baholash(oq: oq, radiusM: 0.08, nuqta: .init(e: 30, n: 29.9, h: 100.08)))
        let qisman = QuvurTasdiq.holat(oq: oq, baholar: [b0, b60])
        XCTAssertEqual(qisman.holat, "qisman")
        XCTAssertEqual(qisman.kamchiliklar.count, 2)      // burilish yo'q + oraliq 59,7 m > 50
        XCTAssertTrue(qisman.kamchiliklar[0].contains("burilish (PK0+30,00)"))
        XCTAssertTrue(qisman.kamchiliklar[1].contains("> 50 m"))
        let b30 = try XCTUnwrap(QuvurTasdiq.baholash(oq: oq, radiusM: 0.08, nuqta: .init(e: 30.02, n: 0.3, h: 100.08)))
        let toliq = QuvurTasdiq.holat(oq: oq, baholar: [b0, b30, b60])
        XCTAssertEqual(toliq.holat, "tasdiqlangan")
        XCTAssertTrue(toliq.kamchiliklar.isEmpty)
        let yomon = try XCTUnwrap(QuvurTasdiq.baholash(oq: oq, radiusM: 0.08, nuqta: .init(e: 15, n: 0.4, h: 100.08)))
        XCTAssertEqual(QuvurTasdiq.holat(oq: oq, baholar: [b0, b30, b60, yomon]).holat, "farq")
        XCTAssertEqual(QuvurTasdiq.holat(oq: oq, baholar: [], skan: false).holat, "rtk")
        XCTAssertEqual(QuvurTasdiq.holat(oq: oq, baholar: []).holat, "yoq")
    }

    func testUzunLiniyaOraliq() throws {
        let uzun = [QuvurTasdiq.Nuqta(e: 0, n: 0, h: 50), QuvurTasdiq.Nuqta(e: 120, n: 0, h: 50)]
        let a = try XCTUnwrap(QuvurTasdiq.baholash(oq: uzun, radiusM: 0.1, nuqta: .init(e: 0, n: 0, h: 50.1)))
        let b = try XCTUnwrap(QuvurTasdiq.baholash(oq: uzun, radiusM: 0.1, nuqta: .init(e: 120, n: 0, h: 50.1)))
        let h = QuvurTasdiq.holat(oq: uzun, baholar: [a, b])
        XCTAssertEqual(h.holat, "qisman")
        XCTAssertTrue(h.kamchiliklar.contains { $0.contains("120 m > 50 m") }, h.kamchiliklar.joined(separator: "|"))
        let c = try XCTUnwrap(QuvurTasdiq.baholash(oq: uzun, radiusM: 0.1, nuqta: .init(e: 60, n: 0.02, h: 50.1)))
        XCTAssertEqual(QuvurTasdiq.holat(oq: uzun, baholar: [a, b, c]).holat, "qisman")   // 60 m > 50
        let d = try XCTUnwrap(QuvurTasdiq.baholash(oq: uzun, radiusM: 0.1, nuqta: .init(e: 40, n: 0.02, h: 50.1)))
        let e = try XCTUnwrap(QuvurTasdiq.baholash(oq: uzun, radiusM: 0.1, nuqta: .init(e: 80, n: 0, h: 50.1)))
        XCTAssertEqual(QuvurTasdiq.holat(oq: uzun, baholar: [a, b, d, e]).holat, "tasdiqlangan")
    }

    func testEnuServerBilanBirXil() {
        let k = QuvurTasdiq.enu(lat0: 40.1151, lon0: 67.8421)
        let p = k(40.1161, 67.8431)
        // Python yerosti_tasdiq.enu: 0,001° shimol / sharq
        XCTAssertEqual(p.n, 111.03685, accuracy: 0.001)
        XCTAssertEqual(p.e, 85.25039, accuracy: 0.001)
    }
}

/// Burilish topish server `yerosti_ijro_geo._turlar` bilan bir xil: zich skan shovqini soxta burilish bermaydi, haqiqiy
/// 20° egilish bitta burilish (sinov/ijro_sinov.py dagi geometriya bilan).
final class QuvurTasdiqBurilishTests: XCTestCase {
    func testZichSkanShovqiniSoxtaBurilishBermaydi() {
        var g = SystemRandomNumberGenerator()
        _ = g
        // deterministik "shovqin": sin/cos aralashmasi, amplitudasi 1 sm (ijro_sinov: gauss σ 1 sm)
        let P: [QuvurTasdiq.Nuqta] = (0..<121).map { i in
            let s = Double(i) * 0.5
            return QuvurTasdiq.Nuqta(e: s, n: 0.01 * sin(Double(i) * 1.7) * cos(Double(i) * 0.37), h: 100 - s * 0.004)
        }
        XCTAssertEqual(QuvurTasdiq.burilishlar(P), [])
    }

    func testHaqiqiyEgilishBittaBurilish() {
        var P: [QuvurTasdiq.Nuqta] = []
        for i in 0..<81 {
            let s = Double(i) * 0.5
            if s <= 20 { P.append(.init(e: s, n: 0, h: 100)) } else {
                let a = 20.0 * .pi / 180
                P.append(.init(e: 20 + (s - 20) * cos(a), n: (s - 20) * sin(a), h: 100))
            }
        }
        let b = QuvurTasdiq.burilishlar(P)
        XCTAssertEqual(b.count, 1, "\(b)")
        XCTAssertEqual(b.first ?? 0, 20, accuracy: 1.0)
    }

    func testSiyrakRTKNuqtalariLShakl() {
        // siyrak RTK nuqtalari (qo'shnilar 1 m dan uzoq) — qo'shnilar bilan hisoblanadi
        let P = [QuvurTasdiq.Nuqta(e: 0, n: 0), .init(e: 10, n: 0), .init(e: 20, n: 0), .init(e: 20, n: 10), .init(e: 20, n: 20)]
        XCTAssertEqual(QuvurTasdiq.burilishlar(P), [20])
    }
}
