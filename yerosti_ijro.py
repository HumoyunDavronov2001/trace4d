"""YEROSTI — ijro hujjati PDF (TALABLAR 14: IH-01…IH-08; 15: LK-06…LK-08). A3 albom, reportlab.

Varaqlar: reja (topoasos ustida); koordinatalar katalogi va kesishuvlar; geodezik asos va lokalizatsiya; har liniyaga
bo'ylama profil; sifat va kelib chiqish. Har varaqda ГОСТ 2.301 ramkasi, shtamp 185×55 mm, imzo joylari,
"varaq k / N", tekshirish QR kodi va "topshirishga yaroqlilik" belgisi.
Tizim: obyektda yaroqli lokalizatsiya bo'lsa — mahalliy X (shimol), Y (sharq) va Boltiq H [G2 5.4, 6.10]; bo'lmasa
WGS84 / UTM va ellipsoid balandligi, hujjat esa "TOPSHIRISHGA YAROQSIZ" deb belgilanadi.
Kirish: `malumot_yig` (bazadan) yoki xuddi shu tuzilmadagi lug'at; geometriya `yerosti_ijro_geo`, o'tish `yerosti_lokal`.
"""
import io
import math
import os
from datetime import datetime, timedelta, timezone

import qrcode
from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import A3, landscape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

import yerosti_chizma as chizma
import yerosti_ijro_geo as geo
import yerosti_lokal as lokal
import yerosti_tasdiq as tasdiq_mod

MM = 72 / 25.4
RX0, RY0, RX1, RY1 = 20.0, 5.0, 415.0, 292.0          # ГОСТ 2.301: chapda 20 mm tikish uchun, qolganlari 5 mm
SH_W, SH_H = 185.0, 55.0                              # ГОСТ 21.101 asosiy yozuv o'lchami
SH_X, SH_Y = RX1 - SH_W, RY0
KX0, KY0, KX1, KY1 = RX0 + 2, RY0 + SH_H + 2, RX1 - 2, RY1 - 2   # ish maydoni (shtamp ustida)
QR_X, QR_Y, QR_O = SH_X - 27.0, RY0 + 27.0, 24.0
PASTKI_X1 = QR_X - 3                                  # pastki chap maydon (shartli belgilar, izohlar) o'ng cheti
SHRIFT_PAPKA = os.environ.get("YEROSTI_SHRIFT_PAPKA", "/usr/share/fonts/truetype/dejavu")
F, FB = "YerostiSans", "YerostiSansB"
MASSHTABLAR = (100, 200, 500, 1000, 2000, 5000, 10000, 25000)
PROFIL_GOR = (100, 200, 500, 1000, 2000)
PROFIL_VER = (10, 20, 50, 100, 200, 500, 1000)
QOLDA_QAZISH_M = 2.0                                  # TALABLAR 10 (CIS qoidasi), AR-06 bilan bir xil
REESTR_ZAXIRA_M = 30.0                                # rejada obyekt atrofidagi reestr tarmoqlari

# web/tokenlar.css bilan bir xil chiziq rangi; gaz va optika matni bosmada o'qilishi uchun to'qroq
TARMOQ = {"suv": ("#2563EB", "#1D4ED8"), "kanalizatsiya": ("#92400E", "#92400E"), "gaz": ("#CA8A04", "#854D0E"),
          "elektr": ("#DC2626", "#B91C1C"), "optika": ("#EA580C", "#C2410C"), "issiqlik": ("#7C3AED", "#6D28D9")}
SIFAT_RANG = {"RASMIY": "#0F7A3D", "SKAN": "#9A5500", "PAST": "#C0262D"}
MATN, MATN2, CHIZIQ, FON2 = "#0B1620", "#4A5868", "#AAB4C0", "#EEF2F6"
LOYIHA_RANG, REESTR_RANG, TOPO_RANG = "#C026D3", "#7B8794", "#9AA5B1"
YAROQLI_RANG, YAROQSIZ_RANG = "#0F7A3D", "#C0262D"
MANBA_NOMI = {"rtk": "RTK", "skan": "skan", "hisoblangan": "hisoblangan"}


def _tasdiqlangan(l):
    return bool((l.get("tasdiq") or {}).get("holat") in ("tasdiqlangan", "rtk"))


def _manba_matn(p, l):
    """Katalogda: tasdiqlangan liniyaning skan nuqtasi — «skan, RTK tasdiq»."""
    m = p.get("manba")
    if m == "skan" and _tasdiqlangan(l):
        return "skan, RTK tasdiq"
    return MANBA_NOMI.get(m, m or "—")


def _rasmiy_hisoblanadi(p, l):
    """Hujjat uchun nuqta rasmiymi: RASMIY yoki tasdiqlangan liniyadagi SKAN (T-031)."""
    return p.get("sifat") == "RASMIY" or (p.get("sifat") == "SKAN" and _tasdiqlangan(l))
SIFAT_QOIDASI = ("RASMIY — RTK FIX, σH ≤ 2 sm, σV ≤ 5 sm, tuzatma yoshi ≤ 10 s. SKAN — LiDAR skan va RTK "
                 "georeferensdan hisoblangan: quvur ustidagi RTK tasdig'i (T-031) chegarada bo'lmaguncha rasmiy o'lchov emas. "
                 "PAST — chegaradan tashqari, faqat ma'lumot uchun.")


# ---------- yordamchilar ----------

def _shrift():
    if F not in pdfmetrics.getRegisteredFontNames():
        pdfmetrics.registerFont(TTFont(F, os.path.join(SHRIFT_PAPKA, "DejaVuSans.ttf")))
        pdfmetrics.registerFont(TTFont(FB, os.path.join(SHRIFT_PAPKA, "DejaVuSans-Bold.ttf")))


def sana_uz(iso):
    """YYYY-MM-DD → DD.MM.YYYY; boshqa shakl o'zgarmaydi."""
    s = str(iso or "").strip()
    return f"{s[8:10]}.{s[5:7]}.{s[:4]}" if len(s) == 10 and s[4] == "-" and s[7] == "-" else s


def order_matn(o):
    """ShN-01: qazish orderi «raqam, DD.MM.YYYY» (ShNK 3.01.03-24, 420-band); ikkalasi yo'q bo'lsa bo'sh."""
    r = str((o or {}).get("order_raqami") or "").strip()
    s = sana_uz((o or {}).get("order_sana"))
    if not r and not s:
        return ""
    return (r or "raqam yo'q") + ", " + (s or "sana yo'q")


def son(x, n=2, yoq="—"):
    if x is None:
        return yoq
    t = f"{x:.{n}f}"
    if t.startswith("-") and not t.strip("-0."):
        t = t[1:]                       # "-0,0" emas — yaxlitlanganda nol
    return t.replace(".", ",")


def tsh(iso, soat=True):
    """Server vaqti (UTC, ISO) → Toshkent vaqti "03.10.2026 02:21" (hujjatda hamma vaqt bitta mintaqada)."""
    if not iso:
        return "—"
    try:
        d = datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
    except ValueError:
        return str(iso)
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.astimezone(timezone(timedelta(hours=5))).strftime("%d.%m.%Y %H:%M" if soat else "%d.%m.%Y")


def son_q(x):
    """Ortiqcha nolsiz: 5 → "5", 2,5 → "2,5", 1,25 → "1,25"."""
    return f"{x:.2f}".rstrip("0").rstrip(".").replace(".", ",")


def stansiya_matn(s):
    return geo.pikitaj(s)[2:]          # "0+12,50" — profil to'rida joy tejash uchun "PK" siz


def tarmoq_nomi(turi):
    return (turi or "").upper()


def liniya_nomi(l):
    return f"{tarmoq_nomi(l['turi'])} Ø{l['diametr_mm']}" + (f" {l['material']}" if l.get("material") else "")


def _en(s, o, sh=F):
    return pdfmetrics.stringWidth(s, sh, o)


def _sig(s, kenglik, o, sh=F, eng_kichik=1.5):
    """Matnni kenglikka sig'diradi: avval shriftni kichraytiradi, keyin qisqartiradi."""
    while o > eng_kichik and _en(s, o, sh) > kenglik:
        o = round(o - 0.1, 2)
    if _en(s, o, sh) > kenglik:
        while s and _en(s + "…", o, sh) > kenglik:
            s = s[:-1]
        s += "…"
    return s, o


def _qatorlar(s, kenglik, o, sh=F):
    natija = []
    for xat in str(s).split("\n"):
        joriy = ""
        for soz in xat.split(" "):
            sinov = (joriy + " " + soz).strip()
            if _en(sinov, o, sh) <= kenglik or not joriy:
                joriy = sinov
            else:
                natija.append(joriy)
                joriy = soz
        natija.append(joriy)
    return natija


def matn(c, x, y, s, o=2.5, sh=F, tekis="l", rang=MATN, burchak=0.0, kenglik=None, halo=False):
    """Matn (mm birlikda). halo — chiziqlar ustida o'qilishi uchun oq hoshiya (kartografik usul)."""
    s = str(s)
    if kenglik:
        s, o = _sig(s, kenglik, o, sh)
    if burchak:
        c.saveState()
        c.translate(x, y)
        c.rotate(burchak)
        x = y = 0
    w = _en(s, o, sh)
    x0 = x - w / 2 if tekis == "c" else (x - w if tekis == "r" else x)
    if halo:
        # Tr (chizish rejimi) PDF grafik holatining qismi — saveState bilan o'raladi, aks holda keyingi matnlar ham
        # faqat oq kontur bo'lib chiziladi
        c.saveState()
        t = c.beginText(x0, y)
        t.setFont(sh, o)
        t.setTextRenderMode(1)
        c.setStrokeColor(white)
        c.setStrokeAlpha(1)
        c.setLineWidth(o * 0.28)
        c.setLineJoin(1)
        c.setDash([], 0)
        t.textOut(s)
        c.drawText(t)
        c.restoreState()
    c.setFont(sh, o)
    c.setFillColor(HexColor(rang))
    c.drawString(x0, y, s, mode=0)
    if burchak:
        c.restoreState()


def _qalam(c, rang=MATN, en=0.25, punktir=None, alfa=1.0):
    c.setStrokeColor(HexColor(rang))
    c.setLineWidth(en)
    c.setDash(punktir or [], 0)
    c.setStrokeAlpha(alfa)


def _polilinya(c, xy):
    if len(xy) < 2:
        return
    p = c.beginPath()
    p.moveTo(*xy[0])
    for q in xy[1:]:
        p.lineTo(*q)
    c.drawPath(p, stroke=1, fill=0)


def _toq(rang, k):
    """Rangni oqga aralashtirish (fon uchun)."""
    h = HexColor(rang)
    return HexColor("#%02X%02X%02X" % tuple(int(255 - (255 - v * 255) * k) for v in (h.red, h.green, h.blue)))


def _chiroyli_qadam(qiymat, qadamlar=(1, 2, 2.5, 5)):
    """qiymat dan kichik bo'lmagan eng yaqin 1-2-2,5-5 qadami."""
    if qiymat <= 0:
        return 1.0
    d = 10 ** math.floor(math.log10(qiymat))
    for q in qadamlar + (10,):
        if q * d >= qiymat - 1e-12:
            return q * d
    return 10 * d


# ---------- ma'lumot tayyorlash ----------

def utm_liniyalar(liniyalar, zona=None):
    """Baza liniyalari (lat/lon) → UTM, nuqtaning hamma kerakli ustunlari bilan (katalog uchun)."""
    return planar_liniyalar(liniyalar, None, zona)


def planar_liniyalar(liniyalar, lok=None, zona=None):
    """Baza liniyalari → hujjat tekisligi: lok bo'lsa mahalliy (e = Y sharq, n = X shimol, h = Boltiq o'q belgisi),
    aks holda UTM (h — ellipsoid). Nuqtaning hamma kerakli ustunlari bilan (katalog uchun)."""
    natija = []
    for l in liniyalar:
        if len(l["nuqtalar"]) < 2:
            continue
        nq = []
        for n in l["nuqtalar"]:
            if lok:
                x, y, h = lok.oldinga(n["lat"], n["lon"], n.get("balandlik"))
                e, nn = y, x
            else:
                e, nn, zona = chizma.utm(n["lat"], n["lon"], zona)
                h = n.get("balandlik")
            nq.append({"id": n.get("id"), "e": e, "n": nn, "h": h, "chuqurlik": n.get("chuqurlik_m"),
                       "sifat": n.get("sifat") or "PAST", "manba": n.get("manba") or "rtk",
                       "sigma_h_sm": n.get("sigma_h_sm"), "rtk_holat": n.get("rtk_holat"), "izoh": n.get("izoh") or ""})
        natija.append({"id": l["id"], "turi": l["turi"], "diametr_mm": int(l.get("diametr_mm") or 0),
                       "material": l.get("material") or "", "sifat": l.get("sifat") or "PAST",
                       "obyekt_nomi": l.get("obyekt_nomi") or "", "izoh": l.get("izoh") or "",
                       "versiya": l.get("versiya"), "nuqtalar": nq,
                       # KU-02 (MUDDI): egasi, ishlash holati, o'rnatilgan yil, ish parametri
                       "egasi": l.get("egasi") or l.get("obyekt_egasi") or "", "ishlash_holati": l.get("ishlash_holati") or "",
                       "ornatilgan_yil": l.get("ornatilgan_yil"), "parametr": l.get("parametr") or ""})
    return natija, zona


def tashkent_sana():
    return datetime.now(timezone(timedelta(hours=5))).strftime("%d.%m.%Y")


def tizim_tanla(lokalizatsiya, zona):
    """Hujjat tizimi. Mahalliy — faqat gorizontal VA vertikal modeli bor lokalizatsiya bilan (LK-06)."""
    p = (lokalizatsiya or {}).get("natija", {}).get("parametrlar") or {}
    if p.get("gor") and p.get("v"):
        return {"tur": "mahalliy", "nomi": lokalizatsiya["tizim_nomi"], "balandlik": "Boltiq 1977 (normal balandlik)",
                "lok": lokal.Lokalizatsiya(p), "zona": zona}
    return {"tur": "utm", "nomi": f"WGS84 / UTM {zona}N", "balandlik": "WGS84 ellipsoid (Boltiq emas)", "lok": None,
            "zona": zona}


