"""YEROSTI — ijro hujjati geometriyasi (TALABLAR 14: IH-04, IH-06, IH-07). Faqat stdlib, sof funksiyalar.

ГОСТ Р 51872-2024: G.1.1 xarakterli nuqtalar (burilish, nishab o'zgarishi, to'g'ri qismda kamida har 50 m, boshqa
tarmoqlar bilan kesishuv), G.2 profil (pikitaj, masofa, nishab qiymati va yo'nalishi), 5.5 loyihadan og'ish.
Kirish: `yerosti_chizma.liniyalar_utm` natijasi (UTM sharq e, shimol n, h — quvur O'QI ellipsoid balandligi).
"""
import math
import re

ORALIQ_M = 50.0             # G.1.1: to'g'ri qismda oraliq nuqta har ≤ 50 m
BURILISH_GRAD = 3.0         # shundan katta yo'nalish o'zgarishi — burilish nuqtasi
NISHAB_FARQ = 0.005         # nishab 5 ‰ dan ko'p o'zgarsa — nishab o'zgarish nuqtasi (RTK σV ≤ 5 sm, 20 m oraliqda 2,5 ‰)
BAZA_M = 2.0                # yo'nalish kamida 2 m bazada o'lchanadi: skan o'qi har ~0,5 m da nuqta beradi,
                            # qo'shni nuqtalar orasidagi shovqin soxta "burilish" bo'lib ko'rinmasin
NISHAB_BAZA_M = 5.0         # nishab har tomonda 5 m oynada eng kichik kvadratlar bilan: 2 mm balandlik shovqini 2 m
                            # vatarda ~2 ‰ farq beradi (sinovda soxta nishab nuqtalari chiqdi), 5 m oynada ~0,6 ‰
ZICH_M = 1.0                # qo'shni nuqta shundan yaqin — skan (zich) uchastka: to'liq baza bo'lmasa (liniya cheti)
                            # tur aniqlanmaydi; siyrak RTK nuqtalarida esa qo'shnilar bilan hisoblanadi
TUTASHUV_M = 0.05           # ikki liniya uchi shu masofada bo'lsa — tutash (diametr/material o'zgarishi)
YORLIQ = {"bosh": "boshlanish", "oxir": "oxiri", "burilish": "burilish", "nishab": "nishab o'zgarishi",
          "tutashuv": "Ø yoki material o'zgarishi", "olchangan": "o'lchangan", "oraliq": "oraliq (hisoblangan)"}


def radius(l):
    return (l.get("diametr_mm") or 0) / 2000.0


def gor(a, b):
    return math.hypot(b["e"] - a["e"], b["n"] - a["n"])


def stansiyalar(P):
    s = [0.0]
    for i in range(1, len(P)):
        s.append(s[-1] + gor(P[i - 1], P[i]))
    return s


