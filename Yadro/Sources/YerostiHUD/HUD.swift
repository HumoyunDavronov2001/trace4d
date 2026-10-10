import Foundation
import YerostiGeometriya

// UI v3 mantig'i (TALABLAR 13-bo'lim) — platformadan mustaqil, Linuxda sinovlanadi.
// Ilova faqat shu natijalarni chizadi: qaror va ustuvorlik bitta joyda.

// MARK: - Sifat pog'onalari (UI-07, UI-19) — PIX4Dcatch QC pog'onalari [P1]

public enum Pogona: String, Sendable, Equatable {
    case yaxshi, orta, past
}

public enum SifatPogonasi {
    /// Yaxshi (RASMIY) kadrlar ulushi: ≥ 90 % yaxshi, 50–90 % o'rta, < 50 % past.
    public static func ulush(foiz: Double) -> Pogona { foiz >= 90 ? .yaxshi : (foiz >= 50 ? .orta : .past) }

    /// RTK gorizontal aniqligi: < 3 sm yaxshi, 3–6 sm o'rta, > 6 sm past.
    public static func aniqlik(sm: Double) -> Pogona { sm < 3 ? .yaxshi : (sm <= 6 ? .orta : .past) }
}

// MARK: - Skanga tayyorlik (UI-01) [P2, E1, H1, H3]

/// LK-05: geodezik asos va bugungi tekshiruv o'lchovi holati (loyihadagi nazorat punktlaridan).
public enum NazoratHolati: Sendable, Equatable {
    /// Loyihada nazorat punktlari yo'q — hujjat mahalliy tizimda chiqmaydi.
    case punktYoq
    /// Punktlar bor, bugun ma'lum punktda tekshiruv o'lchovi qilinmagan.
    case bugunYoq
    /// Bugungi tekshiruv o'tdi: eng katta og'ish (m).
    case bugunOtdi(Double)
    /// Bugungi tekshiruv o'tmadi: og'ish (m) — baza, antenna yoki mountpoint xato.
    case bugunOtmadi(Double)
}

public struct TayyorlikKirish: Sendable {
    public var lidarBor: Bool
    public var rtkUlangan: Bool
    public var rtkHolat: String
    /// T-103 bo'yicha joriy sifat RASMIY mi.
    public var rasmiy: Bool
    public var sigmaHSm: Double?
    public var tuzatmaYoshiS: Double?
    public var bazaMasofaKm: Double?
    public var antennaOfsetKiritilgan: Bool
    public var boshXotiraBayt: Int64?
    /// 0…1; noma'lum bo'lsa nil (band ko'rsatilmaydi).
    public var batareya: Double?
    /// 0 nominal, 1 fair, 2 serious, 3 critical (`ProcessInfo.ThermalState`).
    public var termal: Int
    /// LK-05; nil — band ko'rsatilmaydi (masalan, loyiha tanlanmagan).
    public var nazorat: NazoratHolati?

    public init(lidarBor: Bool, rtkUlangan: Bool, rtkHolat: String, rasmiy: Bool, sigmaHSm: Double?, tuzatmaYoshiS: Double?,
                bazaMasofaKm: Double?, antennaOfsetKiritilgan: Bool, boshXotiraBayt: Int64?, batareya: Double?, termal: Int,
                nazorat: NazoratHolati? = nil) {
        self.lidarBor = lidarBor; self.rtkUlangan = rtkUlangan; self.rtkHolat = rtkHolat; self.rasmiy = rasmiy
        self.sigmaHSm = sigmaHSm; self.tuzatmaYoshiS = tuzatmaYoshiS; self.bazaMasofaKm = bazaMasofaKm
        self.antennaOfsetKiritilgan = antennaOfsetKiritilgan; self.boshXotiraBayt = boshXotiraBayt
        self.batareya = batareya; self.termal = termal; self.nazorat = nazorat
    }
}

