"""YEROSTI — lokalizatsiya: RTK (WGS84) → mahalliy tizim (MSK) va Boltiq balandligi (TALABLAR 15: LK-03, LK-04, LK-05).

Usul [E3 Emlid, T1 Trimble, N1 NGS]: koordinatasi ma'lum punktlar RTK bilan o'lchanadi, o'tish shu juftlardan topiladi.
- Gorizontal: mahalliy Transvers Merkator (WGS84, markaziy meridian — punktlar markazi, k0 = 1), keyin 4 parametrli
  Helmert (siljish, burilish, masshtab) eng kichik kvadratlar bilan.
- Vertikal: ζ = h_ellipsoid − H_Boltiq. 1–3 punktda doimiy siljish, ≥ 4 punktda qiya tekislik (Trimble: tekshiriladigan
  vertikal kalibrlash uchun 4 juft).
- Har punkt qoldig'i, RMS va "bittasini chiqarib" (LOO) bashorat xatosi — moslashtirish qoldig'i kam punktda optimistik.
Belgilash ГОСТ bo'yicha: X — shimol, Y — sharq. Krüger qatorlari Swift `UTM` (YerostiGeometriya) bilan bir xil.
Faqat stdlib.
"""
import math

A = 6378137.0
F = 1 / 298.257223563
_N = F / (2 - F)
_AA = A / (1 + _N) * (1 + _N ** 2 / 4 + _N ** 4 / 64)
_ALFA = [_N / 2 - 2 * _N ** 2 / 3 + 5 * _N ** 3 / 16, 13 * _N ** 2 / 48 - 3 * _N ** 3 / 5, 61 * _N ** 3 / 240]
_BETA = [_N / 2 - 2 * _N ** 2 / 3 + 37 * _N ** 3 / 96, _N ** 2 / 48 + _N ** 3 / 15, 17 * _N ** 3 / 480]
_DELTA = [2 * _N - 2 * _N ** 2 / 3 - 2 * _N ** 3, 7 * _N ** 2 / 3 - 8 * _N ** 3 / 5, 56 * _N ** 3 / 15]

# LK-04 [N1]: qoldiqlar 95 % da gorizontal < 2 sm, vertikal < 4 sm; kamida 4 gorizontal va 4 vertikal punkt
MIN_PUNKT = 4
QOLDIQ_GOR_M = 0.02
QOLDIQ_VER_M = 0.04
# LK-05: tekshiruv o'lchovi — LK-04 chegarasi + RTK 1σ (1 sm + 1 ppm gorizontal, 2 sm vertikal [N1])
TEKSHIRUV_GOR_M = 0.03
TEKSHIRUV_VER_M = 0.05
MASSHTAB_OGOH_PPM = 500.0      # mahalliy tizim tekisligi va ellipsoid farqi odatda ±200 ppm ichida
MASSHTAB_RAD_PPM = 2000.0      # undan katta — punkt yoki birlik xatosi (2 m / km)
QIYALIK_OGOH_PPM = 100.0       # ζ tekisligi qiyaligi 10 sm / km dan oshsa — reper xatosi yoki tog'li hudud
EKSTRAPOLYATSIYA_M = 10.0      # obyekt nuqtasi punktlar qamrovidan shuncha tashqarida — ogohlantirish [E3, N1]


def tm(lat, lon, lon0):
    """WGS84 → mahalliy TM (sharq e, shimol n), k0 = 1, siljishsiz. Swift `UTM.ga` formulasi."""
    fi = math.radians(lat)
    lam = math.radians(lon - lon0)
    sn = 2 * math.sqrt(_N) / (1 + _N)
    t = math.sinh(math.atanh(math.sin(fi)) - sn * math.atanh(sn * math.sin(fi)))
    xi = math.atan2(t, math.cos(lam))
    eta = math.atanh(math.sin(lam) / math.sqrt(1 + t * t))
    e, n = eta, xi
    for j in range(1, 4):
        e += _ALFA[j - 1] * math.cos(2 * j * xi) * math.sinh(2 * j * eta)
        n += _ALFA[j - 1] * math.sin(2 * j * xi) * math.cosh(2 * j * eta)
    return _AA * e, _AA * n


