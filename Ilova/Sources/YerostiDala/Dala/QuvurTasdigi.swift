import SwiftUI
import UIKit
import YerostiDrayver
import YerostiGeometriya
import YerostiTahlil

/// T-031 / TQ (TALABLAR 18): quvur tasdig'i — skan bilan topilgan quvur o'qini vexa uchi quvur USTIDA turgandagi RTK FIX
/// o'lchovlari bilan tekshirish. Hisob server bilan bir xil yadroda (`QuvurTasdiq`): brigada natijani darhol ko'radi,
/// FARQ chiqsa transheya yopilmasidan qayta o'lchaydi. Tasdiqlangan liniyaning SKAN nuqtalari hujjatga rasmiy kiradi.

struct QuvurOqi: Identifiable {
    let id: String
    let nomi: String
    let radiusM: Double
    let oq: [(lat: Double, lon: Double, h: Double)]
}

struct OqHolati {
    let oq: QuvurOqi
    let holat: QuvurTasdiq.Holat
    let baholar: [(tasdiq: QuvurTasdigi, baho: QuvurTasdiq.Baho)]
}

extension Loyiha {
    /// Georeferensli skanlarning quvur o'qlari WGS84 da, balandlik ellipsoid (yuklashdagi formula bilan bir xil).
    func quvurOqlari() -> [QuvurOqi] {
        var r: [QuvurOqi] = []
        for s in skanlar {
            guard let g = s.georef else { continue }
            let T = GorizontalTransformatsiya(burchak: g.burchak, t: Vektor3(g.t[0], g.t[1], g.t[2]))
            for (i, q) in s.quvurlar.enumerated() {
                let oq = q.oqMahalliy.map { p -> (lat: Double, lon: Double, h: Double) in
                    let u = T.qolla(ARKitRamka.enu(Vektor3(p[0], p[1], p[2])))
                    let (lat, lon) = UTM.dan(UTMNuqta(zona: g.utmZona, shimoliy: true, x: u.x, y: u.y))
                    return (lat, lon, u.z)
                }
                guard oq.count >= 2 else { continue }
                let d = Int((q.standartMm ?? q.tashqiDiametrMm).rounded())
                r.append(QuvurOqi(id: "\(s.id.uuidString)·\(i)",
                                  nomi: "Skan \(s.boshlandi.formatted(date: .numeric, time: .shortened)) · quvur \(i + 1) Ø\(d)",
                                  radiusM: Double(d) / 2000, oq: oq))
            }
        }
        return r
    }

    /// TQ-03/TQ-05: har o'q uchun unga 1 m ichida tegishli tasdiqlar bahosi va liniya holati.
    func tasdiqHolatlari() -> [OqHolati] {
        let oqlar = quvurOqlari()
        guard let birinchi = oqlar.first?.oq.first else { return [] }
        let k = QuvurTasdiq.enu(lat0: birinchi.lat, lon0: birinchi.lon)
        let planar: [[QuvurTasdiq.Nuqta]] = oqlar.map { o in
            o.oq.map { p in let q = k(p.lat, p.lon); return QuvurTasdiq.Nuqta(e: q.e, n: q.n, h: p.h) }
        }
        var bog: [[(tasdiq: QuvurTasdigi, baho: QuvurTasdiq.Baho)]] = Array(repeating: [], count: oqlar.count)
        for t in tasdiqlar {
            var pt = k(t.lat, t.lon)
            pt.h = t.h
            var eng: (Int, QuvurTasdiq.Baho)?
            for (i, P) in planar.enumerated() {
                guard let b = QuvurTasdiq.baholash(oq: P, radiusM: oqlar[i].radiusM, nuqta: pt, usti: t.joy != "oq") else { continue }
                if b.dGor <= QuvurTasdiq.yaqinM, eng == nil || b.dGor < eng!.1.dGor { eng = (i, b) }
            }
            if let (i, b) = eng { bog[i].append((t, b)) }
        }
        return oqlar.indices.map { i in
            OqHolati(oq: oqlar[i], holat: QuvurTasdiq.holat(oq: planar[i], baholar: bog[i].map(\.baho)), baholar: bog[i])
        }
    }
}

enum TasdiqKorinish {
    static let nomlar = ["tasdiqlangan": "RTK tasdiqlangan", "qisman": "qisman tasdiqlangan", "farq": "FARQ",
                         "yoq": "tasdiq yo'q", "rtk": "RTK o'lchov"]
    static func tur(_ h: String) -> HolatChip.Tur { h == "tasdiqlangan" ? .ok : h == "farq" ? .xato : h == "rtk" ? .neytral : .ogoh }
    static func nom(_ h: String) -> String { nomlar[h] ?? h }
}

