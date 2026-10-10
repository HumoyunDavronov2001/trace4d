"""YEROSTI — quvur tasdig'i (TALABLAR 18: TQ, T-031). Faqat stdlib + sof modullar (yerosti_ijro_geo, yerosti_lokal).

Skan (LiDAR + RTK traektoriya) bilan olingan quvur o'qi nuqtalari SKAN sifatida keladi: ular to'g'ridan-to'g'ri RTK bilan
o'lchanmagan. TASDIQ — vexa uchi quvur USTIDA (yoki ochiq uchida O'QIDA) turganda RTK FIX o'lchovi, T-103 chegaralarida.
Har tasdiq eng yaqin liniyaga bog'lanadi, skan o'qidan gorizontal va vertikal og'ishi hisoblanadi.
Liniya TASDIQLANGAN: hamma tasdiqlari chegarada; boshi, oxiri va har burilish (G.1.1 xarakterli nuqtalar) 1 m ichida
tasdiqlangan; qo'shni tasdiqlar orasi ≤ 50 m [ГОСТ Р 51872 G.1.1]. Shunda uning SKAN nuqtalari hujjatga RASMIY o'rnida
kiradi (yaroqlilik). Bitta tasdiq chegaradan chiqsa — FARQ: skan georeferensi shubhali, qayta o'lchanadi.
"""
import math

import yerosti_ijro_geo as geo
import yerosti_lokal as lokal

GOR_M = 0.05        # TQ-02: gorizontal og'ish chegarasi — RSS(T-103 σH 2 sm, georef RMS 3 sm) × 1,4
VER_M = 0.08        # vertikal — RSS(σV 5 sm, 3 sm) × 1,4
YAQIN_M = 1.0       # TQ-03: tasdiq liniyaga shu masofada bo'lsa unga tegishli
UCH_M = 1.0         # TQ-04: boshi / oxiri / burilish tasdig'i shu radius ichida bo'lsin
ORALIQ_M = geo.ORALIQ_M   # G.1.1: qo'shni tasdiqlar orasi ≤ 50 m
SIGMA_H_SM, SIGMA_V_SM, TUZATMA_S = 2.0, 5.0, 10.0   # T-103 — tasdiq RASMIY darajada bo'lsin
MIN_S, MIN_EPOXA = 5.0, 5                            # vexa quvur ustida: qisqa o'rtachalash (Emlid odatiy 5 s)
JOYLAR = {"usti": "quvur usti", "oq": "quvur o'qi (ochiq uchi)"}
HOLAT_NOMI = {"tasdiqlangan": "tasdiqlangan", "qisman": "qisman tasdiqlangan", "farq": "FARQ",
              "yoq": "tasdiq yo'q", "rtk": "RTK o'lchov (tasdiq shart emas)"}
KERAKLI_TURLAR = ("bosh", "oxir", "burilish", "tutashuv")


def chegaralar():
    return {"gor_m": GOR_M, "ver_m": VER_M, "yaqin_m": YAQIN_M, "uch_m": UCH_M, "oraliq_m": ORALIQ_M,
            "sigma_h_sm": SIGMA_H_SM, "sigma_v_sm": SIGMA_V_SM, "tuzatma_s": TUZATMA_S, "min_s": MIN_S,
            "min_epoxa": MIN_EPOXA, "joylar": JOYLAR}


def enu(lat0, lon0):
    """Mahalliy tekis koordinata (sharq e, shimol n, metr) — og'ish bir necha sm, masofa bir necha km: yetarli (< 1 sm)."""
    fi = math.radians(lat0)
    m_lat = 111132.954 - 559.822 * math.cos(2 * fi) + 1.175 * math.cos(4 * fi)
    m_lon = 111412.84 * math.cos(fi) - 93.5 * math.cos(3 * fi)

    def k(lat, lon):
        return (lon - lon0) * m_lon, (lat - lat0) * m_lat
    return k


def _planar(l, k):
    nq = []
    for p in l["nuqtalar"]:
        e, n = k(p["lat"], p["lon"])
        nq.append({"e": e, "n": n, "h": p.get("balandlik"), "chuqurlik": p.get("chuqurlik_m"),
                   "sifat": p.get("sifat") or "PAST", "manba": p.get("manba") or "rtk", "sigma_h_sm": p.get("sigma_h_sm"),
                   "rtk_holat": p.get("rtk_holat"), "izoh": ""})
    return {"id": l["id"], "turi": l.get("turi"), "diametr_mm": int(l.get("diametr_mm") or 0),
            "material": l.get("material") or "", "nuqtalar": nq}


