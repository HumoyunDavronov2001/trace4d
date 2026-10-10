import Foundation

/// T-031 / TQ (TALABLAR 18): quvur tasdig'i — vexa uchi quvur ustida turganda RTK FIX o'lchovining skan o'qidan og'ishi va
/// liniya tasdiq holati. Qoida server `yerosti_tasdiq.py` bilan BIR XIL: brigada natijani joyida ko'radi, server qayta hisoblaydi.
public enum QuvurTasdiq {
    public static let gorM = 0.05          // RSS(T-103 σH 2 sm, georef RMS 3 sm) × 1,4
    public static let verM = 0.08          // RSS(σV 5 sm, 3 sm) × 1,4
    public static let yaqinM = 1.0         // tasdiq liniyaga shu masofada bo'lsa unga tegishli
    public static let uchM = 1.0           // boshi / oxiri / burilish shu radiusda tasdiqlansin
    public static let oraliqM = 50.0       // ГОСТ Р 51872 G.1.1
    public static let sigmaHSm = 2.0, sigmaVSm = 5.0, tuzatmaS = 10.0   // T-103
    public static let minS = 5.0, minEpoxa = 5

    public struct Nuqta: Sendable, Equatable {
        public var e: Double, n: Double, h: Double?
        public init(e: Double, n: Double, h: Double? = nil) { self.e = e; self.n = n; self.h = h }
    }

    public struct Baho: Sendable, Equatable {
        public var stansiya: Double
        public var dGor: Double
        public var dVer: Double?
        public var otdi: Bool
        public var sabab: String
    }

    public struct Holat: Sendable, Equatable {
        public var holat: String          // tasdiqlangan | qisman | farq | yoq | rtk
        public var kamchiliklar: [String]
        public var soni: Int
        public var otgan: Int
    }

    /// Mahalliy tekis koordinata (server `enu` bilan bir xil formula).
    public static func enu(lat0: Double, lon0: Double) -> (Double, Double) -> Nuqta {
        let fi = lat0 * .pi / 180
        let mLat = 111_132.954 - 559.822 * cos(2 * fi) + 1.175 * cos(4 * fi)
        let mLon = 111_412.84 * cos(fi) - 93.5 * cos(3 * fi)
        return { lat, lon in Nuqta(e: (lon - lon0) * mLon, n: (lat - lat0) * mLat) }
    }

    public static func stansiyalar(_ P: [Nuqta]) -> [Double] {
        var s = [0.0]
        for i in 1..<max(P.count, 1) { s.append(s[i - 1] + hypot(P[i].e - P[i - 1].e, P[i].n - P[i - 1].n)) }
        return s
    }

    /// Nuqtaning polilinya ustidagi eng yaqin joyi: (stansiya, gorizontal masofa, o'q balandligi).
    public static func proyeksiya(_ P: [Nuqta], _ s: [Double], e: Double, n: Double) -> (Double, Double, Double?)? {
        guard P.count >= 2 else { return nil }
        var eng: (Double, Double, Double?)?
        for i in 0..<(P.count - 1) {
            let a = P[i], b = P[i + 1]
            let dx = b.e - a.e, dy = b.n - a.n, L2 = dx * dx + dy * dy
            let t = L2 <= 0 ? 0 : min(1, max(0, ((e - a.e) * dx + (n - a.n) * dy) / L2))
            let d = hypot(e - (a.e + dx * t), n - (a.n + dy * t))
            if eng == nil || d < eng!.1 {
                var h: Double?
                if let ha = a.h, let hb = b.h { h = ha + (hb - ha) * t }
                eng = (s[i] + L2.squareRoot() * t, d, h)
            }
        }
        return eng
    }

    /// TQ-02: tasdiqning o'qdan og'ishi. `usti` — vexa uchi quvur ustida (o'q + radius), aks holda o'qda.
    public static func baholash(oq: [Nuqta], radiusM: Double, nuqta: Nuqta, usti: Bool = true) -> Baho? {
        guard let (st, d, h) = proyeksiya(oq, stansiyalar(oq), e: nuqta.e, n: nuqta.n) else { return nil }
        var dv: Double?
        if let h, let th = nuqta.h { dv = th - (usti ? h + radiusM : h) }
        var xato: [String] = [], izoh: [String] = []
        if d > gorM { xato.append(String(format: "gorizontal %.1f sm > %.0f sm", d * 100, gorM * 100)) }
        if let dv, abs(dv) > verM { xato.append(String(format: "vertikal %+.1f sm, chegara ±%.0f sm", dv * 100, verM * 100)) }
        if dv == nil { izoh.append("balandlik solishtirilmadi") }
        return Baho(stansiya: st, dGor: d, dVer: dv, otdi: xato.isEmpty, sabab: (xato + izoh).joined(separator: "; "))
    }

