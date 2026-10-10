import SwiftUI
import YerostiDrayver
import YerostiGeometriya
import YerostiHUD
import YerostiTahlil

// MARK: - Loyihalar (D-01) — bosh ekran (DZ-05)

struct LoyihalarEkrani: View {
    @Environment(LoyihaOmbori.self) private var ombor
    @Environment(RTKBoshqaruv.self) private var rtk
    @Environment(Sozlamalar.self) private var sozlama
    @State private var arOchiq = false
    @State private var yangiOchiq = false
    @State private var ulanishOchiq = false
    @State private var sozlamaOchiq = false

    private var yuklanmagan: Int {
        ombor.loyihalar.reduce(0) { a, l in a + l.skanlar.filter { $0.yuklash == .kutmoqda }.count }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button { ulanishOchiq = true } label: { DalaHolati(yuklanmagan: yuklanmagan) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Ulanish sozlamalarini ochadi")
                    HStack(spacing: 12) {
                        Button { arOchiq = true } label: {
                            AmalKarta(sarlavha: "AR ko'rish", izoh: "Atrofdagi quvurlarni kamera orqali ko'rish", belgi: "arkit", urgu: true)
                        }
                        .buttonStyle(.plain)
                        Button { yangiOchiq = true } label: {
                            AmalKarta(sarlavha: "Yangi loyiha", izoh: "Transheya skani uchun obyekt", belgi: "plus.rectangle.on.folder")
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Loyihalar").font(.title3.weight(.bold)).foregroundStyle(Rang.matn)
                        Spacer()
                        if !ombor.loyihalar.isEmpty {
                            Text("\(ombor.loyihalar.count)").font(.subheadline.weight(.semibold)).foregroundStyle(Rang.matn2)
                        }
                    }
                    if ombor.loyihalar.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "cylinder.split.1x2").font(.system(size: 34, weight: .semibold)).foregroundStyle(Rang.urgu)
                            Text("Hali loyiha yo'q").font(.headline).foregroundStyle(Rang.matn)
                            Text("Transheya ochilgan obyekt uchun loyiha yarating. Skan, quvurlar va muhr shu yerda saqlanadi.")
                                .font(.subheadline).foregroundStyle(Rang.matn2).multilineTextAlignment(.center)
                            Button { yangiOchiq = true } label: { Label("Yangi loyiha", systemImage: "plus") }
                                .buttonStyle(AsosiyTugma()).padding(.top, 6)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(Rang.sirt, in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous).strokeBorder(Rang.chiziq))
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(ombor.loyihalar) { l in
                                NavigationLink(value: l.id) { LoyihaKarta(loyiha: l) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Rang.fon.ignoresSafeArea())
            .navigationTitle("Loyihalar")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { LoyihaEkrani(loyihaId: $0) }
            .toolbar {
                ToolbarItem(placement: .principal) { BrendBelgi(olcham: 22) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sozlamaOchiq = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Sozlamalar")
                }
            }
            .fullScreenCover(isPresented: $arOchiq) { ARKorishEkrani(rtk: rtk, sozlama: sozlama) }
            .sheet(isPresented: $yangiOchiq) { NavigationStack { YangiLoyihaEkrani() } }
            .sheet(isPresented: $ulanishOchiq) { NavigationStack { UlanishEkrani() } }
            .sheet(isPresented: $sozlamaOchiq) { NavigationStack { SozlamalarEkrani() } }
        }
    }
}

/// Dala holati kartasi: RTK · tuzatma · server (DZ-05). Bosilsa ulanish ekrani ochiladi.
struct DalaHolati: View {
    @Environment(RTKBoshqaruv.self) private var rtk
    @Environment(Sozlamalar.self) private var sozlama
    let yuklanmagan: Int
    @Environment(\.dynamicTypeSize) private var matnOlchami

    var body: some View {
        let tartib = matnOlchami.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                                     : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        HStack(spacing: 12) {
            tartib {
                rtkUstun
                ntripUstun
                serverUstun
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Rang.matn3)
        }
        .padding(14)
        .background(Rang.sirt, in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous).strokeBorder(Rang.chiziq))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var rtkUstun: some View {
        if !rtk.ulangan {
            HolatUstun(nomi: "RTK", qiymat: "Ulanmagan", tur: .xato)
        } else {
            let s = rtk.holat.sigmaHSm.map { " · " + Format.son($0) + " sm" } ?? ""
            HolatUstun(nomi: "RTK", qiymat: rtk.holat.rtk.rawValue + s,
                       tur: rtk.sifat == .rasmiy ? .ok : (rtk.holat.rtk == .fix || rtk.holat.rtk == .float ? .ogoh : .xato))
        }
    }

    @ViewBuilder private var ntripUstun: some View {
        switch rtk.ntripHolati {
        case .oqim:
            let y = rtk.tuzatmaYoshiS ?? 0
            let b = rtk.bazaMasofaKm.map { " · " + Format.son($0, raqam: 0) + " km" } ?? ""
            HolatUstun(nomi: "Tuzatma", qiymat: Format.son(y, raqam: 0) + " s" + b, tur: y > 10 ? .ogoh : .ok)
        case .ulanmoqda: HolatUstun(nomi: "Tuzatma", qiymat: "Ulanmoqda")
        case .xato: HolatUstun(nomi: "Tuzatma", qiymat: "Xato", tur: .xato)
        case .ochiq: HolatUstun(nomi: "Tuzatma", qiymat: "O'chiq")
        }
    }

