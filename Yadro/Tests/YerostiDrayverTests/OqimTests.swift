import XCTest
@testable import YerostiDrayver
import YerostiGeometriya

final class SinovTransport: NMEATransport {
    let nomi = "sinov"
    var qabulQilindi: ((Data) -> Void)?
    var ulangan = false
    var yuborilgan: [Data] = []
    func ulan() throws { ulangan = true }
    func uz() { ulangan = false }
    func yubor(_ data: Data) throws { yuborilgan.append(data) }
    func bering(_ s: String) { qabulQilindi?(Data(s.utf8)) }
}

final class OqimTests: XCTestCase {
    func testBolaklarVaAxlat() {
        let y = NMEAOqimYiguvchi()
        let gga = NMEAGap.yasa("GNGGA,101010.00,4006.948,N,06750.532,E,4,27,0.6,350.10,M,-40.2,M,1.0,0001")
        let a = y.qabul(Data(("\u{00}\u{FF}axlat" + gga.prefix(20)).utf8))
        XCTAssertTrue(a.isEmpty)
        let b = y.qabul(Data((String(gga.dropFirst(20)) + "\r\n$GNG").utf8))
        XCTAssertEqual(b, [gga])
        let c = y.qabul(Data("ST,1,2,3,4,5,6,7,8*00\n\n".utf8))
        XCTAssertEqual(c, ["$GNGST,1,2,3,4,5,6,7,8*00"])
    }

    func testDrayverOqimi() throws {
        let t = SinovTransport()
        let d = Drayver(transport: t)
        var chaqiruvlar = 0
        var satrlar: [String] = []
        d.holatOzgardi = { _ in chaqiruvlar += 1 }
        d.satrKeldi = { satrlar.append($0) }
        try d.ulan(); XCTAssertTrue(t.ulangan)
        t.bering(NMEAGap.yasa("GNGGA,101010.00,4006.948,N,06750.532,E,4,27,0.6,350.10,M,-40.2,M,1.0,0001") + "\r\n")
        t.bering("$GNGST,buzuq*00\r\n")   // kontrol summa xato — jurnalda qoladi, holatga tegmaydi
        t.bering(NMEAGap.yasa("GNGST,101010.00,0.012,0.010,0.008,30.0,0.009,0.007,0.020") + "\r\n")
        XCTAssertEqual(d.holat.rtk, .fix)
        XCTAssertEqual(d.holat.sifat(), .rasmiy)
        XCTAssertEqual(d.jurnal.satrlar.count, 3)
        XCTAssertEqual(chaqiruvlar, 3)
        XCTAssertTrue(d.jurnal.matn().contains("$GNGST,buzuq*00"))
        XCTAssertEqual(satrlar.count, 3, "buzuq satr ham muhr jurnaliga boradi")
        XCTAssertTrue(d.oxirgiGGASatri?.hasPrefix("$GNGGA,101010.00") == true)
        try d.ulan(); d.uz(); XCTAssertFalse(t.ulangan)
    }
}
