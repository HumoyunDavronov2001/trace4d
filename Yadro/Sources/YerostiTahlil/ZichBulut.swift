import Foundation
import YerostiGeometriya

// MARK: - DS-06/07: LiDAR chuqurlik kadrlaridan zich (rangli) bulut — telefonda jonli, serverda shu kod bilan sinaladi

/// Bitta chuqurlik kadri (ARKit `sceneDepth`): chuqurlik (m), ishonch (0 past, 1 o'rta, 2 yuqori), ixtiyoriy RGB
/// (kamera tasviridan shu piksellarga), ichki parametrlar CHUQURLIK o'lchamida (piksel markazi — butun indeks) va kamera
/// pozasi (ARKit: kamera → dunyo; kamera −z ga qaraydi, tasvir u o'ngga, v pastga).
public struct ChuqurlikKadri: Sendable {
    public var t: Double
    public var en: Int
    public var boy: Int
    public var chuqurlik: [Float]
    public var ishonch: [UInt8]?
    public var rang: [UInt8]?
    public var fx: Double, fy: Double, cx: Double, cy: Double
    public var kamera: PozaNamuna

    public init(t: Double, en: Int, boy: Int, chuqurlik: [Float], ishonch: [UInt8]? = nil, rang: [UInt8]? = nil,
                fx: Double, fy: Double, cx: Double, cy: Double, kamera: PozaNamuna) {
        self.t = t; self.en = en; self.boy = boy; self.chuqurlik = chuqurlik; self.ishonch = ishonch; self.rang = rang
        self.fx = fx; self.fy = fy; self.cx = cx; self.cy = cy; self.kamera = kamera
    }
}

public struct ZichBulutSozlamalari: Sendable {
    /// Voksel (m): quvur topish ham 1 sm to'rda ishlaydi.
    public var voksel = 0.01
    public var minChuqurlikM = 0.2
    /// iPhone LiDAR aniq qismi ~3 m gacha.
    public var maksChuqurlikM = 3.0
    /// ARConfidenceLevel: 1 — o'rta va yuqori.
    public var minIshonch: UInt8 = 1
    /// Vokselda kamida shuncha kuzatuv bo'lsa nuqta chiqadi (bir martalik «uchar piksel» tushadi).
    public var minKuzatuv = 2
    /// Siluet (aralash chuqurlik) pikseli: gorizontal yoki vertikal IKKINCHI farq |d₋ − 2d + d₊| > a + b·d bo'lsa olinmaydi.
    /// Qiya tekislikda ikkinchi farq ~0 (qiya devor saqlanadi), quvur cheti — keskin sinish (tushadi).
    public var siluetBoshM = 0.005
    public var siluetNisbat = 0.005
    /// Silliqlashga faqat chuqurligi |w − d| ≤ a + b·d bo'lgan qo'shnilar kiradi.
    public var silliqBoshM = 0.01
    public var silliqNisbat = 0.01
    /// 3×3 chegarani saqlovchi silliqlash (faqat chuqurligi yaqin qo'shnilar): mustaqil piksel shovqini ~3 marta kamayadi,
    /// 1,5 m da piksel izi ~7 mm — quvur kesimi deyarli buzilmaydi.
    public var silliqlash = true
    public init() {}
}

/// Voksel to'ri: har vokselda nuqtalar yig'indisi (voksel burchagidan siljish), rang va vaqt yig'indisi.
public struct ZichBulut: Sendable {
    struct Yig: Sendable {
        var sx: Float = 0, sy: Float = 0, sz: Float = 0, st: Float = 0
        var r: UInt32 = 0, g: UInt32 = 0, b: UInt32 = 0, n: UInt32 = 0
    }
    public let sozlama: ZichBulutSozlamalari
    private var tor: [Int64: Yig] = [:]
    private var tBosh: Double?
    public private(set) var kadrSoni = 0
    public private(set) var piksellar = 0
    private var rangli = true

    public init(_ s: ZichBulutSozlamalari = .init()) { sozlama = s }

    public var vokselSoni: Int { tor.count }

    static let yarim: Int64 = 1 << 20
    @inline(__always) static func kalit(_ i: Int64, _ j: Int64, _ k: Int64) -> Int64 {
        ((i + yarim) & 0x1F_FFFF) << 42 | ((j + yarim) & 0x1F_FFFF) << 21 | ((k + yarim) & 0x1F_FFFF)
    }
    @inline(__always) static func indeks(_ kalit: Int64) -> (Int64, Int64, Int64) {
        ((kalit >> 42) & 0x1F_FFFF - yarim, (kalit >> 21) & 0x1F_FFFF - yarim, kalit & 0x1F_FFFF - yarim)
    }