    @ViewBuilder private var serverUstun: some View {
        if sozlama.serverManzil.isEmpty || sozlama.dalaToken.isEmpty {
            HolatUstun(nomi: "Server", qiymat: "Sozlanmagan", tur: .ogoh)
        } else if yuklanmagan > 0 {
            HolatUstun(nomi: "Server", qiymat: "\(yuklanmagan) ta kutmoqda", tur: .ogoh)
        } else {
            HolatUstun(nomi: "Server", qiymat: "Sozlangan", tur: .ok)
        }
    }
}

/// Loyiha kartasi: tarmoq rangi, nomi, tomonlar, oxirgi skan va muhr holati.
struct LoyihaKarta: View {
    let loyiha: Loyiha

    var body: some View {
        let t = TarmoqTuri.top(loyiha.tarmoqTuri)
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "cylinder.split.1x2.fill")
                .font(.title3).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(t.rang.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(loyiha.nomi).font(.headline).foregroundStyle(Rang.matn).lineLimit(2)
                Text([t.nomi, loyiha.pudratchi, loyiha.orderRaqami].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(Rang.matn2).lineLimit(1)
                HStack(spacing: 8) {
                    if let o = loyiha.skanlar.first {
                        YuklashNishon(holat: o.yuklash, qisqa: true)
                        Text("\(loyiha.skanlar.count) skan · \(o.boshlandi.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(Rang.matn3).lineLimit(1)
                    } else {
                        HolatChip(matn: "Skan yo'q", tur: .neytral, belgi: "viewfinder")
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Rang.matn3).padding(.top, 14)
        }
        .padding(14)
        .background(Rang.sirt, in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous).strokeBorder(Rang.chiziq))
        .contentShape(Rectangle())
    }
}

// MARK: - Yangi loyiha (D-02)

struct YangiLoyihaEkrani: View {
    @Environment(LoyihaOmbori.self) private var ombor
    @Environment(\.dismiss) private var yop
    @State private var l = Loyiha(nomi: "")

    var body: some View {
        Form {
            Section {
                TextField("Nomi (masalan: 5-mavze suv tarmog'i)", text: $l.nomi)
                TextField("Manzil", text: $l.manzil)
                TextField("Qazish orderi raqami", text: $l.orderRaqami)
                Toggle("Qazish orderi sanasi", isOn: Binding(
                    get: { l.orderSana != nil },
                    set: { l.orderSana = $0 ? Loyiha.isoSana(Date()) : nil }))
                if let s = l.orderSana {
                    DatePicker("Sana", selection: Binding(
                        get: { Loyiha.sanadan(s) ?? Date() },
                        set: { l.orderSana = Loyiha.isoSana($0) }), displayedComponents: .date)
                }
            } header: {
                Text("Obyekt")
            } footer: {
                Text("Order raqami va sanasi ijro hujjatida shart (ShNK 3.01.03-24, 420-band).")
            }
            Section("Tomonlar") {
                TextField("Buyurtmachi", text: $l.buyurtmachi)
                TextField("Pudratchi", text: $l.pudratchi)
            }
            Section("Tarmoq") {
                Picker("Turi", selection: $l.tarmoqTuri) {
                    ForEach(TarmoqTuri.hammasi) { t in
                        Label { Text(t.nomi) } icon: { Image(systemName: "circle.fill").foregroundStyle(t.rang) }.tag(t.id)
                    }
                }
                TextField("Material (PE100, PVX, po'lat…)", text: $l.material)
            }
        }
        .navigationTitle("Yangi loyiha")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Bekor") { yop() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Saqlash") { ombor.qosh(l); yop() }
                    .disabled(l.nomi.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - Loyiha sahifasi

struct LoyihaEkrani: View {
    let loyihaId: UUID
    @Environment(LoyihaOmbori.self) private var ombor
    @Environment(RTKBoshqaruv.self) private var rtk
    @Environment(Sozlamalar.self) private var sozlama
    @State private var skanOchiq = false

    var body: some View {
        if let l = ombor.loyiha(loyihaId) {
            let t = TarmoqTuri.top(l.tarmoqTuri)
            let masofa = l.skanlar.reduce(0.0) { $0 + $1.masofaM }
            let quvurlar = l.skanlar.reduce(0) { $0 + $1.quvurlar.count }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "cylinder.split.1x2.fill")
                            .font(.title2).foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(t.rang.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l.nomi).font(.title3.weight(.bold)).foregroundStyle(Rang.matn)
                            Text([t.nomi, l.material, l.manzil].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(Rang.matn2)
                        }
                    }
                    HStack(spacing: 10) {
                        OlchovKarta(nomi: "Skanlar", qiymat: "\(l.skanlar.count)")
                        OlchovKarta(nomi: "Yurilgan", qiymat: Format.son(masofa, raqam: 0), birlik: "m")
                        OlchovKarta(nomi: "Quvurlar", qiymat: "\(quvurlar)")
                    }
                    Button { skanOchiq = true } label: { Label("Skan boshlash", systemImage: "viewfinder") }
                        .buttonStyle(AsosiyTugma())
                    NavigationLink { XaritaEkrani(loyihaId: l.id) } label: { Label("Xarita: sun'iy yo'ldosh va punktlar", systemImage: "map") }
                        .buttonStyle(IkkilamchiTugma())
                    if !rtk.ulangan {
                        OgohQatori(matn: "RTK ulanmagan. Skan faqat mahalliy ramkada bo'ladi, UTM koordinata va ijro chizmasi chiqmaydi.")
                    }
                    Text("Skanlar").font(.title3.weight(.bold)).foregroundStyle(Rang.matn).padding(.top, 4)
                    if l.skanlar.isEmpty {
                        Text("Hali skan yo'q. Transheya ochiq paytda «Skan boshlash» ni bosing.")
                            .font(.subheadline).foregroundStyle(Rang.matn2)
                    }
                    ForEach(l.skanlar) { s in
                        NavigationLink { HisobotEkrani(loyihaId: l.id, skanId: s.id, yopish: nil) } label: { SkanKarta(skan: s) }
                            .buttonStyle(.plain)
                    }
                    NavigationLink { NazoratEkrani(loyihaId: l.id) } label: { GeodezikAsosKarta(loyiha: l) }
                        .buttonStyle(.plain)
                    NavigationLink { TasdiqEkrani(loyihaId: l.id) } label: { TasdiqKarta(loyiha: l) }
                        .buttonStyle(.plain)
                    BolimKarta(sarlavha: "Obyekt ma'lumoti", belgi: "doc.text") {
                        QiymatQatori(nomi: "Pudratchi", qiymat: l.pudratchi.isEmpty ? "—" : l.pudratchi)
                        QiymatQatori(nomi: "Buyurtmachi", qiymat: l.buyurtmachi.isEmpty ? "—" : l.buyurtmachi)
                        QiymatQatori(nomi: "Qazish orderi", qiymat: l.orderMatn.isEmpty ? "—" : l.orderMatn)
                        QiymatQatori(nomi: "Serverda", qiymat: l.serverId.map { "#\($0)" } ?? "hali yuklanmagan")
                    }
                }
                .padding(16)
            }
            .background(Rang.fon.ignoresSafeArea())
            .navigationTitle("Loyiha")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $skanOchiq) { SkanEkrani(loyiha: l, rtk: rtk, sozlama: sozlama) }
        }
    }
}

