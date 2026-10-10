import XCTest
@testable import YerostiMuhr

final class SHA256Tests: XCTestCase {
    func testNISTVektorlari() {
        XCTAssertEqual(SHA256.hex(SHA256.xesh([UInt8]())), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex(SHA256.xesh(Array("abc".utf8))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex(SHA256.xesh(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func testMillionA_BolaklabVaBirdan() {
        var s = SHA256()
        let bolak = [UInt8](repeating: 0x61, count: 1000)
        for _ in 0..<1000 { s.yangila(bolak) }
        XCTAssertEqual(SHA256.hex(s.yakunla()), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
        var t = SHA256()
        for x in [1, 63, 64, 65, 127, 999_680] { t.yangila([UInt8](repeating: 0x61, count: x)) }
        XCTAssertEqual(SHA256.hex(t.yakunla()), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
                       "noqulay bo'lak o'lchamlari (blok chegarasi atrofida)")
    }
}

final class ZanjirTests: XCTestCase {
    /// Kutilgan qiymatlar Python hashlib bilan mustaqil hisoblangan (server tekshiruvi bilan bir xil).
    func testPythonBilanBirXil() {
        XCTAssertEqual(SHA256.hex(MuhrZanjir.boshlangich), "723bd1030ec5952bb9e947e961a49eedc9a428df725956d5a485684637c71eeb")
        var z = MuhrZanjir()
        z.qosh(.nmea, matn: "$GNGGA,101010.00,4006.948,N,06750.532,E,4,27,0.6,350.10,M,-40.2,M,1.0,0001*6E")
        XCTAssertEqual(z.boshHex, "1e0964f321f7e52535d76c618c99bdfecd850c1a59ca7619d2e7924501d72cfd")
        z.qosh(.kadr, matn: #"{"t":1.25,"q":"RASMIY"}"#)
        XCTAssertEqual(z.boshHex, "e3f4500b3e985d0508bbdcc592a28195e5ea7e2794f6e8f9e70705a29a1c489e")
        z.qosh(.belgi, matn: "mufta · 1,72 m")
        XCTAssertEqual(z.boshHex, "0f0a29bb5ae912a371953f38c7a7464e95b570897f4fe4b1b6a242f285c513ea")
        z.qosh(.izoh, [])
        XCTAssertEqual(z.boshHex, "2715b38babe661140f7879821d13ebb9215171d5ee7ad60710feb4f1e6bb42f0")
        XCTAssertEqual(z.soni, 4)
    }

    func testJurnalTiklashVaBuzilishniSezish() {
        var z = MuhrZanjir()
        var jurnal = MuhrZanjir.jurnalSarlavha
        for i in 0..<200 { jurnal += z.qosh(i % 3 == 0 ? .nmea : .kadr, matn: "yozuv-\(i)-" + String(repeating: "x", count: i)) }
        let t = MuhrZanjir.tekshir(jurnal: jurnal)
        XCTAssertEqual(t?.boshHex, z.boshHex); XCTAssertEqual(t?.soni, 200)
        var buzuq = jurnal; buzuq[5000] ^= 0x20
        XCTAssertNotEqual(MuhrZanjir.tekshir(jurnal: buzuq)?.boshHex, z.boshHex, "bitta bit o'zgarsa muhr buziladi")
        XCTAssertNil(MuhrZanjir.tekshir(jurnal: Array(jurnal.dropLast(3))), "kesilgan jurnal qabul qilinmaydi")
        XCTAssertNil(MuhrZanjir.tekshir(jurnal: Array("XXXX".utf8) + jurnal.dropFirst(4)))
    }

    func testManifestKanonik() throws {
        let m = MuhrManifest(obyektId: 12, qurilma: "iPhone 17 Pro Max / RX2-0001", boshlandi: "2026-09-27T08:00:00Z",
                             tugadi: "2026-09-27T08:14:00Z", yozuvSoni: 4, zanjirBoshi: "2715b3",
                             fayllar: [.init(nomi: "jurnal.ymj", sha256: "ab", hajm: 10)])
        let s = String(decoding: try m.kanonik(), as: UTF8.self)
        XCTAssertEqual(s, #"{"boshlandi":"2026-09-27T08:00:00Z","fayllar":[{"hajm":10,"nomi":"jurnal.ymj","sha256":"ab"}],"#
            + #""obyekt_id":12,"qurilma":"iPhone 17 Pro Max / RX2-0001","tugadi":"2026-09-27T08:14:00Z","#
            + #""versiya":"YEROSTI-MUHR-v1","yozuv_soni":4,"zanjir_boshi":"2715b3"}"#)
    }
}
