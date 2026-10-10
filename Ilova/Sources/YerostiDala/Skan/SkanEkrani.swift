import SwiftUI
import UIKit
import YerostiDrayver
import YerostiHUD
import YerostiTahlil

/// D-05 — Skan ekrani (kamera-birinchi), UI v3. RTK holati hech qachon yashirilmaydi (T-150).
struct SkanEkrani: View {
    @Environment(RTKBoshqaruv.self) private var rtk
    @Environment(LoyihaOmbori.self) private var ombor
    @Environment(Sozlamalar.self) private var sozlama
    @Environment(QurilmaHolati.self) private var qurilma
    @Environment(\.dismiss) private var yop
    @State private var dvigatel: SkanDvigateli
    @State private var varaq: Varaq?
    @State private var hisobot: SkanYozuvi?
    @State private var sozlanish = false

    /// Bitta `sheet(item:)` — bir vaqtda faqat bitta varaq (tayyorlik → ulanish o'tishi ham shu yerda).
    enum Varaq: String, Identifiable {
        case tayyorlik, ulanish, rtk, sifat
        var id: String { rawValue }
    }

    private let loyihaId: UUID

    init(loyiha: Loyiha, rtk: RTKBoshqaruv, sozlama: Sozlamalar) {
        _dvigatel = State(initialValue: SkanDvigateli(loyiha: loyiha, rtk: rtk, sozlama: sozlama))
        loyihaId = loyiha.id
    }

    private var h: SkanHolati { dvigatel.holat }

    /// Yozish paytida FIX yo'qolgan (T-103 dan tashqariga chiqqan) — haptika va VoiceOver uchun.
    private var fixYoqoldi: Bool { h.yozilmoqda && rtk.ulangan && rtk.sifat != .rasmiy }

    /// UI-05: bitta ustuvor yo'riqnoma (qaror yadroda).
    private var yoriqnoma: Yoriqnoma {
        var x = HUDHolati()
        x.termal = qurilma.termal
        x.batareya = qurilma.batareya
        x.yozilmoqda = h.yozilmoqda
        x.rtkUlangan = rtk.ulangan
        x.rasmiy = rtk.sifat == .rasmiy
        x.kuzatuv = h.kuzatuv
        x.xabar = h.xabar
        x.asbob = h.asbob == .quvur ? .quvur : (h.asbob == .arNuqta ? .arNuqta : .yoq)
        x.georefJuft = h.georefJuft
        return YoriqnomaTanlov.tanla(x)
    }