/// LK-10: loyiha sahifasida geodezik asos holati — hujjat shahar tizimida chiqishi shunga bog'liq.
struct GeodezikAsosKarta: View {
    let loyiha: Loyiha
    var body: some View {
        let lok = loyiha.lokalizatsiya()
        HStack(spacing: 12) {
            Image(systemName: "scope").font(.title3.weight(.semibold)).foregroundStyle(Rang.urgu).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("Geodezik asos").font(.headline).foregroundStyle(Rang.matn)
                Text(lok.map { "\($0.nGor) punkt · qoldiq \(Format.sm($0.maksGor))" } ??
                     (loyiha.punktlar.isEmpty ? "punktlar yo'q: hujjat shahar tizimida chiqmaydi" : "\(loyiha.punktlar.count) punkt, o'lchanmagan"))
                    .font(.subheadline).foregroundStyle(Rang.matn2)
            }
            Spacer()
            if let lok {
                HolatChip(matn: lok.yaroqli ? "yaroqli" : "yaroqsiz", tur: lok.yaroqli ? .ok : .xato)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Rang.matn3)
        }
        .padding(14)
        .background(Rang.sirt, in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous).strokeBorder(Rang.chiziq))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct SkanKarta: View {
    let skan: SkanYozuvi
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(skan.boshlandi.formatted(date: .abbreviated, time: .shortened)).font(.headline).foregroundStyle(Rang.matn)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Rang.matn3)
            }
            HStack(spacing: 14) {
                Label("\(skan.kadrSoni)", systemImage: "camera.viewfinder")
                Label(Format.m(skan.masofaM, raqam: 0), systemImage: "figure.walk")
                Label("\(skan.quvurlar.count)", systemImage: "cylinder.split.1x2")
                if let f = skan.rasmiyKadrFoiz { Label("\(Int(f.rounded())) %", systemImage: "checkmark.circle") }
            }
            .font(.subheadline).foregroundStyle(Rang.matn2).monospacedDigit()
            YuklashNishon(holat: skan.yuklash)
        }
        .padding(14)
        .background(Rang.sirt, in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous).strokeBorder(Rang.chiziq))
        .contentShape(Rectangle())
    }
}

extension YuklashHolati {
    /// Server imzo va zanjirni tekshirib tasdiqlagan (qayta yuklash kerak emas).
    var tasdiqlangan: Bool { if case .yuklandi(let m) = self { m.hasPrefix("TASDIQLANGAN") } else { false } }
}

struct YuklashNishon: View {
    let holat: YuklashHolati
    var qisqa = false
    var body: some View {
        switch holat {
        case .kutmoqda:
            HolatChip(matn: qisqa ? "Yuklanmagan" : "Serverga yuklanmagan", tur: .neytral, belgi: "icloud.and.arrow.up")
        case .yuklandi(let m):
            if m.hasPrefix("TASDIQLANGAN") {
                HolatChip(matn: qisqa ? "Muhrlangan" : "Muhr tasdiqlangan", tur: .ok, belgi: "checkmark.seal.fill")
            } else {
                HolatChip(matn: qisqa ? "Muhr buzilgan" : "Muhr: \(m)", tur: .xato, belgi: "xmark.seal.fill")
            }
        case .xato(let x):
            HolatChip(matn: qisqa ? "Xato" : x, tur: .xato, belgi: "exclamationmark.icloud")
        }
    }
}

// MARK: - Yakun hisoboti (D-07, DZ-06)

struct HisobotEkrani: View {
    let loyihaId: UUID
    let skanId: UUID
    let yopish: (() -> Void)?
    @Environment(LoyihaOmbori.self) private var ombor
    @Environment(Sozlamalar.self) private var sozlama
    @Environment(Yuklovchi.self) private var yuklovchi
    @State private var chizmaURL: URL?
    @State private var katalogURL: URL?
    @State private var chizmaXato: String?

