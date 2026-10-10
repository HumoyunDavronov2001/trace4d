import Foundation
import YerostiDrayver
import YerostiGeometriya
import YerostiMuhr
import YerostiTahlil

/// DM-02: data markazdagi MUSTAQIL qayta hisob. Telefon bilan BIR XIL yadro (Swift, Linux CLI).
///
/// Server telefon natijasiga ishonmaydi:
/// 1. muhr jurnalini (YMJ1) noldan o'qib zanjirni tiklaydi; PLY jurnalda muhrlangan fayl ekanini xesh bilan tekshiradi;
/// 2. har georeferens juftini xom NMEA (GGA) bilan solishtiradi va T-103 bo'yicha sifatini qayta baholaydi;
/// 3. georeferensni juftlardan qayta hisoblaydi va telefonniki bilan solishtiradi;
/// 4. quvurlarni PLY dan qayta aniqlaydi va telefon natijasi bilan solishtiradi (o'q, diametr, uzunlik).
public enum QaytaHisob {
    public static let versiya = "yerosti-tahlil 1.2"

    /// "MOS" chegaralari (DM-02 qarori). Bir xil kirish + bir xil yadro → farq mm ulushlarida bo'lishi kerak;
    /// quvur o'qi uchun chek RASMIY σH (2 sm), chunki telefon float64, server PLY dagi float32 bilan ishlaydi.
    public struct Chegaralar: Sendable {
        public var oqM = 0.02
        public var diametrMm = 10.0
        public var georefSiljishM = 0.001
        public var georefBurchakGrad = 0.001
        public var juftNMEAM = 0.001
        /// Telefon quvuriga server quvurini moslash: o'rtacha masofa shundan katta bo'lsa — "mos quvur yo'q".
        public var moslashM = 0.10
        public init() {}
    }

    // MARK: - Natija (JSON: snake_case)

    public struct Natija: Codable, Sendable {
        public var versiya = QaytaHisob.versiya
        public var yadro = YadroVersiya.matn
        public var xulosa = "XATO"
        public var sabablar: [String] = []
        public var ogohlantirishlar: [String] = []
        public var jurnal: JurnalXulosa?
        public var georef: GeorefXulosa?
        public var quvurlar: [QuvurNatija] = []
        public var telefonQuvurlar: [TelefonQuvur] = []
        public var taqqos: [QuvurTaqqos] = []
        public var korinish: KorinishXulosa?
        /// DS-03…DS-05: xom yozuvdan kechikish va bo'lakli georeferens (eski jurnallarda nil).
        public var xom: XomXulosa?
        public var kechikish: KechikishNatija?
        public var bolakli: BolakliXulosa?
        /// DS-02: antenna ofseti xom ma'lumotdan (profil qiymatini tekshirish; avtomatik qo'llanmaydi).
        public var ofset: OfsetBaho?
        public var vaqtS = 0.0
    }

    public struct XomXulosa: Codable, Sendable {
        public var pozaNamuna: Int
        public var pozaHz: Double?
        public var ggaKelishVaqti: Int
        public var chuqurlikKadrlar: Int
        public var profil: ProfilYozuvi?
        public var plyNomi: String?
    }

    public struct BolakliXulosa: Codable, Sendable {
        public var bolaklar: [GeorefBolak]
        public var tugunlar: Int
        public var rmsH: Double
        public var rmsV: Double
        public var juftlar: Int
        public var kechikishS: Double
        public var kechikishManba: String
        /// Bitta qattiq transformatsiyaga nisbatan eng katta tuzatish (m) — suzish qanchalik katta bo'lganini ko'rsatadi.
        public var maksTuzatishM: Double
        public var pastBolaklar: Int
        /// Ko'rinish buluti va quvur o'qlari (ENU) suzishi tuzatilgan holda server georeferensi ramkasida.
        public var enuTuzatilgan: Bool
    }

    public struct JurnalXulosa: Codable, Sendable {
        public var bosh: String
        public var yozuvlar: Int
        public var nmeaSatrlar: Int
        public var ggaEpoxalar: Int
        public var rasmiyEpoxalar: Int
        public var juftlar: Int
        public var plyMuhrlangan: Bool
        public var tarmoq: String?
        public var telefonYadro: String?
    }

    public struct GeorefQiymat: Codable, Sendable {
        public var burchakGrad: Double
        public var t: [Double]
        public var gorizontalRmsM: Double
        public var vertikalRmsM: Double
        public var soni: Int
        public var utmZona: Int
    }

    public struct GeorefXulosa: Codable, Sendable {
        public var server: GeorefQiymat?
        public var telefon: GeorefQiymat?
        public var siljishFarqiM: Double?
        public var burchakFarqiGrad: Double?
        public var juftlarNmeadaTopildi: Int
        public var juftlarRasmiy: Int
    }

