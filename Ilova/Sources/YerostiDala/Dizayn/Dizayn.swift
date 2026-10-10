import SwiftUI
import YerostiHUD

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// Yorug' va to'q rejimga moslashadigan rang (DZ-02).
    init(yorug: UInt32, toq: UInt32) {
        self.init(UIColor { t in UIColor(hex: t.userInterfaceStyle == .dark ? toq : yorug) })
    }
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}

/// Dizayn tokenlari (DZ-01, DZ-02). Kontrast oq/qora fonda ≥ 4,5 — hisoblab tekshirilgan.
enum Rang {
    // Semantik — ro'yxat, forma, hisobot ekranlari (yorug'/to'q)
    static let fon = Color(yorug: 0xF4F6F9, toq: 0x0A0F14)
    static let sirt = Color(yorug: 0xFFFFFF, toq: 0x121A22)
    static let sirt2 = Color(yorug: 0xEEF2F6, toq: 0x1A2430)
    static let chiziq = Color(yorug: 0xE3E8EF, toq: 0x243140)
    static let matn = Color(yorug: 0x0B1620, toq: 0xF2F5F8)
    static let matn2 = Color(yorug: 0x4A5868, toq: 0xA7B3C2)
    static let matn3 = Color(yorug: 0x5E6A79, toq: 0x8593A4)
    static let urgu = Color(yorug: 0x1F5BD6, toq: 0x6B9BFF)
    /// Oq matn ostidagi urg'u foni (asosiy tugma, AR kartasi). To'q rejimda `urgu` oq matn bilan 2,7:1 berardi — shuning uchun alohida.
    static let tugma = Color(yorug: 0x1F5BD6, toq: 0x2F6BEA)
    static let brend = Color(yorug: 0x0B2540, toq: 0xF2F5F8)
    static let rasmiy = Color(yorug: 0x0F7A3D, toq: 0x34D399)
    static let rasmiyFon = Color(yorug: 0xE3F4EA, toq: 0x0F2E22)
    static let skanSifat = Color(yorug: 0x9A5500, toq: 0xFBBF24)
    static let skanFon = Color(yorug: 0xFCEFD9, toq: 0x33260A)
    static let past = Color(yorug: 0xC0262D, toq: 0xFF7B7B)
    static let pastFon = Color(yorug: 0xFCE6E6, toq: 0x3A1618)
    static let firuza = Color(yorug: 0x0E7490, toq: 0x22D3EE)

    // Kamera ustidagi qobiq (doim to'q) — D-05, D-10
    static let fix = Color(hex: 0x34D399)
    static let float = Color(hex: 0xFFD60A)
    static let xato = Color(hex: 0xFF453A)
    static let mesh = Color(hex: 0x22D3EE)
    static let belgi = Color(hex: 0xFFD60A)
}

enum Olcham {
    static let b4: CGFloat = 4, b8: CGFloat = 8, b12: CGFloat = 12, b16: CGFloat = 16, b20: CGFloat = 20, b24: CGFloat = 24
    static let radiusKichik: CGFloat = 10, radiusKarta: CGFloat = 16, radiusKatta: CGFloat = 22
    static let tugma: CGFloat = 52
    /// UI-06: qo'lqop bilan — yozish tugmasi ≥ 15 mm (96 pt), asbob tugmalari ≥ 1 sm (62 pt).
    static let yozishTugma: CGFloat = 96
    static let asbobTugma: CGFloat = 62
}

/// Tarmoq turlari — ilova, AR va veb uchun bir xil ranglar (T-262).
struct TarmoqTuri: Identifiable, Hashable {
    let id: String
    let nomi: String
    let rang: Color
    let uiRang: UIColor

    static let hammasi: [TarmoqTuri] = [
        .init(id: "suv", nomi: "Suv", hex: 0x2563EB),
        .init(id: "kanalizatsiya", nomi: "Kanalizatsiya", hex: 0x92400E),
        .init(id: "gaz", nomi: "Gaz", hex: 0xCA8A04),
        .init(id: "elektr", nomi: "Elektr", hex: 0xDC2626),
        .init(id: "optika", nomi: "Optika", hex: 0xEA580C),
        .init(id: "issiqlik", nomi: "Issiqlik", hex: 0x7C3AED),
    ]

