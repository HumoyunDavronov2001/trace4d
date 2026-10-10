import XCTest
@testable import YerostiGeometriya

final class GeoreferensTests: XCTestCase {
    func aylantir(_ p: Vektor3, gradZ: Double, gradX: Double) -> Vektor3 {
        let a = gradZ * .pi / 180, b = gradX * .pi / 180
        let x1 = p.x * cos(a) - p.y * sin(a), y1 = p.x * sin(a) + p.y * cos(a), z1 = p.z
        return Vektor3(x1, y1 * cos(b) - z1 * sin(b), y1 * sin(b) + z1 * cos(b))
    }

    func testAniqTiklash() throws {
        let mahalliy = [Vektor3(0, 0, 0), Vektor3(4, 0, 0), Vektor3(0, 3, 0), Vektor3(2, 2, -1.5), Vektor3(5, 4, 0.3)]
        let t = Vektor3(401_230.5, 4_441_870.2, 350.4)
        let global = mahalliy.map { aylantir($0, gradZ: 30, gradX: 5) + t }
        let n = try Georeferens.hisobla(mahalliy: mahalliy, global: global)
        XCTAssertLessThan(n.rmsM, 1e-8)
        let sinov = Vektor3(1.5, -2.0, 0.7)
        let kutilgan = aylantir(sinov, gradZ: 30, gradX: 5) + t
        let olingan = n.transformatsiya.qolla(sinov)
        XCTAssertEqual(olingan.x, kutilgan.x, accuracy: 1e-7)
        XCTAssertEqual(olingan.y, kutilgan.y, accuracy: 1e-7)
        XCTAssertEqual(olingan.z, kutilgan.z, accuracy: 1e-7)
        // R ortogonal, det +1 (aks ettirish yo'q)
        let R = n.transformatsiya.R
        let det = R[0][0] * (R[1][1] * R[2][2] - R[1][2] * R[2][1]) - R[0][1] * (R[1][0] * R[2][2] - R[1][2] * R[2][0]) + R[0][2] * (R[1][0] * R[2][1] - R[1][1] * R[2][0])
        XCTAssertEqual(det, 1, accuracy: 1e-9)
    }

    func testShovqinliRMS() throws {
        let mahalliy = [Vektor3(0, 0, 0), Vektor3(6, 0, 0), Vektor3(0, 4, 0), Vektor3(6, 4, -2)]
        let shovqin = [Vektor3(0.01, -0.005, 0.008), Vektor3(-0.008, 0.01, -0.004), Vektor3(0.006, 0.007, -0.01), Vektor3(-0.009, -0.004, 0.006)]
        let global = zip(mahalliy, shovqin).map { aylantir($0, gradZ: -75, gradX: 2) + Vektor3(500, 600, 10) + $1 }
        let n = try Georeferens.hisobla(mahalliy: mahalliy, global: global)
        XCTAssertLessThan(n.rmsM, 0.02)
        XCTAssertGreaterThan(n.rmsM, 0.001)
        XCTAssertEqual(n.qoldiqlarM.count, 4)
        XCTAssertLessThan(n.rmsM, Georeferens.rmsChekM)
    }

    func testXatolar() {
        XCTAssertThrowsError(try Georeferens.hisobla(mahalliy: [Vektor3(0, 0, 0), Vektor3(1, 0, 0)], global: [Vektor3(0, 0, 0), Vektor3(1, 0, 0)])) {
            XCTAssertEqual($0 as? GeoreferensXato, .nuqtaYetarliEmas)
        }
        XCTAssertThrowsError(try Georeferens.hisobla(mahalliy: [Vektor3(0, 0, 0), Vektor3(1, 1, 1), Vektor3(2, 2, 2)], global: [Vektor3(0, 0, 0), Vektor3(1, 1, 1), Vektor3(2, 2, 2)])) {
            XCTAssertEqual($0 as? GeoreferensXato, .nuqtalarBirChiziqda)
        }
        XCTAssertThrowsError(try Georeferens.hisobla(mahalliy: [Vektor3(0, 0, 0), Vektor3(1, 0, 0), Vektor3(0, 1, 0)], global: [Vektor3(0, 0, 0)])) {
            XCTAssertEqual($0 as? GeoreferensXato, .sonlarMosEmas)
        }
    }
}

final class GeodeziyaTests: XCTestCase {
    func testRTCMNamunaBazasi() {
        // RTCM 10403 1005 namunasi: X=1114104.5999, Y=-4850729.7108, Z=3975521.4643
        let g = Geodeziya.geodezik(Vektor3(1114104.5999, -4850729.7108, 3975521.4643))
        let qayta = Geodeziya.ecef(lat: g.lat, lon: g.lon, h: g.h)
        XCTAssertEqual(qayta.x, 1114104.5999, accuracy: 1e-4)
        XCTAssertEqual(qayta.y, -4850729.7108, accuracy: 1e-4)
        XCTAssertEqual(qayta.z, 3975521.4643, accuracy: 1e-4)
        XCTAssertEqual(g.lon, -77.06, accuracy: 0.01)   // AQSh sharqi — standart misol
        XCTAssertEqual(g.lat, 38.8, accuracy: 0.2)
    }