    public struct QuvurNatija: Codable, Sendable {
        public var oqEnu: [[Double]]
        public var oqUtm: [[Double]]?
        public var oqWgs84: [[Double]]?
        public var diametrMm: Double
        public var radiusM: Double
        public var standartMm: Double?
        public var seriya: String?
        public var chuqurlikM: Double?
        public var qiyalikFoiz: Double
        public var uzunlikM: Double
        public var ishonch: Double
        public var muftaSoni: Int
        public var yoyGrad: Double
        public var rmsM: Double
        public var nuqtaSoni: Int
        /// UI-21: bo'ylama profil — [stansiya, markaz balandligi] va [stansiya, yer sirti], mahalliy ENU z (m).
        public var profilOq: [[Double]]
        public var profilYer: [[Double]]
        /// DS-05: o'q nuqtalari kuzatilgan vaqt va bo'lagi PAST mi (RTK qamrovidan tashqari yoki qoldiq > 3 sm).
        public var oqVaqt: [Double]?
        public var oqPast: [Bool]?
        public var georefUsul: String?
    }

    public struct TelefonQuvur: Codable, Sendable {
        public var oqEnu: [[Double]]
        public var diametrMm: Double
        public var standartMm: Double?
        public var uzunlikM: Double
    }

    public struct QuvurTaqqos: Codable, Sendable {
        public var telefon: Int?
        public var server: Int?
        public var oqFarqiM: Double?
        public var diametrFarqiMm: Double?
        public var uzunlikFarqiM: Double?
        public var mos: Bool
        public var izoh: String
    }

    public struct KorinishXulosa: Codable, Sendable {
        public var nuqtalar: Int
        public var vokselM: Double
        public var min: [Double]
        public var max: [Double]
    }

    public enum KirishXato: Error, CustomStringConvertible {
        case jurnal(String)
        case ply(String)
        public var description: String {
            switch self {
            case .jurnal(let m): return "muhr jurnali: " + m
            case .ply(let m): return "PLY: " + m
            }
        }
    }

    // MARK: - Jurnal o'qish

    /// Jurnaldan olingan xom ma'lumot (zanjir shu o'qishda noldan tiklanadi).
    public struct Jurnal {
        public struct Epoxa {
            public let lat: Double
            public let lon: Double
            public let h: Double
            public let rasmiy: Bool
            /// DS-03: GNSS vaqti (sutka soniyasi, uzluksiz) va telefonga kelgan vaqt (uptime).
            public var utcS: Double?
            public var te: Double?
        }
        public var bosh = ""
        public var soni = 0
        public var nmeaSoni = 0
        public var epoxalar: [Epoxa] = []
        public var juftlar: [JuftYozuvi] = []
        public var tarmoq: String?
        public var yadro: String?
        public var ply: (sha256: String, hajm: Int)?
        /// PLY fayl yozuvidan KEYINgi quvurlar — telefonning yakuniy natijasi.
        public var quvurlar: [QuvurYozuvi] = []
        public var georef: GeorefYozuvi?
        /// DS-03: poza izi, profil, zich bulutga qo'shilgan chuqurlik kadrlari, muhrlangan PLY fayllar (nomi → xesh, hajm).
        public var iz: [PozaNamuna] = []
        public var profil: ProfilYozuvi?
        public var chuqurlikKadrlar = 0
        public var plyFayllar: [String: (sha256: String, hajm: Int)] = [:]
    }

