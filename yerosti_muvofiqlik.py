"""T3: loyiha–ijro muvofiqligi — ijro liniyalarini loyiha DXF chiziqlariga moslash, og'ishni me'yor bilan solishtirish,
qurilmagan va loyihadan tashqari qismlarni topish, inspeksiyaga tayyor ro'yxat (PDF + JSON).

Qaror qoidasi o'lchov noaniqligi bilan (ISO 14253-1 yondashuvi, k = 2, ~95 %):
  |og'ish| + 2σ ≤ ruxsat  → me'yorda (isbotlangan);
  |og'ish| − 2σ > ruxsat  → me'yordan tashqari (isbotlangan);
  aks holda               → noaniq: o'lchov aniqligi me'yorni tasdiqlash yoki rad etish uchun yetarli emas.
Ruxsat qiymati faqat manbasi bilan; manbasi topilmagan tarmoq turida qiymat qo'yilmaydi (o'lchov beriladi, xulosa yo'q).
"""
import io
import math
from collections import Counter

from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

import yerosti_ijro as ijro
import yerosti_ijro_geo as geo
from yerosti_dalolatnoma import KAM_RANG, TOLIQ_RANG, X0, X1, Y1, _qr, _Varaq
from yerosti_ijro import F, FB, MATN2, matn, son, tsh

MANBA = "SNiP 3.05.04-85*, 3.6-band"
# 3.6: «Maksimal og'ishlar: bosimli quvurlar o'qi rejada ±100 mm, bosimsiz quvurlar lotogi belgisi ±5 mm, bosimli quvurlar
# usti belgisi ±30 mm — agar loyihada boshqa me'yor asoslanmagan bo'lsa».
MEYOR = {
    "bosimli": {"gorizontal": (0.100, f"{MANBA}: bosimli quvur o'qi rejada ±100 mm"),
                "vertikal": (0.030, f"{MANBA}: bosimli quvur usti belgisi ±30 mm")},
    "bosimsiz": {"gorizontal": None,
                 "vertikal": (0.005, f"{MANBA}: bosimsiz quvur lotogi belgisi ±5 mm")},
}
MEYOR_IZOH = ("O'zbekistonda KMK 3.05.04-97 shu me'yor asosida tuzilgan; KMK matni bilan bevosita solishtirilmagan. "
              "Gaz, issiqlik, elektr va aloqa tarmoqlari uchun manbali ruxsat qiymati kiritilmagan — o'lchov beriladi, xulosa yo'q.")
K = 2.0
SIGMA_ZAXIRA = {"gorizontal": 0.02, "vertikal": 0.05}     # σ yozilmagan nuqta: T-103 RASMIY chegarasi (ehtiyotkor)
NAMUNA_M = 1.0                                           # loyiha chizig'i bo'ylab qamrov namunasi
HOLAT_NOMI = {"meyorda": "me'yorda", "tashqari": "ME'YORDAN TASHQARI", "noaniq": "noaniq (aniqlik yetarli emas)",
              "meyor_yoq": "me'yor kiritilmagan", "loyiha_z_yoq": "loyihada belgi yo'q"}


def rejim(l):
    """Bosimli / bosimsiz: suv — bosimli; kanalizatsiya — ish parametrida bosim (MPa, bar) bo'lsa bosimli, aks holda bosimsiz."""
    par = (l.get("parametr") or "").lower()
    if l["turi"] == "suv":
        return "bosimli"
    if l["turi"] == "kanalizatsiya":
        return "bosimli" if any(s in par for s in ("mpa", "bar", "bosim")) else "bosimsiz"
    return None


def qaror(d, sigma, T):
    if T is None:
        return "meyor_yoq"
    if abs(d) + K * sigma <= T:
        return "meyorda"
    if abs(d) - K * sigma > T:
        return "tashqari"
    return "noaniq"


def _oraliqlar(qiymatlar, qadam):
    """Ketma-ket «belgilangan» stansiyalarni oraliqlarga birlashtiradi: [(bosh, oxir)]."""
    natija = []
    for s in sorted(qiymatlar):
        if natija and s - natija[-1][1] <= qadam * 1.5:
            natija[-1][1] = s
        else:
            natija.append([s, s])
    return [(a, b) for a, b in natija]


