"""T1: quduq, zadvijka, burilish va ulanishdagi QR-belgilar — plastinka varag'i (A4, 8 yorliq) va belgi sahifasi hisoblari.

Plastinka joyida turadi: QR telefon kamerasi bilan /q/<kod> ni ochadi. Kirishsiz sahifada faqat belgi, tarmoq turi, egasi va
ogohlantirish; to'liq ma'lumot (chuqurlik, atrofdagi tarmoqlar) — portal sessiyasi bilan (yerosti_ochiq.belgi_sahifasi).
"""
import io
import math

from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

import yerosti_ijro as ijro
from yerosti_dalolatnoma import TARMOQ_ISHI, _qr
from yerosti_ijro import F, FB, MATN, MATN2, MM, matn

YORLIQ_W, YORLIQ_H = 90.0, 65.0
CHAP, PAST, ORALIQ = 10.0, 11.0, 5.0      # 10 + 90 + 10 + 90 + 10 = 210; 11 + 4·65 + 3·5 + 11 = 297
QR_O = 42.0                               # tashqarida 0,5–1 m dan o'qilishi uchun ≥ 40 mm


def egasi(belgi, liniya, obyekt):
    """Tarmoq egasi: liniya atributi (KU-02), bo'lmasa obyekt tarmoq egasi, bo'lmasa buyurtmachi."""
    return ((liniya or {}).get("egasi") or (obyekt or {}).get("tarmoq_egasi") or (obyekt or {}).get("buyurtmachi") or "").strip()


def tarmoq_nomi(turi):
    return TARMOQ_ISHI.get(turi, turi or "tarmoq").replace(" quvuri", "").replace(" tarmog'i", " tarmog'i")


def _yorliq(c, x, y, b, liniya, obyekt, url):
    import yerosti_baza as baza
    rang = ijro.TARMOQ.get((liniya or {}).get("turi"), ("#334155", "#334155"))[1]
    # kesish chizig'i
    c.setStrokeColor(HexColor("#9AA5B1"))
    c.setLineWidth(0.2)
    c.setDash([1.2, 1.2], 0)
    c.roundRect(x, y, YORLIQ_W, YORLIQ_H, 3, stroke=1, fill=0)
    c.setDash([], 0)
    # yuqori tasma — tarmoq rangi
    c.setFillColor(HexColor(rang))
    c.roundRect(x, y + YORLIQ_H - 10, YORLIQ_W, 10, 3, stroke=0, fill=1)
    c.rect(x, y + YORLIQ_H - 10, YORLIQ_W, 4, stroke=0, fill=1)
    matn(c, x + 4, y + YORLIQ_H - 6.6, "YER OSTI TARMOG'I · TRACE4D", 3.0, FB, rang="#FFFFFF")
    # chap qism: raqam, turi, egasi, aloqa
    qx = x + YORLIQ_W - QR_O - 3
    matn(c, x + 4, y + YORLIQ_H - 20, b["raqam"], 7.5, FB, kenglik=qx - x - 6)
    matn(c, x + 4, y + YORLIQ_H - 27, f"{baza.BELGI_TURLARI.get(b['tur'], b['tur'])} · {tarmoq_nomi((liniya or {}).get('turi'))}", 3.2,
         kenglik=qx - x - 6)
    if liniya:
        matn(c, x + 4, y + YORLIQ_H - 32, f"Ø{liniya['diametr_mm']}" + (f" {liniya['material']}" if liniya.get("material") else ""), 3.0,
             rang=MATN2, kenglik=qx - x - 6)
    eg = egasi(b, liniya, obyekt)
    yy = y + YORLIQ_H - 39
    for s in ijro._qatorlar(f"Egasi: {eg or '—'}", qx - x - 6, 2.8)[:2]:
        matn(c, x + 4, yy, s, 2.8)
        yy -= 3.8
    if b.get("aloqa"):
        matn(c, x + 4, yy, f"Aloqa: {b['aloqa']}", 3.0, FB, kenglik=qx - x - 6)
    # pastki ogohlantirish (ikki qatorgacha) va ko'rsatma
    ogoh = ijro._qatorlar("Qazishdan oldin tarmoq egasiga murojaat qiling.", qx - x - 6, 2.5)[:2]
    for i, q in enumerate(ogoh):
        matn(c, x + 4, y + 8.2 + (len(ogoh) - 1 - i) * 3.3, q, 2.5, FB, rang="#9A3412")
    matn(c, x + 4, y + 3.8, "QR ni telefon kamerasi bilan skanerlang", 2.2, rang=MATN2, kenglik=qx - x - 6)
    # o'ng qism: QR va qisqa manzil
    _qr(c, url, qx, y + 6, QR_O)
    matn(c, qx + QR_O / 2, y + 2.6, url.split("//", 1)[-1], 1.7, tekis="c", rang=MATN2, kenglik=QR_O + 2)