public struct TayyorlikBandi: Equatable, Sendable, Identifiable {
    public enum Holat: String, Sendable, Equatable { case ok, ogoh, toxtat }
    public let id: String
    public let nomi: String
    public let qiymat: String
    public let holat: Holat
    /// Nima qilish kerak — do'stona tilda (H1).
    public let izoh: String?
}

public enum Tayyorlik {
    public static let xotiraToxtatBayt: Int64 = 1_000_000_000
    public static let xotiraOgohBayt: Int64 = 5_000_000_000
    public static let batareyaOgoh = 0.20
    /// K-06: 20 km dan uzoq baza — aniqlik pasayadi, yaqinroq mountpoint tavsiya qilinadi.
    public static let bazaOgohKm = 20.0

    public static func baholash(_ k: TayyorlikKirish) -> [TayyorlikBandi] {
        var b: [TayyorlikBandi] = []
        b.append(k.lidarBor
            ? .init(id: "lidar", nomi: "LiDAR", qiymat: "bor", holat: .ok, izoh: nil)
            : .init(id: "lidar", nomi: "LiDAR", qiymat: "yo'q", holat: .toxtat, izoh: "Skan uchun iPhone Pro yoki Pro Max kerak"))
        if !k.rtkUlangan {
            b.append(.init(id: "rtk", nomi: "RTK qabul qilgich", qiymat: "ulanmagan", holat: .ogoh,
                           izoh: "Usiz skan faqat mahalliy ramkada: UTM koordinata va ijro chizmasi chiqmaydi"))
        } else {
            let s = k.sigmaHSm.map { " · " + Son.vergul($0, 1) + " sm" } ?? ""
            b.append(k.rasmiy
                ? .init(id: "rtk", nomi: "RTK qabul qilgich", qiymat: k.rtkHolat + s, holat: .ok, izoh: nil)
                : .init(id: "rtk", nomi: "RTK qabul qilgich", qiymat: k.rtkHolat + s, holat: .ogoh,
                        izoh: "FIX va aniqlik chegarasini kuting: ochiq osmon ostida turing"))
            if let y = k.tuzatmaYoshiS {
                b.append(y <= 10
                    ? .init(id: "tuzatma", nomi: "Tuzatma yoshi", qiymat: Son.vergul(y, 0) + " s", holat: .ok, izoh: nil)
                    : .init(id: "tuzatma", nomi: "Tuzatma yoshi", qiymat: Son.vergul(y, 0) + " s", holat: .ogoh,
                            izoh: "Tuzatmalar kechikmoqda: internet va NTRIP ulanishini tekshiring"))
            } else {
                b.append(.init(id: "tuzatma", nomi: "Tuzatma (NTRIP)", qiymat: "kelmayapti", holat: .ogoh,
                               izoh: "Ulanish sozlamalarida NTRIP ni yoqing"))
            }
            if let km = k.bazaMasofaKm {
                b.append(km <= bazaOgohKm
                    ? .init(id: "baza", nomi: "Baza masofasi", qiymat: Son.vergul(km, 1) + " km", holat: .ok, izoh: nil)
                    : .init(id: "baza", nomi: "Baza masofasi", qiymat: Son.vergul(km, 1) + " km", holat: .ogoh,
                            izoh: "Baza uzoq: yaqinroq mountpoint tanlang"))
            }
        }
        switch k.nazorat {
        case .punktYoq:
            b.append(.init(id: "nazorat", nomi: "Geodezik asos", qiymat: "punktlar yo'q", holat: .ogoh,
                           izoh: "Hujjat shahar tizimida chiqishi uchun obyekt atrofidagi kamida 4 ta ma'lum punktni o'lchang"))
        case .bugunYoq:
            b.append(.init(id: "nazorat", nomi: "Bugungi tekshiruv", qiymat: "qilinmagan", holat: .ogoh,
                           izoh: "Ma'lum punktda 30 s tekshiruv o'lchovi: baza, antenna va mountpoint xatosini ushlaydi"))
        case .bugunOtdi(let d):
            b.append(.init(id: "nazorat", nomi: "Bugungi tekshiruv", qiymat: Son.vergul(d * 100, 1) + " sm", holat: .ok, izoh: nil))
        case .bugunOtmadi(let d):
            b.append(.init(id: "nazorat", nomi: "Bugungi tekshiruv", qiymat: Son.vergul(d * 100, 1) + " sm", holat: .toxtat,
                           izoh: "Baza koordinatasi, antenna balandligi yoki mountpoint xato: tuzatib, qayta tekshiring"))
        case nil:
            break
        }
        b.append(k.antennaOfsetKiritilgan
            ? .init(id: "antenna", nomi: "Antenna ofseti", qiymat: "kiritilgan", holat: .ok, izoh: nil)
            : .init(id: "antenna", nomi: "Antenna ofseti", qiymat: "kiritilmagan", holat: .ogoh,
                    izoh: "Sozlamalarda antenna va kamera orasidagi masofani kiriting"))
        if let x = k.boshXotiraBayt {
            let h: TayyorlikBandi.Holat = x < xotiraToxtatBayt ? .toxtat : (x < xotiraOgohBayt ? .ogoh : .ok)
            b.append(.init(id: "xotira", nomi: "Bo'sh xotira", qiymat: Son.bayt(x), holat: h,
                           izoh: h == .ok ? nil : "Eski skanlarni serverga yuklab, telefondan o'chiring"))
        }
        if let bat = k.batareya {
            b.append(bat >= batareyaOgoh
                ? .init(id: "batareya", nomi: "Batareya", qiymat: "\(Int((bat * 100).rounded())) %", holat: .ok, izoh: nil)
                : .init(id: "batareya", nomi: "Batareya", qiymat: "\(Int((bat * 100).rounded())) %", holat: .ogoh,
                        izoh: "Quvvat banki ulang: LiDAR va RTK ko'p quvvat oladi"))
        }
        switch k.termal {
        case 3:
            b.append(.init(id: "harorat", nomi: "Telefon harorati", qiymat: "juda issiq", holat: .toxtat,
                           izoh: "Telefon sovushini kuting, soyaga o'ting"))
        case 2:
            b.append(.init(id: "harorat", nomi: "Telefon harorati", qiymat: "issiq", holat: .ogoh,
                           izoh: "Soyada ishlang, fonarni o'chiring"))
        default:
            b.append(.init(id: "harorat", nomi: "Telefon harorati", qiymat: "normal", holat: .ok, izoh: nil))
        }
        return b
    }