    var body: some View {
        ZStack {
            ARKorinish(dvigatel: dvigatel, sozlanish: { faol in withAnimation(.easeOut(duration: 0.2)) { sozlanish = faol } })
                .ignoresSafeArea()
            if sozlanish {
                // UI-04: sozlanish paytida faqat orqaga qaytish qoladi (HIG: ortiqcha UI yashiriladi)
                VStack { HStack { orqaTugma; Spacer() }.padding(.horizontal, 14); Spacer() }.padding(.top, 8)
            } else {
                VStack(spacing: 8) {
                    yuqoriQator
                    holatQatori
                    banner(yoriqnoma)
                    Spacer()
                    if let q = h.oxirgiQuvur {
                        QuvurKartochka(quvur: q, tarmoq: TarmoqTuri.top(dvigatel.loyiha.tarmoqTuri)) { h.oxirgiQuvur = nil }
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    pastkiPanel
                }
                .padding(.top, 8)
            }
            if let t = h.tahlil { tahlilQatlami(t) }
        }
        .animation(.easeOut(duration: 0.2), value: h.oxirgiQuvur != nil)
        .sheet(item: $varaq) { v in
            switch v {
            case .tayyorlik:
                TayyorlikVaragi(lidarBor: h.lidarBor, nazorat: ombor.loyiha(loyihaId)?.bugungiNazorat(),
                                boshlash: { dvigatel.yozishniBoshla() }, ulanish: { varaq = .ulanish })
            case .ulanish:
                NavigationStack { UlanishEkrani() }
            case .rtk:
                NavigationStack { RTKTafsilot() }
            case .sifat:
                SifatQarori(kadr: h.kadrSoni, rasmiy: h.rasmiyKadr, georefJuft: h.georefJuft, georefRmsM: h.georefRmsM,
                            meshM2: h.meshMaydoniM2, masofaM: h.masofaM, quvurlar: h.quvurTopildi,
                            davomiylik: h.boshlanganVaqt.map { Date().timeIntervalSince($0) } ?? 0,
                            tugatish: { varaq = nil; Task { await dvigatel.tugat() } },
                            davom: { varaq = nil },
                            bekor: {
                                varaq = nil
                                dvigatel.bekorQil()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dvigatel.toxtat(); yop() }
                            })
            }
        }
        .onChange(of: h.tugadi) { _, yangi in
            guard let s = yangi else { return }
            ombor.skanQosh(s, loyihaId: dvigatel.loyiha.id)
            hisobot = s
        }
        .fullScreenCover(item: $hisobot) { s in
            NavigationStack { HisobotEkrani(loyihaId: dvigatel.loyiha.id, skanId: s.id, yopish: { hisobot = nil; yop() }) }
        }
        // UI-09: haptika faqat alohida hodisalarda va sozlamada yoqilgan bo'lsa
        .sensoryFeedback(.success, trigger: h.yozilmoqda) { _, _ in sozlama.haptika }
        .sensoryFeedback(.success, trigger: h.quvurTopildi) { eski, yangi in sozlama.haptika && yangi > eski }
        .sensoryFeedback(.warning, trigger: fixYoqoldi) { eski, yangi in sozlama.haptika && yangi && !eski }
        .sensoryFeedback(.error, trigger: h.xatoHisob) { eski, yangi in sozlama.haptika && yangi > eski }
        // UI-11: FIX yo'qolishi va tiklanishi VoiceOver da e'lon qilinadi
        .onChange(of: fixYoqoldi) { _, yangi in
            guard h.yozilmoqda else { return }
            UIAccessibility.post(notification: .announcement, argument: yangi ? "RTK FIX yo'qoldi" : "RTK FIX tiklandi")
        }
        // UI-08: qizish holati dvigatelga (mesh qoplamasi siyraklashadi)
        .onChange(of: qurilma.termal) { _, t in dvigatel.termal = t }
        .onAppear { qurilma.boshla(); dvigatel.termal = qurilma.termal }
        .statusBarHidden(false)
        // UI-10: HUD Dynamic Type ga ergashadi, lekin kamera ko'rinishini to'sib qo'ymasligi uchun XXL gacha
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .preferredColorScheme(.dark)
    }

    // MARK: Yuqori

    private var orqaTugma: some View {
        Button { dvigatel.toxtat(); yop() } label: {
            Label(dvigatel.loyiha.nomi, systemImage: "chevron.left").lineLimit(1)
        }
        .kameraChip()
        .disabled(h.yozilmoqda)
        .accessibilityHint(h.yozilmoqda ? "Yozish paytida chiqib bo'lmaydi" : "")
    }

    private var yuqoriQator: some View {
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
    }

    private var rtkRang: Color {
        guard rtk.ulangan else { return Rang.xato }
        return rtk.sifat == .rasmiy ? Rang.fix : (rtk.holat.rtk == .fix || rtk.holat.rtk == .float ? Rang.float : Rang.xato)
    }

