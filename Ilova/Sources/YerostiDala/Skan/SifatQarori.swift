import SwiftUI
import YerostiHUD

/// UI-07: to'xtatishdagi sifat qarori (PIX4Dcatch "Save / continue / abandon" namunasi) — jurnal yopilishidan OLDIN.
struct SifatQarori: View {
    let kadr: Int
    let rasmiy: Int
    let georefJuft: Int
    let georefRmsM: Double?
    let meshM2: Double
    let masofaM: Double
    let quvurlar: Int
    let davomiylik: TimeInterval
    let tugatish: () -> Void
    let davom: () -> Void
    let bekor: () -> Void
    @State private var bekorTasdiq = false

    var body: some View {
        let foiz = kadr > 0 ? 100 * Double(rasmiy) / Double(kadr) : 0
        let p = SifatPogonasi.ulush(foiz: foiz)
        VStack(alignment: .leading, spacing: 14) {
            Text("Skanni yakunlaysizmi?").font(.title3.weight(.bold)).foregroundStyle(Rang.matn)
            Text("\(Format.vaqt(davomiylik)) · \(Format.m(masofaM, raqam: 0)). Saqlashdan oldin sifatni tekshiring, kerak bo'lsa davom ettiring.")
                .font(.subheadline).foregroundStyle(Rang.matn2)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    OlchovKarta(nomi: "RASMIY kadr", qiymat: Format.son(foiz, raqam: 0), birlik: "%", izoh: "\(rasmiy) / \(kadr)", rang: p.rang)
                    OlchovKarta(nomi: "Georeferens", qiymat: georefRmsM.map { Format.son($0 * 100) } ?? "\(min(georefJuft, 20))/20",
                                birlik: georefRmsM == nil ? nil : "sm", izoh: georefRmsM == nil ? "juftlar" : "RMS")
                }
                GridRow {
                    OlchovKarta(nomi: "Mesh", qiymat: Format.son(meshM2), birlik: "m²", izoh: "LiDAR sirti")
                    OlchovKarta(nomi: "Belgilangan quvur", qiymat: "\(quvurlar)", izoh: "yakunda avtomatik qidiriladi")
                }
            }
            if p != .yaxshi, kadr > 0 {
                OgohQatori(matn: "RASMIY kadrlar \(Int(foiz.rounded())) %: FIX yo'qolgan joylarni qayta yuring yoki davom ettiring.")
            }
            if georefRmsM == nil {
                OgohQatori(matn: "Georeferens hali hisoblanmagan: RTK FIX holatida transheya bo'ylab kamida 1 m yuring.")
            }
            Button(action: tugatish) { Label("Tugatish va saqlash", systemImage: "checkmark.seal") }
                .buttonStyle(AsosiyTugma())
            Button(action: davom) { Label("Yozishni davom ettirish", systemImage: "record.circle") }
                .buttonStyle(IkkilamchiTugma())
            Button(role: .destructive) { bekorTasdiq = true } label: {
                Label("Skanni bekor qilish", systemImage: "trash").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .foregroundStyle(Rang.past)
        }
        .padding(20)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        .confirmationDialog("Skan o'chirilsinmi?", isPresented: $bekorTasdiq, titleVisibility: .visible) {
            Button("Skanni o'chirish", role: .destructive, action: bekor)
            Button("Yo'q", role: .cancel) {}
        } message: {
            Text("Kadrlar, mesh va muhr jurnali telefondan o'chiriladi. Buni qaytarib bo'lmaydi.")
        }
    }
}