def tm_teskari(e, n, lon0):
    """Mahalliy TM → WGS84 (lat, lon). Swift `UTM.dan` formulasi."""
    xi, eta = n / _AA, e / _AA
    xi1, eta1 = xi, eta
    for j in range(1, 4):
        xi1 -= _BETA[j - 1] * math.sin(2 * j * xi) * math.cosh(2 * j * eta)
        eta1 -= _BETA[j - 1] * math.cos(2 * j * xi) * math.sinh(2 * j * eta)
    chi = math.asin(math.sin(xi1) / math.cosh(eta1))
    fi = chi
    for j in range(1, 4):
        fi += _DELTA[j - 1] * math.sin(2 * j * chi)
    return math.degrees(fi), lon0 + math.degrees(math.atan2(math.sinh(eta1), math.cos(xi1)))


class LokalizatsiyaXato(ValueError):
    pass


class Lokalizatsiya:
    """Hisoblangan o'tish. `oldinga`: WGS84 → (X shimol, Y sharq, H Boltiq); `teskari` — aksi.
    Parametrlar lug'atga saqlanadi va qayta tiklanadi (bazada JSON)."""

    def __init__(self, p):
        self.p = p

    @property
    def lon0(self):
        return self.p["lon0"]

    def _gor(self, e, n):
        p = self.p
        de, dn = e - p["ge"], n - p["gn"]
        y = p["a"] * de - p["b"] * dn + p["ly"]
        x = p["b"] * de + p["a"] * dn + p["lx"]
        return x, y

    def zeta(self, e, n):
        """Balandlik anomaliyasi ζ (h_ellipsoid − H_Boltiq) shu joyda; vertikal model bo'lmasa None."""
        v = self.p.get("v")
        if not v:
            return None
        return v["z0"] + v["ge"] * (e - v["ce"]) + v["gn"] * (n - v["cn"])

    def oldinga(self, lat, lon, h=None):
        e, n = tm(lat, lon, self.lon0)
        x, y = (self._gor(e, n) if self.p.get("gor") else (None, None))
        z = self.zeta(e, n)
        return x, y, (None if (h is None or z is None) else h - z)

    def teskari(self, x, y, H=None):
        p = self.p
        if not p.get("gor"):
            raise LokalizatsiyaXato("gorizontal lokalizatsiya yo'q")
        k = p["a"] ** 2 + p["b"] ** 2
        dy, dx = y - p["ly"], x - p["lx"]
        de = (p["a"] * dy + p["b"] * dx) / k
        dn = (-p["b"] * dy + p["a"] * dx) / k
        e, n = de + p["ge"], dn + p["gn"]
        lat, lon = tm_teskari(e, n, self.lon0)
        z = self.zeta(e, n)
        return lat, lon, (None if (H is None or z is None) else H + z)


def _gor_moslash(juftlar):
    """4 parametrli Helmert: w = c·z + t (kompleks shaklda), markazlashtirilgan eng kichik kvadratlar.
    juftlar: [(e, n, X, Y)]. 1 juftda faqat siljish (c = 1)."""
    k = len(juftlar)
    ge = sum(j[0] for j in juftlar) / k
    gn = sum(j[1] for j in juftlar) / k
    lx = sum(j[2] for j in juftlar) / k
    ly = sum(j[3] for j in juftlar) / k
    if k == 1:
        return {"a": 1.0, "b": 0.0, "ge": ge, "gn": gn, "lx": lx, "ly": ly, "model": "siljish"}
    s_zz = s_a = s_b = 0.0
    for e, n, x, y in juftlar:
        de, dn, dx, dy = e - ge, n - gn, x - lx, y - ly
        s_zz += de * de + dn * dn
        s_a += dy * de + dx * dn
        s_b += dx * de - dy * dn
    if s_zz < 1e-6:
        raise LokalizatsiyaXato("punktlar bir joyda: burilish va masshtab aniqlanmaydi")
    return {"a": s_a / s_zz, "b": s_b / s_zz, "ge": ge, "gn": gn, "lx": lx, "ly": ly, "model": "helmert4"}