    var body: some View {
        if let l = ombor.loyiha(loyihaId), let s = l.skanlar.first(where: { $0.id == skanId }) {
            let t = TarmoqTuri.top(l.tarmoqTuri)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l.nomi).font(.title3.weight(.bold)).foregroundStyle(Rang.matn)
                        Text("\(s.boshlandi.formatted(date: .abbreviated, time: .shortened)) · \(Format.vaqt(s.tugadi.timeIntervalSince(s.boshlandi)))")
                            .font(.subheadline).foregroundStyle(Rang.matn2)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        OlchovKarta(nomi: "Kadrlar", qiymat: "\(s.kadrSoni)", izoh: "RTK tegli rasm")
                        OlchovKarta(nomi: "RASMIY kadr", qiymat: s.rasmiyKadrFoiz.map { Format.son($0, raqam: 0) } ?? "—",
                                    birlik: s.rasmiyKadrFoiz == nil ? nil : "%", izoh: "FIX, σH ≤ 2 sm",
                                    rang: s.rasmiyKadrFoiz.map { SifatPogonasi.ulush(foiz: $0).rang } ?? Rang.matn)
                        OlchovKarta(nomi: "Yurilgan", qiymat: Format.son(s.masofaM), birlik: "m", izoh: "kamera traektoriyasi")
                        OlchovKarta(nomi: "Mesh", qiymat: Format.son(s.meshMaydoniM2), birlik: "m²", izoh: "LiDAR sirti")
                    }
                    BolimKarta(sarlavha: "Georeferens", belgi: "scope") {
                        if let g = s.georef {
                            // UI-19: PIX4Dcatch pog'onalari — < 3 sm optimal, 3–6 sm pasaygan, > 6 sm past
                            switch SifatPogonasi.aniqlik(sm: max(g.gorizontalRmsM, g.vertikalRmsM) * 100) {
                            case .yaxshi:
                                HolatChip(matn: "Bog'langan: optimal aniqlik (< 3 sm)", tur: .ok, belgi: "checkmark.circle.fill")
                            case .orta:
                                HolatChip(matn: "Bog'langan: pasaygan aniqlik (3–6 sm)", tur: .ogoh, belgi: "exclamationmark.triangle.fill")
                            case .past:
                                HolatChip(matn: "Aniqlik past (> 6 sm): qayta skan tavsiya", tur: .xato, belgi: "xmark.octagon.fill")
                            }
                            QiymatQatori(nomi: "Gorizontal RMS", qiymat: Format.sm(g.gorizontalRmsM))
                            QiymatQatori(nomi: "Vertikal RMS", qiymat: Format.sm(g.vertikalRmsM))
                            QiymatQatori(nomi: "RTK juftlari", qiymat: "\(g.juftSoni)")
                            QiymatQatori(nomi: "Koordinatalar", qiymat: "WGS84 / UTM \(g.utmZona)N")
                            if let x = s.xom {
                                // DS-04/05: telefonning o'zidagi qayta hisob — server bilan bir xil yadro
                                QiymatQatori(nomi: "Bo'lakli georeferens", qiymat: x.bolaklar > 0
                                             ? "\(x.bolaklar) bo'lak, PAST \(x.pastBolaklar)" : "hisoblanmadi")
                                if let t = x.maksTuzatishSm { QiymatQatori(nomi: "ARKit suzishi tuzatildi", qiymat: "≤ " + Format.son(t) + " sm") }
                                QiymatQatori(nomi: "RTK kechikishi", qiymat: x.kechikishMs.map { Format.son($0, raqam: 0) + " ms"
                                    + (x.kechikishIshonchli ? "" : " (taxminiy)") } ?? "baholanmadi")
                                QiymatQatori(nomi: "Bulut", qiymat: x.plyNomi == "zich.ply" ? "zich, rangli (LiDAR chuqurlik)" : "ARKit mesh")
                                ForEach(x.ogohlantirishlar, id: \.self) { o in
                                    HolatChip(matn: o, tur: .ogoh, belgi: "exclamationmark.triangle.fill")
                                }
                            }
                        } else {
                            HolatChip(matn: "Georeferens yo'q", tur: .xato, belgi: "location.slash")
                            Text("RTK FIX juftlari yetarli emas edi. Quvurlar faqat mahalliy ramkada.")
                                .font(.subheadline).foregroundStyle(Rang.matn2)
                        }
                    }
                    Text("Aniqlangan quvurlar").font(.title3.weight(.bold)).foregroundStyle(Rang.matn).padding(.top, 4)
                    if s.quvurlar.isEmpty {
                        BolimKarta(sarlavha: nil) {
                            Text("Avtomatik topilmadi. Skanda quvur yetarli ko'rinmagan bo'lishi mumkin.")
                                .font(.subheadline).foregroundStyle(Rang.matn2)
                        }
                    }
                    ForEach(Array(s.quvurlar.enumerated()), id: \.offset) { i, q in
                        QuvurHisobKarta(quvur: q, tarmoq: t, raqam: i + 1)
                        BoylamaProfilKarta(quvur: q, raqam: i + 1, tarmoq: t, hOfset: s.georef?.t[2])
                    }
                    if !s.quvurlar.isEmpty { RejaKarta(quvurlar: s.quvurlar, tarmoq: t, burchak: s.georef?.burchak) }
                    BolimKarta(sarlavha: "Raqamli muhr", belgi: "lock.shield") {
                        YuklashNishon(holat: s.yuklash)
                        QiymatQatori(nomi: "Yozuvlar", qiymat: "\(s.yozuvSoni)")
                        QiymatQatori(nomi: "Zanjir boshi", qiymat: String(s.zanjirBoshi.prefix(16)) + "…", mono: true)
                    }
                    BolimKarta(sarlavha: "Ijro chizmasi", belgi: "doc.richtext") {
                        Text(s.georef == nil ? "Georeferens yo'q — UTM koordinatali chizma tuzib bo'lmaydi."
                             : "DXF R12, UTM \(s.georef?.utmZona ?? 42)N. Skandan olingan liniyalar SKAN deb belgilanadi va punktir chiziladi — geodezist RTK nazorat nuqtalari bilan tasdiqlaydi.")
                            .font(.footnote).foregroundStyle(Rang.matn2)
                        Button {
                            chizmaXato = nil
                            do { (chizmaURL, katalogURL) = try IjroChizma.yarat(loyiha: l, skan: s) } catch { chizmaXato = error.localizedDescription }
                        } label: { Label(chizmaURL == nil ? "DXF yaratish (oflayn)" : "Qayta yaratish", systemImage: "doc.badge.plus") }
                            .buttonStyle(IkkilamchiTugma())
                            .disabled(s.georef == nil || s.quvurlar.isEmpty)
                        if let url = chizmaURL {
                            ShareLink(item: url) { Label("DXF chizmani ulashish", systemImage: "square.and.arrow.up") }
                                .buttonStyle(IkkilamchiTugma())
                        }
                        if let csv = katalogURL {
                            ShareLink(item: csv) { Label("Koordinata katalogi (CSV)", systemImage: "tablecells") }
                                .buttonStyle(IkkilamchiTugma())
                        }
                        if let x = chizmaXato { Text(x).font(.footnote).foregroundStyle(Rang.past) }
                    }
                    // Tasdiqlangandan keyin tugma yo'q: qayta yuklash serverda ikkinchi skan ochadi
                    if !s.yuklash.tasdiqlangan {
                        Button {
                            Task { await yuklovchi.yukla(loyihaId: loyihaId, skanId: skanId, ombor: ombor, sozlama: sozlama) }
                        } label: {
                            if yuklovchi.ishlayapti {
                                HStack(spacing: 10) {
                                    ProgressView().tint(.white)
                                    Text("\(yuklovchi.bosqich) · \(Int(yuklovchi.jarayon * 100)) %").monospacedDigit()
                                }
                            } else {
                                Label("Serverga yuklash va muhrlash", systemImage: "checkmark.seal")
                            }
                        }
                        .buttonStyle(AsosiyTugma())
                        .accessibilityHint(yuklovchi.ishlayapti ? "Yuklash davom etmoqda" : "")
                    }
                }
                .padding(16)
            }
            .background(Rang.fon.ignoresSafeArea())
            .navigationTitle("Skan hisoboti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if let yopish { ToolbarItem(placement: .confirmationAction) { Button("Tayyor", action: yopish) } } }
        }
    }
}

