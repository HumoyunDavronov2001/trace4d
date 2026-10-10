import SwiftUI
import YerostiHUD

/// UI-01: yozishdan oldin tayyorlik tekshiruvi. To'suvchi band bo'lsa "Boshlash" o'chiq, ogohlantirishlar sababini aytadi.
struct TayyorlikVaragi: View {
    @Environment(RTKBoshqaruv.self) private var rtk
    @Environment(Sozlamalar.self) private var sozlama
    @Environment(QurilmaHolati.self) private var qurilma
    @Environment(\.dismiss) private var yop
    let lidarBor: Bool
    /// LK-05: loyihaning bugungi geodezik nazorati (nil — band ko'rsatilmaydi).
    var nazorat: NazoratHolati? = nil
    let boshlash: () -> Void
    let ulanish: () -> Void

    private var bandlar: [TayyorlikBandi] {
        Tayyorlik.baholash(TayyorlikKirish(
            lidarBor: lidarBor, rtkUlangan: rtk.ulangan, rtkHolat: rtk.holat.rtk.rawValue, rasmiy: rtk.sifat == .rasmiy,
            sigmaHSm: rtk.holat.sigmaHSm, tuzatmaYoshiS: rtk.tuzatmaYoshiS ?? rtk.holat.tuzatmaYoshiS,
            bazaMasofaKm: rtk.bazaMasofaKm, antennaOfsetKiritilgan: sozlama.antennaOfsetKiritilgan,
            boshXotiraBayt: qurilma.boshXotiraBayt, batareya: qurilma.batareya, termal: qurilma.termal, nazorat: nazorat))
    }

    var body: some View {
        let b = bandlar
        let mumkin = Tayyorlik.boshlashMumkin(b)
        let ogoh = b.filter { $0.holat == .ogoh }.count
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Skanga tayyorlik").font(.title3.weight(.bold)).foregroundStyle(Rang.matn)
                Spacer()
                if !mumkin {
                    HolatChip(matn: "Boshlab bo'lmaydi", tur: .xato, belgi: "xmark.octagon.fill")
                } else if ogoh > 0 {
                    HolatChip(matn: "\(ogoh) ta ogohlantirish", tur: .ogoh, belgi: "exclamationmark.triangle.fill")
                } else {
                    HolatChip(matn: "Tayyor", tur: .ok, belgi: "checkmark.seal.fill")
                }
            }
            ScrollView {
                VStack(spacing: 8) { ForEach(b) { TayyorlikQatori(band: $0) } }
            }
            if b.contains(where: { ($0.id == "rtk" || $0.id == "tuzatma" || $0.id == "baza") && $0.holat != .ok }) {
                Button { yop(); ulanish() } label: { Label("Ulanish sozlamalari", systemImage: "antenna.radiowaves.left.and.right") }
                    .buttonStyle(IkkilamchiTugma())
            }
            Button { yop(); boshlash() } label: {
                Label(ogoh > 0 ? "Baribir boshlash" : "Yozishni boshlash", systemImage: "record.circle")
            }
            .buttonStyle(AsosiyTugma())
            .disabled(!mumkin)
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { qurilma.yangila() }
    }
}

struct TayyorlikQatori: View {
    let band: TayyorlikBandi

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: belgi).font(.title3).foregroundStyle(rang).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(band.nomi).font(.subheadline.weight(.semibold)).foregroundStyle(Rang.matn)
                    Spacer(minLength: 8)
                    Text(band.qiymat).font(.subheadline).monospacedDigit().foregroundStyle(Rang.matn2)
                }
                if let iz = band.izoh { Text(iz).font(.footnote).foregroundStyle(rang) }
            }
        }
        .padding(12)
        .background(Rang.sirt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Rang.chiziq))
        .accessibilityElement(children: .combine)
    }

    private var belgi: String {
        switch band.holat { case .ok: "checkmark.circle.fill"; case .ogoh: "exclamationmark.triangle.fill"; case .toxtat: "xmark.octagon.fill" }
    }
    private var rang: Color {
        switch band.holat { case .ok: Rang.rasmiy; case .ogoh: Rang.skanSifat; case .toxtat: Rang.past }
    }
}
