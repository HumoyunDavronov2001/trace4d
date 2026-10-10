import Foundation
import YerostiGeometriya

/// Serverdagi tarmoq (`GET /api/v1/atrof`). `balandlik` — quvur O'QI (markazi) ellipsoid balandligi (AR-08).
public struct GlobalTarmoq: Codable, Equatable, Sendable {
    public struct Nuqta: Codable, Equatable, Sendable {
        public var lat: Double
        public var lon: Double
        public var balandlik: Double?
        public var chuqurlik_m: Double?
        public init(lat: Double, lon: Double, balandlik: Double? = nil, chuqurlik_m: Double? = nil) {
            self.lat = lat; self.lon = lon; self.balandlik = balandlik; self.chuqurlik_m = chuqurlik_m
        }
    }
    public var id: Int
    public var turi: String
    public var diametr_mm: Int
    public var material: String
    public var sifat: String
    public var pudratchi: String?
    /// UI-13: liniyaning eng katta gorizontal σ (sm); eski serverda yo'q bo'lishi mumkin.
    public var sigma_h_sm: Double?
    public var nuqtalar: [Nuqta]
    public init(id: Int, turi: String, diametr_mm: Int, material: String = "", sifat: String, pudratchi: String? = nil,
                sigma_h_sm: Double? = nil, nuqtalar: [Nuqta]) {
        self.id = id; self.turi = turi; self.diametr_mm = diametr_mm; self.material = material; self.sifat = sifat
        self.pudratchi = pudratchi; self.sigma_h_sm = sigma_h_sm; self.nuqtalar = nuqtalar
    }
}

/// AR sahnasidagi tarmoq — ARKit mahalliy ramkasida (y — yuqori).
public struct MahalliyTarmoq: Equatable, Sendable {
    public var id: Int
    public var turi: String
    public var diametrMm: Int
    public var radius: Double
    public var sifat: String
    public var oq: [Vektor3]
    public var sigmaHSm: Double? = nil
}

public enum ARJoylashuv {
    /// Global (lat, lon, ellipsoid balandligi) → ARKit mahalliy. `georef`: mahalliy ENU → UTM (E, N, H).
    public static func mahalliy(lat: Double, lon: Double, h: Double, georef: GorizontalTransformatsiya, zona: Int) -> Vektor3 {
        let u = UTM.ga(lat: lat, lon: lon, zona: zona)
        return ARKitRamka.arkit(georef.teskari(Vektor3(u.x, u.y, h)))
    }

    /// ARKit mahalliy → global (lat, lon, h).
    public static func global(_ p: Vektor3, georef: GorizontalTransformatsiya, zona: Int) -> (lat: Double, lon: Double, h: Double) {
        let g = georef.qolla(ARKitRamka.enu(p))
        let (lat, lon) = UTM.dan(UTMNuqta(zona: zona, shimoliy: true, x: g.x, y: g.y))
        return (lat, lon, g.z)
    }

    /// Tarmoqni AR ramkasiga o'tkazish. Balandligi yo'q nuqta: yer sirti (x, z) − chuqurlik − r;
    /// yer sirti ham noma'lum bo'lsa — nuqta tashlanadi. 2 dan kam nuqta qolsa — nil.
    public static func tarmoq(_ g: GlobalTarmoq, georef: GorizontalTransformatsiya, zona: Int,
                              yerBalandligi: (Double, Double) -> Double?) -> MahalliyTarmoq? {
        let r = Double(max(g.diametr_mm, 20)) / 2000
        var oq: [Vektor3] = []
        for n in g.nuqtalar {
            if let h = n.balandlik {
                oq.append(mahalliy(lat: n.lat, lon: n.lon, h: h, georef: georef, zona: zona))
            } else if let c = n.chuqurlik_m {
                let p = mahalliy(lat: n.lat, lon: n.lon, h: 0, georef: georef, zona: zona)
                guard let yer = yerBalandligi(p.x, p.z) else { continue }
                oq.append(Vektor3(p.x, yer - c - r, p.z))
            }
        }
        guard oq.count >= 2 else { return nil }
        return MahalliyTarmoq(id: g.id, turi: g.turi, diametrMm: g.diametr_mm, radius: r, sifat: g.sifat, oq: oq,
                              sigmaHSm: g.sigma_h_sm)
    }
}

// MARK: - Gorizontal geometriya (ARKit: x, z tekisligi)

@inline(__always) private func xz(_ v: Vektor3) -> (Double, Double) { (v.x, v.z) }