def loyiha_tizimga(loyiha, tizim):
    """Loyiha chiziqlarini hujjat tizimiga o'tkazadi. `z_mos` — loyiha belgisi o'lchangan belgilar bilan bir tizimda.
    Qaytaradi (loyiha yoki None, izoh)."""
    if not loyiha:
        return None, None
    kor, lok = loyiha.get("koordinata") or "utm", tizim.get("lok")
    if kor == "utm" and tizim["tur"] == "utm":
        return {**loyiha, "z_mos": loyiha.get("z_tizimi") == "ellipsoid"}, None
    if kor == "mahalliy" and tizim["tur"] == "mahalliy":
        return {**loyiha, "z_mos": loyiha.get("z_tizimi") == "boltiq"}, None
    if kor == "utm" and lok:
        ell = loyiha.get("z_tizimi") == "ellipsoid"
        chiziqlar = []
        for ch in loyiha["chiziqlar"]:
            nq = []
            for e, n, z in ch["nuqtalar"]:
                lat, lon = lokal.utm_teskari(e, n, tizim["zona"])
                x, y, H = lok.oldinga(lat, lon, z if ell else None)
                nq.append([y, x, H if ell else z])
            chiziqlar.append({**ch, "nuqtalar": nq})
        return {**loyiha, "chiziqlar": chiziqlar, "z_tizimi": "boltiq", "z_mos": True}, None
    return None, "Loyiha DXF mahalliy tizimda, obyektda lokalizatsiya yo'q: hujjatga qo'yilmadi."


def malumot_yig(obyekt_id, raqam, url, yaratuvchi, sana=None):
    """Bazadan hujjat uchun hamma narsa. Reestr — boshqa obyektlarning shu hudud bilan kesishadigan liniyalari."""
    import yerosti_baza as baza
    o = baza.obyekt_top(obyekt_id)
    if not o:
        raise ValueError("obyekt topilmadi")
    qator = baza.liniyalar_toliq(obyekt_id=obyekt_id)
    _, zona = utm_liniyalar(qator)
    lq = baza.lokalizatsiya_top(obyekt_id)
    tizim = tizim_tanla(lq, zona or 42)
    lin, _ = planar_liniyalar(qator, tizim["lok"], zona)
    if not lin:
        raise ValueError("obyektda chiziladigan liniya yo'q (kamida 2 nuqtali)")
    lat = [n["lat"] for l in qator for n in l["nuqtalar"]]
    lon = [n["lon"] for l in qator for n in l["nuqtalar"]]
    # reja chegarasidagi qo'shni tarmoqlar ham ko'rinsin: quti har tomonga REESTR_ZAXIRA_M
    dlat = REESTR_ZAXIRA_M / 110_540.0
    dlon = REESTR_ZAXIRA_M / (111_320.0 * max(math.cos(math.radians(sum(lat) / len(lat))), 1e-6))
    reestr, _ = planar_liniyalar(baza.reestr_qutida(min(lat) - dlat, max(lat) + dlat, min(lon) - dlon, max(lon) + dlon,
                                                    obyekt_id), tizim["lok"], zona)
    loyiha, loyiha_izoh = loyiha_tizimga(baza.loyiha_top(obyekt_id), tizim)
    # LK-05: ish kunlari — nuqta o'lchov vaqti, bo'lmasa liniya yaratilgan vaqt (Toshkent sanasi)
    kunlar = {lokal.toshkent_sanasi(n.get("vaqt") or l.get("yaratilgan")) for l in qator for n in l["nuqtalar"]}
    punktlar, olchovlar = baza.nazorat_punktlar(obyekt_id), baza.nazorat_olchovlar(obyekt_id)
    asos = {"punktlar": punktlar, "olchovlar": olchovlar, "lok": lq, "tekshiruvlar": [], "kunlar": []}
    if tizim["lok"]:
        asos["tekshiruvlar"] = lokal.tekshiruvlar(tizim["lok"], punktlar, olchovlar)
        ishlatilgan = set(lq.get("olchovlar") or [])
        asos["kunlar"] = lokal.kunlik_nazorat(kunlar - {None}, asos["tekshiruvlar"],
                                              [o2 for o2 in olchovlar if o2["id"] in ishlatilgan],
                                              lq["natija"].get("yaroqli"))
    # TQ (T-031): quvur tasdiqlari — liniya holatlari va hujjat tekisligidagi joylari (reja va jadval uchun)
    tq = baza.tasdiq_holati(obyekt_id, qator)
    for t in tq["tasdiqlar"]:
        if tizim["lok"]:
            x, y, _ = tizim["lok"].oldinga(t["lat"], t["lon"], t.get("h"))
            t["e"], t["n"] = y, x
        else:
            t["e"], t["n"], _ = chizma.utm(t["lat"], t["lon"], zona)
    return {"raqam": raqam, "sana": sana or tashkent_sana(), "url": url, "obyekt": o, "zona": zona, "tizim": tizim,
            "liniyalar": lin, "reestr": reestr, "loyiha": loyiha, "loyiha_izoh": loyiha_izoh, "asos": asos, "tasdiq": tq,
            "topo": baza.topo_top(obyekt_id) if tizim["tur"] == "mahalliy" else None,
            "muhrlar": baza.muhrlar(obyekt_id), "tahlillar": baza.tahlillar(obyekt_id), "yaratuvchi": yaratuvchi}


def yaroqlilik(m):
    """LK-04…LK-06: hujjat rasmiy topshirishga yaroqlimi — sabablari bilan (har varaqda ko'rinadi)."""
    sabab = []
    t = m.get("tizim") or {"tur": "utm"}
    asos = m.get("asos") or {}
    if t["tur"] != "mahalliy":
        sabab.append("mahalliy koordinata tizimi va Boltiq balandligi yo'q: nazorat punktlari bo'yicha lokalizatsiya "
                     "qilinmagan [G2 5.4, 6.10]")
    else:
        n = asos["lok"]["natija"]
        sabab += [f"lokalizatsiya: {x}" for x in n.get("xatolar", [])]
        qobiq = [tuple(q) for q in n.get("qobiq") or []]
        uzoq = [lokal.qamrovdan_tashqari(qobiq, (p["e"], p["n"])) for l in m["liniyalar"] for p in l["nuqtalar"]]
        tashqari = [d for d in uzoq if d > lokal.EKSTRAPOLYATSIYA_M]
        if tashqari:
            sabab.append(f"{len(tashqari)} ta nuqta nazorat punktlari qamrovidan tashqarida (eng uzog'i "
                         f"{son(max(tashqari), 0)} m): ekstrapolyatsiya")
        yomon = [x for x in asos.get("tekshiruvlar", []) if not x["otdi"]]
        if yomon:
            sabab.append("tekshiruv o'lchovi o'tmadi: " + ", ".join(
                f"{x['nomi']} ({son((x['gor'] or 0) * 100, 1)} / {son(abs(x['ver'] or 0) * 100, 1)} sm)" for x in yomon))
        tekshirilmagan = [k["kun"] for k in asos.get("kunlar", []) if not k["tekshirilgan"]]
        if tekshirilmagan:
            sabab.append("tekshiruv o'lchovisiz ish kunlari: " + ", ".join(
                f"{k[8:10]}.{k[5:7]}.{k[:4]}" for k in tekshirilmagan))
    o = m.get("obyekt") or {}
    yoq = [nom for nom, k in (("raqami", "order_raqami"), ("sanasi", "order_sana")) if not str(o.get(k) or "").strip()]
    if yoq:
        sabab.append("qazish orderining " + " va ".join(yoq) + " ko'rsatilmagan [ShNK 3.01.03-24, 420-band]")
    past = sum(1 for l in m["liniyalar"] for p in l["nuqtalar"] if p["sifat"] == "PAST")
    if past:
        sabab.append(f"{past} ta o'lchangan nuqta PAST — RASMIY emas (T-103): rasmiy hujjatga chiqmaydi")
    tq = (m.get("tasdiq") or {}).get("liniyalar") or {}
    for l in m["liniyalar"]:
        skan = sum(1 for p in l["nuqtalar"] if p["sifat"] == "SKAN")
        if skan and not tasdiq_mod.tasdiqlangan(tq, l["id"]):
            h = tq.get(l["id"]) or tq.get(str(l["id"])) or {}
            sabab.append(f"liniya #{l['id']}: {skan} ta SKAN nuqta RASMIY emas — quvur ustidagi RTK tasdig'i yetarli emas "
                         f"(T-031: {tasdiq_mod.HOLAT_NOMI.get(h.get('holat'), 'tasdiq yo\'q')}"
                         + ("; " + "; ".join(h.get("kamchiliklar") or []) if h.get("kamchiliklar") else "") + ")")
    return {"yaroqli": not sabab, "sabablar": sabab}


def tayyorla(m):
    """Xarakterli nuqtalar (global raqam), kesishuvlar (umumiy K raqam), loyihadan og'ish va liniya yig'indilari."""
    m.setdefault("tizim", tizim_tanla(None, m.get("zona") or 42))
    if m.get("loyiha") and "z_mos" not in m["loyiha"]:
        m["loyiha"]["z_mos"] = m["loyiha"].get("z_tizimi") == ("boltiq" if m["tizim"]["tur"] == "mahalliy" else "ellipsoid")
    lin = m["liniyalar"]
    tq_l = (m.get("tasdiq") or {}).get("liniyalar") or {}
    for l in lin:
        l["tasdiq"] = tq_l.get(l["id"]) or tq_l.get(str(l["id"]))
    uchlar = [(l["nuqtalar"][k]["e"], l["nuqtalar"][k]["n"], l["diametr_mm"], l["material"], l["id"])
              for l in lin for k in (0, -1)]
    loyiha = m.get("loyiha")
    raqam = 0
    for l in lin:
        l["xn"] = geo.xarakterli(l, [(e, n, d, mat) for (e, n, d, mat, lid) in uchlar if lid != l["id"]])
        for p in l["xn"]:
            raqam += 1
            p["raqam"] = raqam
        l["uzunlik"] = geo.stansiyalar(l["nuqtalar"])[-1]
        boshqalar = [dict(o, obyekt_nomi=f"shu obyekt, liniya #{o['id']}") for o in lin if o["id"] != l["id"]]
        l["kesishuv"] = geo.kesishuvlar(l, boshqalar + list(m.get("reestr") or []))
        og = geo.loyihadan_ogish(l["xn"], loyiha["chiziqlar"], geo.radius(l), loyiha.get("z_turi", "oq")) if loyiha \
            else [None] * len(l["xn"])
        for p, g in zip(l["xn"], og):
            p["loyiha"] = g
    topilgan = []      # bir obyektdagi ikki liniya kesishuvi ikkalasidan ham topiladi — bitta K raqam
    for l in lin:
        for k in l["kesishuv"]:
            eski = next((t for t in topilgan if math.hypot(t["e"] - k["e"], t["n"] - k["n"]) < 0.02), None)
            k["takror"] = eski is not None
            k["k"] = eski["k"] if eski else len(topilgan) + 1
            k["liniya_id"] = l["id"]
            if not eski:
                topilgan.append(k)
    for l in lin:
        o = [p for p in l["xn"] if not p["hisoblangan"]]
        sig = [p["sigma_h_sm"] for p in o if p.get("sigma_h_sm") is not None]
        ch = [p["chuqurlik"] for p in o if p.get("chuqurlik") is not None]
        g = [p["loyiha"]["gorizontal"] for p in l["xn"] if p.get("loyiha") and p["loyiha"]["yaqin"]]
        l["yigindi"] = {
            "olchangan": len(o), "hisoblangan": len(l["xn"]) - len(o),
            "sifat": {s: sum(1 for p in o if p["sifat"] == s) for s in ("RASMIY", "SKAN", "PAST")},
            "fix": sum(1 for p in o if p.get("rtk_holat") == "FIX"), "sigma_maks": max(sig) if sig else None,
            "chuqurlik": (min(ch), max(ch)) if ch else None,
            "ogish": (max(g), sum(g) / len(g)) if g else None,
        }
    m["yaroqlilik"] = yaroqlilik(m)
    return m


# ---------- har varaq: ramka, shtamp, QR ----------

def _katak(c, x, y, w, h, en=0.25):
    _qalam(c, MATN, en)
    c.rect(x, y, w, h, stroke=1, fill=0)


def _qr(c, url):
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=0)
    q.add_data(url)
    q.make(fit=True)
    mat = q.get_matrix()
    n = len(mat)
    modul = QR_O / (n + 8)          # ISO/IEC 18004: har tomonda 4 modul bo'sh hoshiya
    chet = 4 * modul
    c.setFillColor(white)
    c.setFillAlpha(1)
    c.rect(QR_X, QR_Y, QR_O, QR_O, stroke=0, fill=1)
    c.setFillColor(HexColor("#000000"))
    for i, qator in enumerate(mat):
        j = 0
        while j < n:
            if qator[j]:
                k = j
                while k < n and qator[k]:
                    k += 1
                # qo'shni modullar orasida ingichka oq yoriq qolmasin — bir oz ustma-ust
                c.rect(QR_X + chet + j * modul, QR_Y + QR_O - chet - (i + 1) * modul, (k - j) * modul + 0.01,
                       modul + 0.01, stroke=0, fill=1)
                j = k
            else:
                j += 1
    c.linkURL(url, (QR_X, QR_Y, QR_X + QR_O, QR_Y + QR_O), relative=1, thickness=0)
    matn(c, QR_X + QR_O / 2, QR_Y - 3.2, "Haqiqiyligini", 1.9, tekis="c", rang=MATN2)
    matn(c, QR_X + QR_O / 2, QR_Y - 5.6, "QR orqali tekshiring", 1.9, tekis="c", rang=MATN2)


