import Foundation
import YerostiGeometriya

/// Skan nuqtasi. ARKit mesh uchlarida normal bor; professional skaner bulutida bo'lmasligi mumkin.
/// DS-07: nuqta rangi (sRGB, kamera tasviridan).
public struct Rang: Equatable, Hashable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
}

public struct BulutNuqtasi: Sendable {
    public var p: Vektor3
    public var n: Vektor3?
    /// DS-07: haqiqiy rang (bo'lmasa nil).
    public var rang: Rang?
    /// DS-06: nuqta kuzatilgan o'rtacha vaqt (uptime, s) — bo'lakli georeferens (DS-05) shu vaqt bilan qo'llanadi.
    public var t: Double?
    public init(_ p: Vektor3, n: Vektor3? = nil, rang: Rang? = nil, t: Double? = nil) {
        self.p = p; self.n = n; self.rang = rang; self.t = t
    }
}

public struct QuvurTopishSozlamalari: Sendable {
    /// Voksel o'lchami (m) — bulut shu qadamga siyraklashtiriladi.
    public var voksel: Double = 0.01
    /// "Yuqori" yo'nalish. ARKit: +y; UTM: +z.
    public var yuqori: Vektor3 = Vektor3(0, 1, 0)
    /// Nuqta silindr sirtiga shu masofada bo'lsa "ichki" hisoblanadi (LiDAR shovqini ~1 sm).
    public var chegara: Double = 0.012
    public var normalBurchakMaksGrad: Double = 25
    public var radiusMin: Double = 0.02
    public var radiusMax: Double = 0.45
    /// Quvur o'qining gorizontdan maksimal og'ishi.
    public var qiyalikMaksGrad: Double = 20
    public var minNuqta: Int = 150
    public var minUzunlik: Double = 0.4
    /// Ko'rinadigan yoyning uzluksiz qismi — tekislik/burchak soxta "silindr"larini to'sadi.
    public var minYoyGrad: Double = 90
    /// DS-06: LiDAR quvurni YUQORIDAN ko'radi — ichki nuqtalar o'rtacha yo'nalishining «yuqori» tashkil etuvchisi shundan
    /// kichik bo'lsa (nuqtalar asosan o'q ostida: tub va devor burchagi, chuqurcha) nomzod rad etiladi.
    public var minYuqoriUlush: Double = -0.25
    public var iteratsiya: Int = 1200
    public var maksQuvur: Int = 6
    public var baholashNamunasi: Int = 6000
    public var urug: UInt64 = 20_260_927
    /// Operator tanlagan tarmoq turi ("suv", "gaz", "issiqlik"...) — standart diametr qatorini tanlash uchun.
    public var tarmoqTuri: String?
    /// KU-05: Hough gipotezalari RANSAC gipotezalariga QO'SHIMCHA (ikkalasi bir xil qat'iy tekshiruvdan o'tadi).
    public var hough: Bool = true
    /// Mahalliy baho radiusi (m): 5 sm da DN32…DN500 quvur normallari yetarli yoyga tarqaladi.
    public var houghRadius: Double = 0.05
    /// Mahalliy baho hisoblanadigan urug' nuqtalar soni (deterministik tanlov).
    public var houghUrugSoni: Int = 4000
    public init() {}
}

public struct StandartDiametr: Equatable, Sendable {
    public let seriya: String
    public let tashqiMm: Double
}

/// K-02: tashqi diametrni standart qatorga bog'lash.
public enum StandartDiametrlar {
    /// PE / PVX quvurlar tashqi diametri (ISO 4427 / ISO 1452), mm.
    public static let pePvx: [Double] = [20, 25, 32, 40, 50, 63, 75, 90, 110, 125, 140, 160, 180, 200, 225, 250,
                                         280, 315, 355, 400, 450, 500, 560, 630]
    /// Po'lat quvurlar (GOST 10704 / issiqlik tarmoqlari), mm.
    public static let polat: [Double] = [57, 76, 89, 108, 133, 159, 219, 273, 325, 377, 426, 530]

    /// Tarmoq turiga mos qatorlar. Yangi suv/gaz/kanalizatsiya/kabel quvurlari asosan PE/PVX;
    /// issiqlik (PPU) — po'lat, lekin tashqi qobig'i PE bo'lishi mumkin, shuning uchun ikkalasi.
    public static func seriyalar(tarmoqTuri: String?) -> [(String, [Double])] {
        switch tarmoqTuri {
        case nil, "issiqlik": return [("PE/PVX", pePvx), ("Po'lat", polat)]
        default: return [("PE/PVX", pePvx)]
        }
    }

    public static func moslash(_ olchanganMm: Double, seriyalar: [(String, [Double])]? = nil) -> StandartDiametr? {
        let s = seriyalar ?? [("PE/PVX", pePvx), ("Po'lat", polat)]
        var eng: StandartDiametr?
        var engFarq = Double.infinity
        for (nomi, qator) in s {
            for d in qator {
                let farq = abs(d - olchanganMm)
                if farq < engFarq { engFarq = farq; eng = StandartDiametr(seriya: nomi, tashqiMm: d) }
            }
        }
        guard let e = eng, engFarq <= max(8, 0.06 * e.tashqiMm) else { return nil }
        return e
    }
}

public struct QuvurSegmenti: Equatable, Sendable {
    public var bosh: Vektor3
    public var oxir: Vektor3
    public var yonalish: Vektor3
    public var radius: Double
    public var rms: Double
    public var nuqtaSoni: Int
    public var yoyGrad: Double
    public var uzunlik: Double { bosh.masofa(oxir) }
}

public struct ChuqurlikStansiyasi: Equatable, Sendable {
    public let nuqta: Vektor3
    public let chuqurlikM: Double
}

public struct TopilganQuvur: Sendable {
    /// O'q chizig'i (markaz) — nishabga qarab yuqoridan pastga yo'naltirilgan.
    public var oq: [Vektor3]
    public var radius: Double
    public var tashqiDiametrMm: Double
    public var standart: StandartDiametr?
    /// Oqim yo'nalishidagi o'rtacha nishab, % (≥ 0).
    public var qiyalikFoiz: Double
    /// Yer sirtidan quvur ustigacha (skan bo'yicha taxmin). Yer sirti skanda yetarli bo'lmasa nil.
    public var qoplamaChuqurligiM: Double?
    public var chuqurlikStansiyalari: [ChuqurlikStansiyasi]
    public var uzunlikM: Double
    public var nuqtaSoni: Int
    public var yoyGrad: Double
    public var rmsM: Double
    /// 0…1 — evristik ishonch (yoy, qoldiq, uzunlik). Ehtimollik emas.
    public var ishonch: Double
    public var muftalar: [Vektor3]
    public var segmentlar: [QuvurSegmenti]
}

