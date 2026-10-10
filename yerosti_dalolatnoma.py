"""ShN-05: Yopiq ishlar dalolatnomasi — ShNQ 3.01.01-22, 28-band va 6-ilova shakli, muhrlangan dalil to'plami bilan.

28-band: qurilish jarayonidagi yopiq ishlarga 6-ilova shakli bo'yicha dalolatnoma tuziladi, navbatdagi ishlar boshlanishidan
OLDIN. 1-varaq — shaklning o'zi, maydonlar 6-ilova tartibida. Komissiya xulosasi, chetga chiqish haqidagi qaror va imzolar
odamniki: dastur ularni o'zi yozmaydi (kiritilmasa — qo'lda to'ldirish uchun bo'sh chiziq). Ilova varaqlari — ko'rikka
taqdim etilgan ishlarning o'lchov dalili: liniyalar, o'lchov davri (transheya ochiq paytda), raqamli muhrlar, mustaqil qayta
hisob, ijro s'yomkasi hujjati va muhr jurnalida xeshi bor rasmlar (rasm baytlari o'zgartirilmasdan joylanadi).
"""
import io
import math
from datetime import datetime, timedelta, timezone

from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import A4
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas

import yerosti_ijro as ijro
from yerosti_ijro import F, FB, MATN, MATN2, MM, matn, son, tsh

SHAKL = "ShNQ 3.01.01-22, 6-ilova"
OYLAR = ("yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avgust", "sentabr", "oktabr", "noyabr", "dekabr")
TARMOQ_ISHI = {"suv": "suv ta'minoti quvuri", "kanalizatsiya": "kanalizatsiya quvuri", "gaz": "gaz quvuri",
               "elektr": "elektr kabeli", "optika": "optik aloqa kabeli", "issiqlik": "issiqlik tarmog'i quvuri"}
VAKILLAR = (("pudratchi", "Qurilish-montaj tashkilotining vakili"), ("buyurtmachi", "Buyurtmachining vakili"),
            ("loyiha", "Loyiha tashkilotining vakili"))
# 6-ilova imzo qismidagi yozilishi
IMZOLAR = ("Qurilish-montaj tashkiloti vakili", "Buyurtmachining vakili", "Loyiha tashkilotining vakili")
UZUNLIK = {"ishlar_nomi": 500, "loyiha_hujjati": 500, "materiallar": 1000, "chetga_chiqish_izoh": 500, "xulosa": 1500,
           "keyingi_ishlar": 500}
KENG, BAL = 210.0, 297.0                       # A4 portret, mm
X0, X1, Y0, Y1 = 20.0, 200.0, 12.0, 287.0      # chapda 20 mm tikish uchun (ГОСТ 2.301 bilan bir xil yondashuv)
TOLIQ_RANG, KAM_RANG, CHIZIQ = "#0F7A3D", "#C0262D", "#8C96A3"
MAKS_RASM = 12


# ---------- kirish ----------

def kirish_tekshir(t):
    """Foydalanuvchi kiritgan maydonlar: uzunlik, sana shakli, chetga chiqish tanlovi. Noto'g'ri bo'lsa ValueError."""
    import yerosti_baza as baza
    if not isinstance(t, dict):
        raise ValueError("tana JSON obyekt bo'lsin")
    k = {}
    for nom, n in UZUNLIK.items():
        v = t.get(nom, "")
        if not isinstance(v, str):
            raise ValueError(f"{nom}: matn bo'lsin")
        if len(v) > n:
            raise ValueError(f"{nom}: {n} belgidan oshmasin")
        k[nom] = v.strip()
    for nom in ("sana", "boshlanish", "tugash"):
        k[nom] = baza.sana_tekshir(t.get(nom, ""))
    if not k["sana"]:
        k["sana"] = datetime.now(timezone(timedelta(hours=5))).date().isoformat()
    if k["boshlanish"] and k["tugash"] and k["boshlanish"] > k["tugash"]:
        raise ValueError("ishlarning boshlanish sanasi tugash sanasidan keyin")
    ch = str(t.get("chetga_chiqish", "") or "")
    if ch not in ("", "yoq", "bor"):
        raise ValueError("chetga_chiqish: 'yoq', 'bor' yoki bo'sh")
    k["chetga_chiqish"] = ch
    v = t.get("vakillar") or {}
    if not isinstance(v, dict):
        raise ValueError("vakillar: obyekt bo'lsin")
    k["vakillar"] = {}
    for rol, _ in VAKILLAR:
        x = v.get(rol) or {}
        if not isinstance(x, dict):
            raise ValueError(f"vakillar.{rol}: obyekt bo'lsin")
        fio, lav = str(x.get("fio", "") or "").strip(), str(x.get("lavozim", "") or "").strip()
        if len(fio) > 120 or len(lav) > 120:
            raise ValueError(f"vakillar.{rol}: F.I.O. va lavozim 120 belgidan oshmasin")
        k["vakillar"][rol] = {"fio": fio, "lavozim": lav}
    idlar = t.get("liniya_idlar")
    if idlar in (None, ""):
        k["liniya_idlar"] = None
    else:
        if not isinstance(idlar, list) or not all(isinstance(i, int) for i in idlar) or not idlar:
            raise ValueError("liniya_idlar: butun sonlar ro'yxati")
        k["liniya_idlar"] = sorted(set(idlar))
    return k