    public static func jurnalOqi(_ b: [UInt8]) throws -> Jurnal {
        guard b.count >= 4, Array(b[0..<4]) == MuhrZanjir.jurnalSarlavha else { throw KirishXato.jurnal("sarlavha YMJ1 emas") }
        var j = Jurnal()
        var zanjir = MuhrZanjir()
        var holat = QabulQilgichHolati()
        let sabit = Date(timeIntervalSince1970: 0)
        let dek = JSONDecoder()
        var plyKeyin = false
        var oxirgiGGA: Int?
        var i = 4
        while i < b.count {
            guard i + 5 <= b.count else { throw KirishXato.jurnal("kesilgan (yozuv sarlavhasi)") }
            guard let tur = YozuvTuri(rawValue: b[i]) else { throw KirishXato.jurnal("noma'lum yozuv turi \(b[i])") }
            let n = Int(b[i + 1]) << 24 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 8 | Int(b[i + 4])
            guard i + 5 + n <= b.count else { throw KirishXato.jurnal("kesilgan (yozuv ma'lumoti)") }
            let m = Array(b[(i + 5)..<(i + 5 + n)])
            zanjir.qosh(tur, m)
            i += 5 + n

            switch tur {
            case .nmea:
                j.nmeaSoni += 1
                oxirgiGGA = nil
                guard let x = try? NMEAXabar.ajrat(String(decoding: m, as: UTF8.self)) else { continue }
                holat.qabul(x, hozir: sabit)
                if case .gga = x, let lat = holat.lat, let lon = holat.lon, let h = holat.balandlikEllipsoid {
                    // Telefon juftni GGA kelgan zahoti oladi: σ — oxirgi GST dan (T-103).
                    let s = SifatQoidasi.hisobla(rtk: holat.rtk, sigmaHSm: holat.sigmaHSm, sigmaVSm: holat.sigmaVSm,
                                                 tuzatmaYoshiS: holat.tuzatmaYoshiS)
                    j.epoxalar.append(.init(lat: lat, lon: lon, h: h, rasmiy: s == .rasmiy,
                                            utcS: Kechikish.utcSoniya(holat.vaqtUTC), te: nil))
                    oxirgiGGA = j.epoxalar.count - 1
                }
            case .kadr:
                // DS-03: poza izi va zich bulut kadrlari; kalit kadr metama'lumoti («tur» siz) bu yerda kerak emas
                guard let obj = (try? JSONSerialization.jsonObject(with: Data(m))) as? [String: Any] else { continue }
                switch obj["tur"] as? String {
                case "iz"?:
                    if let y = try? dek.decode(IzYozuvi.self, from: Data(m)), y.togri { j.iz += y.namunalar }
                case "chuqurlik"?:
                    j.chuqurlikKadrlar += 1
                default:
                    break
                }
            case .nuqta, .belgi, .fayl, .izoh:
                guard let obj = (try? JSONSerialization.jsonObject(with: Data(m))) as? [String: Any] else { continue }
                let t = obj["tur"] as? String
                switch (tur, t) {
                case (.nuqta, "juft"?):
                    if let y = try? dek.decode(JuftYozuvi.self, from: Data(m)), y.togri { j.juftlar.append(y) }
                case (.nuqta, "nmea_t"?):
                    if let k = oxirgiGGA, let te = obj["te"] as? Double { j.epoxalar[k].te = te }
                    oxirgiGGA = nil
                case (.belgi, "quvur"?) where plyKeyin:
                    if let y = try? dek.decode(QuvurYozuvi.self, from: Data(m)) { j.quvurlar.append(y) }
                case (.fayl, _):
                    // DS-06: zich.ply (chuqurlik kadrlaridan) yoki mesh.ply; oxirgisidan keyingi quvurlar — telefon natijasi
                    if let nom = obj["nomi"] as? String, nom == "mesh.ply" || nom == "zich.ply", let sha = obj["sha256"] as? String {
                        let hajm = (obj["hajm"] as? String).flatMap { Int($0) } ?? (obj["hajm"] as? Int) ?? -1
                        j.ply = (sha.lowercased(), hajm)
                        j.plyFayllar[nom] = (sha.lowercased(), hajm)
                        plyKeyin = true
                        j.quvurlar = []
                    }
                case (.izoh, "georef"?):
                    j.georef = try? dek.decode(GeorefYozuvi.self, from: Data(m))
                case (.izoh, "profil"?):
                    j.profil = try? dek.decode(ProfilYozuvi.self, from: Data(m))
                case (.izoh, _):
                    if j.tarmoq == nil, let tr = obj["tarmoq"] as? String { j.tarmoq = tr }
                    if j.yadro == nil, let v = obj["yadro"] as? String { j.yadro = v }
                default:
                    break
                }
            default:
                break
            }
        }
        // UTC sutka almashishi (00:00 dan o'tsa) uzluksiz
        let u = Kechikish.uzluksiz(j.epoxalar.map(\.utcS))
        for k in j.epoxalar.indices { j.epoxalar[k].utcS = u[k] }
        j.bosh = zanjir.boshHex
        j.soni = zanjir.soni
        return j
    }

    // MARK: - Asosiy tekshiruv

