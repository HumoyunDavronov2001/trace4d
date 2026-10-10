import Foundation

/// TALABLAR 15 (LK-03…LK-05): RTK (WGS84) → mahalliy tizim (X shimol, Y sharq) va Boltiq balandligi.
/// Koordinatasi ma'lum punktlar RTK bilan o'lchanadi, o'tish shu juftlardan topiladi [Emlid, Trimble, NGS]:
/// mahalliy Transvers Merkator (k0 = 1, markaziy meridian punktlar markazida) → 4 parametrli Helmert; balandlik
/// anomaliyasi ζ = h − H: 1–3 punktda doimiy, ≥ 4 punktda qiya tekislik. Server `yerosti_lokal.py` bilan BIR XIL —
/// telefon joyida qoldiqni ko'rsatadi, server hujjat uchun qayta hisoblaydi (sinov: bir xil kirish → bir xil natija).
public enum MahalliyTM {
    /// WGS84 → (sharq e, shimol n), k0 = 1, siljishsiz. `UTM.ga` qatorlari bilan bir xil.
    public static func ga(lat: Double, lon: Double, lon0: Double) -> (e: Double, n: Double) {
        let n = UTM.n
        let fi = lat * .pi / 180
        let lam = (lon - lon0) * .pi / 180
        let sn = 2 * n.squareRoot() / (1 + n)
        let t = sinh(atanh(sin(fi)) - sn * atanh(sn * sin(fi)))
        let xi = atan2(t, cos(lam))
        let eta = atanh(sin(lam) / (1 + t * t).squareRoot())
        var e = eta, nn = xi
        for j in 1...3 {
            let d = Double(j)
            e += UTM.alfa[j - 1] * cos(2 * d * xi) * sinh(2 * d * eta)
            nn += UTM.alfa[j - 1] * sin(2 * d * xi) * cosh(2 * d * eta)
        }
        return (UTM.A * e, UTM.A * nn)
    }

    public static func dan(e: Double, n: Double, lon0: Double) -> (lat: Double, lon: Double) {
        let xi = n / UTM.A, eta = e / UTM.A
        var xi1 = xi, eta1 = eta
        for j in 1...3 {
            let d = Double(j)
            xi1 -= UTM.beta[j - 1] * sin(2 * d * xi) * cosh(2 * d * eta)
            eta1 -= UTM.beta[j - 1] * cos(2 * d * xi) * sinh(2 * d * eta)
        }
        let chi = asin(sin(xi1) / cosh(eta1))
        var fi = chi
        for j in 1...3 { fi += UTM.delta[j - 1] * sin(2 * Double(j) * chi) }
        return (fi * 180 / .pi, lon0 + atan2(sinh(eta1), cos(xi1)) * 180 / .pi)
    }
}

/// Bitta nazorat punkti: o'lchangan WGS84 (lat, lon, h ellipsoid) va ma'lum mahalliy qiymatlar.
/// X/Y yoki H bo'lmasligi mumkin (faqat balandligi ma'lum reper).
public struct LokalizatsiyaJufti: Equatable {
    public var nomi: String
    public var lat: Double, lon: Double, h: Double?
    public var x: Double?, y: Double?, H: Double?
    public init(nomi: String, lat: Double, lon: Double, h: Double?, x: Double?, y: Double?, H: Double?) {
        self.nomi = nomi; self.lat = lat; self.lon = lon; self.h = h; self.x = x; self.y = y; self.H = H
    }
}

/// Server JSON i bilan bir xil kalitlar (`natija.parametrlar`).
public struct LokParametrlar: Codable, Equatable {
    public struct Vertikal: Codable, Equatable {
        public var z0: Double, ge: Double, gn: Double, ce: Double, cn: Double, model: String
    }
    public var lon0: Double
    public var gor: String?
    public var a: Double, b: Double, ge: Double, gn: Double, lx: Double, ly: Double
    public var v: Vertikal?
}

