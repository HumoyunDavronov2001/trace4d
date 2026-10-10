"""YEROSTI — ijro chizmasi (DXF R12) va koordinata katalogi (CSV), server tomoni (T-235, DXF-01…06).

UTM hisobi Swift `UTM` (Krüger qatori) bilan bir xil — ikkala tomonda bir xil nazorat qiymati bilan test qilingan.
Format Swift `DXFChizma` bilan mos (qatlamlar, 3D polilinya, yorliqlar, katalog, sarlavha bloki).
"""
import math

A = 6378137.0
F = 1 / 298.257223563
K0 = 0.9996
E0 = 500_000.0
_N = F / (2 - F)
_AA = A / (1 + _N) * (1 + _N ** 2 / 4 + _N ** 4 / 64)
_ALFA = [_N / 2 - 2 * _N ** 2 / 3 + 5 * _N ** 3 / 16, 13 * _N ** 2 / 48 - 3 * _N ** 3 / 5, 61 * _N ** 3 / 240]

QATLAMLAR = [("suv", "TRACE4D_SUV", 5), ("kanalizatsiya", "TRACE4D_KANALIZATSIYA", 34), ("gaz", "TRACE4D_GAZ", 2),
             ("elektr", "TRACE4D_ELEKTR", 1), ("optika", "TRACE4D_OPTIKA", 30), ("issiqlik", "TRACE4D_ISSIQLIK", 6)]
YORDAMCHI = [("TRACE4D_NUQTA", 7), ("TRACE4D_YORLIQ", 7), ("TRACE4D_JADVAL", 8), ("TRACE4D_RAMKA", 7), ("TRACE4D_BOSHQA", 7)]
_ASCII = {"ʻ": "'", "ʼ": "'", "‘": "'", "’": "'", "`": "'", "«": '"', "»": '"', "—": "-", "–": "-", "Ø": "D", "ø": "d",
          "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "j", "з": "z", "и": "i", "й": "y",
          "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
          "х": "x", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sh", "ъ": "'", "ы": "i", "ь": "", "э": "e", "ю": "yu", "я": "ya",
          "ў": "o'", "қ": "q", "ғ": "g'", "ҳ": "h"}


def utm_zona(lon):
    return int(math.floor((lon + 180) / 6)) + 1


def utm(lat, lon, zona=None):
    """WGS84 → UTM (sharq, shimol). Swift `UTM.ga` bilan bir xil formula."""
    z = zona or utm_zona(lon)
    fi = math.radians(lat)
    lam = math.radians(lon - ((z - 1) * 6 - 180 + 3))
    sn = 2 * math.sqrt(_N) / (1 + _N)
    t = math.sinh(math.atanh(math.sin(fi)) - sn * math.atanh(sn * math.sin(fi)))
    xi = math.atan2(t, math.cos(lam))
    eta = math.atanh(math.sin(lam) / math.sqrt(1 + t * t))
    e, n = eta, xi
    for j in range(1, 4):
        e += _ALFA[j - 1] * math.cos(2 * j * xi) * math.sinh(2 * j * eta)
        n += _ALFA[j - 1] * math.sin(2 * j * xi) * math.cosh(2 * j * eta)
    return E0 + K0 * _AA * e, (0 if lat >= 0 else 10_000_000) + K0 * _AA * n, z


def ascii_qil(s):
    r = []
    for ch in str(s):
        if ch.isascii() and ch not in "\r\n":
            r.append(ch)
            continue
        t = _ASCII.get(ch.lower(), _ASCII.get(ch))
        if t is not None:
            r.append(t[:1].upper() + t[1:] if ch.isupper() and t else t)
        else:
            r.append(" " if ch in "\r\n" else "?")
    return "".join(r)


def qatlam(turi):
    return next((q for t, q, _ in QATLAMLAR if t == turi), "TRACE4D_BOSHQA")


class _Yozuvchi:
    def __init__(self):
        self.q = []
        self.minx = self.miny = math.inf
        self.maxx = self.maxy = -math.inf

    def j(self, kod, qiymat):
        if isinstance(qiymat, float):
            self.q.append(f"{kod}\n{qiymat:.4f}\n")
            if kod in (10, 11):
                self.minx, self.maxx = min(self.minx, qiymat), max(self.maxx, qiymat)
            if kod in (20, 21):
                self.miny, self.maxy = min(self.miny, qiymat), max(self.maxy, qiymat)
        else:
            self.q.append(f"{kod}\n{qiymat}\n")

    def matn(self, s, x, y, h, burchak, q):
        self.j(0, "TEXT"); self.j(8, q); self.j(10, float(x)); self.j(20, float(y)); self.j(30, 0.0)
        self.j(40, float(h)); self.j(1, ascii_qil(s))
        if burchak:
            self.j(50, float(burchak))

    def chiziq(self, ax, ay, bx, by, q):
        self.j(0, "LINE"); self.j(8, q); self.j(10, float(ax)); self.j(20, float(ay)); self.j(30, 0.0)
        self.j(11, float(bx)); self.j(21, float(by)); self.j(31, 0.0)