def pikitaj(s):
    """Stansiya → "PK0+12,50" (100 m li pikitaj)."""
    s = round(s, 2)
    pk = int(s // 100)
    return f"PK{pk}+{max(0.0, s - pk * 100):05.2f}".replace(".", ",")


def _azimut(a, b):
    return math.atan2(b["e"] - a["e"], b["n"] - a["n"])


def _ichki(a, b, t, kalit):
    va, vb = a.get(kalit), b.get(kalit)
    return None if va is None or vb is None else va + (vb - va) * t


_SIFAT_DARAJA = {"RASMIY": 0, "SKAN": 1, "PAST": 2}


def _yomoni(a, b):
    return a if _SIFAT_DARAJA.get(a, 2) >= _SIFAT_DARAJA.get(b, 2) else b


def nuqta_tayyorla(p, r):
    """Nuqtaga quvur usti va yer balandligini qo'shadi (o'q h + r; yer = usti + chuqurlik)."""
    q = dict(p)
    h = q.get("h")
    q["usti"] = None if h is None else h + r
    q["yer"] = None if (h is None or q.get("chuqurlik") is None) else h + r + q["chuqurlik"]
    return q


def _orqa(s, i):
    j = i - 1
    while j > 0 and s[i] - s[j] < BAZA_M:
        j -= 1
    return j


def _old(s, i):
    j = i + 1
    while j < len(s) - 1 and s[j] - s[i] < BAZA_M:
        j += 1
    return j


def _zich(s, i):
    return min(s[i] - s[i - 1], s[i + 1] - s[i]) < ZICH_M


def _burilish(P, s, i):
    ja, jb = _orqa(s, i), _old(s, i)
    if _zich(s, i) and (s[i] - s[ja] < BAZA_M or s[jb] - s[i] < BAZA_M):
        return None
    a, p, b = P[ja], P[i], P[jb]
    return math.degrees(abs((_azimut(p, b) - _azimut(a, p) + math.pi) % (2 * math.pi) - math.pi))


def _qiyalik(P, s, idx):
    """Eng kichik kvadratlar nishabi (dh/ds) — idx nuqtalari bo'yicha; balandligi yo'qlar tashlanadi."""
    q = [(s[j], P[j]["h"]) for j in idx if P[j].get("h") is not None]
    if len(q) < 2:
        return None
    sm, hm = sum(a for a, _ in q) / len(q), sum(b for _, b in q) / len(q)
    d = sum((a - sm) ** 2 for a, _ in q)
    return None if d <= 1e-12 else sum((a - sm) * (b - hm) for a, b in q) / d


def _nishab_farqi(P, s, i):
    if P[i].get("h") is None:
        return None
    orqa, j = [i, i - 1], i - 2
    while j >= 0 and s[i] - s[j] <= NISHAB_BAZA_M:
        orqa.append(j)
        j -= 1
    old, j = [i, i + 1], i + 2
    while j < len(P) and s[j] - s[i] <= NISHAB_BAZA_M:
        old.append(j)
        j += 1
    if _zich(s, i) and (s[i] - s[min(orqa)] < 0.8 * NISHAB_BAZA_M or s[max(old)] - s[i] < 0.8 * NISHAB_BAZA_M):
        return None
    g1, g2 = _qiyalik(P, s, orqa), _qiyalik(P, s, old)
    return None if g1 is None or g2 is None else abs(g2 - g1)


def _turlar(P, s):
    """Ichki nuqtalar turi: burilish, nishab yoki o'lchangan. Zich nuqtalarda bir egilish bir necha nuqtaga yoyiladi —
    o'lchov oynasi ichida eng kuchlisi qoladi (avval burilishlar, keyin nishab)."""
    turlar = ["olchangan"] * len(P)
    qabul = []
    for tur, baho, chek, oyna in (("burilish", _burilish, BURILISH_GRAD, BAZA_M),
                                   ("nishab", _nishab_farqi, NISHAB_FARQ, NISHAB_BAZA_M)):
        nomzod = []
        for i in range(1, len(P) - 1):
            b = baho(P, s, i)
            if b is not None and b >= chek:
                nomzod.append((b, i))
        for b, i in sorted(nomzod, reverse=True):
            if all(abs(s[i] - s[j]) >= oyna for j in qabul):
                qabul.append(i)
                turlar[i] = tur
    return turlar


def xarakterli(l, boshqa_uchlar=(), oraliq=ORALIQ_M):
    """G.1.1: liniyaning xarakterli nuqtalari stansiya tartibida. `boshqa_uchlar` — shu obyektdagi boshqa liniyalar uchlari
    [(e, n, diametr_mm, material)] — tutashuvda diametr yoki material o'zgarsa belgilanadi. Turi `YORLIQ` kalitlarida."""
    P, r = l["nuqtalar"], radius(l)
    if len(P) < 2:
        return []
    s = stansiyalar(P)
    turlar = _turlar(P, s)
    natija = []
    for i, p in enumerate(P):
        turi = turlar[i]
        if i == 0 or i == len(P) - 1:
            turi = "bosh" if i == 0 else "oxir"
            for (e, n, d, mat) in boshqa_uchlar:
                if math.hypot(p["e"] - e, p["n"] - n) <= TUTASHUV_M and (d != l.get("diametr_mm") or (mat or "") != (l.get("material") or "")):
                    turi = "tutashuv"
        q = nuqta_tayyorla(p, r)
        q.update(turi=turi, stansiya=s[i], hisoblangan=False)
        natija.append(q)
        if i < len(P) - 1:
            L = s[i + 1] - s[i]
            bolak = max(1, math.ceil(L / oraliq - 1e-9))
            for k in range(1, bolak):
                t = k / bolak
                b = P[i + 1]
                o = {"e": p["e"] + (b["e"] - p["e"]) * t, "n": p["n"] + (b["n"] - p["n"]) * t,
                     "h": _ichki(p, b, t, "h"), "chuqurlik": _ichki(p, b, t, "chuqurlik"),
                     "sifat": _yomoni(p.get("sifat", "PAST"), b.get("sifat", "PAST")), "manba": "hisoblangan",
                     "sigma_h_sm": None, "rtk_holat": None, "izoh": ""}
                o = nuqta_tayyorla(o, r)
                o.update(turi="oraliq", stansiya=s[i] + L * t, hisoblangan=True)
                natija.append(o)
    return natija


def nishablar(l):
    """G.2.2: har kesmaning nishabi (‰, o'q bo'yicha; + — stansiya bo'yicha ko'tariladi) va uzunligi."""
    P = l["nuqtalar"]
    s = stansiyalar(P)
    natija = []
    for i in range(len(P) - 1):
        L = s[i + 1] - s[i]
        a, b = P[i].get("h"), P[i + 1].get("h")
        natija.append({"bosh": s[i], "oxir": s[i + 1], "uzunlik": L,
                       "promille": None if (a is None or b is None or L <= 0) else (b - a) / L * 1000})
    return natija


def _kesma_kesishuvi(a, b, c, d):
    """2D kesmalar kesishuvi → (t, u) parametrlar yoki None (parallel yoki kesishmaydi)."""
    r = (b["e"] - a["e"], b["n"] - a["n"])
    q = (d["e"] - c["e"], d["n"] - c["n"])
    den = r[0] * q[1] - r[1] * q[0]
    if abs(den) < 1e-12:
        return None
    w = (c["e"] - a["e"], c["n"] - a["n"])
    t = (w[0] * q[1] - w[1] * q[0]) / den
    u = (w[0] * r[1] - w[1] * r[0]) / den
    if -1e-9 <= t <= 1 + 1e-9 and -1e-9 <= u <= 1 + 1e-9:
        return t, u
    return None


def _uchdami(x, P):
    return min(math.hypot(x["e"] - P[0]["e"], x["n"] - P[0]["n"]),
               math.hypot(x["e"] - P[-1]["e"], x["n"] - P[-1]["n"])) <= TUTASHUV_M


# IH-04a: kesishuvda vertikal oraliq me'yori (в свету), m. Manba: СНиП 2.07.01-89* п.7.23 → СНиП II-89-80 п.4.11; ShNK
# 2.07.01-03 (O'zbekiston) shu asosda; СП 42.13330.2016 (dolzarb tahrir) jadvali bir xil: quvur–quvur 0,2; suv–kanalizatsiya
# 0,4 (suv quvuri yuqorida; pastda — faqat futlyarda); quvur–kabel 0,5; kabel–kabel 0,5 (ajratuvchi bilan 0,15); gaz–kabel 0,5.
KABEL_TURLARI = {"elektr", "optika"}
MEYOR_MANBA = "СНиП 2.07.01-89* п.7.23 / СНиП II-89-80 п.4.11 (ShNK 2.07.01-03 asosi); СП 42.13330.2016"


def kesishuv_meyori(a, b):
    """Ikki tarmoq turi kesishganda eng kichik vertikal oraliq (m), shart va izoh."""
    if a in KABEL_TURLARI and b in KABEL_TURLARI:
        return 0.5, None, "kabel–kabel 0,5 m (ajratuvchi plita yoki quvurda 0,15 m)"
    if a in KABEL_TURLARI or b in KABEL_TURLARI:
        return 0.5, None, "quvur–kabel 0,5 m"
    if {a, b} == {"suv", "kanalizatsiya"}:
        return 0.4, "suv_yuqorida", "suv–kanalizatsiya 0,4 m, suv quvuri yuqorida"
    return 0.2, None, "quvur–quvur 0,2 m"


def kesishuv_bahosi(l_turi, boshqa_turi, oraliq, boshqa_ustida):
    """IH-04a: kesishuvni me'yor bilan solishtirish → meyor_m, xulosa (mos | MOS EMAS | baholanmadi), izoh.
    Hujjat yaroqliligiga ta'sir qilmaydi — loyihachi va tarmoq egasi e'tiboriga."""
    m, shart, izoh = kesishuv_meyori(l_turi or "", boshqa_turi or "")
    if oraliq is None:
        return {"meyor_m": m, "xulosa": "baholanmadi", "izoh": izoh + "; balandlik yo'q"}
    sabab = []
    if oraliq < m - 1e-9:
        sabab.append(f"oraliq {oraliq:.2f} m < {m:.1f} m")
    if shart == "suv_yuqorida":
        suv_ustida = (l_turi == "suv" and boshqa_ustida is False) or (boshqa_turi == "suv" and boshqa_ustida is True)
        if not suv_ustida:
            sabab.append("suv quvuri kanalizatsiya ostida (faqat futlyarda ruxsat)")
    return {"meyor_m": m, "xulosa": "MOS EMAS" if sabab else "mos", "izoh": izoh + ("; " + "; ".join(sabab) if sabab else "")}


def kesishuvlar(l, boshqalar):
    """IH-04: liniyaning reestrdagi boshqa tarmoqlar bilan kesishuvi. Vertikal oraliq — quvur sirtlari orasidagi masofa
    (o'qlar farqi − ikki radius); balandlik ma'lum bo'lmasa None. Tutashuv kesishuv emas: ikki liniya uchma-uch tegsa
    yoki bir xil turdagi liniya uchi bilan ikkinchisiga ulansa (tarmoqlanish)."""
    P, r1 = l["nuqtalar"], radius(l)
    s = stansiyalar(P)
    natija = []
    for o in boshqalar:
        if o.get("id") is not None and o.get("id") == l.get("id"):
            continue
        Q, r2 = o["nuqtalar"], radius(o)
        topilgan = []
        for i in range(len(P) - 1):
            for j in range(len(Q) - 1):
                k = _kesma_kesishuvi(P[i], P[i + 1], Q[j], Q[j + 1])
                if not k:
                    continue
                t, u = k
                x = {"e": P[i]["e"] + (P[i + 1]["e"] - P[i]["e"]) * t, "n": P[i]["n"] + (P[i + 1]["n"] - P[i]["n"]) * t}
                u1, u2 = _uchdami(x, P), _uchdami(x, Q)
                if (u1 and u2) or ((u1 or u2) and o.get("turi") == l.get("turi")):
                    continue
                if any(math.hypot(x["e"] - y["e"], x["n"] - y["n"]) < 0.01 for y in topilgan):
                    continue  # ikki kesma tutashgan uchda bir kesishuv ikki marta topiladi
                topilgan.append(x)
                h1, h2 = _ichki(P[i], P[i + 1], t, "h"), _ichki(Q[j], Q[j + 1], u, "h")
                oraliq = None if (h1 is None or h2 is None) else abs(h1 - h2) - (r1 + r2)
                ustida = None if (h1 is None or h2 is None) else h2 > h1
                natija.append({
                    "e": x["e"], "n": x["n"], "stansiya": s[i] + (s[i + 1] - s[i]) * t, "h": h1, "boshqa_h": h2,
                    "oraliq": oraliq, "boshqa_id": o.get("id"), "boshqa_turi": o.get("turi"),
                    "boshqa_diametr_mm": o.get("diametr_mm"), "boshqa_sifat": o.get("sifat"),
                    "boshqa_obyekt": o.get("obyekt_nomi"),
                    "boshqa_ustida": ustida,
                    **kesishuv_bahosi(l.get("turi"), o.get("turi"), oraliq, ustida),
                })
    natija.sort(key=lambda k: k["stansiya"])
    return natija


# ---------- IH-07: loyiha DXF ----------

class DXFXato(ValueError):
    pass


_DXF_UNICODE = re.compile(r"\\U\+([0-9A-Fa-f]{4})")
_MTEXT_GURUH = re.compile(r"\{\\[^;{}]*;|[{}]")
_MTEXT_KOD = re.compile(r"\\[A-Za-z][^;\\]*;|\\[~]")


def _dxf_matn(s):
    """DXF matni: \\U+XXXX unicode qochishlari (kirill) va MTEXT formatlash kodlari tozalanadi."""
    s = _DXF_UNICODE.sub(lambda m: chr(int(m.group(1), 16)), s)
    s = s.replace("\\P", " ").replace("\\p", " ")
    s = _MTEXT_GURUH.sub("", s)
    s = _MTEXT_KOD.sub("", s)
    return s.replace("%%c", "Ø").replace("%%C", "Ø").replace("%%d", "°").replace("%%D", "°").strip()


def _dxf_ajrat(matn, matn_ham=False):
    """ASCII DXF ENTITIES bo'limidan LINE, LWPOLYLINE, POLYLINE/VERTEX chiziqlari va (kerak bo'lsa) TEXT/MTEXT.
    Bloklar (INSERT) va boshqa obyektlar o'qilmaydi. Koordinata tekshirilmaydi."""
    q = matn.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    juftlar = []
    for i in range(0, len(q) - 1, 2):
        try:
            juftlar.append((int(q[i].strip()), q[i + 1].strip()))
        except ValueError:
            raise DXFXato("DXF formati buzilgan (guruh kodi raqam emas)") from None
    ichida, chiziqlar, matnlar, joriy, tur = False, [], [], None, None

    def yop():
        nonlocal joriy, tur
        if joriy and len(joriy["nuqtalar"]) >= 2:
            if joriy.get("yopiq") and tuple(joriy["nuqtalar"][0]) != tuple(joriy["nuqtalar"][-1]):
                joriy["nuqtalar"].append(tuple(joriy["nuqtalar"][0]))
            chiziqlar.append(joriy)
        joriy, tur = None, None

    k = 0
    try:
        while k < len(juftlar):
            kod, v = juftlar[k]
            if kod == 0 and v == "SECTION" and k + 1 < len(juftlar) and juftlar[k + 1] == (2, "ENTITIES"):
                ichida = True
                k += 2
                continue
            if not ichida:
                k += 1
                continue
            if kod == 0:
                if v == "ENDSEC":
                    yop()
                    break
                if v == "VERTEX" and tur == "POLYLINE":
                    x = y = z = None
                    k += 1
                    while k < len(juftlar) and juftlar[k][0] != 0:
                        c, w = juftlar[k]
                        if c == 10: x = float(w)
                        elif c == 20: y = float(w)
                        elif c == 30: z = float(w)
                        k += 1
                    if x is not None and y is not None:
                        joriy["nuqtalar"].append((x, y, z if joriy.get("3d") else joriy.get("z")))
                    continue
                if v == "SEQEND":
                    yop()
                    k += 1
                    continue
                yop()
                if matn_ham and v in ("TEXT", "MTEXT"):
                    t = {"x": None, "y": None, "x2": None, "y2": None, "h": None, "burchak": 0.0, "matn": "", "tekis": 0}
                    k += 1
                    while k < len(juftlar) and juftlar[k][0] != 0:
                        c, w = juftlar[k]
                        if c == 10: t["x"] = float(w)
                        elif c == 20: t["y"] = float(w)
                        elif c == 11: t["x2"] = float(w)
                        elif c == 21: t["y2"] = float(w)
                        elif c == 40: t["h"] = float(w)
                        elif c == 50: t["burchak"] = float(w)
                        elif c in (72, 73) and v == "TEXT": t["tekis"] |= int(float(w))
                        elif c in (1, 3): t["matn"] += w
                        k += 1
                    if v == "TEXT" and t["tekis"] and t["x2"] is not None:
                        t["x"], t["y"] = t["x2"], t["y2"]       # tekislangan matn — o'rni 11/21 da
                    elif v == "MTEXT" and t["x2"] is not None and not t["burchak"]:
                        t["burchak"] = math.degrees(math.atan2(t["y2"] or 0.0, t["x2"]))   # 11/21 — yo'nalish vektori
                    if t["x"] is not None and t["y"] is not None:
                        matnlar.append({"x": t["x"], "y": t["y"], "h": t["h"], "burchak": t["burchak"],
                                        "matn": _dxf_matn(t["matn"])[:120]})
                    continue
                if v in ("LINE", "LWPOLYLINE", "POLYLINE"):
                    tur = v
                    joriy = {"qatlam": "", "nuqtalar": [], "z": None, "3d": False}
                    x = y = z = x2 = y2 = z2 = None
                    k += 1
                    while k < len(juftlar) and juftlar[k][0] != 0:
                        c, w = juftlar[k]
                        if c == 8: joriy["qatlam"] = w
                        elif v == "LINE" and c == 10: x = float(w)
                        elif v == "LINE" and c == 20: y = float(w)
                        elif v == "LINE" and c == 30: z = float(w)
                        elif v == "LINE" and c == 11: x2 = float(w)
                        elif v == "LINE" and c == 21: y2 = float(w)
                        elif v == "LINE" and c == 31: z2 = float(w)
                        elif v == "LWPOLYLINE" and c == 38: joriy["z"] = float(w)
                        elif v == "LWPOLYLINE" and c == 10: joriy["nuqtalar"].append([float(w), None, None])
                        elif v == "LWPOLYLINE" and c == 20 and joriy["nuqtalar"]: joriy["nuqtalar"][-1][1] = float(w)
                        elif v == "POLYLINE" and c == 30: joriy["z"] = float(w)
                        elif v == "POLYLINE" and c == 70:
                            joriy["3d"] = bool(int(float(w)) & 8)
                            joriy["yopiq"] = bool(int(float(w)) & 1)
                        elif v == "LWPOLYLINE" and c == 70: joriy["yopiq"] = bool(int(float(w)) & 1)
                        k += 1
                    if v == "LINE":
                        if None not in (x, y, x2, y2):
                            joriy["nuqtalar"] = [(x, y, z), (x2, y2, z2)]
                        yop()
                    elif v == "LWPOLYLINE":
                        joriy["nuqtalar"] = [(a, b, joriy["z"]) for a, b, _ in joriy["nuqtalar"] if b is not None]
                        yop()
                    continue
            k += 1
    except ValueError:
        raise DXFXato("DXF formati buzilgan (son kutilgan joyda matn)") from None
    natija = []
    for c in chiziqlar:
        # 2D chizmada balandlik 0 yoziladi — bu "loyiha belgisi 0 m" emas, balandlik yo'q degani
        zsiz = all(z is None or z == 0.0 for (_, _, z) in c["nuqtalar"])
        natija.append({"qatlam": c["qatlam"], "nuqtalar": [[e, n, None if zsiz else z] for (e, n, z) in c["nuqtalar"]]})
    return natija, matnlar


def dxf_oqi(matn, utm=True):
    """Loyiha DXF: LINE, LWPOLYLINE, POLYLINE/VERTEX → [{"qatlam", "nuqtalar": [[e, n, z|None]]}].
    utm=True — koordinatalar UTM oralig'ida bo'lishi shart; mahalliy tizim (LK-07) uchun utm=False, yaqinlik serverda."""
    chiziqlar, _ = _dxf_ajrat(matn)
    if not chiziqlar:
        raise DXFXato("DXF da LINE, POLYLINE yoki LWPOLYLINE topilmadi")
    if utm:
        for c in chiziqlar:
            for (e, n, _) in c["nuqtalar"]:
                if not (100_000 <= e <= 900_000 and 0 <= n <= 9_400_000):
                    raise DXFXato(f"koordinata UTM emas ({e:.1f}; {n:.1f}): loyihani UTM zonasida eksport qiling yoki "
                                  "obyektni lokalizatsiya qilib mahalliy tizimda yuklang")
    return chiziqlar


def dxf_topo_oqi(matn):
    """LK-08: topografik plan — chiziqlar va matnlar (ko'cha nomi, uy raqami, belgilar)."""
    chiziqlar, matnlar = _dxf_ajrat(matn, matn_ham=True)
    if not chiziqlar and not matnlar:
        raise DXFXato("topoplan DXF da chiziq ham, matn ham topilmadi")
    return {"chiziqlar": chiziqlar, "matnlar": matnlar}


def _eng_yaqin_segment(p, chiziqlar):
    eng = None
    for ci, c in enumerate(chiziqlar):
        P = c["nuqtalar"]
        for i in range(len(P) - 1):
            ax, ay, az = P[i]
            bx, by, bz = P[i + 1]
            dx, dy = bx - ax, by - ay
            l2 = dx * dx + dy * dy
            t = 0.0 if l2 <= 0 else max(0.0, min(1.0, ((p["e"] - ax) * dx + (p["n"] - ay) * dy) / l2))
            fx, fy = ax + dx * t, ay + dy * t
            d = math.hypot(p["e"] - fx, p["n"] - fy)
            if eng is None or d < eng[0]:
                z = None if (az is None or bz is None) else az + (bz - az) * t
                eng = (d, z, c["qatlam"], ci)
    return eng


Z_TURLARI = {"oq": "quvur o'qi", "usti": "quvur usti", "tubi": "quvur tubi (tashqi)"}
LOYIHA_YAQIN_M = 5.0        # nuqtadan shu masofadan uzoq loyiha chizig'i boshqa tarmoqniki deb olinadi (belgi olinmaydi)


def loyihadan_ogish(nuqtalar, loyiha, r=0.0, z_turi="oq"):
    """IH-07 [ГОСТ 5.5]: har nuqtaning eng yaqin loyiha chizig'idan gorizontal og'ishi; loyihada Z bo'lsa — o'lchangan
    mos belgi (z_turi: o'q, ust yoki tub) minus loyiha Z. Natija nuqtalar bilan bir tartibda; loyiha yo'q bo'lsa None."""
    natija = []
    for p in nuqtalar:
        e = _eng_yaqin_segment(p, loyiha) if loyiha else None
        if e is None:
            natija.append(None)
            continue
        d, z, qatlam, _ = e
        h = p.get("h")
        olchangan = None if h is None else {"oq": h, "usti": h + r, "tubi": h - r}.get(z_turi, h)
        yaqin = d <= LOYIHA_YAQIN_M
        natija.append({"gorizontal": d, "loyiha_z": z if yaqin else None, "qatlam": qatlam, "yaqin": yaqin,
                       "vertikal": None if (z is None or olchangan is None or not yaqin) else olchangan - z})
    return natija