def _shtamp(c, m, k, N, varaq_nomi):
    o = m["obyekt"]
    x0, y0 = SH_X, SH_Y
    c.setFillColor(white)
    c.rect(x0, y0, SH_W, SH_H, stroke=0, fill=1)
    # chap blok: imzolar (IH-02, O-1: qo'lda to'ldiriladi)
    ust = [17.0, 22.0, 14.0, 12.0]
    yy = [y0 + 50, y0 + 40, y0 + 30, y0 + 20, y0 + 10, y0]
    x = x0
    for w in ust:
        _katak(c, x, y0 + 50, w, 5)
        x += w
    for nom, xx in zip(("Lavozim", "F.I.Sh.", "Imzo", "Sana"), (0, 17, 39, 53)):
        matn(c, x0 + xx + 1, y0 + 51.4, nom, 1.9, rang=MATN2)
    qatorlar = [("Geodezist", "", ""), ("Litsenziya №", "", ""), ("Pudratchi", "", ""), ("Texnik nazorat", "", ""),
                ("Tuzdi (tizim)", m.get("yaratuvchi") or "", m["sana"])]
    for i, (nom, fio, sana) in enumerate(qatorlar):
        y1, y2 = yy[i + 1], yy[i]
        x = x0
        for w in ust:
            _katak(c, x, y1, w, y2 - y1)
            x += w
        matn(c, x0 + 1, y1 + (y2 - y1) / 2 - 0.7, nom, 2.0, kenglik=ust[0] - 1.6)
        if fio:
            matn(c, x0 + 17 + 1, y1 + (y2 - y1) / 2 - 0.7, fio, 1.9, kenglik=ust[1] - 1.6)
        if sana:
            matn(c, x0 + 53 + 0.6, y1 + (y2 - y1) / 2 - 0.7, sana, 1.6, kenglik=ust[3] - 1.0)
    # o'ng blok
    xr = x0 + 65
    _katak(c, xr, y0 + 45, 120, 10)
    nom, ob = _sig(o["nomi"], 116, 3.2, FB)
    matn(c, xr + 2, y0 + 50.6, nom, ob, FB)
    if o.get("manzil"):
        matn(c, xr + 2, y0 + 46.6, "Manzil: " + o["manzil"], 2.0, kenglik=116)
    _katak(c, xr, y0 + 33, 120, 12)
    for i, (a, b) in enumerate((("Buyurtmachi", o.get("buyurtmachi")), ("Pudratchi", o.get("pudratchi")),
                                ("Order (ruxsatnoma)", order_matn(o)))):
        matn(c, xr + 2, y0 + 41.6 - i * 3.6, f"{a}: {b or '—'}", 2.0, kenglik=116)
    _katak(c, xr, y0 + 18, 75, 15)
    satr = _qatorlar(varaq_nomi, 71, 2.9, FB)[:2]
    for i, s in enumerate(satr):
        matn(c, xr + 2, y0 + 27.6 - i * 4.2 + (2 if len(satr) == 1 else 0), s, 2.9, FB, kenglik=71)
    for i, (sarl, qiymat) in enumerate((("Bosqich", "Ijro"), ("Varaq", str(k)), ("Varaqlar", str(N)))):
        xx = xr + 75 + i * 15
        _katak(c, xx, y0 + 28, 15, 5)
        _katak(c, xx, y0 + 18, 15, 10)
        matn(c, xx + 7.5, y0 + 29.4, sarl, 1.8, tekis="c", rang=MATN2)
        matn(c, xx + 7.5, y0 + 21.6, qiymat, 3.2 if i else 2.6, FB, tekis="c")
    _katak(c, xr, y0, 75, 18)
    t = m["tizim"]
    for i, s in enumerate((f"Koordinatalar: {t['nomi']}, m", "X — shimol, Y — sharq (ГОСТ belgilashi)",
                           f"Balandlik: {t['balandlik']}, m", f"Sana: {m['sana']}")):
        matn(c, xr + 2, y0 + 14.2 - i * 3.6, s, 1.95, kenglik=71)
    _katak(c, xr + 75, y0, 45, 18)
    matn(c, xr + 97.5, y0 + 11.0, m["raqam"], 3.0, FB, tekis="c", kenglik=43)
    matn(c, xr + 97.5, y0 + 5.6, "TRACE4D ijro hujjati", 1.9, tekis="c", rang=MATN2)
    _qalam(c, MATN, 0.5)
    c.rect(x0, y0, SH_W, SH_H, stroke=1, fill=0)


def _yaroqlilik_belgisi(c, m):
    """LK-06: har varaqning yuqori o'ng burchagida — topshirishga yaroqli yoki yo'q (sabablari varaqlarda)."""
    y = m.get("yaroqlilik") or {"yaroqli": False}
    s = "TOPSHIRISHGA YAROQLI" if y["yaroqli"] else "TOPSHIRISHGA YAROQSIZ"
    rang = YAROQLI_RANG if y["yaroqli"] else YAROQSIZ_RANG
    w, x1, y1 = _en(s, 2.6, FB) + 6, KX1 - 2, KY1 - 7.6
    c.setFillColor(_toq(rang, 0.12))
    _qalam(c, rang, 0.35)
    c.roundRect(x1 - w, y1, w, 5.6, 1.2, stroke=1, fill=1)
    matn(c, x1 - w / 2, y1 + 1.75, s, 2.6, FB, tekis="c", rang=rang)


def _ramka(c, m, k, N, varaq_nomi):
    _qalam(c, MATN, 0.5)
    c.rect(RX0, RY0, RX1 - RX0, RY1 - RY0, stroke=1, fill=0)
    _shtamp(c, m, k, N, varaq_nomi)
    _qr(c, m["url"])
    _yaroqlilik_belgisi(c, m)


def _pastki_izohlar(c, satrlar, y_bosh, x0=KX0 + 2, x1=PASTKI_X1, o=1.95):
    y = y_bosh
    for s in satrlar:
        for q in _qatorlar(s, x1 - x0, o):
            if y < RY0 + 2.2:
                return
            matn(c, x0, y, q, o, rang=MATN2)
            y -= o * 1.45
        y -= 0.6


# ---------- 1. reja ----------

def _reja_varaq(m):
    lin = m["liniyalar"]
    hamma = [p for l in lin for p in l["nuqtalar"]]
    e0, e1 = min(p["e"] for p in hamma), max(p["e"] for p in hamma)
    n0, n1 = min(p["n"] for p in hamma), max(p["n"] for p in hamma)
    zaxira = QOLDA_QAZISH_M + 3
    w, h = (e1 - e0) + 2 * zaxira, (n1 - n0) + 2 * zaxira
    vw, vh = KX1 - KX0, KY1 - KY0
    S = MASSHTABLAR[-1]
    for s in MASSHTABLAR:
        if w * 1000 / s <= vw - 50 and h * 1000 / s <= vh - 40:
            S = s
            break
    k = 1000 / S
    ec, nc = (e0 + e1) / 2, (n0 + n1) / 2
    cx, cy = (KX0 + KX1) / 2, (KY0 + KY1) / 2

    def X(e):
        return cx + (e - ec) * k

    def Y(n):
        return cy + (n - nc) * k

    def chiz(c):
        _qalam(c, MATN, 0.35)
        c.rect(KX0, KY0, vw, vh, stroke=1, fill=0)
        c.saveState()
        yo = c.beginPath()
        yo.rect(KX0, KY0, vw, vh)
        c.clipPath(yo, stroke=0, fill=0)
        # UTM to'r: kesishuv belgilari
        qadam = _chiroyli_qadam(35 / k)
        ev0, ev1 = ec - (cx - KX0) / k, ec + (KX1 - cx) / k
        nv0, nv1 = nc - (cy - KY0) / k, nc + (KY1 - cy) / k
        tor_e = [q * qadam for q in range(math.ceil(ev0 / qadam), math.floor(ev1 / qadam) + 1)]
        tor_n = [q * qadam for q in range(math.ceil(nv0 / qadam), math.floor(nv1 / qadam) + 1)]
        # LK-08 [G2 6.2]: shaharning topografik plani (mahalliy tizimda) — kulrang fon
        topo = m.get("topo")
        if topo:
            _qalam(c, TOPO_RANG, 0.13)
            for ch in topo["chiziqlar"]:
                xy = [(X(q[0]), Y(q[1])) for q in ch["nuqtalar"]]
                if any(KX0 - 60 < x < KX1 + 60 and KY0 - 60 < y < KY1 + 60 for x, y in xy):
                    _polilinya(c, xy)
            for t in topo["matnlar"]:
                x, y = X(t["x"]), Y(t["y"])
                if KX0 < x < KX1 and KY0 < y < KY1 and t["matn"]:
                    matn(c, x, y, t["matn"], min(max((t.get("h") or 0.5) * k, 1.2), 3.0), rang=TOPO_RANG,
                         burchak=t.get("burchak") or 0.0)
        _qalam(c, REESTR_RANG, 0.18)
        for ge in tor_e:
            for gn in tor_n:
                x, y = X(ge), Y(gn)
                if x < KX0 + 22 or y < KY0 + 7 or y > KY1 - 14 or (x > KX1 - 26 and y > KY1 - 42):
                    continue   # chetdagi to'r yozuvlari, sarlavha, yaroqlilik belgisi va shimol — xoch ustiga tushmasin
                c.line(x - 2.5, y, x + 2.5, y)
                c.line(x, y - 2.5, x, y + 2.5)
        # qo'lda qazish zonasi (2 m) — yarim shaffof keng chiziq
        zona_en = 2 * QOLDA_QAZISH_M * k
        zona_korinadi = zona_en >= 1.0
        if zona_korinadi:
            c.setLineCap(1)
            c.setLineJoin(1)
            for l in lin:
                _qalam(c, TARMOQ.get(l["turi"], (MATN, MATN))[0], zona_en, alfa=0.13)
                _polilinya(c, [(X(p["e"]), Y(p["n"])) for p in l["nuqtalar"]])
            c.setStrokeAlpha(1)
            c.setLineCap(0)
        # reestrdagi boshqa tarmoqlar
        for o in m.get("reestr") or []:
            _qalam(c, REESTR_RANG, 0.25, None if o.get("sifat") == "RASMIY" else [1.6, 0.9])
            xy = [(X(p["e"]), Y(p["n"])) for p in o["nuqtalar"]]
            _polilinya(c, xy)
            i = max(range(len(xy) - 1), key=lambda j: math.dist(xy[j], xy[j + 1]))
            _yorliq_boylab(c, xy[i], xy[i + 1], f"{o['turi']} Ø{o['diametr_mm']} ({o.get('obyekt_nomi') or 'reestr'})",
                           1.8, REESTR_RANG, 1.6)
        # loyiha (DXF)
        loyiha = m.get("loyiha")
        if loyiha:
            for ch in loyiha["chiziqlar"]:
                _qalam(c, LOYIHA_RANG, 0.35, [3.0, 1.2])
                _polilinya(c, [(X(p[0]), Y(p[1])) for p in ch["nuqtalar"]])
        # obyekt liniyalari: kesma sifati — ikki uchining yomonrog'i (SKAN/PAST punktir)
        c.setLineCap(1)
        for l in lin:
            rang = TARMOQ.get(l["turi"], (MATN, MATN))[0]
            P = l["nuqtalar"]
            for i in range(len(P) - 1):
                yomon = geo._yomoni(P[i]["sifat"], P[i + 1]["sifat"])
                yaxlit = yomon == "RASMIY" or (yomon == "SKAN" and _tasdiqlangan(l))   # T-031: tasdiqlangan skan — yaxlit
                _qalam(c, rang, 0.6, None if yaxlit else [2.4, 1.2])
                c.line(X(P[i]["e"]), Y(P[i]["n"]), X(P[i + 1]["e"]), Y(P[i + 1]["n"]))
        c.setLineCap(0)
        _qalam(c)
        # liniya yorliqlari: eng uzun kesma yozuvni sig'dirsa — o'sha kesmada, aks holda liniya bo'ylab; boshqa liniya
        # yoki oldingi yozuv to'smaydigan birinchi o'rin
        qogoz = {l["id"]: [(X(p["e"]), Y(p["n"])) for p in l["nuqtalar"]] for l in lin}
        yozuv_qutilari = []
        for l in lin:
            xy = qogoz[l["id"]]
            yozuv = f"#{l['id']} {liniya_nomi(l)} · {l['sifat']} · L={son(l['uzunlik'], 1)} m"
            tosiq = [q for lid, xy2 in qogoz.items() if lid != l["id"] for q in _namunalar(xy2)]
            i = max(range(len(xy) - 1), key=lambda j: math.dist(xy[j], xy[j + 1]))
            if math.dist(xy[i], xy[i + 1]) >= _en(yozuv, 2.2, FB) + 4:
                nomzod = [(xy[i], xy[i + 1], t) for t in (0.5, 0.32, 0.68, 0.2, 0.8)]
            else:
                st = [0.0]
                for j in range(1, len(xy)):
                    st.append(st[-1] + math.dist(xy[j - 1], xy[j]))
                nomzod = [(_yoy_nuqta(xy, st, st[-1] * f - 2), _yoy_nuqta(xy, st, st[-1] * f + 2), 0.5)
                          for f in (0.5, 0.35, 0.65, 0.25, 0.75)]
            tanlov = nomzod[0]
            for a, b, t in nomzod:
                quti = _yozuv_qutisi(a, b, t, yozuv, 2.2, FB, 2.4)
                if not any(_qutida(quti, q) for q in tosiq) and \
                        not any(_qutida(quti, q) for qq in yozuv_qutilari for q in qq[4]):
                    tanlov = (a, b, t)
                    break
            yozuv_qutilari.append(_yozuv_qutisi(*tanlov, yozuv, 2.2, FB, 2.4))
            _yorliq_boylab(c, tanlov[0], tanlov[1], yozuv, 2.2, TARMOQ.get(l["turi"], (MATN, MATN))[1], 2.4, FB,
                           t=tanlov[2])
        # nuqtalar va raqamlar: avval xarakterli, keyin o'lchangan — joy bo'lsa
        bandlar, yozilgan = [], []
        tashlangan = 0
        tartib = sorted(((0 if p["turi"] not in ("olchangan",) else 1, p["raqam"], p, l) for l in lin for p in l["xn"]),
                        key=lambda t: (t[0], t[1]))
        for _, _, p, l in tartib:
            x, y = X(p["e"]), Y(p["n"])
            muhim = p["turi"] != "olchangan"
            if p["hisoblangan"]:
                c.setFillColor(white)
                _qalam(c, MATN, 0.2)
                c.circle(x, y, 0.65, stroke=1, fill=1)
            else:
                c.setFillColor(HexColor(MATN))
                c.circle(x, y, 0.6 if muhim else 0.35, stroke=0, fill=1)
            s = str(p["raqam"])
            o = 1.8
            tw = _en(s, o)
            joy = None
            if not muhim and any(math.hypot(x - a, y - b) < 6.0 for a, b in yozilgan):
                tashlangan += 1
                continue
            for dx, dy in ((1.1, 1.0), (-1.1 - tw, 1.0), (1.1, -1.0 - o), (-1.1 - tw, -1.0 - o)):
                quti = (x + dx - 0.2, y + dy - 0.3, x + dx + tw + 0.2, y + dy + o)
                if all(quti[2] < b[0] or quti[0] > b[2] or quti[3] < b[1] or quti[1] > b[3] for b in bandlar):
                    joy = (dx, dy, quti)
                    break
            if joy:
                bandlar.append(joy[2])
                yozilgan.append((x, y))
                matn(c, x + joy[0], y + joy[1], s, o, FB if muhim else F, halo=True)
            else:
                tashlangan += 1
        # kesishuvlar
        for l in lin:
            for kk in l["kesishuv"]:
                if kk["takror"]:
                    continue
                x, y = X(kk["e"]), Y(kk["n"])
                p = c.beginPath()
                p.moveTo(x, y + 1.1)
                p.lineTo(x + 1.1, y)
                p.lineTo(x, y - 1.1)
                p.lineTo(x - 1.1, y)
                p.close()
                c.setFillColor(HexColor(SIFAT_RANG["PAST"]) if kk.get("xulosa") == "MOS EMAS" else white)
                _qalam(c, MATN, 0.3)
                c.drawPath(p, stroke=1, fill=1)
                matn(c, x + 1.5, y - 2.8, f"K{kk['k']}", 2.0, FB, halo=True)
        # T-031: RTK tasdiq nuqtalari — uchburchak (yashil — chegarada, qizil — chegaradan tashqarida)
        for t in (m.get("tasdiq") or {}).get("tasdiqlar") or []:
            if t.get("e") is None or t.get("n") is None:
                continue
            x, y = X(t["e"]), Y(t["n"])
            p = c.beginPath()
            p.moveTo(x, y + 1.4)
            p.lineTo(x + 1.2, y - 0.8)
            p.lineTo(x - 1.2, y - 0.8)
            p.close()
            c.setFillColor(HexColor(SIFAT_RANG["RASMIY"] if t.get("otdi") else SIFAT_RANG["PAST"]))
            _qalam(c, MATN, 0.2)
            c.drawPath(p, stroke=1, fill=1)
        c.restoreState()
        # to'r belgilari ramka chetida
        for ge in tor_e:
            x = X(ge)
            if KX0 + 12 < x < KX1 - 12:
                _qalam(c, MATN, 0.25)
                c.line(x, KY0, x, KY0 + 1.6)
                matn(c, x, KY0 + 2.2, f"Y {ge:.0f}", 1.8, tekis="c", rang=MATN2)
        for gn in tor_n:
            y = Y(gn)
            if KY0 + 8 < y < KY1 - 8:
                _qalam(c, MATN, 0.25)
                c.line(KX0, y, KX0 + 1.6, y)
                matn(c, KX0 + 2.2, y + 0.8, f"X {gn:.0f}", 1.8, rang=MATN2)
        # shimol: hujjat tizimining to'r shimoli (yuqori burchakda yaroqlilik belgisi)
        sx, sy = KX1 - 12, KY1 - 34
        p = c.beginPath()
        p.moveTo(sx, sy + 14)
        p.lineTo(sx - 3, sy)
        p.lineTo(sx, sy + 3.5)
        p.close()
        c.setFillColor(HexColor(MATN))
        _qalam(c, MATN, 0.25)
        c.drawPath(p, stroke=1, fill=1)
        p = c.beginPath()
        p.moveTo(sx, sy + 14)
        p.lineTo(sx + 3, sy)
        p.lineTo(sx, sy + 3.5)
        p.close()
        c.setFillColor(white)
        c.drawPath(p, stroke=1, fill=1)
        matn(c, sx, sy + 15.6, "Sh", 3.2, FB, tekis="c")
        matn(c, sx, sy - 3.4, "mahalliy tizim to'ri" if m["tizim"]["tur"] == "mahalliy" else "UTM to'r shimoli", 1.7,
             tekis="c", rang=MATN2)
        matn(c, KX0 + 3, KY1 - 6, "REJA. YER OSTI TARMOQLARINING IJRO S'YOMKASI", 3.6, FB)
        matn(c, KX0 + 3, KY1 - 10.5, f"Masshtab 1:{S}. Koordinatalar: {m['tizim']['nomi']}, to'r qadami "
             f"{son(qadam, 0 if qadam >= 1 else 1)} m. Raqamlar — katalogdagi nuqtalar; K — boshqa tarmoq bilan "
             "kesishuv." + (" Fon — shahar topografik plani." if m.get("topo") else ""), 2.2, rang=MATN2)
        # pastki maydon: shartli belgilar, masshtab chizig'i, izohlar
        _shartli_belgilar(c, m, zona_korinadi)
        _masshtab_chizigi(c, S, k)
        hamma_xn = [(p, l) for l in lin for p in l["xn"] if not p["hisoblangan"]]
        rasmiymas = [(p, l) for p, l in hamma_xn if not _rasmiy_hisoblanadi(p, l)]
        tasdiq_skan = sum(1 for p, l in hamma_xn if p["sifat"] == "SKAN" and _tasdiqlangan(l))
        izoh = []
        if rasmiymas:
            izoh.append(f"Diqqat: {len(rasmiymas)} ta o'lchangan nuqta RASMIY emas "
                        f"(SKAN tasdiqsiz {sum(1 for p, _ in rasmiymas if p['sifat'] == 'SKAN')}, "
                        f"PAST {sum(1 for p, _ in rasmiymas if p['sifat'] == 'PAST')}); ular punktir bilan ko'rsatilgan.")
        if tasdiq_skan:
            izoh.append(f"{tasdiq_skan} ta SKAN nuqta quvur ustidagi RTK tasdig'i bilan tekshirilgan liniyalarda (T-031, "
                        "uchburchaklar) — rasmiy hisoblanadi.")
        if tashlangan:
            izoh.append(f"{tashlangan} ta nuqta raqami zichlik sababli rejada yozilmagan; to'liq ro'yxat katalogda.")
        if not zona_korinadi:
            izoh.append(f"Qo'lda qazish zonasi ({son(QOLDA_QAZISH_M, 0)} m) bu masshtabda ko'rinmaydi.")
        if not (m.get("yaroqlilik") or {}).get("yaroqli"):
            izoh.append("Topshirishga yaroqsiz: sabablar «Geodezik asos» va «Sifat» varaqlarida.")
        if m.get("loyiha_izoh"):
            izoh.append(m["loyiha_izoh"])
        izoh.append(f"Balandliklar ({m['tizim']['balandlik']}), chuqurliklar va sifat — katalog va profillarda.")
        _pastki_izohlar(c, izoh, RY0 + 19.5)

    return [(f"Reja. M 1:{S}", chiz)]


