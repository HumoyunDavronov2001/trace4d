import Foundation

/// Qattiq (masshtabsiz) transformatsiya: global = R·mahalliy + t.
public struct QattiqTransformatsiya: Equatable, Sendable {
    public let R: [[Double]]
    public let t: Vektor3
    public init(R: [[Double]], t: Vektor3) { self.R = R; self.t = t }
    public func qolla(_ p: Vektor3) -> Vektor3 { Matritsa3(R).qolla(p) + t }
}

public struct GeoreferensNatija: Equatable, Sendable {
    public let transformatsiya: QattiqTransformatsiya
    public let qoldiqlarM: [Double]
    public let rmsM: Double
    public let maksQoldiqM: Double
}

public enum GeoreferensXato: Error, Equatable {
    case nuqtaYetarliEmas
    case nuqtalarBirChiziqda
    case sonlarMosEmas
}

/// T-063: ARKit mahalliy ramkasi → UTM. ≥3 marker, Horn (1987) kvaternion usuli.
public enum Georeferens {
    public static let rmsChekM = 0.03  // 3 sm dan katta bo'lsa skan "past aniqlik"

    public static func hisobla(mahalliy p: [Vektor3], global q: [Vektor3]) throws -> GeoreferensNatija {
        guard p.count == q.count else { throw GeoreferensXato.sonlarMosEmas }
        guard p.count >= 3 else { throw GeoreferensXato.nuqtaYetarliEmas }
        let n = Double(p.count)
        let pc = p.reduce(Vektor3.nol, +) / n, qc = q.reduce(Vektor3.nol, +) / n
        let pp = p.map { $0 - pc }, qq = q.map { $0 - qc }

        let masshtab = pp.map { $0.uzunlik }.max() ?? 0
        var maksKross = 0.0
        for i in 0..<pp.count { for j in (i + 1)..<pp.count { maksKross = max(maksKross, pp[i].kross(pp[j]).uzunlik) } }
        guard masshtab > 0, maksKross > 1e-9 * masshtab * masshtab else { throw GeoreferensXato.nuqtalarBirChiziqda }

        var S = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for k in 0..<pp.count {
            let a = [pp[k].x, pp[k].y, pp[k].z], b = [qq[k].x, qq[k].y, qq[k].z]
            for i in 0..<3 { for j in 0..<3 { S[i][j] += a[i] * b[j] } }
        }
        let N: [[Double]] = [
            [S[0][0] + S[1][1] + S[2][2], S[1][2] - S[2][1], S[2][0] - S[0][2], S[0][1] - S[1][0]],
            [S[1][2] - S[2][1], S[0][0] - S[1][1] - S[2][2], S[0][1] + S[1][0], S[2][0] + S[0][2]],
            [S[2][0] - S[0][2], S[0][1] + S[1][0], -S[0][0] + S[1][1] - S[2][2], S[1][2] + S[2][1]],
            [S[0][1] - S[1][0], S[2][0] + S[0][2], S[1][2] + S[2][1], -S[0][0] - S[1][1] + S[2][2]],
        ]
        let (qiymatlar, vektorlar) = SimmetrikJacobi.yech(N)
        var eng = 0
        for i in 1..<4 where qiymatlar[i] > qiymatlar[eng] { eng = i }
        let q0 = vektorlar[0][eng], qx = vektorlar[1][eng], qy = vektorlar[2][eng], qz = vektorlar[3][eng]
        let R: [[Double]] = [
            [q0 * q0 + qx * qx - qy * qy - qz * qz, 2 * (qx * qy - q0 * qz), 2 * (qx * qz + q0 * qy)],
            [2 * (qy * qx + q0 * qz), q0 * q0 - qx * qx + qy * qy - qz * qz, 2 * (qy * qz - q0 * qx)],
            [2 * (qz * qx - q0 * qy), 2 * (qz * qy + q0 * qx), q0 * q0 - qx * qx - qy * qy + qz * qz],
        ]
        let T = QattiqTransformatsiya(R: R, t: qc - Matritsa3(R).qolla(pc))
        let qoldiqlar = zip(p, q).map { (T.qolla($0) - $1).uzunlik }
        let rms = (qoldiqlar.reduce(0) { $0 + $1 * $1 } / n).squareRoot()
        return GeoreferensNatija(transformatsiya: T, qoldiqlarM: qoldiqlar, rmsM: rms,
                                 maksQoldiqM: qoldiqlar.max() ?? 0)
    }
}

