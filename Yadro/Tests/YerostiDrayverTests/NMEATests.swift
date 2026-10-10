import XCTest
@testable import YerostiDrayver
import YerostiGeometriya

final class NMEATests: XCTestCase {
    func testMashhurGGA() throws {
        let g = try NMEAGap.ajrat("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47")
        XCTAssertEqual(g.talker, "GP"); XCTAssertEqual(g.turi, "GGA")
        let gga = GGA(g)!
        XCTAssertEqual(gga.lat!, 48.1173, accuracy: 1e-6)
        XCTAssertEqual(gga.lon!, 11.5166667, accuracy: 1e-6)
        XCTAssertEqual(gga.rtk, .gps); XCTAssertEqual(gga.sputnikSoni, 8)
        XCTAssertEqual(gga.balandlikMSL!, 545.4, accuracy: 1e-9)
        XCTAssertEqual(gga.balandlikEllipsoid!, 592.3, accuracy: 1e-9)
        XCTAssertNil(gga.tuzatmaYoshiS)
    }

    func testKontrolSumma() {
        XCTAssertThrowsError(try NMEAGap.ajrat("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*48")) {
            XCTAssertEqual($0 as? NMEAXato, .kontrolSummaMosEmas)
        }
        XCTAssertThrowsError(try NMEAGap.ajrat("GPGGA,1*00"))
        XCTAssertThrowsError(try NMEAGap.ajrat("$GPGGA,1"))
    }

    func testYasaVaAjrat() throws {
        let s = NMEAGap.yasa("GNGGA,101010.00,4006.948,N,06750.532,E,4,27,0.6,350.10,M,-40.2,M,1.0,0001")
        XCTAssertTrue(s.hasPrefix("$GNGGA,") && s.contains("*"))
        guard case .gga(let g) = try NMEAXabar.ajrat(s) else { return XCTFail("GGA kutilgan") }
        XCTAssertEqual(g.rtk, .fix)
        XCTAssertEqual(g.tuzatmaYoshiS, 1.0); XCTAssertEqual(g.bazaID, "0001")
        XCTAssertEqual(g.lat!, 40 + 6.948 / 60, accuracy: 1e-9)
        XCTAssertEqual(g.lon!, 67 + 50.532 / 60, accuracy: 1e-9)
        XCTAssertEqual(g.balandlikEllipsoid!, 309.9, accuracy: 1e-9)
    }

    func testGST() throws {
        guard case .gst(let s) = try NMEAXabar.ajrat(NMEAGap.yasa("GNGST,101010.00,0.012,0.010,0.008,30.0,0.009,0.007,0.020")) else { return XCTFail() }
        XCTAssertEqual(s.sigmaHSm!, 1.1402, accuracy: 1e-3)
        XCTAssertEqual(s.sigmaVSm!, 2.0, accuracy: 1e-9)
    }

    func testRMCvaHDT() throws {
        guard case .rmc(let r) = try NMEAXabar.ajrat(NMEAGap.yasa("GNRMC,101010.00,A,4006.948,N,06750.532,E,0.02,0.0,260926,,,R,V")) else { return XCTFail() }
        XCTAssertTrue(r.faol); XCTAssertEqual(r.sanaISO, "2026-09-26")
        guard case .hdt(let h) = try NMEAXabar.ajrat(NMEAGap.yasa("GNHDT,123.4,T")) else { return XCTFail() }
        XCTAssertEqual(h.yonalishDeg, 123.4)
        guard case .boshqa(let b) = try NMEAXabar.ajrat(NMEAGap.yasa("GNZDA,101010.00,26,09,2026,00,00")) else { return XCTFail() }
        XCTAssertEqual(b.turi, "ZDA")
    }

    func testJanubiyGarbiy() throws {
        guard case .gga(let g) = try NMEAXabar.ajrat(NMEAGap.yasa("GPGGA,1,3354.000,S,01824.000,W,4,10,1,0,M,0,M,1,0")) else { return XCTFail() }
        XCTAssertEqual(g.lat!, -33.9, accuracy: 1e-9); XCTAssertEqual(g.lon!, -18.4, accuracy: 1e-9)
    }
}
