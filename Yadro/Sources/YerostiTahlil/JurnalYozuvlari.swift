import Foundation
import YerostiGeometriya

/// Yadro versiyasi — telefon muhr jurnaliga yozadi, data markaz o'zinikini solishtiradi (DM-02).
public enum YadroVersiya {
    public static let matn = "2026.10.05"
}

// MARK: - Muhr jurnalidagi JSON yozuvlar (telefon YOZADI, data markaz O'QIYDI — shakl bitta joyda)

/// Georeferens jufti: antenna fazaviy markazi ARKit→ENU mahalliy ramkada (`m`, metr) va shu epoxadagi
/// RTK pozitsiyasi UTM da (`g`: sharq, shimol, ellipsoid balandligi). Faqat RASMIY epoxalar (T-103).
public struct JuftYozuvi: Codable, Equatable, Sendable {
    public var tur = "juft"
    public var m: [Double]
    public var g: [Double]
    public var zona: Int
    /// DS-03: juftlangan poza vaqti va epoxaning telefonga kelgan vaqti (uptime, s). Eski jurnallarda yo'q.
    public var t: Double?
    public var te: Double?

    public init(m: Vektor3, g: Vektor3, zona: Int, t: Double? = nil, te: Double? = nil) {
        self.m = [m.x, m.y, m.z]
        self.g = [g.x, g.y, g.z]
        self.zona = zona
        self.t = t
        self.te = te
    }

    public var mahalliy: Vektor3 { Vektor3(m[0], m[1], m[2]) }
    public var global: Vektor3 { Vektor3(g[0], g[1], g[2]) }
    public var togri: Bool { m.count == 3 && g.count == 3 && (1...60).contains(zona) }
}

/// Skan yakunidagi georeferens (telefon hisoblagan): mahalliy ENU → UTM.
public struct GeorefYozuvi: Codable, Equatable, Sendable {
    public var tur = "georef"
    public var burchak: Double
    public var t: [Double]
    public var rmsH: Double
    public var rmsV: Double
    public var juft: Int
    public var utmZona: Int

    public init(_ n: GorizontalNatija, zona: Int) {
        burchak = n.transformatsiya.burchak
        t = [n.transformatsiya.t.x, n.transformatsiya.t.y, n.transformatsiya.t.z]
        rmsH = n.gorizontalRmsM
        rmsV = n.vertikalRmsM
        juft = n.soni
        utmZona = zona
    }

    public var transformatsiya: GorizontalTransformatsiya? {
        t.count == 3 ? GorizontalTransformatsiya(burchak: burchak, t: Vektor3(t[0], t[1], t[2])) : nil
    }
}

/// Telefon aniqlagan quvur (o'q ARKit mahalliy ramkasida). Skan yakunida PLY fayl yozuvidan keyin keladi.
public struct QuvurYozuvi: Codable, Equatable, Sendable {
    public var tur = "quvur"
    public var diametrMm: Double
    public var standartMm: Double?
    public var chuqurlikM: Double?
    public var qiyalikFoiz: Double
    public var uzunlikM: Double
    public var ishonch: Double
    public var oq: [[Double]]

    public init(_ q: TopilganQuvur) {
        diametrMm = q.tashqiDiametrMm
        standartMm = q.standart?.tashqiMm
        chuqurlikM = q.qoplamaChuqurligiM
        qiyalikFoiz = q.qiyalikFoiz
        uzunlikM = q.uzunlikM
        ishonch = q.ishonch
        oq = q.oq.map { [$0.x, $0.y, $0.z] }
    }

    public var oqNuqtalar: [Vektor3] { oq.compactMap { $0.count == 3 ? Vektor3($0[0], $0[1], $0[2]) : nil } }
}

// MARK: - DS-03: xom yozuv (poza izi, GGA kelish vaqti, profil, chuqurlik kadri)