/// Hisobotdagi quvur kartasi (K-01…K-04 natijasi).
struct QuvurHisobKarta: View {
    let quvur: QuvurXulosa
    let tarmoq: TarmoqTuri
    let raqam: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(tarmoq.rang).frame(width: 6, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(tarmoq.nomi) — quvur \(raqam)").font(.headline).foregroundStyle(Rang.matn)
                    Text(olchamMatni).font(.subheadline).foregroundStyle(Rang.matn2)
                }
                Spacer()
                SifatNishon(sifat: "SKAN")
            }
            HStack(spacing: 0) {
                mini("Chuqurlik", quvur.chuqurlikM.map { Format.m($0) } ?? "—")
                mini("Nishab", Format.son(quvur.qiyalikFoiz) + " %")
                mini("Uzunlik", Format.m(quvur.uzunlikM, raqam: 1))
                mini("Ishonch", "\(Int((quvur.ishonch * 100).rounded())) %")
            }
            if quvur.muftaSoni > 0 {
                Label("\(quvur.muftaSoni) mufta nomzodi", systemImage: "circle.dotted").font(.footnote).foregroundStyle(Rang.matn2)
            }
        }
        .padding(16)
        .background(Rang.sirt, in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous).strokeBorder(Rang.chiziq))
    }

    private var olchamMatni: String {
        if let d = quvur.standartMm { return ["Ø\(Int(d)) mm", quvur.seriya].compactMap { $0 }.joined(separator: " · ") }
        return "Ø≈\(Int(quvur.tashqiDiametrMm.rounded())) mm (standartga tushmadi)"
    }

    private func mini(_ n: String, _ q: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(.caption).foregroundStyle(Rang.matn3)
            Text(q).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Rang.matn)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ulanish (D-03, D-04)

struct UlanishEkrani: View {
    @Environment(RTKBoshqaruv.self) private var rtk
    @Environment(Sozlamalar.self) private var s
    @Environment(\.dismiss) private var yop
    @State private var mountpointlar: [(mountpoint: Mountpoint, masofaKm: Double)] = []
    @State private var jadvalXato: String?
    @State private var yuklanmoqda = false

