import Foundation

// MARK: - DS-05: bo'lakli georeferens — ARKit suzishini RTK bilan tuzatish (telefon va server bir xil)

public struct BolakliSozlama: Sendable {
    /// Tugunlar orasidagi yo'l (m); harakatsiz turilsa ham har `tugunMaksS` soniyada tugun qo'yiladi.
    public var tugunQadamM = 0.5
    public var tugunMaksS = 5.0
    /// Burilish (yaw) shu yo'l oynasida baholanadi: uzun oyna — shovqinga chidamli, qisqa — suzishni tez kuzatadi.
    public var burilishOynaM = 8.0
    /// Siljish shu yo'l oynasida mahalliy chiziqli regressiya bilan silliqlanadi.
    public var siljishOynaM = 2.0
    /// Hisobot bo'lagi (m) va bo'lak qoldig'i chegarasi: oshsa — bo'lak PAST.
    public var bolakM = 10.0
    public var chekM = 0.03
    public var minJuftBolak = 10
    /// RTK FIX uzilishi shundan uzoq bo'lsa — bo'lak PAST (suzish tuzatilmagan).
    public var maksBoshliqS = 3.0
    public init() {}
}

/// Tugun: shu vaqtdagi mahalliy ENU → UTM transformatsiyasi.
public struct BolakliTugun: Codable, Equatable, Sendable {
    public var t: Double
    public var burchak: Double
    public var siljish: [Double]
}

/// Hisobot bo'lagi (yo'l bo'yicha). `past = true` — bu bo'lakdagi skan nuqtalari RASMIY ham, SKAN ham emas.
public struct GeorefBolak: Codable, Equatable, Sendable {
    public var boshM: Double
    public var oxirM: Double
    public var boshT: Double
    public var oxirT: Double
    public var juftlar: Int
    public var rmsH: Double
    public var rmsV: Double
    public var maksM: Double
    public var past: Bool
    public var sabab: String?
}

public enum BolakliXato: Error, Equatable {
    case juftYetarliEmas
}

public struct BolakliGeoreferens: Sendable {
    public let tugunlar: [BolakliTugun]
    public let bolaklar: [GeorefBolak]
    /// Butun skanga bitta qattiq transformatsiya — taqqoslash uchun (DS-05 dan oldingi usul).
    public let umumiy: GorizontalNatija
    /// Juftlar qoldig'i (bo'lakli transformatsiya bilan): umumiy RMS.
    public let rmsH: Double
    public let rmsV: Double

    /// `t` vaqtidagi transformatsiya: tugunlar orasida chiziqli; chetlarda — eng yaqin tugun.
    public func transformatsiya(_ t: Double) -> GorizontalTransformatsiya {
        guard let a0 = tugunlar.first, let aN = tugunlar.last else { return umumiy.transformatsiya }
        func tr(_ k: BolakliTugun) -> GorizontalTransformatsiya {
            GorizontalTransformatsiya(burchak: k.burchak, t: Vektor3(k.siljish[0], k.siljish[1], k.siljish[2]))
        }
        if t <= a0.t { return tr(a0) }
        if t >= aN.t { return tr(aN) }
        var lo = 0, hi = tugunlar.count - 1
        while hi - lo > 1 { let o = (lo + hi) / 2; if tugunlar[o].t <= t { lo = o } else { hi = o } }
        let a = tugunlar[lo], b = tugunlar[hi]
        let u = (t - a.t) / max(b.t - a.t, 1e-9)
        let s = (0..<3).map { a.siljish[$0] + (b.siljish[$0] - a.siljish[$0]) * u }
        return GorizontalTransformatsiya(burchak: a.burchak + (b.burchak - a.burchak) * u, t: Vektor3(s[0], s[1], s[2]))
    }

    public func qolla(_ enu: Vektor3, vaqt t: Double) -> Vektor3 { transformatsiya(t).qolla(enu) }

    /// Shu vaqtdagi nuqta qaysi bo'lakka tegishli; RTK qamrovidan tashqarida — nil (nuqta PAST).
    public func bolak(_ t: Double) -> GeorefBolak? {
        bolaklar.first { t >= $0.boshT - 1e-6 && t <= $0.oxirT + 1e-6 }
    }

