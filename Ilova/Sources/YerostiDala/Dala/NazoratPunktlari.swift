import SwiftUI
import UIKit
import YerostiDrayver
import YerostiGeometriya
import YerostiHUD

/// LK-10: geodezik asos — nazorat punktlari, RTK o'lchovi (≥ 30 s uzluksiz FIX), joyida lokalizatsiya va qoldiqlar.
/// Hisob server bilan bir xil yadroda (`Lokalizatsiya`): brigada xato punktni joyida ko'radi va qayta o'lchaydi.
struct NazoratEkrani: View {
    let loyihaId: UUID
    @Environment(LoyihaOmbori.self) private var ombor
    @Environment(Sozlamalar.self) private var sozlama
    @State private var olchash: OlchashMaqsadi?
    @State private var punktQoshOchiq = false
    @State private var xabar: String?
    @State private var band = false

    struct OlchashMaqsadi: Identifiable {
        let punkt: NazoratPunkt
        let maqsad: String
        var id: String { punkt.nomi + "·" + maqsad }
    }

    var body: some View {
        if let l = ombor.loyiha(loyihaId) {
            let lok = l.lokalizatsiya()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    holatKarta(lok, l.bugungiNazorat())
                    if let xabar { OgohQatori(matn: xabar, belgi: "info.circle.fill") }
                    Text("Punktlar").font(.title3.weight(.bold)).foregroundStyle(Rang.matn).padding(.top, 4)
                    if l.punktlar.isEmpty {
                        Text("Shahar tarmog'i yoki qurilish razbivka asosi punktlarini kiriting (portaldan yoki shu yerda). Obyektni o'rab turgan kamida 4 ta punkt kerak.")
                            .font(.subheadline).foregroundStyle(Rang.matn2)
                    }
                    ForEach(l.punktlar) { p in punktKarta(p, l, lok) }
                    Button { punktQoshOchiq = true } label: { Label("Punkt qo'shish", systemImage: "plus") }
                        .buttonStyle(IkkilamchiTugma())
                    if l.serverId != nil {
                        Button { Task { await serverdanOl(l) } } label: { Label("Serverdan olish", systemImage: "arrow.down.circle") }
                            .buttonStyle(IkkilamchiTugma()).disabled(band)
                        let kutayotgan = l.olchovlar.filter { $0.serverId == nil }.count
                        if kutayotgan > 0 {
                            Button { Task { await yubor(l) } } label: {
                                Label("Serverga yuborish (\(kutayotgan))", systemImage: "icloud.and.arrow.up")
                            }
                            .buttonStyle(AsosiyTugma()).disabled(band)
                        }
                    } else {
                        OgohQatori(matn: "Loyiha hali serverda yo'q: o'lchovlar telefonda saqlanadi, birinchi skan yuklangach yuboriladi.")
                    }
                }
                .padding(16)
            }
            .background(Rang.fon.ignoresSafeArea())
            .navigationTitle("Geodezik asos")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $olchash) { m in
                NavigationStack { OlchashVaragi(loyihaId: loyihaId, punkt: m.punkt, maqsad: m.maqsad) }
            }
            .sheet(isPresented: $punktQoshOchiq) { NavigationStack { PunktQoshishVaragi(loyihaId: loyihaId) } }
        }
    }

    private func holatKarta(_ lok: LokNatija?, _ bugun: NazoratHolati) -> some View {
        BolimKarta(sarlavha: "Lokalizatsiya", belgi: "scope") {
            if let n = lok {
                HStack {
                    Text("\(n.nGor) gorizontal · \(n.nVer) vertikal punkt").font(.subheadline).foregroundStyle(Rang.matn2)
                    Spacer()
                    HolatChip(matn: n.yaroqli ? "yaroqli" : "yaroqsiz", tur: n.yaroqli ? .ok : .xato,
                              belgi: n.yaroqli ? "checkmark.seal.fill" : "xmark.seal.fill")
                }
                QiymatQatori(nomi: "Eng katta qoldiq", qiymat: "\(Format.sm(n.maksGor)) / \(Format.sm(n.maksVer))")
                ForEach(n.xatolar, id: \.self) { Text($0).font(.footnote.weight(.semibold)).foregroundStyle(Rang.past) }
                ForEach(n.ogohlantirishlar, id: \.self) { Text($0).font(.footnote).foregroundStyle(Rang.skanSifat) }
            } else {
                Text("Hali o'lchov yo'q. Har punktda vexani tik tutib «O'lchash» ni bosing: 30 s uzluksiz FIX kerak.")
                    .font(.subheadline).foregroundStyle(Rang.matn2)
            }
            switch bugun {
            case .punktYoq: EmptyView()
            case .bugunYoq: HolatChip(matn: "Bugun tekshiruv qilinmagan", tur: .ogoh, belgi: "exclamationmark.triangle.fill")
            case .bugunOtdi(let d): HolatChip(matn: "Bugungi tekshiruv: \(Format.sm(d))", tur: .ok, belgi: "checkmark.circle.fill")
            case .bugunOtmadi(let d): HolatChip(matn: "Bugungi tekshiruv O'TMADI: \(Format.sm(d))", tur: .xato, belgi: "xmark.octagon.fill")
            }
        }
    }

    private func punktKarta(_ p: NazoratPunkt, _ l: Loyiha, _ lok: LokNatija?) -> some View {
        let kal = l.olchovlar.filter { $0.punktNomi == p.nomi && $0.maqsad == "kalibrlash" }.count
        let tek = l.olchovlar.filter { $0.punktNomi == p.nomi && $0.maqsad == "tekshiruv" }.count
        let q = lok?.qoldiqlar.first { $0.nomi == p.nomi }
        let yomon = (q?.gor ?? 0) > Lokalizatsiya.qoldiqGorM || abs(q?.ver ?? 0) > Lokalizatsiya.qoldiqVerM
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(p.nomi).font(.headline).foregroundStyle(Rang.matn)
                if !p.sinf.isEmpty { Text(p.sinf).font(.caption).foregroundStyle(Rang.matn3) }
                Spacer()
                HolatChip(matn: "\(kal) + \(tek)", tur: kal > 0 ? (yomon ? .xato : .ok) : .neytral, belgi: "location.fill")
            }
            Text(koordinata(p)).font(.footnote.monospaced()).foregroundStyle(Rang.matn2)
            if let q {
                Text("Qoldiq: \(Format.sm(q.gor)) gorizontal, \(Format.sm(q.ver.map(abs))) vertikal")
                    .font(.footnote.weight(.semibold)).foregroundStyle(yomon ? Rang.past : Rang.rasmiy)
            }
            HStack(spacing: 10) {
                Button("O'lchash") { olchash = .init(punkt: p, maqsad: "kalibrlash") }.buttonStyle(IkkilamchiTugma())
                Button("Tekshiruv") { olchash = .init(punkt: p, maqsad: "tekshiruv") }.buttonStyle(IkkilamchiTugma())
                    .disabled(lok == nil)
            }
        }
        .padding(14)
        .background(Rang.sirt, in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous).strokeBorder(Rang.chiziq))
        .accessibilityElement(children: .contain)
    }

    private func koordinata(_ p: NazoratPunkt) -> String {
        let x = p.x.map { "X " + Format.son($0, raqam: 3) } ?? "X —"
        let y = p.y.map { "Y " + Format.son($0, raqam: 3) } ?? "Y —"
        let h = p.h.map { "H " + Format.son($0, raqam: 3) } ?? "H —"
        return "\(x) · \(y) · \(h)"
    }

    @MainActor private func serverdanOl(_ l: Loyiha) async {
        guard let sid = l.serverId else { return }
        band = true
        defer { band = false }
        do {
            let m = try ServerMijoz(manzil: sozlama.serverManzil, token: sozlama.dalaToken)
            let (punktlar, olchovlar) = try await m.geodezikAsos(obyektId: sid)
            for p in punktlar { ombor.punktSaqla(p, loyihaId: l.id) }
            let bor = Set(l.olchovlar.compactMap(\.serverId))
            var yangi = 0
            for o in olchovlar where !bor.contains(o.serverId ?? -1) {
                ombor.olchovSaqla(o, loyihaId: l.id)
                yangi += 1
            }
            xabar = "Serverdan: \(punktlar.count) punkt, \(yangi) ta yangi o'lchov."
        } catch {
            xabar = error.localizedDescription
        }
    }

    @MainActor private func yubor(_ l: Loyiha) async {
        guard let sid = l.serverId else { return }
        band = true
        defer { band = false }
        do {
            let m = try ServerMijoz(manzil: sozlama.serverManzil, token: sozlama.dalaToken)
            var soni = 0
            for o in l.olchovlar where o.serverId == nil {
                var y = o
                y.serverId = try await m.nazoratOlchovYubor(obyektId: sid, o)
                ombor.olchovSaqla(y, loyihaId: l.id)
                soni += 1
            }
            xabar = "\(soni) ta o'lchov serverga yuborildi."
        } catch {
            xabar = "Yuborilmadi: \(error.localizedDescription)"
        }
    }
}