/// K-01…K-04, KU-05: LiDAR/fotogrammetriya bulutidan quvurlarni avtomatik ajratish.
/// Gipotezalar ikki manbadan: yo'naltirilgan nuqta juftlari (RANSAC, Schnabel 2007) va Hough ovozi
/// (Rabbani & van den Heuvel 2005 tamoyili: o'q yo'nalishi Gauss sferasida, so'ng kesimda markaz va radius) →
/// Levenberg–Marquardt geometrik aniqlashtirish → uzluksiz yoy va uzunlik tekshiruvi →
/// segmentlarni polilinyaga ulash → standart diametr, nishab, qoplama chuqurligi, mufta nomzodlari.
public final class QuvurTopish {
    public let s: QuvurTopishSozlamalari
    private var P: [Vektor3] = []
    private var N: [Vektor3] = []
    private var faol: [Bool] = []
    private var tasodif: Tasodifiy
    private var panjara: Panjara!
    private let yuqori: Vektor3
    private var mahalliy: [MahalliyBaho] = []

    public init(_ sozlamalar: QuvurTopishSozlamalari = QuvurTopishSozlamalari()) {
        s = sozlamalar
        tasodif = Tasodifiy(urug: sozlamalar.urug)
        yuqori = sozlamalar.yuqori.birlik ?? Vektor3(0, 1, 0)
    }

    // MARK: - Asosiy kirish

    /// Barcha quvurlarni topadi. `urugNuqta` berilsa (operator ekranda quvurni bosgan joy) —
    /// faqat shu nuqtaga eng yaqin quvurni qaytaradi.
    public func topish(_ nuqtalar: [BulutNuqtasi], urugNuqta: Vektor3? = nil) -> [TopilganQuvur] {
        tayyorla(nuqtalar)
        guard P.count >= s.minNuqta else { return [] }
        if let u = urugNuqta {
            for k in 0..<P.count where P[k].masofa(u) > 1.5 { faol[k] = false }
        }
        var segmentlar: [QuvurSegmenti] = []
        var segmentIchki: [[Int]] = []
        for _ in 0..<(s.maksQuvur * 2) {
            guard let (seg, ichki) = keyingiSegment() else { break }
            for k in ichki { faol[k] = false }
            // KU-05: ikki quvur bitta hajmni egallay olmaydi — topilgan quvur ichidagi yoki uni o'rab olgan o'qdosh
            // "quvur" (kuchli shovqinda ichki/tashqi qobiq) rad etiladi
            if segmentlar.contains(where: { ustmaUst($0, seg) }) { continue }
            segmentlar.append(seg)
            segmentIchki.append(ichki)
            qobiqniOchir(seg)
        }
        var quvurlar = zanjirla(segmentlar).map { quvurYasa($0) }
        quvurlar.sort { $0.nuqtaSoni > $1.nuqtaSoni }
        if let u = urugNuqta {
            let yaqin = quvurlar.min { sirtMasofa(u, $0) < sirtMasofa(u, $1) }
            if let q = yaqin, sirtMasofa(u, q) < 3 * s.chegara + 0.02 { return [q] }
            return []
        }
        return Array(quvurlar.prefix(s.maksQuvur))
    }

    // MARK: - Tayyorlash: voksel + normallar

