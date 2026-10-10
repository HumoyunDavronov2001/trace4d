import SwiftUI
import YerostiDrayver
import YerostiHUD
import YerostiTahlil

/// D-10 — AR ko'rish, UI v3: quruvchi telefonni yerga qaratadi va ko'milgan tarmoqlarni ko'radi (K-09, AR-01…AR-08, UI-12…UI-16).
struct ARKorishEkrani: View {
    @Environment(RTKBoshqaruv.self) private var rtk
    @Environment(\.dismiss) private var yop
    @State private var dvigatel: ARKorishDvigateli
    @State private var varaq: Varaq?
    @State private var sozlanish = false

    enum Varaq: String, Identifiable {
        case ulanish, rtk
        var id: String { rawValue }
    }

    init(rtk: RTKBoshqaruv, sozlama: Sozlamalar) {
        _dvigatel = State(initialValue: ARKorishDvigateli(rtk: rtk, sozlama: sozlama))
    }

    private var h: ARKorishHolati { dvigatel.holat }

    var body: some View {
        ZStack {
            ARKorinish(dvigatel: dvigatel, sozlanish: { faol in withAnimation(.easeOut(duration: 0.2)) { sozlanish = faol } })
                .ignoresSafeArea()
            if sozlanish {
                VStack { HStack { orqaTugma; Spacer() }.padding(.horizontal, 14); Spacer() }.padding(.top, 8)
            } else {
                if h.boglangan, h.rejim == .korish, h.kuzatuv == .normal { nishonBelgisi }
                chetKorsatkichi
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        orqaTugma
                        Spacer(minLength: 4)
                        Button { varaq = .rtk } label: { RTKChipIchi() }
                            .kameraChip(chegara: rtkRang.opacity(0.6))
                            .accessibilityHint("RTK tafsilotini ochadi")
                        Button { varaq = .ulanish } label: { Image(systemName: "antenna.radiowaves.left.and.right") }
                            .kameraChip()
                            .accessibilityLabel("Ulanish")
                    }
                    .padding(.horizontal, 14)
                    HStack(spacing: 6) {
                        bogChip
                        if h.boglangan {
                            Button { dvigatel.qaytaBoglash() } label: { Label("Qayta bog'lash", systemImage: "arrow.clockwise") }
                                .kameraChip()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    if h.boglangan, !h.turlar.isEmpty { filtrQatori }
                    if h.boglangan {
                        Text(h.yuklash ?? "Atrofda \(h.tarmoqlar.count) tarmoq · \(h.pudratchiSoni) pudratchi")
                            .kameraChip(chegara: h.yuklash == nil ? nil : Rang.float)
                    }
                    if let y = yoriqnoma { banner(y) }
                    Spacer()
                    pastkiPanel
                    Picker("Rejim", selection: Binding(get: { h.rejim }, set: { h.rejim = $0 })) {
                        ForEach(ARKorishHolati.Rejim.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .padding(.top, 8)
            }
        }
        .sheet(item: $varaq) { v in
            switch v {
            case .ulanish: NavigationStack { UlanishEkrani() }
            case .rtk: NavigationStack { RTKTafsilot() }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)   // UI-10
        .preferredColorScheme(.dark)
    }

    private var orqaTugma: some View {
        Button { dvigatel.toxtat(); yop() } label: { Label("AR ko'rish", systemImage: "chevron.left") }.kameraChip()
    }

    private var rtkRang: Color {
        guard rtk.ulangan else { return Rang.xato }
        return rtk.sifat == .rasmiy ? Rang.fix : (rtk.holat.rtk == .fix || rtk.holat.rtk == .float ? Rang.float : Rang.xato)
    }

    /// UI-05: kuzatuv muammosi ustuvor, keyin dvigatel xabari. AR da "yozish" maslahatlari yo'q.
    private var yoriqnoma: Yoriqnoma? {
        if h.kuzatuv != .normal {
            var x = HUDHolati()
            x.kuzatuv = h.kuzatuv
            return YoriqnomaTanlov.tanla(x)
        }
        return h.xabar.map { Yoriqnoma(matn: $0, tur: .ogoh, belgi: "info.circle.fill") }
    }

    private func banner(_ y: Yoriqnoma) -> some View {
        HStack(spacing: 10) {
            Image(systemName: y.belgi).font(.subheadline.weight(.bold)).foregroundStyle(Rang.float)
            Text(y.matn).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .kameraPanel(chegara: Rang.float, radius: 14)
        .padding(.horizontal, 14)
        .onTapGesture { h.xabar = nil }
        .accessibilityElement(children: .combine)
    }

    private var nishonBelgisi: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2).frame(width: 34, height: 34)
            Rectangle().fill(.white).frame(width: 2, height: 14)
            Rectangle().fill(.white).frame(width: 14, height: 2)
        }
        .shadow(color: .black.opacity(0.6), radius: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// UI-15: eng yaqin quvur ekrandan tashqarida — chetda yo'nalish va masofa (HIG: ekrandan tashqaridagi obyektga yo'naltirish).
    private var chetKorsatkichi: some View {
        GeometryReader { geo in
            if let c = h.chet {
                let p = Yonalish.chetNuqtasi(burchak: c.burchak, kenglik: geo.size.width, balandlik: geo.size.height, chet: 40)
                let t = TarmoqTuri.top(c.turi)
                // uzun nomli yorliq ekrandan chiqmasin, yuqori HUD va pastki panelga tegmasin
                let x = min(max(p.x, 100), geo.size.width - 100)
                let y = min(max(p.y, 170), geo.size.height - 230)
                VStack(spacing: 4) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.title2)
                        .foregroundStyle(t.rang)
                        .shadow(color: .black.opacity(0.7), radius: 3)
                        .rotationEffect(.radians(c.burchak))
                    Text("\(t.nomi) · \(Format.m(c.masofaM, raqam: 1))").kameraChip(chegara: t.rang)
                }
                .position(x: x, y: y)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(t.nomi) quvuri ekrandan tashqarida, \(Format.m(c.masofaM, raqam: 1)) uzoqlikda")
            }
        }
        .allowsHitTesting(false)
    }

    /// UI-14: tarmoq turlari va "faqat RASMIY" filtri. Faqat ko'rinishni o'zgartiradi — nishon va xavf zonasi hammasini hisoblaydi.
    private var filtrQatori: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(h.turlar, id: \.self) { tur in
                    let t = TarmoqTuri.top(tur)
                    let yashirin = h.yashirinTurlar.contains(tur)
                    Button {
                        if yashirin { h.yashirinTurlar.remove(tur) } else { h.yashirinTurlar.insert(tur) }
                        dvigatel.filtrniQolla()
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(yashirin ? Color.clear : t.rang).frame(width: 9, height: 9)
                                .overlay(Circle().strokeBorder(t.rang, lineWidth: 1.5))
                            Text(t.nomi).strikethrough(yashirin)
                        }
                    }
                    .kameraChip(chegara: yashirin ? nil : t.rang.opacity(0.7))
                    .opacity(yashirin ? 0.6 : 1)
                    .accessibilityLabel("\(t.nomi) \(yashirin ? "yashirin" : "ko'rinadi")")
                }
                Button {
                    h.faqatRasmiy.toggle()
                    dvigatel.filtrniQolla()
                } label: {
                    Label("Faqat RASMIY", systemImage: h.faqatRasmiy ? "checkmark.seal.fill" : "seal")
                }
                .kameraChip(chegara: h.faqatRasmiy ? Rang.fix : nil)
                .accessibilityAddTraits(h.faqatRasmiy ? .isSelected : [])
            }
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder private var bogChip: some View {
        if h.boglangan, let r = h.rmsM {
            Label("Bog'langan ±" + Format.sm(r), systemImage: "link")
                .kameraChip(chegara: SifatPogonasi.aniqlik(sm: r * 100).kameraRang)
        } else if rtk.ulangan {
            Label("Bog'lanmoqda \(min(h.juftSoni, 20))/20 · \(Format.son(min(h.yoyilishM, 0.5) * 2)) / 1 m", systemImage: "link")
                .kameraChip(chegara: Rang.float)
        }
    }

    @ViewBuilder private var pastkiPanel: some View {
        switch h.rejim {
        case .korish: nishonPaneli
        case .chuqur:
            panel {
                Text("Yerga bosing: 1×1 m virtual chuqur ochiladi, ichidagi quvurlarni yon tomondan ko'rasiz.")
                    .font(.subheadline)
                Button("Chuqurni yopish") { dvigatel.chuqurTozala() }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        case .xavf: xavfPaneli
        }
    }

    @ViewBuilder private var nishonPaneli: some View {
        if !h.boglangan {
            panel {
                Text(rtk.ulangan ? "Bog'lash uchun RTK FIX holatida 2–3 m yuring (telefonni yerga qaratib)."
                                 : "RTK qabul qilgichni ulang: usiz tarmoqlar metr xatosi bilan chiqadi va ko'rsatilmaydi.")
                    .font(.subheadline.weight(.medium))
            }
        } else if let n = h.nishon {
            let t = TarmoqTuri.top(n.turi)
            panel(chegara: t.rang) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3).fill(t.rang).frame(width: 14, height: 14)
                    Text("\(t.nomi) Ø\(n.diametrMm)").font(.headline)
                    Spacer()
                }
                HStack(alignment: .top, spacing: 18) {
                    qiymat("Masofa", n.tomon == .ostida ? "ostida" : "\(Format.m(n.gorizontalMasofaM)) \(n.tomon.rawValue)")
                    qiymat("Chuqurlik", Format.m(n.chuqurlikM))
                }
                if n.gorizontalMasofaM < QazishXavfi.yonBufer {
                    Label("2 m ichida: mexanizatsiya bilan qazish taqiqlanadi, faqat qo'lda", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Rang.xato)
                }
            }
        } else {
            panel { Text("Nishon atrofida 5 m ichida kiritilgan tarmoq yo'q").font(.subheadline.weight(.medium)) }
        }
    }

    private var xavfPaneli: some View {
        panel(chegara: h.xavf.isEmpty ? nil : Rang.xato) {
            HStack {
                Text("Qazish zonasi: \(h.poligonSoni) nuqta").font(.headline)
                Spacer()
                Button("Tozalash") { dvigatel.xavfTozala() }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
            if h.poligonSoni < 3 {
                Text("Qaziladigan joy burchaklarini yerga bosib belgilang (kamida 3 ta).").font(.subheadline)
            } else if h.xavf.isEmpty {
                Text("2 m ichida kiritilgan tarmoq yo'q. Diqqat: bazaga kiritilmagan eski tarmoqlar bo'lishi mumkin.")
                    .font(.subheadline).foregroundStyle(Rang.fix)
            } else {
                ForEach(Array(h.xavf.enumerated()), id: \.offset) { _, x in
                    let t = TarmoqTuri.top(x.turi)
                    HStack {
                        RoundedRectangle(cornerRadius: 3).fill(t.rang).frame(width: 10, height: 10)
                        Text(t.nomi).font(.subheadline.weight(.semibold))
                        Text(x.daraja == .kesishadi ? "kesib o'tadi" : "\(Format.m(x.gorizontalMasofaM)) yonda")
                        Spacer()
                        Text("chuq. \(Format.m(x.chuqurlikM))").monospacedDigit()
                    }
                    .font(.subheadline)
                }
                Label("Faqat qo'lda qazish, tarmoq egasi vakili ishtirokida.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Rang.xato)
            }
        }
    }

    private func qiymat(_ nomi: String, _ q: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nomi).font(.caption).opacity(0.7)
            Text(q).font(.title2.weight(.bold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func panel<C: View>(chegara: Color? = nil, @ViewBuilder _ ichi: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8, content: ichi)
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kameraPanel(chegara: chegara)
            .padding(.horizontal, 14)
    }
}
