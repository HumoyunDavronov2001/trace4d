import Foundation

public enum NMEAXato: Error, Equatable {
    case notogriFormat
    case kontrolSummaMosEmas
}

/// Xom NMEA gapi: `$GNGGA,...*HH` — kontrol summa tekshirilgan, maydonlarga ajratilgan.
public struct NMEAGap: Equatable {
    public let talker: String
    public let turi: String
    public let maydonlar: [String]

    public static func ajrat(_ satr: String) throws -> NMEAGap {
        var s = satr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("$") else { throw NMEAXato.notogriFormat }
        s.removeFirst()
        guard let yulduz = s.lastIndex(of: "*") else { throw NMEAXato.notogriFormat }
        let tana = String(s[s.startIndex..<yulduz])
        let hex = String(s[s.index(after: yulduz)...])
        guard hex.count == 2, let berilgan = UInt8(hex, radix: 16) else { throw NMEAXato.notogriFormat }
        var xor: UInt8 = 0
        for b in tana.utf8 { xor ^= b }
        guard xor == berilgan else { throw NMEAXato.kontrolSummaMosEmas }
        let qismlar = tana.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let manzil = qismlar.first, manzil.count >= 3 else { throw NMEAXato.notogriFormat }
        let talker = manzil.count > 3 ? String(manzil.prefix(manzil.count - 3)) : ""
        return NMEAGap(talker: talker, turi: String(manzil.suffix(3)), maydonlar: Array(qismlar.dropFirst()))
    }

    /// Yuborishdan oldin gap yasash (kontrol summa bilan) — sinov va RTCM/buyruq uchun.
    public static func yasa(_ tana: String) -> String {
        var xor: UInt8 = 0
        for b in tana.utf8 { xor ^= b }
        return "$" + tana + "*" + String(format: "%02X", xor)
    }

    func maydon(_ i: Int) -> String? { i < maydonlar.count && !maydonlar[i].isEmpty ? maydonlar[i] : nil }
    func son(_ i: Int) -> Double? { maydon(i).flatMap { Double($0) } }
    func butun(_ i: Int) -> Int? { maydon(i).flatMap { Int($0) } }

    /// `ddmm.mmmm` / `dddmm.mmmm` → daraja (yarim shar belgisi bilan).
    func koordinata(_ i: Int, yarimShar j: Int) -> Double? {
        guard let v = son(i), let ys = maydon(j) else { return nil }
        let daraja = floor(v / 100)
        let daqiqa = v - daraja * 100
        let q = daraja + daqiqa / 60
        return (ys == "S" || ys == "W") ? -q : q
    }
}

/// GGA — pozitsiya, fix sifati, sputniklar, tuzatma yoshi.
public struct GGA: Equatable {
    public let vaqtUTC: String?
    public let lat: Double?
    public let lon: Double?
    public let sifatKodi: Int
    public let rtk: RTKHolat
    public let sputnikSoni: Int?
    public let hdop: Double?
    public let balandlikMSL: Double?
    public let geoidFarqi: Double?
    public let tuzatmaYoshiS: Double?
    public let bazaID: String?

    public init?(_ g: NMEAGap) {
        guard g.turi == "GGA", g.maydonlar.count >= 9 else { return nil }
        vaqtUTC = g.maydon(0)
        lat = g.koordinata(1, yarimShar: 2)
        lon = g.koordinata(3, yarimShar: 4)
        sifatKodi = g.butun(5) ?? 0
        rtk = RTKHolat(ggaSifatKodi: sifatKodi)
        sputnikSoni = g.butun(6)
        hdop = g.son(7)
        balandlikMSL = g.son(8)
        geoidFarqi = g.son(10)
        tuzatmaYoshiS = g.son(12)
        bazaID = g.maydon(13)
    }

    /// Ellipsoid balandligi (RTK uchun asosiy): MSL + geoid farqi.
    public var balandlikEllipsoid: Double? {
        guard let m = balandlikMSL else { return nil }
        return m + (geoidFarqi ?? 0)
    }
}