def _masofa_poliliniyagacha(x, y, nuqtalar):
    eng = math.inf
    for a, b in zip(nuqtalar, nuqtalar[1:]):
        dx, dy = b["e"] - a["e"], b["n"] - a["n"]
        l2 = dx * dx + dy * dy
        t = 0.0 if l2 <= 0 else max(0.0, min(1.0, ((x - a["e"]) * dx + (y - a["n"]) * dy) / l2))
        eng = min(eng, math.hypot(x - a["e"] - dx * t, y - a["n"] - dy * t))
    if len(nuqtalar) == 1:
        eng = math.hypot(x - nuqtalar[0]["e"], y - nuqtalar[0]["n"])
    return eng


def tahlil(m):
    """`m` — ijro.malumot_yig + tayyorla natijasi (hujjat koordinata tizimida). Loyiha yo'q bo'lsa ValueError."""
    loyiha = m.get("loyiha")
    if not loyiha or not loyiha.get("chiziqlar"):
        raise ValueError("loyiha DXF yuklanmagan: muvofiqlik tekshirilmaydi")
    joylar, liniyalar, tashqari_oraliq = [], [], []
    for l in m["liniyalar"]:
        r = rejim(l)
        me = MEYOR.get(r) or {}
        Tg, mg = me.get("gorizontal") or (None, None)
        Tv, mv = me.get("vertikal") or (None, None)
        sv = {n.get("id"): n.get("sigma_v_sm") for n in l.get("nuqtalar") or []}
        hg, hv = Counter(), Counter()
        dgs, dvs, tashqi = [], [], []
        for p in l["xn"]:
            if p.get("hisoblangan"):
                continue
            g = p.get("loyiha")
            if not g or not g.get("yaqin"):
                tashqi.append(p["stansiya"])
                continue
            sh = (p.get("sigma_h_sm") / 100) if p.get("sigma_h_sm") is not None else SIGMA_ZAXIRA["gorizontal"]
            s_v = (sv.get(p.get("id")) / 100) if sv.get(p.get("id")) is not None else SIGMA_ZAXIRA["vertikal"]
            dg, dv = g["gorizontal"], g.get("vertikal")
            q_g = qaror(dg, sh, Tg)
            q_v = qaror(dv, s_v, Tv) if dv is not None else "loyiha_z_yoq"
            hg[q_g] += 1
            hv[q_v] += 1
            dgs.append(abs(dg))
            if dv is not None:
                dvs.append(abs(dv))
            joylar.append({"liniya": l["id"], "stansiya": p["stansiya"], "gorizontal_m": dg, "sigma_h_m": sh, "holat_g": q_g,
                           "vertikal_m": dv, "sigma_v_m": s_v, "holat_v": q_v, "sifat": p.get("sifat"), "qatlam": g.get("qatlam")})
        for a, b in _oraliqlar(tashqi, 5.0):
            tashqari_oraliq.append({"liniya": l["id"], "bosh_m": a, "oxir_m": b})
        liniyalar.append({"id": l["id"], "turi": l["turi"], "diametr_mm": l["diametr_mm"], "material": l.get("material") or "",
                          "rejim": r, "ruxsat_g_m": Tg, "manba_g": mg, "ruxsat_v_m": Tv, "manba_v": mv,
                          "uzunlik_m": l["uzunlik"], "nuqtalar": sum(hg.values()) + len(tashqi), "loyihada": sum(hg.values()),
                          "holat_g": dict(hg), "holat_v": dict(hv), "maks_g_m": max(dgs) if dgs else None,
                          "maks_v_m": max(dvs) if dvs else None})
    # loyihada bor, ijroda yo'q: loyiha chizig'i bo'ylab har 1 m da eng yaqin ijro liniyasi 5 m dan uzoq
    qurilmagan, qamrov = [], []
    for c in loyiha["chiziqlar"]:
        P = c["nuqtalar"]
        uz, yoq, namunalar = 0.0, [], 0
        for a, b in zip(P, P[1:]):
            seg = math.hypot(b[0] - a[0], b[1] - a[1])
            n = max(1, int(seg / NAMUNA_M))
            for i in range(n + (1 if b is P[-1] else 0)):
                t = i / n
                x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                d = min((_masofa_poliliniyagacha(x, y, l["nuqtalar"]) for l in m["liniyalar"] if l.get("nuqtalar")), default=math.inf)
                namunalar += 1
                if d > geo.LOYIHA_YAQIN_M:
                    yoq.append(uz + seg * t)
            uz += seg
        for a, b in _oraliqlar(yoq, NAMUNA_M):
            qurilmagan.append({"qatlam": c["qatlam"], "bosh_m": a, "oxir_m": b, "uzunlik_m": min(uz, b - a + NAMUNA_M)})
        qamrov.append({"qatlam": c["qatlam"], "uzunlik_m": uz,
                       "qamrov_foiz": 100.0 * (1 - len(yoq) / namunalar) if namunalar else 0.0})
    jami = Counter()
    for j in joylar:
        for k in ("holat_g", "holat_v"):
            jami[f"{k}:{j[k]}"] += 1
    return {"loyiha": {"fayl_nomi": loyiha.get("fayl_nomi"), "sha256": loyiha.get("sha256"), "z_turi": loyiha.get("z_turi"),
                       "yaratilgan": loyiha.get("yaratilgan")},
            "qoida": f"|og'ish| + {K:g}σ ≤ ruxsat — me'yorda; |og'ish| − {K:g}σ > ruxsat — me'yordan tashqari; aks holda noaniq",
            "meyor_izoh": MEYOR_IZOH, "liniyalar": liniyalar, "joylar": joylar, "qurilmagan": qurilmagan,
            "loyihadan_tashqari": tashqari_oraliq, "qamrov": qamrov,
            "jami": {"tashqari": jami["holat_g:tashqari"] + jami["holat_v:tashqari"],
                     "noaniq": jami["holat_g:noaniq"] + jami["holat_v:noaniq"],
                     "meyorda": jami["holat_g:meyorda"] + jami["holat_v:meyorda"],
                     "meyor_yoq": jami["holat_g:meyor_yoq"] + jami["holat_v:meyor_yoq"],
                     "qurilmagan_m": round(sum(q["uzunlik_m"] for q in qurilmagan), 2),
                     "loyihadan_tashqari_oraliq": len(tashqari_oraliq)}}