    var body: some View {
        @Bindable var s = s
        Form {
            Section {
                holatQatori
                Button("Emlid Reach (Bluetooth MFi) — ulanish") { rtk.ulanEA() }
                Button("Yangi qurilmani juftlash…") { EATransport.tanlash { _ in rtk.ulanEA() } }
                HStack {
                    TextField("TCP host", text: $s.tcpHost).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("port", value: $s.tcpPort, format: .number.grouping(.never)).keyboardType(.numberPad).frame(width: 70)
                }
                Button("Wi-Fi (TCP) orqali ulanish") { rtk.ulanTCP(host: s.tcpHost, port: s.tcpPort) }
                if rtk.ulangan { Button("Uzish", role: .destructive) { rtk.uz() } }
            } header: {
                bosqich(1, "Qabul qilgich", rtk.ulangan ? (rtk.sifat == .rasmiy ? .ok : .ogoh) : .xato,
                        rtk.ulangan ? "RTK \(rtk.holat.rtk.rawValue)" : "ulanmagan")
            }
            if rtk.ulangan {
                Section("Joriy yechim") {
                    LabeledContent("Holat", value: rtk.holat.rtk.rawValue + " · " + rtk.sifat.rawValue)
                    LabeledContent("σ gorizontal / vertikal", value: "\(rtk.holat.sigmaHSm.map { Format.son($0) } ?? "—") / \(rtk.holat.sigmaVSm.map { Format.son($0) } ?? "—") sm")
                    LabeledContent("Sputniklar", value: rtk.holat.sputnikSoni.map(String.init) ?? "—")
                    LabeledContent("Tuzatma yoshi", value: rtk.tuzatmaYoshiS.map { Format.son($0) + " s" } ?? (rtk.holat.tuzatmaYoshiS.map { Format.son($0) + " s (qabul qilgich)" } ?? "—"))
                    LabeledContent("Baza masofasi", value: rtk.bazaMasofaKm.map { Format.son($0) + " km" } ?? "—")
                    if !rtk.tizimlar.isEmpty { LabeledContent("Tuzatmadagi tizimlar", value: rtk.tizimlar.joined(separator: ", ")) }
                }
            }
            Section {
                TextField("Caster (host)", text: $s.ntripHost).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                HStack {
                    TextField("Port", value: $s.ntripPort, format: .number.grouping(.never)).keyboardType(.numberPad)
                    Picker("Versiya", selection: $s.ntripVersiya) { Text("NTRIP 2").tag(2); Text("NTRIP 1").tag(1) }.pickerStyle(.segmented)
                }
                TextField("Login", text: $s.ntripLogin).autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("Parol", text: $s.ntripParol)
                TextField("Mountpoint", text: $s.ntripMountpoint).autocorrectionDisabled().textInputAutocapitalization(.characters)
                Button(yuklanmoqda ? "Yuklanmoqda…" : "Eng yaqin mountpointlar") { Task { await jadval() } }.disabled(yuklanmoqda || s.ntripHost.isEmpty)
                if let x = jadvalXato { Text(x).font(.system(size: 13)).foregroundStyle(.red) }
                ForEach(Array(mountpointlar.enumerated()), id: \.offset) { i, m in
                    Button { s.ntripMountpoint = m.mountpoint.nomi } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(m.mountpoint.nomi).font(.subheadline.weight(.semibold)).foregroundStyle(Rang.matn)
                                    // UI-20 [P2]: eng yaqin baza stansiyasi tavsiya qilinadi
                                    if i == 0, m.masofaKm > 0 { HolatChip(matn: "Tavsiya", tur: .ok, belgi: "star.fill") }
                                }
                                Text("\(m.mountpoint.format) · \(m.mountpoint.navTizim)\(m.mountpoint.tarmoqYechimi ? " · VRS" : "")")
                                    .font(.caption).foregroundStyle(Rang.matn2)
                            }
                            Spacer()
                            if s.ntripMountpoint == m.mountpoint.nomi { Image(systemName: "checkmark").foregroundStyle(Rang.urgu) }
                            Text(Format.son(m.masofaKm) + " km").monospacedDigit()
                                .foregroundStyle(m.masofaKm > 20 ? Rang.skanSifat : Rang.matn2)
                        }
                    }
                }
                Button("NTRIP ulanish") {
                    s.saqla()
                    rtk.ntripUlan(NTRIPSozlama(host: s.ntripHost, port: s.ntripPort, mountpoint: s.ntripMountpoint,
                                               login: s.ntripLogin, parol: s.ntripParol, versiya: s.ntripVersiya))
                }
                .disabled(s.ntripHost.isEmpty || s.ntripMountpoint.isEmpty)
                ntripHolati
            } header: {
                bosqich(2, "Tuzatmalar (NTRIP)", ntripTur, ntripQisqa)
            } footer: {
                Text("UzPOS, Emlid Caster yoki o'z Reach RS3 bazangiz. Tuzatmalar qabul qilgichga MFi orqali uzatiladi. Odatiy tuzatma yoshi 1–2 s.")
            }
            Section {
                LabeledContent("x · y · z", value: s.antennaOfset.count == 3
                               ? s.antennaOfset.map { Format.son($0, raqam: 3) }.joined(separator: " · ") + " m" : "—")
                NavigationLink("Ofsetni o'zgartirish") { SozlamalarEkrani() }
            } header: {
                bosqich(3, "Antenna ofseti", s.antennaOfsetKiritilgan ? .ok : .ogoh, s.antennaOfsetKiritilgan ? "kiritilgan" : "kiritilmagan")
            } footer: {
                Text("Kamera va antenna fazaviy markazi orasidagi masofa. Noto'g'ri ofset georeferensni buzadi.")
            }
        }
        .navigationTitle("Ulanish")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tayyor") { s.saqla(); yop() } } }
        .onDisappear { s.saqla() }
    }

    /// UI-20: bosqich sarlavhasi — raqam, nom va holat chipi (katta harflarsiz).
    private func bosqich(_ n: Int, _ nomi: String, _ tur: HolatChip.Tur, _ holat: String) -> some View {
        HStack(spacing: 8) {
            Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Rang.tugma, in: Circle())
            Text(nomi).font(.subheadline.weight(.semibold)).foregroundStyle(Rang.matn)
            Spacer()
            HolatChip(matn: holat, tur: tur)
        }
        .textCase(nil)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    private var ntripTur: HolatChip.Tur {
        switch rtk.ntripHolati {
        case .oqim: return (rtk.tuzatmaYoshiS ?? 0) > 10 ? .ogoh : .ok
        case .ulanmoqda, .ochiq: return .neytral
        case .xato: return .xato
        }
    }

    private var ntripQisqa: String {
        switch rtk.ntripHolati {
        case .oqim: return rtk.tuzatmaYoshiS.map { "yoshi " + Format.son($0, raqam: 0) + " s" } ?? "kelmoqda"
        case .ulanmoqda: return "ulanmoqda"
        case .ochiq: return "o'chiq"
        case .xato: return "xato"
        }
    }

    @ViewBuilder private var holatQatori: some View {
        switch rtk.ulanish {
        case .yoq: Label("Ulanmagan", systemImage: "antenna.radiowaves.left.and.right.slash").foregroundStyle(.secondary)
        case .ulanmoqda: HStack { ProgressView(); Text("Ulanmoqda…") }
        case .ulangan(let n): Label(n, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .xato(let x): Label(x, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder private var ntripHolati: some View {
        switch rtk.ntripHolati {
        case .ochiq: EmptyView()
        case .ulanmoqda: HStack { ProgressView(); Text("Casterga ulanmoqda…") }
        case .oqim: Label("Tuzatmalar kelmoqda", systemImage: "dot.radiowaves.up.forward").foregroundStyle(.green)
        case .xato(let x): Label(x, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private func jadval() async {
        yuklanmoqda = true; jadvalXato = nil
        defer { yuklanmoqda = false }
        do {
            let r = try await NTRIPKlient.manbaJadvali(host: s.ntripHost, port: s.ntripPort, versiya: s.ntripVersiya)
            if let lat = rtk.holat.lat, let lon = rtk.holat.lon {
                mountpointlar = ManbaJadvali.engYaqin(r, lat: lat, lon: lon, soni: 8)
            } else {
                mountpointlar = r.prefix(12).map { (mountpoint: $0, masofaKm: 0.0) }
                jadvalXato = "RTK joylashuvi yo'q — masofa bo'yicha saralanmadi"
            }
            if r.isEmpty { jadvalXato = "Caster mountpoint qaytarmadi" }
        } catch {
            jadvalXato = error.localizedDescription
        }
    }
}

// MARK: - Sozlamalar (D-11)

struct SozlamalarEkrani: View {
    @Environment(Sozlamalar.self) private var s
    @Environment(RTKBoshqaruv.self) private var rtk
    @Environment(\.dismiss) private var yop
    @State private var seriya = ""

    var body: some View {
        @Bindable var s = s
        Form {
            Section {
                TextField("https://trace4dapi.example.uz", text: $s.serverManzil).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("Dala tokeni (YRD.…)", text: $s.dalaToken)
            } header: { Text("Server") } footer: { Text("Token admin panelidagi «Dala qurilmalari» bo'limida bir marta ko'rsatiladi.") }
            Section {
                ofsetMaydon("x (o'ngga)", 0)
                ofsetMaydon("y (yuqoriga)", 1)
                ofsetMaydon("z (o'zingizga)", 2)
                HStack {
                    Text("RTK kechikishi")
                    Spacer()
                    TextField("s", value: $s.rtkKechikishS, format: .number.precision(.fractionLength(3))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    Text("s")
                }
            } header: { Text("Antenna ofseti (kameraga nisbatan, m)") } footer: {
                Text("Telefon portret holatda. Emlid skanerlash dastagida o'lchab kiriting (T-095). Noto'g'ri ofset georeferensni buzadi. "
                     + "Manba: \(s.ofsetManba). Server har skanda ofsetni xom ma'lumotdan tekshiradi va farq 2 sm dan oshsa ogohlantiradi.")
            }
            Section {
                Picker("Dastak", selection: $s.dastak) {
                    Text("Emlid skanerlash dastagi").tag("emlid-skan")
                    Text("Vexa").tag("vexa")
                    Text("Yo'q").tag("yo'q")
                }
                Picker("Telefon tomoni", selection: $s.dastakTomoni) {
                    Text("O'ng").tag("o'ng")
                    Text("Chap").tag("chap")
                }
                if let j = DastakProfillari.top(identifikator: Qurilma.model, tomon: s.dastakTomoni) {
                    LabeledContent("Jadval (\(j.profil.iphone))", value: j.ofset.map { Format.son($0, raqam: 3) }.joined(separator: " · ") + " m")
                    Text(j.profil.manba + (j.profil.tasdiqlangan ? "" : ". TASDIQLANMAGAN: o'qlar yo'nalishi manbada yo'q — o'lchab tekshiring."))
                        .font(.footnote).foregroundStyle(j.profil.tasdiqlangan ? Rang.matn2 : Rang.skanSifat)
                    Button("Jadval qiymatini qo'llash") { s.antennaOfset = j.ofset; s.ofsetManba = "jadval" }
                } else {
                    Text("Bu iPhone (\(Qurilma.model)) uchun dastak jadvalida qiymat yo'q — ofsetni o'lchab kiriting.")
                        .font(.footnote).foregroundStyle(Rang.matn2)
                }
                Toggle("Zich rangli bulut (LiDAR chuqurlik)", isOn: $s.zichBulut)
            } header: { Text("Dastak profili (DS-02)") } footer: {
                Text("Profil har skan jurnaliga muhrlanadi. Zich bulut quvurni aniqroq topadi, lekin fayl kattaroq (30 m transheya ~ 20–30 MB).")
            }
            Section {
                if let m = rtk.moslik {
                    HolatChip(matn: m.izoh, tur: m.iosMos ? .ok : .xato, belgi: m.iosMos ? "checkmark.circle.fill" : "xmark.octagon.fill")
                }
                TextField("Seriya raqami (qurilma tagida)", text: $seriya).autocorrectionDisabled().textInputAutocapitalization(.characters)
                if !seriya.isEmpty {
                    let m = ReachMoslik.seriyadan(seriya)
                    Text(m.izoh).font(.footnote).foregroundStyle(m.iosMos ? Rang.matn2 : Rang.past)
                }
            } header: { Text("Qabul qilgich mosligi (DS-01)") } footer: {
                Text("iPhone bilan faqat Reach RX2 va Reach RX MFi ishlaydi. 1-avlod Reach RX faqat Android bilan ishlaydi (Emlid hujjati).")
            }
            Section {
                Toggle("Tebranish (haptika)", isOn: $s.haptika)
            } header: { Text("Qulaylik") } footer: {
                Text("Skan boshlanishi va tugashi, quvur topilishi va FIX yo'qolishida qisqa tebranish. Kamera ishiga xalaqit bermasligi uchun faqat muhim hodisalarda.")
            }
            Section("Qurilma kaliti (Secure Enclave)") {
                LabeledContent("Barmoq izi", value: QurilmaKaliti.barmoqIzi() ?? "yaratilmagan").font(.system(.footnote, design: .monospaced))
            }
        }
        .navigationTitle("Sozlamalar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tayyor") { s.saqla(); yop() } } }
        .onDisappear { s.saqla() }
    }

    private func ofsetMaydon(_ nomi: String, _ i: Int) -> some View {
        HStack {
            Text(nomi)
            Spacer()
            TextField("0", value: Binding(get: { s.antennaOfset.count == 3 ? s.antennaOfset[i] : 0 },
                                          set: { v in
                                              var o = s.antennaOfset.count == 3 ? s.antennaOfset : [0, 0, 0]
                                              o[i] = v
                                              s.antennaOfset = o
                                              s.ofsetManba = "qo'lda"
                                          }),
                      format: .number.precision(.fractionLength(3)))
                .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).frame(width: 90)
            Text("m")
        }
    }
}

/// K-08: ijro chizmasi qurilmaning o'zida (oflayn) — yadrodagi DXFChizma (LibreOffice'da tekshirilgan).
enum IjroChizma {
    struct Xato: LocalizedError { let matn: String; var errorDescription: String? { matn } }

    static func yarat(loyiha l: Loyiha, skan s: SkanYozuvi) throws -> (URL, URL) {
        guard let g = s.georef else { throw Xato(matn: "Georeferens yo'q") }
        let T = GorizontalTransformatsiya(burchak: g.burchak, t: Vektor3(g.t[0], g.t[1], g.t[2]))
        let liniyalar: [ChizmaLiniya] = s.quvurlar.map { q in
            ChizmaLiniya(turi: l.tarmoqTuri, diametrMm: Int((q.standartMm ?? q.tashqiDiametrMm).rounded()), material: l.material,
                         sifat: "SKAN", nuqtalar: q.oqMahalliy.map { p in
                             let u = T.qolla(ARKitRamka.enu(Vektor3(p[0], p[1], p[2])))
                             return ChizmaNuqta(e: u.x, n: u.y, h: u.z, chuqurlik: q.chuqurlikM, sifat: "SKAN")
                         })
        }
        let muhr: String
        switch s.yuklash {
        case .yuklandi(let m): muhr = m
        case .kutmoqda: muhr = "serverga yuklanmagan (zanjir \(s.zanjirBoshi.prefix(12)))"
        case .xato: muhr = "yuklash xatosi (zanjir \(s.zanjirBoshi.prefix(12)))"
        }
        let sana = ISO8601DateFormatter.string(from: s.tugadi, timeZone: .current, formatOptions: [.withFullDate])
        let dxf = DXFChizma.yoz(liniyalar, sarlavha: ChizmaSarlavha(
            obyekt: l.nomi, order: l.orderMatn, pudratchi: l.pudratchi, buyurtmachi: l.buyurtmachi, sana: sana,
            muhr: muhr, koordinataTizimi: "WGS84 / UTM \(g.utmZona)N"))
        let papka = Papkalar.hujjatlar.appendingPathComponent(s.papka, isDirectory: true)
        let nom = DXFChizma.ascii(l.nomi).replacingOccurrences(of: "/", with: "-").prefix(40)
        let u1 = papka.appendingPathComponent("ijro_\(nom)_\(sana).dxf")
        let u2 = papka.appendingPathComponent("katalog_\(nom)_\(sana).csv")
        try dxf.write(to: u1, atomically: true, encoding: .ascii)
        try DXFChizma.katalogCSV(liniyalar).write(to: u2, atomically: true, encoding: .utf8)
        return (u1, u2)
    }
}