// MARK: - Gravitatsiya bilan bog'lash (4 erkinlik darajasi): RTK traektoriyasidan avtomatik georeferens

/// ARKit dunyo ramkasi (worldAlignment = .gravity): x — o'ng, y — yuqori, z — orqaga.
/// ENU ko'rinishiga o'tkazish: (sharq≈x, shimol≈−z, yuqori=y). Gorizontal burilish keyin topiladi.
public enum ARKitRamka {
    public static func enu(_ p: Vektor3) -> Vektor3 { Vektor3(p.x, -p.z, p.y) }
    public static func arkit(_ e: Vektor3) -> Vektor3 { Vektor3(e.x, e.z, -e.y) }
}

/// Mahalliy ENU → global (UTM sharq, shimol, balandlik): faqat vertikal o'q atrofida burilish + siljish.
public struct GorizontalTransformatsiya: Equatable, Sendable {
    public let burchak: Double
    public let t: Vektor3
    public init(burchak: Double, t: Vektor3) { self.burchak = burchak; self.t = t }
    public func qolla(_ p: Vektor3) -> Vektor3 {
        let c = cos(burchak), s = sin(burchak)
        return Vektor3(c * p.x - s * p.y + t.x, s * p.x + c * p.y + t.y, p.z + t.z)
    }
    public func teskari(_ g: Vektor3) -> Vektor3 {
        let c = cos(burchak), s = sin(burchak)
        let x = g.x - t.x, y = g.y - t.y
        return Vektor3(c * x + s * y, -s * x + c * y, g.z - t.z)
    }
}

public struct GorizontalNatija: Equatable, Sendable {
    public let transformatsiya: GorizontalTransformatsiya
    public let gorizontalRmsM: Double
    public let vertikalRmsM: Double
    public let maksQoldiqM: Double
    public let soni: Int
}

public enum GravitatsiyaXato: Error, Equatable {
    case nuqtaYetarliEmas
    case sonlarMosEmas
    case yoyilishYetarliEmas
}

extension Georeferens {
    /// ARKit trayektoriyasi (ENU ga o'tkazilgan) va RTK pozitsiyalari (UTM) juftlaridan burilish+siljish.
    /// Gravitatsiya ikkala ramkada ma'lum bo'lgani uchun to'g'ri chiziq bo'ylab yurish ham yetarli.
    public static func gravitatsiyaBilan(mahalliyENU p: [Vektor3], global q: [Vektor3], minYoyilishM: Double = 1.0)
        throws -> GorizontalNatija {
        guard p.count == q.count else { throw GravitatsiyaXato.sonlarMosEmas }
        guard p.count >= 3 else { throw GravitatsiyaXato.nuqtaYetarliEmas }
        let n = Double(p.count)
        let pc = p.reduce(Vektor3.nol, +) / n, qc = q.reduce(Vektor3.nol, +) / n
        var S = 0.0, C = 0.0, yoyilish = 0.0
        for i in 0..<p.count {
            let ux = p[i].x - pc.x, uy = p[i].y - pc.y
            let vx = q[i].x - qc.x, vy = q[i].y - qc.y
            S += ux * vy - uy * vx
            C += ux * vx + uy * vy
            yoyilish = max(yoyilish, (ux * ux + uy * uy).squareRoot())
        }
        guard yoyilish >= minYoyilishM / 2 else { throw GravitatsiyaXato.yoyilishYetarliEmas }
        let teta = atan2(S, C)
        let c = cos(teta), s = sin(teta)
        let t = Vektor3(qc.x - (c * pc.x - s * pc.y), qc.y - (s * pc.x + c * pc.y), qc.z - pc.z)
        let T = GorizontalTransformatsiya(burchak: teta, t: t)
        var h2 = 0.0, v2 = 0.0, maks = 0.0
        for i in 0..<p.count {
            let d = T.qolla(p[i]) - q[i]
            h2 += d.x * d.x + d.y * d.y
            v2 += d.z * d.z
            maks = max(maks, d.uzunlik)
        }
        return GorizontalNatija(transformatsiya: T, gorizontalRmsM: (h2 / n).squareRoot(), vertikalRmsM: (v2 / n).squareRoot(),
                                maksQoldiqM: maks, soni: p.count)
    }
}
