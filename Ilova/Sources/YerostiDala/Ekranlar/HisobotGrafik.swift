import Charts
import SwiftUI
import YerostiGeometriya
import YerostiTahlil

/// UI-17: bo'ylama profil. ГОСТ Р 51872: ijro hujjatida quvur usti belgilari ko'rsatiladi.
/// Balandliklar mahalliy (ARKit y) yoki georeferens bo'lsa mutlaq ellipsoid H (`hOfset` = georeferens t.z).
struct BoylamaProfilKarta: View {
    let quvur: QuvurXulosa
    let raqam: Int
    let tarmoq: TarmoqTuri
    let hOfset: Double?

    private struct Nuqta: Identifiable {
        let id: String
        let s: Double
        let h: Double
        let qator: String
    }

    private struct Qator: Identifiable {
        let id: Int
        let s: Double
        let usti: Double
        let yer: Double?
    }

    var body: some View {
        if let oq = quvur.profilOq, oq.count >= 2 {
            let r = quvur.tashqiDiametrMm / 2000
            let d = hOfset ?? 0
            let yer = quvur.profilYer ?? []
            let profil = BoylamaProfil(oq: oq, yer: yer, radius: r)
            BolimKarta(sarlavha: "Bo'ylama profil: quvur \(raqam)", belgi: "chart.xyaxis.line") {
                Chart(nuqtalar(oq: oq, yer: yer, r: r, d: d)) { n in
                    LineMark(x: .value("Stansiya", n.s), y: .value("Balandlik", n.h))
                        .foregroundStyle(by: .value("Qator", n.qator))
                        .lineStyle(StrokeStyle(lineWidth: n.qator == "Quvur usti" ? 3 : 1.5,
                                               dash: n.qator == "Yer sirti" ? [5, 4] : []))
                }
                .chartForegroundStyleScale(["Quvur usti": tarmoq.rang, "Quvur osti": tarmoq.rang.opacity(0.45), "Yer sirti": Rang.skanSifat])
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxisLabel("Stansiya, m")
                .chartYAxisLabel(hOfset == nil ? "Balandlik (mahalliy), m" : "H (ellipsoid), m")
                .frame(height: 210)
                .accessibilityLabel("Bo'ylama profil: quvur usti, quvur osti va yer sirti stansiya bo'yicha")
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Stansiya").gridColumnAlignment(.leading)
                        Text("Quvur usti")
                        Text("Yer")
                        Text("Qoplama")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Rang.matn2)
                    Divider()
                    ForEach(qatorlar(profil: profil, d: d)) { q in
                        GridRow {
                            Text(Format.son(q.s, raqam: 1) + " m").gridColumnAlignment(.leading)
                            Text(Format.son(q.usti, raqam: 2))
                            Text(q.yer.map { Format.son($0, raqam: 2) } ?? "—")
                            Text(q.yer.map { Format.son($0 - q.usti, raqam: 2) } ?? "—")
                        }
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Rang.matn)
                    }
                }
                Text("Yer sirti skan bo'yicha taxmin (transheya chetidan). Belgilar RTK nazorat nuqtalari bilan tasdiqlanadi.")
                    .font(.caption)
                    .foregroundStyle(Rang.matn3)
            }
        }
    }

    private func nuqtalar(oq: [[Double]], yer: [[Double]], r: Double, d: Double) -> [Nuqta] {
        var n: [Nuqta] = []
        for (i, p) in oq.enumerated() where p.count == 2 {
            n.append(Nuqta(id: "u\(i)", s: p[0], h: p[1] + r + d, qator: "Quvur usti"))
            n.append(Nuqta(id: "o\(i)", s: p[0], h: p[1] - r + d, qator: "Quvur osti"))
        }
        for (i, p) in yer.enumerated() where p.count == 2 {
            n.append(Nuqta(id: "y\(i)", s: p[0], h: p[1] + d, qator: "Yer sirti"))
        }
        return n
    }

    /// Belgilar jadvali: yer o'lchangan stansiyalar (ko'pi bilan 12 ta, teng oraliqda); yer yo'q bo'lsa o'q cho'qqilari.
    private func qatorlar(profil: BoylamaProfil, d: Double) -> [Qator] {
        let manba: [(Double, Double?)] = profil.yer.isEmpty ? profil.oq.map { ($0[0], nil) } : profil.yer.map { ($0[0], $0[1]) }
        let qadam = max(1, Int((Double(manba.count) / 12).rounded(.up)))
        return stride(from: 0, to: manba.count, by: qadam).compactMap { i -> Qator? in
            let (s, yer) = manba[i]
            guard let usti = profil.quvurUsti(s) else { return nil }
            return Qator(id: i, s: s, usti: usti + d, yer: yer.map { $0 + d })
        }
    }
}

/// UI-18: reja — yuqoridan quvur o'qlari, shimol yo'nalishi va masshtab chizig'i.
/// Georeferens bo'lsa UTM to'r shimoliga buriladi; bo'lmasa mahalliy yo'nalish (shimol noma'lum deb yoziladi).
struct RejaKarta: View {
    let quvurlar: [QuvurXulosa]
    let tarmoq: TarmoqTuri
    let burchak: Double?

