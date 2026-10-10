import Foundation
import YerostiGeometriya
import YerostiTahlil

/// FAQAT SINOV UCHUN: transheya + quvur sahnasini LiDAR chuqurlik kamerasi kabi «suratga olish» (nur kesishuvi).
/// ARKit ramkasi: y yuqori; transheya x bo'ylab, markazi z = 0; yer y = 0; tub y = −chuqurlik.
public struct TransheyaSahnasi: Sendable {
    public var kenglik = 0.8
    public var chuqurlik = 1.2
    public var quvurRadius = 0.0315          // Ø63
    public var quvurZ = 0.0
    public var uzunlik = 6.0
    public var shovqinBosh = 0.004           // σ = a + b·d (m)
    public var shovqinNisbat = 0.004
    public init() {}

    public static let yerRang = Rang(120, 92, 60), devorRang = Rang(150, 112, 80), tubRang = Rang(92, 70, 52), quvurRang = Rang(40, 90, 200)

    public var quvurMarkazY: Double { -chuqurlik + quvurRadius }

    /// Nur kesishuvi: eng yaqin sirt masofasi (nur yo'nalishi bo'yicha parametr) va rangi.
    func kesish(_ o: Vektor3, _ d: Vektor3) -> (t: Double, rang: Rang)? {
        var eng: (t: Double, rang: Rang)?
        func ol(_ t: Double, _ r: Rang) { if t > 1e-6, t < (eng?.t ?? .infinity) { eng = (t, r) } }
        let w = kenglik / 2
        // yer (transheyadan tashqari)
        if abs(d.y) > 1e-12 {
            let t = -o.y / d.y, p = o + d * t
            if abs(p.z) > w { ol(t, Self.yerRang) }
            let tb = (-chuqurlik - o.y) / d.y, pb = o + d * tb
            if abs(pb.z) <= w { ol(tb, Self.tubRang) }
        }
        // devorlar
        if abs(d.z) > 1e-12 {
            for zz in [-w, w] {
                let t = (zz - o.z) / d.z, p = o + d * t
                if p.y <= 0, p.y >= -chuqurlik { ol(t, Self.devorRang) }
            }
        }
        // quvur (x o'qi bo'ylab silindr)
        let yc = quvurMarkazY, r = quvurRadius
        let a = d.y * d.y + d.z * d.z
        if a > 1e-12 {
            let oy = o.y - yc, oz = o.z - quvurZ
            let b = 2 * (oy * d.y + oz * d.z), c = oy * oy + oz * oz - r * r
            let D = b * b - 4 * a * c
            if D >= 0 {
                let t = (-b - D.squareRoot()) / (2 * a), p = o + d * t
                if p.x >= 0, p.x <= uzunlik { ol(t, Self.quvurRang) }
            }
        }
        return eng
    }

    /// Kamera pozasidan chuqurlik kadri (256×192, iPhone LiDAR o'lchami).
    public func kadr(_ kamera: PozaNamuna, t: Double, urug: UInt64, en: Int = 256, boy: Int = 192,
                     fx: Double = 211, fy: Double = 211) -> ChuqurlikKadri {
        let cx = Double(en - 1) / 2, cy = Double(boy - 1) / 2
        var rnd = Tasodifiy(urug: urug)
        var dm = [Float](repeating: 0, count: en * boy)
        var ish = [UInt8](repeating: 0, count: en * boy)
        var rg = [UInt8](repeating: 0, count: en * boy * 3)
        let R = kamera.q.matritsa
        for v in 0..<boy {
            for u in 0..<en {
                let dc = Vektor3((Double(u) - cx) / fx, -(Double(v) - cy) / fy, -1)
                let dw = R.qolla(dc)
                guard let k = kesish(kamera.p, dw) else { continue }
                let z = k.t + rnd.normal(sigma: shovqinBosh + shovqinNisbat * k.t)
                let i = v * en + u
                dm[i] = Float(z)
                ish[i] = 2
                rg[3 * i] = k.rang.r; rg[3 * i + 1] = k.rang.g; rg[3 * i + 2] = k.rang.b
            }
        }
        return ChuqurlikKadri(t: t, en: en, boy: boy, chuqurlik: dm, ishonch: ish, rang: rg, fx: fx, fy: fy, cx: cx, cy: cy,
                              kamera: kamera)
    }

    /// Transheya bo'ylab yurish: kamera yer sathidan `balandlik` yuqorida, chetda (z = +0,3), pastga qaraydi.
    public func yurish(kadrlar n: Int = 75, balandlik: Double = 0.3, t0: Double = 1000) -> [ChuqurlikKadri] {
        (0..<n).map { k in
            let u = Double(k) / Double(max(n - 1, 1))
            let x = -0.3 + (uzunlik + 0.6) * u
            let q = Kvaternion(oq: Vektor3(1, 0, 0), burchak: -75 * .pi / 180) * Kvaternion(oq: Vektor3(0, 0, 1), burchak: 0.05 * sin(Double(k)))
            let p = PozaNamuna(t: t0 + Double(k) * 0.2, p: Vektor3(x, balandlik, 0.3), q: q)
            return kadr(p, t: t0 + Double(k) * 0.2, urug: UInt64(k + 1))
        }
    }
}
