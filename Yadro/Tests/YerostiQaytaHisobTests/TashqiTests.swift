import XCTest
import YerostiGeometriya
import YerostiTahlil
@testable import YerostiQaytaHisob

/// LD-02: tashqi LiDAR buluti (UTM, z yuqori, muhrsiz) — quvur telefon yadrosi bilan topiladi, koordinatalar UTM/WGS84 da.
final class TashqiTests: XCTestCase {
    static let E0 = 362_300.0, N0 = 4_445_250.0, H0 = 400.0

    /// Sinov sahnasi (ARKit ramkasi) → UTM: E = E0 + x, N = N0 − z, H = H0 + y.
    static func utmPLY(surish: Vektor3 = .nol) -> (Data, tub: (Double) -> Double) {
        var sahna = SinovSahna(urug: 11)
        let r = 0.08
        let tub: (Double) -> Double = { z in -1.85 + 0.01 * z }
        sahna.transheya(kenglik: 0.8, uzunlik: 3, tub: tub, yashirin: { x, _ in abs(x) < r })
        sahna.quvur(bosh: Vektor3(0, tub(0) + r, 0), yonalish: Vektor3(0, 0.01, 1), uzunlik: 3, radius: r)
        let utm = sahna.nuqtalar.map { b in
            BulutNuqtasi(Vektor3(E0 + b.p.x, N0 - b.p.z, H0 + b.p.y) + surish, n: b.n.map { Vektor3($0.x, -$0.z, $0.y) })
        }
        return (PLY.yoz(utm, boshlangich: Vektor3(E0, N0, H0), izoh: "YEROSTI tashqi LiDAR"), tub)
    }

    func testTashqiBulutdanQuvurUTMda() throws {
        let (ply, tub) = Self.utmPLY()
        let (n, korinish) = QaytaHisob.aniqla(ply: [UInt8](ply), zona: 42, tarmoq: "suv", korinishMaks: 50_000)
        XCTAssertEqual(n.xulosa, "TASHQI")
        XCTAssertEqual(n.quvurlar.count, 1, n.sabablar.joined(separator: "; "))
        let q = try XCTUnwrap(n.quvurlar.first)
        XCTAssertEqual(q.standartMm ?? q.diametrMm, 160, accuracy: 10)
        XCTAssertGreaterThan(q.uzunlikM, 2.5)
        let utm = try XCTUnwrap(q.oqUtm)
        for p in utm {
            XCTAssertEqual(p[0], Self.E0, accuracy: 0.02)                      // o'q E0 ustida
            XCTAssertTrue(p[1] <= Self.N0 + 0.1 && p[1] >= Self.N0 - 3.1)      // shimolga qarab manfiy (ARKit z → −N)
            let z = Self.N0 - p[1]
            XCTAssertEqual(p[2], Self.H0 + tub(z) + 0.08, accuracy: 0.03)      // o'q balandligi
        }
        let w = try XCTUnwrap(q.oqWgs84)
        XCTAssertEqual(w.count, utm.count)
        XCTAssertEqual(w[0][0], 40.15, accuracy: 0.2)       // Jizzax atrofi
        XCTAssertNotNil(korinish)
        XCTAssertEqual(n.georef?.server?.utmZona, 42)
        XCTAssertTrue(n.ogohlantirishlar.contains { $0.contains("tashqi LiDAR") })
        XCTAssertEqual(n.jurnal?.tarmoq, "suv")
        // JSON — snake_case, ishchi o'qiydi
        let j = String(decoding: try QaytaHisob.json(n), as: UTF8.self)
        XCTAssertTrue(j.contains("\"oq_wgs84\"") && j.contains("\"xulosa\":\"TASHQI\""))
    }

    func testBoshBulutXato() {
        let bosh = PLY.yoz([], boshlangich: .nol)
        let (n, _) = QaytaHisob.aniqla(ply: [UInt8](bosh), zona: 42, tarmoq: nil)
        XCTAssertEqual(n.xulosa, "XATO")
        XCTAssertFalse(n.sabablar.isEmpty)
    }
}