/// Loyiha sahifasidagi karta: nechta quvur o'qi tasdiqlangan.
struct TasdiqKarta: View {
    let loyiha: Loyiha
    var body: some View {
        let h = loyiha.tasdiqHolatlari()
        let tasdiqlangan = h.filter { $0.holat.holat == "tasdiqlangan" }.count
        let farq = h.filter { $0.holat.holat == "farq" }.count
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal").font(.title3.weight(.semibold)).foregroundStyle(Rang.urgu).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("Quvur tasdig'i (T-031)").font(.headline).foregroundStyle(Rang.matn)
                Text(h.isEmpty ? "georeferensli skan yo'q" :
                        "\(tasdiqlangan) / \(h.count) quvur o'qi RTK bilan tasdiqlangan · \(loyiha.tasdiqlar.count) o'lchov" + (farq > 0 ? " · FARQ \(farq)" : ""))
                    .font(.subheadline).foregroundStyle(Rang.matn2)
            }
            Spacer()
            if !h.isEmpty {
                HolatChip(matn: farq > 0 ? "FARQ" : (tasdiqlangan == h.count ? "tasdiqlangan" : "\(tasdiqlangan)/\(h.count)"),
                          tur: farq > 0 ? .xato : (tasdiqlangan == h.count ? .ok : .ogoh))
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

struct TasdiqEkrani: View {
    let loyihaId: UUID
    @Environment(LoyihaOmbori.self) private var ombor
    @Environment(Sozlamalar.self) private var sozlama
    @Environment(RTKBoshqaruv.self) private var rtk
    @State private var olchashOchiq = false
    @State private var xabar: String?
    @State private var band = false

    var body: some View {
        if let l = ombor.loyiha(loyihaId) {
            let holatlar = l.tasdiqHolatlari()
            let kutayotgan = l.tasdiqlar.filter { $0.serverId == nil }.count
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BolimKarta(sarlavha: "Quvur tasdig'i (T-031)", belgi: "checkmark.seal") {
                        Text("Skan o'qi RTK bilan to'g'ridan-to'g'ri o'lchanmagan (SKAN). Vexa uchini quvur USTIGA qo'yib FIX da o'lchang: boshi, oxiri, har burilish va kamida har 50 m. Og'ish ≤ 5 sm gorizontal, ≤ 8 sm vertikal bo'lsa liniya tasdiqlanadi va hujjatga rasmiy kiradi; chegaradan chiqsa — FARQ, transheya yopilmasidan qayta tekshiring.")
                            .font(.subheadline).foregroundStyle(Rang.matn2)
                        QiymatQatori(nomi: "Tasdiqlar", qiymat: "\(l.tasdiqlar.count)" + (kutayotgan > 0 ? " · yuborilmagan \(kutayotgan)" : ""))
                    }
                    if let xabar { OgohQatori(matn: xabar, belgi: "info.circle.fill") }
                    if holatlar.isEmpty {
                        OgohQatori(matn: "Georeferensli skan yo'q: avval RTK ulangan holda skan qiling, keyin quvur ustini o'lchang.")
                    }
                    ForEach(holatlar, id: \.oq.id) { h in oqKarta(h) }
                    Button { olchashOchiq = true } label: { Label("Quvur ustida o'lchash", systemImage: "scope") }
                        .buttonStyle(AsosiyTugma()).disabled(!rtk.ulangan || holatlar.isEmpty)
                    if !rtk.ulangan { OgohQatori(matn: "RTK ulanmagan: tasdiq o'lchovi faqat FIX da olinadi.") }
                    if l.serverId != nil, kutayotgan > 0 {
                        Button { Task { await yubor(l) } } label: { Label("Serverga yuborish (\(kutayotgan))", systemImage: "icloud.and.arrow.up") }
                            .buttonStyle(IkkilamchiTugma()).disabled(band)
                    }
                }
                .padding(16)
            }
            .background(Rang.fon.ignoresSafeArea())
            .navigationTitle("Quvur tasdig'i")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $olchashOchiq) { NavigationStack { TasdiqOlchashVaragi(loyihaId: loyihaId) } }
        }
    }

    private func oqKarta(_ h: OqHolati) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(h.oq.nomi).font(.headline).foregroundStyle(Rang.matn)
                Spacer()
                HolatChip(matn: TasdiqKorinish.nom(h.holat.holat), tur: TasdiqKorinish.tur(h.holat.holat))
            }
            Text("\(h.holat.otgan) / \(h.holat.soni) tasdiq chegarada · o'q uzunligi \(Format.m(QuvurTasdiq.stansiyalar(h.oq.oq.map { _ in QuvurTasdiq.Nuqta(e: 0, n: 0) }).last ?? 0, raqam: 1))")
                .font(.footnote).foregroundStyle(Rang.matn2)
            ForEach(h.holat.kamchiliklar, id: \.self) { Text("• " + $0).font(.footnote).foregroundStyle(Rang.skanSifat) }
            ForEach(h.baholar, id: \.tasdiq.id) { b in
                HStack(spacing: 8) {
                    Text(b.tasdiq.nomi).font(.subheadline.weight(.semibold)).foregroundStyle(Rang.matn)
                    Text(QuvurTasdiq.pikitaj(b.baho.stansiya)).font(.footnote.monospacedDigit()).foregroundStyle(Rang.matn2)
                    Spacer()
                    Text("\(Format.sm(b.baho.dGor)) / \(Format.sm(b.baho.dVer.map(abs)))").font(.footnote.monospacedDigit())
                        .foregroundStyle(b.baho.otdi ? Rang.rasmiy : Rang.past)
                    Button { ombor.tasdiqOchir(b.tasdiq.id, loyihaId: loyihaId) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(Rang.matn3).disabled(b.tasdiq.serverId != nil)
                }
            }
        }
        .padding(14)
        .background(Rang.sirt, in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous).strokeBorder(Rang.chiziq))
    }

    @MainActor private func yubor(_ l: Loyiha) async {
        guard let sid = l.serverId else { return }
        band = true
        defer { band = false }
        do {
            let m = try ServerMijoz(manzil: sozlama.serverManzil, token: sozlama.dalaToken)
            var soni = 0
            for var t in l.tasdiqlar where t.serverId == nil {
                t.serverId = try await m.tasdiqYubor(obyektId: sid, t)
                ombor.tasdiqSaqla(t, loyihaId: l.id)
                soni += 1
            }
            xabar = "\(soni) ta tasdiq serverga yuborildi."
        } catch {
            xabar = "Yuborilmadi: \(error.localizedDescription)"
        }
    }
}