public struct LokQoldiq: Equatable {
    public var nomi: String
    public var gor: Double?   // metr
    public var ver: Double?   // metr, ishorali (ma'lum − bashorat)
}

public struct LokNatija {
    public var parametrlar: LokParametrlar
    public var qoldiqlar: [LokQoldiq]
    public var loo: [LokQoldiq]
    public var nGor: Int, nVer: Int
    public var maksGor: Double?, maksVer: Double?
    public var masshtabPpm: Double?, burilishGrad: Double?, qiyalikPpm: Double?
    public var xatolar: [String], ogohlantirishlar: [String]
    public var yaroqli: Bool { xatolar.isEmpty }
}

public enum Lokalizatsiya {
    // LK-04 [NGS]: kamida 4 gorizontal va 4 vertikal punkt; qoldiq 95 % da gorizontal < 2 sm, vertikal < 4 sm
    public static let minPunkt = 4
    public static let qoldiqGorM = 0.02
    public static let qoldiqVerM = 0.04
    // LK-05: tekshiruv — chegara + RTK 1σ
    public static let tekshiruvGorM = 0.03
    public static let tekshiruvVerM = 0.05
    public static let masshtabOgohPpm = 500.0
    public static let masshtabRadPpm = 2000.0
    public static let qiyalikOgohPpm = 100.0

    public enum Xato: Error, Equatable { case bosh, birJoyda }

    struct Gor { var a: Double, b: Double, ge: Double, gn: Double, lx: Double, ly: Double, model: String }

    static func gorMoslash(_ j: [(e: Double, n: Double, x: Double, y: Double)]) throws -> Gor {
        let k = Double(j.count)
        let ge = j.map(\.e).reduce(0, +) / k, gn = j.map(\.n).reduce(0, +) / k
        let lx = j.map(\.x).reduce(0, +) / k, ly = j.map(\.y).reduce(0, +) / k
        if j.count == 1 { return Gor(a: 1, b: 0, ge: ge, gn: gn, lx: lx, ly: ly, model: "siljish") }
        var szz = 0.0, sa = 0.0, sb = 0.0
        for p in j {
            let de = p.e - ge, dn = p.n - gn, dx = p.x - lx, dy = p.y - ly
            szz += de * de + dn * dn
            sa += dy * de + dx * dn
            sb += dx * de - dy * dn
        }
        guard szz >= 1e-6 else { throw Xato.birJoyda }
        return Gor(a: sa / szz, b: sb / szz, ge: ge, gn: gn, lx: lx, ly: ly, model: "helmert4")
    }

    static func verMoslash(_ j: [(e: Double, n: Double, z: Double)]) -> LokParametrlar.Vertikal {
        let k = Double(j.count)
        let ce = j.map(\.e).reduce(0, +) / k, cn = j.map(\.n).reduce(0, +) / k, z0 = j.map(\.z).reduce(0, +) / k
        if j.count < minPunkt { return .init(z0: z0, ge: 0, gn: 0, ce: ce, cn: cn, model: "doimiy") }
        var see = 0.0, sen = 0.0, snn = 0.0, sez = 0.0, snz = 0.0
        for p in j {
            let de = p.e - ce, dn = p.n - cn, dz = p.z - z0
            see += de * de; sen += de * dn; snn += dn * dn; sez += de * dz; snz += dn * dz
        }
        let det = see * snn - sen * sen
        // punktlar bir chiziqqa yaqin: ko'ndalang yoyilish uzunasiga nisbatan ≥ 10 % va ≥ 2 m bo'lsin
        let yarim = (see + snn) / 2, farq = (((see - snn) / 2) * ((see - snn) / 2) + sen * sen).squareRoot()
        let kichik = max(yarim - farq, 0), katta = yarim + farq
        if det <= 0 || (kichik / k).squareRoot() < max(2.0, 0.1 * (katta / k).squareRoot()) {
            return .init(z0: z0, ge: 0, gn: 0, ce: ce, cn: cn, model: "doimiy (punktlar bir chiziqda)")
        }
        return .init(z0: z0, ge: (sez * snn - snz * sen) / det, gn: (snz * see - sez * sen) / det, ce: ce, cn: cn,
                     model: "qiya tekislik")
    }

