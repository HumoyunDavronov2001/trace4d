import Foundation

/// Muhr jurnali yozuv turlari. Jurnal fayli: "YMJ1" + [tur:1][uzunlik:4 BE][ma'lumot]...
public enum YozuvTuri: UInt8, Codable, Sendable {
    case nmea = 1       // xom NMEA satri (qabul qilgichdan kelgan baytlar)
    case kadr = 2       // kadr metama'lumoti (JSON): vaqt, kamera pozasi, RTK holati, sifat
    case mesh = 3       // mesh bo'lagi xeshi (JSON)
    case nuqta = 4      // RTK nuqta (JSON)
    case belgi = 5      // operator belgisi (quvur turi, mufta...)
    case fayl = 6       // tashqi fayl xeshi (JSON: nomi, sha256, hajm)
    case izoh = 7
    case rtcm = 8       // tuzatma oqimi bo'lagi xeshi
}

/// K-05: o'zgartirib bo'lmaydigan xesh-zanjir.
/// h₀ = SHA256("YEROSTI-MUHR-v1"),  hᵢ = SHA256(hᵢ₋₁ ‖ tur ‖ uzunlik(4B BE) ‖ ma'lumot).
/// Bitta bayt o'zgarsa, keyingi barcha xeshlar va yakuniy "bosh" o'zgaradi.
public struct MuhrZanjir: Sendable {
    public static let versiya = "YEROSTI-MUHR-v1"
    public static let jurnalSarlavha: [UInt8] = Array("YMJ1".utf8)
    public static var boshlangich: [UInt8] { SHA256.xesh(Array(versiya.utf8)) }

    public private(set) var bosh: [UInt8] = MuhrZanjir.boshlangich
    public private(set) var soni = 0

    public init() {}

    /// Yozuv qo'shadi va jurnalga yoziladigan baytlarni qaytaradi.
    @discardableResult
    public mutating func qosh(_ tur: YozuvTuri, _ malumot: [UInt8]) -> [UInt8] {
        let n = UInt32(malumot.count)
        let sarlavha: [UInt8] = [tur.rawValue, UInt8(n >> 24), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)]
        var s = SHA256()
        s.yangila(bosh)
        s.yangila(sarlavha)
        s.yangila(malumot)
        bosh = s.yakunla()
        soni += 1
        return sarlavha + malumot
    }

    @discardableResult
    public mutating func qosh(_ tur: YozuvTuri, matn: String) -> [UInt8] { qosh(tur, Array(matn.utf8)) }

    public var boshHex: String { SHA256.hex(bosh) }

    /// Jurnal faylini qayta o'qib zanjirni tiklash (server shu ishni Pythonda qiladi).
    public static func tekshir(jurnal: [UInt8]) -> (boshHex: String, soni: Int)? {
        guard jurnal.count >= 4, Array(jurnal[0..<4]) == jurnalSarlavha else { return nil }
        var z = MuhrZanjir()
        var i = 4
        while i < jurnal.count {
            guard i + 5 <= jurnal.count, let tur = YozuvTuri(rawValue: jurnal[i]) else { return nil }
            let n = Int(jurnal[i + 1]) << 24 | Int(jurnal[i + 2]) << 16 | Int(jurnal[i + 3]) << 8 | Int(jurnal[i + 4])
            guard i + 5 + n <= jurnal.count else { return nil }
            z.qosh(tur, Array(jurnal[(i + 5)..<(i + 5 + n)]))
            i += 5 + n
        }
        return (z.boshHex, z.soni)
    }
}

/// Imzolanadigan manifest. Kalitlar tartiblangan, bo'shliqsiz JSON — server bayt-baytga qayta quradi.
public struct MuhrManifest: Codable, Equatable, Sendable {
    public struct Fayl: Codable, Equatable, Sendable {
        public var nomi: String
        public var sha256: String
        public var hajm: Int
        public init(nomi: String, sha256: String, hajm: Int) { self.nomi = nomi; self.sha256 = sha256; self.hajm = hajm }
    }
    public var versiya: String = MuhrZanjir.versiya
    public var obyektId: Int
    public var qurilma: String
    public var boshlandi: String
    public var tugadi: String
    public var yozuvSoni: Int
    public var zanjirBoshi: String
    public var fayllar: [Fayl]

    public init(obyektId: Int, qurilma: String, boshlandi: String, tugadi: String, yozuvSoni: Int,
                zanjirBoshi: String, fayllar: [Fayl]) {
        self.obyektId = obyektId; self.qurilma = qurilma; self.boshlandi = boshlandi; self.tugadi = tugadi
        self.yozuvSoni = yozuvSoni; self.zanjirBoshi = zanjirBoshi; self.fayllar = fayllar
    }

    enum CodingKeys: String, CodingKey {
        case versiya, qurilma, boshlandi, tugadi, fayllar
        case obyektId = "obyekt_id", yozuvSoni = "yozuv_soni", zanjirBoshi = "zanjir_boshi"
    }

    /// Imzolanadigan kanonik baytlar.
    public func kanonik() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }
}