/// ARKit poza izi — ~1 s lik to'plam (har kadr, 60 Hz). Ixcham butun sonlar: `t0` + `dt` (mikrosekund),
/// `p` — kamera markazi ARKit dunyosida (0,1 mm), `q` — burilish kvaternioni [x, y, z, w] (10⁻⁶).
/// `.kadr` turida yoziladi (eski o'quvchilar «tur» siz kadr metama'lumotini kutadi — bu yozuvni o'tkazib yuboradi).
public struct IzYozuvi: Codable, Equatable, Sendable {
    public var tur = "iz"
    public var t0: Double
    public var dt: [Int]
    public var p: [[Int]]
    public var q: [[Int]]

    public init(_ n: [PozaNamuna]) {
        let b = n.first?.t ?? 0
        t0 = b
        dt = n.map { Int((($0.t - b) * 1e6).rounded()) }
        p = n.map { [Int(($0.p.x * 1e4).rounded()), Int(($0.p.y * 1e4).rounded()), Int(($0.p.z * 1e4).rounded())] }
        q = n.map { x in
            let k = x.q.normallangan
            return [Int((k.x * 1e6).rounded()), Int((k.y * 1e6).rounded()), Int((k.z * 1e6).rounded()), Int((k.w * 1e6).rounded())]
        }
    }

    public var togri: Bool {
        dt.count == p.count && dt.count == q.count && p.allSatisfy { $0.count == 3 } && q.allSatisfy { $0.count == 4 }
    }

    public var namunalar: [PozaNamuna] {
        guard togri else { return [] }
        return (0..<dt.count).map { i in
            PozaNamuna(t: t0 + Double(dt[i]) / 1e6,
                       p: Vektor3(Double(p[i][0]) / 1e4, Double(p[i][1]) / 1e4, Double(p[i][2]) / 1e4),
                       q: Kvaternion(Double(q[i][0]) / 1e6, Double(q[i][1]) / 1e6, Double(q[i][2]) / 1e6, Double(q[i][3]) / 1e6).normallangan)
        }
    }
}

/// Oldingi `.nmea` yozuvidagi GGA satri telefonga kelgan vaqt (uptime, s) — kechikishni baholash uchun (DS-04).
/// `.nuqta` turida, GGA satridan darhol keyin yoziladi.
public struct NMEAVaqtYozuvi: Codable, Equatable, Sendable {
    public var tur = "nmea_t"
    public var te: Double
    public init(te: Double) { self.te = te }
}

/// DS-02: skan boshidagi qurilma va dastak profili — antenna ofseti va kechikish qayerdan olingani muhrlanadi.
/// `antennaOfset` — portret ramkasi (x o'ng, y yuqori, z foydalanuvchiga), kameradan antenna fazaviy markazigacha, m.
public struct ProfilYozuvi: Codable, Equatable, Sendable {
    public var tur = "profil"
    public var qabulQilgich: String
    public var seriya: String?
    public var iphone: String
    public var dastak: String
    public var tomon: String
    public var antennaOfset: [Double]
    public var kechikishS: Double
    /// "jadval" — tasdiqlangan profil jadvalidan, "qo'lda" — administrator kiritgan, "yo'q" — ofset noma'lum.
    public var manba: String

    public init(qabulQilgich: String, seriya: String?, iphone: String, dastak: String, tomon: String,
                antennaOfset: [Double], kechikishS: Double, manba: String) {
        self.qabulQilgich = qabulQilgich; self.seriya = seriya; self.iphone = iphone; self.dastak = dastak
        self.tomon = tomon; self.antennaOfset = antennaOfset; self.kechikishS = kechikishS; self.manba = manba
    }
}

/// DS-06: zich bulutga qo'shilgan chuqurlik kadri (xom kadr saqlanmaydi): tartib, vaqt, qo'shilgan piksel soni va
/// xom chuqurlik baytlarining SHA-256 i. `.kadr` turida.
public struct ChuqurlikYozuvi: Codable, Equatable, Sendable {
    public var tur = "chuqurlik"
    public var i: Int
    public var t: Double
    public var n: Int
    public var sha256: String
    public init(i: Int, t: Double, n: Int, sha256: String) { self.i = i; self.t = t; self.n = n; self.sha256 = sha256 }
}
