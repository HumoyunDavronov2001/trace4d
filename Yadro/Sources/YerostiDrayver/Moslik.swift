import Foundation

// MARK: - DS-01: Emlid qabul qilgichi iOS bilan mosmi

/// Manba [E2] docs.emlid.com (2026-10-04 ko'rildi): eski Reach RX — faqat Android (Bluetooth SPP); Reach RX MFi
/// (2-avlod: qutida/tagida MFi belgisi yoki seriya raqamining oxirgi 4 raqami > 2414) va Reach RX2 — iOS External Accessory
/// (`com.emlid.nmea`, `com.emlid.corrections`). App Store uchun Emlid ilova bundle ID sini oq ro'yxatga kiritishi kerak [E3].
public enum ReachMoslik {
    public enum Model: String, Codable, Sendable {
        case rx2 = "Reach RX2"
        case rxMFi = "Reach RX MFi"
        case rxEski = "Reach RX (1-avlod)"
        case nomalum = "noma'lum"
    }

    public struct Natija: Equatable, Sendable {
        public let model: Model
        public let iosMos: Bool
        public let izoh: String
    }

    static let mfiChegara = 2414

    /// Seriya raqami bo'yicha (oxirgi 4 raqam). RX2 seriyasi alohida tekshirilmaydi — u doim iOS bilan mos.
    public static func seriyadan(_ seriya: String, model: String? = nil) -> Natija {
        if let m = model?.uppercased(), m.contains("RX2") {
            return Natija(model: .rx2, iosMos: true, izoh: "Reach RX2 — iOS External Accessory orqali ulanadi")
        }
        let raqamlar = seriya.reversed().prefix { $0.isNumber }
        guard raqamlar.count >= 4, let s = Int(String(raqamlar.prefix(4).reversed())) else {
            return Natija(model: .nomalum, iosMos: false,
                          izoh: "seriya raqamidan aniqlanmadi: qurilma tagida yoki qutida MFi belgisi borligini tekshiring")
        }
        if s > mfiChegara {
            return Natija(model: .rxMFi, iosMos: true, izoh: "Reach RX MFi (seriya oxiri \(s) > \(mfiChegara)) — iOS bilan ishlaydi")
        }
        return Natija(model: .rxEski, iosMos: false,
                      izoh: "1-avlod Reach RX (seriya oxiri \(s) ≤ \(mfiChegara)): faqat Android — iPhone bilan ISHLAMAYDI. "
                          + "Reach RX2 yoki Reach RX MFi kerak")
    }

    /// iOS External Accessory ro'yxatida ko'ringan aksessuar: protokol bo'lsa — MFi (RX2 yoki RX MFi).
    public static func aksessuardan(nomi: String, model: String, seriya: String, protokollar: [String]) -> Natija {
        guard protokollar.contains("com.emlid.nmea") else {
            return Natija(model: .nomalum, iosMos: false, izoh: "\(nomi): com.emlid.nmea protokoli yo'q — Emlid qabul qilgichi emas")
        }
        if (nomi + " " + model).uppercased().contains("RX2") {
            return Natija(model: .rx2, iosMos: true, izoh: "Reach RX2 ulandi")
        }
        let s = seriyadan(seriya)
        return Natija(model: .rxMFi, iosMos: true, izoh: s.model == .rxMFi ? s.izoh : "Reach RX MFi ulandi")
    }
}

// MARK: - DS-02: dastak profili (iPhone modeli × dastak tomoni → antenna ofseti)

public struct DastakProfili: Codable, Equatable, Sendable {
    public let iphone: String
    public let identifikatorlar: [String]
    public let dastak: String
    /// Telefon dastakning O'NG tomonida bo'lganda ofset (portret ramkasi, m); chap tomonda x ishorasi teskari.
    public let ofsetOng: [Double]
    public let manba: String
    /// O'q yo'nalishlari bizning portret ramkamizda tekshirilganmi (dala o'lchovi yoki xom ma'lumotdan baholash bilan).
    public let tasdiqlangan: Bool
}

public enum DastakProfillari {
    /// Faqat manbasi bor yozuvlar. Emlid hujjati (3.7, PIX4Dcatch) faqat bitta misol beradi va o'q yo'nalishini
    /// yozmaydi — shuning uchun «tasdiqlanmagan»: ilova uni avtomatik qo'llamaydi, administrator tasdiqlashi yoki dala
    /// skanida `AntennaOfset.baho` bilan tekshirilishi kerak.
    public static let jadval: [DastakProfili] = [
        DastakProfili(iphone: "iPhone 15 Pro", identifikatorlar: ["iPhone16,1"], dastak: "Emlid Scanning Kit",
                      ofsetOng: [0.072, 0.108, 0.028],
                      manba: "Reach RX hujjati 3.7 (PIX4Dcatch) misoli — o'q yo'nalishi ko'rsatilmagan", tasdiqlangan: false),
    ]

    public static func top(identifikator: String, tomon: String) -> (ofset: [Double], profil: DastakProfili)? {
        guard let p = jadval.first(where: { $0.identifikatorlar.contains(identifikator) }) else { return nil }
        let o = tomon == "chap" ? [-p.ofsetOng[0], p.ofsetOng[1], p.ofsetOng[2]] : p.ofsetOng
        return (o, p)
    }
}