/// LK-02: punkt ustida o'rtachalash. Faqat yangi GGA epoxalari olinadi; FIX bir marta yo'qolsa yig'ilgan
/// namunalar tashlanadi va 30 s qaytadan sanaladi (uzluksiz FIX — server shartiga mos).
struct OlchashVaragi: View {
    let loyihaId: UUID
    let punkt: NazoratPunkt
    let maqsad: String
    @Environment(RTKBoshqaruv.self) private var rtk
    @Environment(LoyihaOmbori.self) private var ombor
    @Environment(Sozlamalar.self) private var sozlama
    @Environment(\.dismiss) private var yop
    @AppStorage("vexaBalandligiM") private var vexa = 1.80
    @State private var namunalar: [Namuna] = []
    @State private var boshlandi: Date?
    @State private var oxirgiEpoxa: String?
    @State private var uzilish = 0
    @State private var natija: NazoratOlchov?
    @State private var yuborish: String?
    @State private var soat = Date()

    struct Namuna { let lat: Double, lon: Double, h: Double }
    static let kerakS = 30.0
    static let minEpoxa = 20

    private var otgan: Double { boshlandi.map { soat.timeIntervalSince($0) } ?? 0 }

    var body: some View {
        Form {
            Section("Punkt") {
                QiymatQatori(nomi: "Nomi", qiymat: punkt.nomi)
                QiymatQatori(nomi: "Maqsad", qiymat: maqsad == "tekshiruv" ? "tekshiruv (kalibrlashga kirmaydi)" : "kalibrlash")
            }
            Section {
                HStack {
                    Text("Vexa + antenna, m")
                    Spacer()
                    TextField("1,800", value: $vexa, format: .number.precision(.fractionLength(3)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                }
                .disabled(boshlandi != nil)
            } header: {
                Text("Antenna balandligi")
            } footer: {
                Text("Punkt belgisidan antenna fazaviy markazigacha: vexa uzunligi + qabul qilgich hujjatidagi ofset. Xato balandlik butun o'lchovni buzadi.")
            }
            Section("O'lchov") {
                HStack {
                    Text("RTK")
                    Spacer()
                    HolatChip(matn: rtk.holat.rtk.rawValue + (rtk.holat.sigmaHSm.map { " · " + Format.son($0, raqam: 1) + " sm" } ?? ""),
                              tur: rtk.holat.rtk == .fix ? .ok : .ogoh)
                }
                if natija == nil {
                    ProgressView(value: min(otgan / Self.kerakS, 1)) {
                        Text(boshlandi == nil ? "Vexani punkt ustida tik tuting" :
                                "\(Int(otgan)) / \(Int(Self.kerakS)) s · \(namunalar.count) epoxa")
                    }
                    if uzilish > 0 { Text("FIX \(uzilish) marta uzildi: o'rtachalash qaytadan boshlandi").font(.footnote).foregroundStyle(Rang.skanSifat) }
                    Button(boshlandi == nil ? "Boshlash" : "To'xtatish") {
                        if boshlandi == nil { namunalar = []; uzilish = 0; boshlandi = Date() } else { boshlandi = nil }
                    }
                    .disabled(!rtk.ulangan)
                }
            }
            if let o = natija { natijaBolimi(o) }
        }
        .navigationTitle(maqsad == "tekshiruv" ? "Tekshiruv o'lchovi" : "Punktni o'lchash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(natija == nil ? "Bekor" : "Tayyor") { yop() } } }
        .task(id: boshlandi) { await yigish() }
        .sensoryFeedback(.success, trigger: natija?.id)
    }

    @ViewBuilder private func natijaBolimi(_ o: NazoratOlchov) -> some View {
        let l = ombor.loyiha(loyihaId)
        let lok = l?.lokalizatsiya()
        Section("Natija") {
            QiymatQatori(nomi: "Epoxalar", qiymat: "\(o.epoxalar) · \(Int(o.davomiylikS)) s")
            QiymatQatori(nomi: "Tarqoqlik σ", qiymat: "\(Format.son(o.sigmaHSm, raqam: 1)) / \(Format.son(o.sigmaVSm, raqam: 1)) sm")
            if maqsad == "tekshiruv", let lok {
                let t = Lokalizatsiya.tekshiruv(lok.parametrlar, lat: o.lat, lon: o.lon, h: o.h, x: punkt.x, y: punkt.y, H: punkt.h)
                QiymatQatori(nomi: "Og'ish", qiymat: "\(Format.sm(t.gor)) / \(Format.sm(t.ver.map(abs)))")
                HolatChip(matn: t.otdi ? "Tekshiruv o'tdi" : "O'TMADI: baza, antenna yoki mountpoint xato",
                          tur: t.otdi ? .ok : .xato, belgi: t.otdi ? "checkmark.circle.fill" : "xmark.octagon.fill")
            } else if let q = lok?.qoldiqlar.first(where: { $0.nomi == punkt.nomi }) {
                QiymatQatori(nomi: "Qoldiq", qiymat: "\(Format.sm(q.gor)) / \(Format.sm(q.ver.map(abs)))")
                if let n = lok { Text(n.yaroqli ? "Lokalizatsiya chegaradan o'tadi." : n.xatolar.joined(separator: "; "))
                    .font(.footnote).foregroundStyle(n.yaroqli ? Rang.rasmiy : Rang.skanSifat) }
            }
            if let yuborish { Text(yuborish).font(.footnote).foregroundStyle(Rang.matn2) }
        }
    }

    @MainActor private func yigish() async {
        guard boshlandi != nil, natija == nil else { return }
        while !Task.isCancelled, boshlandi != nil, natija == nil {
            soat = Date()
            let h = rtk.holat
            if h.vaqtUTC != oxirgiEpoxa, let lat = h.lat, let lon = h.lon, let hh = h.balandlikEllipsoid {
                oxirgiEpoxa = h.vaqtUTC
                if h.rtk == .fix, !h.eskirganmi() {
                    namunalar.append(Namuna(lat: lat, lon: lon, h: hh - vexa))
                } else if !namunalar.isEmpty {
                    namunalar = []
                    uzilish += 1
                    boshlandi = Date()       // .task(id:) qayta ishga tushadi
                    return
                }
            }
            if otgan >= Self.kerakS, namunalar.count >= Self.minEpoxa {
                yakunla()
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    @MainActor private func yakunla() {
        let k = Double(namunalar.count)
        let lat = namunalar.map(\.lat).reduce(0, +) / k, lon = namunalar.map(\.lon).reduce(0, +) / k
        let h = namunalar.map(\.h).reduce(0, +) / k
        let mLat = 111_320.0, mLon = 111_320.0 * cos(lat * .pi / 180)
        let sN = (namunalar.map { pow(($0.lat - lat) * mLat, 2) }.reduce(0, +) / k).squareRoot()
        let sE = (namunalar.map { pow(($0.lon - lon) * mLon, 2) }.reduce(0, +) / k).squareRoot()
        let sV = (namunalar.map { pow($0.h - h, 2) }.reduce(0, +) / k).squareRoot()
        // σ: namunalar tarqoqligi va qabul qilgich bahosining kattasi (sm)
        let o = NazoratOlchov(punktNomi: punkt.nomi, maqsad: maqsad, lat: lat, lon: lon, h: h,
                              sigmaHSm: max(hypot(sN, sE) * 100, rtk.holat.sigmaHSm ?? 0),
                              sigmaVSm: max(sV * 100, rtk.holat.sigmaVSm ?? 0), epoxalar: namunalar.count,
                              davomiylikS: otgan, antennaM: vexa, vaqt: Date(), serverId: nil)
        ombor.olchovSaqla(o, loyihaId: loyihaId)
        natija = o
        boshlandi = nil
        UIAccessibility.post(notification: .announcement, argument: "O'lchov tayyor")
        guard let sid = ombor.loyiha(loyihaId)?.serverId else { yuborish = "Telefonda saqlandi."; return }
        Task { @MainActor in
            do {
                let m = try ServerMijoz(manzil: sozlama.serverManzil, token: sozlama.dalaToken)
                var y = o
                y.serverId = try await m.nazoratOlchovYubor(obyektId: sid, o)
                ombor.olchovSaqla(y, loyihaId: loyihaId)
                yuborish = "Serverga yuborildi."
            } catch {
                yuborish = "Telefonda saqlandi, serverga keyin yuboriladi: \(error.localizedDescription)"
            }
        }
    }
}

/// LK-01: punktni qo'lda kiritish (katalogdan). O'nlik vergul ham qabul qilinadi.
struct PunktQoshishVaragi: View {
    let loyihaId: UUID
    @Environment(LoyihaOmbori.self) private var ombor
    @Environment(\.dismiss) private var yop
    @State private var nomi = ""
    @State private var x = ""
    @State private var y = ""
    @State private var h = ""
    @State private var sinf = ""

    private func son(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return t.isEmpty ? nil : Double(t)
    }
    private var yaroqli: Bool {
        let n = !nomi.trimmingCharacters(in: .whitespaces).isEmpty
        let xy = (son(x) != nil) == (son(y) != nil) && (x.isEmpty || son(x) != nil) && (y.isEmpty || son(y) != nil)
        let hh = h.isEmpty || son(h) != nil
        return n && xy && hh && (son(x) != nil || son(h) != nil)
    }

    var body: some View {
        Form {
            Section {
                TextField("Nomi (masalan Pp-112)", text: $nomi).textInputAutocapitalization(.never)
                TextField("X — shimol, m", text: $x).keyboardType(.decimalPad)
                TextField("Y — sharq, m", text: $y).keyboardType(.decimalPad)
                TextField("H — Boltiq, m", text: $h).keyboardType(.decimalPad)
                TextField("Sinf (ixtiyoriy)", text: $sinf)
            } footer: {
                Text("Shahar tarmog'i yoki razbivka asosi katalogidagi qiymatlar. Faqat balandligi ma'lum reperda X va Y bo'sh qoldiriladi.")
            }
        }
        .navigationTitle("Punkt qo'shish")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Bekor") { yop() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Saqlash") {
                    ombor.punktSaqla(NazoratPunkt(nomi: nomi.trimmingCharacters(in: .whitespaces), x: son(x), y: son(y), h: son(h),
                                                  sinf: sinf), loyihaId: loyihaId)
                    yop()
                }
                .disabled(!yaroqli)
            }
        }
    }
}