    private func tayyorla(_ nuqtalar: [BulutNuqtasi]) {
        var yig: [Panjara.Kalit: (p: Vektor3, n: Vektor3, sn: Int, k: Int)] = [:]
        yig.reserveCapacity(nuqtalar.count)
        for b in nuqtalar {
            let kl = Panjara.kalit(b.p, s.voksel)
            var e = yig[kl] ?? (p: Vektor3.nol, n: Vektor3.nol, sn: 0, k: 0)
            e.p += b.p
            e.k += 1
            if let n = b.n?.birlik {
                let yo = (e.sn > 0 && e.n.nuqta(n) < 0) ? -n : n
                e.n += yo
                e.sn += 1
            }
            yig[kl] = e
        }
        let kalitlar = yig.keys.sorted { ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z) }  // deterministik tartib
        P = []; P.reserveCapacity(kalitlar.count)
        var nq: [Vektor3?] = []; nq.reserveCapacity(kalitlar.count)
        for kl in kalitlar {
            let e = yig[kl]!
            P.append(e.p / Double(e.k))
            nq.append(e.sn > 0 ? e.n.birlik : nil)
        }
        let yetishmaydi = nq.contains { $0 == nil }
        if yetishmaydi {
            let hisoblangan = normallarniBahola(radius: max(0.03, 3 * s.voksel))
            N = (0..<P.count).map { nq[$0] ?? hisoblangan[$0] }
        } else {
            N = nq.map { $0! }
        }
        faol = [Bool](repeating: true, count: P.count)
        panjara = Panjara(P, kat: 0.1)
        mahalliyBaholar()
    }

    private func normallarniBahola(radius: Double) -> [Vektor3] {
        let pj = Panjara(P, kat: radius)
        let r2 = radius * radius
        var natija = [Vektor3](repeating: yuqori, count: P.count)
        var qoshni: [Int] = []
        for i in 0..<P.count {
            qoshni.removeAll(keepingCapacity: true)
            pj.atrofda(P[i], radius: radius) { j in if (P[j] - P[i]).uzunlik2 <= r2 { qoshni.append(j) } }
            guard qoshni.count >= 5 else { continue }
            var mark = Vektor3.nol
            for j in qoshni { mark += P[j] }
            mark = mark / Double(qoshni.count)
            var m = Matritsa3.nol
            for j in qoshni { m.tashqiQosh(P[j] - mark) }
            natija[i] = m.xosTahlil()[0].vektor
        }
        return natija
    }

    // MARK: - Silindr modeli

    struct Silindr { var c: Vektor3; var a: Vektor3; var r: Double }

    @inline(__always)
    private func radial(_ p: Vektor3, _ m: Silindr) -> (v: Vektor3, d: Double, t: Double) {
        let d = p - m.c
        let t = d.nuqta(m.a)
        let v = d - m.a * t
        return (v, v.uzunlik, t)
    }

    private var cosMin: Double { cos(s.normalBurchakMaksGrad * .pi / 180) }

    @inline(__always)
    private func ichkimi(_ k: Int, _ m: Silindr, chegara: Double) -> Bool {
        let (v, d, _) = radial(P[k], m)
        guard d > 1e-9, abs(d - m.r) < chegara else { return false }
        return abs(N[k].nuqta(v / d)) >= cosMin
    }

    private func gipoteza(_ i: Int, _ j: Int) -> Silindr? {
        let n1 = N[i], n2 = N[j]
        let kr = n1.kross(n2)
        guard kr.uzunlik > sin(10 * .pi / 180), let a = kr.birlik else { return nil }
        guard abs(a.nuqta(yuqori)) <= sin(s.qiyalikMaksGrad * .pi / 180) else { return nil }
        let (e1, e2) = a.perpendikulyarBazis()
        let q1x = P[i].nuqta(e1), q1y = P[i].nuqta(e2), q2x = P[j].nuqta(e1), q2y = P[j].nuqta(e2)
        let m1x = n1.nuqta(e1), m1y = n1.nuqta(e2), m2x = n2.nuqta(e1), m2y = n2.nuqta(e2)
        let det = -m1x * m2y + m2x * m1y
        guard abs(det) > 1e-6 else { return nil }
        let dx = q2x - q1x, dy = q2y - q1y
        let t = (-dx * m2y + m2x * dy) / det
        let cx = q1x + t * m1x, cy = q1y + t * m1y
        let r1 = ((q1x - cx) * (q1x - cx) + (q1y - cy) * (q1y - cy)).squareRoot()
        let r2 = ((q2x - cx) * (q2x - cx) + (q2y - cy) * (q2y - cy)).squareRoot()
        guard abs(r1 - r2) < s.chegara else { return nil }
        let r = (r1 + r2) / 2
        guard r >= s.radiusMin, r <= s.radiusMax else { return nil }
        return Silindr(c: e1 * cx + e2 * cy + a * P[i].nuqta(a), a: a, r: r)
    }

    // MARK: - RANSAC → aniqlashtirish → tekshiruv

    private func keyingiSegment() -> (QuvurSegmenti, [Int])? {
        let hovuz = (0..<P.count).filter { faol[$0] }
        guard hovuz.count >= s.minNuqta else { return nil }
        let namuna: [Int] = hovuz.count <= s.baholashNamunasi ? hovuz
            : (0..<s.baholashNamunasi).map { _ in hovuz[Int(tasodif.next() % UInt64(hovuz.count))] }
        var eng: [(ball: Int, m: Silindr)] = []
        for _ in 0..<s.iteratsiya {
            let i = hovuz[Int(tasodif.next() % UInt64(hovuz.count))]
            guard let j = juftTanla(i), let m = gipoteza(i, j) else { continue }
            var ichkiN: [Int] = []
            for k in namuna where ichkimi(k, m, chegara: s.chegara) { ichkiN.append(k) }
            let ball = ichkiN.count
            guard ball >= 8, uzluksizYoy(ichkiN, m) >= 0.7 * s.minYoyGrad else { continue }
            // DS-06: o'q ostidan ko'ringan «silindr» (botiq burchak) eng yaxshi 6 talikni egallamasin
            guard yuqoridanKorinadi(ichkiN, m) else { continue }
            // Bir xil silindrning nusxalarini saqlamaymiz
            if let x = eng.firstIndex(where: { oxshash($0.m, m) }) {
                if eng[x].ball < ball { eng[x] = (ball, m) }
            } else {
                eng.append((ball, m))
            }
            eng.sort { $0.ball > $1.ball }
            if eng.count > 6 { eng.removeLast() }
        }
        var tanlangan: (QuvurSegmenti, [Int])?
        for g in eng {
            guard let natija = tekshir(g.m, hovuz: hovuz) else { continue }
            if tanlangan == nil || natija.1.count > tanlangan!.1.count { tanlangan = natija }
        }
        if s.hough {
            for m in houghGipotezalari() {
                guard let natija = tekshir(m, hovuz: hovuz) else { continue }
                if tanlangan == nil || natija.1.count > tanlangan!.1.count { tanlangan = natija }
            }
        }
        return tanlangan
    }

    // MARK: - KU-05: fizik cheklov — quvurlar bir-birining ichida bo'lmaydi

    /// Ikki segment hajmi kesishadimi: birining o'qi (uchlaridan max(2r, 10 sm) ichkarida, 2 sm qadam) namunalarining
    /// yarmidan ko'pi ikkinchisining ichidan o'tsa. Burilishdagi qo'shni segmentlar uchlari bilan tutashadi — ular o'tadi.
    private func ustmaUst(_ a: QuvurSegmenti, _ b: QuvurSegmenti) -> Bool {
        func ichida(_ x: QuvurSegmenti, _ y: QuvurSegmenti) -> Bool {
            let m = max(2 * y.radius, 0.10), L = y.uzunlik
            let namuna: [Double] = L > 2 * m ? Array(stride(from: m, through: L - m, by: 0.02)) : [L / 2]
            var ichki = 0
            for t in namuna {
                let d = y.bosh + y.yonalish * t - x.bosh
                let tx = d.nuqta(x.yonalish)
                guard tx >= 0, tx <= x.uzunlik else { continue }
                if (d - x.yonalish * tx).uzunlik < x.radius + 0.5 * y.radius { ichki += 1 }
            }
            return 2 * ichki > namuna.count
        }
        return ichida(a, b) || ichida(b, a)
    }

    /// Qabul qilingan segment atrofidagi shovqin qobig'i (|d − r| ≤ max(chegara, 3·rms), uchlaridan 2 sm gacha)
    /// keyingi qidiruvga kirmaydi.
    private func qobiqniOchir(_ seg: QuvurSegmenti) {
        let band = max(s.chegara, 3 * seg.rms)
        let m = Silindr(c: seg.bosh, a: seg.yonalish, r: seg.radius)
        let L = seg.uzunlik
        for k in 0..<P.count where faol[k] {
            let (_, d, t) = radial(P[k], m)
            if t >= -0.02, t <= L + 0.02, abs(d - m.r) <= band { faol[k] = false }
        }
    }

    // MARK: - KU-05: Hough gipotezalari

    /// Urug' nuqtadagi mahalliy silindr bahosi. O'q — atrofdagi normallar tarqoqlik matritsasining eng kichik xos
    /// vektori: silindrda hamma normal o'qqa tik (Gauss sferasida katta aylana). Tekislikda normallar tarqalmaydi
    /// (μ1 ≈ 0), tartibsiz axlatda hamma tomonga tarqaladi (μ0 katta) — ikkalasi ham ovoz bermaydi.
    /// Markaz — kesim tekisligida normal chiziqlariga eng yaqin nuqta (kichik kvadratlar), radius — masofalar medianasi.
    struct MahalliyBaho { var k: Int; var a: Vektor3; var c: Vektor3; var r: Double }

    private func mahalliyBaholar() {
        mahalliy = []
        guard s.hough, P.count >= s.minNuqta else { return }
        let rho = s.houghRadius, rho2 = rho * rho
        let pj = Panjara(P, kat: rho)
        var t = Tasodifiy(urug: s.urug ^ 0x4B55_0005_4855_4748)   // RANSAC ketma-ketligiga tegmaydi
        var urug: [Int] = []
        if P.count <= s.houghUrugSoni {
            urug = Array(0..<P.count)
        } else {
            var bor = Set<Int>()
            while urug.count < s.houghUrugSoni {
                let k = Int(t.next() % UInt64(P.count))
                if bor.insert(k).inserted { urug.append(k) }
            }
        }
        let sinQiya = sin(s.qiyalikMaksGrad * .pi / 180)
        var qoshni: [Int] = []
        var masofa: [Double] = []
        for i in urug {
            qoshni.removeAll(keepingCapacity: true)
            pj.atrofda(P[i], radius: rho) { j in if (P[j] - P[i]).uzunlik2 <= rho2 { qoshni.append(j) } }
            guard qoshni.count >= 12 else { continue }
            var M = Matritsa3.nol
            for j in qoshni { M.tashqiQosh(N[j]) }
            let x = M.xosTahlil()
            let iz = x[0].qiymat + x[1].qiymat + x[2].qiymat
            guard iz > 0 else { continue }
            let mu0 = x[0].qiymat / iz, mu1 = x[1].qiymat / iz
            guard mu1 >= 0.01, mu0 <= 0.35 * mu1, let a = x[0].vektor.birlik, abs(a.nuqta(yuqori)) <= sinQiya else { continue }
            let (e1, e2) = a.perpendikulyarBazis()
            var a11 = 0.0, a12 = 0.0, a22 = 0.0, b1 = 0.0, b2 = 0.0, soni = 0.0
            for j in qoshni {
                let nx = N[j].nuqta(e1), ny = N[j].nuqta(e2)
                let l = (nx * nx + ny * ny).squareRoot()
                guard l > 0.8 else { continue }
                let mx = nx / l, my = ny / l
                let px = P[j].nuqta(e1), py = P[j].nuqta(e2)
                let q11 = 1 - mx * mx, q12 = -mx * my, q22 = 1 - my * my
                a11 += q11; a12 += q12; a22 += q22
                b1 += q11 * px + q12 * py; b2 += q12 * px + q22 * py
                soni += 1
            }
            let det = a11 * a22 - a12 * a12
            guard soni >= 10, det > 0.005 * soni * soni else { continue }
            let cx = (a22 * b1 - a12 * b2) / det, cy = (a11 * b2 - a12 * b1) / det
            masofa.removeAll(keepingCapacity: true)
            for j in qoshni {
                let dx = P[j].nuqta(e1) - cx, dy = P[j].nuqta(e2) - cy
                masofa.append((dx * dx + dy * dy).squareRoot())
            }
            masofa.sort()
            let r = masofa[masofa.count / 2]
            guard r >= s.radiusMin, r <= s.radiusMax else { continue }
            var og = masofa.map { abs($0 - r) }
            og.sort()
            guard og[og.count / 2] <= s.chegara else { continue }
            mahalliy.append(MahalliyBaho(k: i, a: a, c: e1 * cx + e2 * cy + a * P[i].nuqta(a), r: r))
        }
    }

    /// Ovoz: faol urug'lar o'q yo'nalishiga (gorizontal belbog', 2° katak, 3×3 oyna) ovoz beradi; har cho'qqida
    /// kesim tekisligida markaz (1,5 sm) va radius (1 sm) bo'yicha ikkinchi ovoz (3×3×3 oyna). Lug'at tartibiga
    /// bog'liq emas (kalitlar saralanadi) — telefon va server bir xil gipotezalarni oladi.
    func houghGipotezalari(maks: Int = 8) -> [Silindr] {
        var qolgan = mahalliy.filter { faol[$0.k] }
        guard qolgan.count >= 8 else { return [] }
        let (h1, h2) = yuqori.perpendikulyarBazis()
        let qadam = 2.0 * Double.pi / 180
        let nAz = 90
        let elMaks = s.qiyalikMaksGrad * .pi / 180
        let nEl = Int((2 * elMaks / qadam).rounded(.up)) + 1
        func katak(_ a: Vektor3) -> Int {
            var v = a
            var az = atan2(v.nuqta(h2), v.nuqta(h1))
            if az < 0 { v = -v; az += .pi }
            let el = asin(max(-1, min(1, v.nuqta(yuqori))))
            let ia = min(nAz - 1, max(0, Int(az / qadam)))
            let ie = min(nEl - 1, max(0, Int((el + elMaks) / qadam)))
            return ia * nEl + ie
        }
        func oyna(_ k: Int) -> [Int] {   // azimut aylanadi; 0↔179° chegarasida balandlik teskari
            let ia = k / nEl, ie = k % nEl
            var r: [Int] = []
            for da in -1...1 {
                var a2 = ia + da, e0 = ie
                if a2 < 0 { a2 += nAz; e0 = nEl - 1 - ie } else if a2 >= nAz { a2 -= nAz; e0 = nEl - 1 - ie }
                for de in -1...1 where e0 + de >= 0 && e0 + de < nEl { r.append(a2 * nEl + e0 + de) }
            }
            return r
        }
        var natija: [Silindr] = []
        for _ in 0..<4 where natija.count < maks && qolgan.count >= 8 {
            var kataklar = [[Int]](repeating: [], count: nAz * nEl)
            for (x, b) in qolgan.enumerated() { kataklar[katak(b.a)].append(x) }
            var engSoni = 0, engK = -1
            for k in 0..<(nAz * nEl) where !kataklar[k].isEmpty {
                let soni = oyna(k).reduce(0) { $0 + kataklar[$1].count }
                if soni > engSoni { engSoni = soni; engK = k }
            }
            guard engSoni >= 8 else { break }
            var S = Matritsa3.nol
            for k in oyna(engK) { for x in kataklar[k] { S.tashqiQosh(qolgan[x].a) } }
            guard let d = S.xosTahlil()[2].vektor.birlik else { break }
            let cosTol = cos(5 * Double.pi / 180)
            let azolar = (0..<qolgan.count).filter { abs(qolgan[$0].a.nuqta(d)) >= cosTol }
            // kesim tekisligida markaz + radius ovozi
            let (f1, f2) = d.perpendikulyarBazis()
            let kq = 0.015, rq = 0.01
            struct K3: Hashable, Comparable {
                let u: Int, v: Int, r: Int
                static func < (a: K3, b: K3) -> Bool { (a.u, a.v, a.r) < (b.u, b.v, b.r) }
            }
            var guruh: [K3: [Int]] = [:]
            for x in azolar {
                let b = qolgan[x]
                guruh[K3(u: Int((b.c.nuqta(f1) / kq).rounded(.down)), v: Int((b.c.nuqta(f2) / kq).rounded(.down)),
                         r: Int((b.r / rq).rounded(.down))), default: []].append(x)
            }
            var bosh = Set(azolar)
            let kalitlar = guruh.keys.sorted()
            for _ in 0..<3 where natija.count < maks {
                var engS = 0
                var engA: [Int] = []
                for kl in kalitlar {
                    var a: [Int] = []
                    for du in -1...1 { for dv in -1...1 { for dr in -1...1 {
                        if let l = guruh[K3(u: kl.u + du, v: kl.v + dv, r: kl.r + dr)] { a.append(contentsOf: l.filter { bosh.contains($0) }) }
                    } } }
                    if a.count > engS { engS = a.count; engA = a }
                }
                guard engS >= 6 else { break }
                func median(_ q: [Double]) -> Double { let t = q.sorted(); return t[t.count / 2] }
                let u = median(engA.map { qolgan[$0].c.nuqta(f1) }), v = median(engA.map { qolgan[$0].c.nuqta(f2) })
                let tt = median(engA.map { qolgan[$0].c.nuqta(d) })
                let r = median(engA.map { qolgan[$0].r })
                natija.append(Silindr(c: f1 * u + f2 * v + d * tt, a: d, r: r))
                for x in engA { bosh.remove(x) }
            }
            let azoSet = Set(azolar)
            qolgan = (0..<qolgan.count).filter { !azoSet.contains($0) }.map { qolgan[$0] }
        }
        return natija
    }

    /// Sinov uchun tashxis: berilgan silindr `tekshir` ning qaysi bosqichida to'xtaydi.
    func tashxis(_ nuqtalar: [BulutNuqtasi], c: Vektor3, a: Vektor3, r: Double) -> String {
        tayyorla(nuqtalar)
        let hovuz = Array(0..<P.count)
        var m = Silindr(c: c, a: a, r: r)
        var log: [String] = []
        var ichki = hovuz.filter { ichkimi($0, m, chegara: s.chegara) }
        let geom = hovuz.filter { let (_, d, _) = radial(P[$0], m); return abs(d - m.r) < s.chegara }
        log.append("geom \(geom.count) ichki(normal bilan) \(ichki.count)")
        for q in 0..<3 {
            ichki = hovuz.filter { ichkimi($0, m, chegara: s.chegara) }
            m = aniqlashtir(m, ichki)
            log.append(String(format: "LM%d: n=%d r=%.4f c=(%.3f,%.3f,%.3f)", q, ichki.count, m.r, m.c.x, m.c.y, m.c.z))
        }
        ichki = hovuz.filter { ichkimi($0, m, chegara: s.chegara) }
        let ka = kesimBoyichaAjrat(ichki, m)
        log.append("kesim: \(ka?.count ?? -1)")
        if let ka {
            log.append("yoy \(uzluksizYoy(ka, m)) yuqori \(yuqoridanKorinadi(ka, m))")
            let (e1, e2) = m.a.perpendikulyarBazis()
            var sav = [Int](repeating: 0, count: 72)
            for k in ka {
                let v = radial(P[k], m).v
                var b = atan2(v.nuqta(e2), v.nuqta(e1)) * 180 / .pi
                if b < 0 { b += 360 }
                sav[min(71, Int(b / 5))] += 1
            }
            log.append("e1=(\(String(format: "%.2f,%.2f,%.2f", e1.x, e1.y, e1.z))) e2=(\(String(format: "%.2f,%.2f,%.2f", e2.x, e2.y, e2.z))) savat: " + sav.enumerated().filter { $0.element > 0 }.map { "\($0.offset * 5):\($0.element)" }.joined(separator: " "))
        }
        if let natija = tekshir(Silindr(c: c, a: a, r: r), hovuz: hovuz) {
            log.append(String(format: "TEKSHIR OK r=%.4f n=%d yoy %.0f", natija.0.radius, natija.1.count, natija.0.yoyGrad))
        } else { log.append("TEKSHIR rad") }
        return log.joined(separator: " | ")
    }

    /// Sinov uchun: Hough gipotezalari (tekshiruvsiz).
    func houghSinov(_ nuqtalar: [BulutNuqtasi]) -> [Silindr] {
        tayyorla(nuqtalar)
        return houghGipotezalari()
    }

    private func oxshash(_ a: Silindr, _ b: Silindr) -> Bool {
        guard abs(a.a.nuqta(b.a)) > cos(5 * .pi / 180), abs(a.r - b.r) < 0.02 else { return false }
        let (v, _, _) = radial(b.c, Silindr(c: a.c, a: a.a, r: a.r))
        return v.uzunlik < 0.03
    }

    private func juftTanla(_ i: Int) -> Int? {
        var tanlov: Int?
        var soni = 0
        panjara.atrofda(P[i], radius: 0.25) { j in
            guard faol[j], j != i else { return }
            let d = P[j].masofa(P[i])
            guard d >= 0.02, d <= 0.25 else { return }
            soni += 1
            if tasodif.next() % UInt64(soni) == 0 { tanlov = j }  // rezervuar tanlov
        }
        return tanlov
    }

    private func tekshir(_ boshlangich: Silindr, hovuz: [Int]) -> (QuvurSegmenti, [Int])? {
        var m = boshlangich
        var ichki: [Int] = []
        for _ in 0..<3 {
            ichki = hovuz.filter { ichkimi($0, m, chegara: s.chegara) }
            guard ichki.count >= s.minNuqta / 2 else { return nil }
            m = aniqlashtir(m, ichki)
            guard m.r >= s.radiusMin, m.r <= s.radiusMax,
                  abs(m.a.nuqta(yuqori)) <= sin(s.qiyalikMaksGrad * .pi / 180) else { return nil }
        }
        ichki = hovuz.filter { ichkimi($0, m, chegara: s.chegara) }
        guard let dastlabki = kesimBoyichaAjrat(ichki, m) else { return nil }
        m = aniqlashtir(m, dastlabki)
        ichki = hovuz.filter { ichkimi($0, m, chegara: s.chegara) }
        guard let yakuniy = kesimBoyichaAjrat(ichki, m) else { return nil }
        m = aniqlashtir(m, yakuniy)
        let t = yakuniy.map { radial(P[$0], m).t }.sorted()
        let tBosh = t[Int(Double(t.count - 1) * 0.01)], tOxir = t[Int(Double(t.count - 1) * 0.99)]
        guard tOxir - tBosh >= s.minUzunlik else { return nil }
        let yoy = uzluksizYoy(yakuniy, m)
        guard yoy >= s.minYoyGrad else { return nil }
        guard yuqoridanKorinadi(yakuniy, m) else { return nil }
        let rms = (yakuniy.reduce(0) { a, k in let d = radial(P[k], m).d - m.r; return a + d * d } / Double(yakuniy.count)).squareRoot()
        let seg = QuvurSegmenti(bosh: m.c + m.a * tBosh, oxir: m.c + m.a * tOxir, yonalish: m.a, radius: m.r,
                                rms: rms, nuqtaSoni: yakuniy.count, yoyGrad: yoy)
        return (seg, yakuniy)
    }

    /// O'q bo'ylab 5 sm lik kesimlar. Kesim "quvur kesimi" hisoblanadi, agar undagi nuqtalar kamida 90° yoyni
    /// (6 ta 15° sektor) egallasa. Quvur yotgan tub yoki yonidagi devor o'qqa tegib turgan tasma hosil qiladi —
    /// u faqat bitta tor burchakda bo'ladi va quvur tugagan joydan keyin ham davom etadi; bu tekshiruv uni kesadi.
    /// Uzluksiz quvur kesimlari (≤ 25 sm bo'shliq kechiriladi) ichidan eng ko'p nuqtali qism olinadi.
    private func kesimBoyichaAjrat(_ ichki: [Int], _ m: Silindr) -> [Int]? {
        guard !ichki.isEmpty else { return nil }
        let (e1, e2) = m.a.perpendikulyarBazis()
        let q = 0.05
        // DS-06: sektor kengligi vokselning burchak o'lchamidan kichik bo'lmasin (Ø63 da 1 sm voksel ≈ 18°) — aks holda
        // to'rga tushgan bulutda bo'sh «taroq» sektorlar paydo bo'ladi
        let sw = max(15.0, s.voksel / max(m.r, 1e-6) * 180 / .pi)
        let ns = max(4, min(24, Int(360 / sw)))
        let kerak = Int((90 / (360 / Double(ns))).rounded(.up))
        let tlar: [(k: Int, t: Double, sektor: Int)] = ichki.map { k in
            let (v, _, t) = radial(P[k], m)
            var b = atan2(v.nuqta(e2), v.nuqta(e1)) * 180 / .pi
            if b < 0 { b += 360 }
            return (k, t, min(ns - 1, Int(b / (360 / Double(ns)))))
        }
        let tMin = tlar.map { $0.t }.min()!, tMax = tlar.map { $0.t }.max()!
        let n = Int((tMax - tMin) / q) + 1
        var niqob = [UInt32](repeating: 0, count: n)
        var soni = [Int](repeating: 0, count: n)
        for x in tlar {
            let i = min(n - 1, Int((x.t - tMin) / q))
            niqob[i] |= 1 << UInt32(x.sektor)
            soni[i] += 1
        }
        let yaroqli = niqob.map { $0.nonzeroBitCount >= kerak }
        var engBosh = -1, engOxir = -1, engSoni = 0
        var i = 0
        while i < n {
            guard yaroqli[i] else { i += 1; continue }
            var oxirgi = i
            var k = i + 1
            while k < n {
                if yaroqli[k] { oxirgi = k } else if k - oxirgi > 5 { break }
                k += 1
            }
            let jami = soni[i...oxirgi].reduce(0, +)
            if jami > engSoni { engSoni = jami; engBosh = i; engOxir = oxirgi }
            i = oxirgi + 1
        }
        guard engBosh >= 0 else { return nil }
        let t0 = tMin + Double(engBosh) * q, t1 = tMin + Double(engOxir + 1) * q
        let natija = tlar.filter { $0.t >= t0 && $0.t < t1 }.map { $0.k }
        return natija.count >= s.minNuqta ? natija : nil
    }

    /// DS-06: ichki nuqtalarning o'qdan o'rtacha birlik yo'nalishi «yuqori»ga qaraganmi. Botiq burchakka chizilgan silindr
    /// nuqtalari pastda (tub) va yonda (devor) — o'rtacha yo'nalish pastga qaraydi; haqiqiy quvurning ustki yoyi ko'rinadi.
    private func yuqoridanKorinadi(_ ichki: [Int], _ m: Silindr) -> Bool {
        var y = Vektor3.nol
        for k in ichki { if let b = radial(P[k], m).v.birlik { y = y + b } }
        guard let o = (y / Double(max(ichki.count, 1))).birlik else { return true }
        return o.nuqta(yuqori) >= s.minYuqoriUlush
    }

    /// Eng uzun uzluksiz ko'rinadigan yoy (gradus): 5° lik 72 savatcha, yakka bo'sh savatcha yopiladi.
    private func uzluksizYoy(_ ichki: [Int], _ m: Silindr) -> Double {
        let (e1, e2) = m.a.perpendikulyarBazis()
        // savatcha: 5° yoki vokselning burchak o'lchami (kichik quvurda 1 sm voksel 5° dan katta yoyni egallaydi)
        let w = max(5.0, s.voksel / max(m.r, 1e-6) * 180 / .pi)
        let nb = max(8, min(72, Int(360 / w)))
        let kw = 360 / Double(nb)
        var sav = [Int](repeating: 0, count: nb)
        for k in ichki {
            let v = radial(P[k], m).v
            var burchak = atan2(v.nuqta(e2), v.nuqta(e1)) * 180 / .pi
            if burchak < 0 { burchak += 360 }
            sav[min(nb - 1, Int(burchak / kw))] += 1
        }
        let chek = max(2, Int(Double(ichki.count) / (5.5 * Double(nb))))
        let band = sav.map { $0 >= chek }
        let yopiq = (0..<nb).map { i in band[i] || (band[(i + nb - 1) % nb] && band[(i + 1) % nb]) }
        if yopiq.allSatisfy({ $0 }) { return 360 }
        let bosh = yopiq.firstIndex(of: false)!
        var eng = 0, joriy = 0
        for q in 1...nb {
            if yopiq[(bosh + q) % nb] { joriy += 1; eng = max(eng, joriy) } else { joriy = 0 }
        }
        return Double(eng) * kw
    }

    /// Levenberg–Marquardt: parametrlar (α, β — yo'nalish burilishi, u, v — o'q siljishi, r).
    private func aniqlashtir(_ m0: Silindr, _ ichki: [Int]) -> Silindr {
        var idx = ichki
        if idx.count > 4000 {
            var t = Tasodifiy(urug: 7)
            idx = (0..<4000).map { _ in ichki[Int(t.next() % UInt64(ichki.count))] }
        }
        guard idx.count >= 10 else { return m0 }
        var g = Vektor3.nol
        for k in idx { g += P[k] }
        g = g / Double(idx.count)
        let a0 = m0.a
        let c0 = m0.c + a0 * (g - m0.c).nuqta(a0)
        let (e1, e2) = a0.perpendikulyarBazis()
        func model(_ th: [Double]) -> Silindr {
            let a = (a0 + e1 * th[0] + e2 * th[1]).birlik ?? a0
            return Silindr(c: c0 + e1 * th[2] + e2 * th[3], a: a, r: m0.r + th[4])
        }
        func qoldiq(_ th: [Double]) -> [Double] {
            let m = model(th)
            return idx.map { radial(P[$0], m).d - m.r }
        }
        var th = [Double](repeating: 0, count: 5)
        var f = qoldiq(th)
        var narx = f.reduce(0) { $0 + $1 * $1 }
        var lam = 1e-3
        for _ in 0..<30 {
            let h = 1e-7
            var J = [[Double]](repeating: [Double](repeating: 0, count: 5), count: idx.count)
            for p in 0..<5 {
                var t2 = th; t2[p] += h
                let f2 = qoldiq(t2)
                for i in 0..<idx.count { J[i][p] = (f2[i] - f[i]) / h }
            }
            var A = [[Double]](repeating: [Double](repeating: 0, count: 5), count: 5)
            var b = [Double](repeating: 0, count: 5)
            for i in 0..<idx.count {
                for p in 0..<5 {
                    b[p] -= J[i][p] * f[i]
                    for q in 0..<5 { A[p][q] += J[i][p] * J[i][q] }
                }
            }
            var yaxshilandi = false
            for _ in 0..<8 {
                var Al = A
                for p in 0..<5 { Al[p][p] += lam * max(A[p][p], 1e-12) }
                guard let d = yech5(Al, b) else { lam *= 10; continue }
                let yangi = zip(th, d).map { $0 + $1 }
                let fy = qoldiq(yangi)
                let ny = fy.reduce(0) { $0 + $1 * $1 }
                if ny < narx {
                    th = yangi; f = fy
                    let kamaydi = narx - ny
                    narx = ny; lam = max(lam / 3, 1e-9); yaxshilandi = true
                    if kamaydi < 1e-12 * max(narx, 1e-12) { return model(th) }
                    break
                }
                lam *= 4
            }
            if !yaxshilandi { break }
        }
        return model(th)
    }

    private func yech5(_ A0: [[Double]], _ b0: [Double]) -> [Double]? {
        var A = A0, b = b0
        let n = b.count
        for c in 0..<n {
            var piv = c
            for r in (c + 1)..<n where abs(A[r][c]) > abs(A[piv][c]) { piv = r }
            guard abs(A[piv][c]) > 1e-300 else { return nil }
            A.swapAt(c, piv); b.swapAt(c, piv)
            for r in (c + 1)..<n {
                let k = A[r][c] / A[c][c]
                for q in c..<n { A[r][q] -= k * A[c][q] }
                b[r] -= k * b[c]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = b[r]
            for q in (r + 1)..<n { s -= A[r][q] * x[q] }
            x[r] = s / A[r][r]
        }
        return x
    }

    // MARK: - Segmentlarni ulash (K-04)

    private func zanjirla(_ seg: [QuvurSegmenti]) -> [[QuvurSegmenti]] {
        let n = seg.count
        var ota = Array(0..<n)
        func ild(_ x: Int) -> Int { var x = x; while ota[x] != x { ota[x] = ota[ota[x]]; x = ota[x] }; return x }
        var qoshni = [[Int]](repeating: [], count: n)
        for i in 0..<n {
            for j in (i + 1)..<n where ulanadimi(seg[i], seg[j]) {
                ota[ild(i)] = ild(j)
                qoshni[i].append(j); qoshni[j].append(i)
            }
        }
        var guruhlar: [Int: [Int]] = [:]
        for i in 0..<n { guruhlar[ild(i), default: []].append(i) }
        var natija: [[QuvurSegmenti]] = []
        for (_, a) in guruhlar.sorted(by: { $0.key < $1.key }) {
            // uchdan boshlab tartiblash
            let boshi = a.first { qoshni[$0].count <= 1 } ?? a[0]
            var tartib = [boshi]
            var korilgan: Set<Int> = [boshi]
            while let oxirgi = tartib.last, let keyingi = qoshni[oxirgi].first(where: { !korilgan.contains($0) }) {
                tartib.append(keyingi); korilgan.insert(keyingi)
            }
            for x in a where !korilgan.contains(x) { tartib.append(x) }
            natija.append(tartib.map { seg[$0] })
        }
        return natija
    }

    private func ulanadimi(_ a: QuvurSegmenti, _ b: QuvurSegmenti) -> Bool {
        guard abs(a.radius - b.radius) <= max(0.008, 0.12 * max(a.radius, b.radius)) else { return false }
        let uchlar = [(a.bosh, b.bosh), (a.bosh, b.oxir), (a.oxir, b.bosh), (a.oxir, b.oxir)]
        guard uchlar.map({ $0.0.masofa($0.1) }).min()! <= 0.35 else { return false }
        return chiziqlarMasofasi(a, b) <= 0.06
    }

    /// Ikki o'q chizig'i orasidagi eng qisqa masofa va eng yaqin nuqtalar o'rtasi.
    private func engYaqin(_ a: QuvurSegmenti, _ b: QuvurSegmenti) -> (masofa: Double, orta: Vektor3) {
        let d1 = a.yonalish, d2 = b.yonalish
        let r = a.bosh - b.bosh
        let aa = d1.nuqta(d1), bb = d1.nuqta(d2), cc = d2.nuqta(d2), dd = d1.nuqta(r), ee = d2.nuqta(r)
        let maxraj = aa * cc - bb * bb
        if abs(maxraj) < 1e-9 {  // parallel
            let x = a.oxir.masofa(b.bosh) < a.bosh.masofa(b.oxir) ? (a.oxir, b.bosh) : (a.bosh, b.oxir)
            let v = r - d1 * dd
            return (v.uzunlik, (x.0 + x.1) / 2)
        }
        let s1 = (bb * ee - cc * dd) / maxraj
        let s2 = (aa * ee - bb * dd) / maxraj
        let p1 = a.bosh + d1 * s1, p2 = b.bosh + d2 * s2
        return (p1.masofa(p2), (p1 + p2) / 2)
    }

    private func chiziqlarMasofasi(_ a: QuvurSegmenti, _ b: QuvurSegmenti) -> Double { engYaqin(a, b).masofa }

    // MARK: - Quvur xususiyatlari

    private func quvurYasa(_ zanjir: [QuvurSegmenti]) -> TopilganQuvur {
        // Polilinya: har segmentni oldingisiga yaqin uchidan davom ettiramiz
        var segs = zanjir
        if segs.count > 1 {
            // birinchi segmentni ikkinchisiga qaragan uchi "oxir" bo'ladigan qilib buramiz
            let s0 = segs[0], s1 = segs[1]
            if min(s0.bosh.masofa(s1.bosh), s0.bosh.masofa(s1.oxir)) < min(s0.oxir.masofa(s1.bosh), s0.oxir.masofa(s1.oxir)) {
                segs[0] = teskari(s0)
            }
            for i in 1..<segs.count where segs[i].bosh.masofa(segs[i - 1].oxir) > segs[i].oxir.masofa(segs[i - 1].oxir) {
                segs[i] = teskari(segs[i])
            }
        }
        var oq: [Vektor3] = [segs[0].bosh]
        for i in 1..<segs.count { oq.append(engYaqin(segs[i - 1], segs[i]).orta) }
        oq.append(segs[segs.count - 1].oxir)
        // Oqim yo'nalishi: balanddan pastga
        if oq.first!.nuqta(yuqori) < oq.last!.nuqta(yuqori) { oq.reverse(); segs = segs.reversed().map(teskari) }
        let jamiN = segs.reduce(0) { $0 + $1.nuqtaSoni }
        let r = segs.reduce(0) { $0 + $1.radius * Double($1.nuqtaSoni) } / Double(jamiN)
        let rms = (segs.reduce(0) { $0 + $1.rms * $1.rms * Double($1.nuqtaSoni) } / Double(jamiN)).squareRoot()
        let yoy = segs.map { $0.yoyGrad }.max() ?? 0
        var uzunlik = 0.0, gorizontal = 0.0
        for i in 1..<oq.count {
            let d = oq[i] - oq[i - 1]
            uzunlik += d.uzunlik
            let v = d.nuqta(yuqori)
            gorizontal += (d - yuqori * v).uzunlik
        }
        let tushish = oq.first!.nuqta(yuqori) - oq.last!.nuqta(yuqori)
        let qiyalik = gorizontal > 1e-6 ? 100 * tushish / gorizontal : 0
        let diam = 2 * r * 1000
        let stansiyalar = chuqurliklar(oq, r)
        let tartibda = stansiyalar.map { $0.chuqurlikM }.sorted()
        let median: Double? = tartibda.isEmpty ? nil : tartibda[tartibda.count / 2]
        let muftalar = segs.flatMap { muftaNomzodlari($0) }
        let yoyF = min(1, yoy / 160), rmsF = max(0, 1 - rms / s.chegara), uzF = min(1, uzunlik / 1.0)
        return TopilganQuvur(
            oq: oq, radius: r, tashqiDiametrMm: diam,
            standart: StandartDiametrlar.moslash(diam, seriyalar: StandartDiametrlar.seriyalar(tarmoqTuri: s.tarmoqTuri)),
            qiyalikFoiz: qiyalik, qoplamaChuqurligiM: median, chuqurlikStansiyalari: stansiyalar,
            uzunlikM: uzunlik, nuqtaSoni: jamiN, yoyGrad: yoy, rmsM: rms,
            ishonch: ((yoyF + rmsF + uzF) / 3 * 100).rounded() / 100, muftalar: muftalar, segmentlar: segs)
    }

    private func teskari(_ q: QuvurSegmenti) -> QuvurSegmenti {
        var t = q; t.bosh = q.oxir; t.oxir = q.bosh; t.yonalish = -q.yonalish; return t
    }

    /// Har ~0,5 m da qoplama chuqurligi: gorizontal sirtli nuqtalar (normali ≈ yuqori), o'qdan yon tomonda
    /// (r+0,15…3 m), quvur ustidan ≥ 20 sm baland — ularning balandligi medianasi minus quvur usti.
    /// Uyilgan tuproq (otval) natijani oshirishi mumkin — shuning uchun "skan bo'yicha taxmin" deb ko'rsatiladi.
    private func chuqurliklar(_ oq: [Vektor3], _ r: Double) -> [ChuqurlikStansiyasi] {
        var kum: [Double] = [0]
        for i in 1..<oq.count { kum.append(kum[i - 1] + oq[i].masofa(oq[i - 1])) }
        let L = kum.last!
        guard L > 0 else { return [] }
        let n = max(1, Int((L / 0.5).rounded()))
        var bal = [[Double]](repeating: [], count: n + 1)
        let cosGor = cos(20 * Double.pi / 180)
        let up = yuqori
        let gor: (Vektor3) -> Vektor3 = { v in v - up * v.nuqta(up) }
        for k in 0..<P.count {
            guard abs(N[k].nuqta(up)) >= cosGor else { continue }
            let pg = gor(P[k])
            var engYon = Double.infinity, engS = 0.0, engOq = oq[0], engOrtiq = 0.0
            for i in 1..<oq.count {
                let a = oq[i - 1], b = oq[i]
                let ag = gor(a), bg = gor(b)
                let ab = bg - ag
                let uz2 = max(ab.uzunlik2, 1e-12)
                let tXom = (pg - ag).nuqta(ab) / uz2
                let t = max(0, min(1, tXom))
                let yon = pg.masofa(ag + ab * t)
                if yon < engYon {
                    engYon = yon
                    engS = kum[i - 1] + t * (kum[i] - kum[i - 1])
                    engOq = a + (b - a) * t
                    engOrtiq = max(0, tXom < 0 ? -tXom : tXom - 1) * uz2.squareRoot()
                }
            }
            guard engOrtiq <= 0.3, engYon >= r + 0.15, engYon <= 3.0 else { continue }
            let ust = engOq.nuqta(up) + r
            let h = P[k].nuqta(up)
            guard h >= ust + 0.2 else { continue }
            bal[min(n, max(0, Int((engS / L * Double(n)).rounded())))].append(h - ust)
        }
        var natija: [ChuqurlikStansiyasi] = []
        for st in 0...n where bal[st].count >= 30 {
            let x = bal[st].sorted()
            let sArc = Double(st) / Double(n) * L
            var j = 1
            while j < kum.count - 1, kum[j] < sArc { j += 1 }
            let t = (kum[j] - kum[j - 1]) > 0 ? (sArc - kum[j - 1]) / (kum[j] - kum[j - 1]) : 0
            natija.append(ChuqurlikStansiyasi(nuqta: oq[j - 1] + (oq[j] - oq[j - 1]) * max(0, min(1, t)),
                                              chuqurlikM: x[x.count / 2]))
        }
        return natija
    }

    /// K-03: radius profilidagi bo'rtiqlar — mufta/ulanish nomzodlari.
    private func muftaNomzodlari(_ seg: QuvurSegmenti) -> [Vektor3] {
        let m = Silindr(c: seg.bosh, a: seg.yonalish, r: seg.radius)
        let L = seg.uzunlik
        let qadam = 0.04
        let savN = Int(L / qadam) + 1
        guard savN >= 8 else { return [] }
        var sav = [[Double]](repeating: [], count: savN)
        for k in 0..<P.count {
            let (_, d, t) = radial(P[k], m)
            guard t >= 0, t <= L, d >= m.r - 2 * s.chegara, d <= m.r + 0.035 else { continue }
            sav[min(savN - 1, Int(t / qadam))].append(d - m.r)
        }
        let ort: [Double?] = sav.map { b in
            guard b.count >= 6 else { return nil }
            let x = b.sorted(); return x[x.count / 2]
        }
        let mavjud = ort.compactMap { $0 }.sorted()
        guard mavjud.count >= 6 else { return [] }
        let asos = mavjud[mavjud.count / 2]
        let chek = max(0.006, 0.08 * seg.radius)
        var natija: [Vektor3] = []
        var i = 2  // uchlarda chekka effekt — tashlanadi
        while i < savN - 2 {
            guard let v = ort[i], v - asos >= chek else { i += 1; continue }
            var j = i
            while j + 1 < savN - 2, let w = ort[j + 1], w - asos >= chek { j += 1 }
            let uz = Double(j - i + 1) * qadam
            if uz <= 0.3 {
                let t = (Double(i) + Double(j) + 1) / 2 * qadam
                natija.append(seg.bosh + seg.yonalish * t)
            }
            i = j + 1
        }
        return natija
    }

    private func sirtMasofa(_ u: Vektor3, _ q: TopilganQuvur) -> Double {
        var eng = Double.infinity
        for i in 1..<q.oq.count {
            let a = q.oq[i - 1], b = q.oq[i]
            let ab = b - a
            let t = max(0, min(1, (u - a).nuqta(ab) / max(ab.uzunlik2, 1e-12)))
            eng = min(eng, abs(u.masofa(a + ab * t) - q.radius))
        }
        return eng
    }
}

/// Fazoviy xesh-panjara (qo'shnilarni tez topish).
struct Panjara {
    struct Kalit: Hashable { let x: Int32; let y: Int32; let z: Int32 }
    let kat: Double
    private var h: [Kalit: [Int32]] = [:]

    static func kalit(_ p: Vektor3, _ kat: Double) -> Kalit {
        Kalit(x: Int32(floor(p.x / kat)), y: Int32(floor(p.y / kat)), z: Int32(floor(p.z / kat)))
    }

    init(_ P: [Vektor3], kat: Double) {
        self.kat = kat
        for (i, p) in P.enumerated() { h[Panjara.kalit(p, kat), default: []].append(Int32(i)) }
    }

    func atrofda(_ p: Vektor3, radius: Double, _ ish: (Int) -> Void) {
        let r = Int32(ceil(radius / kat))
        let k = Panjara.kalit(p, kat)
        for dx in -r...r { for dy in -r...r { for dz in -r...r {
            if let l = h[Kalit(x: k.x + dx, y: k.y + dy, z: k.z + dz)] { for i in l { ish(Int(i)) } }
        } } }
    }
}