/// GST — pozitsiya xatosi statistikasi (σ, metrda).
public struct GST: Equatable {
    public let vaqtUTC: String?
    public let rmsM: Double?
    public let sigmaKattaM: Double?
    public let sigmaKichikM: Double?
    public let orientatsiyaDeg: Double?
    public let sigmaLatM: Double?
    public let sigmaLonM: Double?
    public let sigmaAltM: Double?

    public init?(_ g: NMEAGap) {
        guard g.turi == "GST", g.maydonlar.count >= 8 else { return nil }
        vaqtUTC = g.maydon(0)
        rmsM = g.son(1)
        sigmaKattaM = g.son(2)
        sigmaKichikM = g.son(3)
        orientatsiyaDeg = g.son(4)
        sigmaLatM = g.son(5)
        sigmaLonM = g.son(6)
        sigmaAltM = g.son(7)
    }

    /// Gorizontal σ (sm) = √(σlat² + σlon²) — server bilan kelishilgan formula.
    public var sigmaHSm: Double? {
        guard let a = sigmaLatM, let b = sigmaLonM else { return nil }
        return (a * a + b * b).squareRoot() * 100
    }
    public var sigmaVSm: Double? { sigmaAltM.map { $0 * 100 } }
}

/// RMC — sana, holat, tezlik, kurs.
public struct RMC: Equatable {
    public let vaqtUTC: String?
    public let faol: Bool
    public let lat: Double?
    public let lon: Double?
    public let tezlikUzel: Double?
    public let kursDeg: Double?
    public let sanaDDMMYY: String?

    public init?(_ g: NMEAGap) {
        guard g.turi == "RMC", g.maydonlar.count >= 9 else { return nil }
        vaqtUTC = g.maydon(0)
        faol = g.maydon(1) == "A"
        lat = g.koordinata(2, yarimShar: 3)
        lon = g.koordinata(4, yarimShar: 5)
        tezlikUzel = g.son(6)
        kursDeg = g.son(7)
        sanaDDMMYY = g.maydon(8)
    }

    /// `ddmmyy` → ISO `yyyy-mm-dd`.
    public var sanaISO: String? {
        guard let s = sanaDDMMYY, s.count == 6 else { return nil }
        let kun = String(s.prefix(2))
        let oy = String(s.dropFirst(2).prefix(2))
        let yil = String(s.suffix(2))
        return "20\(yil)-\(oy)-\(kun)"
    }
}

/// HDT — haqiqiy yo'nalish (ikki antennali qabul qilgichlarda).
public struct HDT: Equatable {
    public let yonalishDeg: Double?
    public init?(_ g: NMEAGap) {
        guard g.turi == "HDT" else { return nil }
        yonalishDeg = g.son(0)
    }
}

/// GSA — DOP qiymatlari.
public struct GSA: Equatable {
    public let pdop: Double?
    public let hdop: Double?
    public let vdop: Double?
    public init?(_ g: NMEAGap) {
        guard g.turi == "GSA", g.maydonlar.count >= 17 else { return nil }
        pdop = g.son(14)
        hdop = g.son(15)
        vdop = g.son(16)
    }
}

public enum NMEAXabar: Equatable {
    case gga(GGA)
    case gst(GST)
    case rmc(RMC)
    case hdt(HDT)
    case gsa(GSA)
    case boshqa(NMEAGap)

    public static func ajrat(_ satr: String) throws -> NMEAXabar {
        let g = try NMEAGap.ajrat(satr)
        switch g.turi {
        case "GGA": if let x = GGA(g) { return .gga(x) }
        case "GST": if let x = GST(g) { return .gst(x) }
        case "RMC": if let x = RMC(g) { return .rmc(x) }
        case "HDT": if let x = HDT(g) { return .hdt(x) }
        case "GSA": if let x = GSA(g) { return .gsa(x) }
        default: break
        }
        return .boshqa(g)
    }
}