    init(id: String, nomi: String, hex: UInt32) {
        self.id = id; self.nomi = nomi
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        rang = Color(red: r, green: g, blue: b)
        uiRang = UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    static func top(_ id: String) -> TarmoqTuri { hammasi.first { $0.id == id } ?? hammasi[0] }
}

/// Kamera ustidagi shaffof qora chip. "Kontrastni oshirish" yoqilsa deyarli shaffofsiz (UI-10).
struct KameraChip: ViewModifier {
    var chegara: Color? = nil
    @Environment(\.colorSchemeContrast) private var kontrast
    func body(content: Content) -> some View {
        let yuqori = kontrast == .increased
        content
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(minHeight: 32)
            .background(.black.opacity(yuqori ? 0.88 : 0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(chegara ?? (yuqori ? .white.opacity(0.5) : .clear), lineWidth: yuqori ? 1.5 : 1))
    }
}

/// Kamera ustidagi panel (kartochka, yo'riqnoma, qaror). UI-10: yuqori kontrastda 0,9 va aniq chegara.
struct KameraPanel: ViewModifier {
    var chegara: Color? = nil
    var radius: CGFloat = 16
    @Environment(\.colorSchemeContrast) private var kontrast
    func body(content: Content) -> some View {
        let yuqori = kontrast == .increased
        content
            .background(.black.opacity(yuqori ? 0.9 : 0.72), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(chegara ?? .white.opacity(yuqori ? 0.5 : 0.15), lineWidth: yuqori ? 1.5 : 1))
    }
}

extension View {
    func kameraChip(chegara: Color? = nil) -> some View { modifier(KameraChip(chegara: chegara)) }
    func kameraPanel(chegara: Color? = nil, radius: CGFloat = 16) -> some View { modifier(KameraPanel(chegara: chegara, radius: radius)) }
}

/// Sifat pog'onasi ranglari (UI-07, UI-19): kamera ustida yorqin, ro'yxatda semantik.
extension Pogona {
    var kameraRang: Color {
        switch self { case .yaxshi: Rang.fix; case .orta: Rang.float; case .past: Rang.xato }
    }
    var rang: Color {
        switch self { case .yaxshi: Rang.rasmiy; case .orta: Rang.skanSifat; case .past: Rang.past }
    }
}

/// O'ng ustundagi dumaloq asbob tugmasi: 62 pt ≈ 1 sm (UI-06, NN/G), qo'lqop bilan ham bosiladi.
struct AsbobTugma: View {
    let belgi: String
    let nomi: String
    var faol = false
    var rang: Color = Rang.mesh
    let amal: () -> Void

    var body: some View {
        Button(action: amal) {
            VStack(spacing: 4) {
                Image(systemName: belgi)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(faol ? rang : .white)
                    .frame(width: Olcham.asbobTugma, height: Olcham.asbobTugma)
                    .background(faol ? rang.opacity(0.22) : .black.opacity(0.55), in: Circle())
                    .overlay(Circle().strokeBorder(faol ? rang : .white.opacity(0.18), lineWidth: 1))
                Text(nomi)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(nomi)
        .accessibilityAddTraits(faol ? .isSelected : [])
    }
}

enum Format {
    static func sm(_ m: Double?) -> String {
        guard let m else { return "—" }
        return String(format: "%.1f sm", m * 100).replacingOccurrences(of: ".", with: ",")
    }
    static func m(_ v: Double?, raqam: Int = 2) -> String {
        guard let v else { return "—" }
        return String(format: "%.\(raqam)f m", v).replacingOccurrences(of: ".", with: ",")
    }
    static func son(_ v: Double, raqam: Int = 1) -> String {
        String(format: "%.\(raqam)f", v).replacingOccurrences(of: ".", with: ",")
    }
    static func vaqt(_ s: TimeInterval) -> String {
        let t = Int(s)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}


// MARK: - Komponentlar (DZ-04)

/// Brend belgisi: TRACE + 4D (urg'u rangida).
struct BrendBelgi: View {
    var olcham: CGFloat = 28
    var body: some View {
        Text("\(Text("TRACE").foregroundStyle(Rang.brend))\(Text("4D").foregroundStyle(Rang.urgu))")
            .font(.system(size: olcham, weight: .heavy, design: .rounded))
            .tracking(1)
            .accessibilityLabel("TRACE4D")
    }
}

/// Holat chipi: nuqta + matn. Dala holati qatorida va kartalarda.
struct HolatChip: View {
    enum Tur { case ok, ogoh, xato, neytral }
    let matn: String
    var tur: Tur = .neytral
    var belgi: String?

    static func rangi(_ t: Tur) -> Color {
        switch t { case .ok: Rang.rasmiy; case .ogoh: Rang.skanSifat; case .xato: Rang.past; case .neytral: Rang.matn2 }
    }
    static func foni(_ t: Tur) -> Color {
        switch t { case .ok: Rang.rasmiyFon; case .ogoh: Rang.skanFon; case .xato: Rang.pastFon; case .neytral: Rang.sirt2 }
    }
    private var rang: Color { Self.rangi(tur) }
    private var fon: Color { Self.foni(tur) }

    var body: some View {
        HStack(spacing: 6) {
            if let belgi { Image(systemName: belgi).font(.caption.weight(.bold)) } else { Circle().fill(rang).frame(width: 7, height: 7) }
            Text(matn).font(.footnote.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(rang)
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .background(fon, in: Capsule())
    }
}

/// Holat ustuni: rangli nuqta + nom, ostida qiymat. Bosh ekrandagi dala holati kartasi (DZ-05).
struct HolatUstun: View {
    let nomi: String
    let qiymat: String
    var tur: HolatChip.Tur = .neytral

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(HolatChip.rangi(tur)).frame(width: 8, height: 8)
                Text(nomi).font(.caption.weight(.semibold)).foregroundStyle(Rang.matn2)
            }
            Text(qiymat).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Rang.matn)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Ogohlantirish qatori: ko'p qatorli, sariq fonda (chip sig'maydigan matnlar uchun).
struct OgohQatori: View {
    let matn: String
    var belgi = "exclamationmark.triangle.fill"
    var body: some View {
        Label(matn, systemImage: belgi)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Rang.skanSifat)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rang.skanFon, in: RoundedRectangle(cornerRadius: Olcham.radiusKichik, style: .continuous))
    }
}

/// Sifat nishoni: RASMIY / SKAN / PAST (T-031, T-103).
struct SifatNishon: View {
    let sifat: String
    var body: some View {
        switch sifat {
        case "RASMIY": HolatChip(matn: "RASMIY", tur: .ok, belgi: "checkmark.seal.fill")
        case "SKAN": HolatChip(matn: "SKAN", tur: .ogoh, belgi: "viewfinder")
        default: HolatChip(matn: "PAST", tur: .xato, belgi: "exclamationmark.triangle.fill")
        }
    }
}

/// O'lchov kartasi: izoh, katta qiymat (teng kenglikdagi raqamlar), birlik.
struct OlchovKarta: View {
    let nomi: String
    let qiymat: String
    var birlik: String?
    var izoh: String?
    var rang: Color = Rang.matn

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(nomi).font(.footnote).foregroundStyle(Rang.matn2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(qiymat).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(rang)
                if let birlik { Text(birlik).font(.subheadline.weight(.medium)).foregroundStyle(Rang.matn2) }
            }
            if let izoh { Text(izoh).font(.caption).foregroundStyle(Rang.matn3) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Rang.sirt, in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous).strokeBorder(Rang.chiziq))
        .accessibilityElement(children: .combine)
    }
}

/// Bo'lim kartasi: sarlavha + tarkib.
struct BolimKarta<Tarkib: View>: View {
    let sarlavha: String?
    var belgi: String?
    @ViewBuilder var tarkib: Tarkib

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sarlavha {
                Label {
                    Text(sarlavha).font(.headline)
                } icon: {
                    if let belgi { Image(systemName: belgi).foregroundStyle(Rang.urgu) }
                }
                .foregroundStyle(Rang.matn)
            }
            tarkib
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Rang.sirt, in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous).strokeBorder(Rang.chiziq))
    }
}