# ---------- ma'lumot ----------

def _ish_nomi(l):
    return f"{TARMOQ_ISHI.get(l['turi'], l['turi'])} Ø{l['diametr_mm']}" + (f" {l['material']}" if l.get("material") else "")


def malumot_yig(obyekt_id, kirish, raqam, url, yaratuvchi):
    """Bazadan dalolatnoma va dalil to'plami uchun hamma narsa. O'lchov dalili ijro hujjati bilan bir xil hisobdan
    (ijro.malumot_yig + tayyorla): uzunlik, chuqurlik, sifat, T-031, loyihadan og'ish."""
    import yerosti_baza as baza
    m = ijro.malumot_yig(obyekt_id, raqam, url, yaratuvchi)
    if kirish["liniya_idlar"]:
        bor = {l["id"] for l in m["liniyalar"]}
        yoq = [i for i in kirish["liniya_idlar"] if i not in bor]
        if yoq:
            raise ValueError(f"liniya shu obyektda topilmadi: {', '.join(map(str, yoq))}")
        m["liniyalar"] = [l for l in m["liniyalar"] if l["id"] in kirish["liniya_idlar"]]
    ijro.tayyorla(m)
    tanlangan = {l["id"] for l in m["liniyalar"]}
    vaqtlar = sorted(str(n.get("vaqt") or l.get("yaratilgan")) for l in baza.liniyalar_toliq(obyekt_id=obyekt_id)
                     if l["id"] in tanlangan for n in l["nuqtalar"] if (n.get("vaqt") or l.get("yaratilgan")))
    ijrolar = [h for h in baza.hujjatlar(obyekt_id) if (h.get("tur") or "ijro") == "ijro" and h["holat"] == "amal"]
    rasmlar = baza.muhrlangan_rasmlar(obyekt_id)
    for r in rasmlar[:MAKS_RASM]:
        with open(baza.skan_yoli(r["skan_id"]), "rb") as f:
            r["baytlar"] = f.read()
    m.update({"kirish": kirish, "olchov_davri": (vaqtlar[0], vaqtlar[-1]) if vaqtlar else None,
              "rasmlar": rasmlar, "ijro_hujjat": ijrolar[0] if ijrolar else None,
              "loyiha_xom": baza.loyiha_top(obyekt_id)})
    m["kamchiliklar"], m["ogohlantirishlar"] = kamchiliklar(m)
    return m