/// Kesmadagi eng yaqin nuqta parametri (3D).
private func kesmaT(_ p: Vektor3, _ a: Vektor3, _ b: Vektor3, gorizontal: Bool) -> Double {
    let ab = b - a, ap = p - a
    let ab2 = gorizontal ? ab.x * ab.x + ab.z * ab.z : ab.uzunlik2
    guard ab2 > 1e-12 else { return 0 }
    let d = gorizontal ? ap.x * ab.x + ap.z * ab.z : ap.nuqta(ab)
    return max(0, min(1, d / ab2))
}

private func gorMasofa(_ a: Vektor3, _ b: Vektor3) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)).squareRoot() }

private func kesishadi(_ p1: (Double, Double), _ p2: (Double, Double), _ q1: (Double, Double), _ q2: (Double, Double)) -> Bool {
    func yon(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> Double {
        (b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0)
    }
    let d1 = yon(q1, q2, p1), d2 = yon(q1, q2, p2), d3 = yon(p1, p2, q1), d4 = yon(p1, p2, q2)
    return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0))
}

private func ichidami(_ p: (Double, Double), _ pol: [(Double, Double)]) -> Bool {
    var ich = false
    var j = pol.count - 1
    for i in 0..<pol.count {
        let (xi, yi) = pol[i], (xj, yj) = pol[j]
        if (yi > p.1) != (yj > p.1), p.0 < (xj - xi) * (p.1 - yi) / (yj - yi) + xi { ich.toggle() }
        j = i
    }
    return ich
}

/// Ikki gorizontal kesma orasidagi eng qisqa masofa (kesishsa 0).
private func kesmalarMasofasi(_ a1: Vektor3, _ a2: Vektor3, _ b1: Vektor3, _ b2: Vektor3) -> Double {
    if kesishadi(xz(a1), xz(a2), xz(b1), xz(b2)) { return 0 }
    var eng = Double.infinity
    for (p, s, e) in [(a1, b1, b2), (a2, b1, b2), (b1, a1, a2), (b2, a1, a2)] {
        let t = kesmaT(p, s, e, gorizontal: true)
        eng = min(eng, gorMasofa(p, s + (e - s) * t))
    }
    return eng
}

public enum XavfDaraja: String, Sendable { case kesishadi = "KESISHADI", buferda = "BUFERDA" }

public struct XavfNatija: Equatable, Sendable {
    public let tarmoqId: Int
    public let turi: String
    public let daraja: XavfDaraja
    public let gorizontalMasofaM: Double
    /// Poligon yer sathidan eng yaqin joydagi quvur ustigacha.
    public let chuqurlikM: Double
    /// Mexanizatsiyalashgan qazishga yaqinlik: ustidan < 1 m yoki yondan < 2 m.
    public let faqatQolda: Bool
}

/// AR-06: qazish poligoni (yerga bosilgan nuqtalar) va tarmoqlar.
public enum QazishXavfi {
    public static let yonBufer = 2.0
    public static let ustBufer = 1.0

    public static func tekshir(poligon: [Vektor3], tarmoqlar: [MahalliyTarmoq], bufer: Double = yonBufer) -> [XavfNatija] {
        guard poligon.count >= 3 else { return [] }
        let pol = poligon.map(xz)
        let yer = poligon.map { $0.y }.reduce(0, +) / Double(poligon.count)
        var natija: [XavfNatija] = []
        for t in tarmoqlar {
            var eng = Double.infinity
            var engNuqta = t.oq[0]
            for i in 1..<t.oq.count {
                let a = t.oq[i - 1], b = t.oq[i]
                if ichidami(xz(a), pol) { eng = 0; engNuqta = a; break }
                for k in 0..<poligon.count {
                    let c = poligon[k], d = poligon[(k + 1) % poligon.count]
                    let m = kesmalarMasofasi(a, b, c, d)
                    if m < eng {
                        eng = m
                        let tt = kesmaT(Vektor3((c.x + d.x) / 2, 0, (c.z + d.z) / 2), a, b, gorizontal: true)
                        engNuqta = a + (b - a) * tt
                    }
                }
                if eng == 0 { break }
            }
            if ichidami(xz(t.oq[t.oq.count - 1]), pol) { eng = 0; engNuqta = t.oq[t.oq.count - 1] }
            guard eng <= bufer else { continue }
            let chuqurlik = yer - (engNuqta.y + t.radius)
            natija.append(XavfNatija(tarmoqId: t.id, turi: t.turi, daraja: eng == 0 ? .kesishadi : .buferda,
                                     gorizontalMasofaM: eng, chuqurlikM: chuqurlik,
                                     faqatQolda: eng < yonBufer || chuqurlik < ustBufer))
        }
        return natija.sorted { $0.gorizontalMasofaM < $1.gorizontalMasofaM }
    }
}