/// TQ-01: vexa uchi quvur ustida — 5 s uzluksiz FIX o'rtachasi (kamida 5 epoxa), FIX uzilsa qaytadan. Natija darhol eng yaqin
/// o'qqa solishtiriladi (server bilan bir xil qoida).
struct TasdiqOlchashVaragi: View {
    let loyihaId: UUID
    @Environment(RTKBoshqaruv.self) private var rtk
    @Environment(LoyihaOmbori.self) private var ombor
    @Environment(Sozlamalar.self) private var sozlama
    @Environment(\.dismiss) private var yop
    @AppStorage("vexaBalandligiM") private var vexa = 1.80
    @State private var nomi = ""
    @State private var joy = "usti"
    @State private var namunalar: [Namuna] = []
    @State private var boshlandi: Date?
    @State private var oxirgiEpoxa: String?
    @State private var uzilish = 0
    @State private var natija: QuvurTasdigi?
    @State private var yuborish: String?
    @State private var soat = Date()

    struct Namuna { let lat: Double, lon: Double, h: Double }
    static let kerakS = QuvurTasdiq.minS
    static let minEpoxa = QuvurTasdiq.minEpoxa

    private var otgan: Double { boshlandi.map { soat.timeIntervalSince($0) } ?? 0 }

    var body: some View {
        Form {
            Section("Tasdiq") {
                TextField("Nomi (masalan T1, burilish)", text: $nomi).disabled(boshlandi != nil || natija != nil)
                Picker("Vexa uchi", selection: $joy) {
                    Text("quvur ustida").tag("usti")
                    Text("ochiq uchida, o'qda").tag("oq")
                }
                .disabled(boshlandi != nil || natija != nil)
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
                Text("Vexa uchidan antenna fazaviy markazigacha. Uchni quvurning eng yuqori nuqtasiga qo'ying, vexani tik tuting.")
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
                        Text(boshlandi == nil ? "Vexani quvur ustida tik tuting" : "\(Int(otgan)) / \(Int(Self.kerakS)) s · \(namunalar.count) epoxa")
                    }
                    if uzilish > 0 { Text("FIX \(uzilish) marta uzildi: o'rtachalash qaytadan boshlandi").font(.footnote).foregroundStyle(Rang.skanSifat) }
                    Button(boshlandi == nil ? "Boshlash" : "To'xtatish") {
                        if boshlandi == nil { namunalar = []; uzilish = 0; boshlandi = Date() } else { boshlandi = nil }
                    }
                    .disabled(!rtk.ulangan)
                }
            }
            if let t = natija { natijaBolimi(t) }
        }
        .navigationTitle("Quvur ustida o'lchash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(natija == nil ? "Bekor" : "Tayyor") { yop() } } }
        .task(id: boshlandi) { await yigish() }
        .sensoryFeedback(.success, trigger: natija?.id)
        .onAppear { if nomi.isEmpty { nomi = "T\((ombor.loyiha(loyihaId)?.tasdiqlar.count ?? 0) + 1)" } }
    }

    @ViewBuilder private func natijaBolimi(_ t: QuvurTasdigi) -> some View {
        let h = ombor.loyiha(loyihaId)?.tasdiqHolatlari().first { $0.baholar.contains { $0.tasdiq.id == t.id } }
        Section("Natija") {
            QiymatQatori(nomi: "Epoxalar", qiymat: "\(t.epoxalar) · \(Int(t.davomiylikS)) s")
            QiymatQatori(nomi: "Tarqoqlik σ", qiymat: "\(Format.son(t.sigmaHSm, raqam: 1)) / \(Format.son(t.sigmaVSm, raqam: 1)) sm")
            if let h, let b = h.baholar.first(where: { $0.tasdiq.id == t.id })?.baho {
                QiymatQatori(nomi: "O'q", qiymat: h.oq.nomi)
                QiymatQatori(nomi: "Pikitaj", qiymat: QuvurTasdiq.pikitaj(b.stansiya))
                QiymatQatori(nomi: "Og'ish gor. / vert.", qiymat: "\(Format.sm(b.dGor)) / \(Format.sm(b.dVer.map(abs)))")
                HolatChip(matn: b.otdi ? "Chegarada" : "CHEGARADAN TASHQARIDA: " + b.sabab, tur: b.otdi ? .ok : .xato,
                          belgi: b.otdi ? "checkmark.circle.fill" : "xmark.octagon.fill")
                HolatChip(matn: "Liniya: " + TasdiqKorinish.nom(h.holat.holat), tur: TasdiqKorinish.tur(h.holat.holat))
            } else {
                HolatChip(matn: "1 m ichida quvur o'qi topilmadi — tasdiq hech qaysi skanga tegishli emas", tur: .ogoh, belgi: "exclamationmark.triangle.fill")
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
                    boshlandi = Date()
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
        let t = QuvurTasdigi(nomi: nomi.trimmingCharacters(in: .whitespaces), lat: lat, lon: lon, h: h,
                             sigmaHSm: max(hypot(sN, sE) * 100, rtk.holat.sigmaHSm ?? 0),
                             sigmaVSm: max(sV * 100, rtk.holat.sigmaVSm ?? 0), epoxalar: namunalar.count,
                             davomiylikS: otgan, antennaM: vexa, joy: joy, vaqt: Date(), serverId: nil)
        // T-103: σ chegaradan oshsa tasdiq qabul qilinmaydi — server ham rad etadi
        guard t.sigmaHSm <= QuvurTasdiq.sigmaHSm, t.sigmaVSm <= QuvurTasdiq.sigmaVSm else {
            yuborish = "Tarqoqlik σ chegaradan katta (\(Format.son(t.sigmaHSm, raqam: 1)) / \(Format.son(t.sigmaVSm, raqam: 1)) sm): vexani tik tuting va qaytadan o'lchang."
            boshlandi = nil
            return
        }
        ombor.tasdiqSaqla(t, loyihaId: loyihaId)
        natija = t
        boshlandi = nil
        UIAccessibility.post(notification: .announcement, argument: "Tasdiq o'lchovi tayyor")
        guard let sid = ombor.loyiha(loyihaId)?.serverId else { yuborish = "Telefonda saqlandi, skan yuklanganda serverga ketadi."; return }
        Task { @MainActor in
            do {
                let m = try ServerMijoz(manzil: sozlama.serverManzil, token: sozlama.dalaToken)
                var y = t
                y.serverId = try await m.tasdiqYubor(obyektId: sid, t)
                ombor.tasdiqSaqla(y, loyihaId: loyihaId)
                yuborish = "Serverga yuborildi."
            } catch {
                yuborish = "Telefonda saqlandi, serverga keyin yuboriladi: \(error.localizedDescription)"
            }
        }
    }
}
