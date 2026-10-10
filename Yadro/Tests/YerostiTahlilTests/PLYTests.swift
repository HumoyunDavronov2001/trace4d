import XCTest
@testable import YerostiTahlil
import YerostiGeometriya

final class PLYTests: XCTestCase {
    func testUTMKoordinatalarAniqlikniYoqotmaydi() throws {
        let bosh = Vektor3(401_234.0, 4_441_870.0, 350.0)
        let nuqtalar = (0..<500).map { i in
            BulutNuqtasi(bosh + Vektor3(Double(i) * 0.0123, 1.7 - Double(i) * 0.001, -1.85), n: Vektor3(0, 0, 1))
        }
        let d = PLY.yoz(nuqtalar, boshlangich: bosh)
        let o = try XCTUnwrap(PLY.oqi(d))
        XCTAssertEqual(o.nuqtalar.count, 500)
        XCTAssertEqual(o.boshlangich, bosh)
        for (a, b) in zip(nuqtalar, o.nuqtalar) { XCTAssertLessThan(a.p.masofa(b.p), 1e-5, "mm dan ancha yaxshi") }
        XCTAssertTrue(String(decoding: d.prefix(40), as: UTF8.self).hasPrefix("ply\nformat binary_little_endian 1.0\n"))
        XCTAssertEqual(d.count - d.range(of: Data("end_header\n".utf8))!.upperBound, 500 * 24)
    }
}
