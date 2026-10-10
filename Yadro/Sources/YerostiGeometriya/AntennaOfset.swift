import Foundation

// MARK: - DS-02: antenna ofsetini xom ma'lumotdan baholash (profil qiymatini tekshirish uchun)

public struct OfsetBaho: Codable, Equatable, Sendable {
    /// Baholangan ofset, portret ramkasi (x o'ng, y yuqori, z foydalanuvchiga), m.
    public var ofset: [Double]
    /// Har o'q bo'yicha taxminiy σ (m) — RTK shovqini va telefon burilishlari xilma-xilligidan.
    public var sigma: [Double]
    /// Profil (jurnaldagi) ofsetidan farq (m).
    public var profildanFarqM: Double?
    public var juftlar: Int
    /// Telefon yetarli burilganmi (eng zaif o'q σ ≤ 1,5 sm).
    public var kuzatiladi: Bool
    public var sabab: String?
}

public enum AntennaOfset {
    /// Portret ofseti → ARKit kamera ramkasi chiziqli: (−o_y, o_x, o_z) = K·o.
    static let K: [[Double]] = [[0, -1, 0], [1, 0, 0], [0, 0, 1]]

    /// Juftlar oynalarda (ARKit suzishi oyna ichida sezilmasin): har oynada qattiq yaw + siljish, hammasiga umumiy ofset.
    /// Har takrorda: ofset bilan oyna transformatsiyalari → oyna bo'yicha markazlangan chiziqli eng kichik kvadratlar.
    public static func baho(iz: PozaIzi, epoxalar: [RTKEpoxasi], L: Double, c: Double?, boshlangich: [Double] = [0, 0, 0],
                            profil: [Double]? = nil, oynaS: Double = 15, sigmaGNSS: Double = 0.01) -> OfsetBaho {
        var natija = OfsetBaho(ofset: boshlangich, sigma: [.infinity, .infinity, .infinity], profildanFarqM: nil, juftlar: 0,
                               kuzatiladi: false, sabab: nil)
        // juftlar uchun poza (R, p) va epoxa
        var j: [(t: Double, R: Matritsa3, p: Vektor3, g: Vektor3)] = []
        for e in epoxalar where e.rasmiy {
            guard let t = Kechikish.pozaVaqti(e, L: L, c: c), let x = iz.poza(t) else { continue }
            j.append((t, x.q.matritsa, x.p, e.g))
        }
        natija.juftlar = j.count
        guard j.count >= 30 else { natija.sabab = "RASMIY juftlar 30 tadan kam"; return natija }
        // oynalar
        var oynalar: [[Int]] = []
        var bosh = 0
        while bosh < j.count {
            var k = bosh
            while k + 1 < j.count, j[k + 1].t - j[bosh].t <= oynaS { k += 1 }
            if k - bosh + 1 >= 10 { oynalar.append(Array(bosh...k)) }
            bosh = k + 1
        }
        guard !oynalar.isEmpty else { natija.sabab = "oynalar yetarli emas"; return natija }
        let E: [[Double]] = [[1, 0, 0], [0, 0, -1], [0, 1, 0]]   // ARKit (x, y, z) → ENU (x, −z, y)
        func kop(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
            (0..<3).map { i in (0..<3).map { k in (0..<3).reduce(0) { $0 + a[i][$1] * b[$1][k] } } }
        }
        func qolla(_ a: [[Double]], _ v: [Double]) -> [Double] { (0..<3).map { i in (0..<3).reduce(0) { $0 + a[i][$1] * v[$1] } } }
        var o = boshlangich
        var N = [[Double]](repeating: [0, 0, 0], count: 3)
        for _ in 0..<4 {
            N = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
            var h = [0.0, 0.0, 0.0]
            for w in oynalar {
                let m = w.map { i -> Vektor3 in
                    let oc = Vektor3(-o[1], o[0], o[2])
                    return ARKitRamka.enu(j[i].R.qolla(oc) + j[i].p)
                }
                guard let g = try? Georeferens.gravitatsiyaBilan(mahalliyENU: m, global: w.map { j[$0].g }, minYoyilishM: 0.3) else { continue }
                let ps = g.transformatsiya.burchak, cs = cos(ps), sn = sin(ps)
                let Rz: [[Double]] = [[cs, -sn, 0], [sn, cs, 0], [0, 0, 1]]
                let RE = kop(Rz, E)
                // b_i = g_i − Rz·E·p_i ;  a_i = Rz·E·R_i·K
                let ab: [([[Double]], [Double])] = w.map { i in
                    let a = kop(kop(RE, j[i].R.m), K)
                    let rp = qolla(RE, [j[i].p.x, j[i].p.y, j[i].p.z])
                    return (a, [j[i].g.x - rp[0], j[i].g.y - rp[1], j[i].g.z - rp[2]])
                }
                let n = Double(ab.count)
                var am = [[Double]](repeating: [0, 0, 0], count: 3), bm = [0.0, 0.0, 0.0]
                for (a, b) in ab { for r in 0..<3 { bm[r] += b[r] / n; for c2 in 0..<3 { am[r][c2] += a[r][c2] / n } } }
                for (a, b) in ab {
                    for r in 0..<3 {
                        let ar = (0..<3).map { a[r][$0] - am[r][$0] }, br = b[r] - bm[r]
                        for p in 0..<3 { h[p] += ar[p] * br; for q in 0..<3 { N[p][q] += ar[p] * ar[q] } }
                    }
                }
            }
            guard let yangi = yech3(N, h) else { natija.sabab = "tenglama yechilmadi (burilish yo'q)"; return natija }
            o = yangi
        }
        let xos = Matritsa3(N).xosTahlil()
        natija.ofset = o
        // σ_o ≈ σ_GNSS · sqrt(diag(N⁻¹))
        if let inv = teskari3(N) {
            natija.sigma = (0..<3).map { sigmaGNSS * max(0, inv[$0][$0]).squareRoot() }
        }
        natija.kuzatiladi = (xos.first?.qiymat ?? 0) > 0 && natija.sigma.allSatisfy { $0 <= 0.015 }
        if !natija.kuzatiladi { natija.sabab = "telefon yetarli burilmagan: ofset ishonchli baholanmaydi" }
        if let p = profil, p.count == 3 {
            natija.profildanFarqM = ((o[0] - p[0]) * (o[0] - p[0]) + (o[1] - p[1]) * (o[1] - p[1]) + (o[2] - p[2]) * (o[2] - p[2])).squareRoot()
        }
        return natija
    }

    static func yech3(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        guard let inv = teskari3(A) else { return nil }
        return (0..<3).map { i in (0..<3).reduce(0) { $0 + inv[i][$1] * b[$1] } }
    }

    static func teskari3(_ m: [[Double]]) -> [[Double]]? {
        let a = m
        let det = a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
            + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        guard abs(det) > 1e-12 else { return nil }
        return [[(a[1][1] * a[2][2] - a[1][2] * a[2][1]) / det, (a[0][2] * a[2][1] - a[0][1] * a[2][2]) / det, (a[0][1] * a[1][2] - a[0][2] * a[1][1]) / det],
                [(a[1][2] * a[2][0] - a[1][0] * a[2][2]) / det, (a[0][0] * a[2][2] - a[0][2] * a[2][0]) / det, (a[0][2] * a[1][0] - a[0][0] * a[1][2]) / det],
                [(a[1][0] * a[2][1] - a[1][1] * a[2][0]) / det, (a[0][1] * a[2][0] - a[0][0] * a[2][1]) / det, (a[0][0] * a[1][1] - a[0][1] * a[1][0]) / det]]
    }
}