def _ver_moslash(juftlar):
    """juftlar: [(e, n, ζ)]. 1–3 juftda doimiy, ≥ 4 da qiya tekislik ζ = z0 + ge·(e − ce) + gn·(n − cn)."""
    k = len(juftlar)
    ce = sum(j[0] for j in juftlar) / k
    cn = sum(j[1] for j in juftlar) / k
    z0 = sum(j[2] for j in juftlar) / k
    if k < MIN_PUNKT:
        return {"z0": z0, "ge": 0.0, "gn": 0.0, "ce": ce, "cn": cn, "model": "doimiy"}
    see = sen = snn = sez = snz = 0.0
    for e, n, z in juftlar:
        de, dn, dz = e - ce, n - cn, z - z0
        see += de * de
        sen += de * dn
        snn += dn * dn
        sez += de * dz
        snz += dn * dz
    det = see * snn - sen * sen
    # punktlar bir chiziqqa yaqin bo'lsa tekislik qiyaligi ko'ndalang yo'nalishda aniqlanmaydi (shovqinni kuchaytiradi):
    # ko'ndalang yoyilish (kovariatsiyaning kichik o'z qiymati) uzunasiga nisbatan ≥ 10 % va ≥ 2 m bo'lsin
    yarim, farq = (see + snn) / 2, math.sqrt(((see - snn) / 2) ** 2 + sen * sen)
    kichik, katta = max(yarim - farq, 0.0), yarim + farq
    if det <= 0 or math.sqrt(kichik / k) < max(2.0, 0.1 * math.sqrt(katta / k)):
        return {"z0": z0, "ge": 0.0, "gn": 0.0, "ce": ce, "cn": cn, "model": "doimiy (punktlar bir chiziqda)"}
    return {"z0": z0, "ge": (sez * snn - snz * sen) / det, "gn": (snz * see - sez * sen) / det, "ce": ce, "cn": cn,
            "model": "qiya tekislik"}


def _qobiq(nuqtalar):
    """Qavariq qobiq (monoton zanjir), soat miliga teskari."""
    q = sorted(set(nuqtalar))
    if len(q) < 3:
        return q

    def kr(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    past, yuqori = [], []
    for p in q:
        while len(past) >= 2 and kr(past[-2], past[-1], p) <= 0:
            past.pop()
        past.append(p)
    for p in reversed(q):
        while len(yuqori) >= 2 and kr(yuqori[-2], yuqori[-1], p) <= 0:
            yuqori.pop()
        yuqori.append(p)
    return past[:-1] + yuqori[:-1]


def _kesmagacha(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 <= 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2))
    return math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dy * t)


