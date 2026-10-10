import Foundation
import Observation
import Security
import YerostiGeometriya
import YerostiHUD

// MARK: - Loyiha modeli (oflayn — Documents/loyihalar.json, T-051)

struct Loyiha: Codable, Identifiable, Hashable {
    var id = UUID()
    var nomi: String
    var manzil = ""
    var buyurtmachi = ""
    var pudratchi = ""
    var orderRaqami = ""
    /// ShN-01 (ShNK 3.01.03-24, 420-band): qazish orderi sanasi "YYYY-MM-DD". Ixtiyoriy — eski JSON da yo'q.
    var orderSana: String?
    var tarmoqTuri = "suv"
    var material = ""
    var yaratilgan = Date()
    var serverId: Int?
    var skanlar: [SkanYozuvi] = []
    /// LK-01/LK-02: geodezik asos. Ixtiyoriy — eski loyihalar.json da bu kalitlar yo'q (yo'qsa dekodlash buziladi).
    var nazoratPunktlar: [NazoratPunkt]?
    var nazoratOlchovlar: [NazoratOlchov]?
    /// TQ-01 (T-031): quvur ustidagi RTK tasdiqlari. Ixtiyoriy — eski JSON da yo'q.
    var quvurTasdiqlari: [QuvurTasdigi]?
}

extension Loyiha {
    /// ShN-01: server `order_matn` bilan bir xil shakl — «raqam, DD.MM.YYYY»; ikkalasi yo'q bo'lsa bo'sh.
    var orderMatn: String {
        let r = orderRaqami.trimmingCharacters(in: .whitespaces)
        let d = (orderSana ?? "").trimmingCharacters(in: .whitespaces)
        let ch = d.split(separator: "-")
        let uz = ch.count == 3 && d.count == 10 ? "\(ch[2]).\(ch[1]).\(ch[0])" : d
        if r.isEmpty && uz.isEmpty { return "" }
        return (r.isEmpty ? "raqam yo'q" : r) + ", " + (uz.isEmpty ? "sana yo'q" : uz)
    }