def kamchiliklar(m):
    """Dalil to'plami TO'LIQ emasligi sabablari (komissiya ko'rishi kerak) va ogohlantirishlar (to'liqlikka ta'sir qilmaydi)."""
    k, o = [], []
    if not any(x["holat"] == "TASDIQLANGAN" for x in m.get("muhrlar") or []):
        k.append("obyektda TASDIQLANGAN raqamli muhr yo'q: o'lchovlar dala qurilmasi imzosi bilan tasdiqlanmagan")
    ob = m.get("obyekt") or {}
    yoq = [nom for nom, kalit in (("raqami", "order_raqami"), ("sanasi", "order_sana")) if not str(ob.get(kalit) or "").strip()]
    if yoq:
        k.append("qazish orderining " + " va ".join(yoq) + " ko'rsatilmagan [ShNK 3.01.03-24, 420-band]")
    tq = (m.get("tasdiq") or {}).get("liniyalar") or {}
    for l in m["liniyalar"]:
        y = l["yigindi"]
        if y["sifat"]["PAST"]:
            k.append(f"liniya #{l['id']}: {y['sifat']['PAST']} ta o'lchangan nuqta PAST (T-103)")
        if y["sifat"]["SKAN"] and not ijro.tasdiq_mod.tasdiqlangan(tq, l["id"]):
            k.append(f"liniya #{l['id']}: SKAN nuqtalar quvur ustidagi RTK tasdig'isiz (T-031)")
    if not m.get("olchov_davri"):
        k.append("o'lchov vaqti yozilmagan: ish ochiq paytda o'lchangani ko'rsatilmaydi")
    if not m.get("rasmlar"):
        o.append("muhrlangan rasm yo'q (dalil — RTK va skan)")
    if not m.get("ijro_hujjat"):
        o.append("ijro s'yomkasi hujjati hali tuzilmagan")
    return k, o


def _sana_soz(iso):
    """2026-10-05 → «05» oktabr 2026 y."""
    try:
        d = datetime.strptime(iso, "%Y-%m-%d")
    except (TypeError, ValueError):
        return "«____» _____________ 20___ y."
    return f"«{d.day:02d}» {OYLAR[d.month - 1]} {d.year} y."


def _uzunlik(x):
    return son(x, 1).replace(".", ",") if x is not None else "—"


def _chuqurlik(ch):
    """(min, max) → «1,6–1,8» yoki bir xil bo'lsa «1,68»."""
    if not ch:
        return None
    return son(ch[0], 2) if abs(ch[1] - ch[0]) < 0.005 else f"{son(ch[0], 2)}–{son(ch[1], 2)}"


def avto_matnlar(m):
    """Foydalanuvchi bo'sh qoldirgan maydonlar uchun dastur taklifi (faqat o'lchangan faktlar)."""
    lin = m["liniyalar"]
    jami = sum(l["uzunlik"] for l in lin)
    ishlar = "yer osti muhandislik tarmoqlarini yotqizish: " + "; ".join(
        f"{_ish_nomi(l)} — {_uzunlik(l['uzunlik'])} m" for l in lin) + f" (jami {_uzunlik(jami)} m)"
    taqdim = []
    for l in lin:
        ch = l["yigindi"]["chuqurlik"]
        taqdim.append(f"liniya #{l['id']}: {_ish_nomi(l)}, uzunligi {_uzunlik(l['uzunlik'])} m"
                      + (f", yotqizish chuqurligi {_chuqurlik(ch)} m" if ch else ""))
    guruh = {}
    for l in lin:
        kalit = (l.get("material") or "material ko'rsatilmagan", l["diametr_mm"], l["turi"])
        guruh[kalit] = guruh.get(kalit, 0) + l["uzunlik"]
    materiallar = "; ".join(f"{mat} Ø{d} ({TARMOQ_ISHI.get(t, t)}) — {_uzunlik(u)} m" for (mat, d, t), u in sorted(guruh.items(), key=str))
    return {"ishlar_nomi": ishlar, "taqdim": taqdim, "materiallar": materiallar,
            "keyingi_ishlar": "transheyani qayta ko'mish (tuproq bilan to'ldirish va zichlash)"}


def _ogish(m):
    """Loyihadan o'lchangan og'ish (loyiha DXF bo'lsa): gorizontal va vertikal maksimum, m."""
    g, v = [], []
    for l in m["liniyalar"]:
        for p in l["xn"]:
            x = p.get("loyiha")
            if x and x.get("yaqin"):
                g.append(abs(x["gorizontal"]))
                if x.get("vertikal") is not None:
                    v.append(abs(x["vertikal"]))
    return (max(g) if g else None, max(v) if v else None)


# ---------- chizish ----------

