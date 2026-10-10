import MapKit
import SwiftUI
import YerostiDrayver
import YerostiGeometriya
import YerostiTahlil

/// SY-05: dala xaritasi — Apple sun'iy yo'ldosh surati (MapKit litsenziyasi ichida: Apple xaritasida ko'rsatiladi)
/// ustida loyiha quvurlari, nazorat punktlari va joriy RTK pozitsiya. Surat faqat kontekst va punktni dalada topish
/// uchun: uning o'zi bir necha metr xato bo'lishi mumkin, o'lchovlar suratga MOSLANMAYDI (TALABLAR 16).
struct XaritaEkrani: View {
    let loyihaId: UUID
    @Environment(LoyihaOmbori.self) private var ombor
    @Environment(RTKBoshqaruv.self) private var rtk
    @State private var kamera: MapCameraPosition = .automatic
    @State private var suniy = true
    @State private var tanlangan: String?

    var body: some View {
        if let l = ombor.loyiha(loyihaId) {
            let quvurlar = l.quvurlarWGS84()
            let punktlar = l.punktJoylari()
            let rang = TarmoqTuri.top(l.tarmoqTuri).rang
            let pos = rtkJoyi
            Map(position: $kamera, selection: $tanlangan) {
                ForEach(Array(quvurlar.enumerated()), id: \.offset) { _, q in
                    MapPolyline(coordinates: q)
                        .stroke(rang, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                ForEach(punktlar, id: \.nomi) { p in
                    Annotation(p.nomi, coordinate: p.joy, anchor: .center) {
                        PunktBelgisi(olchangan: p.olchangan, tanlangan: tanlangan == p.nomi)
                    }
                    .tag(p.nomi)
                }
                if let pos {
                    MapCircle(center: pos, radius: max((rtk.holat.sigmaHSm ?? 100) / 100, 0.05))
                        .foregroundStyle(Rang.fix.opacity(0.18))
                        .stroke(Rang.fix, lineWidth: 1)
                    Annotation("RTK", coordinate: pos, anchor: .center) {
                        Circle().fill(rtk.holat.rtk == .fix ? Rang.fix : Rang.float)
                            .frame(width: 16, height: 16).overlay(Circle().stroke(.white, lineWidth: 2.5))
                            .shadow(radius: 2)
                    }
                }
            }
            .mapStyle(suniy ? .hybrid(elevation: .flat) : .standard(elevation: .flat))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .safeAreaInset(edge: .bottom) { pastkiPanel(punktlar, pos) }
            .navigationTitle("Xarita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Asos", selection: $suniy) {
                        Text("Sun'iy yo'ldosh").tag(true)
                        Text("Sxema").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
            }
        }
    }

    private var rtkJoyi: CLLocationCoordinate2D? {
        guard rtk.ulangan, let la = rtk.holat.lat, let lo = rtk.holat.lon else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }

    private func pastkiPanel(_ punktlar: [PunktJoyi], _ pos: CLLocationCoordinate2D?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = tanlangan, let p = punktlar.first(where: { $0.nomi == t }) {
                if let pos {
                    let (d, az) = Xarita.masofa(pos, p.joy)
                    Text("\(p.nomi) gacha \(Format.son(d, raqam: d < 10 ? 2 : 1)) m · \(Xarita.yonalish(az))")
                        .font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Rang.matn)
                } else {
                    Text("\(p.nomi): RTK ulanmagan, masofa hisoblanmaydi").font(.headline).foregroundStyle(Rang.matn)
                }
                Text(p.olchangan ? "O'lchangan joyi (RTK o'rtachasi)" : "Lokalizatsiya bo'yicha bashorat: punkt shu atrofda")
                    .font(.footnote).foregroundStyle(Rang.matn2)
            } else {
                Text("Punktni tanlang: unga masofa va yo'nalish chiqadi").font(.subheadline.weight(.semibold))
                    .foregroundStyle(Rang.matn)
            }
            Text(suniy ? "Apple sun'iy yo'ldosh surati bir necha metr siljigan bo'lishi mumkin. Quvurlar va punktlar RTK bo'yicha chiziladi, suratga moslanmaydi."
                       : "Sxema: Apple xaritasi. Quvurlar va punktlar RTK bo'yicha.")
                .font(.caption).foregroundStyle(Rang.matn3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Olcham.radiusKarta, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}

/// O'lchangan punkt — to'la doira; lokalizatsiya bo'yicha bashorat — halqa.
struct PunktBelgisi: View {
    let olchangan: Bool
    let tanlangan: Bool
    var body: some View {
        let o: CGFloat = tanlangan ? 22 : 16
        ZStack {
            Circle().fill(olchangan ? Rang.tugma : Color.white.opacity(0.85)).frame(width: o, height: o)
            Circle().stroke(olchangan ? Color.white : Rang.tugma, lineWidth: 3).frame(width: o, height: o)
        }
        .shadow(radius: tanlangan ? 4 : 2)
    }
}

struct PunktJoyi {
    let nomi: String
    let joy: CLLocationCoordinate2D
    let olchangan: Bool
}

enum Xarita {
    /// Gorizontal masofa va azimut (WGS84 egrilik radiuslari; qisqa masofada mm aniq) — portal bilan bir xil formula.
    static func masofa(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> (Double, Double) {
        let R = 6378137.0, f = 1 / 298.257223563, e2 = f * (2 - f)
        let fi = (a.latitude + b.latitude) / 2 * .pi / 180
        let w = 1 - e2 * sin(fi) * sin(fi)
        let N = R / w.squareRoot(), M = R * (1 - e2) / pow(w, 1.5)
        let dx = (b.longitude - a.longitude) * .pi / 180 * N * cos(fi)
        let dy = (b.latitude - a.latitude) * .pi / 180 * M
        return (hypot(dx, dy), (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360))
    }

    static func yonalish(_ az: Double) -> String {
        let nomlar = ["shimol", "shimoli-sharq", "sharq", "janubi-sharq", "janub", "janubi-g'arb", "g'arb", "shimoli-g'arb"]
        return "\(nomlar[Int((az + 22.5) / 45) % 8]) \(Int(az.rounded()))°"
    }
}

extension Loyiha {
    /// SY-05: georeferensli skanlarning quvur o'qlari WGS84 da (yuklashdagi formula bilan bir xil).
    func quvurlarWGS84() -> [[CLLocationCoordinate2D]] {
        skanlar.flatMap { s -> [[CLLocationCoordinate2D]] in
            guard let g = s.georef else { return [] }
            let T = GorizontalTransformatsiya(burchak: g.burchak, t: Vektor3(g.t[0], g.t[1], g.t[2]))
            return s.quvurlar.map { q in
                q.oqMahalliy.map { p in
                    let u = T.qolla(ARKitRamka.enu(Vektor3(p[0], p[1], p[2])))
                    let (lat, lon) = UTM.dan(UTMNuqta(zona: g.utmZona, shimoliy: true, x: u.x, y: u.y))
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
            }
        }
    }

    /// Nazorat punktlari: o'lchanganlari — RTK o'lchovlari o'rtachasi; o'lchanmaganlari — lokalizatsiya bo'lsa uning
    /// teskari o'tishi bilan bashorat (monumentni dalada topish uchun).
    func punktJoylari() -> [PunktJoyi] {
        let lok = lokalizatsiya()
        return punktlar.compactMap { p in
            let o = olchovlar.filter { $0.punktNomi == p.nomi }
            if !o.isEmpty {
                let k = Double(o.count)
                return PunktJoyi(nomi: p.nomi, joy: CLLocationCoordinate2D(latitude: o.map(\.lat).reduce(0, +) / k,
                                                                         longitude: o.map(\.lon).reduce(0, +) / k),
                                 olchangan: true)
            }
            guard let lok, lok.parametrlar.gor != nil, let x = p.x, let y = p.y else { return nil }
            let t = Lokalizatsiya.teskari(lok.parametrlar, x: x, y: y, H: nil)
            return PunktJoyi(nomi: p.nomi, joy: CLLocationCoordinate2D(latitude: t.lat, longitude: t.lon), olchangan: false)
        }
    }
}