    func testJizzaxAylanma() {
        let e = Geodeziya.ecef(lat: 40.1158, lon: 67.8422, h: 380.0)
        let g = Geodeziya.geodezik(e)
        XCTAssertEqual(g.lat, 40.1158, accuracy: 1e-9)
        XCTAssertEqual(g.lon, 67.8422, accuracy: 1e-9)
        XCTAssertEqual(g.h, 380.0, accuracy: 1e-4)
    }

    func testMasofa() {
        // meridian bo'ylab 0,1° ≈ 11,1 km
        let d = Geodeziya.masofa(lat1: 40.0, lon1: 67.8, lat2: 40.1, lon2: 67.8)
        XCTAssertEqual(d, 11_100, accuracy: 30)
    }
}

final class VektorTests: XCTestCase {
    func testXosTahlil() {
        var m = Matritsa3.nol
        m.tashqiQosh(Vektor3(1, 0, 0), vazn: 5)
        m.tashqiQosh(Vektor3(0, 1, 0), vazn: 2)
        m.tashqiQosh(Vektor3(0, 0, 1), vazn: 0.5)
        let x = m.xosTahlil()
        XCTAssertEqual(x[0].qiymat, 0.5, accuracy: 1e-12)
        XCTAssertEqual(abs(x[0].vektor.z), 1, accuracy: 1e-12)
        XCTAssertEqual(x[2].qiymat, 5, accuracy: 1e-12)
    }

    func testTasodifiyTakrorlanadi() {
        var a = Tasodifiy(urug: 7), b = Tasodifiy(urug: 7)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
        var c = Tasodifiy(urug: 1)
        let ortacha = (0..<20000).map { _ in c.normal(sigma: 2) }.reduce(0, +) / 20000
        XCTAssertEqual(ortacha, 0, accuracy: 0.05)
    }

    func testPerpendikulyarBazis() {
        for a in [Vektor3(0, 0, 1), Vektor3(1, 0, 0), Vektor3(0.3, -0.8, 0.52)] {
            let (e1, e2) = a.perpendikulyarBazis()
            XCTAssertEqual(e1.nuqta(a.birlik!), 0, accuracy: 1e-12)
            XCTAssertEqual(e2.nuqta(a.birlik!), 0, accuracy: 1e-12)
            XCTAssertEqual(e1.nuqta(e2), 0, accuracy: 1e-12)
            XCTAssertEqual(e1.uzunlik, 1, accuracy: 1e-12)
        }
    }
}

final class GravitatsiyaGeoreferensTests: XCTestCase {
    func testTogriYurishdanBurilishTopiladi() throws {
        var t = Tasodifiy(urug: 99)
        let yaw = 37.0 * Double.pi / 180
        let T = GorizontalTransformatsiya(burchak: yaw, t: Vektor3(401_234.5, 4_441_870.2, 350.4))
        var mahalliy: [Vektor3] = [], global: [Vektor3] = []
        for i in 0..<300 {
            // transheya bo'ylab 20 m deyarli to'g'ri yurish, ±5 sm chayqalish, qo'l balandligi o'zgarishi
            let s = Double(i) * 0.066
            let p = Vektor3(0.05 * sin(s * 3), s, 1.3 + 0.05 * sin(s * 1.7))
            mahalliy.append(p)
            let g = T.qolla(p)
            global.append(Vektor3(g.x + t.normal(sigma: 0.01), g.y + t.normal(sigma: 0.01), g.z + t.normal(sigma: 0.02)))
        }
        let n = try Georeferens.gravitatsiyaBilan(mahalliyENU: mahalliy, global: global)
        XCTAssertEqual(n.transformatsiya.burchak * 180 / .pi, 37.0, accuracy: 0.1)
        XCTAssertEqual(n.gorizontalRmsM, 0.014, accuracy: 0.004)
        XCTAssertEqual(n.vertikalRmsM, 0.02, accuracy: 0.004)
        // 10 m nariga ekstrapolyatsiya xatosi ≤ 3 sm
        let uzoq = Vektor3(0.5, 30, 0)
        XCTAssertLessThan((n.transformatsiya.qolla(uzoq) - T.qolla(uzoq)).uzunlik, 0.03)
        XCTAssertLessThan((n.transformatsiya.teskari(T.qolla(uzoq)) - uzoq).uzunlik, 0.03)
    }

    func testARKitENU() {
        let a = Vektor3(1.5, 2.0, -3.0)   // o'ngda, yuqorida, oldinda
        XCTAssertEqual(ARKitRamka.enu(a), Vektor3(1.5, 3.0, 2.0))
        XCTAssertEqual(ARKitRamka.arkit(ARKitRamka.enu(a)), a)
    }

    func testBirJoydaTurishYetarliEmas() {
        let p = [Vektor3](repeating: Vektor3(0, 0, 1), count: 10)
        XCTAssertThrowsError(try Georeferens.gravitatsiyaBilan(mahalliyENU: p, global: p)) {
            XCTAssertEqual($0 as? GravitatsiyaXato, .yoyilishYetarliEmas)
        }
    }
}
