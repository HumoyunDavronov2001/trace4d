import XCTest
@testable import YerostiGeometriya

/// LK-03: Swift lokalizatsiyasi server `yerosti_lokal.py` bilan bir xil. Kutilgan qiymatlar Python dan olingan
/// (SUN'IY mahalliy tizim: o'z meridiani 67,80°, burilish 0,37°, masshtab +120 ppm, punktlarga 6 mm / 1 sm shovqin).
final class LokalizatsiyaTests: XCTestCase {
    let juftlar: [LokalizatsiyaJufti] = [
        .init(nomi: "P1", lat: 40.112, lon: 67.838, h: 350.0, x: 7550.443094330313, y: 28872.77644163491, H: 388.5436881797175),
        .init(nomi: "P2", lat: 40.112, lon: 67.846, h: 353.0, x: 7555.1743832665325, y: 29554.865199071537, H: 391.5160322838596),
        .init(nomi: "P3", lat: 40.118, lon: 67.846, h: 356.0, x: 8221.465255471057, y: 29550.23233957615, H: 394.5145232716334),
        .init(nomi: "P4", lat: 40.118, lon: 67.838, h: 359.0, x: 8216.72798181772, y: 28868.19093155284, H: 397.54847198187656),
        .init(nomi: "P5", lat: 40.115, lon: 67.8425, h: 362.0, x: 7886.253499932508, y: 29254.150210557524, H: 400.5281261803906),
    ]

    func testMahalliyTMServerBilanBirXil() {
        let p = MahalliyTM.ga(lat: 40.1162, lon: 67.8431, lon0: 67.84)
        XCTAssertEqual(p.e, 264.27169453447374, accuracy: 1e-6)
        XCTAssertEqual(p.n, 4442431.3889945755, accuracy: 1e-6)
        let q = MahalliyTM.dan(e: 1234.5, n: 4441000.25, lon0: 67.84)
        XCTAssertEqual(q.lat, 40.10331025861802, accuracy: 1e-10)
        XCTAssertEqual(q.lon, 67.85447838628393, accuracy: 1e-10)
    }

    func testParametrlarVaQoldiqlarServerBilanBirXil() throws {
        let n = try Lokalizatsiya.hisobla(juftlar)
        let p = n.parametrlar
        XCTAssertEqual(p.lon0, 67.8421, accuracy: 1e-12)
        XCTAssertEqual(p.a, 1.0000953784494124, accuracy: 1e-11)
        XCTAssertEqual(p.b, 0.006931950298011805, accuracy: 1e-11)
        XCTAssertEqual(p.lx, 7886.012842963626, accuracy: 1e-6)
        XCTAssertEqual(p.ly, 29220.04302447859, accuracy: 1e-6)
        XCTAssertEqual(p.v?.model, "qiya tekislik")
        XCTAssertEqual(p.v?.z0 ?? 0, -38.53016837949552, accuracy: 1e-9)
        XCTAssertEqual(p.v?.ge ?? 0, 4.5210100549309326e-05, accuracy: 1e-12)
        XCTAssertEqual(p.v?.gn ?? 0, -2.4577946752339033e-06, accuracy: 1e-12)
        let kutQ: [(Double, Double)] = [(0.006361964475711905, -0.0014643220549714897), (0.0101546717970796, 0.0017145836684449023),
                                        (0.0063604970487583104, -0.0014331841243233612), (0.006533345849955505, 0.0016834342636684596),
                                        (0.011067451154455064, -0.0005005117527616676)]
        let kutL: [(Double, Double)] = [(0.01169644642615709, -0.005081953948092632), (0.018240978185124244, 0.005476760000590275),
                                        (0.011425046214080315, -0.004577358251253827), (0.012011072123395463, 0.005841557315761747),
                                        (0.013856436505325045, -0.0006275948151142074)]
        for i in 0..<5 {
            XCTAssertEqual(n.qoldiqlar[i].gor ?? -1, kutQ[i].0, accuracy: 1e-7)
            XCTAssertEqual(n.qoldiqlar[i].ver ?? -1, kutQ[i].1, accuracy: 1e-7)
            XCTAssertEqual(n.loo[i].gor ?? -1, kutL[i].0, accuracy: 1e-7)
            XCTAssertEqual(n.loo[i].ver ?? -1, kutL[i].1, accuracy: 1e-7)
        }
        XCTAssertEqual(n.masshtabPpm ?? 0, 119.40183700454021, accuracy: 1e-5)
        XCTAssertEqual(n.burilishGrad ?? 0, 0.39712725826547707, accuracy: 1e-9)
        XCTAssertEqual(n.qiyalikPpm ?? 0, 45.27685883919364, accuracy: 1e-5)
        XCTAssertTrue(n.yaroqli, n.xatolar.joined(separator: "; "))
        let f = Lokalizatsiya.oldinga(p, lat: 40.1162, lon: 67.8431, h: 380.0)
        XCTAssertEqual(f.x ?? 0, 8019.854973635582, accuracy: 1e-6)
        XCTAssertEqual(f.y ?? 0, 29304.3764865685, accuracy: 1e-6)
        XCTAssertEqual(f.H ?? 0, 418.5266417394605, accuracy: 1e-6)
        let t = Lokalizatsiya.teskari(p, x: f.x!, y: f.y!, H: f.H!)
        // Krüger 3-tartib qatorlari: aylanish ~0,03 mm (Python bilan bir xil) — chegara 1 mm (1e-8°)
        XCTAssertEqual(t.lat, 40.1162, accuracy: 1e-8)
        XCTAssertEqual(t.lon, 67.8431, accuracy: 1e-8)
        XCTAssertEqual(t.h ?? 0, 380.0, accuracy: 1e-6)
    }

