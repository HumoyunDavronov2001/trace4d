import SwiftUI
import YerostiDrayver
import YerostiHUD

/// UI-03: RTK holati bosilganda — to'liq tafsilot (Emlid Flow holat qatori namunasi). Skan va AR ekranida bir xil.
struct RTKTafsilot: View {
    @Environment(RTKBoshqaruv.self) private var rtk
    @Environment(\.dismiss) private var yop

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: rtk.ulangan ? "location.fill" : "location.slash.fill")
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(asosiyRang.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rtk.ulangan ? "RTK \(rtk.holat.rtk.rawValue)" : "RTK ulanmagan").font(.title3.weight(.bold))
                        Text(rtk.ulangan ? (rtk.sifat == .rasmiy ? "RASMIY: rasmiy chizmaga yaroqli" : "PAST: kadrlar rasmiy emas")
                                         : "Qabul qilgichni ulash uchun «Ulanish» ga o'ting")
                            .font(.subheadline).foregroundStyle(Rang.matn2)
                    }
                }
                .padding(.vertical, 4)
            }
            if rtk.ulangan {
                Section("Yechim") {
                    qator("σ gorizontal", rtk.holat.sigmaHSm.map { Format.son($0) + " sm" }, pogona: rtk.holat.sigmaHSm.map { SifatPogonasi.aniqlik(sm: $0) })
                    qator("σ vertikal", rtk.holat.sigmaVSm.map { Format.son($0) + " sm" })
                    qator("Sputniklar", rtk.holat.sputnikSoni.map(String.init))
                    qator("HDOP", rtk.holat.hdop.map { Format.son($0) })
                }
                Section("Tuzatma") {
                    qator("Tuzatma yoshi", (rtk.tuzatmaYoshiS ?? rtk.holat.tuzatmaYoshiS).map { Format.son($0) + " s" })
                    qator("Baza masofasi", rtk.bazaMasofaKm.map { Format.son($0) + " km" })
                    if !rtk.tizimlar.isEmpty { qator("Tizimlar", rtk.tizimlar.joined(separator: ", ")) }
                    qator("NTRIP", ntripMatni)
                }
                Section("Joylashuv (WGS84)") {
                    qator("Kenglik", rtk.holat.lat.map { String(format: "%.8f°", $0) })
                    qator("Uzunlik", rtk.holat.lon.map { String(format: "%.8f°", $0) })
                    qator("Ellipsoid balandligi", rtk.holat.balandlikEllipsoid.map { Format.m($0, raqam: 3) })
                    qator("UTC vaqt", rtk.holat.vaqtUTC)
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("RASMIY sifat (T-103): FIX, σ gorizontal ≤ 2 sm, σ vertikal ≤ 5 sm, tuzatma yoshi ≤ 10 s. Odatiy tuzatma yoshi 1–2 s.")
            }
        }
        .navigationTitle("RTK holati")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tayyor") { yop() } } }
    }

    private var asosiyRang: Color {
        guard rtk.ulangan else { return Rang.past }
        return rtk.sifat == .rasmiy ? Rang.rasmiy : Rang.skanSifat
    }

    private var ntripMatni: String {
        switch rtk.ntripHolati {
        case .ochiq: "o'chiq"
        case .ulanmoqda: "ulanmoqda"
        case .oqim: "tuzatmalar kelmoqda"
        case .xato(let x): "xato: \(x)"
        }
    }

    private func qator(_ nomi: String, _ qiymat: String?, pogona: Pogona? = nil) -> some View {
        HStack {
            Text(nomi).foregroundStyle(Rang.matn2)
            Spacer()
            Text(qiymat ?? "—").monospacedDigit().fontWeight(.semibold).foregroundStyle(pogona?.rang ?? Rang.matn)
        }
        .accessibilityElement(children: .combine)
    }
}
