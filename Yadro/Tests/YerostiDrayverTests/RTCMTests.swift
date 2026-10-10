import XCTest
@testable import YerostiDrayver
import YerostiGeometriya

/// RTCM 10403 standartidagi 1005 misoli (stansiya 2003). CRC va maydonlar Python bilan mustaqil tekshirilgan.
let standart1005: [UInt8] = [0xD3, 0x00, 0x13, 0x3E, 0xD7, 0xD3, 0x02, 0x02, 0x98, 0x0E, 0xDE, 0xEF, 0x34, 0xB4,
                             0xBD, 0x62, 0xAC, 0x09, 0x41, 0x98, 0x6F, 0x33, 0x36, 0x0B, 0x98]

struct BitYozuvchi {
    var b: [UInt8] = []
    var n = 0
    mutating func yoz(_ v: Int64, _ bitlar: Int) {
        let u = UInt64(bitPattern: v)
        for i in stride(from: bitlar - 1, through: 0, by: -1) {
            if n % 8 == 0 { b.append(0) }
            b[b.count - 1] |= UInt8((u >> UInt64(i)) & 1) << UInt8(7 - n % 8)
            n += 1
        }
    }
}

final class RTCMTests: XCTestCase {
    func testCRCStandartMisol() {
        XCTAssertEqual(RTCM3.crc24q(standart1005.prefix(22)), 0x360B98)
        XCTAssertEqual(RTCM3.ramka(Array(standart1005[3..<22])), standart1005)
    }

    func test1005Dekod() throws {
        let a = RTCM3Ajratuvchi()
        let r = a.qabul(standart1005)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].xabarRaqami, 1005)
        let b = try XCTUnwrap(RTCM3.bazaStansiya(r[0]))
        XCTAssertEqual(b.stansiyaID, 2003)
        XCTAssertEqual(b.ecef.x, 1114104.5999, accuracy: 1e-6)
        XCTAssertEqual(b.ecef.y, -4850729.7108, accuracy: 1e-6)
        XCTAssertEqual(b.ecef.z, 3975521.4643, accuracy: 1e-6)
        XCTAssertNil(b.antennaBalandligiM)
    }

    func testOqimdaAxlatVaBolaklar() {
        let a = RTCM3Ajratuvchi()
        let msm = RTCM3.ramka([0x43, 0x20, 0x00, 0x11])  // 1074
        let oqim: [UInt8] = [0x00, 0xD3, 0xFF, 0x12] + standart1005 + [0x0D, 0x0A, 0xD3] + msm + [0x55]
        var ramkalar: [RTCM3Ramka] = []
        for b in oqim { ramkalar += a.qabul([b]) }  // bittadan bayt
        XCTAssertEqual(ramkalar.map { $0.xabarRaqami }, [1005, 1074])
        XCTAssertEqual(a.tashlanganBaytlar, 8, "axlat baytlari: 00 D3 FF 12 + 0D 0A D3 + 55")
    }

    func testBuzilganRamkaTashlanadi() {
        var buzuq = standart1005; buzuq[10] ^= 0x01
        let a = RTCM3Ajratuvchi()
        XCTAssertTrue(a.qabul(buzuq).isEmpty)
        XCTAssertEqual(a.qabul(standart1005).count, 1, "keyingi to'g'ri ramka baribir o'qiladi")
    }

    func test1006JizzaxBazasi() throws {
        let e = Geodeziya.ecef(lat: 40.1300, lon: 67.8200, h: 395.0)
        var w = BitYozuvchi()
        w.yoz(1006, 12); w.yoz(77, 12); w.yoz(0, 6); w.yoz(1, 1); w.yoz(1, 1); w.yoz(1, 1); w.yoz(0, 1)
        w.yoz(Int64((e.x * 1e4).rounded()), 38); w.yoz(0, 1); w.yoz(0, 1)
        w.yoz(Int64((e.y * 1e4).rounded()), 38); w.yoz(0, 2)
        w.yoz(Int64((e.z * 1e4).rounded()), 38); w.yoz(15000, 16)
        let r = RTCM3Ajratuvchi().qabul(RTCM3.ramka(w.b))
        let b = try XCTUnwrap(RTCM3.bazaStansiya(r[0]))
        XCTAssertEqual(b.stansiyaID, 77)
        XCTAssertEqual(b.lat, 40.13, accuracy: 1e-7); XCTAssertEqual(b.lon, 67.82, accuracy: 1e-7)
        XCTAssertEqual(b.antennaBalandligiM!, 1.5, accuracy: 1e-9)
        XCTAssertEqual(b.masofaM(lat: 40.1158, lon: 67.8422, h: 395) / 1000, 2.44, accuracy: 0.05)
    }

    func testTuzatmaKuzatuvchi() {
        let k = TuzatmaKuzatuvchi()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let a = RTCM3Ajratuvchi()
        var bayt: [UInt8] = standart1005
        for raqam in [1074, 1084, 1094, 1124, 1230] {
            bayt += RTCM3.ramka([UInt8(raqam >> 4), UInt8((raqam & 0xF) << 4), 0x00])
        }
        k.qabul(a.qabul(bayt), baytSoni: bayt.count, vaqt: t0)
        XCTAssertEqual(k.tizimlar, ["GPS", "GLONASS", "Galileo", "BeiDou"])
        XCTAssertEqual(k.yoshiS(hozir: t0.addingTimeInterval(1.5))!, 1.5, accuracy: 1e-9)
        let km = k.bazaMasofasiKm(lat: 40.1158, lon: 67.8422)!
        XCTAssertGreaterThan(km, TuzatmaKuzatuvchi.bazaMasofaOgohKm, "standart misol bazasi AQShda — ogohlantirish kerak")
        XCTAssertEqual(k.xabarSoni[1005], 1)
    }
}
