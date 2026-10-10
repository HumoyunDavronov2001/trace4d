import XCTest
@testable import YerostiGeometriya

final class UTMTests: XCTestCase {
    func testZona() {
        XCTAssertEqual(UTM.zona(lon: 67.8422), 42)
        XCTAssertEqual(UTM.zona(lon: 69.25), 42)
        XCTAssertEqual(UTM.zona(lon: 72.0), 43)
        XCTAssertEqual(UTM.zona(lon: 65.99), 41)
    }

    func testMarkaziyMeridianVaEkvator() {
        let p = UTM.ga(lat: 40.0, lon: 69.0)
        XCTAssertEqual(p.x, 500_000, accuracy: 1e-6)
        let e = UTM.ga(lat: 0.0, lon: 66.5)
        XCTAssertEqual(e.y, 0, accuracy: 1e-6)
        XCTAssertLessThan(e.x, 500_000)
    }

    func testAylanmaAniqlik() {
        for (lat, lon) in [(40.1158, 67.8422), (41.3, 69.3), (39.65, 66.96), (-33.9, 18.4), (60.0, 71.9)] {
            let p = UTM.ga(lat: lat, lon: lon)
            let (l2, o2) = UTM.dan(p)
            // Krüger qatori 3 had: aylanma xato < 1e-8° (≈1 mm)
            XCTAssertEqual(l2, lat, accuracy: 1e-8, "lat \(lat)")
            XCTAssertEqual(o2, lon, accuracy: 1e-8, "lon \(lon)")
        }
    }

    func testMasshtabMarkaziyMeridianda() {
        let a = UTM.ga(lat: 40.0, lon: 69.0), b = UTM.ga(lat: 40.001, lon: 69.0)
        let utmMasofa = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
        let haqiqiy = UTM.meridianRadiusi(lat: 40.0005) * 0.001 * .pi / 180
        XCTAssertEqual(utmMasofa / haqiqiy, 0.9996, accuracy: 1e-6)
    }

    func testJizzaxMetrMasofaVaGridKonvergensiya() {
        // Parallel bo'ylab 100 m sharqqa: UTM masofa ≈ 100 m (masshtab ~1.0004),
        // shimoliy ustun grid konvergensiyasi γ ≈ Δλ·sin φ tufayli ~1.3 m o'zgaradi — bu XATO EMAS.
        let lat = 40.1158, lon = 67.8422
        let fi = lat * Double.pi / 180
        let e2 = UTM.f * (2 - UTM.f)
        let N = UTM.a / (1 - e2 * sin(fi) * sin(fi)).squareRoot()
        let dlon = 100 / (N * cos(fi)) * 180 / Double.pi
        let a = UTM.ga(lat: lat, lon: lon), b = UTM.ga(lat: lat, lon: lon + dlon)
        let masofa = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
        XCTAssertEqual(masofa, 100, accuracy: 0.1)
        let gamma = (lon - 69.0) * Double.pi / 180 * sin(fi)  // CM dan g'arbda manfiy
        XCTAssertEqual(b.y - a.y, 100 * tan(gamma), accuracy: 0.05)
        XCTAssertEqual(a.zona, 42); XCTAssertTrue(a.shimoliy)
    }
}

/// DXF-05: server (Python `yerosti_chizma.utm`) bilan bir xil nazorat qiymatlari — ≤ 1 mm.
final class UTMServerMoslikTests: XCTestCase {
    func testPythonBilanBirXil() {
        let nazorat: [(Double, Double, Double, Double)] = [
            (40.1158, 67.8422, 401_336.5326, 4_441_252.3786),
            (41.3111, 69.2797, 523_412.2580, 4_573_330.7733),
            (39.6542, 66.9597, 324_958.3376, 4_391_367.2861),
        ]
        for (lat, lon, e, n) in nazorat {
            let p = UTM.ga(lat: lat, lon: lon, zona: 42)
            XCTAssertEqual(p.x, e, accuracy: 0.001, "E \(lat),\(lon)")
            XCTAssertEqual(p.y, n, accuracy: 0.001, "N \(lat),\(lon)")
        }
    }
}