    static func gorQolla(_ p: LokParametrlar, _ e: Double, _ n: Double) -> (x: Double, y: Double) {
        let de = e - p.ge, dn = n - p.gn
        return (p.b * de + p.a * dn + p.lx, p.a * de - p.b * dn + p.ly)
    }

    static func zeta(_ v: LokParametrlar.Vertikal?, _ e: Double, _ n: Double) -> Double? {
        guard let v else { return nil }
        return v.z0 + v.ge * (e - v.ce) + v.gn * (n - v.cn)
    }

    /// WGS84 → (X shimol, Y sharq, H Boltiq).
    public static func oldinga(_ p: LokParametrlar, lat: Double, lon: Double, h: Double?) -> (x: Double?, y: Double?, H: Double?) {
        let (e, n) = MahalliyTM.ga(lat: lat, lon: lon, lon0: p.lon0)
        let g: (x: Double, y: Double)? = p.gor == nil ? nil : gorQolla(p, e, n)
        let z = zeta(p.v, e, n)
        return (g?.x, g?.y, (h != nil && z != nil) ? h! - z! : nil)
    }

    /// (X, Y, H) → WGS84 (lat, lon, h ellipsoid).
    public static func teskari(_ p: LokParametrlar, x: Double, y: Double, H: Double?) -> (lat: Double, lon: Double, h: Double?) {
        let k = p.a * p.a + p.b * p.b
        let dy = y - p.ly, dx = x - p.lx
        let e = (p.a * dy + p.b * dx) / k + p.ge, n = (-p.b * dy + p.a * dx) / k + p.gn
        let (lat, lon) = MahalliyTM.dan(e: e, n: n, lon0: p.lon0)
        let z = zeta(p.v, e, n)
        return (lat, lon, (H != nil && z != nil) ? H! + z! : nil)
    }