def qamrovdan_tashqari(qobiq, p):
    """Nuqtaning punktlar qobig'idan tashqaridagi masofasi (ichida — 0). Qobiq 3 nuqtadan kam — butun masofa."""
    if not qobiq:
        return math.inf
    if len(qobiq) == 1:
        return math.hypot(p[0] - qobiq[0][0], p[1] - qobiq[0][1])
    if len(qobiq) == 2:
        return _kesmagacha(p, qobiq[0], qobiq[1])
    ichida = all((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= -1e-9
                 for a, b in zip(qobiq, qobiq[1:] + qobiq[:1]))
    return 0.0 if ichida else min(_kesmagacha(p, a, b) for a, b in zip(qobiq, qobiq[1:] + qobiq[:1]))


def hisobla(juftlar):
    """LK-03/LK-04. juftlar: [{"nomi", "lat", "lon", "h", "X", "Y", "H"}] — X/Y yoki H bo'lmasa (masalan, faqat
    balandligi ma'lum reper) o'sha qism hisobga kirmaydi. Natija: parametrlar, qoldiqlar, LOO, sifat xulosasi."""
    if not juftlar:
        raise LokalizatsiyaXato("kalibrlash o'lchovi yo'q")
    lon0 = sum(j["lon"] for j in juftlar) / len(juftlar)
    for j in juftlar:
        j["e"], j["n"] = tm(j["lat"], j["lon"], lon0)
    gj = [j for j in juftlar if j.get("X") is not None and j.get("Y") is not None]
    vj = [j for j in juftlar if j.get("H") is not None and j.get("h") is not None]
    p = {"lon0": lon0, "gor": None, "v": None}
    if gj:
        g = _gor_moslash([(j["e"], j["n"], j["X"], j["Y"]) for j in gj])
        p.update({k: g[k] for k in ("a", "b", "ge", "gn", "lx", "ly")})
        p["gor"] = g["model"]
    if vj:
        p["v"] = _ver_moslash([(j["e"], j["n"], j["h"] - j["H"]) for j in vj])
    lok = Lokalizatsiya(p)

    gid, vid = {id(j) for j in gj}, {id(j) for j in vj}
    qoldiq = []
    for j in juftlar:
        x, y, H = lok.oldinga(j["lat"], j["lon"], j.get("h"))
        r = {"nomi": j["nomi"], "dX": None, "dY": None, "gor": None, "ver": None}
        if id(j) in gid:
            r.update(dX=j["X"] - x, dY=j["Y"] - y, gor=math.hypot(j["X"] - x, j["Y"] - y))
        if id(j) in vid and H is not None:
            r["ver"] = j["H"] - H
        qoldiq.append(r)

    # LOO: punkt chiqarib tashlanib, qolganlar bilan bashorat qilinadi (o'sha model turi bilan)
    loo = []
    for i, j in enumerate(juftlar):
        r = {"nomi": j["nomi"], "gor": None, "ver": None}
        qolgan_g = [k for k in gj if k is not j]
        if id(j) in gid and len(qolgan_g) >= 2:
            g = _gor_moslash([(k["e"], k["n"], k["X"], k["Y"]) for k in qolgan_g])
            x, y = Lokalizatsiya({**p, **{k: g[k] for k in ("a", "b", "ge", "gn", "lx", "ly")}})._gor(j["e"], j["n"])
            r["gor"] = math.hypot(j["X"] - x, j["Y"] - y)
        qolgan_v = [k for k in vj if k is not j]
        if id(j) in vid and len(qolgan_v) >= 1:   # kam punktda LOO oddiyroq modelga (doimiy) o'tadi
            v = _ver_moslash([(k["e"], k["n"], k["h"] - k["H"]) for k in qolgan_v])
            z = v["z0"] + v["ge"] * (j["e"] - v["ce"]) + v["gn"] * (j["n"] - v["cn"])
            r["ver"] = j["H"] - (j["h"] - z)
        loo.append(r)

    gq = [r["gor"] for r in qoldiq if r["gor"] is not None]
    vq = [r["ver"] for r in qoldiq if r["ver"] is not None]
    natija = {
        "parametrlar": p, "qoldiqlar": qoldiq, "loo": loo, "n_gor": len(gj), "n_ver": len(vj),
        "maks_gor": max(gq) if gq else None, "maks_ver": max((abs(v) for v in vq), default=None),
        "rms_gor": math.sqrt(sum(v * v for v in gq) / len(gq)) if gq else None,
        "rms_ver": math.sqrt(sum(v * v for v in vq) / len(vq)) if vq else None,
        "masshtab_ppm": (math.hypot(p["a"], p["b"]) - 1) * 1e6 if p["gor"] else None,
        "burilish_grad": math.degrees(math.atan2(p["b"], p["a"])) if p["gor"] else None,
        "qiyalik_ppm": (math.hypot(p["v"]["ge"], p["v"]["gn"]) * 1e6) if p["v"] else None,
        "qobiq": _qobiq([(j["Y"], j["X"]) for j in gj]),
    }
    natija.update(baholash(natija))
    return natija


def baholash(n):
    """LK-04: sifat chegarasi. Qaytaradi: yaroqli, xatolar (yaroqsiz qiladi), ogohlantirishlar."""
    xatolar, ogoh = [], []
    if n["n_gor"] < MIN_PUNKT:
        xatolar.append(f"gorizontal punktlar {n['n_gor']} ta: kamida {MIN_PUNKT} ta kerak (tekshiriladigan kalibrlash)")
    if n["n_ver"] < MIN_PUNKT:
        xatolar.append(f"balandligi ma'lum punktlar {n['n_ver']} ta: kamida {MIN_PUNKT} ta kerak")
    if n["maks_gor"] is not None and n["maks_gor"] > QOLDIQ_GOR_M:
        xatolar.append(f"gorizontal qoldiq {n['maks_gor'] * 100:.1f} sm > {QOLDIQ_GOR_M * 100:.0f} sm".replace(".", ","))
    if n["maks_ver"] is not None and n["maks_ver"] > QOLDIQ_VER_M:
        xatolar.append(f"vertikal qoldiq {n['maks_ver'] * 100:.1f} sm > {QOLDIQ_VER_M * 100:.0f} sm".replace(".", ","))
    m = n.get("masshtab_ppm")
    if m is not None and abs(m) > MASSHTAB_RAD_PPM:
        xatolar.append(f"masshtab {m:+.0f} ppm: punkt koordinatasi yoki birligi xato")
    elif m is not None and abs(m) > MASSHTAB_OGOH_PPM:
        ogoh.append(f"masshtab {m:+.0f} ppm odatdagidan katta")
    q = n.get("qiyalik_ppm")
    if q is not None and q > QIYALIK_OGOH_PPM:
        ogoh.append(f"balandlik tekisligi qiyaligi {q:.0f} ppm: reper xatosi yoki tog'li hudud, geoid modeli kerak")
    return {"yaroqli": not xatolar, "xatolar": xatolar, "ogohlantirishlar": ogoh}


def tekshiruv(lok, olchov, punkt):
    """LK-05: kalibrlashga kirmagan o'lchovning ma'lum punktdan og'ishi."""
    x, y, H = lok.oldinga(olchov["lat"], olchov["lon"], olchov.get("h"))
    gor = None if (x is None or punkt.get("X") is None) else math.hypot(punkt["X"] - x, punkt["Y"] - y)
    ver = None if (H is None or punkt.get("H") is None) else punkt["H"] - H
    otdi = (gor is None or gor <= TEKSHIRUV_GOR_M) and (ver is None or abs(ver) <= TEKSHIRUV_VER_M) \
        and not (gor is None and ver is None)
    return {"gor": gor, "ver": ver, "otdi": otdi}


# ---------- baza yozuvlaridan hisob (server va hujjat uchun) ----------

def juftlar_yasash(punktlar, olchovlar):
    """Kalibrlash o'lchovlari punkt bo'yicha o'rtachalanadi. punktlar: nazorat_punkt qatorlari (x shimol, y sharq, h);
    olchovlar: nazorat_olchov qatorlari. Qaytaradi: (juftlar, ishlatilgan o'lchov id lari)."""
    pm = {p["id"]: p for p in punktlar}
    guruh = {}
    for o in olchovlar:
        if o["maqsad"] == "kalibrlash" and o["punkt_id"] in pm:
            guruh.setdefault(o["punkt_id"], []).append(o)
    juftlar, idlar = [], []
    for pid, g in sorted(guruh.items(), key=lambda t: pm[t[0]]["nomi"]):
        p = pm[pid]
        hlar = [o["h"] for o in g if o.get("h") is not None]
        juftlar.append({"nomi": p["nomi"], "punkt_id": pid, "olchov_soni": len(g),
                        "lat": sum(o["lat"] for o in g) / len(g), "lon": sum(o["lon"] for o in g) / len(g),
                        "h": sum(hlar) / len(hlar) if hlar else None,
                        "X": p.get("x"), "Y": p.get("y"), "H": p.get("h")})
        idlar += [o["id"] for o in g]
    return juftlar, idlar


def tekshiruvlar(lok, punktlar, olchovlar):
    """LK-05: har tekshiruv o'lchovi uchun ma'lum punktdan og'ish."""
    pm = {p["id"]: p for p in punktlar}
    natija = []
    for o in olchovlar:
        if o["maqsad"] != "tekshiruv" or o["punkt_id"] not in pm:
            continue
        p = pm[o["punkt_id"]]
        t = tekshiruv(lok, o, {"X": p.get("x"), "Y": p.get("y"), "H": p.get("h")})
        natija.append({"olchov_id": o["id"], "nomi": p["nomi"], "vaqt": o.get("vaqt"), **t})
    return natija


def toshkent_sanasi(iso):
    """ISO (UTC) → Toshkent sanasi 'YYYY-MM-DD' (ish kuni)."""
    from datetime import datetime, timedelta, timezone
    if not iso:
        return None
    try:
        d = datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
    except ValueError:
        return str(iso)[:10]
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.astimezone(timezone(timedelta(hours=5))).strftime("%Y-%m-%d")


def kunlik_nazorat(ish_kunlari, tekshiruv_natijalari, kalibrlash_olchovlari, lok_yaroqli):
    """LK-05: har o'lchov kuni uchun o'tgan tekshiruv bormi. Yaroqli lokalizatsiyadagi kalibrlash o'lchovlari kuni ham
    tekshirilgan hisoblanadi: o'sha kunning baza o'rnatilishi punktlarga qoldiq chegarasida mos kelgan."""
    otgan = {toshkent_sanasi(t["vaqt"]) for t in tekshiruv_natijalari if t["otdi"]}
    if lok_yaroqli:
        otgan |= {toshkent_sanasi(o.get("vaqt")) for o in kalibrlash_olchovlari}
    return [{"kun": k, "tekshirilgan": k in otgan} for k in sorted(ish_kunlari)]


def utm_teskari(e, n, zona):
    """UTM (shimoliy yarimshar) → WGS84: k0 = 0,9996, sharq siljishi 500 km."""
    return tm_teskari((e - 500_000.0) / 0.9996, n / 0.9996, (zona - 1) * 6 - 180 + 3)


# ---------- CSV import (LK-01, LK-02) ----------

def _csv_qatorlar(matn):
    """Ajratgich avtomatik: tab, ';' yoki ','. ';' va tabda o'nlik vergul ham qabul qilinadi."""
    import csv
    import io
    qatorlar = [q for q in matn.replace("\r\n", "\n").replace("\r", "\n").split("\n") if q.strip()]
    if not qatorlar:
        return [], ","
    namuna = qatorlar[0]
    ajr = "\t" if "\t" in namuna else (";" if ";" in namuna else ",")
    return [[k.strip() for k in q] for q in csv.reader(io.StringIO("\n".join(qatorlar)), delimiter=ajr)], ajr


def _son_csv(s, ajr):
    s = (s or "").strip()
    if not s:
        return None
    if ajr != ",":
        s = s.replace(",", ".")
    return float(s)


def punkt_csv(matn):
    """Nazorat punktlari: nomi; X (shimol); Y (sharq); H (Boltiq); [sinf]; [manba]. Sarlavha qatori bo'lishi mumkin.
    Qaytaradi (qatorlar, xatolar)."""
    qatorlar, ajr = _csv_qatorlar(matn)
    natija, xatolar = [], []
    for i, q in enumerate(qatorlar, 1):
        if i == 1 and q and not any(ch.isdigit() for ch in "".join(q[1:3])):
            continue                                          # sarlavha
        if len(q) < 4:
            xatolar.append(f"{i}-qator: kamida 4 ustun kerak (nomi; X; Y; H)")
            continue
        try:
            natija.append({"nomi": q[0], "x": _son_csv(q[1], ajr), "y": _son_csv(q[2], ajr), "h": _son_csv(q[3], ajr),
                           "sinf": q[4] if len(q) > 4 else "", "manba": q[5] if len(q) > 5 else ""})
        except ValueError:
            xatolar.append(f"{i}-qator: son o'qilmadi")
    return natija, xatolar


def _vaqt_emlid(s):
    """Emlid Flow: '2024-05-14 10:20:30.1 UTC+05:00' → ISO (UTC); o'qilmasa None."""
    from datetime import datetime, timezone
    if not s:
        return None
    t = s.strip().replace(" UTC", "").replace("UTC", "")
    try:
        d = datetime.fromisoformat(t)
    except ValueError:
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.astimezone(timezone.utc).isoformat(timespec="seconds")


def olchov_csv(matn, maqsad="kalibrlash"):
    """O'lchovlar: Emlid Flow eksporti (sarlavha: Name, Latitude, Longitude, Ellipsoidal height, Solution status,
    Lateral RMS, Elevation RMS, Averaging start/end, Samples — RMS metrda) yoki oddiy shakl
    nomi; lat; lon; h_ellipsoid; σH_sm; σV_sm. Tavsif yoki kodda "tekshiruv"/"check" bo'lsa — tekshiruv o'lchovi."""
    qatorlar, ajr = _csv_qatorlar(matn)
    if not qatorlar:
        return [], ["CSV bo'sh"]
    sarl = [s.lower() for s in qatorlar[0]]

    def ust(*nomlar):
        for n in nomlar:
            for i, s in enumerate(sarl):
                if s == n:
                    return i
        return None

    natija, xatolar = [], []
    if ust("latitude") is not None:
        i_n, i_la, i_lo = ust("name"), ust("latitude"), ust("longitude")
        i_h, i_st = ust("ellipsoidal height"), ust("solution status")
        i_sh, i_sv = ust("lateral rms"), ust("elevation rms")
        i_b, i_o, i_s = ust("averaging start"), ust("averaging end"), ust("samples")
        i_d, i_c, i_a = ust("description"), ust("code"), ust("antenna height")
        for k, q in enumerate(qatorlar[1:], 2):
            try:
                ol = lambda i: q[i] if (i is not None and i < len(q)) else ""   # noqa: E731
                boshi, oxiri = _vaqt_emlid(ol(i_b)), _vaqt_emlid(ol(i_o))
                dav = None
                if boshi and oxiri:
                    from datetime import datetime
                    dav = (datetime.fromisoformat(oxiri) - datetime.fromisoformat(boshi)).total_seconds()
                belgi = (ol(i_d) + " " + ol(i_c)).lower()
                natija.append({"punkt": ol(i_n), "lat": _son_csv(ol(i_la), ajr), "lon": _son_csv(ol(i_lo), ajr),
                               "h": _son_csv(ol(i_h), ajr), "rtk_holat": ol(i_st).upper() or "?",
                               "sigma_h_sm": None if _son_csv(ol(i_sh), ajr) is None else _son_csv(ol(i_sh), ajr) * 100,
                               "sigma_v_sm": None if _son_csv(ol(i_sv), ajr) is None else _son_csv(ol(i_sv), ajr) * 100,
                               "epoxalar": int(_son_csv(ol(i_s), ajr)) if _son_csv(ol(i_s), ajr) is not None else None,
                               "davomiylik_s": dav, "vaqt": boshi, "antenna_m": _son_csv(ol(i_a), ajr),
                               "maqsad": "tekshiruv" if ("tekshiruv" in belgi or "check" in belgi) else maqsad})
            except ValueError:
                xatolar.append(f"{k}-qator: son o'qilmadi")
        return natija, xatolar
    for k, q in enumerate(qatorlar, 1):
        if k == 1 and not any(ch.isdigit() for ch in "".join(q[1:3])):
            continue
        if len(q) < 4:
            xatolar.append(f"{k}-qator: kamida 4 ustun kerak (nomi; lat; lon; h)")
            continue
        try:
            natija.append({"punkt": q[0], "lat": _son_csv(q[1], ajr), "lon": _son_csv(q[2], ajr), "h": _son_csv(q[3], ajr),
                           "sigma_h_sm": _son_csv(q[4], ajr) if len(q) > 4 else None,
                           "sigma_v_sm": _son_csv(q[5], ajr) if len(q) > 5 else None,
                           "maqsad": (q[6].strip().lower() if len(q) > 6 and q[6].strip() else maqsad),
                           "rtk_holat": "FIX", "vaqt": None})
        except ValueError:
            xatolar.append(f"{k}-qator: son o'qilmadi")
    return natija, xatolar
