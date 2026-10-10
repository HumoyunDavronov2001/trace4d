import XCTest
import YerostiDrayver

/// DS-01: Reach qabul qilgichi iOS bilan mosligi; DS-02: dastak profili jadvali.
final class MoslikTests: XCTestCase {
    func testSeriya() {
        XCTAssertEqual(ReachMoslik.seriyadan("RX-00012500").model, .rxMFi)
        XCTAssertTrue(ReachMoslik.seriyadan("RX-00012500").iosMos)
        let eski = ReachMoslik.seriyadan("RX-00012414")
        XCTAssertEqual(eski.model, .rxEski)
        XCTAssertFalse(eski.iosMos)
        XCTAssertTrue(eski.izoh.contains("ISHLAMAYDI"))
        XCTAssertEqual(ReachMoslik.seriyadan("abc").model, .nomalum)
        XCTAssertEqual(ReachMoslik.seriyadan("123", model: "Reach RX2").model, .rx2)
    }

    func testAksessuar() {
        XCTAssertEqual(ReachMoslik.aksessuardan(nomi: "Reach RX2", model: "RX2", seriya: "1", protokollar: ["com.emlid.nmea"]).model, .rx2)
        XCTAssertEqual(ReachMoslik.aksessuardan(nomi: "Reach RX", model: "", seriya: "x9999", protokollar: ["com.emlid.nmea"]).model, .rxMFi)
        XCTAssertFalse(ReachMoslik.aksessuardan(nomi: "Boshqa", model: "", seriya: "", protokollar: ["com.x"]).iosMos)
    }

    func testDastakProfili() {
        let o = DastakProfillari.top(identifikator: "iPhone16,1", tomon: "chap")
        XCTAssertEqual(o?.ofset, [-0.072, 0.108, 0.028])
        XCTAssertEqual(o?.profil.tasdiqlangan, false, "manbada o'q yo'nalishi yo'q — avtomatik qo'llanmaydi")
        XCTAssertNil(DastakProfillari.top(identifikator: "iPhone99,9", tomon: "o'ng"))
    }
}