    func testChegaralar() throws {
        let uch = try Lokalizatsiya.hisobla(Array(juftlar.prefix(3)))
        XCTAssertFalse(uch.yaroqli)
        XCTAssertEqual(uch.parametrlar.v?.model, "doimiy")
        var yomon = juftlar
        yomon[2].x! += 0.06
        let n = try Lokalizatsiya.hisobla(yomon)
        XCTAssertFalse(n.yaroqli)
        XCTAssertEqual(n.loo.max { ($0.gor ?? 0) < ($1.gor ?? 0) }?.nomi, "P3", "LOO xato punktni ko'rsatadi")
        let p = try Lokalizatsiya.hisobla(juftlar).parametrlar
        let f = Lokalizatsiya.oldinga(p, lat: 40.116, lon: 67.84, h: 360.0)
        XCTAssertTrue(Lokalizatsiya.tekshiruv(p, lat: 40.116, lon: 67.84, h: 360.0, x: f.x! + 0.01, y: f.y!, H: f.H! - 0.02).otdi)
        XCTAssertFalse(Lokalizatsiya.tekshiruv(p, lat: 40.116, lon: 67.84, h: 360.0, x: f.x! + 0.05, y: f.y!, H: f.H!).otdi)
    }

    func testServerJSONiniOqiydi() throws {
        let json = #"{"lon0": 67.8421, "gor": "helmert4", "a": 1.0000953784494124, "b": 0.006931950298011805, "ge": 6.297899801666062e-09, "gn": 4442298.146386163, "lx": 7886.012842963626, "ly": 29220.04302447859, "v": {"z0": -38.53016837949552, "ge": 4.5210100549309326e-05, "gn": -2.4577946752339033e-06, "ce": 6.297899801666062e-09, "cn": 4442298.146386163, "model": "qiya tekislik"}}"#
        let p = try JSONDecoder().decode(LokParametrlar.self, from: Data(json.utf8))
        let f = Lokalizatsiya.oldinga(p, lat: 40.1162, lon: 67.8431, h: 380.0)
        XCTAssertEqual(f.x ?? 0, 8019.854973635582, accuracy: 1e-6)
        XCTAssertEqual(f.H ?? 0, 418.5266417394605, accuracy: 1e-6)
    }
}