    /// Burilish stansiyalari (≥ 3°, 2 m bazada; zich nuqtalarda bir egilish bitta nuqta): server `_turlar` soddalashgan.
    public static func burilishlar(_ P: [Nuqta], bazaM: Double = 2.0, gradChek: Double = 3.0) -> [Double] {
        guard P.count >= 3 else { return [] }
        let s = stansiyalar(P)
        var nomzod: [(Double, Int)] = []
        for i in 1..<(P.count - 1) {
            var ja = i - 1
            while ja > 0, s[i] - s[ja] < bazaM { ja -= 1 }
            var jb = i + 1
            while jb < P.count - 1, s[jb] - s[i] < bazaM { jb += 1 }
            let zich = (s[i] - s[i - 1] < 1.0) || (s[i + 1] - s[i] < 1.0)
            if zich, s[i] - s[ja] < bazaM || s[jb] - s[i] < bazaM { continue }
            let a1 = atan2(P[i].e - P[ja].e, P[i].n - P[ja].n), a2 = atan2(P[jb].e - P[i].e, P[jb].n - P[i].n)
            var f = (a2 - a1).truncatingRemainder(dividingBy: 2 * .pi)
            if f > .pi { f -= 2 * .pi } else if f < -.pi { f += 2 * .pi }
            let grad = abs(f) * 180 / .pi
            if grad >= gradChek { nomzod.append((grad, i)) }
        }
        var qabul: [Int] = []
        for (_, i) in nomzod.sorted(by: { $0.0 > $1.0 }) where qabul.allSatisfy({ abs(s[i] - s[$0]) >= bazaM }) { qabul.append(i) }
        return qabul.map { s[$0] }.sorted()
    }

    /// TQ-05: liniya holati. `skan` — liniyada skan nuqtalari bor (tasdiq shart).
    public static func holat(oq: [Nuqta], baholar: [Baho], skan: Bool = true) -> Holat {
        let farq = baholar.filter { !$0.otdi }
        if baholar.isEmpty { return Holat(holat: skan ? "yoq" : "rtk", kamchiliklar: skan ? ["tasdiq o'lchovi yo'q"] : [], soni: 0, otgan: 0) }
        if !farq.isEmpty {
            return Holat(holat: "farq", kamchiliklar: ["\(farq.count) ta tasdiq chegaradan tashqarida: skan georeferensi yoki tasdiq joyi shubhali"],
                         soni: baholar.count, otgan: baholar.count - farq.count)
        }
        let st = baholar.map(\.stansiya).sorted()
        let s = stansiyalar(oq)
        var kerak: [(String, Double)] = [("boshlanish", 0), ("oxiri", s.last ?? 0)]
        kerak += burilishlar(oq).map { ("burilish", $0) }
        var kam: [String] = []
        for (nomi, k) in kerak where (st.map { abs($0 - k) }.min() ?? .infinity) > uchM {
            kam.append("\(nomi) (\(pikitaj(k))) \(Int(uchM)) m ichida tasdiqlanmagan")
        }
        for i in 1..<st.count where st[i] - st[i - 1] > oraliqM + 1e-9 {
            kam.append("\(pikitaj(st[i - 1])) – \(pikitaj(st[i])) oralig'i \(Int((st[i] - st[i - 1]).rounded())) m > \(Int(oraliqM)) m")
        }
        return Holat(holat: kam.isEmpty ? "tasdiqlangan" : "qisman", kamchiliklar: kam, soni: baholar.count, otgan: baholar.count)
    }

    public static func pikitaj(_ s: Double) -> String {
        let r = (s * 100).rounded() / 100
        let pk = Int(r / 100)
        return String(format: "PK%d+%05.2f", pk, max(0, r - Double(pk) * 100)).replacingOccurrences(of: ".", with: ",")
    }
}