    /// Kadrni qo'shadi; qo'shilgan piksellar soni qaytadi.
    @discardableResult
    public mutating func qosh(_ k: ChuqurlikKadri) -> Int {
        guard k.en > 2, k.boy > 2, k.chuqurlik.count >= k.en * k.boy else { return 0 }
        if tBosh == nil { tBosh = k.t }
        if k.rang == nil { rangli = false }
        let s = sozlama, v = s.voksel
        let R = k.kamera.q.matritsa.m, P = k.kamera.p
        let dt = Float(k.t - (tBosh ?? k.t))
        var qoshildi = 0
        let d0 = k.chuqurlik, en = k.en
        // 1) yaroqli piksellar va (ixtiyoriy) chegarani saqlovchi 3×3 silliqlash
        var d = [Float](repeating: .nan, count: en * k.boy)
        for vv in 0..<k.boy {
            for uu in 0..<en {
                let i = vv * en + uu
                let z = d0[i]
                guard z.isFinite, Double(z) >= s.minChuqurlikM, Double(z) <= s.maksChuqurlikM else { continue }
                if let c = k.ishonch, c[i] < s.minIshonch { continue }
                guard s.silliqlash, vv > 0, uu > 0, vv < k.boy - 1, uu < en - 1 else { d[i] = z; continue }
                let chek = Float(s.silliqBoshM + s.silliqNisbat * Double(z))
                var yig: Float = 0, n: Float = 0
                for dv in -1...1 {
                    for du in -1...1 {
                        let w = d0[i + dv * en + du]
                        if w.isFinite, w > 0, abs(w - z) <= chek { yig += w; n += 1 }
                    }
                }
                d[i] = yig / n
            }
        }
        // 2) siluet testi silliq chuqurlikda, 3) dunyoga va vokselga
        for vv in 1..<(k.boy - 1) {
            for uu in 1..<(en - 1) {
                let i = vv * en + uu
                let z = d[i]
                guard z.isFinite else { continue }
                let sil = Float(s.siluetBoshM + s.siluetNisbat * Double(z))
                let gx = d[i - 1] + d[i + 1] - 2 * z, gy = d[i - en] + d[i + en] - 2 * z
                guard gx.isFinite, gy.isFinite, abs(gx) <= sil, abs(gy) <= sil else { continue }
                let zd = Double(z)
                let xc = (Double(uu) - k.cx) / k.fx * zd, yc = -(Double(vv) - k.cy) / k.fy * zd, zc = -zd
                let wx = R[0][0] * xc + R[0][1] * yc + R[0][2] * zc + P.x
                let wy = R[1][0] * xc + R[1][1] * yc + R[1][2] * zc + P.y
                let wz = R[2][0] * xc + R[2][1] * yc + R[2][2] * zc + P.z
                let ix = Int64((wx / v).rounded(.down)), iy = Int64((wy / v).rounded(.down)), iz = Int64((wz / v).rounded(.down))
                let key = ZichBulut.kalit(ix, iy, iz)
                var a = tor[key] ?? Yig()
                a.sx += Float(wx - Double(ix) * v); a.sy += Float(wy - Double(iy) * v); a.sz += Float(wz - Double(iz) * v)
                a.st += dt
                if let rg = k.rang {
                    a.r += UInt32(rg[3 * i]); a.g += UInt32(rg[3 * i + 1]); a.b += UInt32(rg[3 * i + 2])
                }
                a.n += 1
                tor[key] = a
                qoshildi += 1
            }
        }
        kadrSoni += 1
        piksellar += qoshildi
        return qoshildi
    }

    /// Voksel markazlari (kuzatuvlar o'rtachasi), o'rtacha rang va vaqt. Kalit bo'yicha tartiblangan — deterministik.
    public func nuqtalar() -> [BulutNuqtasi] {
        let v = sozlama.voksel, t0 = tBosh ?? 0
        var r: [BulutNuqtasi] = []
        r.reserveCapacity(tor.count)
        for key in tor.keys.sorted() {
            let a = tor[key]!
            guard a.n >= UInt32(sozlama.minKuzatuv) else { continue }
            let (i, j, k) = ZichBulut.indeks(key)
            let n = Float(a.n)
            let p = Vektor3(Double(i) * v + Double(a.sx / n), Double(j) * v + Double(a.sy / n), Double(k) * v + Double(a.sz / n))
            let rang = rangli ? Rang(UInt8(a.r / a.n), UInt8(a.g / a.n), UInt8(a.b / a.n)) : nil
            r.append(BulutNuqtasi(p, rang: rang, t: t0 + Double(a.st / n)))
        }
        return r
    }
}