    /// `korinishMaks` > 0 bo'lsa 3D ko'ruvchi uchun siyraklashtirilgan ENU bulut (PLY baytlari) ham qaytadi.
    public static func tekshir(jurnal jb: [UInt8], ply pb: [UInt8], chek: Chegaralar = .init(),
                               korinishMaks: Int = 0) -> (natija: Natija, korinish: Data?) {
        let t0 = Date()
        var n = Natija()
        var korinish: Data?
        let j: Jurnal
        do { j = try jurnalOqi(jb) } catch {
            n.sabablar = ["\(error)"]
            n.vaqtS = Date().timeIntervalSince(t0)
            return (n, nil)
        }
        guard let bulut = PLY.oqi(Data(pb)) else {
            n.sabablar = ["PLY o'qilmadi"]
            n.vaqtS = Date().timeIntervalSince(t0)
            return (n, nil)
        }
        var farq: [String] = []

        // 1) PLY — jurnalda muhrlangan faylmi
        let plyXesh = SHA256.hex(SHA256.xesh(pb))
        let plyNomi = j.plyFayllar.first { $0.value.sha256 == plyXesh && $0.value.hajm == pb.count }?.key
        let plyMuhr = plyNomi != nil
        if j.plyFayllar.isEmpty { farq.append("jurnalda mesh.ply / zich.ply fayl yozuvi yo'q") }
        else if !plyMuhr { farq.append("PLY jurnalda muhrlangan fayl emas (xesh yoki hajm mos emas)") }
        else if j.plyFayllar["zich.ply"] != nil && plyNomi != "zich.ply" {
            n.ogohlantirishlar.append("telefon zich bulut (zich.ply) muhrlagan, lekin serverga \(plyNomi ?? "boshqa") yuklangan")
        }

        // 2) juftlar ↔ xom NMEA
        let zona = j.juftlar.first?.zona ?? j.georef?.utmZona ?? 42
        let epoxaUTM: [(x: Double, y: Double, h: Double, rasmiy: Bool)] = j.epoxalar.map {
            let u = UTM.ga(lat: $0.lat, lon: $0.lon, zona: zona)
            return (u.x, u.y, $0.h, $0.rasmiy)
        }.sorted { $0.x < $1.x }
        var topildi = 0, rasmiy = 0
        for p in j.juftlar {
            let g = p.global
            var lo = 0, hi = epoxaUTM.count
            while lo < hi { let o = (lo + hi) / 2; if epoxaUTM[o].x < g.x - chek.juftNMEAM { lo = o + 1 } else { hi = o } }
            var mos: (Bool, Bool)?
            var k = lo
            while k < epoxaUTM.count, epoxaUTM[k].x <= g.x + chek.juftNMEAM {
                let e = epoxaUTM[k]
                if abs(e.y - g.y) <= chek.juftNMEAM, abs(e.h - g.z) <= chek.juftNMEAM {
                    mos = (true, e.rasmiy)
                    if e.rasmiy { break }
                }
                k += 1
            }
            if let m = mos { topildi += 1; if m.1 { rasmiy += 1 } }
        }
        if topildi < j.juftlar.count { farq.append("\(j.juftlar.count - topildi) ta georeferens jufti xom NMEA da topilmadi") }
        if rasmiy < topildi { farq.append("\(topildi - rasmiy) ta juft RASMIY bo'lmagan epoxadan (T-103)") }

        // 3) georeferensni qayta hisoblash (telefon qoidasi: ≥ 20 juft)
        var serverGeoref: GorizontalNatija?
        if j.juftlar.count >= 20 {
            serverGeoref = try? Georeferens.gravitatsiyaBilan(mahalliyENU: j.juftlar.map(\.mahalliy),
                                                              global: j.juftlar.map(\.global))
        }
        func qiymat(_ g: GorizontalNatija) -> GeorefQiymat {
            GeorefQiymat(burchakGrad: g.transformatsiya.burchak * 180 / .pi,
                         t: [g.transformatsiya.t.x, g.transformatsiya.t.y, g.transformatsiya.t.z],
                         gorizontalRmsM: g.gorizontalRmsM, vertikalRmsM: g.vertikalRmsM, soni: g.soni, utmZona: zona)
        }
        var gx = GeorefXulosa(server: serverGeoref.map(qiymat), telefon: nil, siljishFarqiM: nil, burchakFarqiGrad: nil,
                              juftlarNmeadaTopildi: topildi, juftlarRasmiy: rasmiy)
        if let tg = j.georef {
            gx.telefon = GeorefQiymat(burchakGrad: tg.burchak * 180 / .pi, t: tg.t, gorizontalRmsM: tg.rmsH, vertikalRmsM: tg.rmsV,
                                      soni: tg.juft, utmZona: tg.utmZona)
        }
        switch (serverGeoref, j.georef?.transformatsiya) {
        case let (s?, tf?):
            let ds = (s.transformatsiya.t - tf.t).uzunlik
            var db = (s.transformatsiya.burchak - tf.burchak) * 180 / .pi
            db = abs((db + 540).truncatingRemainder(dividingBy: 360) - 180)
            gx.siljishFarqiM = ds
            gx.burchakFarqiGrad = db
            if ds > chek.georefSiljishM || db > chek.georefBurchakGrad {
                farq.append("georeferens farqi: siljish \(sm(ds)), burilish \(String(format: "%.4f", db))°")
            }
            if j.georef?.utmZona != zona { farq.append("UTM zonasi mos emas") }
        case (nil, _?):
            farq.append("telefonda georeferens bor, juftlardan qayta hisoblab bo'lmadi")
        case (_?, nil):
            n.ogohlantirishlar.append("telefon georeferens yozmagan, server juftlardan hisobladi")
        case (nil, nil):
            n.ogohlantirishlar.append("georeferens yo'q — natija faqat mahalliy ramkada")
        }
        n.georef = gx
        // (bo'lakli georeferens bo'lsa bu ogohlantirish 3b bo'limida aniqlashtiriladi)
        let qattiqQoldiq = serverGeoref.map { max($0.gorizontalRmsM, $0.vertikalRmsM) }
        if let v = j.yadro, v != YadroVersiya.matn {
            n.ogohlantirishlar.append("telefon yadrosi \(v), server yadrosi \(YadroVersiya.matn)")
        }

        // 3b) DS-04/05: xom poza izi + GGA kelish vaqtidan kechikish va bo'lakli georeferens (ARKit suzishi tuzatiladi)
        var bolakli: BolakliGeoreferens?
        if !j.iz.isEmpty || j.profil != nil || j.chuqurlikKadrlar > 0 {
            let hz: Double? = j.iz.count > 1 ? Double(j.iz.count - 1) / max(1e-9, j.iz.last!.t - j.iz.first!.t) : nil
            n.xom = XomXulosa(pozaNamuna: j.iz.count, pozaHz: hz, ggaKelishVaqti: j.epoxalar.filter { $0.te != nil }.count,
                              chuqurlikKadrlar: j.chuqurlikKadrlar, profil: j.profil, plyNomi: plyNomi)
        }
        if !j.iz.isEmpty {
            let iz = PozaIzi(j.iz)
            let ofset = j.profil?.antennaOfset ?? [0, 0, 0]
            let ep = j.epoxalar.map { e -> RTKEpoxasi in
                let u = UTM.ga(lat: e.lat, lon: e.lon, zona: zona)
                return RTKEpoxasi(g: Vektor3(u.x, u.y, e.h), utcS: e.utcS, te: e.te, rasmiy: e.rasmiy)
            }
            let k = Kechikish.baho(iz: iz, epoxalar: ep, ofset: ofset)
            n.kechikish = k
            var L = j.profil?.kechikishS ?? 0.08
            var manba = j.profil == nil ? "standart (80 ms)" : "telefon sozlamasi"
            var c: Double?
            if k.ishonchli, let kb = k.kechikishS {
                L = kb; manba = "xom ma'lumotdan (DS-04)"; c = Kechikish.soatBoglanishi(ep)
            } else if let sabab = k.sabab {
                n.ogohlantirishlar.append("RTK kechikishi baholanmadi: \(sabab) — \(manba) ishlatildi")
            }
            if k.ishonchli, let o = k.ortachaS, let tel = j.profil?.kechikishS, abs(o - tel) > 0.02 {
                n.ogohlantirishlar.append("RTK kechikishi: telefon sozlamasi \(Int((tel * 1000).rounded())) ms, xom ma'lumotdan "
                                          + "\(Int((o * 1000).rounded())) ms")
            }
            let ob = AntennaOfset.baho(iz: iz, epoxalar: ep, L: L, c: c, boshlangich: ofset, profil: j.profil?.antennaOfset)
            n.ofset = ob
            if ob.kuzatiladi, let f = ob.profildanFarqM, f > 0.02 {
                n.ogohlantirishlar.append(String(format: "antenna ofseti: profilda (%.3f, %.3f, %.3f) m, xom ma'lumotdan (%.3f, %.3f, %.3f) m — "
                                                 + "farq %.1f sm, dastak profilini tekshiring (DS-02)", ofset[0], ofset[1], ofset[2],
                                                 ob.ofset[0], ob.ofset[1], ob.ofset[2], f * 100))
            }
            let jf = Kechikish.juftlar(iz: iz, epoxalar: ep, ofset: ofset, L: L, c: c)
            if let b = try? BolakliGeoreferens.hisobla(jf) {
                bolakli = b
                let maks = jf.map { (b.qolla($0.m, vaqt: $0.t) - b.umumiy.transformatsiya.qolla($0.m)).uzunlik }.max() ?? 0
                let past = b.bolaklar.filter(\.past)
                n.bolakli = BolakliXulosa(bolaklar: b.bolaklar, tugunlar: b.tugunlar.count, rmsH: b.rmsH, rmsV: b.rmsV,
                                          juftlar: jf.count, kechikishS: L, kechikishManba: manba, maksTuzatishM: maks,
                                          pastBolaklar: past.count, enuTuzatilgan: serverGeoref != nil)
                for bo in past {
                    n.ogohlantirishlar.append("georeferens bo'lagi \(Int(bo.boshM.rounded()))–\(Int(bo.oxirM.rounded())) m PAST: \(bo.sabab ?? "")")
                }
            } else {
                n.ogohlantirishlar.append("bo'lakli georeferens hisoblanmadi: poza izi ichida RASMIY juftlar 20 tadan kam")
            }
        }
        if let q = qattiqQoldiq, q > 0.03 {
            if let b = bolakli, b.bolaklar.allSatisfy({ !$0.past }) {
                n.ogohlantirishlar.append("bitta qattiq georeferens qoldig'i \(sm(q)) (ARKit suzishi) — bo'lakli georeferens bilan tuzatildi, "
                                          + "bo'laklar qoldig'i \(sm(max(b.rmsH, b.rmsV)))")
            } else {
                n.ogohlantirishlar.append("georeferens qoldig'i katta: \(sm(q))")
            }
        }
        let vaqtTop: ((Vektor3) -> Double?)? = bolakli == nil ? nil : nuqtaVaqtiTopuvchi(bulut.nuqtalar, iz: j.iz)

        // 4) quvurlarni qayta aniqlash — telefon yakunidagi chaqiruv bilan bir xil sozlama
        var qs = QuvurTopishSozlamalari()
        qs.tarmoqTuri = j.tarmoq
        let serverQ = QuvurTopish(qs).topish(bulut.nuqtalar)
        let T = serverGeoref?.transformatsiya
        n.quvurlar = serverQ.map { q in
            let enu = q.oq.map { ARKitRamka.enu($0) }
            let profil = BoylamaProfil(q)
            var r = QuvurNatija(oqEnu: enu.map { [$0.x, $0.y, $0.z] }, oqUtm: nil, oqWgs84: nil,
                                diametrMm: q.tashqiDiametrMm, radiusM: q.radius, standartMm: q.standart?.tashqiMm,
                                seriya: q.standart?.seriya, chuqurlikM: q.qoplamaChuqurligiM, qiyalikFoiz: q.qiyalikFoiz,
                                uzunlikM: q.uzunlikM, ishonch: q.ishonch, muftaSoni: q.muftalar.count, yoyGrad: q.yoyGrad,
                                rmsM: q.rmsM, nuqtaSoni: q.nuqtaSoni, profilOq: profil.oq, profilYer: profil.yer)
            func utmga(_ u: [Vektor3]) {
                r.oqUtm = u.map { [$0.x, $0.y, $0.z] }
                r.oqWgs84 = u.map { p in
                    let (lat, lon) = UTM.dan(UTMNuqta(zona: zona, shimoliy: true, x: p.x, y: p.y))
                    return [lat, lon, p.z]
                }
            }
            if let b = bolakli, let vt = vaqtTop {
                // DS-05: har o'q nuqtasi o'zi kuzatilgan vaqtdagi transformatsiya bilan; vaqti noma'lum — PAST
                let vaqt = q.oq.map { vt($0) }
                let u = zip(enu, vaqt).map { p, t in t.map { b.qolla(p, vaqt: $0) } ?? b.umumiy.transformatsiya.qolla(p) }
                utmga(u)
                r.oqVaqt = vaqt.map { $0 ?? -1 }
                r.oqPast = vaqt.map { t in t.map { b.bolak($0)?.past ?? true } ?? true }
                r.georefUsul = "bolakli"
                if let T { r.oqEnu = u.map { let e = T.teskari($0); return [e.x, e.y, e.z] } }
            } else if let T {
                utmga(enu.map { T.qolla($0) })
                r.georefUsul = "qattiq"
            }
            return r
        }
        n.telefonQuvurlar = j.quvurlar.map { q in
            TelefonQuvur(oqEnu: q.oqNuqtalar.map { let e = ARKitRamka.enu($0); return [e.x, e.y, e.z] },
                         diametrMm: q.diametrMm, standartMm: q.standartMm, uzunlikM: q.uzunlikM)
        }
        n.taqqos = taqqosla(telefon: j.quvurlar, server: serverQ, chek: chek)
        for t in n.taqqos where !t.mos { farq.append(t.izoh) }

        n.jurnal = JurnalXulosa(bosh: j.bosh, yozuvlar: j.soni, nmeaSatrlar: j.nmeaSoni, ggaEpoxalar: j.epoxalar.count,
                                rasmiyEpoxalar: j.epoxalar.filter(\.rasmiy).count, juftlar: j.juftlar.count,
                                plyMuhrlangan: plyMuhr, tarmoq: j.tarmoq, telefonYadro: j.yadro)

        if korinishMaks > 0 {
            var tuzatish: ((Vektor3) -> Vektor3)?
            if let b = bolakli, let T, let vt = vaqtTop {
                // ENU → (nuqta vaqtidagi bo'lakli UTM) → server qattiq ramkasidagi ENU: ko'ruvchi va M3C2 farqi shu ramkada
                tuzatish = { p in
                    let e = ARKitRamka.enu(p)
                    guard let t = vt(p) else { return e }
                    return T.teskari(b.qolla(e, vaqt: t))
                }
            }
            let (d, x) = korinishBulut(bulut.nuqtalar, maks: korinishMaks, tuzatish: tuzatish)
            korinish = d
            n.korinish = x
        }
        n.sabablar = farq
        n.xulosa = farq.isEmpty ? "MOS" : "FARQ"
        n.vaqtS = Date().timeIntervalSince(t0)
        return (n, korinish)
    }