    public static func boshlashMumkin(_ b: [TayyorlikBandi]) -> Bool { !b.contains { $0.holat == .toxtat } }
}

// MARK: - Yagona ustuvor yo'riqnoma (UI-05) [H1]

public struct Yoriqnoma: Equatable, Sendable {
    public enum Tur: String, Sendable, Equatable { case xavf, ogoh, maslahat }
    public let matn: String
    public let tur: Tur
    /// SF Symbol nomi.
    public let belgi: String
}

public enum Kuzatuv: Sendable, Equatable {
    case normal, sekinroq, teksturaKam, sozlanmoqda, qaytaAniqlash, cheklangan
}

public enum HUDAsbob: Sendable, Equatable { case yoq, arNuqta, quvur }

public struct HUDHolati: Sendable {
    public var termal = 0
    public var batareya: Double?
    public var yozilmoqda = false
    public var rtkUlangan = false
    public var rasmiy = false
    public var kuzatuv = Kuzatuv.normal
    /// Dvigatelning bir martalik xabari (masalan "quvur topilmadi").
    public var xabar: String?
    public var asbob = HUDAsbob.yoq
    public var georefJuft = 0
    public init() {}
}

public enum YoriqnomaTanlov {
    /// Bir vaqtda bitta xabar. Ustuvorlik: qizish → batareya → FIX yo'qoldi → kuzatuv → dvigatel xabari → maslahat.
    public static func tanla(_ h: HUDHolati) -> Yoriqnoma {
        if h.termal >= 3 {
            return .init(matn: "Telefon juda qizib ketdi: skanni tugating va sovushini kuting", tur: .xavf, belgi: "thermometer.high")
        }
        if h.termal == 2 {
            return .init(matn: "Telefon qizimoqda: soyada ishlang, fonarni o'chiring", tur: .ogoh, belgi: "thermometer.medium")
        }
        if h.yozilmoqda, let b = h.batareya, b <= 0.15 {
            return .init(matn: "Batareya \(Int((b * 100).rounded())) %: quvvat banki ulang yoki skanni tugating",
                         tur: b <= 0.10 ? .xavf : .ogoh, belgi: "battery.25")
        }
        if h.yozilmoqda, h.rtkUlangan, !h.rasmiy {
            return .init(matn: "RTK FIX yo'qoldi: ochiq joyga o'ting, sekin yuring. Kadrlar PAST belgilanmoqda",
                         tur: .xavf, belgi: "location.slash.fill")
        }
        switch h.kuzatuv {
        case .normal: break
        case .sekinroq:
            return .init(matn: "Telefonni sekinroq harakatlantiring", tur: .ogoh, belgi: "tortoise.fill")
        case .teksturaKam:
            return .init(matn: "Sirt yaxshi ko'rinmayapti: fonarni yoqing yoki telefonni sirtga yaqinroq tuting",
                         tur: .ogoh, belgi: "flashlight.on.fill")
        case .sozlanmoqda:
            return .init(matn: "Kamera sozlanmoqda: telefonni sekin u yoq-bu yoqqa suring", tur: .ogoh, belgi: "camera.metering.center.weighted")
        case .qaytaAniqlash:
            return .init(matn: "Joy qayta aniqlanmoqda: oldingi turgan joyingizga qayting", tur: .ogoh, belgi: "arrow.uturn.backward")
        case .cheklangan:
            return .init(matn: "Kuzatuv cheklangan: sekinroq harakatlaning", tur: .ogoh, belgi: "exclamationmark.triangle.fill")
        }
        if let x = h.xabar { return .init(matn: x, tur: .ogoh, belgi: "info.circle.fill") }
        if h.yozilmoqda, !h.rtkUlangan {
            return .init(matn: "RTK ulanmagan: skan faqat mahalliy ramkada bo'ladi", tur: .ogoh, belgi: "antenna.radiowaves.left.and.right.slash")
        }
        switch h.asbob {
        case .quvur: return .init(matn: "Quvur ustiga bosing: o'q, diametr va chuqurlik aniqlanadi", tur: .maslahat, belgi: "hand.tap.fill")
        case .arNuqta: return .init(matn: "Belgi qo'yish uchun sirtga bosing", tur: .maslahat, belgi: "hand.tap.fill")
        case .yoq: break
        }
        if h.yozilmoqda, h.rtkUlangan, h.georefJuft < 20 {
            return .init(matn: "Bog'lanmoqda \(h.georefJuft)/20: transheya bo'ylab kamida 1 m yuring",
                         tur: .maslahat, belgi: "link")
        }
        if h.yozilmoqda {
            return .init(matn: "Quvur bo'ylab sekin yuring, telefonni transheyaga qaratib turing", tur: .maslahat, belgi: "figure.walk")
        }
        return .init(matn: "Yozishni boshlash uchun katta tugmani bosing", tur: .maslahat, belgi: "record.circle")
    }
}

