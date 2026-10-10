import Foundation

/// 3 o'lchamli vektor (metr). ARKit ramkasida y — yuqori; UTM da (x=sharq, y=shimol, z=balandlik).
public struct Vektor3: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }

    public static let nol = Vektor3(0, 0, 0)

    @inlinable public static func + (a: Vektor3, b: Vektor3) -> Vektor3 { Vektor3(a.x + b.x, a.y + b.y, a.z + b.z) }
    @inlinable public static func - (a: Vektor3, b: Vektor3) -> Vektor3 { Vektor3(a.x - b.x, a.y - b.y, a.z - b.z) }
    @inlinable public static func * (a: Vektor3, k: Double) -> Vektor3 { Vektor3(a.x * k, a.y * k, a.z * k) }
    @inlinable public static func * (k: Double, a: Vektor3) -> Vektor3 { Vektor3(a.x * k, a.y * k, a.z * k) }
    @inlinable public static func / (a: Vektor3, k: Double) -> Vektor3 { Vektor3(a.x / k, a.y / k, a.z / k) }
    @inlinable public static prefix func - (a: Vektor3) -> Vektor3 { Vektor3(-a.x, -a.y, -a.z) }
    @inlinable public static func += (a: inout Vektor3, b: Vektor3) { a = a + b }

    @inlinable public func nuqta(_ b: Vektor3) -> Double { x * b.x + y * b.y + z * b.z }
    @inlinable public func kross(_ b: Vektor3) -> Vektor3 {
        Vektor3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x)
    }
    @inlinable public var uzunlik2: Double { x * x + y * y + z * z }
    @inlinable public var uzunlik: Double { uzunlik2.squareRoot() }
    /// Birlik vektor; nol vektor uchun nil.
    @inlinable public var birlik: Vektor3? {
        let u = uzunlik
        return u > 1e-12 ? self / u : nil
    }
    @inlinable public func masofa(_ b: Vektor3) -> Double { (self - b).uzunlik }

    /// Shu vektorga perpendikulyar ikki birlik vektor (o'ng qo'l bazisi).
    public func perpendikulyarBazis() -> (Vektor3, Vektor3) {
        let a = birlik ?? Vektor3(0, 0, 1)
        let yordam = abs(a.x) < 0.9 ? Vektor3(1, 0, 0) : Vektor3(0, 1, 0)
        let e1 = a.kross(yordam).birlik!
        let e2 = a.kross(e1)
        return (e1, e2)
    }
}

/// 3×3 matritsa (qator bo'yicha).
public struct Matritsa3: Equatable, Sendable {
    public var m: [[Double]]
    public init(_ m: [[Double]]) { self.m = m }
    public static let nol = Matritsa3([[0, 0, 0], [0, 0, 0], [0, 0, 0]])

    public func qolla(_ v: Vektor3) -> Vektor3 {
        Vektor3(m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
                m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
                m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z)
    }

    /// v·vᵀ ni qo'shish (kovariatsiya yig'ish uchun).
    public mutating func tashqiQosh(_ v: Vektor3, vazn: Double = 1) {
        let a = [v.x, v.y, v.z]
        for i in 0..<3 { for j in 0..<3 { m[i][j] += vazn * a[i] * a[j] } }
    }

    /// Simmetrik matritsaning xos qiymatlari (o'sish tartibida) va mos birlik xos vektorlari.
    public func xosTahlil() -> [(qiymat: Double, vektor: Vektor3)] {
        let (q, v) = SimmetrikJacobi.yech(m)
        return (0..<3).map { i in (q[i], Vektor3(v[0][i], v[1][i], v[2][i])) }
            .sorted { $0.qiymat < $1.qiymat }
    }
}

/// Kichik simmetrik matritsalar uchun siklik Jacobi xos qiymat usuli.
public enum SimmetrikJacobi {
    public static func yech(_ kirish: [[Double]]) -> (qiymatlar: [Double], vektorlar: [[Double]]) {
        var A = kirish
        let n = A.count
        var V = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n { V[i][i] = 1 }
        for _ in 0..<100 {
            var off = 0.0
            var diag = 0.0
            for i in 0..<n {
                diag += A[i][i] * A[i][i]
                for j in 0..<n where i != j { off += A[i][j] * A[i][j] }
            }
            if off <= 1e-26 * max(diag, 1e-300) || off < 1e-300 { break }
            for p in 0..<n {
                for q in (p + 1)..<n where abs(A[p][q]) > 1e-300 {
                    let teta = (A[q][q] - A[p][p]) / (2 * A[p][q])
                    let t = (teta >= 0 ? 1.0 : -1.0) / (abs(teta) + (teta * teta + 1).squareRoot())
                    let c = 1 / (t * t + 1).squareRoot(), s = t * c
                    for k in 0..<n {
                        let akp = A[k][p], akq = A[k][q]
                        A[k][p] = c * akp - s * akq
                        A[k][q] = s * akp + c * akq
                    }
                    for k in 0..<n {
                        let apk = A[p][k], aqk = A[q][k]
                        A[p][k] = c * apk - s * aqk
                        A[q][k] = s * apk + c * aqk
                    }
                    for k in 0..<n {
                        let vkp = V[k][p], vkq = V[k][q]
                        V[k][p] = c * vkp - s * vkq
                        V[k][q] = s * vkp + c * vkq
                    }
                }
            }
        }
        return ((0..<n).map { A[$0][$0] }, V)
    }
}

/// Aniqlangan (deterministik) tasodifiy sonlar — SplitMix64. Bir xil urug' → bir xil natija.
public struct Tasodifiy: RandomNumberGenerator, Sendable {
    private var holat: UInt64
    public init(urug: UInt64) { holat = urug }
    public mutating func next() -> UInt64 {
        holat &+= 0x9E3779B97F4A7C15
        var z = holat
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// [0, 1) oralig'ida.
    public mutating func birlik() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
    /// Normal taqsimot (Box–Muller).
    public mutating func normal(sigma: Double = 1) -> Double {
        let u1 = max(birlik(), 1e-300), u2 = birlik()
        return sigma * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