    // MARK: - Quvurlarni solishtirish

    static func taqqosla(telefon: [QuvurYozuvi], server: [TopilganQuvur], chek: Chegaralar) -> [QuvurTaqqos] {
        var band = Set<Int>()
        var natija: [QuvurTaqqos] = []
        for (i, t) in telefon.enumerated() {
            let A = t.oqNuqtalar
            var eng: (k: Int, d: Double)?
            for (k, s) in server.enumerated() where !band.contains(k) && A.count >= 2 {
                let d = A.map { poliliniyagacha($0, s.oq).masofa }.reduce(0, +) / Double(A.count)
                if d < (eng?.d ?? .infinity) { eng = (k, d) }
            }
            guard let e = eng, e.d <= chek.moslashM else {
                natija.append(QuvurTaqqos(telefon: i + 1, server: nil, oqFarqiM: nil, diametrFarqiMm: nil, uzunlikFarqiM: nil,
                                          mos: false, izoh: "telefon quvuri \(i + 1): serverda mos quvur topilmadi"))
                continue
            }
            band.insert(e.k)
            let s = server[e.k]
            let oq = oqFarqi(A, s.oq) ?? e.d
            let dd = abs((t.standartMm ?? t.diametrMm) - (s.standart?.tashqiMm ?? s.tashqiDiametrMm))
            let du = abs(t.uzunlikM - s.uzunlikM)
            let mos = oq <= chek.oqM && dd <= chek.diametrMm
            var izoh = "quvur \(i + 1): o'q farqi \(sm(oq)), diametr farqi \(Int(dd.rounded())) mm"
            if !mos { izoh = "quvur \(i + 1) mos emas — o'q farqi \(sm(oq)), diametr farqi \(Int(dd.rounded())) mm" }
            natija.append(QuvurTaqqos(telefon: i + 1, server: e.k + 1, oqFarqiM: oq, diametrFarqiMm: dd,
                                      uzunlikFarqiM: du, mos: mos, izoh: izoh))
        }
        for k in server.indices where !band.contains(k) {
            natija.append(QuvurTaqqos(telefon: nil, server: k + 1, oqFarqiM: nil, diametrFarqiMm: nil, uzunlikFarqiM: nil,
                                      mos: false, izoh: "server qo'shimcha quvur topdi (\(k + 1)) — telefon natijasida yo'q"))
        }
        return natija
    }

