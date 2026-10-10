import Foundation

/// Qabul qilgichning joriy holati — NMEA xabarlaridan yig'iladi (T-057, T-150).
public struct QabulQilgichHolati: Equatable {
    public var lat: Double?
    public var lon: Double?
    public var balandlikEllipsoid: Double?
    public var rtk: RTKHolat = .yoq
    public var sputnikSoni: Int?
    public var hdop: Double?
    public var sigmaHSm: Double?
    public var sigmaVSm: Double?
    public var tuzatmaYoshiS: Double?
    public var bazaID: String?
    public var yonalishDeg: Double?
    public var vaqtUTC: String?
    public var sanaISO: String?
    public var oxirgiGGA: Date?
    public var oxirgiGST: Date?

    public init() {}

    /// GGA 2 s dan eski bo'lsa — qabul qilgich jim, holat "ma'lumot yo'q" deb ko'rsatiladi.
    public static let eskirishChekS: TimeInterval = 2.0

    public func eskirganmi(hozir: Date = Date()) -> Bool {
        guard let o = oxirgiGGA else { return true }
        return hozir.timeIntervalSince(o) > Self.eskirishChekS
    }

    public var pozitsiyaBormi: Bool { lat != nil && lon != nil }

    /// Joriy sifat — T-103. GST GGA dan 2 s dan ko'p orqada qolsa σ ishonchsiz → PAST.
    public func sifat(hozir: Date = Date()) -> Sifat {
        if eskirganmi(hozir: hozir) { return .past }
        if let g = oxirgiGGA, let s = oxirgiGST, abs(g.timeIntervalSince(s)) > Self.eskirishChekS {
            return .past
        }
        return SifatQoidasi.hisobla(rtk: rtk, sigmaHSm: sigmaHSm, sigmaVSm: sigmaVSm,
                                    tuzatmaYoshiS: tuzatmaYoshiS)
    }

    public mutating func qabul(_ x: NMEAXabar, hozir: Date = Date()) {
        switch x {
        case .gga(let g):
            lat = g.lat; lon = g.lon
            balandlikEllipsoid = g.balandlikEllipsoid
            rtk = g.rtk
            sputnikSoni = g.sputnikSoni
            hdop = g.hdop ?? hdop
            tuzatmaYoshiS = g.tuzatmaYoshiS
            bazaID = g.bazaID
            vaqtUTC = g.vaqtUTC
            oxirgiGGA = hozir
        case .gst(let s):
            sigmaHSm = s.sigmaHSm
            sigmaVSm = s.sigmaVSm
            oxirgiGST = hozir
        case .rmc(let r):
            if let s = r.sanaISO { sanaISO = s }
        case .hdt(let h):
            yonalishDeg = h.yonalishDeg
        case .gsa(let a):
            if let h = a.hdop { hdop = h }
        case .boshqa:
            break
        }
    }

    /// ISO vaqt `yyyy-mm-ddThh:mm:ssZ` — GGA vaqti + RMC sanasi. Sana yo'q bo'lsa `sana` parametri.
    public func vaqtISO(zaxiraSana: String? = nil) -> String? {
        guard let v = vaqtUTC, v.count >= 6 else { return nil }
        guard let sana = sanaISO ?? zaxiraSana else { return nil }
        let hh = v.prefix(2), mm = v.dropFirst(2).prefix(2), ss = v.dropFirst(4).prefix(2)
        return "\(sana)T\(hh):\(mm):\(ss)Z"
    }

    /// Serverga yuboriladigan nuqta (T-035 metama'lumoti bilan). Vexa uchi = antenna − vexa balandligi.
    public func nuqta(chuqurlikM: Double?, antennaBalandligiM: Double, qiyshayishDeg: Double? = nil,
                      qurilmaSeriya: String?, tuzatmaManbai: String?, izoh: String? = nil,
                      hozir: Date = Date(), zaxiraSana: String? = nil) -> NuqtaYozuvi? {
        guard let lat = lat, let lon = lon else { return nil }
        return NuqtaYozuvi(
            lat: lat, lon: lon,
            balandlik: balandlikEllipsoid.map { $0 - antennaBalandligiM },
            chuqurlik_m: chuqurlikM,
            rtk_holat: rtk.rawValue,
            sigma_h_sm: sigmaHSm, sigma_v_sm: sigmaVSm,
            tuzatma_yoshi_s: tuzatmaYoshiS,
            sputnik_soni: sputnikSoni,
            vaqt: vaqtISO(zaxiraSana: zaxiraSana),
            qurilma_seriya: qurilmaSeriya,
            tuzatma_manbai: tuzatmaManbai ?? bazaID,
            antenna_balandligi_m: antennaBalandligiM,
            qiyshayish_deg: qiyshayishDeg,
            izoh: izoh
        )
    }
}

/// Server `POST /api/v1/liniyalar` → `nuqtalar[]` elementi. Kalitlar server bilan bir xil.
public struct NuqtaYozuvi: Codable, Equatable {
    public var lat: Double
    public var lon: Double
    public var balandlik: Double?
    public var chuqurlik_m: Double?
    public var rtk_holat: String
    public var sigma_h_sm: Double?
    public var sigma_v_sm: Double?
    public var tuzatma_yoshi_s: Double?
    public var sputnik_soni: Int?
    public var vaqt: String?
    public var qurilma_seriya: String?
    public var tuzatma_manbai: String?
    public var antenna_balandligi_m: Double?
    public var qiyshayish_deg: Double?
    public var izoh: String?
    /// "rtk" (vexa uchi, bevosita) yoki "skan" (LiDAR + RTK georeferens). nil → server "rtk" deb oladi.
    public var manba: String?

    public init(lat: Double, lon: Double, balandlik: Double? = nil, chuqurlik_m: Double? = nil, rtk_holat: String,
                sigma_h_sm: Double? = nil, sigma_v_sm: Double? = nil, tuzatma_yoshi_s: Double? = nil,
                sputnik_soni: Int? = nil, vaqt: String? = nil, qurilma_seriya: String? = nil,
                tuzatma_manbai: String? = nil, antenna_balandligi_m: Double? = nil, qiyshayish_deg: Double? = nil,
                izoh: String? = nil, manba: String? = nil) {
        self.lat = lat; self.lon = lon; self.balandlik = balandlik; self.chuqurlik_m = chuqurlik_m
        self.rtk_holat = rtk_holat; self.sigma_h_sm = sigma_h_sm; self.sigma_v_sm = sigma_v_sm
        self.tuzatma_yoshi_s = tuzatma_yoshi_s; self.sputnik_soni = sputnik_soni; self.vaqt = vaqt
        self.qurilma_seriya = qurilma_seriya; self.tuzatma_manbai = tuzatma_manbai
        self.antenna_balandligi_m = antenna_balandligi_m; self.qiyshayish_deg = qiyshayish_deg
        self.izoh = izoh; self.manba = manba
    }

    /// Mahalliy baho — server qayta hisoblaydi, lekin ekranda darhol ko'rsatish uchun.
    public var sifat: Sifat {
        SifatQoidasi.hisobla(rtk: RTKHolat(rawValue: rtk_holat) ?? .yoq, sigmaHSm: sigma_h_sm,
                             sigmaVSm: sigma_v_sm, tuzatmaYoshiS: tuzatma_yoshi_s)
    }
}
