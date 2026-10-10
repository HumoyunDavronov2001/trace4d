import Foundation

// MARK: - DS-04: RTK kechikishini xom ma'lumotdan baholash (serverda; telefon ham shu kod bilan)

/// Bitta GGA epoxasi georeferens uchun: UTM (sharq, shimol, ellipsoid balandligi), GNSS vaqti (sutka soniyasi, uzluksiz)
/// va telefonga kelgan vaqt (uptime, s; DS-03 `nmea_t` yozuvidan). Faqat RASMIY epoxalar juftlanadi (T-103).
public struct RTKEpoxasi: Equatable, Sendable {
    public var g: Vektor3
    public var utcS: Double?
    public var te: Double?
    public var rasmiy: Bool
    public init(g: Vektor3, utcS: Double?, te: Double?, rasmiy: Bool) { self.g = g; self.utcS = utcS; self.te = te; self.rasmiy = rasmiy }
}

public struct KechikishNatija: Codable, Equatable, Sendable {
    /// Topilgan kechikish (s): poza vaqti = epoxaning telefon vaqtidagi tebranishsiz kelishi − kechikish.
    public var kechikishS: Double?
    /// Shu kechikishdagi georeferens qoldig'i (3D RMS, m).
    public var rmsM: Double?
    /// Telefon sozlamasi bilan bir xil ma'noda: o'rtacha (kelish − poza) vaqti, s.
    public var ortachaS: Double?
    /// [kechikish s, RMS m] egri chizig'i (0…300 ms).
    public var egri: [[Double]]
    public var juftlar: Int
    /// "utc" — GNSS vaqti + soat bog'lanishi (kelish tebranishi chiqarilgan), "kelish" — faqat kelish vaqti.
    public var usul: String
    public var ishonchli: Bool
    public var sabab: String?
}

public enum Kechikish {
    /// "hhmmss.ss" → sutka soniyasi.
    public static func utcSoniya(_ v: String?) -> Double? {
        guard let v, v.count >= 6, let hh = Double(v.prefix(2)), let mm = Double(v.dropFirst(2).prefix(2)),
              let ss = Double(v.dropFirst(4)) else { return nil }
        return hh * 3600 + mm * 60 + ss
    }

    /// Sutka almashishi (UTC 00:00) uzilmasin: kamaysa +86400.
    public static func uzluksiz(_ s: [Double?]) -> [Double?] {
        var qosh = 0.0, oldingi: Double?
        return s.map { x in
            guard let x else { return nil }
            if let o = oldingi, x + qosh < o - 43_200 { qosh += 86_400 }
            oldingi = x + qosh
            return x + qosh
        }
    }

    /// Soat bog'lanishi: te ≈ utc + c + δ (δ ≥ 0 — uzatish kechikishi). c = (te − utc) ning 5-persentili:
    /// kelish tebranishi chiqariladi, qolgan doimiy qism kechikish sifatida baholanadi.
    public static func soatBoglanishi(_ e: [RTKEpoxasi]) -> Double? {
        var d = e.compactMap { x -> Double? in
            guard let u = x.utcS, let t = x.te else { return nil }
            return t - u
        }
        guard d.count >= 10 else { return nil }
        d.sort()
        return d[Int(Double(d.count - 1) * 0.05)]
    }

    /// Epoxaning poza vaqti (uptime): kechikish `L` bilan.
    public static func pozaVaqti(_ e: RTKEpoxasi, L: Double, c: Double?) -> Double? {
        if let c, let u = e.utcS { return u + c - L }
        if let t = e.te { return t - L }
        return nil
    }

    /// Juftlar: (vaqt, antenna ENU mahalliy, UTM) — faqat RASMIY va poza izi ichidagi epoxalar.
    public static func juftlar(iz: PozaIzi, epoxalar: [RTKEpoxasi], ofset: [Double], L: Double, c: Double?)
        -> [(t: Double, m: Vektor3, g: Vektor3)] {
        var r: [(t: Double, m: Vektor3, g: Vektor3)] = []
        r.reserveCapacity(epoxalar.count)
        for e in epoxalar where e.rasmiy {
            guard let t = pozaVaqti(e, L: L, c: c), let p = iz.poza(t) else { continue }
            r.append((t, Antenna.enu(p, ofset: ofset), e.g))
        }
        return r
    }

