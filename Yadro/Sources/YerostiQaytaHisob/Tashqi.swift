import Foundation
import YerostiGeometriya
import YerostiTahlil

/// LD-02 (TALABLAR 19): tashqi LiDAR (SLAM skaner, boshqa qurilma) nuqta buluti — UTM (E, N, H ellipsoid) da, muhr va
/// NMEA jurnali yo'q. Quvurlar telefon va server bilan BIR XIL yadro (`QuvurTopish`) bilan topiladi; georeferens fayldan
/// olinadi va mustaqil tekshirilmaydi — natijada ogohlantirish, nuqtalar SKAN (T-031 tasdig'i shart).
extension QaytaHisob {
    public static let tashqiXulosa = "TASHQI"

    /// PLY — `PLY.yoz` formati (float32 nisbiy + `comment boshlangich E N H`), koordinatalar UTM `zona`.
    public static func aniqla(ply pb: [UInt8], zona: Int, tarmoq: String?, korinishMaks: Int = 0) -> (natija: Natija, korinish: Data?) {
        let t0 = Date()
        var n = Natija()
        var korinish: Data?
        guard let bulut = PLY.oqi(Data(pb)), !bulut.nuqtalar.isEmpty else {
            n.sabablar = ["PLY o'qilmadi yoki bo'sh"]
            n.vaqtS = Date().timeIntervalSince(t0)
            return (n, nil)
        }
        // UTM → ARKit ramkasi: x = E − E0, y = H − H0 (yuqori), z = −(N − N0). `ARKitRamka.enu` buni ENU ga qaytaradi,
        // shuning uchun telefon uchun yozilgan pipeline (yuqori vektor, chuqurlik, profil) o'zgarishsiz ishlaydi.
        let o = bulut.boshlangich
        let mahalliy = bulut.nuqtalar.map { b in
            BulutNuqtasi(Vektor3(b.p.x - o.x, b.p.z - o.z, -(b.p.y - o.y)), n: b.n.map { Vektor3($0.x, $0.z, -$0.y) })
        }
        var qs = QuvurTopishSozlamalari()
        qs.tarmoqTuri = tarmoq
        let serverQ = QuvurTopish(qs).topish(mahalliy)
        let T = GorizontalTransformatsiya(burchak: 0, t: o)      // ENU + boshlang'ich = UTM
        n.quvurlar = serverQ.map { q in
            let enu = q.oq.map { ARKitRamka.enu($0) }
            let profil = BoylamaProfil(q)
            var r = QuvurNatija(oqEnu: enu.map { [$0.x, $0.y, $0.z] }, oqUtm: nil, oqWgs84: nil,
                                diametrMm: q.tashqiDiametrMm, radiusM: q.radius, standartMm: q.standart?.tashqiMm,
                                seriya: q.standart?.seriya, chuqurlikM: q.qoplamaChuqurligiM, qiyalikFoiz: q.qiyalikFoiz,
                                uzunlikM: q.uzunlikM, ishonch: q.ishonch, muftaSoni: q.muftalar.count, yoyGrad: q.yoyGrad,
                                rmsM: q.rmsM, nuqtaSoni: q.nuqtaSoni, profilOq: profil.oq, profilYer: profil.yer)
            let u = enu.map { T.qolla($0) }
            r.oqUtm = u.map { [$0.x, $0.y, $0.z] }
            r.oqWgs84 = u.map { p in
                let (lat, lon) = UTM.dan(UTMNuqta(zona: zona, shimoliy: true, x: p.x, y: p.y))
                return [lat, lon, p.z]
            }
            return r
        }
        n.georef = GeorefXulosa(server: GeorefQiymat(burchakGrad: 0, t: [o.x, o.y, o.z], gorizontalRmsM: 0, vertikalRmsM: 0,
                                                     soni: 0, utmZona: zona),
                                telefon: nil, siljishFarqiM: nil, burchakFarqiGrad: nil, juftlarNmeadaTopildi: 0, juftlarRasmiy: 0)
        n.jurnal = JurnalXulosa(bosh: "", yozuvlar: 0, nmeaSatrlar: 0, ggaEpoxalar: 0, rasmiyEpoxalar: 0, juftlar: 0,
                                plyMuhrlangan: false, tarmoq: tarmoq, telefonYadro: nil)
        n.ogohlantirishlar = ["tashqi LiDAR: georeferens fayldan olingan, mustaqil tekshirilmagan (muhr va NMEA jurnali yo'q)",
                              "nuqtalar SKAN: quvur ustidagi RTK tasdig'i (T-031) bo'lmaguncha rasmiy emas"]
        if serverQ.isEmpty { n.sabablar = ["buluta quvur topilmadi"] }
        if korinishMaks > 0 {
            let (d, x) = korinishBulut(mahalliy, maks: korinishMaks)
            korinish = d
            n.korinish = x
        }
        n.xulosa = serverQ.isEmpty ? "XATO" : tashqiXulosa
        n.vaqtS = Date().timeIntervalSince(t0)
        return (n, korinish)
    }
}
