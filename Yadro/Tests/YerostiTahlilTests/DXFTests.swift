import XCTest
@testable import YerostiTahlil

/// DXF ni guruh-kod juftlariga ajratuvchi oddiy o'quvchi (sinov uchun).
func dxfJuftlar(_ s: String) -> [(Int, String)] {
    let q = s.components(separatedBy: "\n")
    var r: [(Int, String)] = []
    var i = 0
    while i + 1 < q.count {
        guard let k = Int(q[i].trimmingCharacters(in: .whitespaces)) else { break }
        r.append((k, q[i + 1])); i += 2
    }
    return r
}

final class DXFTests: XCTestCase {
    let liniyalar = [
        ChizmaLiniya(turi: "suv", diametrMm: 160, material: "PE100", sifat: "RASMIY", nuqtalar: [
            ChizmaNuqta(e: 401_230.123, n: 4_441_860.456, h: 348.21, chuqurlik: 1.69, sifat: "RASMIY"),
            ChizmaNuqta(e: 401_236.500, n: 4_441_871.000, h: 348.15, chuqurlik: 1.71, sifat: "RASMIY"),
            ChizmaNuqta(e: 401_240.000, n: 4_441_890.250, h: 348.02, chuqurlik: 1.74, sifat: "RASMIY"),
        ]),
        ChizmaLiniya(turi: "gaz", diametrMm: 110, material: "PE80", sifat: "SKAN", nuqtalar: [
            ChizmaNuqta(e: 401_228.0, n: 4_441_860.0, h: 348.9, chuqurlik: 1.05, sifat: "SKAN"),
            ChizmaNuqta(e: 401_229.0, n: 4_441_880.0, h: nil, chuqurlik: nil, sifat: "SKAN"),
        ]),
        ChizmaLiniya(turi: "suv", diametrMm: 63, material: "", sifat: "RASMIY", nuqtalar: [
            ChizmaNuqta(e: 1, n: 1, sifat: "RASMIY")]),  // 1 nuqtali — chizilmaydi
    ]

    func testTuzilishVaKoordinatalar() {
        let s = DXFChizma.yoz(liniyalar, sarlavha: ChizmaSarlavha(obyekt: "5-mavze suv tarmog‘i", order: "JZ-2026-0148",
                                                                   pudratchi: "Жиззах Сув Қурилиш", sana: "2026-09-27", muhr: "TASDIQLANGAN"))
        XCTAssertTrue(s.allSatisfy { $0.isASCII }, "R12 fayl faqat ASCII")
        let j = dxfJuftlar(s)
        XCTAssertEqual(j.first?.1, "SECTION")
        XCTAssertEqual(j.last?.1, "EOF")
        XCTAssertTrue(j.contains { $0 == (1, "AC1009") })
        let ob = j.filter { $0.0 == 0 }.map { $0.1 }
        XCTAssertEqual(ob.filter { $0 == "POLYLINE" }.count, 2, "1 nuqtali liniya chizilmaydi")
        XCTAssertEqual(ob.filter { $0 == "VERTEX" }.count, 5)
        XCTAssertEqual(ob.filter { $0 == "SEQEND" }.count, 2)
        XCTAssertEqual(ob.filter { $0 == "POINT" }.count, 5)
        // birinchi VERTEX koordinatalari (4 xona aniqlik)
        let v = j.firstIndex { $0 == (0, "VERTEX") }!
        XCTAssertEqual(j[v + 1].1, "TRACE4D_SUV")
        XCTAssertEqual(Double(j[v + 2].1)!, 401_230.123, accuracy: 1e-4)
        XCTAssertEqual(Double(j[v + 3].1)!, 4_441_860.456, accuracy: 1e-4)
        XCTAssertEqual(Double(j[v + 4].1)!, 348.21, accuracy: 1e-4)
        // SKAN liniyasi punktir
        let g = j.firstIndex { $0 == (8, "TRACE4D_GAZ") }!
        XCTAssertEqual(j[g + 1].1, "DASHED")
        // qatlamlar jadvali va o'giriq
        XCTAssertTrue(j.contains { $0 == (2, "TRACE4D_KANALIZATSIYA") })
        XCTAssertTrue(s.contains("Pudratchi: Jizzax Suv Qurilish"), "kirill → lotin")
        XCTAssertTrue(s.contains("Obyekt: 5-mavze suv tarmog'i"))
        XCTAssertTrue(s.contains("SUV D160 PE100 h=1.71"))
        XCTAssertTrue(s.contains("GAZ D110 PE80 h=1.05 (SKAN)"))
        XCTAssertTrue(s.contains("401240.000") || s.contains("401240.0000"))
        // $EXTMIN/$EXTMAX faqat chizilgan elementlardan: chizilmagan (1 nuqtali) liniya (1,1) chegarani buzmasin
        let e = j.firstIndex { $0 == (9, "$EXTMIN") }!
        XCTAssertGreaterThan(Double(j[e + 1].1)!, 401_000, "EXTMIN.x")
        XCTAssertGreaterThan(Double(j[e + 2].1)!, 4_441_000, "EXTMIN.y")
        let x = j.firstIndex { $0 == (9, "$EXTMAX") }!
        XCTAssertLessThan(Double(j[x + 1].1)! - Double(j[e + 1].1)!, 200, "kenglik — chizma + jadval")
    }

    /// DXF_CHIQISH berilsa — faylni yozadi (LibreOffice bilan tashqi tekshiruv uchun).
    func testFaylgaYozish() throws {
        guard let yol = ProcessInfo.processInfo.environment["DXF_CHIQISH"] else { return }
        let s = DXFChizma.yoz(liniyalar, sarlavha: ChizmaSarlavha(obyekt: "Format tekshiruvi", sana: "2026-09-27", muhr: "-"))
        try s.write(toFile: yol, atomically: true, encoding: .ascii)
    }

    func testKatalogCSV() {
        let c = DXFChizma.katalogCSV(liniyalar).split(separator: "\n")
        XCTAssertEqual(c.count, 1 + 5)
        XCTAssertEqual(c[1], "1;suv;160;401230.123;4441860.456;348.210;1.69;RASMIY")
        XCTAssertEqual(c[5], "5;gaz;110;401229.000;4441880.000;;;SKAN")
    }

    func testASCII() {
        XCTAssertEqual(DXFChizma.ascii("Тошкент ш., Ғалаба кўчаси"), "Toshkent sh., G'alaba ko'chasi")
        XCTAssertEqual(DXFChizma.ascii("Ø160 — «PE»"), "D160 - \"PE\"")
    }
}