class _Varaq:
    """A4 bo'yicha yozuv: y kursor, sahifa to'lsa yangi varaq. Ikki o'tish: avval varaqlar soni, keyin «k / N»."""

    def __init__(self, c, m, N, pastki=None):
        self.c, self.m, self.N = c, m, N
        self.pastki_matn = pastki or f"{m['raqam']} · Yopiq ishlar dalolatnomasi · {SHAKL} · TRACE4D"
        self.k = 0
        self.y = Y1
        self.yangi()

    def yangi(self):
        if self.k:
            self._pastki()
            self.c.restoreState()
            self.c.showPage()
        self.k += 1
        self.c.saveState()
        self.c.scale(MM, MM)
        self.y = Y1 - 2

    def _pastki(self):
        c, m = self.c, self.m
        c.setStrokeColor(HexColor(CHIZIQ))
        c.setLineWidth(0.2)
        c.line(X0, Y0 + 4, X1, Y0 + 4)
        matn(c, X0, Y0, self.pastki_matn, 2.1, rang=MATN2)
        matn(c, X1, Y0, f"varaq {self.k}" + (f" / {self.N}" if self.N else ""), 2.1, tekis="r", rang=MATN2)

    def joy(self, h):
        if self.y - h < Y0 + 8:
            self.yangi()

    def oraliq(self, h):
        self.y -= h

    def satrlar(self, s, o=3.0, sh=F, rang=MATN, x=X0, kenglik=None, qadam=1.38):
        for q in ijro._qatorlar(s, (kenglik or (X1 - x)), o, sh):
            self.joy(o * qadam)
            self.y -= o * qadam
            matn(self.c, x, self.y, q, o, sh, rang=rang)

    def maydon(self, qiymat, izoh, o=3.0, satr=1, x=X0, oldi=None):
        """Shakl maydoni: (oldi matn) + qiymat chiziq ustida, ostida kichik kulrang izoh — 6-ilovadagidek."""
        c = self.c
        qatorlar = ijro._qatorlar(qiymat, X1 - x - (ijro._en(oldi, o) + 2 if oldi else 0), o) if qiymat else [""]
        qatorlar += [""] * max(0, satr - len(qatorlar))
        for i, q in enumerate(qatorlar):
            self.joy(o * 1.6 + (3 if izoh and i == len(qatorlar) - 1 else 0))
            self.y -= o * 1.6
            xx = x
            if oldi and i == 0:
                matn(c, x, self.y + 0.6, oldi, o)
                xx = x + ijro._en(oldi, o) + 2
            c.setStrokeColor(HexColor(CHIZIQ))
            c.setLineWidth(0.18)
            c.line(xx, self.y - 0.8, X1, self.y - 0.8)
            if q:
                matn(c, xx + 1, self.y + 0.4, q, o, rang="#0B2A55")
        if izoh:
            self.y -= 2.6
            matn(c, (x + X1) / 2, self.y, izoh, 2.1, tekis="c", rang=MATN2)

    def bolim(self, s, o=3.4):
        self.joy(o * 3)
        self.y -= o * 1.9
        matn(self.c, X0, self.y, s, o, FB)
        self.y -= 1.2

    def jadval(self, ustunlar, qatorlar, o=2.4):
        """ustunlar: [(sarlavha, kenglik mm, tekis)], qatorlar: [[matn...]]. Kenglik yig'indisi ≤ 180."""
        c = self.c

        def sarlavha():
            self.joy(o * 2.4)
            self.y -= o * 1.8
            x = X0
            for nom, w, _ in ustunlar:
                matn(c, x + 1, self.y, nom, o * 0.92, FB, rang=MATN2, kenglik=w - 2)
                x += w
            c.setStrokeColor(HexColor(CHIZIQ))
            c.setLineWidth(0.2)
            c.line(X0, self.y - 1.2, X0 + sum(w for _, w, _ in ustunlar), self.y - 1.2)
            self.y -= 1.2
        sarlavha()
        for q in qatorlar:
            if self.y - o * 1.8 < Y0 + 8:
                self.yangi()
                sarlavha()
            self.y -= o * 1.7
            x = X0
            for (nom, w, tekis), s in zip(ustunlar, q):
                xx = x + 1 if tekis == "l" else (x + w - 1 if tekis == "r" else x + w / 2)
                matn(c, xx, self.y, s, o, tekis=tekis, kenglik=w - 2)
                x += w