    var body: some View {
        let chiziqlar = quvurlar.map { q in q.oqMahalliy.compactMap(nuqta) }
        if chiziqlar.contains(where: { $0.count >= 2 }) {
            BolimKarta(sarlavha: "Reja", belgi: "map") {
                Canvas { ctx, size in chiz(ctx, size, chiziqlar) }
                    .frame(height: 220)
                    .background(Rang.sirt2, in: RoundedRectangle(cornerRadius: Olcham.radiusKichik, style: .continuous))
                    .accessibilityLabel("Reja: \(chiziqlar.count) ta quvur o'qi yuqoridan")
                Text(burchak == nil ? "Georeferens yo'q: yo'nalish mahalliy, shimol noma'lum" : "Yuqori tomon: UTM to'r shimoli")
                    .font(.caption)
                    .foregroundStyle(Rang.matn3)
            }
        }
    }

    /// ARKit (x, y, z) → ENU (sharq = x, shimol = −z); georeferens bo'lsa UTM yo'nalishiga burish.
    private func nuqta(_ p: [Double]) -> CGPoint? {
        guard p.count == 3 else { return nil }
        let e = p[0], n = -p[2]
        guard let b = burchak else { return CGPoint(x: e, y: n) }
        return CGPoint(x: cos(b) * e - sin(b) * n, y: sin(b) * e + cos(b) * n)
    }

    private func chiz(_ ctx: GraphicsContext, _ size: CGSize, _ chiziqlar: [[CGPoint]]) {
        let hammasi = chiziqlar.flatMap { $0 }
        guard let mnx = hammasi.map(\.x).min(), let mxx = hammasi.map(\.x).max(),
              let mny = hammasi.map(\.y).min(), let mxy = hammasi.map(\.y).max() else { return }
        let chet: CGFloat = 30
        let dx = max(mxx - mnx, 1), dy = max(mxy - mny, 1)
        let s = min((size.width - 2 * chet) / dx, (size.height - 2 * chet) / dy)
        let ox = (size.width - dx * s) / 2 - mnx * s
        let oy = (size.height + dy * s) / 2 + mny * s
        let ekran = { (p: CGPoint) in CGPoint(x: ox + p.x * s, y: oy - p.y * s) }
        for (i, c) in chiziqlar.enumerated() where c.count >= 2 {
            var yol = Path()
            yol.addLines(c.map(ekran))
            ctx.stroke(yol, with: .color(tarmoq.rang), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            let bosh = ekran(c[0])
            ctx.fill(Path(ellipseIn: CGRect(x: bosh.x - 5, y: bosh.y - 5, width: 10, height: 10)), with: .color(Rang.matn))
            ctx.draw(Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(Rang.matn), at: CGPoint(x: bosh.x + 12, y: bosh.y - 10))
        }
        // shimol belgisi (yuqori o'ng)
        let n = CGPoint(x: size.width - 22, y: 26)
        var strelka = Path()
        strelka.move(to: CGPoint(x: n.x, y: n.y - 12))
        strelka.addLine(to: CGPoint(x: n.x - 7, y: n.y + 8))
        strelka.addLine(to: CGPoint(x: n.x, y: n.y + 3))
        strelka.addLine(to: CGPoint(x: n.x + 7, y: n.y + 8))
        strelka.closeSubpath()
        ctx.fill(strelka, with: .color(burchak == nil ? Rang.matn3 : Rang.urgu))
        ctx.draw(Text("N").font(.caption2.weight(.bold)).foregroundStyle(Rang.matn2), at: CGPoint(x: n.x, y: n.y + 18))
        // masshtab chizig'i (pastki chap): kenglikning ~30 % idan oshmaydigan "yaxlit" uzunlik
        let uzunlik = [0.5, 1, 2, 5, 10, 20, 50, 100].last { $0 * s <= size.width * 0.3 } ?? 0.5
        let a = CGPoint(x: 14, y: size.height - 16), b = CGPoint(x: 14 + uzunlik * s, y: size.height - 16)
        var chiziq = Path()
        chiziq.move(to: a)
        chiziq.addLine(to: b)
        chiziq.move(to: CGPoint(x: a.x, y: a.y - 5))
        chiziq.addLine(to: CGPoint(x: a.x, y: a.y + 5))
        chiziq.move(to: CGPoint(x: b.x, y: b.y - 5))
        chiziq.addLine(to: CGPoint(x: b.x, y: b.y + 5))
        ctx.stroke(chiziq, with: .color(Rang.matn), lineWidth: 2)
        ctx.draw(Text(Format.son(uzunlik, raqam: uzunlik < 1 ? 1 : 0) + " m").font(.caption2.weight(.semibold)).foregroundStyle(Rang.matn),
                 at: CGPoint(x: (a.x + b.x) / 2, y: a.y - 10))
    }
}