    public static func hisobla(_ juftlar: [LokalizatsiyaJufti]) throws -> LokNatija {
        guard !juftlar.isEmpty else { throw Xato.bosh }
        let lon0 = juftlar.map(\.lon).reduce(0, +) / Double(juftlar.count)
        let en = juftlar.map { MahalliyTM.ga(lat: $0.lat, lon: $0.lon, lon0: lon0) }
        let gi = juftlar.indices.filter { juftlar[$0].x != nil && juftlar[$0].y != nil }
        let vi = juftlar.indices.filter { juftlar[$0].H != nil && juftlar[$0].h != nil }
        func gorKirish(_ idx: [Int]) -> [(e: Double, n: Double, x: Double, y: Double)] {
            idx.map { (en[$0].e, en[$0].n, juftlar[$0].x!, juftlar[$0].y!) }
        }
        func verKirish(_ idx: [Int]) -> [(e: Double, n: Double, z: Double)] {
            idx.map { (en[$0].e, en[$0].n, juftlar[$0].h! - juftlar[$0].H!) }
        }
        var p = LokParametrlar(lon0: lon0, gor: nil, a: 1, b: 0, ge: 0, gn: 0, lx: 0, ly: 0, v: nil)
        if !gi.isEmpty {
            let g = try gorMoslash(gorKirish(gi))
            p.a = g.a; p.b = g.b; p.ge = g.ge; p.gn = g.gn; p.lx = g.lx; p.ly = g.ly; p.gor = g.model
        }
        if !vi.isEmpty { p.v = verMoslash(verKirish(vi)) }

        var qoldiq: [LokQoldiq] = [], loo: [LokQoldiq] = []
        for i in juftlar.indices {
            let j = juftlar[i]
            let f = oldinga(p, lat: j.lat, lon: j.lon, h: j.h)
            var r = LokQoldiq(nomi: j.nomi, gor: nil, ver: nil)
            if gi.contains(i), let x = f.x, let y = f.y { r.gor = hypot(j.x! - x, j.y! - y) }
            if vi.contains(i), let H = f.H { r.ver = j.H! - H }
            qoldiq.append(r)
            // LOO: punkt chiqarib tashlanib, qolganlar bilan bashorat
            var l = LokQoldiq(nomi: j.nomi, gor: nil, ver: nil)
            let qg = gi.filter { $0 != i }
            if gi.contains(i), qg.count >= 2, let g = try? gorMoslash(gorKirish(qg)) {
                var pl = p; pl.a = g.a; pl.b = g.b; pl.ge = g.ge; pl.gn = g.gn; pl.lx = g.lx; pl.ly = g.ly
                let q = gorQolla(pl, en[i].e, en[i].n)
                l.gor = hypot(j.x! - q.x, j.y! - q.y)
            }
            let qv = vi.filter { $0 != i }
            if vi.contains(i), !qv.isEmpty, let z = zeta(verMoslash(verKirish(qv)), en[i].e, en[i].n) {
                l.ver = j.H! - (j.h! - z)
            }
            loo.append(l)
        }
        let gq = qoldiq.compactMap(\.gor), vq = qoldiq.compactMap(\.ver).map(abs)
        var n = LokNatija(parametrlar: p, qoldiqlar: qoldiq, loo: loo, nGor: gi.count, nVer: vi.count,
                          maksGor: gq.max(), maksVer: vq.max(),
                          masshtabPpm: p.gor == nil ? nil : (hypot(p.a, p.b) - 1) * 1e6,
                          burilishGrad: p.gor == nil ? nil : atan2(p.b, p.a) * 180 / .pi,
                          qiyalikPpm: p.v.map { hypot($0.ge, $0.gn) * 1e6 }, xatolar: [], ogohlantirishlar: [])
        if n.nGor < minPunkt { n.xatolar.append("gorizontal punktlar \(n.nGor) ta: kamida \(minPunkt) ta kerak") }
        if n.nVer < minPunkt { n.xatolar.append("balandligi ma'lum punktlar \(n.nVer) ta: kamida \(minPunkt) ta kerak") }
        if let m = n.maksGor, m > qoldiqGorM { n.xatolar.append(String(format: "gorizontal qoldiq %.1f sm > 2 sm", m * 100)) }
        if let m = n.maksVer, m > qoldiqVerM { n.xatolar.append(String(format: "vertikal qoldiq %.1f sm > 4 sm", m * 100)) }
        if let m = n.masshtabPpm, abs(m) > masshtabRadPpm {
            n.xatolar.append(String(format: "masshtab %+.0f ppm: punkt koordinatasi yoki birligi xato", m))
        } else if let m = n.masshtabPpm, abs(m) > masshtabOgohPpm {
            n.ogohlantirishlar.append(String(format: "masshtab %+.0f ppm odatdagidan katta", m))
        }
        if let q = n.qiyalikPpm, q > qiyalikOgohPpm {
            n.ogohlantirishlar.append(String(format: "balandlik tekisligi qiyaligi %.0f ppm", q))
        }
        return n
    }

    /// LK-05: kalibrlashga kirmagan o'lchovning ma'lum punktdan og'ishi.
    public static func tekshiruv(_ p: LokParametrlar, lat: Double, lon: Double, h: Double?,
                                 x: Double?, y: Double?, H: Double?) -> (gor: Double?, ver: Double?, otdi: Bool) {
        let f = oldinga(p, lat: lat, lon: lon, h: h)
        let gor: Double? = (f.x != nil && x != nil) ? hypot(x! - f.x!, y! - f.y!) : nil
        let ver: Double? = (f.H != nil && H != nil) ? H! - f.H! : nil
        let otdi = (gor ?? 0) <= tekshiruvGorM && abs(ver ?? 0) <= tekshiruvVerM && !(gor == nil && ver == nil)
        return (gor, ver, otdi)
    }
}
