import Foundation

/// Ijro chizmasi uchun liniya — proyeksiyalangan koordinatalarda (UTM: e — sharq, n — shimol, h — o'q balandligi).
public struct ChizmaNuqta: Equatable, Sendable {
    public var e: Double
    public var n: Double
    public var h: Double?
    public var chuqurlik: Double?
    public var sifat: String
    public init(e: Double, n: Double, h: Double? = nil, chuqurlik: Double? = nil, sifat: String) {
        self.e = e; self.n = n; self.h = h; self.chuqurlik = chuqurlik; self.sifat = sifat
    }
}

public struct ChizmaLiniya: Equatable, Sendable {
    public var turi: String
    public var diametrMm: Int
    public var material: String
    public var sifat: String
    public var nuqtalar: [ChizmaNuqta]
    public init(turi: String, diametrMm: Int, material: String, sifat: String, nuqtalar: [ChizmaNuqta]) {
        self.turi = turi; self.diametrMm = diametrMm; self.material = material; self.sifat = sifat; self.nuqtalar = nuqtalar
    }
}

public struct ChizmaSarlavha: Equatable, Sendable {
    public var obyekt: String
    public var order: String
    public var pudratchi: String
    public var buyurtmachi: String
    public var sana: String
    public var muhr: String
    public var koordinataTizimi: String
    public init(obyekt: String, order: String = "", pudratchi: String = "", buyurtmachi: String = "", sana: String,
                muhr: String = "", koordinataTizimi: String = "WGS84 / UTM 42N") {
        self.obyekt = obyekt; self.order = order; self.pudratchi = pudratchi; self.buyurtmachi = buyurtmachi
        self.sana = sana; self.muhr = muhr; self.koordinataTizimi = koordinataTizimi
    }
}

/// DXF-01…DXF-06: AutoCAD R12 (AC1009) ASCII — AutoCAD, QGIS, LibreOffice, nanoCAD ochadi.
public enum DXFChizma {
    /// Qatlam va AutoCAD rang indeksi (ACI).
    public static let qatlamlar: [(tur: String, qatlam: String, aci: Int)] = [
        ("suv", "TRACE4D_SUV", 5), ("kanalizatsiya", "TRACE4D_KANALIZATSIYA", 34), ("gaz", "TRACE4D_GAZ", 2),
        ("elektr", "TRACE4D_ELEKTR", 1), ("optika", "TRACE4D_OPTIKA", 30), ("issiqlik", "TRACE4D_ISSIQLIK", 6),
    ]
    static let yordamchi: [(String, Int)] = [("TRACE4D_NUQTA", 7), ("TRACE4D_YORLIQ", 7), ("TRACE4D_JADVAL", 8), ("TRACE4D_RAMKA", 7)]

    public static func qatlam(_ turi: String) -> String { qatlamlar.first { $0.tur == turi }?.qatlam ?? "TRACE4D_BOSHQA" }

    /// Faqat ASCII: o'zbek/rus harflari lotinga o'giriladi (R12 kod sahifasi muammosiz ochilishi uchun).
    public static func ascii(_ s: String) -> String {
        let jadval: [Character: String] = [
            "ʻ": "'", "ʼ": "'", "‘": "'", "’": "'", "`": "'", "«": "\"", "»": "\"", "—": "-", "–": "-", "Ø": "D", "ø": "d",
            "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "j", "з": "z", "и": "i", "й": "y",
            "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
            "х": "x", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sh", "ъ": "'", "ы": "i", "ь": "", "э": "e", "ю": "yu", "я": "ya",
            "ў": "o'", "қ": "q", "ғ": "g'", "ҳ": "h",
        ]
        var r = ""
        for ch in s {
            if ch.isASCII, ch != "\n", ch != "\r" { r.append(ch); continue }
            let kichik = Character(ch.lowercased())
            if let t = jadval[kichik] ?? jadval[ch] {
                r += ch.isUppercase && !t.isEmpty ? t.prefix(1).uppercased() + t.dropFirst() : t
            } else if ch == "\n" || ch == "\r" {
                r += " "
            } else {
                r += "?"
            }
        }
        return r
    }

    private final class Yozuvchi {
        var s = ""
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        func j(_ kod: Int, _ q: String) { s += "\(kod)\n\(q)\n" }
        func j(_ kod: Int, _ q: Double) {
            s += "\(kod)\n" + String(format: "%.4f", q) + "\n"
            if kod == 10 || kod == 11 { minX = min(minX, q); maxX = max(maxX, q) }
            if kod == 20 || kod == 21 { minY = min(minY, q); maxY = max(maxY, q) }
        }
        func j(_ kod: Int, _ q: Int) { s += "\(kod)\n\(q)\n" }
    }

