import Foundation
import YerostiGeometriya
import YerostiTahlil

/// KU-04 (TALABLAR 20): ikki skan orasidagi o'zgarish — M3C2 usuli (Lague, Brodu, Leroux 2013; CloudCompare M3C2):
/// yadro nuqtalar (A ning siyraklashtirilgan buluti), har birida PCA normal — ko'p masshtabli: D ∈ {10, 20, 30 sm} ichidan
/// sirt eng tekis bo'lgani (λ0/Σλ eng kichik; Lague 2013 usuli — burchak va Ø16 sm quvur yonida 30 sm sfera normalni
/// buzadi), normal bo'ylab d diametrli
/// silindr ichidagi A va B nuqtalarining o'rtacha holati farqi = masofa (ishorali); noaniqlik LoD95 = 1,96·(√(σA²/nA + σB²/nB) + reg).
/// LoD dan kichik farq shovqindan ajralmaydi — "ahamiyatsiz".
public enum Farq {
    public struct Sozlama: Sendable {
        public var yadroVokselM = 0.05        // yadro nuqtalar zichligi
        public var normalDiametrlarM: [Double] = [0.10, 0.20, 0.30]   // D — ko'p masshtab, eng tekisi tanlanadi
        /// d — silindr diametri. 10 sm: 1,5 sm vokselli bulutda sirt kesimida ~30 nuqta; Ø110+ quvur yonida tubga yetmaydi.
        public var proyeksiyaDiametrM = 0.10
        /// Silindr yarim balandligi. 0,5 m: ≥ 0,6 m transheyaning qarshi devori silindrga tushmaydi (1 m da tushib, LoD ni
        /// 10 sm gacha shishirardi); 50 sm gacha o'zgarish o'lchanadi.
        public var maksChuqurlikM = 0.5
        public var registratsiyaM = 0.02      // ikki skan georeferensi orasidagi xato (RTK)
        public var minNuqta = 5
        /// Silindr ichida normal bo'ylab sirt qatlamlarini ajratuvchi bo'shliq. A — yadro nuqtasining o'z qatlami (0 ga eng
        /// yaqin), B — shu qatlamga eng yaqin qatlam: tor transheyada devor, tub va quvur bir silindrga tushsa ham har sirt
        /// o'zi bilan solishtiriladi (konservativ: o'zgarish chegarasi ≤ d/2 ga torayadi, boshqa sirtdan "o'zgarish" to'qilmaydi).
        public var boshliqM = 0.03
        /// Tanlangan qatlam tarqoqligi (normal bo'ylab σ) shundan katta bo'lsa — sirt silindr o'qiga parallel yotibdi (masalan,
        /// devor ostini ko'mgan tub) yoki juda g'adir-budur: bunday yadro nuqta taqqoslanmaydi.
        public var maksTarqoqlikM = 0.03
        /// O'zgarish dog'i: bir xil ishorali ahamiyatli yadro nuqtalar, ≤ 2,5 voksel oraliqda bog'langan. Maydoni shundan
        /// (≈ 22×22 sm) katta bo'lsa — mahalliy o'zgarish bor, bulutning qolgan qismi o'zgarmagan bo'lsa ham.
        public var minDogM2 = 0.05
        /// Ahamiyatli yadro nuqtalar ulushi shundan oshsa ham — o'zgarish bor (keng tarqalgan o'zgarish).
        public var ulushChek = 0.05
        public init() {}
    }

    public struct Natija: Codable, Sendable {
        public var p: [Double]         // yadro nuqta (A ramkasida)
        public var n: [Double]         // normal
        public var masofa: Double?     // ishorali: musbat — B normal yo'nalishida (A dan "yuqorida")
        public var lod95: Double?
        public var ahamiyatli: Bool
        public var nA: Int
        public var nB: Int
    }