    /// Nuqtadan poliliniyagacha masofa. `ichida` = eng yaqin nuqta chiziq uchlaridan tashqarida EMAS.
    static func poliliniyagacha(_ p: Vektor3, _ L: [Vektor3]) -> (masofa: Double, ichida: Bool) {
        guard L.count >= 2 else { return ((L.first.map { (p - $0).uzunlik }) ?? .infinity, false) }
        var eng = Double.infinity, ichida = true
        for i in 0..<(L.count - 1) {
            let a = L[i], d = L[i + 1] - a
            let l2 = d.uzunlik2
            let u = l2 > 0 ? (p - a).nuqta(d) / l2 : 0
            let c = min(max(u, 0), 1)
            let m = (p - (a + d * c)).uzunlik
            if m < eng {
                eng = m
                ichida = !((i == 0 && u < 0) || (i == L.count - 2 && u > 1))
            }
        }
        return (eng, ichida)
    }

    /// Ikki o'q orasidagi yon og'ish (simmetrik, uchlardan tashqaridagi qismlarsiz). Uzunlik farqi alohida o'lchanadi.
    static func oqFarqi(_ A: [Vektor3], _ B: [Vektor3]) -> Double? {
        var maks: Double?
        for p in A { let r = poliliniyagacha(p, B); if r.ichida { maks = max(maks ?? 0, r.masofa) } }
        for p in B { let r = poliliniyagacha(p, A); if r.ichida { maks = max(maks ?? 0, r.masofa) } }
        return maks
    }