// MARK: - AR noaniqlik yo'lagi (UI-13) [A1, R1]

public enum Noaniqlik {
    /// Serverda σ bo'lmagan RASMIY bo'lmagan liniya uchun ehtiyotkor qiymat: yorliqda "aniqlik noma'lum" deb yoziladi.
    public static let nomalumSigmaM = 0.25

    /// Liniya σ (m): serverdagi eng katta σH; yo'q bo'lsa RASMIY → T-103 chegarasi (2 sm), boshqasi — noma'lum.
    public static func liniyaSigma(sigmaHSm: Double?, sifat: String) -> (m: Double, malum: Bool) {
        if let s = sigmaHSm, s > 0 { return (s / 100, true) }
        if sifat == "RASMIY" { return (0.02, true) }
        return (nomalumSigmaM, false)
    }

    /// Yo'lak yarim kengligi (m) ≈ 95 %: 2·√(σ_liniya² + σ_bog'lash²).
    public static func yarimKenglik(liniyaSigmaM: Double, bogRmsM: Double?) -> Double {
        let b = bogRmsM ?? 0
        return 2 * (liniyaSigmaM * liniyaSigmaM + b * b).squareRoot()
    }
}

// MARK: - Ekrandan tashqaridagi quvur (UI-15) [H1]