    public struct Xulosa: Codable, Sendable {
        public var yadroSoni: Int
        public var baholangan: Int
        public var ahamiyatli: Int
        public var ahamiyatliUlush: Double
        public var ortachaM: Double
        public var ortachaAbsM: Double
        public var maksAbsM: Double
        public var p95AbsM: Double
        /// Faqat ahamiyatli yadro nuqtalar |masofa| sining 95-persentili (3D shkalasi uchun); ahamiyatli yo'q bo'lsa 0.
        public var p95AhamiyatliAbsM: Double
        /// Eng katta dog' |masofa| sining 95-persentili — 3D shkalasi shu bo'yicha (burchakdagi yakka katta qiymatlar shkalani buzmaydi).
        public var dogP95AbsM: Double
        public var lod95OrtachaM: Double
        /// Eng katta o'zgarish dog'i: yadro nuqtalar soni, maydoni (dog' normaliga tik tekislikdagi voksel kataklari × voksel² —
        /// sirt voksel chegarasida yotsa yadro ikki qavat bo'ladi, shuning uchun soni × voksel² EMAS), o'rtacha masofasi, markazi.
        public var dogSoni: Int
        public var dogMaydonM2: Double
        public var dogOrtachaM: Double
        public var dogMarkaz: [Double]?
        /// OZGARISH — dog' maydoni ≥ minDogM2 yoki ulush > ulushChek; aks holda OZGARMAGAN.
        public var xulosa: String
        public var sozlama: [String: Double]
    }

    // Voksel to'r — qo'shni qidirish
    struct Tor {
        let v: Double
        var katak: [SIMD3<Int32>: [Int]] = [:]
        let P: [Vektor3]
        init(_ P: [Vektor3], v: Double) {
            self.P = P; self.v = v
            katak.reserveCapacity(P.count / 4 + 1)
            for (i, p) in P.enumerated() { katak[Self.k(p, v), default: []].append(i) }
        }
        static func k(_ p: Vektor3, _ v: Double) -> SIMD3<Int32> {
            SIMD3<Int32>(Int32((p.x / v).rounded(.down)), Int32((p.y / v).rounded(.down)), Int32((p.z / v).rounded(.down)))
        }
        /// Silindr (o'q c ± n·yarim, radius r) ichidagi nuqtalarning o'q bo'yicha koordinatasi. Faqat silindrni o'rab olgan
        /// to'rtburchak quti kataklari ko'riladi (sfera emas): tik va yotiq normalda ~10 marta kam katak.
        func silindr(_ c: Vektor3, _ n: Vektor3, yarim: Double, r: Double) -> [Double] {
            let a = c - n * yarim, b = c + n * yarim
            let k0 = Self.k(Vektor3(min(a.x, b.x) - r, min(a.y, b.y) - r, min(a.z, b.z) - r), v)
            let k1 = Self.k(Vektor3(max(a.x, b.x) + r, max(a.y, b.y) + r, max(a.z, b.z) + r), v)
            var h: [Double] = []
            for x in k0.x...k1.x { for y in k0.y...k1.y { for z in k0.z...k1.z {
                guard let idx = katak[SIMD3<Int32>(x, y, z)] else { continue }
                for i in idx {
                    let d = P[i] - c
                    let t = d.nuqta(n)
                    guard abs(t) <= yarim, (d - n * t).uzunlik <= r else { continue }
                    h.append(t)
                }
            } } }
            return h
        }

        /// Markazdan r radius ichidagi nuqtalar indekslari.
        func atrof(_ c: Vektor3, r: Double) -> [Int] {
            let s = Int32((r / v).rounded(.up))
            let k0 = Self.k(c, v)
            var natija: [Int] = []
            for dx in -s...s { for dy in -s...s { for dz in -s...s {
                guard let idx = katak[SIMD3<Int32>(k0.x + dx, k0.y + dy, k0.z + dz)] else { continue }
                for i in idx where (P[i] - c).uzunlik <= r { natija.append(i) }
            } } }
            return natija
        }
    }

    static func pcaNormal(_ Q: [Vektor3]) -> Vektor3? { pcaNormalTekislik(Q)?.n }