    public static func yoz(_ liniyalar: [ChizmaLiniya], sarlavha: ChizmaSarlavha, matnBalandligi: Double = 0.5) -> String {
        let chiziladi = liniyalar.filter { $0.nuqtalar.count >= 2 }
        let hamma = chiziladi.flatMap { $0.nuqtalar }
        let maxE = hamma.map { $0.e }.max() ?? 0
        let maxN = hamma.map { $0.n }.max() ?? 0

        // ENTITIES avval yoziladi — $EXTMIN/$EXTMAX haqiqatda yozilgan elementlardan olinadi
        let w = Yozuvchi()
        w.j(0, "SECTION"); w.j(2, "ENTITIES")
        var raqam = 0
        var katalog: [(Int, ChizmaNuqta)] = []
        for l in chiziladi {
            let q = qatlam(l.turi)
            w.j(0, "POLYLINE"); w.j(8, q)
            if l.sifat != "RASMIY" { w.j(6, "DASHED") }
            // R12: POLYLINE ning 10/20 — "soxta" nuqta (AutoCAD e'tiborga olmaydi). 0,0 yozilsa ba'zi o'quvchilar
            // (LibreOffice) uni chegaraga qo'shadi — shuning uchun birinchi cho'qqi yoziladi.
            w.j(66, 1); w.j(10, l.nuqtalar[0].e); w.j(20, l.nuqtalar[0].n); w.j(30, 0.0); w.j(70, 8)
            for p in l.nuqtalar {
                w.j(0, "VERTEX"); w.j(8, q)
                w.j(10, p.e); w.j(20, p.n); w.j(30, p.h ?? 0); w.j(70, 32)
            }
            w.j(0, "SEQEND"); w.j(8, q)
            for p in l.nuqtalar {
                raqam += 1
                katalog.append((raqam, p))
                w.j(0, "POINT"); w.j(8, "TRACE4D_NUQTA"); w.j(10, p.e); w.j(20, p.n); w.j(30, p.h ?? 0)
                matn(w, "\(raqam)", p.e + matnBalandligi * 0.3, p.n + matnBalandligi * 0.3, matnBalandligi * 0.6, 0, "TRACE4D_NUQTA")
            }
            let i = l.nuqtalar.count / 2
            let a = l.nuqtalar[max(0, i - 1)], b = l.nuqtalar[i]
            var burchak = atan2(b.n - a.n, b.e - a.e) * 180 / .pi
            if burchak > 90 { burchak -= 180 } else if burchak < -90 { burchak += 180 }
            let chuqurliklar = l.nuqtalar.compactMap { $0.chuqurlik }
            let ch = chuqurliklar.isEmpty ? "" : String(format: " h=%.2f", chuqurliklar.reduce(0, +) / Double(chuqurliklar.count))
            let tur = qatlamlar.first { $0.tur == l.turi }.map { String($0.qatlam.dropFirst(8)) } ?? l.turi.uppercased()
            let yorliq = ascii("\(tur) D\(l.diametrMm) \(l.material)\(ch)\(l.sifat == "RASMIY" ? "" : " (\(l.sifat))")")
            let o = matnBalandligi * 0.6
            let nx = -sin(burchak * .pi / 180) * o, ny = cos(burchak * .pi / 180) * o
            matn(w, yorliq, (a.e + b.e) / 2 + nx, (a.n + b.n) / 2 + ny, matnBalandligi, burchak, "TRACE4D_YORLIQ")
        }

        // Koordinata katalogi (DXF-04) — chizmaning o'ng tomonida
        let x0 = maxE + 5, h = matnBalandligi * 0.8, qator = h * 1.8
        let ustunlar: [(String, Double)] = [("No", 3), ("E (X), m", 14), ("N (Y), m", 14), ("H, m", 9), ("Chuq., m", 8), ("Sifat", 8)]
        let kenglik = ustunlar.reduce(0) { $0 + $1.1 }
        var y = maxN
        func chiziq(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ q: String) {
            w.j(0, "LINE"); w.j(8, q); w.j(10, ax); w.j(20, ay); w.j(30, 0.0); w.j(11, bx); w.j(21, by); w.j(31, 0.0)
        }
        matn(w, "KOORDINATALAR KATALOGI (\(ascii(sarlavha.koordinataTizimi)))", x0, y + qator * 0.6, h, 0, "TRACE4D_JADVAL")
        chiziq(x0, y, x0 + kenglik, y, "TRACE4D_JADVAL")
        var x = x0
        for (nomi, k) in ustunlar { matn(w, nomi, x + 0.3, y - qator + h * 0.4, h, 0, "TRACE4D_JADVAL"); x += k }
        y -= qator
        chiziq(x0, y, x0 + kenglik, y, "TRACE4D_JADVAL")
        for (r, p) in katalog {
            let qiymatlar = ["\(r)", String(format: "%.3f", p.e), String(format: "%.3f", p.n), p.h.map { String(format: "%.3f", $0) } ?? "-",
                             p.chuqurlik.map { String(format: "%.2f", $0) } ?? "-", ascii(p.sifat)]
            x = x0
            for (i, (_, k)) in ustunlar.enumerated() { matn(w, qiymatlar[i], x + 0.3, y - qator + h * 0.4, h, 0, "TRACE4D_JADVAL"); x += k }
            y -= qator
            chiziq(x0, y, x0 + kenglik, y, "TRACE4D_JADVAL")
        }
        x = x0
        for (_, k) in ustunlar + [("", 0)] { chiziq(x, maxN, x, y, "TRACE4D_JADVAL"); x += k }

        // Sarlavha bloki (DXF-06)
        let satrlar = [
            "IJRO S'YOMKASI - YER OSTI TARMOQLARI",
            "Obyekt: \(sarlavha.obyekt)", "Order: \(sarlavha.order)", "Pudratchi: \(sarlavha.pudratchi)",
            "Buyurtmachi: \(sarlavha.buyurtmachi)", "Sana: \(sarlavha.sana)", "Raqamli muhr: \(sarlavha.muhr)",
            "Koordinatalar: \(sarlavha.koordinataTizimi)", "Yaratildi: TRACE4D (RTK + LiDAR)",
            "Geodezist: ______________________   Imzo: ____________",
        ].map(ascii)
        let ry = y - qator * 2
        let rb = qator * Double(satrlar.count) + qator
        chiziq(x0, ry, x0 + kenglik, ry, "TRACE4D_RAMKA")
        chiziq(x0, ry - rb, x0 + kenglik, ry - rb, "TRACE4D_RAMKA")
        chiziq(x0, ry, x0, ry - rb, "TRACE4D_RAMKA")
        chiziq(x0 + kenglik, ry, x0 + kenglik, ry - rb, "TRACE4D_RAMKA")
        for (i, s) in satrlar.enumerated() {
            matn(w, s, x0 + 0.6, ry - qator * Double(i + 1), i == 0 ? h * 1.2 : h, 0, "TRACE4D_RAMKA")
        }
        w.j(0, "ENDSEC")
        w.j(0, "EOF")

        // HEADER va TABLES — haqiqiy chegaralar bilan, faylning boshiga
        let hw = Yozuvchi()
        let chegara = w.minX.isFinite ? (w.minX, w.minY, w.maxX, w.maxY) : (0.0, 0.0, 0.0, 0.0)
        hw.j(0, "SECTION"); hw.j(2, "HEADER")
        hw.j(9, "$ACADVER"); hw.j(1, "AC1009")
        hw.j(9, "$INSUNITS"); hw.j(70, 6)
        hw.j(9, "$EXTMIN"); hw.j(10, chegara.0); hw.j(20, chegara.1); hw.j(30, 0.0)
        hw.j(9, "$EXTMAX"); hw.j(10, chegara.2); hw.j(20, chegara.3); hw.j(30, 0.0)
        hw.j(0, "ENDSEC")
        hw.j(0, "SECTION"); hw.j(2, "TABLES")
        hw.j(0, "TABLE"); hw.j(2, "LTYPE"); hw.j(70, 2)
        hw.j(0, "LTYPE"); hw.j(2, "CONTINUOUS"); hw.j(70, 0); hw.j(3, "Solid line"); hw.j(72, 65); hw.j(73, 0); hw.j(40, 0.0)
        hw.j(0, "LTYPE"); hw.j(2, "DASHED"); hw.j(70, 0); hw.j(3, "__ __ __"); hw.j(72, 65); hw.j(73, 2); hw.j(40, 1.5)
        hw.j(49, 1.0); hw.j(49, -0.5)
        hw.j(0, "ENDTAB")
        let barchaQatlam = qatlamlar.map { ($0.qatlam, $0.aci) } + yordamchi + [("TRACE4D_BOSHQA", 7)]
        hw.j(0, "TABLE"); hw.j(2, "LAYER"); hw.j(70, barchaQatlam.count)
        for (nomi, aci) in barchaQatlam {
            hw.j(0, "LAYER"); hw.j(2, nomi); hw.j(70, 0); hw.j(62, aci); hw.j(6, "CONTINUOUS")
        }
        hw.j(0, "ENDTAB")
        hw.j(0, "ENDSEC")
        return hw.s + w.s
    }

    private static func matn(_ w: Yozuvchi, _ s: String, _ x: Double, _ y: Double, _ h: Double, _ burchak: Double, _ q: String) {
        w.j(0, "TEXT"); w.j(8, q); w.j(10, x); w.j(20, y); w.j(30, 0.0); w.j(40, h); w.j(1, ascii(s))
        if burchak != 0 { w.j(50, burchak) }
    }

    /// Koordinata katalogi CSV (DXF-04).
    public static func katalogCSV(_ liniyalar: [ChizmaLiniya]) -> String {
        var s = "raqam;turi;diametr_mm;e;n;h;chuqurlik_m;sifat\n"
        var r = 0
        for l in liniyalar where l.nuqtalar.count >= 2 {
            for p in l.nuqtalar {
                r += 1
                s += "\(r);\(l.turi);\(l.diametrMm);" + String(format: "%.3f;%.3f;", p.e, p.n)
                    + (p.h.map { String(format: "%.3f", $0) } ?? "") + ";" + (p.chuqurlik.map { String(format: "%.2f", $0) } ?? "")
                    + ";\(p.sifat)\n"
            }
        }
        return s
    }
}