    // MARK: - 3D ko'ruvchi uchun bulut (DM-03)

    /// ARKit → ENU (z yuqori), voksel bilan siyraklashtirilgan; `maks` dan oshsa voksel kattalashadi.
    static func korinishBulut(_ nuqtalar: [BulutNuqtasi], maks: Int, tuzatish: ((Vektor3) -> Vektor3)? = nil)
        -> (Data, KorinishXulosa) {
        var v = 0.015
        var tanlangan: [Vektor3] = []
        var ranglar: [Rang?] = []
        // DS-05: suzish tuzatishi bir marta hisoblanadi; DS-07: rang saqlanadi
        let enular: [Vektor3] = nuqtalar.map { tuzatish?($0.p) ?? ARKitRamka.enu($0.p) }
        repeat {
            var korilgan = Set<SIMD3<Int32>>()
            tanlangan = []
            ranglar = []
            tanlangan.reserveCapacity(min(nuqtalar.count, maks))
            for (i, e) in enular.enumerated() {
                let k = SIMD3<Int32>(Int32((e.x / v).rounded(.down)), Int32((e.y / v).rounded(.down)), Int32((e.z / v).rounded(.down)))
                if korilgan.insert(k).inserted { tanlangan.append(e); ranglar.append(nuqtalar[i].rang) }
            }
            if tanlangan.count > maks { v *= 1.4 }
        } while tanlangan.count > maks
        var mn = Vektor3(.infinity, .infinity, .infinity), mx = Vektor3(-.infinity, -.infinity, -.infinity)
        for p in tanlangan {
            mn = Vektor3(min(mn.x, p.x), min(mn.y, p.y), min(mn.z, p.z))
            mx = Vektor3(max(mx.x, p.x), max(mx.y, p.y), max(mx.z, p.z))
        }
        if tanlangan.isEmpty { mn = .nol; mx = .nol }
        let d = PLY.yoz(zip(tanlangan, ranglar).map { BulutNuqtasi($0, rang: $1) }, izoh: "YEROSTI korinish ENU (z yuqori)")
        return (d, KorinishXulosa(nuqtalar: tanlangan.count, vokselM: v, min: [mn.x, mn.y, mn.z], max: [mx.x, mx.y, mx.z]))
    }