    /// Qisqa vaqt oynalarida (ARKit suzishi ta'sir qilmasin) gravitatsiyali georeferens qoldig'i — umumiy RMS (m).
    static func qoldiq(_ j: [(t: Double, m: Vektor3, g: Vektor3)], oynaS: Double) -> (rms: Double, n: Int)? {
        guard j.count >= 10 else { return nil }
        var kv = 0.0, n = 0, i = 0
        while i < j.count {
            var k = i
            while k < j.count, j[k].t - j[i].t <= oynaS { k += 1 }
            // oxirgi kichik bo'lak oldingisiga qo'shiladi
            if j.count - k < 10 { k = j.count }
            let b = Array(j[i..<k])
            if b.count >= 10, let g = try? Georeferens.gravitatsiyaBilan(mahalliyENU: b.map(\.m), global: b.map(\.g), minYoyilishM: 0.3) {
                kv += (g.gorizontalRmsM * g.gorizontalRmsM + g.vertikalRmsM * g.vertikalRmsM) * Double(b.count)
                n += b.count
            }
            i = k
        }
        return n > 0 ? ((kv / Double(n)).squareRoot(), n) : nil
    }

    /// Kechikishni 0…300 ms oralig'ida izlash: qoldiqni eng kichik qiladigan qiymat, keyin parabola bilan aniqlashtirish.
    /// Harakat tezligi o'zgarmasa (bir tekis to'g'ri yurish) kechikish siljish bilan aralashadi — `ishonchli = false`.
    public static func baho(iz: PozaIzi, epoxalar: [RTKEpoxasi], ofset: [Double],
                            oraliq: ClosedRange<Double> = 0...0.3, qadam: Double = 0.005, oynaS: Double = 20) -> KechikishNatija {
        let c = soatBoglanishi(epoxalar)
        let usul = c == nil ? "kelish" : "utc"
        var natija = KechikishNatija(kechikishS: nil, rmsM: nil, ortachaS: nil, egri: [], juftlar: 0, usul: usul,
                                     ishonchli: false, sabab: nil)
        guard epoxalar.contains(where: { $0.te != nil }) else {
            natija.sabab = "jurnalda epoxalarning kelish vaqti yo'q (DS-03 dan oldingi yozuv)"
            return natija
        }
        var egri: [(L: Double, rms: Double, n: Int)] = []
        var L = oraliq.lowerBound
        while L <= oraliq.upperBound + 1e-9 {
            let j = juftlar(iz: iz, epoxalar: epoxalar, ofset: ofset, L: L, c: c)
            if let q = qoldiq(j, oynaS: oynaS) { egri.append((L, q.rms, q.n)) }
            L += qadam
        }
        natija.egri = egri.map { [($0.L * 1000).rounded() / 1000, ($0.rms * 1e5).rounded() / 1e5] }
        guard egri.count >= 5, let k = egri.indices.min(by: { egri[$0].rms < egri[$1].rms }) else {
            natija.sabab = "juftlar yetarli emas (kamida 10 ta RASMIY epoxa poza izi ichida kerak)"
            return natija
        }
        var Lb = egri[k].L
        if k > 0, k < egri.count - 1 {
            let (a, b, d) = (egri[k - 1].rms, egri[k].rms, egri[k + 1].rms)
            let maxraj = a - 2 * b + d
            if maxraj > 1e-12 { Lb += 0.5 * qadam * (a - d) / maxraj }
        }
        let jb = juftlar(iz: iz, epoxalar: epoxalar, ofset: ofset, L: Lb, c: c)
        let qb = qoldiq(jb, oynaS: oynaS)
        natija.kechikishS = Lb
        natija.rmsM = qb?.rms ?? egri[k].rms
        natija.juftlar = jb.count
        let kelish = epoxalar.filter(\.rasmiy).compactMap { e -> Double? in
            guard let te = e.te, let tp = pozaVaqti(e, L: Lb, c: c) else { return nil }
            return te - tp
        }
        natija.ortachaS = kelish.isEmpty ? nil : kelish.reduce(0, +) / Double(kelish.count)
        // Ishonch: minimum chetda emas va egri yetarli darajada «chuqur» (kechikish kuzatiladigan harakat bor).
        let eng = egri[k].rms, chet = max(egri.first!.rms, egri.last!.rms)
        if k == 0 || k == egri.count - 1 {
            natija.sabab = "eng kichik qoldiq oraliq chetida (\(Int((Lb * 1000).rounded())) ms) — haqiqiy qiymat 0…300 ms dan tashqarida bo'lishi mumkin"
        } else if chet - eng < 0.002 {
            natija.sabab = "harakat bir tekis: kechikish qoldiqqa deyarli ta'sir qilmaydi (egri chuqurligi \(Int(((chet - eng) * 1000).rounded())) mm)"
        } else {
            natija.ishonchli = true
        }
        return natija
    }
}