    /// Juftlardan hisoblash. Juftlar vaqt bo'yicha tartiblanadi; kamida 20 ta va 1 m yoyilish kerak.
    public static func hisobla(_ juft: [(t: Double, m: Vektor3, g: Vektor3)], sozlama s: BolakliSozlama = .init())
        throws -> BolakliGeoreferens {
        let j = juft.sorted { $0.t < $1.t }
        guard j.count >= 20 else { throw BolakliXato.juftYetarliEmas }
        let umumiy = try Georeferens.gravitatsiyaBilan(mahalliyENU: j.map(\.m), global: j.map(\.g))
        let psi0 = umumiy.transformatsiya.burchak

        // yo'l uzunligi (gorizontal, ARKit ENU bo'yicha)
        var yol = [0.0]
        for i in 1..<j.count {
            let d = j[i].m - j[i - 1].m
            yol.append(yol[i - 1] + (d.x * d.x + d.y * d.y).squareRoot())
        }

        // tugunlar
        var tugunIdx = [0]
        for i in 1..<j.count {
            let o = tugunIdx.last!
            if yol[i] - yol[o] >= s.tugunQadamM || j[i].t - j[o].t >= s.tugunMaksS { tugunIdx.append(i) }
        }
        if tugunIdx.last! != j.count - 1 { tugunIdx.append(j.count - 1) }

        func oyna(_ k: Int, _ yarim: Double, minSoni: Int) -> [Int] {
            var y = yarim
            while true {
                let r = j.indices.filter { abs(yol[$0] - yol[k]) <= y }
                let tarqoq: Bool = {
                    guard let a = r.first, let b = r.last else { return false }
                    return yol[b] - yol[a] >= 1.0
                }()
                if (r.count >= minSoni && tarqoq) || r.count == j.count { return r }
                y *= 1.5
            }
        }
        func burchakYaqin(_ a: Double) -> Double { psi0 + atan2(sin(a - psi0), cos(a - psi0)) }

        // 1) burilish har tugunda
        var psi: [Double] = []
        for k in tugunIdx {
            let r = oyna(k, s.burilishOynaM / 2, minSoni: 10)
            let g = try? Georeferens.gravitatsiyaBilan(mahalliyENU: r.map { j[$0].m }, global: r.map { j[$0].g }, minYoyilishM: 1.0)
            psi.append(burchakYaqin(g?.transformatsiya.burchak ?? psi0))
        }
        func psiVaqtda(_ t: Double) -> Double {
            if t <= j[tugunIdx[0]].t { return psi[0] }
            for q in 1..<tugunIdx.count where t <= j[tugunIdx[q]].t {
                let a = j[tugunIdx[q - 1]].t, b = j[tugunIdx[q]].t
                let u = (t - a) / max(b - a, 1e-9)
                return psi[q - 1] + (psi[q] - psi[q - 1]) * u
            }
            return psi[psi.count - 1]
        }

        // 2) siljish qoldiqlari va har tugunda mahalliy chiziqli regressiya (vaqt bo'yicha)
        let r: [Vektor3] = j.map { x in
            let p = psiVaqtda(x.t), c = cos(p), sn = sin(p)
            return x.g - Vektor3(c * x.m.x - sn * x.m.y, sn * x.m.x + c * x.m.y, x.m.z)
        }
        var tugunlar: [BolakliTugun] = []
        for (q, k) in tugunIdx.enumerated() {
            let w = oyna(k, s.siljishOynaM / 2, minSoni: 6)
            let t0 = j[k].t
            let n = Double(w.count)
            let tm = w.reduce(0) { $0 + (j[$1].t - t0) } / n
            let rm = w.reduce(Vektor3.nol) { $0 + r[$1] } / n
            var stt = 0.0
            var str = Vektor3.nol
            for i in w { let dt = j[i].t - t0 - tm; stt += dt * dt; str = str + (r[i] - rm) * dt }
            // t0 dagi qiymat: rm + qiyalik·(0 − tm)
            let a = stt > 1e-9 ? rm + (str / stt) * (-tm) : rm
            tugunlar.append(BolakliTugun(t: t0, burchak: psi[q], siljish: [a.x, a.y, a.z]))
        }

        let bg0 = BolakliGeoreferens(tugunlar: tugunlar, bolaklar: [], umumiy: umumiy, rmsH: 0, rmsV: 0)

        // 3) qoldiqlar, bo'laklar
        var h2 = 0.0, v2 = 0.0
        let qoldiq: [Vektor3] = j.map { bg0.qolla($0.m, vaqt: $0.t) - $0.g }
        for d in qoldiq { h2 += d.x * d.x + d.y * d.y; v2 += d.z * d.z }
        var bolaklar: [GeorefBolak] = []
        func bolakYasa(_ bosh: Int, _ oxir: Int) -> GeorefBolak {
            var bh = 0.0, bv = 0.0, mk = 0.0
            for i in bosh...oxir {
                let d = qoldiq[i]
                bh += d.x * d.x + d.y * d.y; bv += d.z * d.z; mk = max(mk, d.uzunlik)
            }
            let n = Double(oxir - bosh + 1)
            let rh = (bh / n).squareRoot(), rv = (bv / n).squareRoot()
            var sabab: String?
            if oxir - bosh + 1 < s.minJuftBolak { sabab = "RTK juftlari kam (\(oxir - bosh + 1))" }
            else if max(rh, rv) > s.chekM { sabab = String(format: "qoldiq %.1f sm > %.0f sm", max(rh, rv) * 100, s.chekM * 100) }
            return GeorefBolak(boshM: yol[bosh], oxirM: yol[oxir], boshT: j[bosh].t, oxirT: j[oxir].t, juftlar: oxir - bosh + 1,
                               rmsH: rh, rmsV: rv, maksM: mk, past: sabab != nil, sabab: sabab)
        }
        // bo'laklar: har `bolakM` yo'lda yoki RTK uzilishida yangisi; uzilishning o'zi — alohida PAST bo'lak
        var bosh = 0
        while bosh < j.count {
            var oxir = bosh
            let chegara = (floor(yol[bosh] / s.bolakM) + 1) * s.bolakM
            while oxir + 1 < j.count, yol[oxir + 1] < chegara, j[oxir + 1].t - j[oxir].t <= s.maksBoshliqS { oxir += 1 }
            var b = bolakYasa(bosh, oxir)
            // oxirgi kalta bo'lak (yarim bo'lakdan qisqa) oldingisiga qo'shiladi
            if oxir == j.count - 1, b.juftlar < s.minJuftBolak, let o = bolaklar.last, o.juftlar > 0,
               j[bosh].t - o.oxirT <= s.maksBoshliqS {
                let oBosh = j.firstIndex { $0.t >= o.boshT - 1e-9 } ?? bosh
                bolaklar.removeLast()
                b = bolakYasa(oBosh, oxir)
            }
            bolaklar.append(b)
            if oxir + 1 < j.count, j[oxir + 1].t - j[oxir].t > s.maksBoshliqS {
                let dt = j[oxir + 1].t - j[oxir].t
                bolaklar.append(GeorefBolak(boshM: yol[oxir], oxirM: yol[oxir + 1], boshT: j[oxir].t, oxirT: j[oxir + 1].t,
                                            juftlar: 0, rmsH: 0, rmsV: 0, maksM: 0, past: true,
                                            sabab: String(format: "RTK FIX uzilishi %.1f s", dt)))
            }
            bosh = oxir + 1
        }
        // vaqt bo'yicha tutash: oddiy bo'lak keyingisi boshigacha cho'ziladi (nuqta bo'shliqqa tushmasin)
        for k in 0..<(bolaklar.count - 1) where bolaklar[k].juftlar > 0 && bolaklar[k + 1].juftlar > 0 {
            bolaklar[k].oxirT = bolaklar[k + 1].boshT
        }
        let n = Double(j.count)
        return BolakliGeoreferens(tugunlar: tugunlar, bolaklar: bolaklar, umumiy: umumiy,
                                  rmsH: (h2 / n).squareRoot(), rmsV: (v2 / n).squareRoot())
    }
}
