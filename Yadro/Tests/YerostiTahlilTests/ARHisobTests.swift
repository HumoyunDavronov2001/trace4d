import XCTest
@testable import YerostiTahlil
import YerostiGeometriya

final class ARHisobTests: XCTestCase {
    /// Sinov georeferensi: mahalliy ENU → UTM 42N (Jizzax atrofi), burilish 23°.
    let georef = GorizontalTransformatsiya(burchak: 23 * Double.pi / 180, t: Vektor3(401_230.0, 4_441_860.0, 350.0))

    func testGlobalMahalliyAylanma() {
        for p in [Vektor3(0, 0, 0), Vektor3(3.2, -1.7, -12.5), Vektor3(-40, 2, 25)] {
            let g = ARJoylashuv.global(p, georef: georef, zona: 42)
            let q = ARJoylashuv.mahalliy(lat: g.lat, lon: g.lon, h: g.h, georef: georef, zona: 42)
            XCTAssertLessThan(q.masofa(p), 0.001, "aylanma xatosi 1 mm dan kam: \(p)")
        }
    }

    func testTarmoqBalandliksizYerMinusChuqurlik() throws {
        let a = ARJoylashuv.global(Vektor3(0, -1.5, -2), georef: georef, zona: 42)
        let b = ARJoylashuv.global(Vektor3(0, -1.5, -8), georef: georef, zona: 42)
        let g = GlobalTarmoq(id: 7, turi: "suv", diametr_mm: 160, sifat: "RASMIY", nuqtalar: [
            .init(lat: a.lat, lon: a.lon, balandlik: a.h),                   // balandlik bor
            .init(lat: b.lat, lon: b.lon, chuqurlik_m: 1.4),                 // faqat chuqurlik
            .init(lat: b.lat, lon: b.lon)])                                   // hech narsa yo'q — tashlanadi
        let t = try XCTUnwrap(ARJoylashuv.tarmoq(g, georef: georef, zona: 42, yerBalandligi: { _, _ in 0.2 }))
        XCTAssertEqual(t.oq.count, 2)
        XCTAssertEqual(t.oq[0].y, -1.5, accuracy: 0.001)
        XCTAssertEqual(t.oq[1].y, 0.2 - 1.4 - 0.08, accuracy: 0.001, "yer − chuqurlik − r")
        XCTAssertEqual(t.oq[1].z, -8, accuracy: 0.001)
        XCTAssertNil(ARJoylashuv.tarmoq(g, georef: georef, zona: 42, yerBalandligi: { _, _ in nil }), "yer noma'lum — 1 nuqta qoladi")
    }

    /// z o'qi bo'ylab −20…0 m, yerdan 1,6 m chuqurlikda (o'q y = −1.6 − r) suv quvuri.
    func quvur(id: Int = 1, x: Double = 0, r: Double = 0.08) -> MahalliyTarmoq {
        MahalliyTarmoq(id: id, turi: "suv", diametrMm: Int(r * 2000), radius: r, sifat: "RASMIY",
                       oq: [Vektor3(x, -1.6 - r, 0), Vektor3(x, -1.6 - r, -20)])
    }

    func kvadrat(_ cx: Double, _ cz: Double, _ yarim: Double) -> [Vektor3] {
        [Vektor3(cx - yarim, 0, cz - yarim), Vektor3(cx + yarim, 0, cz - yarim),
         Vektor3(cx + yarim, 0, cz + yarim), Vektor3(cx - yarim, 0, cz + yarim)]
    }

    func testQazishXavfi() throws {
        let t = [quvur(id: 1, x: 0), quvur(id: 2, x: 3.0, r: 0.055), quvur(id: 3, x: 9.0)]
        // 1×1 m chuqur x=0.4 atrofida: 1-quvur kesib o'tadi, 2-quvur 2,1 m da (bufer tashqarisida), 3 uzoq
        let n = QazishXavfi.tekshir(poligon: kvadrat(0.4, -5, 0.5), tarmoqlar: t)
        XCTAssertEqual(n.map { $0.tarmoqId }, [1])
        let k = try XCTUnwrap(n.first)
        XCTAssertEqual(k.daraja, .kesishadi)
        XCTAssertEqual(k.chuqurlikM, 1.6, accuracy: 1e-9)
        XCTAssertTrue(k.faqatQolda)
        // chuqur x=1.6 da: 1-quvur 1,1 m da (bufer), 2-quvur 0,9 m da (bufer)
        let m = QazishXavfi.tekshir(poligon: kvadrat(1.6, -5, 0.5), tarmoqlar: t)
        XCTAssertEqual(m.map { $0.tarmoqId }, [2, 1])
        XCTAssertEqual(m[0].gorizontalMasofaM, 0.9, accuracy: 1e-9)
        XCTAssertEqual(m[1].gorizontalMasofaM, 1.1, accuracy: 1e-9)
        XCTAssertTrue(m.allSatisfy { $0.daraja == .buferda && $0.faqatQolda })
        // uzoqda — bo'sh
        XCTAssertTrue(QazishXavfi.tekshir(poligon: kvadrat(6, -5, 0.5), tarmoqlar: t).isEmpty)
    }

    func testNishonChapOngOstida() throws {
        let t = [quvur(id: 1, x: 0)]
        let oldi = Vektor3(0, 0, -1)  // kamera −z ga qarab turibdi → o'ng = +x
        let a = try XCTUnwrap(Nishon.top(yerNuqtasi: Vektor3(-0.42, 0, -6), kameraOldi: oldi, tarmoqlar: t))
        XCTAssertEqual(a.tomon, .ong); XCTAssertEqual(a.gorizontalMasofaM, 0.42, accuracy: 1e-9)
        XCTAssertEqual(a.chuqurlikM, 1.6, accuracy: 1e-9)
        let b = try XCTUnwrap(Nishon.top(yerNuqtasi: Vektor3(0.8, 0.1, -6), kameraOldi: oldi, tarmoqlar: t))
        XCTAssertEqual(b.tomon, .chap); XCTAssertEqual(b.chuqurlikM, 1.7, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Nishon.top(yerNuqtasi: Vektor3(0.02, 0, -6), kameraOldi: oldi, tarmoqlar: t)).tomon, .ostida)
        XCTAssertNil(Nishon.top(yerNuqtasi: Vektor3(7, 0, -6), kameraOldi: oldi, tarmoqlar: t), "5 m dan uzoq — ko'rsatilmaydi")
    }

    func testQoziqlarVaChuqurTubi() {
        let t = quvur(id: 1, x: 0)
        let q = ARChizish.qoziqlar(t, oraliq: 2, yerBalandligi: { _, _ in 0 })
        XCTAssertEqual(q.count, 11, "0, 2, …, 20 m")
        XCTAssertTrue(q.allSatisfy { abs($0.chuqurlikM - 1.6) < 1e-9 })
        XCTAssertEqual(ARChizish.chuqurTubi(markaz: Vektor3(0.2, 0, -5), tarmoqlar: [t]), -1.6 - 0.16 - 0.3, accuracy: 1e-9)
        XCTAssertEqual(ARChizish.chuqurTubi(markaz: Vektor3(5, 0, -5), tarmoqlar: [t]), -1.5, accuracy: 1e-9, "quvur yo'q — 1,5 m")
    }
}