def _yoy_nuqta(xy, st, s):
    """Qog'ozdagi polilinyada stansiya s dagi nuqta."""
    s = max(0.0, min(st[-1], s))
    for j in range(len(st) - 1):
        if st[j + 1] >= s:
            t = 0 if st[j + 1] == st[j] else (s - st[j]) / (st[j + 1] - st[j])
            return (xy[j][0] + (xy[j + 1][0] - xy[j][0]) * t, xy[j][1] + (xy[j + 1][1] - xy[j][1]) * t)
    return xy[-1]


def _namunalar(xy, qadam=1.0):
    """Qog'ozdagi polilinya bo'ylab har ~1 mm da nuqta (yozuv to'sig'ini tekshirish uchun)."""
    natija = []
    for a, b in zip(xy, xy[1:]):
        n = max(1, int(math.dist(a, b) / qadam))
        natija += [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n + 1)]
    return natija


def _tik_burchak(a, b):
    burchak = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
    if burchak > 90:
        burchak -= 180
    elif burchak < -90:
        burchak += 180
    return burchak


def _yozuv_qutisi(a, b, t, s, o, sh, siljish):
    """Burilgan yozuv to'rtburchagi: (markaz x, y, burchak, yarim o'lchamlar, burchak nuqtalari)."""
    burchak = _tik_burchak(a, b)
    r = math.radians(burchak)
    ux, uy, nx, ny = math.cos(r), math.sin(r), -math.sin(r), math.cos(r)
    mx, my = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
    cx, cy = mx + nx * (siljish + o * 0.35), my + ny * (siljish + o * 0.35)
    hw, hh = _en(s, o, sh) / 2 + 0.8, o * 0.75
    burchaklar = [(cx + ux * dx * hw + nx * dy * hh, cy + uy * dx * hw + ny * dy * hh) for dx, dy in
                  ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    return (cx, cy, r, (hw, hh), _namunalar(burchaklar + burchaklar[:1], 1.0))


def _qutida(quti, q):
    cx, cy, r, (hw, hh), _ = quti
    dx, dy = q[0] - cx, q[1] - cy
    return abs(dx * math.cos(r) + dy * math.sin(r)) <= hw and abs(-dx * math.sin(r) + dy * math.cos(r)) <= hh


def _yorliq_boylab(c, a, b, s, o, rang, siljish, sh=F, t=0.5):
    """Kesmaning t ulushida, kesma bo'ylab (o'qiladigan yo'nalishda) yorliq."""
    burchak = _tik_burchak(a, b)
    mx, my = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
    r = math.radians(burchak)
    matn(c, mx - math.sin(r) * siljish, my + math.cos(r) * siljish, s, o, sh, tekis="c", rang=rang, burchak=burchak,
         halo=True)


def _shartli_belgilar(c, m, zona_korinadi):
    lin = m["liniyalar"]
    matn(c, KX0 + 2, RY0 + SH_H - 4, "SHARTLI BELGILAR", 2.4, FB)
    belgilar = []
    for turi in sorted({l["turi"] for l in lin}):
        belgilar.append(("chiziq", TARMOQ.get(turi, (MATN,))[0], None, f"{turi} (bu obyekt)"))
    belgilar.append(("chiziq", MATN, None, "RASMIY yoki RTK tasdiqlangan skan"))
    belgilar.append(("chiziq", MATN, [2.4, 1.2], "SKAN tasdiqsiz / PAST (rasmiy emas)"))
    if (m.get("tasdiq") or {}).get("tasdiqlar"):
        belgilar.append(("uchburchak", SIFAT_RANG["RASMIY"], None, "RTK tasdiq nuqtasi (T-031)"))
    if zona_korinadi:
        belgilar.append(("zona", TARMOQ.get(lin[0]["turi"], (MATN,))[0], None, f"qo'lda qazish zonasi ({son(QOLDA_QAZISH_M, 0)} m)"))
    if m.get("reestr"):
        belgilar.append(("ingichka", REESTR_RANG, None, "reestrdagi boshqa tarmoq"))
    if m.get("loyiha"):
        belgilar.append(("chiziq", LOYIHA_RANG, [3.0, 1.2], "loyiha (DXF)"))
    belgilar += [("nuqta", MATN, None, "o'lchangan nuqta"), ("ochiq", MATN, None, "oraliq nuqta (hisoblangan)"),
                 ("romb", MATN, None, "kesishuv (K)")]
    ustun_x = (KX0 + 2, KX0 + 64)
    for i, (tur, rang, punktir, nom) in enumerate(belgilar[:14]):
        x = ustun_x[i // 7]
        y = RY0 + SH_H - 9 - (i % 7) * 3.6
        if tur in ("chiziq", "ingichka"):
            _qalam(c, rang, 0.6 if tur == "chiziq" else 0.25, punktir)
            c.line(x, y + 0.7, x + 10, y + 0.7)
        elif tur == "zona":
            c.setFillColor(HexColor(rang))
            c.setFillAlpha(0.13)
            c.rect(x, y - 0.6, 10, 2.6, stroke=0, fill=1)
            c.setFillAlpha(1)
        elif tur == "nuqta":
            c.setFillColor(HexColor(rang))
            c.circle(x + 5, y + 0.7, 0.6, stroke=0, fill=1)
        elif tur == "ochiq":
            c.setFillColor(white)
            _qalam(c, rang, 0.2)
            c.circle(x + 5, y + 0.7, 0.65, stroke=1, fill=1)
        elif tur == "uchburchak":
            p = c.beginPath()
            p.moveTo(x + 5, y + 2.0)
            p.lineTo(x + 6.2, y - 0.3)
            p.lineTo(x + 3.8, y - 0.3)
            p.close()
            c.setFillColor(HexColor(rang))
            _qalam(c, MATN, 0.2)
            c.drawPath(p, stroke=1, fill=1)
        elif tur == "romb":
            p = c.beginPath()
            p.moveTo(x + 5, y + 1.8)
            p.lineTo(x + 6.1, y + 0.7)
            p.lineTo(x + 5, y - 0.4)
            p.lineTo(x + 3.9, y + 0.7)
            p.close()
            c.setFillColor(white)
            _qalam(c, MATN, 0.3)
            c.drawPath(p, stroke=1, fill=1)
        _qalam(c)
        matn(c, x + 12, y, nom, 1.95, kenglik=48)


def _masshtab_chizigi(c, S, k):
    x0, y0 = KX0 + 128, RY0 + SH_H - 13
    matn(c, x0, RY0 + SH_H - 4, f"Masshtab 1:{S}", 2.6, FB)
    uz = _chiroyli_qadam(36 / k, (1, 2, 5))
    while uz * k > 44:
        uz /= 2
    w = uz * k
    for i in range(4):
        c.setFillColor(HexColor(MATN) if i % 2 == 0 else white)
        _qalam(c, MATN, 0.2)
        c.rect(x0 + i * w / 4, y0, w / 4, 1.4, stroke=1, fill=1)
    matn(c, x0, y0 + 2.2, "0", 1.8, tekis="c")
    matn(c, x0 + w / 2, y0 + 2.2, son_q(uz / 2), 1.8, tekis="c")
    matn(c, x0 + w, y0 + 2.2, f"{son_q(uz)} m", 1.8, tekis="c")
    matn(c, x0, y0 - 3.2, f"1 sm qog'ozda = {son_q(S / 100)} m joyda", 1.9, rang=MATN2)


# ---------- 2. oqim varaqlari (katalog, sifat) ----------

class _Oqim:
    """Jadval va matnni varaqlarga bo'ladi; yangi varaqda jadval sarlavhasi takrorlanadi."""
    QATOR_H, USTUN_H, GURUH_H = 4.4, 8.6, 5.0

    def __init__(self, sarlavha, pastki):
        self.sarlavha, self.pastki = sarlavha, pastki
        self.varaqlar = [[]]
        self.y = KY1 - 10
        self.ustun = None

    def _joy(self, h):
        if self.y - h < KY0 + 1:
            self.varaqlar.append([])
            self.y = KY1 - 10
            if self.ustun:
                self.varaqlar[-1].append(("ustun", self.y, self.ustun))
                self.y -= self.USTUN_H

    def bolim(self, s):
        self.ustun = None
        self._joy(9 + self.USTUN_H + self.QATOR_H)
        self.y -= 2
        self.varaqlar[-1].append(("bolim", self.y - 3.6, s))
        self.y -= 7

    def ustunlar(self, ustun):
        self._joy(self.USTUN_H + self.QATOR_H)
        self.ustun = ustun
        self.varaqlar[-1].append(("ustun", self.y, ustun))
        self.y -= self.USTUN_H

    def guruh(self, s):
        self._joy(self.GURUH_H + self.QATOR_H)
        self.varaqlar[-1].append(("guruh", self.y, self.ustun, s))
        self.y -= self.GURUH_H

    def qator(self, qiymatlar, ranglar=None):
        self._joy(self.QATOR_H)
        self.varaqlar[-1].append(("qator", self.y, self.ustun, qiymatlar, ranglar or {}))
        self.y -= self.QATOR_H

    def matn(self, s, o=2.2, sh=F, rang=MATN):
        self.ustun = None
        for q in _qatorlar(s, KX1 - KX0 - 6, o, sh):
            self._joy(o * 1.5)
            self.varaqlar[-1].append(("matn", self.y - o, q, o, sh, rang))
            self.y -= o * 1.5
        self.y -= 1

    def bosh_joy(self, h):
        self.y -= h

    def varaq_funksiyalar(self, nomi):
        natija = []
        for i, el in enumerate(self.varaqlar):
            if not el:
                continue
            nom = nomi if i == 0 else f"{nomi} (davomi)"
            natija.append((nom, lambda c, el=el, nom=nom: self._chiz(c, el, nom)))
        return natija

    def _chiz(self, c, elementlar, nom):
        matn(c, KX0 + 3, KY1 - 6, nom.upper(), 3.6, FB)
        for el in elementlar:
            tur, y = el[0], el[1]
            if tur == "bolim":
                matn(c, KX0 + 3, y, el[2], 2.9, FB)
            elif tur == "matn":
                matn(c, KX0 + 3, y, el[2], el[3], el[4], rang=el[5])
            elif tur == "ustun":
                x = KX0 + 3
                for (nomi, w, _) in el[2]:
                    c.setFillColor(HexColor(FON2))
                    _qalam(c, MATN, 0.25)
                    c.rect(x, y - self.USTUN_H, w, self.USTUN_H, stroke=1, fill=1)
                    satr = _qatorlar(nomi, w - 1.4, 2.0, FB)[:2]
                    for j, s in enumerate(satr):
                        yy = y - self.USTUN_H / 2 - 0.7 + (len(satr) - 1) * 1.4 - j * 2.8
                        matn(c, x + w / 2, yy, s, 2.0, FB, tekis="c", kenglik=w - 1.0)
                    x += w
            elif tur == "guruh":
                kenglik = sum(w for _, w, _ in el[2])
                c.setFillColor(HexColor("#F7F9FB"))
                _qalam(c, MATN, 0.25)
                c.rect(KX0 + 3, y - self.GURUH_H, kenglik, self.GURUH_H, stroke=1, fill=1)
                matn(c, KX0 + 4.5, y - self.GURUH_H + 1.5, el[3], 2.2, FB, kenglik=kenglik - 3)
            elif tur == "qator":
                x = KX0 + 3
                for j, (_, w, tekis) in enumerate(el[2]):
                    _qalam(c, CHIZIQ, 0.15)
                    c.rect(x, y - self.QATOR_H, w, self.QATOR_H, stroke=1, fill=0)
                    s = el[3][j] if j < len(el[3]) else ""
                    rang = el[4].get(j, MATN)
                    xx = x + 1 if tekis == "l" else (x + w - 1 if tekis == "r" else x + w / 2)
                    matn(c, xx, y - self.QATOR_H + 1.3, s, 2.05, tekis=tekis, rang=rang, kenglik=w - 1.6)
                    x += w
        _pastki_izohlar(c, self.pastki, RY0 + SH_H - 5)


def _ustun_toldir(ustun, jami=KX1 - KX0 - 6):
    """Oxirgi ustun qolgan kenglikni oladi."""
    band = sum(w for _, w, _ in ustun[:-1])
    nom, _, tekis = ustun[-1]
    return ustun[:-1] + [(nom, max(12.0, jami - band), tekis)]


def _katalog_varaqlar(m):
    lin = m["liniyalar"]
    loyiha = m.get("loyiha")
    ustun = [("№", 9, "c"), ("Nuqta turi", 33, "l"), ("X (shimol), m", 28, "r"), ("Y (sharq), m", 26, "r"),
             ("H o'q, m", 20, "r"), ("H usti, m", 20, "r"), ("H yer, m", 20, "r"), ("Chuqurlik, m", 19, "r"),
             ("Pikitaj", 24, "c"), ("Sifat", 17, "c"), ("Manba", 21, "c"), ("RTK", 15, "c"), ("σH, sm", 14, "r")]
    if loyiha:
        ustun.append(("Loyihadan og'ish, m", 22, "r"))
    ustun = _ustun_toldir(ustun + [("Izoh", 0, "l")])
    pastki = [f"Katalog [ГОСТ Р 51872: 5.4, 6.10]. X — shimol, Y — sharq ({m['tizim']['nomi']}), H — "
              f"{m['tizim']['balandlik']}. H usti = H o'q + D/2; H yer = H usti + chuqurlik (yer sirtidan quvur "
              "ustigacha).",
              "Sifat: " + SIFAT_QOIDASI,
              "Oraliq nuqtalar ikki o'lchangan nuqta orasida chiziqli hisoblangan (G.1.1: to'g'ri qismda kamida har 50 m). "
              "Burilish (≥ 3°, 2 m bazada) va nishab o'zgarishi (≥ 5 ‰, har tomonda 5 m oynada) koordinatalardan avtomatik aniqlangan."]
    q = _Oqim("Koordinatalar katalogi", pastki)
    q.ustunlar(ustun)
    for l in lin:
        y = l["yigindi"]
        q.guruh(f"Liniya #{l['id']}: {liniya_nomi(l)} · L = {son(l['uzunlik'], 2)} m · sifat {l['sifat']} · "
                f"nuqtalar {y['olchangan']} o'lchangan" + (f", {y['hisoblangan']} hisoblangan" if y["hisoblangan"] else "")
                + (f" · egasi: {l['egasi']}" if l.get("egasi") else "") + (f" · {l['ishlash_holati']}" if l.get("ishlash_holati") else "")
                + (f" · {l['ornatilgan_yil']} y." if l.get("ornatilgan_yil") else "") + (f" · {l['parametr']}" if l.get("parametr") else "")
                + " · PAS 128 / ASCE 38: QL-A (ochib bevosita o'lchangan)")
        for p in l["xn"]:
            qiymat = [str(p["raqam"]), geo.YORLIQ.get(p["turi"], p["turi"]), son(p["n"], 3), son(p["e"], 3),
                      son(p.get("h"), 3), son(p.get("usti"), 3), son(p.get("yer"), 3), son(p.get("chuqurlik"), 2),
                      geo.pikitaj(p["stansiya"]), p["sifat"], _manba_matn(p, l),
                      p.get("rtk_holat") or "—", son(p.get("sigma_h_sm"), 1)]
            if loyiha:
                g = p.get("loyiha")
                qiymat.append(son(g["gorizontal"], 2) if g else "—")
            qiymat.append(p.get("izoh") or "")
            q.qator(qiymat, {9: SIFAT_RANG.get(p["sifat"], MATN)})
    # kesishuvlar (IH-04)
    q.bolim("Boshqa tarmoqlar bilan kesishuvlar [ГОСТ Р 51872: 6.8, G.1.1]")
    kesh = [k for l in lin for k in l["kesishuv"] if not k["takror"]]
    if not kesh:
        q.matn(f"Reestrdagi boshqa tarmoqlar bilan kesishuv topilmadi (hududdagi {len(m.get('reestr') or [])} ta reestr "
               "liniyasi va shu obyektning boshqa liniyalari tekshirildi). Reestrda yo'q tarmoqlar tekshirilmaydi.")
    else:
        kus = _ustun_toldir([("K", 10, "c"), ("Liniya", 34, "l"), ("Pikitaj", 22, "c"), ("X (shimol), m", 28, "r"),
                             ("Y (sharq), m", 26, "r"), ("H o'q, m", 20, "r"), ("Boshqa tarmoq", 72, "l"),
                             ("Boshqa H o'q, m", 24, "r"), ("Oraliq, m", 18, "r"), ("Me'yor, m", 18, "r"),
                             ("Joylashuv", 26, "c"), ("Me'yorga mosligi", 0, "l")])
        q.ustunlar(kus)
        lmap = {l["id"]: l for l in lin}
        for k in kesh:
            l = lmap[k["liniya_id"]]
            joy = "—" if k["boshqa_ustida"] is None else ("boshqasi ustida" if k["boshqa_ustida"] else "boshqasi ostida")
            mos = k.get("xulosa") or "baholanmadi"
            ranglar = {}
            if k["oraliq"] is not None and k["oraliq"] < 0:
                ranglar[8] = SIFAT_RANG["PAST"]
            ranglar[11] = SIFAT_RANG["PAST"] if mos == "MOS EMAS" else (SIFAT_RANG["RASMIY"] if mos == "mos" else MATN2)
            q.qator([f"K{k['k']}", f"#{l['id']} {liniya_nomi(l)}", geo.pikitaj(k["stansiya"]), son(k["n"], 3),
                     son(k["e"], 3), son(k["h"], 3),
                     f"{k['boshqa_turi']} Ø{k['boshqa_diametr_mm']} · {k.get('boshqa_obyekt') or ''} · "
                     f"{k.get('boshqa_sifat') or ''}", son(k["boshqa_h"], 3), son(k["oraliq"], 2), son(k.get("meyor_m"), 1), joy,
                     mos + (f" — {k['izoh']}" if mos != "mos" and k.get("izoh") else "")], ranglar)
        pastki.append("Kesishuv: vertikal oraliq — quvur sirtlari orasidagi masofa |H o'q₁ − H o'q₂| − (D₁ + D₂)/2; "
                      "manfiy qiymat balandliklar noaniqligi yoki xato belgisi, joyida tekshiring. Faqat TRACE4D reestri bo'yicha.")
        pastki.append(f"Me'yor (IH-04a): kesishuvda eng kichik vertikal oraliq — {geo.MEYOR_MANBA}: quvur–quvur 0,2 m; "
                      "suv–kanalizatsiya 0,4 m (suv yuqorida); quvur–kabel va kabel–kabel 0,5 m. «MOS EMAS» loyihachi va "
                      "tarmoq egasi e'tiboriga; hujjat yaroqliligiga ta'sir qilmaydi.")
    return q.varaq_funksiyalar("Koordinatalar katalogi")


# ---------- 3. bo'ylama profil ----------

PROFIL_QATORLAR = [("raqam", "Nuqta №", 7.0), ("pikitaj", "Pikitaj", 14.0), ("masofa", "Masofa, m", 9.0),
                   ("nishab", "Nishab, ‰ / uzunlik, m", 11.0), ("chuqurlik", "Chuqurlik (quvur ustigacha), m", 12.0),
                   ("usti", "Quvur usti belgisi, m", 14.0), ("yer", "Yer belgisi, m", 14.0),
                   ("loyiha", "Loyiha belgisi, m", 14.0)]
PX0 = KX0 + 58              # to'r ma'lumot ustuni boshi (chapda qator nomlari)
PX_ICH = PX0 + 4            # chizma boshlanishi
PTOR_Y0 = KY0
PTOR_Y1 = KY0 + sum(h for _, _, h in PROFIL_QATORLAR)
PCHIZ_Y1 = KY1 - 14


def _profil_varaqlar(m):
    natija = []
    loyiha = m.get("loyiha")
    for l in m["liniyalar"]:
        L = l["uzunlik"]
        kenglik = (KX1 - 4) - PX_ICH
        Sg = next((s for s in PROFIL_GOR if L * 1000 / s <= kenglik), None)
        if Sg is None:
            Sg = PROFIL_GOR[-1]
        qism_uz = kenglik * Sg / 1000
        qismlar = max(1, math.ceil(L / qism_uz - 1e-9))
        for qi in range(qismlar):
            s0, s1 = qi * qism_uz, min(L, (qi + 1) * qism_uz)
            nom = f"Bo'ylama profil. Liniya #{l['id']}" + (f" ({qi + 1}/{qismlar})" if qismlar > 1 else "")
            natija.append((nom, lambda c, l=l, s0=s0, s1=s1, Sg=Sg, qi=qi, qismlar=qismlar:
                           _profil_chiz(c, m, l, s0, s1, Sg, qi, qismlar, loyiha)))
    return natija


def _yorliqli(nuqtalar, xf, oraliq=2.7, siyrak=6.0):
    """Profil to'rida qiymat yoziladigan nuqtalar: avval xarakterli (≥ 2,7 mm oraliq), keyin qolganlari siyrak
    (≥ 6 mm) — skan o'qi har 0,5 m da nuqta beradi, hammasi yozilsa to'r o'qib bo'lmaydi."""
    tanlangan = []
    for p in sorted(nuqtalar, key=lambda p: (p["turi"] in ("olchangan", "oraliq"), p["stansiya"])):
        x = xf(p["stansiya"])
        chek = siyrak if p["turi"] in ("olchangan", "oraliq") else oraliq
        if all(abs(x - xf(q["stansiya"])) >= chek for q in tanlangan):
            tanlangan.append(p)
    return sorted(tanlangan, key=lambda p: p["stansiya"])


def _profil_chiz(c, m, l, s0, s1, Sg, qi, qismlar, loyiha):
    r = geo.radius(l)
    rang, mrang = TARMOQ.get(l["turi"], (MATN, MATN))
    pts = [p for p in l["xn"] if s0 - 1e-6 <= p["stansiya"] <= s1 + 1e-6]
    kesh = [k for k in l["kesishuv"] if s0 - 1e-6 <= k["stansiya"] <= s1 + 1e-6]
    loyiha_ell = bool(loyiha) and bool(loyiha.get("z_mos"))     # loyiha belgisi o'lchangan belgilar tizimida
    zlar = []
    for p in pts:
        if p.get("h") is not None:
            zlar += [p["h"] - r, p["usti"]]
        if p.get("yer") is not None:
            zlar.append(p["yer"])
        g = p.get("loyiha")
        if loyiha_ell and g and g.get("loyiha_z") is not None:
            zlar.append(g["loyiha_z"])
    for k in kesh:
        if k["boshqa_h"] is not None:
            r2 = (k["boshqa_diametr_mm"] or 0) / 2000
            zlar += [k["boshqa_h"] - r2, k["boshqa_h"] + r2]

    def xf(s):
        return PX_ICH + (s - s0) * 1000 / Sg

    # sarlavha
    matn(c, KX0 + 3, KY1 - 6, f"BO'YLAMA PROFIL. LINIYA #{l['id']}: {liniya_nomi(l)}"
         + (f" ({qi + 1}/{qismlar}-qism)" if qismlar > 1 else ""), 3.6, FB)
    # to'r
    _qalam(c, MATN, 0.35)
    c.rect(KX0, PTOR_Y0, KX1 - KX0, PTOR_Y1 - PTOR_Y0, stroke=1, fill=0)
    c.line(PX0, PTOR_Y0, PX0, PTOR_Y1)
    y = PTOR_Y0
    qator_y = {}
    for kalit, nomi, h in PROFIL_QATORLAR:
        qator_y[kalit] = (y, y + h)
        _qalam(c, MATN, 0.25)
        c.line(KX0, y + h, KX1, y + h)
        nomi_matn = nomi
        if kalit == "loyiha" and loyiha:
            nomi_matn = f"Loyiha belgisi ({geo.Z_TURLARI.get(loyiha.get('z_turi'), '')}"\
                        f"{'' if loyiha.get('z_mos') else ', boshqa tizim'}), m"
        satr = _qatorlar(nomi_matn, PX0 - KX0 - 3, 2.1)[:3]
        for j, s in enumerate(satr):
            matn(c, KX0 + 1.5, y + h / 2 + (len(satr) - 1) * 1.4 - j * 2.8 - 0.7, s, 2.1)
        y += h
    if not zlar:
        matn(c, (PX0 + KX1) / 2, (PTOR_Y1 + PCHIZ_Y1) / 2, "Balandlik o'lchanmagan: profil chizilmaydi", 3.0,
             tekis="c", rang=MATN2)
        Sv, datum = None, None
    else:
        zmin, zmax = min(zlar), max(zlar)
        bosh = PCHIZ_Y1 - (PTOR_Y1 + 3)
        Sv, datum = PROFIL_VER[-1], math.floor(zmin - 0.3)
        for sv in PROFIL_VER:
            qadam = 0.5 if sv <= 50 else (1.0 if sv <= 200 else 5.0)
            d = math.floor((zmin - 0.3) / qadam) * qadam
            if (zmax + 0.3 - d) * 1000 / sv <= bosh:
                Sv, datum = sv, d
                break

    def yf(z):
        return PTOR_Y1 + 3 + (z - datum) * 1000 / Sv

    yorliqli = _yorliqli(pts, xf)
    if Sv:
        ortiq = Sg / Sv
        matn(c, KX0 + 3, KY1 - 10.5,
             f"Masshtab: gorizontal 1:{Sg}, vertikal 1:{Sv}" + (f" (vertikal {son(ortiq, 0)} marta bo'rttirilgan)" if ortiq > 1.01 else "")
             + f". Balandliklar {m['tizim']['balandlik']}, m. Shartli gorizont {son(datum, 2)} m. "
             f"{geo.pikitaj(s0)} … {geo.pikitaj(s1)}.", 2.2, rang=MATN2)
        # balandlik o'qi
        tik = _chiroyli_qadam(8 * Sv / 1000, (1, 2, 2.5, 5))
        _qalam(c, MATN, 0.25)
        c.line(PX0, PTOR_Y1, PX0, PCHIZ_Y1)
        z = math.ceil(datum / tik) * tik
        while yf(z) <= PCHIZ_Y1 + 0.01:
            c.line(PX0, yf(z), PX0 + 1.5, yf(z))
            matn(c, PX0 - 1.2, yf(z) - 0.7, son(z, 2), 1.9, tekis="r", rang=MATN2)
            z += tik
        matn(c, KX0 + 1.5, PTOR_Y1 + 1.2, f"Sh.G. {son(datum, 2)}", 2.0, FB)
        c.saveState()
        yo = c.beginPath()
        yo.rect(PX0, PTOR_Y1, KX1 - PX0, PCHIZ_Y1 - PTOR_Y1)
        c.clipPath(yo, stroke=0, fill=0)
        # tik chiziqlar yorliqli nuqtalardan to'rgacha
        for p in yorliqli:
            yuqori = max(v for v in (p.get("yer"), p.get("usti"), datum) if v is not None)
            _qalam(c, CHIZIQ, 0.12)
            c.line(xf(p["stansiya"]), yf(yuqori), xf(p["stansiya"]), PTOR_Y1)
        # quvur: o'q ± r, uzluksiz bo'laklar bo'yicha
        bolak = []
        for p in pts + [None]:
            if p is not None and p.get("h") is not None:
                bolak.append(p)
                continue
            if len(bolak) >= 2:
                yuq = [(xf(q["stansiya"]), yf(q["h"] + r)) for q in bolak]
                pas = [(xf(q["stansiya"]), yf(q["h"] - r)) for q in bolak]
                yo = c.beginPath()
                yo.moveTo(*yuq[0])
                for t in yuq[1:] + pas[::-1]:
                    yo.lineTo(*t)
                yo.close()
                c.setFillColor(_toq(rang, 0.35))
                c.drawPath(yo, stroke=0, fill=1)
                for i in range(len(bolak) - 1):
                    yomon = geo._yomoni(bolak[i]["sifat"], bolak[i + 1]["sifat"])
                    _qalam(c, rang, 0.35, None if yomon == "RASMIY" else [1.8, 0.9])
                    c.line(*yuq[i], *yuq[i + 1])
                    c.line(*pas[i], *pas[i + 1])
            bolak = []
        # yer sirti
        _qalam(c, MATN, 0.4)
        bolak = []
        for p in pts + [None]:
            if p is not None and p.get("yer") is not None:
                bolak.append((xf(p["stansiya"]), yf(p["yer"])))
                continue
            _polilinya(c, bolak)
            bolak = []
        # loyiha profili (faqat bir xil balandlik tizimida)
        if loyiha_ell:
            _qalam(c, LOYIHA_RANG, 0.35, [3.0, 1.2])
            bolak = []
            for p in pts + [None]:
                g = p.get("loyiha") if p else None
                if g and g.get("loyiha_z") is not None:
                    bolak.append((xf(p["stansiya"]), yf(g["loyiha_z"])))
                    continue
                _polilinya(c, bolak)
                bolak = []
        _qalam(c)
        # kesishuvlar
        band = []
        for k in kesh:
            x = xf(k["stansiya"])
            r2 = (k["boshqa_diametr_mm"] or 0) / 2000
            yer_bu = _ichki_qiymat(pts, k["stansiya"], "yer")
            matn_y = (yf(yer_bu) if yer_bu is not None else PCHIZ_Y1 - 14) + 3
            yozuv = f"{k['boshqa_turi']} Ø{k['boshqa_diametr_mm']}" + \
                (f", oraliq {son(k['oraliq'], 2)} m" if k["oraliq"] is not None else ", balandlik yo'q")
            w = max(_en(yozuv, 1.8), 6) + 1.5
            while any(x < b[2] and x + w > b[0] and matn_y < b[3] and matn_y + 5.2 > b[1] for b in band):
                matn_y += 5.6
            band.append((x, matn_y, x + w, matn_y + 5.2))
            if k["boshqa_h"] is not None:
                rx, ry = max(r2 * 1000 / Sg, 0.8), max(r2 * 1000 / Sv, 0.8)
                yy = yf(k["boshqa_h"])
                c.setFillColor(_toq(TARMOQ.get(k["boshqa_turi"], (MATN,))[0], 0.75))
                _qalam(c, MATN, 0.25)
                c.ellipse(x - rx, yy - ry, x + rx, yy + ry, stroke=1, fill=1)
                _qalam(c, MATN2, 0.15, [0.8, 0.6])
                c.line(x, yy + ry, x, matn_y - 0.5)
            else:
                _qalam(c, MATN2, 0.2, [0.8, 0.6])
                c.line(x, PTOR_Y1, x, matn_y - 0.5)
            _qalam(c)
            matn(c, x + 0.8, matn_y, f"K{k['k']}", 2.1, FB)
            matn(c, x + 0.8, matn_y + 2.6, yozuv, 1.8, rang=MATN2)
        c.restoreState()
    # to'r qiymatlari
    _qalam(c, MATN, 0.2)
    for p in yorliqli:
        x = xf(p["stansiya"])
        g = p.get("loyiha")
        qiymatlar = {"raqam": str(p["raqam"]), "pikitaj": stansiya_matn(p["stansiya"]), "chuqurlik": son(p.get("chuqurlik"), 2),
                     "usti": son(p.get("usti"), 2), "yer": son(p.get("yer"), 2)}
        if loyiha:
            qiymatlar["loyiha"] = son(g.get("loyiha_z") if g else None, 2)
        for kalit, (ya, yb) in qator_y.items():
            if kalit not in qiymatlar:
                continue
            s = qiymatlar[kalit]
            if kalit == "raqam":
                matn(c, x, ya + 2.0, s, 1.9, FB if p["turi"] != "olchangan" else F, tekis="c")
            else:
                matn(c, x + 0.7, ya + 1.0, s, 1.95, burchak=90, kenglik=yb - ya - 2.0)
        _qalam(c, MATN, 0.2)
        c.line(x, qator_y["masofa"][0], x, qator_y["masofa"][1])
    if not loyiha:
        ya, yb = qator_y["loyiha"]
        matn(c, (PX0 + KX1) / 2, (ya + yb) / 2 - 0.8, "loyiha kiritilmagan", 2.3, tekis="c", rang=MATN2)
    elif not any(p.get("loyiha") and p["loyiha"].get("loyiha_z") is not None for p in pts):
        ya, yb = qator_y["loyiha"]
        matn(c, (PX0 + KX1) / 2, (ya + yb) / 2 - 0.8, "loyihada bu liniya yaqinida balandlik yo'q", 2.3, tekis="c",
             rang=MATN2)
    # masofalar (yorliqli nuqtalar orasida)
    ya, yb = qator_y["masofa"]
    for a, b in zip(yorliqli, yorliqli[1:]):
        xa, xb = xf(a["stansiya"]), xf(b["stansiya"])
        s = son(b["stansiya"] - a["stansiya"], 2)
        if xb - xa >= _en(s, 1.9) + 1.0:
            matn(c, (xa + xb) / 2, ya + 3.0, s, 1.9, tekis="c")
        elif xb - xa >= 2.4:
            matn(c, (xa + xb) / 2 + 0.7, ya + 0.6, s, 1.6, burchak=90, kenglik=yb - ya - 1.2)
    # nishab: sinish nuqtalari orasidagi uchastkalar
    ya, yb = qator_y["nishab"]
    sinish = [p for p in pts if p["turi"] in ("bosh", "oxir", "burilish", "nishab", "tutashuv")]
    if pts and (not sinish or sinish[0] is not pts[0]):
        sinish = [pts[0]] + sinish
    if pts and sinish[-1] is not pts[-1]:
        sinish.append(pts[-1])
    for a, b in zip(sinish, sinish[1:]):
        xa, xb = xf(a["stansiya"]), xf(b["stansiya"])
        _qalam(c, MATN, 0.2)
        c.line(xa, ya, xa, yb)
        c.line(xb, ya, xb, yb)
        uz = b["stansiya"] - a["stansiya"]
        pm = None if (a.get("h") is None or b.get("h") is None or uz <= 0) else (b["h"] - a["h"]) / uz * 1000
        if xb - xa >= 3:
            _qalam(c, MATN2, 0.15)
            if pm is None or abs(pm) < 0.5:
                c.line(xa, (ya + yb) / 2, xb, (ya + yb) / 2)
            elif pm > 0:
                c.line(xa, ya + 0.5, xb, yb - 0.5)
            else:
                c.line(xa, yb - 0.5, xb, ya + 0.5)
        yuq, past = son(abs(pm) if pm is not None else None, 1), son(uz, 2)
        if xb - xa >= max(_en(yuq, 1.9), _en(past, 1.9)) + 2:
            matn(c, (xa + xb) / 2, yb - 3.2, yuq, 1.9, FB, tekis="c")
            matn(c, (xa + xb) / 2, ya + 1.0, past, 1.9, tekis="c")
        elif xb - xa >= 2.6:
            matn(c, (xa + xb) / 2 + 0.7, ya + 0.6, f"{yuq}/{past}", 1.6, burchak=90, kenglik=yb - ya - 1.2)
    # pastki maydon
    matn(c, KX0 + 2, RY0 + SH_H - 4, "SHARTLI BELGILAR", 2.4, FB)
    belgilar = [("yer", "yer sirti"), ("quvur", f"quvur ({liniya_nomi(l)}), o'q ± D/2"),
                ("punktir", "SKAN / PAST uchastka (rasmiy emas)"), ("kesh", "kesishgan tarmoq kesimi (K)")]
    if loyiha_ell:
        belgilar.append(("loyiha", "loyiha profili (DXF)"))
    for i, (tur, nom) in enumerate(belgilar):
        x, y = KX0 + 2 + (i // 4) * 64, RY0 + SH_H - 9 - (i % 4) * 4.1
        if tur == "yer":
            _qalam(c, MATN, 0.4)
            c.line(x, y + 0.7, x + 10, y + 0.7)
        elif tur == "quvur":
            c.setFillColor(_toq(rang, 0.35))
            _qalam(c, rang, 0.35)
            c.rect(x, y - 0.2, 10, 1.8, stroke=1, fill=1)
        elif tur == "punktir":
            _qalam(c, rang, 0.35, [1.8, 0.9])
            c.line(x, y + 0.7, x + 10, y + 0.7)
        elif tur == "kesh":
            c.setFillColor(_toq(rang, 0.75))
            _qalam(c, MATN, 0.25)
            c.ellipse(x + 3.5, y - 0.6, x + 6.5, y + 2.0, stroke=1, fill=1)
        elif tur == "loyiha":
            _qalam(c, LOYIHA_RANG, 0.35, [3.0, 1.2])
            c.line(x, y + 0.7, x + 10, y + 0.7)
        _qalam(c)
        matn(c, x + 12, y, nom, 1.95, kenglik=50)
    izoh = ["Nishab: qalin raqam ‰ (diagonal — pikitaj o'sishi bo'yicha ko'tarilish yoki pasayish), pastida uchastka "
            "uzunligi, m. Uchastka — sinish nuqtalari (boshlanish, burilish, nishab o'zgarishi, oxiri) orasida.",
            "Belgilar va masofalar to'rda faqat ajratilgan nuqtalarda yozilgan; barcha nuqta qiymatlari katalogda."]
    if loyiha and not loyiha_ell:
        izoh.append("Loyiha belgilari boshqa balandlik tizimida: o'lchangan belgilar bilan bevosita taqqoslanmaydi, "
                    "profil chizig'i chizilmagan. Lokalizatsiya qilinsa ikkalasi Boltiqda bo'ladi (LK-07).")
    _pastki_izohlar(c, izoh, RY0 + SH_H - 27)


def _ichki_qiymat(pts, s, kalit):
    for a, b in zip(pts, pts[1:]):
        if a["stansiya"] <= s <= b["stansiya"] and a.get(kalit) is not None and b.get(kalit) is not None:
            t = 0 if b["stansiya"] == a["stansiya"] else (s - a["stansiya"]) / (b["stansiya"] - a["stansiya"])
            return a[kalit] + (b[kalit] - a[kalit]) * t
    return None


# ---------- 4. sifat va kelib chiqish ----------

def _tasdiq_qisqa(l):
    h = l.get("tasdiq") or {}
    if not h or h.get("holat") == "rtk":
        return "shart emas (RTK)"
    return f"{tasdiq_mod.HOLAT_NOMI.get(h.get('holat'), h.get('holat'))} ({h.get('otgan', 0)}/{h.get('soni', 0)})"


def _tasdiq_rang(l):
    h = (l.get("tasdiq") or {}).get("holat")
    return SIFAT_RANG["RASMIY"] if h in ("tasdiqlangan", "rtk") else (SIFAT_RANG["PAST"] if h == "farq" else SIFAT_RANG["SKAN"])


def _tasdiq_bolimi(q, m):
    """T-031: skan o'qining quvur ustidagi RTK o'lchovlari bilan tekshiruvi — liniya holatlari va tasdiq jadvali."""
    lin = m["liniyalar"]
    tq = m.get("tasdiq") or {}
    ch = tq.get("chegaralar") or tasdiq_mod.chegaralar()
    q.bolim("Quvur tasdig'i (T-031): skan o'qining quvur ustidagi RTK o'lchovlari bilan tekshiruvi")
    q.matn(f"Tasdiq — vexa uchi quvur ustida (yoki ochiq uchida o'qda) turganda RTK FIX o'lchovi, T-103 chegaralarida. "
           f"Skan o'qidan og'ish chegarasi: gorizontal ≤ {son(ch['gor_m'] * 100, 0)} sm, vertikal ≤ {son(ch['ver_m'] * 100, 0)} sm. "
           f"Liniya tasdiqlangan hisoblanadi, agar boshi, oxiri va har burilish {son(ch['uch_m'], 0)} m ichida tasdiqlangan va "
           f"qo'shni tasdiqlar orasi ≤ {son(ch['oraliq_m'], 0)} m bo'lsa [ГОСТ Р 51872 G.1.1]. Tasdiqlangan liniyaning SKAN "
           "nuqtalari rasmiy hujjatga kiradi; bitta tasdiq chegaradan chiqsa — FARQ, skan georeferensi qayta o'lchanadi.")
    skan_lin = [l for l in lin if any(p["sifat"] == "SKAN" for p in l["nuqtalar"])]
    if not skan_lin:
        q.matn("Skan liniyasi yo'q: barcha nuqtalar RTK bilan to'g'ridan-to'g'ri o'lchangan, tasdiq shart emas.")
    for l in skan_lin:
        h = l.get("tasdiq") or {}
        og = (f"eng katta og'ish {son((h.get('maks_gor') or 0) * 100, 1)} / "
              f"{son((h.get('maks_ver') or 0) * 100, 1)} sm" if h.get("soni") else "o'lchov yo'q")
        kam = "; ".join(h.get("kamchiliklar") or [])
        q.matn(f"Liniya #{l['id']} {liniya_nomi(l)}: {tasdiq_mod.HOLAT_NOMI.get(h.get('holat'), 'tasdiq yo\'q').upper()} — "
               f"{h.get('otgan', 0)} / {h.get('soni', 0)} tasdiq chegarada, {og}." + (f" Kamchilik: {kam}." if kam else ""),
               2.2, FB if h.get("holat") == "tasdiqlangan" else F, _tasdiq_rang(l))
    tasdiqlar = tq.get("tasdiqlar") or []
    if not tasdiqlar:
        q.matn("Tasdiq o'lchovi yo'q.")
        return
    q.ustunlar(_ustun_toldir([("№", 9, "c"), ("Nomi", 22, "l"), ("Liniya", 14, "c"), ("Pikitaj", 22, "c"),
                              ("X (shimol), m", 28, "r"), ("Y (sharq), m", 26, "r"), ("H, m", 20, "r"), ("Joy", 24, "c"),
                              ("Δ gor., sm", 18, "r"), ("Δ vert., sm", 18, "r"), ("σH / σV, sm", 22, "c"), ("Vaqt", 30, "l"),
                              ("Natija", 0, "l")]))
    for i, t in enumerate(tasdiqlar, 1):
        q.qator([str(i), t.get("nomi") or f"T{t.get('id', i)}", f"#{t['liniya_id']}" if t.get("liniya_id") else "—",
                 t.get("pk") or "—", son(t.get("n"), 3), son(t.get("e"), 3), son(t.get("h"), 3),
                 tasdiq_mod.JOYLAR.get(t.get("joy"), t.get("joy") or "—"),
                 son(None if t.get("d_gor") is None else t["d_gor"] * 100, 1),
                 son(None if t.get("d_ver") is None else t["d_ver"] * 100, 1),
                 f"{son(t.get('sigma_h_sm'), 1)} / {son(t.get('sigma_v_sm'), 1)}", tsh(t.get("vaqt")),
                 ("chegarada" if t.get("otdi") else "CHEGARADAN TASHQARIDA") + (f" · {t['sabab']}" if t.get("sabab") else "")],
                {12: SIFAT_RANG["RASMIY"] if t.get("otdi") else SIFAT_RANG["PAST"]})


def _sifat_varaqlar(m):
    lin = m["liniyalar"]
    loyiha = m.get("loyiha")
    q = _Oqim("Sifat va kelib chiqish", ["Sifat: " + SIFAT_QOIDASI])
    y = m.get("yaroqlilik") or {"yaroqli": False, "sabablar": []}
    q.bolim("Topshirishga yaroqlilik (LK-06)")
    if y["yaroqli"]:
        q.matn("Yaroqli: qazish orderi raqami va sanasi ko'rsatilgan, mahalliy tizim va Boltiq balandligida, lokalizatsiya "
               "va kunlik tekshiruvlar chegarada, barcha "
               "nuqtalar RASMIY yoki quvur ustidagi RTK tasdig'i (T-031) bilan tekshirilgan skan. Rasmiy kuchga geodezist "
               "imzosi bilan kiradi.", 2.3, FB, YAROQLI_RANG)
    else:
        q.matn("YAROQSIZ. Quyidagilar tuzatilmaguncha hujjat ma'lumot uchun:", 2.3, FB, YAROQSIZ_RANG)
        for i, x in enumerate(y["sabablar"], 1):
            q.matn(f"{i}) {x}", 2.2, rang=YAROQSIZ_RANG)
    q.bolim("Liniyalar")
    q.ustunlar(_ustun_toldir([("Liniya", 14, "c"), ("Tarmoq", 40, "l"), ("Uzunlik, m", 20, "r"),
                              ("Nuqtalar (o'lch. / hisobl.)", 28, "c"), ("RASMIY", 16, "r"), ("SKAN", 14, "r"),
                              ("PAST", 14, "r"), ("RTK FIX", 18, "r"), ("σH maks, sm", 20, "r"),
                              ("Chuqurlik, m", 26, "c"), ("Kesishuv (mos emas)", 26, "c"), ("Loyihadan og'ish maks / o'rt., m", 32, "c"),
                              ("RTK tasdiq (T-031)", 32, "c"), ("Sifat", 0, "c")]))
    for l in lin:
        y = l["yigindi"]
        ch = y["chuqurlik"]
        og = y["ogish"]
        q.qator([f"#{l['id']}", liniya_nomi(l), son(l["uzunlik"], 2), f"{y['olchangan']} / {y['hisoblangan']}",
                 str(y["sifat"]["RASMIY"]), str(y["sifat"]["SKAN"]), str(y["sifat"]["PAST"]),
                 f"{y['fix']}/{y['olchangan']}", son(y["sigma_maks"], 1),
                 (f"{son(ch[0], 2)} … {son(ch[1], 2)}" if ch else "—"),
                 f"{len(l['kesishuv'])}" + (f" ({mos_emas})" if (mos_emas := sum(1 for k in l["kesishuv"] if k.get("xulosa") == "MOS EMAS")) else ""),
                 (f"{son(og[0], 2)} / {son(og[1], 2)}" if og else ("—" if not loyiha else "yaqin loyiha yo'q")),
                 _tasdiq_qisqa(l), l["sifat"]],
                {13: SIFAT_RANG.get(l["sifat"], MATN), 12: _tasdiq_rang(l), **({10: SIFAT_RANG["PAST"]} if mos_emas else {})})
    _tasdiq_bolimi(q, m)
    q.bolim("Raqamli muhrlar (K-05: qurilma imzosi → fayl xeshlari → jurnal zanjiri)")
    muhrlar = m.get("muhrlar") or []
    if muhrlar:
        q.ustunlar(_ustun_toldir([("Muhr", 16, "c"), ("Sana", 44, "l"), ("Holat", 30, "c"), ("Yozuvlar", 20, "r"),
                                  ("Zanjir boshi (SHA-256)", 120, "l"), ("Sabab", 0, "l")]))
        for mh in muhrlar:
            q.qator([f"#{mh['id']}", tsh(mh["yaratilgan"]), mh["holat"], str(mh.get("yozuv_soni") or "—"),
                     (mh.get("zanjir_boshi") or "—"), mh.get("sabab") or ""],
                    {2: SIFAT_RANG["RASMIY"] if mh["holat"] == "TASDIQLANGAN" else SIFAT_RANG["PAST"]})
    else:
        q.matn("Muhr yo'q: bu obyekt ma'lumoti dala qurilmasi imzosi bilan tasdiqlanmagan (qo'lda yoki API orqali kiritilgan).")
    q.bolim("Mustaqil qayta hisob (DM-02: data markazda telefon bilan bir xil yadro)")
    tahlillar = m.get("tahlillar") or []
    if tahlillar:
        q.ustunlar(_ustun_toldir([("Tahlil", 16, "c"), ("Manba", 22, "c"), ("Holat", 22, "c"), ("Xulosa", 22, "c"),
                                  ("Quvurlar", 18, "r"), ("O'q farqi maks, m", 28, "r"), ("Tugagan", 44, "l"),
                                  ("Sabab va ogohlantirishlar", 0, "l")]))
        for t in tahlillar:
            sabab = "; ".join((t.get("sabablar") or []) + (t.get("ogohlantirishlar") or [])) or (t.get("xato") or "")
            manba = (f"tashqi: {t.get('manba_nomi') or 'LiDAR'}" if t.get("tur") == "tashqi" else
                     f"M3C2 #{t.get('farq_a_id')}↔#{t.get('farq_b_id')}" if t.get("tur") == "farq" else
                     (f"muhr #{t['muhr_id']}" if t.get("muhr_id") else "—"))
            q.qator([f"#{t['id']}", manba,
                     t["holat"], t.get("xulosa") or "—",
                     str(t["quvur_soni"]) if t.get("quvur_soni") is not None and t.get("tur") != "farq" else "—",
                     son(t.get("oq_farqi_maks_m"), 3),
                     tsh(t.get("tugagan")), sabab],
                    {3: SIFAT_RANG["RASMIY"] if t.get("xulosa") == "MOS" else
                     (SIFAT_RANG["PAST"] if t.get("xulosa") in ("FARQ", "XATO") else (SIFAT_RANG["SKAN"] if t.get("xulosa") == "TASHQI" else MATN))})
    else:
        q.matn("Qayta hisob o'tkazilmagan: obyektda tasdiqlangan muhr bilan yuklangan skan yo'q.")
    q.bolim("Loyiha (IH-07)")
    if loyiha:
        q.matn(f"Fayl: {loyiha.get('fayl_nomi')} · SHA-256 {loyiha.get('sha256')} · yuklangan {tsh(loyiha.get('yaratilgan'))} · "
               f"{len(loyiha['chiziqlar'])} ta chiziq · loyiha belgisi: {geo.Z_TURLARI.get(loyiha.get('z_turi'), '—')}, "
               f"belgi tizimi: {'hujjat bilan bir xil' if loyiha.get('z_mos') else 'boshqa (vertikal taqqoslanmaydi)'}"
               f", koordinata: {'mahalliy' if loyiha.get('koordinata') == 'mahalliy' else 'UTM'}. Gorizontal og'ish — "
               f"nuqtadan eng yaqin loyiha chizig'igacha; {son(geo.LOYIHA_YAQIN_M, 0)} m dan uzoq bo'lsa boshqa tarmoq deb "
               "olinadi. Ruxsat etilgan og'ish loyiha hujjatida: bu hujjat faqat o'lchangan qiymatni beradi.")
    else:
        q.matn("Loyiha DXF kiritilmagan: loyihadan og'ish hisoblanmagan, profilda loyiha belgilari yo'q.")
    q.bolim("Bayonotlar")
    t = m["tizim"]
    if t["tur"] == "mahalliy":
        tizim_bayonot = [
            f"Koordinatalar «{t['nomi']}» tizimida, metr. X — shimol, Y — sharq (ГОСТ Р 51872 belgilashi). O'tish "
            "obyekt atrofidagi geodezik asos punktlarini RTK bilan o'lchab topilgan (lokalizatsiya, «Geodezik asos» "
            "varag'i): natija razbivka tarmog'i punktlariga bog'langan [G2 6.10].",
            "Balandliklar Boltiq 1977 tizimida (normal balandlik): ellipsoid balandligidan shu punktlar bo'yicha topilgan "
            "anomaliya tekisligi ayirilgan. Geoid modeli qo'llanmagan: aniqlik punktlar qamrovi ichida kafolatlanadi."]
    else:
        tizim_bayonot = [
            f"Koordinatalar WGS84 / UTM {m['zona']}N (EPSG:326{m['zona']:02d}), metr. X — shimol, Y — sharq "
            "(ГОСТ Р 51872 belgilashi). Masofalar UTM to'ri bo'yicha: masshtab koeffitsienti 0,9996…1,0004, 100 m da ≤ 4 sm.",
            "Balandliklar WGS84 ellipsoid balandligi, Boltiq emas: farq o'nlab metr. Mahalliy tizim va Boltiq uchun "
            "obyekt atrofidagi kamida 4 ta ma'lum punktni RTK bilan o'lchab lokalizatsiya qiling (LK)."]
    for i, s in enumerate(tizim_bayonot + [
        "O'lchov usuli: rasmiy koordinata va balandliklar — RTK GNSS (FIX) bilan o'lchangan nuqtalar. LiDAR skan — transheya "
        "va quvurning tasdiqlovchi 3D dalili (ShNK 3.01.03-24 ning 406–407-bandlarida LiDAR usuli nomlanmagan): SKAN nuqtalar "
        "faqat quvur ustidagi RTK nuqtalari bilan tasdiqlangan liniyada (T-031) rasmiy hisoblanadi.",
        "Chuqurlik — yer sirtidan quvur ustigacha. H usti = H o'q + D/2; H yer = H usti + chuqurlik.",
        "Sifat qoidasi (T-103) bitta: server va telefon bir xil hisoblaydi. " + SIFAT_QOIDASI,
        "SKAN nuqtalari (LiDAR + RTK traektoriya) quvur ustidagi RTK tasdig'i (T-031) chegarada bo'lgan liniyalarda rasmiy "
        "hisoblanadi: tasdiq nuqtalari rejada uchburchak, holati «Sifat» varag'ida.",
        "Oraliq nuqtalar ikki o'lchangan nuqta orasida chiziqli hisoblangan (ГОСТ Р 51872 G.1.1: to'g'ri qismda kamida har "
        "50 m); katalogda \"hisoblangan\" deb belgilangan. Burilish (≥ 3°, 2 m bazada) va nishab o'zgarishi (≥ 5 ‰, har "
        "tomonda 5 m oynada eng kichik kvadratlar bilan) avtomatik aniqlangan: zich skan shovqini soxta nuqta bermaydi.",
        f"Qo'lda qazish zonasi: tarmoqdan yon tomonga {son(QOLDA_QAZISH_M, 0)} m; undan yaqinda mexanizatsiyalashgan qazish "
        "taqiqlanadi, faqat qo'lda va tarmoq egasi nazoratida.",
        "Kesishuvlar faqat TRACE4D reestridagi tarmoqlar bo'yicha hisoblangan; reestrda yo'q tarmoqlar tekshirilmagan. "
        f"Vertikal oraliq me'yori ({geo.MEYOR_MANBA}) bilan solishtirilgan: «MOS EMAS» — loyihachi va tarmoq egasi e'tiboriga, "
        "hujjat yaroqliligiga ta'sir qilmaydi.",
        "Hujjat TRACE4D tizimida avtomatik tuzilgan. Geodezist imzosi va litsenziya raqamisiz rasmiy kuchga ega emas. "
        "Haqiqiyligini QR orqali tekshiring: sahifada hujjat raqami, PDF xeshi, muhr va qayta hisob holati ko'rsatiladi "
        "(koordinatalarsiz).",
    ], 1):
        q.matn(f"{i}. {s}", 2.2)
    return q.varaq_funksiyalar("Sifat va kelib chiqish")


# ---------- geodezik asos va lokalizatsiya (LK-06) ----------

def _sm(x, n=1):
    return son(None if x is None else x * 100, n)


def _asos_varaqlar(m):
    """Punktlar katalogi, kalibrlash qoldiqlari va LOO, parametrlar, tekshiruv o'lchovlari, ish kunlari, xulosa."""
    asos = m.get("asos") or {}
    t = m["tizim"]
    lq = asos.get("lok")
    pastki = ["Lokalizatsiya [E3 Emlid, T1 Trimble, N1 NGS]: mahalliy Transvers Merkator (k0 = 1) → 4 parametrli "
              "Helmert; balandlik anomaliyasi ≥ 4 punktda qiya tekislik. Chegaralar: ≥ 4 punkt, qoldiq gorizontal "
              f"≤ {lokal.QOLDIQ_GOR_M * 100:.0f} sm, vertikal ≤ {lokal.QOLDIQ_VER_M * 100:.0f} sm; tekshiruv "
              f"≤ {lokal.TEKSHIRUV_GOR_M * 100:.0f} / {lokal.TEKSHIRUV_VER_M * 100:.0f} sm.",
              "LOO — punkt hisobdan chiqarilib, qolganlari bo'yicha bashorat qilingandagi xato (mustaqil tekshiruv)."]
    q = _Oqim("Geodezik asos va lokalizatsiya", pastki)
    if t["tur"] != "mahalliy" or not lq:
        q.bolim("Lokalizatsiya qilinmagan")
        q.matn("Hujjat WGS84 / UTM va ellipsoid balandligida. ГОСТ Р 51872-2024 5.4-band katalogni hududning o'z "
               "koordinata va balandlik tizimida, 6.10-band esa razbivka tarmog'i punktlari va reperlarga nisbatan "
               "talab qiladi. Shu sababli hujjat rasmiy topshirishga yaroqsiz.", 2.3)
        q.matn("Tuzatish: obyekt atrofida, uni o'rab turadigan kamida 4 ta koordinatasi va Boltiq balandligi ma'lum "
               "punktni (shahar tarmog'i yoki qurilish razbivka asosi) har biri kamida 30 s RTK FIX bilan o'lchang, "
               "portalda «Geodezik asos» bo'limida lokalizatsiyani hisoblang. Har o'lchov kuni bitta punktda tekshiruv "
               "o'lchovi qiling.", 2.3)
        if asos.get("punktlar"):
            q.matn(f"Kiritilgan punktlar: {len(asos['punktlar'])} ta, o'lchovlar: {len(asos.get('olchovlar') or [])} ta.", 2.2)
        return q.varaq_funksiyalar("Geodezik asos va lokalizatsiya")
    n = lq["natija"]
    q.bolim(f"Tizim: {t['nomi']} · balandlik: {t['balandlik']}")
    q.matn(f"Lokalizatsiya #{lq['id']}, {tsh(lq['yaratilgan'])}: gorizontal {n['n_gor']} punkt, vertikal {n['n_ver']} "
           f"punkt. Xulosa: {'chegaradan o' + chr(39) + 'tdi' if n.get('yaroqli') else 'chegaradan o' + chr(39) + 'tmadi'}.",
           2.3, FB, YAROQLI_RANG if n.get("yaroqli") else YAROQSIZ_RANG)
    q.bolim("Geodezik asos punktlari (boshlang'ich ma'lumot)")
    q.ustunlar(_ustun_toldir([("Punkt", 30, "l"), ("X (shimol), m", 32, "r"), ("Y (sharq), m", 32, "r"),
                              ("H (Boltiq), m", 26, "r"), ("Sinf", 40, "l"), ("Manba", 0, "l")]))
    for pk in asos.get("punktlar") or []:
        q.qator([pk["nomi"], son(pk.get("x"), 3), son(pk.get("y"), 3), son(pk.get("h"), 3), pk.get("sinf") or "—",
                 pk.get("manba") or "—"])
    q.bolim("Kalibrlash: qoldiqlar va mustaqil tekshiruv (LOO)")
    q.ustunlar(_ustun_toldir([("Punkt", 30, "l"), ("O'lchovlar", 22, "r"), ("dX, sm", 22, "r"), ("dY, sm", 22, "r"),
                              ("Gorizontal qoldiq, sm", 34, "r"), ("Vertikal qoldiq, sm", 34, "r"),
                              ("LOO gorizontal, sm", 32, "r"), ("LOO vertikal, sm", 32, "r"), ("Holat", 0, "c")]))
    loo = {r["nomi"]: r for r in n.get("loo", [])}
    soni = {j["nomi"]: j.get("olchov_soni") for j in (n.get("juftlar") or [])}
    for r in n.get("qoldiqlar", []):
        lo = loo.get(r["nomi"], {})
        yomon = (r["gor"] is not None and r["gor"] > lokal.QOLDIQ_GOR_M) or \
            (r["ver"] is not None and abs(r["ver"]) > lokal.QOLDIQ_VER_M)
        q.qator([r["nomi"], str(soni.get(r["nomi"]) or "—"), _sm(r.get("dX")), _sm(r.get("dY")), _sm(r.get("gor")),
                 _sm(r.get("ver")), _sm(lo.get("gor")), _sm(lo.get("ver")), "chegaradan tashqari" if yomon else "chegarada"],
                {8: YAROQSIZ_RANG if yomon else YAROQLI_RANG})
    q.bolim("Parametrlar")
    p = n["parametrlar"]
    v = p.get("v") or {}
    q.matn(f"Gorizontal: {p.get('gor')}, masshtab {son(n.get('masshtab_ppm'), 1)} ppm, burilish "
           f"{son(n.get('burilish_grad'), 5)}°, markaziy meridian {son(p.get('lon0'), 6)}°; RMS {_sm(n.get('rms_gor'))} sm, "
           f"eng katta {_sm(n.get('maks_gor'))} sm.", 2.2)
    q.matn(f"Vertikal: {v.get('model', '—')}, ζ₀ = {son(v.get('z0'), 3)} m, qiyalik {son(n.get('qiyalik_ppm'), 1)} ppm; "
           f"RMS {_sm(n.get('rms_ver'))} sm, eng katta {_sm(n.get('maks_ver'))} sm.", 2.2)
    for x in n.get("ogohlantirishlar", []):
        q.matn(f"Ogohlantirish: {x}", 2.2, rang=SIFAT_RANG["SKAN"])
    q.bolim("Tekshiruv o'lchovlari (LK-05: kalibrlashga kirmaydi)")
    tek = asos.get("tekshiruvlar") or []
    if tek:
        q.ustunlar(_ustun_toldir([("Sana", 40, "l"), ("Punkt", 30, "l"), ("Gorizontal og'ish, sm", 40, "r"),
                                  ("Vertikal og'ish, sm", 40, "r"), ("Natija", 0, "c")]))
        for x in tek:
            q.qator([tsh(x.get("vaqt")), x["nomi"], _sm(x["gor"]), _sm(x["ver"]),
                     "o'tdi" if x["otdi"] else "O'TMADI"], {4: YAROQLI_RANG if x["otdi"] else YAROQSIZ_RANG})
    else:
        q.matn("Tekshiruv o'lchovi yo'q.", 2.2)
    q.bolim("Ish kunlari nazorati")
    kunlar = asos.get("kunlar") or []
    if kunlar:
        q.ustunlar(_ustun_toldir([("Ish kuni", 40, "l"), ("Holat", 0, "l")]))
        for k in kunlar:
            q.qator([f"{k['kun'][8:10]}.{k['kun'][5:7]}.{k['kun'][:4]}",
                     "tekshirilgan" if k["tekshirilgan"] else "tekshiruv o'lchovi yo'q"],
                    {1: YAROQLI_RANG if k["tekshirilgan"] else YAROQSIZ_RANG})
    else:
        q.matn("Ish kunlari aniqlanmadi.", 2.2)
    return q.varaq_funksiyalar("Geodezik asos va lokalizatsiya")


# ---------- yig'ish ----------

def hujjat_pdf(m):
    """IH-01: PDF baytlari va varaqlar soni. Varaqlar soni oldindan ma'lum — har shtampda "k / N"."""
    _shrift()
    tayyorla(m)
    varaqlar = _reja_varaq(m) + _katalog_varaqlar(m) + _asos_varaqlar(m) + _profil_varaqlar(m) + _sifat_varaqlar(m)
    N = len(varaqlar)
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=landscape(A3), pageCompression=1)
    c.setTitle(f"Ijro hujjati {m['raqam']}: {m['obyekt']['nomi']}")
    c.setAuthor("TRACE4D")
    c.setSubject("Yer osti muhandislik tarmoqlarining ijro s'yomkasi (ГОСТ Р 51872-2024)")
    c.setCreator("TRACE4D ijro hujjati")
    c.setKeywords([m["raqam"], m["tizim"]["nomi"], "ijro s'yomkasi"])
    for k, (nomi, chiz) in enumerate(varaqlar, 1):
        c.saveState()
        c.scale(MM, MM)
        chiz(c)
        _ramka(c, m, k, N, nomi)
        c.restoreState()
        c.showPage()
    c.save()
    return buf.getvalue(), N


def tekshirish_xulosasi(m, N):
    """IH-08: /t/ sahifasi uchun hujjat paytidagi qisqa xulosa. KOORDINATA YO'Q — faqat sanoq va holatlar."""
    lin = m["liniyalar"]
    sifat = {s: sum(l["yigindi"]["sifat"][s] for l in lin) for s in ("RASMIY", "SKAN", "PAST")}
    muhr, tahlil = {}, {}
    for h in m.get("muhrlar") or []:
        muhr[h["holat"]] = muhr.get(h["holat"], 0) + 1
    for t in m.get("tahlillar") or []:
        k = t.get("xulosa") or t["holat"]
        tahlil[k] = tahlil.get(k, 0) + 1
    o = m["obyekt"]
    y = m.get("yaroqlilik") or {}
    tq_l = (m.get("tasdiq") or {}).get("liniyalar") or {}
    skan_lin = [l for l in lin if any(p["sifat"] == "SKAN" for p in l["nuqtalar"])]
    tasdiq = {"kerak": len(skan_lin), "tasdiqlangan": sum(1 for l in skan_lin if tasdiq_mod.tasdiqlangan(tq_l, l["id"])),
              "farq": sum(1 for l in skan_lin if (tq_l.get(l["id"]) or {}).get("holat") == "farq"),
              "olchovlar": len((m.get("tasdiq") or {}).get("tasdiqlar") or [])}
    return {"tizim": m["tizim"]["nomi"], "balandlik": m["tizim"]["balandlik"], "yaroqli": bool(y.get("yaroqli")),
            "sabablar_soni": len(y.get("sabablar") or []), "tasdiq": tasdiq,
            "obyekt": o["nomi"], "pudratchi": o.get("pudratchi") or "", "order": o.get("order_raqami") or "",
            "order_sana": o.get("order_sana") or "",
            "sana": m["sana"], "varaqlar": N, "liniyalar": len(lin), "uzunlik_m": round(sum(l["uzunlik"] for l in lin), 2),
            "tarmoqlar": sorted({l["turi"] for l in lin}), "nuqtalar": sifat, "muhr": muhr, "tahlil": tahlil,
            "loyiha": bool(m.get("loyiha")),
            "kesishuvlar": sum(1 for l in lin for k in l["kesishuv"] if not k["takror"]),
            "kesishuv_mos_emas": sum(1 for l in lin for k in l["kesishuv"] if not k["takror"] and k.get("xulosa") == "MOS EMAS")}