def liniyalar_utm(liniyalar):
    """Baza liniyalari (lat/lon) → chizma liniyalari (e, n, h). Zona — birinchi nuqtadan (hammasi bir zonada)."""
    zona = None
    natija = []
    for l in liniyalar:
        if len(l["nuqtalar"]) < 2:
            continue
        nq = []
        for n in l["nuqtalar"]:
            e, nn, zona = utm(n["lat"], n["lon"], zona)
            nq.append({"e": e, "n": nn, "h": n.get("balandlik"), "chuqurlik": n.get("chuqurlik_m"), "sifat": n.get("sifat", "")})
        natija.append({"turi": l["turi"], "diametr_mm": l["diametr_mm"], "material": l.get("material", ""),
                       "sifat": l["sifat"], "nuqtalar": nq})
    return natija, zona or 42


def dxf(liniyalar, sarlavha, matn_h=0.5):
    """liniyalar: [{turi, diametr_mm, material, sifat, nuqtalar:[{e,n,h,chuqurlik,sifat}]}] (UTM)."""
    w = _Yozuvchi()
    hamma = [p for l in liniyalar for p in l["nuqtalar"]]
    max_e = max((p["e"] for p in hamma), default=0.0)
    max_n = max((p["n"] for p in hamma), default=0.0)
    w.j(0, "SECTION"); w.j(2, "ENTITIES")
    raqam, katalog = 0, []
    for l in liniyalar:
        q = qatlam(l["turi"])
        w.j(0, "POLYLINE"); w.j(8, q)
        if l["sifat"] != "RASMIY":
            w.j(6, "DASHED")
        w.j(66, 1); w.j(10, float(l["nuqtalar"][0]["e"])); w.j(20, float(l["nuqtalar"][0]["n"])); w.j(30, 0.0); w.j(70, 8)
        for p in l["nuqtalar"]:
            w.j(0, "VERTEX"); w.j(8, q); w.j(10, float(p["e"])); w.j(20, float(p["n"])); w.j(30, float(p["h"] or 0.0)); w.j(70, 32)
        w.j(0, "SEQEND"); w.j(8, q)
        for p in l["nuqtalar"]:
            raqam += 1
            katalog.append((raqam, p))
            w.j(0, "POINT"); w.j(8, "TRACE4D_NUQTA"); w.j(10, float(p["e"])); w.j(20, float(p["n"])); w.j(30, float(p["h"] or 0.0))
            w.matn(str(raqam), p["e"] + matn_h * 0.3, p["n"] + matn_h * 0.3, matn_h * 0.6, 0, "TRACE4D_NUQTA")
        i = len(l["nuqtalar"]) // 2
        a, b = l["nuqtalar"][max(0, i - 1)], l["nuqtalar"][i]
        burchak = math.degrees(math.atan2(b["n"] - a["n"], b["e"] - a["e"]))
        if burchak > 90:
            burchak -= 180
        elif burchak < -90:
            burchak += 180
        ch = [p["chuqurlik"] for p in l["nuqtalar"] if p["chuqurlik"] is not None]
        tur = next((qq[8:] for t, qq, _ in QATLAMLAR if t == l["turi"]), l["turi"].upper())
        yorliq = f"{tur} D{l['diametr_mm']} {l['material']}" + (f" h={sum(ch) / len(ch):.2f}" if ch else "") \
            + ("" if l["sifat"] == "RASMIY" else f" ({l['sifat']})")
        o = matn_h * 0.6
        w.matn(yorliq, (a["e"] + b["e"]) / 2 - math.sin(math.radians(burchak)) * o,
               (a["n"] + b["n"]) / 2 + math.cos(math.radians(burchak)) * o, matn_h, burchak, "TRACE4D_YORLIQ")
    x0, h = max_e + 5, matn_h * 0.8
    qator = h * 1.8
    ustunlar = [("No", 3), ("E (X), m", 14), ("N (Y), m", 14), ("H, m", 9), ("Chuq., m", 8), ("Sifat", 8)]
    kenglik = sum(k for _, k in ustunlar)
    y = max_n
    w.matn(f"KOORDINATALAR KATALOGI ({sarlavha.get('koordinata_tizimi', 'WGS84 / UTM 42N')})", x0, y + qator * 0.6, h, 0, "TRACE4D_JADVAL")
    w.chiziq(x0, y, x0 + kenglik, y, "TRACE4D_JADVAL")
    x = x0
    for nomi, k in ustunlar:
        w.matn(nomi, x + 0.3, y - qator + h * 0.4, h, 0, "TRACE4D_JADVAL"); x += k
    y -= qator
    w.chiziq(x0, y, x0 + kenglik, y, "TRACE4D_JADVAL")
    for r, p in katalog:
        qiymat = [str(r), f"{p['e']:.3f}", f"{p['n']:.3f}", f"{p['h']:.3f}" if p["h"] is not None else "-",
                  f"{p['chuqurlik']:.2f}" if p["chuqurlik"] is not None else "-", p["sifat"]]
        x = x0
        for i, (_, k) in enumerate(ustunlar):
            w.matn(qiymat[i], x + 0.3, y - qator + h * 0.4, h, 0, "TRACE4D_JADVAL"); x += k
        y -= qator
        w.chiziq(x0, y, x0 + kenglik, y, "TRACE4D_JADVAL")
    x = x0
    for _, k in ustunlar + [("", 0)]:
        w.chiziq(x, max_n, x, y, "TRACE4D_JADVAL"); x += k
    satrlar = ["IJRO S'YOMKASI - YER OSTI TARMOQLARI", f"Obyekt: {sarlavha.get('obyekt', '')}",
               f"Order: {sarlavha.get('order', '')}", f"Pudratchi: {sarlavha.get('pudratchi', '')}",
               f"Buyurtmachi: {sarlavha.get('buyurtmachi', '')}", f"Sana: {sarlavha.get('sana', '')}",
               f"Raqamli muhr: {sarlavha.get('muhr', '')}", f"Koordinatalar: {sarlavha.get('koordinata_tizimi', 'WGS84 / UTM 42N')}",
               "Yaratildi: TRACE4D (RTK + LiDAR)", "Geodezist: ______________________   Imzo: ____________"]
    ry = y - qator * 2
    rb = qator * len(satrlar) + qator
    for ax, ay, bx, by in [(x0, ry, x0 + kenglik, ry), (x0, ry - rb, x0 + kenglik, ry - rb), (x0, ry, x0, ry - rb),
                           (x0 + kenglik, ry, x0 + kenglik, ry - rb)]:
        w.chiziq(ax, ay, bx, by, "TRACE4D_RAMKA")
    for i, s in enumerate(satrlar):
        w.matn(s, x0 + 0.6, ry - qator * (i + 1), h * 1.2 if i == 0 else h, 0, "TRACE4D_RAMKA")
    w.j(0, "ENDSEC"); w.j(0, "EOF")

    hw = _Yozuvchi()
    mx = (w.minx, w.miny, w.maxx, w.maxy) if math.isfinite(w.minx) else (0.0, 0.0, 0.0, 0.0)
    hw.j(0, "SECTION"); hw.j(2, "HEADER")
    hw.j(9, "$ACADVER"); hw.j(1, "AC1009"); hw.j(9, "$INSUNITS"); hw.j(70, 6)
    hw.j(9, "$EXTMIN"); hw.j(10, float(mx[0])); hw.j(20, float(mx[1])); hw.j(30, 0.0)
    hw.j(9, "$EXTMAX"); hw.j(10, float(mx[2])); hw.j(20, float(mx[3])); hw.j(30, 0.0)
    hw.j(0, "ENDSEC")
    hw.j(0, "SECTION"); hw.j(2, "TABLES")
    hw.j(0, "TABLE"); hw.j(2, "LTYPE"); hw.j(70, 2)
    hw.j(0, "LTYPE"); hw.j(2, "CONTINUOUS"); hw.j(70, 0); hw.j(3, "Solid line"); hw.j(72, 65); hw.j(73, 0); hw.j(40, 0.0)
    hw.j(0, "LTYPE"); hw.j(2, "DASHED"); hw.j(70, 0); hw.j(3, "__ __ __"); hw.j(72, 65); hw.j(73, 2); hw.j(40, 1.5)
    hw.j(49, 1.0); hw.j(49, -0.5)
    hw.j(0, "ENDTAB")
    barcha = [(q, a) for _, q, a in QATLAMLAR] + YORDAMCHI
    hw.j(0, "TABLE"); hw.j(2, "LAYER"); hw.j(70, len(barcha))
    for nomi, aci in barcha:
        hw.j(0, "LAYER"); hw.j(2, nomi); hw.j(70, 0); hw.j(62, aci); hw.j(6, "CONTINUOUS")
    hw.j(0, "ENDTAB"); hw.j(0, "ENDSEC")
    return "".join(hw.q + w.q)


def katalog_csv(liniyalar):
    q = ["raqam;turi;diametr_mm;e;n;h;chuqurlik_m;sifat"]
    r = 0
    for l in liniyalar:
        for p in l["nuqtalar"]:
            r += 1
            q.append(f"{r};{l['turi']};{l['diametr_mm']};{p['e']:.3f};{p['n']:.3f};"
                     + (f"{p['h']:.3f}" if p["h"] is not None else "") + ";"
                     + (f"{p['chuqurlik']:.2f}" if p["chuqurlik"] is not None else "") + f";{p['sifat']}")
    return "\n".join(q) + "\n"
