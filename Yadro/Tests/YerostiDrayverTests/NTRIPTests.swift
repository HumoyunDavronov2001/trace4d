import XCTest
@testable import YerostiDrayver
import YerostiGeometriya

final class NTRIPTests: XCTestCase {
    func testSorovV2() {
        let s = NTRIPSozlama(host: "caster.example.uz", port: 2101, mountpoint: "JIZ0", login: "brigada1", parol: "p@ss", versiya: 2)
        let q = String(decoding: NTRIPSorov.mountpoint(s, gga: "$GNGGA,1*00"), as: UTF8.self)
        let kutilgan = "GET /JIZ0 HTTP/1.1\r\nHost: caster.example.uz:2101\r\nNtrip-Version: Ntrip/2.0\r\n"
            + "User-Agent: NTRIP YEROSTI/1.0\r\nAuthorization: Basic YnJpZ2FkYTE6cEBzcw==\r\n"
            + "Ntrip-GGA: $GNGGA,1*00\r\nConnection: close\r\n\r\n"
        XCTAssertEqual(q, kutilgan)
    }

    func testSorovV1LoginsizVaManbaJadvali() {
        let s = NTRIPSozlama(host: "h", mountpoint: "M", versiya: 1)
        XCTAssertEqual(String(decoding: NTRIPSorov.mountpoint(s), as: UTF8.self),
                       "GET /M HTTP/1.0\r\nUser-Agent: NTRIP YEROSTI/1.0\r\nAccept: */*\r\nConnection: close\r\n\r\n")
        XCTAssertTrue(String(decoding: NTRIPSorov.manbaJadvali(host: "h"), as: UTF8.self).hasPrefix("GET / HTTP/1.1\r\n"))
    }

    func testICYOqimBoshQatorsiz() {
        let j = NTRIPJavob()
        let rtcm: [UInt8] = [0xD3, 0x00, 0x02, 0x3E, 0xD0, 0x0D, 0x0A, 0x0D, 0x0A, 0x01]
        let a = j.qabul(Data("ICY 200 OK\r\n".utf8))
        XCTAssertEqual(j.holat, .oqim, "VRS caster GGA kutib jim turishi mumkin — 12 baytning o'zi yetarli")
        XCTAssertTrue(a.isEmpty)
        XCTAssertEqual(Array(j.qabul(Data(rtcm))), rtcm, "ikkilik ichidagi CRLFCRLF sarlavha deb olinmasin")
    }

    func testICYBoshQatorBilanBittaBolakda() {
        let j = NTRIPJavob()
        let chiq = j.qabul(Data("ICY 200 OK\r\n\r\n".utf8) + Data([0xD3, 0x01]))
        XCTAssertEqual(j.holat, .oqim)
        XCTAssertEqual(Array(chiq), [0xD3, 0x01])
    }

    func testHTTP2ChunkedBolaklab() {
        let j = NTRIPJavob()
        let butun = "HTTP/1.1 200 OK\r\nContent-Type: gnss/data\r\nTransfer-Encoding: chunked\r\n\r\n"
            + "5\r\nABCDE\r\n3;ext=1\r\nFGH\r\n0\r\n\r\n"
        var chiqish = Data()
        for b in Array(butun.utf8) { chiqish.append(j.qabul(Data([b]))) }  // har bayt alohida
        XCTAssertEqual(j.holatKodi, 200)
        XCTAssertEqual(String(decoding: chiqish, as: UTF8.self), "ABCDEFGH")
    }

    func testXatolar() {
        let a = NTRIPJavob(); _ = a.qabul(Data("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic\r\n\r\n".utf8))
        XCTAssertEqual(a.holat, .xato("login yoki parol noto'g'ri (401)"))
        let b = NTRIPJavob(); _ = b.qabul(Data("SOURCETABLE 200 OK\r\nContent-Type: text/plain\r\n\r\nSTR;".utf8))
        if case .xato(let x) = b.holat { XCTAssertTrue(x.contains("mountpoint topilmadi")) } else { XCTFail("xato kutilgan") }
        let c = NTRIPJavob(); _ = c.qabul(Data("HTTP/1.1 404 Not Found\r\n\r\n".utf8))
        XCTAssertEqual(c.holat, .xato("mountpoint topilmadi (404)"))
        let d = NTRIPJavob(); _ = d.qabul(Data("SALOM\r\n\r\n".utf8))
        if case .xato = d.holat {} else { XCTFail() }
    }

    func testManbaJadvaliVaEngYaqin() {
        let matn = """
        SOURCETABLE 200 OK\r
        CAS;caster.example.uz;2101;UZ;Kadastr;0;UZB;40.10;67.84;0.0.0.0;0;http://example\r
        STR;JIZ0;Jizzax;RTCM 3.3;1004(1),1005(10),1077(1);2;GPS+GLO+GAL+BDS;UzPOS;UZB;40.12;67.84;0;0;Trimble;none;B;N;9600;\r
        STR;TSH1;Toshkent;RTCM 3.2;1005(10),1074(1);2;GPS+GLO;UzPOS;UZB;41.31;69.28;0;0;Leica;none;B;N;9600;\r
        STR;VRS_JZ;Jizzax VRS;RTCM 3.3;MSM4;2;GPS+GLO+GAL;UzPOS;UZB;40.11;67.85;1;1;sNTRIP;none;B;N;9600;\r
        STR;OLD;Eski;RTCM 2.3;1(1);2;GPS;X;UZB;40.11;67.84;0;0;x;none;N;N;9600;\r
        NET;UzPOS;Kadastr;B;N;http://x;none;x@x;none\r
        ENDSOURCETABLE\r
        """
        let m = ManbaJadvali.ajrat(matn)
        XCTAssertEqual(m.count, 4)
        XCTAssertEqual(m[2].nomi, "VRS_JZ"); XCTAssertTrue(m[2].ggaKerak); XCTAssertTrue(m[2].tarmoqYechimi)
        let yaqin = ManbaJadvali.engYaqin(m, lat: 40.1158, lon: 67.8422)
        // JIZ0 (40.12, 67.84) ≈ 0,50 km; VRS_JZ (40.11, 67.85) ≈ 0,93 km; RTCM 2.3 chiqarib tashlanadi
        XCTAssertEqual(yaqin.map { $0.mountpoint.nomi }, ["JIZ0", "VRS_JZ", "TSH1"])
        XCTAssertEqual(yaqin[0].masofaKm, 0.50, accuracy: 0.05)
        XCTAssertEqual(yaqin[1].masofaKm, 0.93, accuracy: 0.05)
        XCTAssertEqual(yaqin[2].masofaKm, 185, accuracy: 15)

        let j = NTRIPJavob(mountpointSoralgan: false)
        _ = j.qabul(Data(matn.utf8))
        XCTAssertEqual(j.holat, .manbaJadvali)
        XCTAssertTrue(j.manbaJadvaliTugadi)
        XCTAssertEqual(ManbaJadvali.ajrat(j.manbaJadvaliMatni).count, 4)
    }
}