# ---------- PDF ----------

def _sm(x):
    return "—" if x is None else son(x * 100, 1)


def pdf(m, t):
    """(PDF baytlari, varaqlar soni): inspeksiyaga tayyor ro'yxat. Ikki o'tish — «varaq k / N»."""
    ijro._shrift()
    N = None
    for _ in range(2):
        buf = io.BytesIO()
        c = canvas.Canvas(buf, pagesize=A4, pageCompression=1)
        c.setTitle(f"Loyiha–ijro muvofiqligi {m['raqam']}: {m['obyekt']['nomi']}")
        c.setAuthor("TRACE4D")
        c.setSubject("Loyiha va ijro s'yomkasi muvofiqligi (T3), me'yor va o'lchov noaniqligi bilan")
        v = _Varaq(c, m, N, pastki=f"{m['raqam']} · Loyiha–ijro muvofiqligi hisoboti · TRACE4D")
        _chiz(v, m, t)
        v._pastki()
        c.restoreState()
        c.showPage()
        c.save()
        N = v.k
    return buf.getvalue(), N


def _chiz(v, m, t):
    c, o, j = v.c, m["obyekt"], t["jami"]
    _qr(c, m["url"], X1 - 24, Y1 - 24, 24)
    matn(c, X1 - 12, Y1 - 27, "Haqiqiyligini QR orqali tekshiring", 1.9, tekis="c", rang=MATN2)
    matn(c, X0, Y1 - 3, "Inspeksiyaga tayyor ro'yxat", 2.4, rang=MATN2)
    matn(c, X0, Y1 - 9, m["raqam"], 4.2, FB)
    ok = not j["tashqari"] and not j["qurilmagan_m"]
    matn(c, X0, Y1 - 15, "ME'YORDAN TASHQARI OG'ISH TOPILMADI" if ok else
         f"ME'YORDAN TASHQARI: {j['tashqari']} joy · QURILMAGAN: {son(j['qurilmagan_m'], 1)} m", 2.6, FB,
         rang=TOLIQ_RANG if ok else KAM_RANG)
    v.y = Y1 - 34
    matn(c, (X0 + X1) / 2, v.y, "LOYIHA–IJRO MUVOFIQLIGI HISOBOTI", 4.6, FB, tekis="c")
    v.y -= 4
    lo = t["loyiha"]
    v.satrlar(f"Obyekt: {o['nomi']}" + (f", {o['manzil']}" if o.get("manzil") else ""), 2.9)
    v.satrlar(f"Loyiha fayli: {lo.get('fayl_nomi')} · SHA-256 {str(lo.get('sha256'))[:16]}… · yuklangan {tsh(lo.get('yaratilgan'))} · "
              f"loyiha belgisi: {geo.Z_TURLARI.get(lo.get('z_turi'), '—')}", 2.6, rang=MATN2)
    v.satrlar(f"Koordinata va balandlik tizimi: {m['tizim']['nomi']}; {m['tizim']['balandlik']}. Hisobot sanasi {m['sana']}.", 2.6, rang=MATN2)

    v.bolim("1. Qaror qoidasi va me'yor")
    v.satrlar(f"Har o'lchangan nuqtada eng yaqin loyiha chizig'igacha og'ish (5 m dan uzoq — loyihadan tashqari). {t['qoida']}. "
              "σ — nuqtaning o'lchov xatosi (RTK σH, σV); yozilmagan bo'lsa RASMIY chegarasi (2 / 5 sm) olinadi.", 2.6)
    v.jadval([("Rejim", 26, "l"), ("Rejada", 20, "c"), ("Belgi bo'yicha", 26, "c"), ("Manba", 108, "l")],
             [["bosimli", "±100 mm", "±30 mm (usti)", f"{MANBA}"], ["bosimsiz", "—", "±5 mm (lotok)", f"{MANBA}"]])
    v.satrlar(t["meyor_izoh"], 2.3, rang=MATN2)
    if any(l["rejim"] == "bosimsiz" for l in t["liniyalar"]):
        v.satrlar("Bosimsiz quvur lotogi ±5 mm: RTK balandlik aniqligi (σV 1–5 sm) bilan bunday me'yorni tasdiqlab bo'lmaydi — "
                  "katta og'ishlar isbotlanadi, qolgani «noaniq»; lotok belgisi geometrik nivelirlash bilan tekshiriladi.", 2.4, F, rang=KAM_RANG)

    v.bolim("2. Liniyalar bo'yicha xulosa")
    rows = []
    for l in t["liniyalar"]:
        hg, hv = l["holat_g"], l["holat_v"]
        rows.append([f"#{l['id']}", f"{ijro.tarmoq_nomi(l['turi'])} Ø{l['diametr_mm']}", l["rejim"] or "—", f"{l['loyihada']}/{l['nuqtalar']}",
                     f"{_sm(l['maks_g_m'])}", " / ".join(str(hg.get(k, 0)) for k in ("meyorda", "tashqari", "noaniq")) if l["ruxsat_g_m"] else "me'yor yo'q",
                     f"{_sm(l['maks_v_m'])}", " / ".join(str(hv.get(k, 0)) for k in ("meyorda", "tashqari", "noaniq")) if l["ruxsat_v_m"] else "me'yor yo'q"])
    v.jadval([("Liniya", 14, "c"), ("Tarmoq", 34, "l"), ("Rejim", 18, "c"), ("Loyihada/jami", 22, "c"), ("Reja maks, sm", 22, "r"),
              ("Reja M/T/N", 24, "c"), ("Belgi maks, sm", 22, "r"), ("Belgi M/T/N", 24, "c")], rows)
    v.satrlar("M — me'yorda, T — me'yordan tashqari, N — noaniq (o'lchov aniqligi yetarli emas); nuqtalar soni.", 2.3, rang=MATN2)

    v.bolim("3. Me'yordan tashqari va noaniq joylar")
    muhim = [x for x in t["joylar"] if "tashqari" in (x["holat_g"], x["holat_v"]) or "noaniq" in (x["holat_g"], x["holat_v"])]
    muhim.sort(key=lambda x: (0 if "tashqari" in (x["holat_g"], x["holat_v"]) else 1, x["liniya"], x["stansiya"]))
    if muhim:
        v.jadval([("Liniya", 14, "c"), ("Pikitaj", 24, "c"), ("Rejada, sm", 20, "r"), ("σH, sm", 14, "r"), ("Holat (reja)", 34, "l"),
                  ("Belgi, sm", 18, "r"), ("σV, sm", 14, "r"), ("Holat (belgi)", 42, "l")],
                 [[f"#{x['liniya']}", ijro.stansiya_matn(x["stansiya"]), _sm(x["gorizontal_m"]), _sm(x["sigma_h_m"]),
                   HOLAT_NOMI[x["holat_g"]], _sm(x["vertikal_m"]), _sm(x["sigma_v_m"]), HOLAT_NOMI[x["holat_v"]]] for x in muhim[:120]])
        if len(muhim) > 120:
            v.satrlar(f"… yana {len(muhim) - 120} joy JSON natijada.", 2.4, rang=MATN2)
    else:
        v.satrlar("Yo'q: barcha o'lchangan nuqtalar me'yorda yoki me'yor kiritilmagan.", 2.7)

    v.bolim("4. Loyihada bor, ijroda yo'q (qurilmagan yoki o'lchanmagan)")
    if t["qurilmagan"]:
        v.jadval([("Loyiha qatlami", 60, "l"), ("Boshi, m", 30, "r"), ("Oxiri, m", 30, "r"), ("Uzunlik, m", 30, "r")],
                 [[q["qatlam"], son(q["bosh_m"], 1), son(q["oxir_m"], 1), son(q["uzunlik_m"], 1)] for q in t["qurilmagan"]])
    else:
        v.satrlar("Yo'q: loyiha chiziqlarining har 1 m ida 5 m ichida ijro liniyasi bor.", 2.7)
    for q in t["qamrov"]:
        v.satrlar(f"«{q['qatlam']}»: loyiha uzunligi {son(q['uzunlik_m'], 1)} m, ijro bilan qamrov {son(q['qamrov_foiz'], 0)} %.", 2.5, rang=MATN2)

    v.bolim("5. Ijroda bor, loyihada yo'q (loyihadan tashqari)")
    if t["loyihadan_tashqari"]:
        v.jadval([("Liniya", 20, "c"), ("Pikitaj boshi", 40, "c"), ("Pikitaj oxiri", 40, "c")],
                 [[f"#{x['liniya']}", ijro.stansiya_matn(x["bosh_m"]), ijro.stansiya_matn(x["oxir_m"])] for x in t["loyihadan_tashqari"]])
    else:
        v.satrlar("Yo'q: har o'lchangan nuqtadan 5 m ichida loyiha chizig'i bor.", 2.7)
    v.oraliq(4)
    v.satrlar("Hisobot TRACE4D tizimida ijro s'yomkasi va loyiha DXF dan avtomatik tuzilgan. Xulosa me'yor bandi va o'lchov xatosi bilan "
              "berilgan; yakuniy qaror inspeksiya va texnik nazoratniki.", 2.3, rang=MATN2)


def tekshirish_xulosasi(m, t, N):
    """/t/ sahifasi uchun (koordinatasiz)."""
    o = m["obyekt"]
    return {"tur": "muvofiqlik", "obyekt": o["nomi"], "pudratchi": o.get("pudratchi") or "", "sana": m["sana"], "varaqlar": N,
            "loyiha": t["loyiha"].get("fayl_nomi"), "liniyalar": len(t["liniyalar"]), **t["jami"]}