def proyeksiya(P, s, e, n):
    """Nuqtaning polilinya ustidagi eng yaqin joyi → (stansiya, gorizontal masofa, o'q balandligi yoki None)."""
    eng = None
    for i in range(len(P) - 1):
        a, b = P[i], P[i + 1]
        dx, dy = b["e"] - a["e"], b["n"] - a["n"]
        L2 = dx * dx + dy * dy
        t = 0.0 if L2 <= 0 else max(0.0, min(1.0, ((e - a["e"]) * dx + (n - a["n"]) * dy) / L2))
        d = math.hypot(e - (a["e"] + dx * t), n - (a["n"] + dy * t))
        if eng is None or d < eng[1]:
            h = None if a.get("h") is None or b.get("h") is None else a["h"] + (b["h"] - a["h"]) * t
            eng = (s[i] + math.sqrt(L2) * t, d, h)
    return eng


def baholash(lp, t):
    """TQ-02: tasdiq {e, n, h, joy} ning planar liniya o'qidan og'ishi. joy: usti — vexa uchi quvur ustida (o'q + D/2),
    oq — ochiq uchida o'qda. Balandlik ma'lum bo'lmasa faqat gorizontal baholanadi (sababda yoziladi)."""
    P = lp["nuqtalar"]
    st, d, h = proyeksiya(P, geo.stansiyalar(P), t["e"], t["n"])
    kutilgan = None if h is None else (h + geo.radius(lp) if (t.get("joy") or "usti") == "usti" else h)
    dv = None if (kutilgan is None or t.get("h") is None) else t["h"] - kutilgan
    xato, izoh = [], []
    if d > GOR_M:
        xato.append(f"gorizontal {d * 100:.1f} sm > {GOR_M * 100:.0f} sm")
    if dv is not None and abs(dv) > VER_M:
        xato.append(f"vertikal {dv * 100:+.1f} sm, chegara ±{VER_M * 100:.0f} sm")
    if dv is None:
        izoh.append("balandlik solishtirilmadi (o'q yoki tasdiq balandligi yo'q)")
    return {"stansiya": st, "d_gor": d, "d_ver": dv, "otdi": not xato, "sabab": "; ".join(xato + izoh)}


def kerakli_nuqtalar(lp):
    """TQ-04: tasdiqlanishi shart bo'lgan joylar — G.1.1 xarakterli nuqtalar: boshi, oxiri, burilish, tutashuv."""
    return [(p["turi"], p["stansiya"]) for p in geo.xarakterli(lp) if p["turi"] in KERAKLI_TURLAR]


def liniya_holati(lp, baholar):
    """TQ-05: liniya tasdiq holati. `baholar` — shu liniyaga bog'langan tasdiqlar bahosi."""
    P = lp["nuqtalar"]
    skan = any(p["manba"] == "skan" or p["sifat"] == "SKAN" for p in P)
    farq = [b for b in baholar if not b["otdi"]]
    r = {"soni": len(baholar), "otgan": len(baholar) - len(farq), "skan": skan,
         "maks_gor": max((b["d_gor"] for b in baholar), default=None),
         "maks_ver": max((abs(b["d_ver"]) for b in baholar if b["d_ver"] is not None), default=None),
         "kerakli": [{"turi": t, "stansiya": s, "pk": geo.pikitaj(s)} for t, s in kerakli_nuqtalar(lp)]}
    if not baholar:
        r.update(holat="rtk" if not skan else "yoq", kamchiliklar=[] if not skan else ["tasdiq o'lchovi yo'q"])
        return r
    if farq:
        r.update(holat="farq", kamchiliklar=[f"{len(farq)} ta tasdiq chegaradan tashqarida: skan georeferensi yoki "
                                              "tasdiq joyi shubhali, qayta o'lchang"])
        return r
    st = sorted(b["stansiya"] for b in baholar)
    kam = []
    for turi, s in kerakli_nuqtalar(lp):
        if min(abs(x - s) for x in st) > UCH_M:
            kam.append(f"{geo.YORLIQ.get(turi, turi)} ({geo.pikitaj(s)}) {UCH_M:.0f} m ichida tasdiqlanmagan")
    for a, b in zip(st, st[1:]):
        if b - a > ORALIQ_M + 1e-9:
            kam.append(f"{geo.pikitaj(a)} – {geo.pikitaj(b)} oralig'i {b - a:.0f} m > {ORALIQ_M:.0f} m")
    r.update(holat="tasdiqlangan" if not kam else "qisman", kamchiliklar=kam)
    return r


