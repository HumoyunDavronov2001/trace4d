import Foundation

// MARK: - DS-03…DS-05: ARKit poza izi (xom yozuv) — telefon va server bir xil hisoblaydi

/// Birlik kvaternion [x, y, z, w] (ARKit `simd_quatf` bilan bir xil tartib).
public struct Kvaternion: Equatable, Sendable {
    public var x: Double, y: Double, z: Double, w: Double
    public init(_ x: Double, _ y: Double, _ z: Double, _ w: Double) { self.x = x; self.y = y; self.z = z; self.w = w }

    public static let birlik = Kvaternion(0, 0, 0, 1)

    /// O'q atrofida burilish (radian).
    public init(oq: Vektor3, burchak: Double) {
        let a = oq.birlik ?? Vektor3(0, 1, 0), s = sin(burchak / 2)
        self.init(a.x * s, a.y * s, a.z * s, cos(burchak / 2))
    }

    /// Burilish matritsasidan (Shepperd usuli).
    public init(_ m: Matritsa3) {
        let r = m.m, iz = r[0][0] + r[1][1] + r[2][2]
        if iz > 0 {
            let s = (iz + 1).squareRoot() * 2
            self.init((r[2][1] - r[1][2]) / s, (r[0][2] - r[2][0]) / s, (r[1][0] - r[0][1]) / s, s / 4)
        } else if r[0][0] > r[1][1] && r[0][0] > r[2][2] {
            let s = (1 + r[0][0] - r[1][1] - r[2][2]).squareRoot() * 2
            self.init(s / 4, (r[0][1] + r[1][0]) / s, (r[0][2] + r[2][0]) / s, (r[2][1] - r[1][2]) / s)
        } else if r[1][1] > r[2][2] {
            let s = (1 + r[1][1] - r[0][0] - r[2][2]).squareRoot() * 2
            self.init((r[0][1] + r[1][0]) / s, s / 4, (r[1][2] + r[2][1]) / s, (r[0][2] - r[2][0]) / s)
        } else {
            let s = (1 + r[2][2] - r[0][0] - r[1][1]).squareRoot() * 2
            self.init((r[0][2] + r[2][0]) / s, (r[1][2] + r[2][1]) / s, s / 4, (r[1][0] - r[0][1]) / s)
        }
        self = normallangan
    }

    public var normallangan: Kvaternion {
        let n = (x * x + y * y + z * z + w * w).squareRoot()
        return n > 0 ? Kvaternion(x / n, y / n, z / n, w / n) : .birlik
    }

    public static func * (a: Kvaternion, b: Kvaternion) -> Kvaternion {
        Kvaternion(a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
                   a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
                   a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
                   a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
    }

    public var matritsa: Matritsa3 {
        let q = normallangan
        let (x, y, z, w) = (q.x, q.y, q.z, q.w)
        return Matritsa3([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                          [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                          [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    }

    public func qolla(_ v: Vektor3) -> Vektor3 { matritsa.qolla(v) }

    /// Sferik chiziqli interpolyatsiya, u ∈ [0, 1]; qisqa yo'l tanlanadi.
    public static func slerp(_ a: Kvaternion, _ b0: Kvaternion, _ u: Double) -> Kvaternion {
        var b = b0
        var d = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
        if d < 0 { b = Kvaternion(-b.x, -b.y, -b.z, -b.w); d = -d }
        if d > 0.9995 {
            return Kvaternion(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u, a.w + (b.w - a.w) * u).normallangan
        }
        let th = acos(min(1, d)), s = sin(th)
        let ka = sin((1 - u) * th) / s, kb = sin(u * th) / s
        return Kvaternion(ka * a.x + kb * b.x, ka * a.y + kb * b.y, ka * a.z + kb * b.z, ka * a.w + kb * b.w)
    }
}

/// Bitta poza: ARKit kamerasi → dunyo (ARKit ramkasi, y yuqori). `t` — ARFrame.timestamp (uptime, s).
public struct PozaNamuna: Equatable, Sendable {
    public var t: Double
    public var p: Vektor3
    public var q: Kvaternion
    public init(t: Double, p: Vektor3, q: Kvaternion) { self.t = t; self.p = p; self.q = q }

    /// Kamera ramkasidagi nuqtani dunyoga.
    public func dunyoga(_ v: Vektor3) -> Vektor3 { q.qolla(v) + p }
}

/// Vaqt bo'yicha tartiblangan poza izi; oraliq vaqt — chiziqli (joy) va sferik (burilish) interpolyatsiya.
public struct PozaIzi: Sendable {
    public private(set) var namunalar: [PozaNamuna]

    public init(_ n: [PozaNamuna]) {
        var s = n.sorted { $0.t < $1.t }
        // bir xil vaqtli takrorlar olib tashlanadi
        var u: [PozaNamuna] = []
        u.reserveCapacity(s.count)
        for x in s where u.last.map({ x.t > $0.t }) ?? true { u.append(x) }
        s = u
        namunalar = s
    }

    public var bosh: Double? { namunalar.first?.t }
    public var oxir: Double? { namunalar.last?.t }
    public var yoq: Bool { namunalar.isEmpty }

    /// `t` vaqtidagi poza. Iz chegarasidan `chetS` dan ko'p tashqarida yoki namunalar orasidagi bo'shliq `boshliqS` dan
    /// katta bo'lsa — nil (ixtiyoriy taxmin qilinmaydi).
    public func poza(_ t: Double, chetS: Double = 0.05, boshliqS: Double = 0.5) -> PozaNamuna? {
        guard let a0 = namunalar.first, let aN = namunalar.last else { return nil }
        if t <= a0.t { return a0.t - t <= chetS ? PozaNamuna(t: t, p: a0.p, q: a0.q) : nil }
        if t >= aN.t { return t - aN.t <= chetS ? PozaNamuna(t: t, p: aN.p, q: aN.q) : nil }
        var lo = 0, hi = namunalar.count - 1
        while hi - lo > 1 { let o = (lo + hi) / 2; if namunalar[o].t <= t { lo = o } else { hi = o } }
        let a = namunalar[lo], b = namunalar[hi]
        guard b.t - a.t <= boshliqS else { return nil }
        let u = (t - a.t) / (b.t - a.t)
        return PozaNamuna(t: t, p: a.p + (b.p - a.p) * u, q: Kvaternion.slerp(a.q, b.q, u))
    }
}

/// DS-02: antenna fazaviy markazi kameraga nisbatan — telefon PORTRET ramkasida (x o'ng, y yuqori, z foydalanuvchiga), m.
/// ARKit kamera ramkasiga o'tish ilovadagi `GeorefYiguvchi` bilan bir xil: (x, y, z) = (−o_y, o_x, o_z).
public enum Antenna {
    public static func kamerada(_ o: [Double]) -> Vektor3 {
        guard o.count == 3 else { return .nol }
        return Vektor3(-o[1], o[0], o[2])
    }

    /// Antenna markazi ENU mahalliy ramkada (georeferens juftining `m` qismi).
    public static func enu(_ poza: PozaNamuna, ofset: [Double]) -> Vektor3 {
        ARKitRamka.enu(poza.dunyoga(kamerada(ofset)))
    }
}