public enum Tomon: String, Sendable { case chap = "chapda", ong = "o'ngda", ostida = "ostida" }

public struct NishonNatija: Equatable, Sendable {
    public let tarmoqId: Int
    public let turi: String
    public let diametrMm: Int
    public let gorizontalMasofaM: Double
    public let tomon: Tomon
    public let chuqurlikM: Double
    public let oqNuqtasi: Vektor3
}

/// AR-05: ekran markazidagi yer nuqtasiga eng yaqin quvur (ekskavatorchi uchun).
public enum Nishon {
    public static func top(yerNuqtasi p: Vektor3, kameraOldi f: Vektor3, tarmoqlar: [MahalliyTarmoq],
                           maksMasofa: Double = 5) -> NishonNatija? {
        var eng: (t: MahalliyTarmoq, q: Vektor3, d: Double)?
        for t in tarmoqlar {
            for i in 1..<t.oq.count {
                let a = t.oq[i - 1], b = t.oq[i]
                let q = a + (b - a) * kesmaT(p, a, b, gorizontal: true)
                let d = gorMasofa(p, q)
                if d < (eng?.d ?? .infinity) { eng = (t, q, d) }
            }
        }
        guard let e = eng, e.d <= maksMasofa else { return nil }
        let ong = Vektor3(-f.z, 0, f.x)  // ARKit: oldinga f bo'lsa, o'ng = (−fz, 0, fx)
        let siljish = Vektor3(e.q.x - p.x, 0, e.q.z - p.z)
        let s = siljish.nuqta(ong.birlik ?? Vektor3(1, 0, 0))
        let tomon: Tomon = e.d < 0.05 ? .ostida : (s > 0 ? .ong : .chap)
        return NishonNatija(tarmoqId: e.t.id, turi: e.t.turi, diametrMm: e.t.diametrMm, gorizontalMasofaM: e.d,
                            tomon: tomon, chuqurlikM: p.y - (e.q.y + e.t.radius), oqNuqtasi: e.q)
    }
}

public struct Qoziq: Equatable, Sendable {
    public let yer: Vektor3
    public let quvurUsti: Vektor3
    public let chuqurlikM: Double
}

public enum ARChizish {
    /// AR-04: har `oraliq` metrda chuqurlik qozig'i. Yer balandligi noma'lum joy — tashlanadi.
    public static func qoziqlar(_ t: MahalliyTarmoq, oraliq: Double = 2, yerBalandligi: (Double, Double) -> Double?) -> [Qoziq] {
        var natija: [Qoziq] = []
        var qoldiq = 0.0
        for i in 1..<t.oq.count {
            let a = t.oq[i - 1], b = t.oq[i]
            let L = gorMasofa(a, b)
            var s = qoldiq
            while s <= L {
                let q = a + (b - a) * (L > 0 ? s / L : 0)
                if let yer = yerBalandligi(q.x, q.z) {
                    let ust = Vektor3(q.x, q.y + t.radius, q.z)
                    natija.append(Qoziq(yer: Vektor3(q.x, yer, q.z), quvurUsti: ust, chuqurlikM: yer - ust.y))
                }
                s += oraliq
            }
            qoldiq = s - L
        }
        return natija
    }

    /// AR-03: virtual chuqur tubi — ichidagi eng chuqur quvurdan 0,3 m past (quvur bo'lmasa 1,5 m).
    public static func chuqurTubi(markaz: Vektor3, olcham: Double = 1.0, tarmoqlar: [MahalliyTarmoq]) -> Double {
        let yarim = olcham / 2
        var engPast: Double?
        for t in tarmoqlar {
            for i in 1..<t.oq.count {
                let a = t.oq[i - 1], b = t.oq[i]
                for k in 0...20 {
                    let q = a + (b - a) * (Double(k) / 20)
                    if abs(q.x - markaz.x) <= yarim + t.radius, abs(q.z - markaz.z) <= yarim + t.radius {
                        engPast = min(engPast ?? .infinity, q.y - t.radius)
                    }
                }
            }
        }
        return (engPast.map { $0 - 0.3 }) ?? (markaz.y - 1.5)
    }
}