/// Karta ichidagi "nom — qiymat" qatori.
struct QiymatQatori: View {
    let nomi: String
    let qiymat: String
    var mono = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(nomi).font(.subheadline).foregroundStyle(Rang.matn2)
            Spacer(minLength: 12)
            Text(qiymat).font(mono ? .subheadline.monospaced() : .subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Rang.matn).multilineTextAlignment(.trailing)
        }
    }
}

/// Asosiy tugma: to'liq kenglik, 52 pt, urg'u fon. O'chiq holatda kulrang (xira ko'k emas — matn o'qilsin).
struct AsosiyTugma: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View { Tana(c: c) }

    private struct Tana: View {
        let c: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var yoqilgan
        var body: some View {
            c.label
                .font(.headline)
                .foregroundStyle(yoqilgan ? Color.white : Rang.matn3)
                .frame(maxWidth: .infinity, minHeight: Olcham.tugma)
                .background(yoqilgan ? Rang.tugma.opacity(c.isPressed ? 0.8 : 1) : Rang.sirt2,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Ikkilamchi tugma: urg'u rangidagi yengil fon.
struct IkkilamchiTugma: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View { Tana(c: c) }

    private struct Tana: View {
        let c: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var yoqilgan
        var body: some View {
            c.label
                .font(.headline)
                .foregroundStyle(yoqilgan ? Rang.urgu : Rang.matn3)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(yoqilgan ? Rang.urgu.opacity(c.isPressed ? 0.2 : 0.12) : Rang.sirt2,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Bosh ekrandagi amal kartasi (belgi, sarlavha, izoh).
struct AmalKarta: View {
    let sarlavha: String
    let izoh: String
    let belgi: String
    var urgu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: belgi)
                .font(.title2.weight(.semibold))
                .foregroundStyle(urgu ? Color.white : Rang.urgu)
                .frame(width: 44, height: 44)
                .background(urgu ? Color.white.opacity(0.18) : Rang.urgu.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(sarlavha).font(.headline).foregroundStyle(urgu ? Color.white : Rang.matn)
            Text(izoh).font(.footnote).foregroundStyle(urgu ? Color.white.opacity(0.85) : Rang.matn2).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(16)
        .background(urgu ? AnyShapeStyle(Rang.tugma.gradient) : AnyShapeStyle(Rang.sirt), in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous).strokeBorder(urgu ? Color.clear : Rang.chiziq))
    }
}