def _qr(c, url, x, y, o):
    """QR (mm): ijro hujjatidagi bilan bir xil usul — 4 modulli bo'sh hoshiya."""
    q = ijro.qrcode.QRCode(error_correction=ijro.qrcode.constants.ERROR_CORRECT_M, border=0)
    q.add_data(url)
    q.make(fit=True)
    mat = q.get_matrix()
    n = len(mat)
    modul = o / (n + 8)
    chet = 4 * modul
    c.setFillColor(white)
    c.rect(x, y, o, o, stroke=0, fill=1)
    c.setFillColor(HexColor("#000000"))
    for i, qator in enumerate(mat):
        j = 0
        while j < n:
            if qator[j]:
                k = j
                while k < n and qator[k]:
                    k += 1
                c.rect(x + chet + j * modul, y + o - chet - (i + 1) * modul, (k - j) * modul + 0.01, modul + 0.01, stroke=0, fill=1)
                j = k
            else:
                j += 1
    c.linkURL(url, (x, y, x + o, y + o), relative=1, thickness=0)


def _shakl_varaq(v, m):
    """1-varaq: 6-ilova shakli tartibida."""
    c, k, a = v.c, m["kirish"], avto_matnlar(m)
    o = m["obyekt"]
    _qr(c, m["url"], X1 - 24, Y1 - 24, 24)
    matn(c, X1 - 12, Y1 - 27, "Haqiqiyligini QR orqali tekshiring", 1.9, tekis="c", rang=MATN2)
    matn(c, X0, Y1 - 3, f"{SHAKL} shakli bo'yicha", 2.4, rang=MATN2)
    matn(c, X0, Y1 - 9, m["raqam"], 4.2, FB)
    toliq = not m["kamchiliklar"]
    matn(c, X0, Y1 - 15, "DALIL TO'PLAMI TO'LIQ" if toliq else f"DALIL TO'PLAMI TO'LIQ EMAS: {len(m['kamchiliklar'])} ta kamchilik (ilovada)",
         2.6, FB, rang=TOLIQ_RANG if toliq else KAM_RANG)
    v.y = Y1 - 34
    matn(c, (X0 + X1) / 2, v.y, "YOPIQ ISHLAR DALOLATNOMASI", 5.0, FB, tekis="c")
    v.y -= 4
    v.maydon(f"{o['nomi']}" + (f", {o['manzil']}" if o.get("manzil") else "") + " da", "(obyekt nomi va joylashish o'rni)")
    v.maydon(k["ishlar_nomi"] or a["ishlar_nomi"], "(ishlar nomi)", oldi="bajarilgan", satr=2)
    v.oraliq(3)
    v.joy(6)
    v.y -= 5
    matn(c, X1, v.y, _sana_soz(k["sana"]), 3.2, tekis="r")
    v.y -= 2
    v.bolim("Ishchi guruh tarkibi:", 3.2)
    for rol, nom in VAKILLAR:
        x = k["vakillar"][rol]
        v.maydon(", ".join(s for s in (x["fio"], x["lavozim"]) if s), "(F.I.O., lavozimi)", oldi=nom)
    v.maydon(o.get("pudratchi") or "", "(qurilish-montaj tashkilotining nomi)")
    v.satrlar("tomonidan bajarilgan quyidagi ishlar bo'yicha ko'rik o'tkazdi va quyidagilar to'g'risida ushbu "
              "dalolatnomani tuzdi:", 3.0)
    v.oraliq(1)
    v.satrlar("1. Aniqlik kiritishga quyidagi ishlar taqdim etilgan:", 3.0, FB)
    v.maydon("; ".join(a["taqdim"]), "(yopiq ishlarning nomi)", satr=2)
    v.satrlar("2. Ishlar quyidagi loyiha bo'yicha bajarilgan:", 3.0, FB)
    v.maydon(k["loyiha_hujjati"], "(loyihalash tashkilotining nomi, chizmalar raqami va sanasi)", satr=2)
    lx = m.get("loyiha_xom")
    if lx:
        v.satrlar(f"TRACE4D da loyiha fayli: {lx.get('fayl_nomi')} · SHA-256 {str(lx.get('sha256'))[:16]}… · yuklangan "
                  f"{tsh(lx.get('yaratilgan'))}", 2.2, rang=MATN2)
    v.satrlar("3. Ishlarni bajarishda qo'llanildi:", 3.0, FB)
    v.maydon(k["materiallar"] or a["materiallar"], "(sertifikatlar yoki sifatni tasdiqlovchi boshqa hujjatlar ilova qilingan "
             "holda materiallar, konstruksiyalar, buyumlarning nomlari)", satr=2)
    tanlov = {"yoq": "yo'l qo'yilmagan", "bor": "yo'l qo'yilgan"}.get(k["chetga_chiqish"], "yo'l qo'yilmagan (yoki yo'l qo'yilgan)")
    v.satrlar(f"4. Ishlarni bajarishda loyiha hujjatidan chetga chiqishga {tanlov}:", 3.0, FB)
    v.maydon(k["chetga_chiqish_izoh"], "(chizmalarning nomeri va sanasi)")
    g, vv = _ogish(m)
    v.satrlar("TRACE4D o'lchovi: " + (f"loyihadan og'ish gorizontal maks {son(g, 2)} m"
                                      + (f", vertikal maks {son(vv, 2)} m" if vv is not None else "") if g is not None
                                      else "loyiha DXF yuklanmagan — og'ish o'lchanmagan"), 2.2, rang=MATN2)
    v.maydon(ijro.sana_uz(k["boshlanish"]), None, oldi="5. Ishlarning boshlanish sanasi")
    v.maydon(ijro.sana_uz(k["tugash"]), None, oldi="    Ishlarning tugash sanasi")
    od = m.get("olchov_davri")
    if od:
        v.satrlar(f"TRACE4D o'lchovi (ochiq transheya): {tsh(od[0])} – {tsh(od[1])}", 2.2, rang=MATN2)
    v.bolim("Xulosa", 3.2)
    v.maydon(k["xulosa"], None, satr=3)
    v.oraliq(1)
    v.satrlar("Yuqorida ta'kidlanganlarga asosan quyidagi ishlarni bajarish mumkin:", 3.0)
    v.maydon(k["keyingi_ishlar"] or a["keyingi_ishlar"], "(ishlar va konstruksiyalarning nomlari)")
    v.oraliq(3)
    for nom in IMZOLAR:
        v.joy(9)
        v.y -= 7
        matn(c, X0, v.y, nom, 3.0)
        c.setStrokeColor(HexColor(CHIZIQ))
        c.line(X1 - 60, v.y - 0.8, X1, v.y - 0.8)
        matn(c, X1 - 30, v.y - 3.4, "(imzo)", 2.1, tekis="c", rang=MATN2)
    v.oraliq(6)
    v.satrlar("Dalolatnoma TRACE4D tizimida o'lchov ma'lumotlaridan tuzilgan; komissiya xulosasi va imzolarsiz kuchga ega emas. "
              "Muhrlangan dalil to'plami — ilova varaqlarida.", 2.2, rang=MATN2)