def hisobla(liniyalar, tasdiqlar):
    """TQ-03/05: obyekt liniyalari (baza qatorlari: nuqtalar lat/lon/balandlik/sifat/manba) va tasdiqlari →
    {"tasdiqlar": [tasdiq + liniya_id, stansiya, pk, d_gor, d_ver, otdi, sabab], "liniyalar": {id: holat}, "chegaralar"}."""
    lin = [l for l in liniyalar if len(l.get("nuqtalar") or []) >= 2]
    natija = [dict(t) for t in tasdiqlar]
    if not lin:
        for r in natija:
            r.update(liniya_id=None, stansiya=None, pk=None, d_gor=None, d_ver=None, otdi=False, sabab="obyektda liniya yo'q")
        return {"tasdiqlar": natija, "liniyalar": {}, "chegaralar": chegaralar()}
    hamma = [p for l in lin for p in l["nuqtalar"]]
    k = enu(sum(p["lat"] for p in hamma) / len(hamma), sum(p["lon"] for p in hamma) / len(hamma))
    planar = {l["id"]: _planar(l, k) for l in lin}
    baholar = {lid: [] for lid in planar}
    for r in natija:
        e, n = k(r["lat"], r["lon"])
        tt = {"e": e, "n": n, "h": r.get("h"), "joy": r.get("joy") or "usti"}
        nomzod = None
        if r.get("liniya_id") in planar:
            nomzod = (r["liniya_id"], baholash(planar[r["liniya_id"]], tt))
        else:
            for lid, lp in planar.items():
                b = baholash(lp, tt)
                if b["d_gor"] <= YAQIN_M and (nomzod is None or b["d_gor"] < nomzod[1]["d_gor"]):
                    nomzod = (lid, b)
        if nomzod is None:
            eng = min(baholash(lp, tt)["d_gor"] for lp in planar.values())
            r.update(liniya_id=None, stansiya=None, pk=None, d_gor=eng, d_ver=None, otdi=False,
                     sabab=f"{YAQIN_M:.0f} m ichida liniya yo'q (eng yaqini {eng:.1f} m)")
            continue
        lid, b = nomzod
        r.update(liniya_id=lid, stansiya=b["stansiya"], pk=geo.pikitaj(b["stansiya"]), d_gor=b["d_gor"],
                 d_ver=b["d_ver"], otdi=b["otdi"], sabab=b["sabab"])
        baholar[lid].append(b)
    return {"tasdiqlar": natija, "liniyalar": {lid: liniya_holati(lp, baholar[lid]) for lid, lp in planar.items()},
            "chegaralar": chegaralar()}


def tasdiqlangan(holatlar, liniya_id):
    h = (holatlar or {}).get(liniya_id) or (holatlar or {}).get(str(liniya_id))
    return bool(h and h["holat"] in ("tasdiqlangan", "rtk"))


def csv_oqi(matn, joy="usti"):
    """TQ-06: Emlid Flow eksporti (Name, Latitude, Longitude, Ellipsoidal height, Solution status, Lateral/Elevation RMS,
    Averaging start/end, Samples, Description/Code) yoki oddiy shakl: nomi; lat; lon; h; σH_sm; σV_sm; joy.
    Tavsif yoki kodda «oq» / «axis» bo'lsa — vexa uchi o'qda (ochiq uch), aks holda `joy`."""
    qatorlar, ajr = lokal._csv_qatorlar(matn)
    if not qatorlar:
        return [], ["CSV bo'sh"]
    sarl = [s.lower() for s in qatorlar[0]]

    def ust(*nomlar):
        for nm in nomlar:
            for i, s in enumerate(sarl):
                if s == nm:
                    return i
        return None

    def joyi(matn_):
        m = (matn_ or "").lower()
        return "oq" if ("oq" in m.split() or "axis" in m or "o'q" in m or "markaz" in m) else joy

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
                boshi, oxiri = lokal._vaqt_emlid(ol(i_b)), lokal._vaqt_emlid(ol(i_o))
                dav = None
                if boshi and oxiri:
                    from datetime import datetime
                    dav = (datetime.fromisoformat(oxiri) - datetime.fromisoformat(boshi)).total_seconds()
                sh, sv = lokal._son_csv(ol(i_sh), ajr), lokal._son_csv(ol(i_sv), ajr)
                natija.append({"nomi": ol(i_n), "lat": lokal._son_csv(ol(i_la), ajr), "lon": lokal._son_csv(ol(i_lo), ajr),
                               "h": lokal._son_csv(ol(i_h), ajr), "rtk_holat": ol(i_st).upper() or "?",
                               "sigma_h_sm": None if sh is None else sh * 100, "sigma_v_sm": None if sv is None else sv * 100,
                               "epoxalar": int(lokal._son_csv(ol(i_s), ajr)) if lokal._son_csv(ol(i_s), ajr) is not None else None,
                               "davomiylik_s": dav, "vaqt": boshi, "antenna_m": lokal._son_csv(ol(i_a), ajr),
                               "joy": joyi(ol(i_d) + " " + ol(i_c))})
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
            natija.append({"nomi": q[0], "lat": lokal._son_csv(q[1], ajr), "lon": lokal._son_csv(q[2], ajr),
                           "h": lokal._son_csv(q[3], ajr),
                           "sigma_h_sm": lokal._son_csv(q[4], ajr) if len(q) > 4 else None,
                           "sigma_v_sm": lokal._son_csv(q[5], ajr) if len(q) > 5 else None,
                           "joy": joyi(q[6]) if len(q) > 6 else joy, "rtk_holat": "FIX", "vaqt": None})
        except ValueError:
            xatolar.append(f"{k}-qator: son o'qilmadi")
    return natija, xatolar