    /// PCA normal va sirt o'zgaruvchanligi λ0/(λ0+λ1+λ2): tekislikda ≈ 0, burchak va egri sirtda katta.
    static func pcaNormalTekislik(_ Q: [Vektor3]) -> (n: Vektor3, sv: Double)? {
        guard Q.count >= 3 else { return nil }
        let k = Double(Q.count)
        let m = Q.reduce(Vektor3.nol, +) * (1 / k)
        var xx = 0.0, xy = 0.0, xz = 0.0, yy = 0.0, yz = 0.0, zz = 0.0
        for q in Q { let d = q - m; xx += d.x*d.x; xy += d.x*d.y; xz += d.x*d.z; yy += d.y*d.y; yz += d.y*d.z; zz += d.z*d.z }
        // eng kichik o'z qiymat vektori — teskari darajali iteratsiya o'rniga 3×3 analitik: Jakobi 12 iteratsiya
        var A = [[xx, xy, xz], [xy, yy, yz], [xz, yz, zz]]
        var V = [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]]
        for _ in 0..<12 {
            for p in 0..<2 { for q in (p + 1)..<3 where abs(A[p][q]) > 1e-15 {
                let th = 0.5 * atan2(2 * A[p][q], A[q][q] - A[p][p])
                let c = cos(th), s = sin(th)
                for r in 0..<3 {
                    let arp = A[r][p], arq = A[r][q]
                    A[r][p] = c * arp - s * arq; A[r][q] = s * arp + c * arq
                }
                for r in 0..<3 {
                    let apr = A[p][r], aqr = A[q][r]
                    A[p][r] = c * apr - s * aqr; A[q][r] = s * apr + c * aqr
                }
                for r in 0..<3 {
                    let vrp = V[r][p], vrq = V[r][q]
                    V[r][p] = c * vrp - s * vrq; V[r][q] = s * vrp + c * vrq
                }
            } }
        }
        let eng = (0..<3).min { A[$0][$0] < A[$1][$1] }!
        var n = Vektor3(V[0][eng], V[1][eng], V[2][eng])
        if n.z < 0 { n = n * -1 }      // yuqoriga qarasin (ENU z)
        guard let nb = n.birlik else { return nil }
        let jami = max(A[0][0] + A[1][1] + A[2][2], 1e-18)
        return (nb, max(0, A[eng][eng]) / jami)
    }

    /// A va B — bir ramkada (ENU, metr). Natija A ning yadro nuqtalarida.
    public static func hisobla(_ A: [Vektor3], _ B: [Vektor3], _ s: Sozlama = .init()) -> (natijalar: [Natija], xulosa: Xulosa) {
        // yadro nuqtalar: voksel markazidagi birinchi nuqta
        var korilgan = Set<SIMD3<Int32>>()
        var yadro: [Vektor3] = []
        for p in A where korilgan.insert(Tor.k(p, s.yadroVokselM)).inserted { yadro.append(p) }
        let torA = Tor(A, v: s.proyeksiyaDiametrM), torB = Tor(B, v: s.proyeksiyaDiametrM)
        let dMax = s.normalDiametrlarM.max() ?? 0.30
        let masshtablar = s.normalDiametrlarM.sorted()
        let torN = Tor(A, v: dMax)
        var natijalar: [Natija] = []
        natijalar.reserveCapacity(yadro.count)
        let r = s.proyeksiyaDiametrM / 2
        for c in yadro {
            let atrof = torN.atrof(c, r: dMax / 2).map { A[$0] }
            var engTekis: (n: Vektor3, sv: Double)?
            for D in masshtablar {
                let Q = D >= dMax ? atrof : atrof.filter { ($0 - c).uzunlik <= D / 2 }
                guard Q.count >= 10, let x = pcaNormalTekislik(Q) else { continue }
                if engTekis == nil || x.sv < engTekis!.sv { engTekis = x }
            }
            guard let n = engTekis?.n else {
                natijalar.append(Natija(p: [c.x, c.y, c.z], n: [0, 0, 1], masofa: nil, lod95: nil, ahamiyatli: false, nA: 0, nB: 0)); continue
            }
            func silindr(_ tor: Tor) -> [Double] { tor.silindr(c, n, yarim: s.maksChuqurlikM, r: r) }
            func qatlamlar(_ h: [Double]) -> [[Double]] {
                var q: [[Double]] = []
                for x in h.sorted() {
                    if let o = q.last?.last, x - o <= s.boshliqM { q[q.count - 1].append(x) } else { q.append([x]) }
                }
                return q.filter { $0.count >= s.minNuqta }
            }
            func orta(_ q: [Double]) -> Double { q.reduce(0, +) / Double(q.count) }
            let qA = qatlamlar(silindr(torA)), qB = qatlamlar(silindr(torB))
            guard let hA = qA.min(by: { abs(orta($0)) < abs(orta($1)) }),
                  case let mA0 = orta(hA), let hB = qB.min(by: { abs(orta($0) - mA0) < abs(orta($1) - mA0) }) else {
                natijalar.append(Natija(p: [c.x, c.y, c.z], n: [n.x, n.y, n.z], masofa: nil, lod95: nil, ahamiyatli: false,
                                        nA: qA.map(\.count).max() ?? 0, nB: qB.map(\.count).max() ?? 0)); continue
            }
            func ort(_ h: [Double]) -> (Double, Double) {
                let m = h.reduce(0, +) / Double(h.count)
                let v = h.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(max(h.count - 1, 1))
                return (m, v.squareRoot())
            }
            let (mA, sA) = ort(hA), (mB, sB) = ort(hB)
            guard sA <= s.maksTarqoqlikM, sB <= s.maksTarqoqlikM else {
                natijalar.append(Natija(p: [c.x, c.y, c.z], n: [n.x, n.y, n.z], masofa: nil, lod95: nil, ahamiyatli: false,
                                        nA: hA.count, nB: hB.count)); continue
            }
            let masofa = mB - mA
            let lod = 1.96 * ((sA * sA / Double(hA.count) + sB * sB / Double(hB.count)).squareRoot() + s.registratsiyaM)
            natijalar.append(Natija(p: [c.x, c.y, c.z], n: [n.x, n.y, n.z], masofa: masofa, lod95: lod, ahamiyatli: abs(masofa) > lod,
                                    nA: hA.count, nB: hB.count))
        }
        let bor = natijalar.compactMap(\.masofa)
        let abs_ = bor.map { abs($0) }.sorted()
        func p95(_ x: [Double]) -> Double { x.isEmpty ? 0 : x[min(x.count - 1, Int(Double(x.count) * 0.95))] }
        // O'zgarish dog'lari: bir xil ishorali ahamiyatli yadro nuqtalar, ≤ 2,5 voksel oraliqda bog'langan (union-find)
        let ah = natijalar.indices.filter { natijalar[$0].ahamiyatli }
        let bogM = 2.5 * s.yadroVokselM
        var ota = Array(0..<ah.count)
        func ild(_ x: Int) -> Int { var x = x; while ota[x] != x { ota[x] = ota[ota[x]]; x = ota[x] }; return x }
        func nuqta(_ i: Int) -> Vektor3 { let n = natijalar[ah[i]]; return Vektor3(n.p[0], n.p[1], n.p[2]) }
        var katak: [SIMD3<Int32>: [Int]] = [:]
        for i in 0..<ah.count { katak[Tor.k(nuqta(i), bogM), default: []].append(i) }
        for i in 0..<ah.count {
            let p = nuqta(i), k0 = Tor.k(p, bogM), musbat = (natijalar[ah[i]].masofa ?? 0) > 0
            for dx in Int32(-1)...1 { for dy in Int32(-1)...1 { for dz in Int32(-1)...1 {
                guard let l = katak[SIMD3<Int32>(k0.x + dx, k0.y + dy, k0.z + dz)] else { continue }
                for j in l where j > i && ((natijalar[ah[j]].masofa ?? 0) > 0) == musbat && (nuqta(j) - p).uzunlik <= bogM {
                    ota[ild(i)] = ild(j)
                }
            } } }
        }
        var guruh: [Int: [Int]] = [:]
        for i in 0..<ah.count { guruh[ild(i), default: []].append(i) }
        let dog = guruh.values.max { $0.count != $1.count ? $0.count < $1.count : $0[0] > $1[0] } ?? []
        let dogM = dog.map { natijalar[ah[$0]].masofa ?? 0 }
        let dogMarkaz: [Double]? = dog.isEmpty ? nil : {
            let c = dog.reduce(Vektor3.nol) { $0 + nuqta($1) } * (1 / Double(dog.count))
            return [c.x, c.y, c.z]
        }()
        var dogMaydon = 0.0
        if !dog.isEmpty {
            var M = Matritsa3.nol
            for i in dog { let n = natijalar[ah[i]].n; M.tashqiQosh(Vektor3(n[0], n[1], n[2])) }
            let (e1, e2) = M.xosTahlil()[2].vektor.perpendikulyarBazis()   // eng katta xos vektor — dog' normali (ishorasiz)
            var kataklar = Set<SIMD2<Int32>>()
            for i in dog {
                let p = nuqta(i)
                kataklar.insert(SIMD2<Int32>(Int32((p.nuqta(e1) / s.yadroVokselM).rounded(.down)), Int32((p.nuqta(e2) / s.yadroVokselM).rounded(.down))))
            }
            dogMaydon = Double(kataklar.count) * s.yadroVokselM * s.yadroVokselM
        }
        let ulush = Double(ah.count) / Double(max(bor.count, 1))
        let xulosa = Xulosa(yadroSoni: yadro.count, baholangan: bor.count, ahamiyatli: ah.count,
                            ahamiyatliUlush: (ulush * 10_000).rounded() / 10_000,
                            ortachaM: bor.isEmpty ? 0 : bor.reduce(0, +) / Double(bor.count),
                            ortachaAbsM: abs_.isEmpty ? 0 : abs_.reduce(0, +) / Double(abs_.count),
                            maksAbsM: abs_.last ?? 0, p95AbsM: p95(abs_),
                            p95AhamiyatliAbsM: p95(ah.map { abs(natijalar[$0].masofa ?? 0) }.sorted()),
                            dogP95AbsM: p95(dogM.map { abs($0) }.sorted()),
                            lod95OrtachaM: natijalar.compactMap(\.lod95).reduce(0, +) / Double(max(bor.count, 1)),
                            dogSoni: dog.count, dogMaydonM2: (dogMaydon * 10_000).rounded() / 10_000,
                            dogOrtachaM: dogM.isEmpty ? 0 : dogM.reduce(0, +) / Double(dogM.count), dogMarkaz: dogMarkaz,
                            xulosa: (dogMaydon >= s.minDogM2 || ulush > s.ulushChek) ? "OZGARISH" : "OZGARMAGAN",
                            sozlama: ["yadro_voksel_m": s.yadroVokselM, "normal_diametr_min_m": masshtablar.first ?? dMax, "normal_diametr_max_m": dMax,
                                      "proyeksiya_diametr_m": s.proyeksiyaDiametrM, "maks_chuqurlik_m": s.maksChuqurlikM,
                                      "registratsiya_m": s.registratsiyaM, "boshliq_m": s.boshliqM, "maks_tarqoqlik_m": s.maksTarqoqlikM, "min_dog_m2": s.minDogM2, "ulush_chek": s.ulushChek])
        return (natijalar, xulosa)
    }

    /// 3D ko'ruvchi uchun PLY: x y z farq lod (float32), masofasi yo'q yadro nuqtalar farq = NaN.
    public static func ply(_ natijalar: [Natija]) -> Data {
        var s = "ply\nformat binary_little_endian 1.0\ncomment YEROSTI farq M3C2 (A ramkasi, ENU)\n"
        s += "element vertex \(natijalar.count)\nproperty float x\nproperty float y\nproperty float z\nproperty float farq\nproperty float lod\nend_header\n"
        var d = Data(s.utf8)
        d.reserveCapacity(d.count + natijalar.count * 20)
        func f(_ x: Double) { var v = Float(x).bitPattern.littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
        for n in natijalar {
            f(n.p[0]); f(n.p[1]); f(n.p[2]); f(n.masofa ?? .nan); f(n.lod95 ?? .nan)
        }
        return d
    }

    public static func json(_ x: Xulosa) throws -> Data {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys]
        return try e.encode(x)
    }
}