public enum Yonalish {
    /// ARKit ramkasi (y yuqori). Kamera oldiga nisbatan gorizontal burchak (radian; + o'ngda) va masofa (m).
    public static func nisbiy(kamera: Vektor3, oldinga: Vektor3, nuqta: Vektor3) -> (burchak: Double, masofa: Double) {
        let fx = oldinga.x, fz = oldinga.z
        let fl = (fx * fx + fz * fz).squareRoot()
        let dx = nuqta.x - kamera.x, dz = nuqta.z - kamera.z
        let masofa = (dx * dx + dz * dz).squareRoot()
        guard fl > 1e-9, masofa > 1e-9 else { return (0, masofa) }
        let f = (fx / fl, fz / fl)
        let ong = (-f.1, f.0)
        return (atan2(dx * ong.0 + dz * ong.1, dx * f.0 + dz * f.1), masofa)
    }

    /// Poliliniyalar ichida kameraga gorizontal eng yaqin nuqta.
    public static func engYaqin(kamera: Vektor3, oqlar: [[Vektor3]]) -> Vektor3? {
        var eng: (Double, Vektor3)?
        for oq in oqlar where oq.count >= 2 {
            for i in 1..<oq.count {
                let a = oq[i - 1], b = oq[i]
                let abx = b.x - a.x, abz = b.z - a.z
                let l2 = abx * abx + abz * abz
                let t = l2 > 1e-12 ? max(0, min(1, ((kamera.x - a.x) * abx + (kamera.z - a.z) * abz) / l2)) : 0
                let q = a + (b - a) * t
                let d = (q.x - kamera.x) * (q.x - kamera.x) + (q.z - kamera.z) * (q.z - kamera.z)
                if d < (eng?.0 ?? .infinity) { eng = (d, q) }
            }
        }
        return eng?.1
    }

    /// Ekran chetidagi nuqta: markazdan `burchak` yo'nalishida (0 — yuqoriga, + o'ngga), chetdan `chet` ichkarida.
    public static func chetNuqtasi(burchak: Double, kenglik: Double, balandlik: Double, chet: Double) -> (x: Double, y: Double) {
        let dx = sin(burchak), dy = -cos(burchak)
        let yx = kenglik / 2 - chet, yy = balandlik / 2 - chet
        let k = min(abs(dx) > 1e-9 ? yx / abs(dx) : .infinity, abs(dy) > 1e-9 ? yy / abs(dy) : .infinity)
        return (kenglik / 2 + dx * k, balandlik / 2 + dy * k)
    }
}

// MARK: - Son formatlari (o'zbekcha: vergul)

public enum Son {
    public static func vergul(_ v: Double, _ raqam: Int) -> String {
        String(format: "%.\(raqam)f", v).replacingOccurrences(of: ".", with: ",")
    }

    public static func bayt(_ b: Int64) -> String {
        let gb = Double(b) / 1_000_000_000
        return gb >= 1 ? vergul(gb, 1) + " GB" : vergul(Double(b) / 1_000_000, 0) + " MB"
    }
}