def plastinka_pdf(belgilar, url_asos):
    """T1-4: A4 varaqlarda 8 tadan yorliq. `belgilar` — [(belgi, liniya, obyekt)], `url_asos` — https://xost."""
    import yerosti_ijro as _i
    _i._shrift()
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4, pageCompression=1)
    c.setTitle("TRACE4D QR-belgilar plastinkasi")
    c.setAuthor("TRACE4D")
    c.setSubject("Quduq, zadvijka va burilishdagi QR-belgilar (T1)")
    for k in range(0, len(belgilar), 8):
        c.saveState()
        c.scale(MM, MM)
        for j, (b, liniya, obyekt) in enumerate(belgilar[k:k + 8]):
            ust, qator = j % 2, j // 2
            x = CHAP + ust * (YORLIQ_W + ORALIQ * 2)
            y = 297.0 - PAST - (qator + 1) * YORLIQ_H - qator * ORALIQ
            _yorliq(c, x, y, b, liniya, obyekt, f"{url_asos}/q/{b['kod']}")
        c.restoreState()
        c.showPage()
    c.save()
    return buf.getvalue()


def _xy(lat, lon, lat0, lon0):
    return ((lon - lon0) * 111_320.0 * math.cos(math.radians(lat0)), (lat - lat0) * 110_540.0)


def eng_yaqin(lat, lon, nuqtalar):
    """Nuqtadan poliliniyagacha eng yaqin masofa (m) va o'sha joydagi chuqurlik (chiziqli interpolyatsiya)."""
    eng = (math.inf, None)
    p = [(_xy(n["lat"], n["lon"], lat, lon), n.get("chuqurlik_m")) for n in nuqtalar]
    if len(p) == 1:
        (x, y), ch = p[0]
        return math.hypot(x, y), ch
    for (a, ca), (b, cb) in zip(p, p[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        l2 = dx * dx + dy * dy
        u = 0.0 if l2 == 0 else max(0.0, min(1.0, -(a[0] * dx + a[1] * dy) / l2))
        d = math.hypot(a[0] + u * dx, a[1] + u * dy)
        if d < eng[0]:
            ch = ca if cb is None else (cb if ca is None else ca + (cb - ca) * u)
            eng = (d, ch)
    return eng


def atrofdagilar(b, radius=30.0):
    """T1-3: belgi atrofidagi barcha amaldagi tarmoqlar (hamma obyekt va pudratchilardan) — eng yaqin masofa bo'yicha."""
    import yerosti_baza as baza
    natija = []
    for l in baza.atrofdagi(b["lat"], b["lon"], radius):
        d, ch = eng_yaqin(b["lat"], b["lon"], l["nuqtalar"])
        if d <= radius:
            natija.append(dict(l, masofa_m=d, chuqurlik_shu_yerda=ch))
    natija.sort(key=lambda x: x["masofa_m"])
    return natija