    /// "YYYY-MM-DD" — telefonning mahalliy kuni (Gregorian, POSIX).
    static func isoSana(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func sanadan(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}

/// TQ-01 (T-031): vexa uchi quvur USTIDA (yoki ochiq uchida O'QIDA) turgandagi RTK FIX o'lchovi — skan o'qini tasdiqlaydi.
/// h — vexa uchi (antenna balandligi ayirilgan), ellipsoid.
struct QuvurTasdigi: Codable, Identifiable, Hashable {
    var id = UUID()
    var nomi: String
    var lat: Double
    var lon: Double
    var h: Double?
    var sigmaHSm: Double
    var sigmaVSm: Double
    var epoxalar: Int
    var davomiylikS: Double
    var antennaM: Double
    /// "usti" — quvur usti (o'q + D/2), "oq" — ochiq uchida o'q.
    var joy = "usti"
    var vaqt: Date
    var serverId: Int?
}

/// LK-01: shahar geodezik tarmog'i yoki qurilish razbivka asosi punkti: mahalliy X (shimol), Y (sharq), Boltiq H.
/// Faqat balandligi ma'lum reperda X va Y bo'sh.
struct NazoratPunkt: Codable, Identifiable, Hashable {
    var id = UUID()
    var nomi: String
    var x: Double?
    var y: Double?
    var h: Double?
    var sinf = ""
}

/// LK-02: punkt ustida ≥ 30 s uzluksiz FIX o'rtachasi. h — punkt belgisi (antenna balandligi ayirilgan), ellipsoid.
struct NazoratOlchov: Codable, Identifiable, Hashable {
    var id = UUID()
    var punktNomi: String
    /// "kalibrlash" yoki "tekshiruv" (LK-05: tekshiruv kalibrlashga kirmaydi).
    var maqsad: String
    var lat: Double
    var lon: Double
    var h: Double?
    var sigmaHSm: Double
    var sigmaVSm: Double
    var epoxalar: Int
    var davomiylikS: Double
    var antennaM: Double
    var vaqt: Date
    /// Serverdagi yozuv id si (yuborilgan yoki serverdan olingan) — qayta yuborilmaydi.
    var serverId: Int?
}

extension Loyiha {
    var punktlar: [NazoratPunkt] { nazoratPunktlar ?? [] }
    var olchovlar: [NazoratOlchov] { nazoratOlchovlar ?? [] }
    var tasdiqlar: [QuvurTasdigi] { quvurTasdiqlari ?? [] }

    /// LK-03: joyida lokalizatsiya — server bilan bir xil yadro (`Lokalizatsiya`), kalibrlash o'lchovlari punkt
    /// bo'yicha o'rtachalanadi. O'lchov yo'q — nil.
    func lokalizatsiya() -> LokNatija? {
        let guruh = Dictionary(grouping: olchovlar.filter { $0.maqsad == "kalibrlash" }, by: \.punktNomi)
        let juftlar: [LokalizatsiyaJufti] = punktlar.compactMap { p in
            guard let g = guruh[p.nomi], !g.isEmpty else { return nil }
            let k = Double(g.count), hlar = g.compactMap(\.h)
            return LokalizatsiyaJufti(nomi: p.nomi, lat: g.map(\.lat).reduce(0, +) / k, lon: g.map(\.lon).reduce(0, +) / k,
                                      h: hlar.isEmpty ? nil : hlar.reduce(0, +) / Double(hlar.count), x: p.x, y: p.y, H: p.h)
        }
        return try? Lokalizatsiya.hisobla(juftlar)
    }

    /// LK-05: bugungi tekshiruv holati (tayyorlik varag'i). Qoida server bilan bir xil: bugungi tekshiruv o'lchovlari
    /// baholanadi; ular bo'lmasa, bugun yaroqli lokalizatsiyaga kirgan kalibrlash o'lchovi ham tekshiruv hisoblanadi.
    func bugungiNazorat(hozir: Date = Date()) -> NazoratHolati {
        guard !punktlar.isEmpty else { return .punktYoq }
        let bugun = olchovlar.filter { Calendar.current.isDate($0.vaqt, inSameDayAs: hozir) }
        guard let lok = lokalizatsiya() else { return .bugunYoq }
        var engKatta: Double?, otdi = true
        for o in bugun where o.maqsad == "tekshiruv" {
            guard let p = punktlar.first(where: { $0.nomi == o.punktNomi }) else { continue }
            let t = Lokalizatsiya.tekshiruv(lok.parametrlar, lat: o.lat, lon: o.lon, h: o.h, x: p.x, y: p.y, H: p.h)
            engKatta = max(engKatta ?? 0, max(t.gor ?? 0, abs(t.ver ?? 0)))
            if !t.otdi { otdi = false }
        }
        if let d = engKatta { return otdi ? .bugunOtdi(d) : .bugunOtmadi(d) }
        if lok.yaroqli, bugun.contains(where: { $0.maqsad == "kalibrlash" }) { return .bugunOtdi(lok.maksGor ?? 0) }
        return .bugunYoq
    }
}

struct QuvurXulosa: Codable, Hashable {
    var tashqiDiametrMm: Double
    var standartMm: Double?
    var seriya: String?
    var chuqurlikM: Double?
    var qiyalikFoiz: Double
    var uzunlikM: Double
    var ishonch: Double
    var muftaSoni: Int
    /// O'q chizig'i ARKit mahalliy ramkasida (x, y, z).
    var oqMahalliy: [[Double]]
    /// UI-17: bo'ylama profil — [stansiya, markaz y] va [stansiya, yer sirti y] (ARKit y, m). Eski yozuvlarda yo'q.
    var profilOq: [[Double]]?
    var profilYer: [[Double]]?
}

struct GeorefXulosa: Codable, Hashable {
    var burchak: Double
    var t: [Double]
    var gorizontalRmsM: Double
    var vertikalRmsM: Double
    var juftSoni: Int
    var utmZona: Int
}

enum YuklashHolati: Codable, Hashable {
    case kutmoqda
    case yuklandi(muhrHolati: String)
    case xato(String)
}

struct SkanYozuvi: Codable, Identifiable, Hashable {
    var id = UUID()
    var papka: String
    var boshlandi: Date
    var tugadi: Date
    var kadrSoni: Int
    var masofaM: Double
    var meshMaydoniM2: Double
    var rasmiyKadrFoiz: Double?
    var yozuvSoni: Int
    var zanjirBoshi: String
    var georef: GeorefXulosa?
    var quvurlar: [QuvurXulosa]
    var yuklash: YuklashHolati = .kutmoqda
    /// DS-03…DS-06: telefonning o'zida muhrlangan jurnal bo'yicha qayta hisob (server bilan bir xil yadro). Eski yozuvlarda yo'q.
    var xom: XomSkanXulosa?
}

/// DS-04/05: skan yakunidagi qayta hisob xulosasi — yuklashda liniya nuqtalari shundan olinadi.
struct XomSkanXulosa: Codable, Hashable {
    var plyNomi: String
    var kechikishMs: Double?
    var kechikishIshonchli: Bool
    var bolaklar: Int
    var pastBolaklar: Int
    var maksTuzatishSm: Double?
    var ofsetFarqSm: Double?
    var ogohlantirishlar: [String]
    var quvurlar: [QuvurGeo]
}

/// Bo'lakli georeferensdagi quvur o'qi: WGS84 (lat, lon, ellipsoid h), har nuqta bo'lagi PAST mi va σ (sm).
struct QuvurGeo: Codable, Hashable {
    var tashqiDiametrMm: Double
    var standartMm: Double?
    var chuqurlikM: Double?
    var ishonch: Double
    var wgs84: [[Double]]
    var past: [Bool]
    var sigmaHSm: [Double]
    var sigmaVSm: [Double]
}

enum Papkalar {
    static var hujjatlar: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var ichki: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func skan(_ loyiha: Loyiha, _ skanId: UUID) -> URL {
        let u = hujjatlar.appendingPathComponent("Loyihalar/\(loyiha.id.uuidString)/\(skanId.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

@MainActor @Observable
final class LoyihaOmbori {
    private(set) var loyihalar: [Loyiha] = []
    @ObservationIgnored private let fayl = Papkalar.hujjatlar.appendingPathComponent("loyihalar.json")

    init() { yukla() }

    func yukla() {
        guard let d = try? Data(contentsOf: fayl) else { return }
        let dek = JSONDecoder(); dek.dateDecodingStrategy = .iso8601
        loyihalar = (try? dek.decode([Loyiha].self, from: d)) ?? []
    }

    private func saqla() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(loyihalar) { try? d.write(to: fayl, options: [.atomic, .completeFileProtection]) }
    }

    func qosh(_ l: Loyiha) { loyihalar.insert(l, at: 0); saqla() }

    func yangila(_ l: Loyiha) {
        guard let i = loyihalar.firstIndex(where: { $0.id == l.id }) else { return }
        loyihalar[i] = l; saqla()
    }

    func skanQosh(_ s: SkanYozuvi, loyihaId: UUID) {
        guard let i = loyihalar.firstIndex(where: { $0.id == loyihaId }) else { return }
        loyihalar[i].skanlar.insert(s, at: 0); saqla()
    }

    func skanYangila(_ s: SkanYozuvi, loyihaId: UUID) {
        guard let i = loyihalar.firstIndex(where: { $0.id == loyihaId }),
              let j = loyihalar[i].skanlar.firstIndex(where: { $0.id == s.id }) else { return }
        loyihalar[i].skanlar[j] = s; saqla()
    }

    func loyiha(_ id: UUID) -> Loyiha? { loyihalar.first { $0.id == id } }

    /// LK-01: shu nomli punkt bo'lsa almashtiriladi (katalog yangilangan).
    func punktSaqla(_ p: NazoratPunkt, loyihaId: UUID) {
        guard let i = loyihalar.firstIndex(where: { $0.id == loyihaId }) else { return }
        var r = loyihalar[i].punktlar.filter { $0.nomi != p.nomi }
        r.append(p)
        loyihalar[i].nazoratPunktlar = r.sorted { $0.nomi.localizedStandardCompare($1.nomi) == .orderedAscending }
        saqla()
    }

    func olchovSaqla(_ o: NazoratOlchov, loyihaId: UUID) {
        guard let i = loyihalar.firstIndex(where: { $0.id == loyihaId }) else { return }
        var r = loyihalar[i].olchovlar.filter { $0.id != o.id }
        r.append(o)
        loyihalar[i].nazoratOlchovlar = r.sorted { $0.vaqt < $1.vaqt }
        saqla()
    }

    func olchovOchir(_ id: UUID, loyihaId: UUID) {
        guard let i = loyihalar.firstIndex(where: { $0.id == loyihaId }) else { return }
        loyihalar[i].nazoratOlchovlar = loyihalar[i].olchovlar.filter { $0.id != id }
        saqla()
    }

    /// TQ-01: tasdiq saqlanadi (bor bo'lsa almashtiriladi — serverId yangilanishi uchun).
    func tasdiqSaqla(_ t: QuvurTasdigi, loyihaId: UUID) {
        guard let i = loyihalar.firstIndex(where: { $0.id == loyihaId }) else { return }
        var r = loyihalar[i].tasdiqlar.filter { $0.id != t.id }
        r.append(t)
        loyihalar[i].quvurTasdiqlari = r.sorted { $0.vaqt < $1.vaqt }
        saqla()
    }

    func tasdiqOchir(_ id: UUID, loyihaId: UUID) {
        guard let i = loyihalar.firstIndex(where: { $0.id == loyihaId }) else { return }
        loyihalar[i].quvurTasdiqlari = loyihalar[i].tasdiqlar.filter { $0.id != id }
        saqla()
    }
}

// MARK: - Sozlamalar (maxfiylar — Keychain)

@MainActor @Observable
final class Sozlamalar {
    var serverManzil: String
    var dalaToken: String
    var ntripHost: String
    var ntripPort: Int
    var ntripMountpoint: String
    var ntripLogin: String
    var ntripParol: String
    var ntripVersiya: Int
    var tcpHost: String
    var tcpPort: Int
    /// Antenna fazaviy markazining kameraga nisbatan siljishi, portret ramkasida (m): x o'ng, y yuqori, z foydalanuvchiga.
    var antennaOfset: [Double]
    /// NMEA kelish kechikishi (s) — kamera pozasini shu vaqtga interpolyatsiya qilamiz.
    var rtkKechikishS: Double
    /// UI-09: tebranish (haptika) — foydalanuvchi o'chira oladi (HIG: haptika ixtiyoriy bo'lsin).
    var haptika: Bool
    /// DS-02: dastak ("yo'q", "emlid-skan", "vexa"), telefon tomoni ("o'ng", "chap") va ofset manbasi ("qo'lda", "jadval").
    var dastak: String
    var dastakTomoni: String
    var ofsetManba: String
    /// DS-06: LiDAR chuqurlik kadrlaridan zich rangli bulut (quvur shundan topiladi).
    var zichBulut: Bool

    /// Ekran yopilganda va ulanishda chaqiriladi (maxfiylar — Keychain, qolgani — UserDefaults).
    func saqla() {
        let u = UserDefaults.standard
        u.set(serverManzil, forKey: "serverManzil"); u.set(ntripHost, forKey: "ntripHost")
        u.set(ntripPort, forKey: "ntripPort"); u.set(ntripMountpoint, forKey: "ntripMountpoint")
        u.set(ntripLogin, forKey: "ntripLogin"); u.set(ntripVersiya, forKey: "ntripVersiya")
        u.set(tcpHost, forKey: "tcpHost"); u.set(tcpPort, forKey: "tcpPort")
        u.set(antennaOfset, forKey: "antennaOfset"); u.set(rtkKechikishS, forKey: "rtkKechikishS")
        u.set(haptika, forKey: "haptika")
        u.set(dastak, forKey: "dastak"); u.set(dastakTomoni, forKey: "dastakTomoni"); u.set(ofsetManba, forKey: "ofsetManba")
        u.set(zichBulut, forKey: "zichBulut")
        Kalitlar.yoz("dalaToken", dalaToken); Kalitlar.yoz("ntripParol", ntripParol)
    }

    init() {
        let u = UserDefaults.standard
        serverManzil = u.string(forKey: "serverManzil") ?? ""
        dalaToken = Kalitlar.oqi("dalaToken") ?? ""
        ntripHost = u.string(forKey: "ntripHost") ?? ""
        ntripPort = u.object(forKey: "ntripPort") as? Int ?? 2101
        ntripMountpoint = u.string(forKey: "ntripMountpoint") ?? ""
        ntripLogin = u.string(forKey: "ntripLogin") ?? ""
        ntripParol = Kalitlar.oqi("ntripParol") ?? ""
        ntripVersiya = u.object(forKey: "ntripVersiya") as? Int ?? 2
        tcpHost = u.string(forKey: "tcpHost") ?? "192.168.42.1"
        tcpPort = u.object(forKey: "tcpPort") as? Int ?? 9001
        antennaOfset = u.array(forKey: "antennaOfset") as? [Double] ?? [0, 0, 0]
        rtkKechikishS = u.object(forKey: "rtkKechikishS") as? Double ?? 0.08
        dastak = u.string(forKey: "dastak") ?? "emlid-skan"
        dastakTomoni = u.string(forKey: "dastakTomoni") ?? "o'ng"
        ofsetManba = u.string(forKey: "ofsetManba") ?? "qo'lda"
        zichBulut = u.object(forKey: "zichBulut") as? Bool ?? true
        haptika = u.object(forKey: "haptika") as? Bool ?? true
    }

    /// UI-01: antenna ofseti kiritilganmi (hammasi 0 — kiritilmagan deb hisoblanadi).
    var antennaOfsetKiritilgan: Bool { antennaOfset.contains { $0 != 0 } }
}

/// Keychain — dala tokeni va NTRIP paroli ochiq matnda saqlanmaydi.
enum Kalitlar {
    static let xizmat = "uz.trace4d.scan"

    static func yoz(_ kalit: String, _ qiymat: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: xizmat,
                                kSecAttrAccount as String: kalit]
        SecItemDelete(q as CFDictionary)
        guard !qiymat.isEmpty else { return }
        var y = q
        y[kSecValueData as String] = Data(qiymat.utf8)
        y[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(y as CFDictionary, nil)
    }

    static func oqi(_ kalit: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: xizmat,
                                kSecAttrAccount as String: kalit, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var natija: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &natija) == errSecSuccess, let d = natija as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
