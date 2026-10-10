import XCTest
@testable import YerostiDrayver
import YerostiGeometriya

final class SifatTests: XCTestCase {
    func testQoida() {
        XCTAssertEqual(SifatQoidasi.hisobla(rtk: .fix, sigmaHSm: 1.2, sigmaVSm: 3.0, tuzatmaYoshiS: 2), .rasmiy)
        XCTAssertEqual(SifatQoidasi.hisobla(rtk: .fix, sigmaHSm: 2.0, sigmaVSm: 5.0, tuzatmaYoshiS: 10), .rasmiy)
        XCTAssertEqual(SifatQoidasi.hisobla(rtk: .float, sigmaHSm: 0.5, sigmaVSm: 1.0, tuzatmaYoshiS: 1), .past)
        XCTAssertEqual(SifatQoidasi.hisobla(rtk: .fix, sigmaHSm: 2.01, sigmaVSm: 1.0, tuzatmaYoshiS: 1), .past)
        XCTAssertEqual(SifatQoidasi.hisobla(rtk: .fix, sigmaHSm: 1.0, sigmaVSm: 5.1, tuzatmaYoshiS: 1), .past)
        XCTAssertEqual(SifatQoidasi.hisobla(rtk: .fix, sigmaHSm: 1.0, sigmaVSm: 1.0, tuzatmaYoshiS: 10.5), .past)
        XCTAssertEqual(SifatQoidasi.hisobla(rtk: .fix, sigmaHSm: nil, sigmaVSm: 1.0, tuzatmaYoshiS: 1), .past, "isbotsiz → PAST")
        XCTAssertEqual(SifatQoidasi.hisobla(rtk: .fix, sigmaHSm: 1.0, sigmaVSm: 1.0, tuzatmaYoshiS: nil), .past)
    }

    func testHolatYigish() throws {
        var h = QabulQilgichHolati()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(h.eskirganmi(hozir: t0)); XCTAssertEqual(h.sifat(hozir: t0), .past)
        h.qabul(try NMEAXabar.ajrat(NMEAGap.yasa("GNGGA,101010.00,4006.948,N,06750.532,E,4,27,0.6,350.10,M,-40.2,M,1.0,0001")), hozir: t0)
        XCTAssertEqual(h.sifat(hozir: t0), .past, "GST kelmaguncha isbot yo'q")
        h.qabul(try NMEAXabar.ajrat(NMEAGap.yasa("GNGST,101010.00,0.012,0.010,0.008,30.0,0.009,0.007,0.020")), hozir: t0)
        XCTAssertEqual(h.sifat(hozir: t0), .rasmiy)
        XCTAssertEqual(h.sifat(hozir: t0.addingTimeInterval(3)), .past, "2 s dan eski GGA → ma'lumot yo'q")
        h.qabul(try NMEAXabar.ajrat(NMEAGap.yasa("GNGGA,101011.00,4006.948,N,06750.532,E,5,27,0.6,350.10,M,-40.2,M,1.0,0001")), hozir: t0.addingTimeInterval(1))
        XCTAssertEqual(h.rtk, .float); XCTAssertEqual(h.sifat(hozir: t0.addingTimeInterval(1)), .past)
        h.qabul(try NMEAXabar.ajrat(NMEAGap.yasa("GNGGA,101012.00,4006.948,N,06750.532,E,4,27,0.6,350.10,M,-40.2,M,15.0,0001")), hozir: t0.addingTimeInterval(2))
        XCTAssertEqual(h.sifat(hozir: t0.addingTimeInterval(2)), .past, "tuzatma yoshi 15 s")
        h.qabul(try NMEAXabar.ajrat(NMEAGap.yasa("GNGGA,101013.00,4006.948,N,06750.532,E,4,27,0.6,350.10,M,-40.2,M,1.0,0001")), hozir: t0.addingTimeInterval(5))
        XCTAssertEqual(h.sifat(hozir: t0.addingTimeInterval(5)), .past, "GST 5 s orqada qoldi → σ ishonchsiz")
    }

    func testNuqtaYozuviJSON() throws {
        var h = QabulQilgichHolati()
        let t0 = Date()
        h.qabul(try NMEAXabar.ajrat(NMEAGap.yasa("GNRMC,101010.00,A,4006.948,N,06750.532,E,0.02,0.0,260926,,,R,V")), hozir: t0)
        h.qabul(try NMEAXabar.ajrat(NMEAGap.yasa("GNGGA,101010.00,4006.948,N,06750.532,E,4,27,0.6,350.10,M,-40.2,M,1.0,0001")), hozir: t0)
        h.qabul(try NMEAXabar.ajrat(NMEAGap.yasa("GNGST,101010.00,0.012,0.010,0.008,30.0,0.009,0.007,0.020")), hozir: t0)
        let n = h.nuqta(chuqurlikM: 1.7, antennaBalandligiM: 2.0, qiyshayishDeg: 3.1, qurilmaSeriya: "RX2-0001", tuzatmaManbai: nil, hozir: t0)!
        XCTAssertEqual(n.sifat, .rasmiy)
        XCTAssertEqual(n.balandlik!, 307.9, accuracy: 1e-9, "antenna − vexa")
        XCTAssertEqual(n.vaqt, "2026-09-26T10:10:10Z")
        XCTAssertEqual(n.tuzatma_manbai, "0001", "manba berilmasa baza ID")
        let json = try JSONEncoder().encode(n)
        let lugat = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        for kalit in ["lat", "lon", "rtk_holat", "sigma_h_sm", "sigma_v_sm", "tuzatma_yoshi_s", "sputnik_soni",
                      "antenna_balandligi_m", "qiyshayish_deg", "qurilma_seriya", "chuqurlik_m", "vaqt"] {
            XCTAssertNotNil(lugat[kalit], "server kaliti yo'q: \(kalit)")
        }
        XCTAssertEqual(lugat["rtk_holat"] as? String, "FIX")
        XCTAssertNil(lugat["sifat"], "sifat serverda hisoblanadi, yuborilmaydi")
        let qayta = try JSONDecoder().decode(NuqtaYozuvi.self, from: json)
        XCTAssertEqual(qayta, n)
    }
}