    private var holatQatori: some View {
        HStack(spacing: 6) {
            if case .oqim = rtk.ntripHolati, let y = rtk.tuzatmaYoshiS {
                let b = rtk.bazaMasofaKm.map { " · " + Format.son($0, raqam: 0) + " km" } ?? ""
                Text("Tuzatma \(Format.son(y, raqam: 0)) s" + b)
                    .kameraChip(chegara: y > 10 || (rtk.bazaMasofaKm ?? 0) > 20 ? Rang.float : nil)
            } else if case .xato = rtk.ntripHolati {
                Text("NTRIP xato").kameraChip(chegara: Rang.xato)
            }
            if let g = h.georefRmsM {
                let p = SifatPogonasi.aniqlik(sm: g * 100)
                Label("±" + Format.sm(g), systemImage: "link").kameraChip(chegara: p.kameraRang)
            } else if rtk.ulangan, h.yozilmoqda {
                Label("\(min(h.georefJuft, 20))/20", systemImage: "link").kameraChip(chegara: Rang.float)
            }
            Label(Format.son(h.meshMaydoniM2) + " m²", systemImage: "square.grid.3x3.topleft.filled")
                .kameraChip()
                .accessibilityLabel("Mesh \(Format.son(h.meshMaydoniM2)) kvadrat metr")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
    }

    private func bannerRang(_ t: Yoriqnoma.Tur) -> Color {
        switch t {
        case .xavf: return Rang.xato
        case .ogoh: return Rang.float
        case .maslahat: return .white
        }
    }

    private func banner(_ y: Yoriqnoma) -> some View {
        let rang = bannerRang(y.tur)
        return HStack(spacing: 10) {
            Image(systemName: y.belgi).font(.subheadline.weight(.bold)).foregroundStyle(rang)
            Text(y.matn).font(.subheadline.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .kameraPanel(chegara: y.tur == .maslahat ? nil : rang, radius: 14)
        .padding(.horizontal, 14)
        .onTapGesture { if h.xabar != nil { h.xabar = nil } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(y.tur == .xavf ? .isHeader : [])
    }

    // MARK: Asboblar — pastda, yozish tugmasi ustida: bosh barmoq yetadi, ekran markazi transheya uchun bo'sh (UI-06)

    private var asboblar: some View {
        HStack(spacing: 4) {
            AsbobTugma(belgi: "plus", nomi: "AR nuqta", faol: h.asbob == .arNuqta, rang: Rang.belgi) {
                h.asbob = h.asbob == .arNuqta ? .yoq : .arNuqta
            }
            AsbobTugma(belgi: "cylinder.split.1x2", nomi: "Quvur", faol: h.asbob == .quvur, rang: Rang.mesh) {
                h.asbob = h.asbob == .quvur ? .yoq : .quvur
            }
            AsbobTugma(belgi: h.fonar ? "flashlight.on.fill" : "flashlight.off.fill", nomi: "Fonar", faol: h.fonar, rang: Rang.float) {
                dvigatel.fonar(!h.fonar)
            }
            AsbobTugma(belgi: "triangle", nomi: "Mesh", faol: h.meshKorinadi) { dvigatel.meshKorsat(!h.meshKorinadi) }
        }
    }

    // MARK: Pastki panel

    private var pastkiPanel: some View {
        VStack(spacing: 12) {
            asboblar
            if h.yozilmoqda, let b = h.boshlanganVaqt {
                TimelineView(.periodic(from: b, by: 1)) { c in
                    HStack(spacing: 6) {
                        Circle().fill(Rang.xato).frame(width: 9, height: 9).shadow(color: Rang.xato, radius: 4)
                        Text(Format.vaqt(c.date.timeIntervalSince(b))).font(.headline).monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("Yozish vaqti \(Format.vaqt(c.date.timeIntervalSince(b)))")
                }
            }
            HStack(alignment: .center) {
                rasmiyUlush.frame(width: 110, alignment: .leading)
                Spacer()
                yozishTugmasi
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(h.quvurTopildi)").font(.headline).monospacedDigit()
                    Text("quvur").font(.caption).opacity(0.8)
                }
                .foregroundStyle(.white)
                .frame(width: 110, alignment: .trailing)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 20)
        .padding(.top, 36)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    /// UI-19: RASMIY kadrlar ulushi PIX4Dcatch pog'onasi rangida.
    private var rasmiyUlush: some View {
        let foiz = h.kadrSoni > 0 ? 100 * Double(h.rasmiyKadr) / Double(h.kadrSoni) : 0
        let p = SifatPogonasi.ulush(foiz: foiz)
        return VStack(alignment: .leading, spacing: 2) {
            Text(h.kadrSoni > 0 ? "\(Int(foiz.rounded())) %" : "—").font(.headline).monospacedDigit()
                .foregroundStyle(h.kadrSoni > 0 ? p.kameraRang : .white)
            Text("RASMIY · \(h.kadrSoni) kadr").font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    /// UI-06: 96 pt (≈ 16 mm) — qo'lqop bilan. To'xtatish sifat qarori orqali (UI-07).
    private var yozishTugmasi: some View {
        Button {
            if h.yozilmoqda { varaq = .sifat } else { qurilma.yangila(); varaq = .tayyorlik }
        } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 6).frame(width: Olcham.yozishTugma, height: Olcham.yozishTugma)
                if h.yozilmoqda {
                    RoundedRectangle(cornerRadius: 9).fill(Rang.xato).frame(width: 40, height: 40)
                } else {
                    Circle().fill(Rang.xato).frame(width: Olcham.yozishTugma - 20, height: Olcham.yozishTugma - 20)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(h.tahlil != nil)
        .accessibilityLabel(h.yozilmoqda ? "Skanni yakunlash" : "Skanni boshlash")
    }

    private func tahlilQatlami(_ t: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white).scaleEffect(1.3)
            Text(t).font(.headline).foregroundStyle(.white)
        }
        .padding(24)
        .kameraPanel(radius: 18)
    }
}

/// RTK chipi ichi: nuqta + holat + σH (skan va AR ekranida bir xil, UI-02).
struct RTKChipIchi: View {
    @Environment(RTKBoshqaruv.self) private var rtk
    var body: some View {
        if !rtk.ulangan {
            HStack(spacing: 6) { Circle().fill(Rang.xato).frame(width: 8, height: 8); Text("RTK ulanmagan") }
        } else {
            let rang = rtk.sifat == .rasmiy ? Rang.fix : (rtk.holat.rtk == .fix || rtk.holat.rtk == .float ? Rang.float : Rang.xato)
            HStack(spacing: 6) {
                Circle().fill(rang).frame(width: 8, height: 8).shadow(color: rang, radius: 4)
                Text("RTK \(rtk.holat.rtk.rawValue)")
                if let s = rtk.holat.sigmaHSm { Text(Format.son(s) + " sm").font(.caption).opacity(0.85) }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// K-01 natijasi: avtomatik topilgan quvur.
struct QuvurKartochka: View {
    let quvur: TopilganQuvur
    let tarmoq: TarmoqTuri
    let yopish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RoundedRectangle(cornerRadius: 3).fill(tarmoq.rang).frame(width: 14, height: 14)
                Text("\(tarmoq.nomi) — quvur aniqlandi").font(.headline)
                Spacer()
                Button(action: yopish) { Image(systemName: "xmark.circle.fill").font(.title3) }
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityLabel("Yopish")
            }
            HStack(alignment: .top, spacing: 16) {
                qiymat("Diametr", quvur.standart.map { "Ø\(Int($0.tashqiMm))" } ?? "\(Int(quvur.tashqiDiametrMm.rounded())) mm",
                       izoh: "o'lchandi \(Int(quvur.tashqiDiametrMm.rounded())) mm")
                qiymat("Chuqurlik", quvur.qoplamaChuqurligiM.map { Format.m($0) } ?? "—", izoh: "skan bo'yicha")
                qiymat("Nishab", Format.son(quvur.qiyalikFoiz) + " %", izoh: Format.m(quvur.uzunlikM, raqam: 1))
            }
            HStack(spacing: 8) {
                Text("Ishonch \(Int((quvur.ishonch * 100).rounded())) %")
                if !quvur.muftalar.isEmpty { Text("· \(quvur.muftalar.count) mufta") }
                Spacer()
                Text("SKAN · RTK nazorat nuqtasi bilan tasdiqlanadi").opacity(0.75).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(14)
        .kameraPanel(chegara: tarmoq.rang.opacity(0.85))
        .accessibilityElement(children: .combine)
    }

    private func qiymat(_ nomi: String, _ q: String, izoh: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nomi).font(.caption).opacity(0.7)
            Text(q).font(.title2.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(izoh).font(.caption).opacity(0.7)
        }
    }
}