    /// DS-05: nuqta kuzatilgan vaqt. Bulutda vaqt bo'lsa (zich.ply) — 5 sm atrofidagi nuqtalar vaqtining medianasi;
    /// bo'lmasa (mesh.ply) — kamera shu nuqtaga eng yaqin turgan poza vaqti (LiDAR masofasi 5 m dan uzoq bo'lsa nil).
    static func nuqtaVaqtiTopuvchi(_ nuqtalar: [BulutNuqtasi], iz: [PozaNamuna]) -> (Vektor3) -> Double? {
        let kat = 0.05
        func kalit(_ p: Vektor3, _ k: Double) -> SIMD3<Int32> {
            SIMD3(Int32((p.x / k).rounded(.down)), Int32((p.y / k).rounded(.down)), Int32((p.z / k).rounded(.down)))
        }
        if !nuqtalar.isEmpty, nuqtalar.allSatisfy({ $0.t != nil }) {
            var tor: [SIMD3<Int32>: [Double]] = [:]
            for b in nuqtalar { tor[kalit(b.p, kat), default: []].append(b.t!) }
            return { p in
                let c = kalit(p, kat)
                var t: [Double] = []
                for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                    if let l = tor[c &+ SIMD3(Int32(dx), Int32(dy), Int32(dz))] { t += l }
                } } }
                guard !t.isEmpty else { return nil }
                t.sort()
                return t[t.count / 2]
            }
        }
        let ik = 0.5
        var tor: [SIMD3<Int32>: [Int]] = [:]
        for (i, x) in iz.enumerated() { tor[kalit(x.p, ik), default: []].append(i) }
        return { p in
            let c = kalit(p, ik)
            var eng: (Int, Double)?
            for r in 0...10 {
                for dx in -r...r { for dy in -r...r { for dz in -r...r where max(abs(dx), abs(dy), abs(dz)) == r {
                    for i in tor[c &+ SIMD3(Int32(dx), Int32(dy), Int32(dz))] ?? [] {
                        let d = (iz[i].p - p).uzunlik
                        if d < (eng?.1 ?? .infinity) { eng = (i, d) }
                    }
                } } }
                if let e = eng, e.1 <= Double(r) * ik { break }
            }
            guard let e = eng, e.1 <= 5.0 else { return nil }
            return iz[e.0].t
        }
    }

    static func sm(_ m: Double) -> String { String(format: "%.1f sm", m * 100).replacingOccurrences(of: ".", with: ",") }

    /// Natijani JSON ga (snake_case, kalitlar tartiblangan).
    public static func json(_ n: Natija) throws -> Data {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys]
        return try e.encode(n)
    }
}