def _dalil_varaq(v, m):
    """Ilova: muhrlangan dalil to'plami."""
    c = v.c
    v.yangi()
    v.y = Y1 - 4
    matn(c, X0, v.y, f"Ilova. {m['raqam']} dalolatnomasiga muhrlangan dalil to'plami", 4.0, FB)
    v.y -= 3
    if m["kamchiliklar"]:
        v.satrlar(f"DALIL TO'PLAMI TO'LIQ EMAS — komissiya quyidagilarni ko'rishi kerak:", 3.0, FB, rang=KAM_RANG)
        for i, s in enumerate(m["kamchiliklar"], 1):
            v.satrlar(f"{i}) {s}", 2.6, rang=KAM_RANG, x=X0 + 3)
    else:
        v.satrlar("DALIL TO'PLAMI TO'LIQ: muhrlangan o'lchovlar, sifat va tasdiq chegarada.", 3.0, FB, rang=TOLIQ_RANG)
    for s in m["ogohlantirishlar"]:
        v.satrlar(f"· {s}", 2.4, rang=MATN2, x=X0 + 3)

    v.bolim("A. Ko'rikka taqdim etilgan ishlar (o'lchangan)")
    tq = (m.get("tasdiq") or {}).get("liniyalar") or {}
    v.jadval([("Liniya", 14, "c"), ("Ish", 58, "l"), ("Uzunlik, m", 20, "r"), ("Chuqurlik, m", 24, "c"),
              ("RASMIY / SKAN / PAST", 34, "c"), ("RTK tasdiq (T-031)", 30, "c")],
             [[f"#{l['id']}", _ish_nomi(l), _uzunlik(l["uzunlik"]),
               _chuqurlik(l["yigindi"]["chuqurlik"]) or "—",
               " / ".join(str(l["yigindi"]["sifat"][s]) for s in ("RASMIY", "SKAN", "PAST")),
               (ijro.tasdiq_mod.HOLAT_NOMI.get((tq.get(l["id"]) or tq.get(str(l["id"])) or {}).get("holat"), "kerak emas")
                if l["yigindi"]["sifat"]["SKAN"] else "kerak emas (RTK)")]
              for l in m["liniyalar"]])

    v.bolim("B. O'lchov davri — ish ochiq turgan paytda (ShNK 3.01.03-24, 279, 390-bandlar)")
    od = m.get("olchov_davri")
    v.satrlar(f"Birinchi o'lchov {tsh(od[0])}, oxirgi o'lchov {tsh(od[1])} (Toshkent vaqti). Dalolatnoma {ijro.sana_uz(m['kirish']['sana'])} "
              "sanasida; 28-band bo'yicha navbatdagi ishlar boshlanishidan oldin tuziladi." if od else
              "O'lchov vaqti yozilmagan.", 2.7)

    v.bolim("C. Raqamli muhrlar (K-05: qurilma imzosi → fayl xeshlari → jurnal zanjiri)")
    mh = m.get("muhrlar") or []
    if mh:
        v.jadval([("Muhr", 16, "c"), ("Sana", 34, "l"), ("Holat", 30, "c"), ("Yozuvlar", 20, "r"), ("Zanjir boshi (SHA-256)", 80, "l")],
                 [[f"#{x['id']}", tsh(x["yaratilgan"]), x["holat"], str(x.get("yozuv_soni") or "—"), (x.get("zanjir_boshi") or "—")[:40] + "…"]
                  for x in mh])
    else:
        v.satrlar("Muhr yo'q: ma'lumot qo'lda yoki API orqali kiritilgan.", 2.7, rang=KAM_RANG)

    v.bolim("D. Mustaqil qayta hisob (data markazda telefon bilan bir xil yadro)")
    th = [t for t in (m.get("tahlillar") or []) if (t.get("tur") or "muhr") == "muhr"]
    if th:
        v.jadval([("Tahlil", 16, "c"), ("Muhr", 16, "c"), ("Holat", 22, "c"), ("Xulosa", 24, "c"), ("Quvur", 16, "r"),
                  ("O'q farqi, m", 26, "r"), ("Tugagan", 60, "l")],
                 [[f"#{t['id']}", f"#{t['muhr_id']}" if t.get("muhr_id") else "—", t["holat"], t.get("xulosa") or "—",
                   str(t.get("quvur_soni") if t.get("quvur_soni") is not None else "—"), son(t.get("oq_farqi_maks_m"), 3),
                   tsh(t.get("tugagan"))] for t in th])
    else:
        v.satrlar("Qayta hisob o'tkazilmagan.", 2.7)

    v.bolim("E. Ijro s'yomkasi hujjati (ГОСТ Р 51872-2024)")
    ih = m.get("ijro_hujjat")
    if ih:
        x = ih.get("xulosa") or {}
        v.satrlar(f"{ih['raqam']} · {tsh(ih.get('yaratilgan'))} · " +
                  ("TOPSHIRISHGA YAROQLI" if x.get("yaroqli") else f"topshirishga yaroqsiz ({x.get('sabablar_soni', 0)} ta sabab hujjatda)")
                  + f" · PDF SHA-256 {str(ih.get('sha256'))[:16]}…", 2.7)
    else:
        v.satrlar("Hali tuzilmagan.", 2.7)

    rasmlar = (m.get("rasmlar") or [])[:MAKS_RASM]
    v.bolim(f"F. Muhrlangan rasmlar ({len(m.get('rasmlar') or [])} ta" + (f", birinchi {MAKS_RASM} tasi" if len(m.get('rasmlar') or []) > MAKS_RASM else "") + ")")
    if not rasmlar:
        v.satrlar("Muhr jurnalida xeshi bor rasm yuklanmagan.", 2.7)
        return
    v.satrlar("Har rasm baytlari muhr jurnalidagi kalit kadr xeshi bilan bir xil — o'zgartirilmagan holda joylangan.", 2.3, rang=MATN2)
    w, h, ox = 86.0, 64.5, 8.0
    for i, r in enumerate(rasmlar):
        if i % 2 == 0:
            v.joy(h + 9)
            v.y -= h + 1
        x = X0 + (i % 2) * (w + ox)
        try:
            img = ImageReader(io.BytesIO(r["baytlar"]))
            iw, ihh = img.getSize()
            s = min(w / iw, h / ihh)
            c.drawImage(img, x + (w - iw * s) / 2, v.y + (h - ihh * s) / 2, iw * s, ihh * s)
        except Exception:  # noqa: BLE001 — buzuq rasm hujjatni to'xtatmasin
            matn(c, x + w / 2, v.y + h / 2, "rasm o'qilmadi", 2.6, tekis="c", rang=KAM_RANG)
        c.setStrokeColor(HexColor(CHIZIQ))
        c.setLineWidth(0.2)
        c.rect(x, v.y, w, h, stroke=1, fill=0)
        izoh = (f"muhr #{r['muhr_id']} · kadr #{r.get('kadr')} · {r.get('sifat') or '—'}"
                + (f" · RTK {r['rtk']}" if r.get("rtk") else "") + (f" σH {son(r['sigma_h_sm'], 1)} sm" if r.get("sigma_h_sm") is not None else ""))
        matn(c, x, v.y - 3.0, izoh, 2.1, rang=MATN2, kenglik=w)
        matn(c, x, v.y - 5.6, f"SHA-256 {r['sha256'][:32]}…", 1.9, rang=MATN2, kenglik=w)
        if i % 2 == 1 or i == len(rasmlar) - 1:
            v.y -= 8


def pdf(m):
    """(PDF baytlari, varaqlar soni). Ikki o'tish: birinchisi varaqlarni sanaydi."""
    ijro._shrift()
    N = None
    for _ in range(2):
        buf = io.BytesIO()
        c = canvas.Canvas(buf, pagesize=A4, pageCompression=1)
        c.setTitle(f"Yopiq ishlar dalolatnomasi {m['raqam']}: {m['obyekt']['nomi']}")
        c.setAuthor("TRACE4D")
        c.setSubject(f"Yopiq ishlar dalolatnomasi ({SHAKL}) va muhrlangan dalil to'plami")
        c.setCreator("TRACE4D yopiq ishlar dalolatnomasi")
        c.setKeywords([m["raqam"], "yopiq ishlar dalolatnomasi", SHAKL])
        v = _Varaq(c, m, N)
        _shakl_varaq(v, m)
        _dalil_varaq(v, m)
        v._pastki()
        c.restoreState()
        c.showPage()
        c.save()
        N = v.k
    return buf.getvalue(), N


def tekshirish_xulosasi(m, N):
    """/t/ sahifasi uchun (koordinata va shaxs ismlarisiz)."""
    o = m["obyekt"]
    od = m.get("olchov_davri")
    return {"tur": "yopiq", "obyekt": o["nomi"], "pudratchi": o.get("pudratchi") or "", "order": o.get("order_raqami") or "",
            "order_sana": o.get("order_sana") or "", "sana": ijro.sana_uz(m["kirish"]["sana"]), "varaqlar": N,
            "liniyalar": len(m["liniyalar"]), "uzunlik_m": round(sum(l["uzunlik"] for l in m["liniyalar"]), 2),
            "tarmoqlar": sorted({l["turi"] for l in m["liniyalar"]}),
            "muhrlar": sum(1 for x in m.get("muhrlar") or [] if x["holat"] == "TASDIQLANGAN"),
            "rasmlar": len(m.get("rasmlar") or []), "olchov_davri": list(od) if od else None,
            "toliq": not m["kamchiliklar"], "kamchiliklar_soni": len(m["kamchiliklar"]),
            "ijro_hujjat": (m.get("ijro_hujjat") or {}).get("raqam")}
