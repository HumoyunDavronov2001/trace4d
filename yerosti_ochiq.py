"""YEROSTI — kirishsiz ochiladigan sahifalar (TALABLAR 14).

/t/<kod>   — ijro hujjatining haqiqiyligi (IH-08): raqam, obyekt, sana, PDF xeshi, muhr va qayta hisob holati.
             KOORDINATA YO'Q (muhim infratuzilma) — faqat hujjat yaratilganda saqlangan qisqa xulosa.
/u/<token> — muddatli ulashish (UL-02): faqat bitta obyekt, o'qish uchun.
Hamma qiymat html.escape dan o'tadi; skript faqat /static dan (CSP script-src 'self').
"""
import html
from datetime import datetime, timedelta, timezone

ULASH_NOMI = {"amal": "amalda", "bekor": "bekor qilingan", "muddati_tugagan": "muddati tugagan"}


def _e(x):
    return html.escape("" if x is None else str(x), quote=True)


def _son(x, n=1):
    return "—" if x is None else f"{x:.{n}f}".replace(".", ",")


TOSHKENT = timezone(timedelta(hours=5))


def _sana(iso):
    """Server vaqti UTC (ISO) → Toshkent vaqti: '2026-10-02T20:26:00+00:00' → '03.10.2026 01:26'."""
    if not iso:
        return "—"
    try:
        d = datetime.fromisoformat(str(iso))
    except ValueError:
        return str(iso)
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.astimezone(TOSHKENT).strftime("%d.%m.%Y %H:%M")


def _order(o):
    """ShN-01: qazish orderi «raqam, DD.MM.YYYY» — yerosti_ijro.order_matn bilan bir xil shakl (bu modul ijro ni yuklamaydi)."""
    r = str((o or {}).get("order_raqami") or "").strip()
    s = str((o or {}).get("order_sana") or "").strip()
    if len(s) == 10 and s[4] == "-" and s[7] == "-":
        s = f"{s[8:10]}.{s[5:7]}.{s[:4]}"
    if not r and not s:
        return ""
    return (r or "raqam yo'q") + ", " + (s or "sana yo'q")


def qobiq(sarlavha, izoh, tana, skript=None):
    return (
        "<!doctype html>\n<html lang=\"uz\">\n<head>\n<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        "<meta name=\"robots\" content=\"noindex, nofollow\">\n<meta name=\"referrer\" content=\"no-referrer\">\n"
        f"<title>{_e(sarlavha)} — TRACE4D</title>\n"
        "<link rel=\"icon\" href=\"/static/belgi.svg\" type=\"image/svg+xml\">\n"
        "<link rel=\"stylesheet\" href=\"/static/tokenlar.css\">\n<link rel=\"stylesheet\" href=\"/static/shrift.css\">\n"
        "<link rel=\"stylesheet\" href=\"/static/ochiq.css\">\n"
        "</head>\n<body>\n"
        f"<header class=\"o-bosh\"><span class=\"o-brend\">TRACE<em>4D</em></span><span class=\"o-bosh-izoh\">{_e(izoh)}</span></header>\n"
        f"<main class=\"o-asosiy\">\n{tana}\n</main>\n"
        "<footer class=\"o-oxir\">TRACE4D · yer osti muhandislik tarmoqlarining raqamli reestri · vaqt: Toshkent (UTC+5)</footer>\n"
        + (f"<script src=\"/static/{skript}\"></script>\n" if skript else "")
        + "</body>\n</html>\n")


def _qatorlar(juftlar):
    return "".join(f"<dt>{_e(a)}</dt><dd>{b}</dd>" for a, b in juftlar)


def _tasdiq_matn(t):
    """IH-08: /t/ sahifasida tasdiq holati — faqat sanoq (koordinata yo'q)."""
    if not t:
        return "hisoblanmagan (eski hujjat)"
    if not t.get("kerak"):
        return "skan liniyalari yo'q (barcha nuqtalar RTK)"
    return (f"{t.get('tasdiqlangan', 0)} / {t['kerak']} skan liniyasi RTK bilan tasdiqlangan · {t.get('olchovlar', 0)} ta tasdiq o'lchovi"
            + (f" · FARQ: {t['farq']}" if t.get("farq") else ""))


def _hujjat_banner(h):
    if h["holat"] == "bekor":
        return (f"<section class=\"o-holat o-holat-bekor\" role=\"status\"><b>Hujjat bekor qilingan</b>"
                f"<span>{_e(_sana(h.get('bekor_vaqt')))} · sabab: {_e(h.get('bekor_sabab') or '—')}</span></section>")
    return ("<section class=\"o-holat o-holat-amal\" role=\"status\"><b>Hujjat haqiqiy va amalda</b>"
            "<span>TRACE4D reestrida shu raqam va xesh bilan ro'yxatdan o'tgan</span></section>")


def _xesh_tekshiruv(h):
    return (f"<section class=\"o-karta\" id=\"xesh-tekshir\" data-sha256=\"{_e(h.get('sha256'))}\">"
            "<h2>Qo'lingizdagi PDF shu hujjatmi?</h2>"
            "<p>Faylni tanlang: xesh brauzeringizda hisoblanadi, fayl serverga yuborilmaydi.</p>"
            "<label class=\"o-fayl\"><input type=\"file\" id=\"xesh-fayl\" accept=\"application/pdf\"> PDF faylni tanlash</label>"
            "<p id=\"xesh-natija\" class=\"o-natija\" aria-live=\"polite\"></p>"
            "<p class=\"o-kichik\">Buyruq satrida: <code>sha256sum fayl.pdf</code> (Windows: <code>certutil -hashfile fayl.pdf "
            "SHA256</code>) — natija yuqoridagi xesh bilan bir xil bo'lishi kerak.</p></section>\n")


def dalolatnoma_sahifasi(h, obyekt):
    """ShN-05: yopiq ishlar dalolatnomasini tekshirish — koordinata va shaxs ismlarisiz."""
    x = h.get("xulosa") or {}
    od = x.get("olchov_davri")
    juftlar = [
        ("Hujjat turi", "Yopiq ishlar dalolatnomasi (ShNQ 3.01.01-22, 6-ilova) va muhrlangan dalil to'plami"),
        ("Obyekt", _e(x.get("obyekt") or (obyekt or {}).get("nomi"))),
        ("Pudratchi", _e(x.get("pudratchi") or "—")),
        ("Order (ruxsatnoma)", _e(_order({"order_raqami": x.get("order"), "order_sana": x.get("order_sana")}) or "—")),
        ("Dalolatnoma sanasi", _e(x.get("sana") or _sana(h.get("yaratilgan")))),
        ("Varaqlar", _e(h.get("varaqlar"))),
        ("Ko'rikka taqdim etilgan ishlar", _e(", ".join(x.get("tarmoqlar") or []) or "—")
         + f" · {_e(x.get('liniyalar', 0))} liniya · {_e(_son(x.get('uzunlik_m'), 1))} m"),
        ("O'lchov davri (ish ochiq paytda)", _e(f"{_sana(od[0])} – {_sana(od[1])}") if od else "yozilmagan"),
        ("Raqamli muhrlar", _e(f"{x.get('muhrlar', 0)} ta TASDIQLANGAN")),
        ("Muhrlangan rasmlar", _e(x.get("rasmlar", 0))),
        ("Ijro s'yomkasi hujjati", _e(x.get("ijro_hujjat") or "tuzilmagan")),
        ("Dalil to'plami", "<span class=\"o-nishon o-rasmiy\">to'liq</span>" if x.get("toliq") else
         f"<span class=\"o-nishon o-past\">to'liq emas</span> · {_e(x.get('kamchiliklar_soni', 0))} ta kamchilik hujjat ilovasida"),
        ("PDF SHA-256", f"<code class=\"o-xesh\">{_e(h.get('sha256'))}</code>"),
    ]
    tana = (f"{_hujjat_banner(h)}\n<h1 class=\"o-sarlavha\">{_e(h.get('raqam'))}</h1>\n"
            "<p class=\"o-izoh\">Quyidagi ma'lumot dalolatnoma tuzilgan paytda saqlangan. Komissiya a'zolarining ismlari bu "
            "sahifada ko'rsatilmaydi.</p>\n"
            f"<dl class=\"o-maydon\">{_qatorlar(juftlar)}</dl>\n{_xesh_tekshiruv(h)}"
            "<p class=\"o-kichik\">Muhim infratuzilma: bu sahifada koordinatalar va chizma ko'rsatilmaydi. Dalolatnoma komissiya "
            "xulosasi va imzolari bilan kuchga ega.</p>")
    return qobiq(f"Dalolatnoma {h.get('raqam')}", "Yopiq ishlar dalolatnomasini tekshirish", tana, "tekshir.js")


def muvofiqlik_sahifasi(h, obyekt):
    """T3: loyiha–ijro muvofiqligi hisobotini tekshirish — koordinatasiz, faqat sanoqlar."""
    x = h.get("xulosa") or {}
    juftlar = [
        ("Hujjat turi", "Loyiha–ijro muvofiqligi hisoboti (inspeksiyaga tayyor ro'yxat)"),
        ("Obyekt", _e(x.get("obyekt") or (obyekt or {}).get("nomi"))),
        ("Pudratchi", _e(x.get("pudratchi") or "—")),
        ("Hisobot sanasi", _e(x.get("sana") or _sana(h.get("yaratilgan")))),
        ("Loyiha fayli", _e(x.get("loyiha") or "—")),
        ("Liniyalar", _e(x.get("liniyalar", 0))),
        ("Me'yordan tashqari joylar", _e(x.get("tashqari", 0))),
        ("Noaniq (o'lchov aniqligi yetarli emas)", _e(x.get("noaniq", 0))),
        ("Qurilmagan (loyihada bor, ijroda yo'q)", _e(f"{_son(x.get('qurilmagan_m'), 1)} m")),
        ("PDF SHA-256", f"<code class=\"o-xesh\">{_e(h.get('sha256'))}</code>"),
    ]
    tana = (f"{_hujjat_banner(h)}\n<h1 class=\"o-sarlavha\">{_e(h.get('raqam'))}</h1>\n"
            "<p class=\"o-izoh\">Quyidagi ma'lumot hisobot tuzilgan paytda saqlangan.</p>\n"
            f"<dl class=\"o-maydon\">{_qatorlar(juftlar)}</dl>\n{_xesh_tekshiruv(h)}"
            "<p class=\"o-kichik\">Muhim infratuzilma: bu sahifada koordinatalar va chizma ko'rsatilmaydi.</p>")
    return qobiq(f"Hisobot {h.get('raqam')}", "Loyiha–ijro muvofiqligi hisobotini tekshirish", tana, "tekshir.js")


def tekshirish_sahifasi(h, obyekt):
    """IH-08. `h` — hujjat qatori (xulosa ichida), `obyekt` — joriy obyekt (faqat nomi uchun)."""
    x = h.get("xulosa") or {}
    if (h.get("tur") or x.get("tur")) == "yopiq":
        return dalolatnoma_sahifasi(h, obyekt)
    if (h.get("tur") or x.get("tur")) == "muvofiqlik":
        return muvofiqlik_sahifasi(h, obyekt)
    if h["holat"] == "bekor":
        banner = (f"<section class=\"o-holat o-holat-bekor\" role=\"status\"><b>Hujjat bekor qilingan</b>"
                  f"<span>{_e(_sana(h.get('bekor_vaqt')))} · sabab: {_e(h.get('bekor_sabab') or '—')}</span></section>")
    else:
        banner = ("<section class=\"o-holat o-holat-amal\" role=\"status\"><b>Hujjat haqiqiy va amalda</b>"
                  "<span>TRACE4D reestrida shu raqam va xesh bilan ro'yxatdan o'tgan</span></section>")
    sif = x.get("nuqtalar") or {}
    muhr = x.get("muhr") or {}
    tahlil = x.get("tahlil") or {}
    juftlar = [
        ("Obyekt", _e(x.get("obyekt") or (obyekt or {}).get("nomi"))),
        ("Pudratchi", _e(x.get("pudratchi") or "—")),
        ("Order (ruxsatnoma)", _e(_order({"order_raqami": x.get("order"), "order_sana": x.get("order_sana")}) or "—")),
        ("Hujjat sanasi", _e(x.get("sana") or _sana(h.get("yaratilgan")))),
        ("Varaqlar", _e(h.get("varaqlar"))),
        ("Tarmoqlar", _e(", ".join(x.get("tarmoqlar") or []) or "—")
         + f" · {_e(x.get('liniyalar', 0))} liniya · {_e(_son(x.get('uzunlik_m'), 1))} m"),
        ("Nuqtalar sifati", " · ".join(f"<span class=\"o-nishon o-{k.lower()}\">{_e(k)} {_e(sif.get(k, 0))}</span>"
                                       for k in ("RASMIY", "SKAN", "PAST"))),
        ("Quvur tasdig'i (T-031)", _e(_tasdiq_matn(x.get("tasdiq")))),
        ("Raqamli muhr", " · ".join(f"{_e(k)} {_e(v)}" for k, v in sorted(muhr.items())) or
         "muhr yo'q (qurilma imzosi bilan tasdiqlanmagan)"),
        ("Mustaqil qayta hisob", " · ".join(f"{_e(k)} {_e(v)}" for k, v in sorted(tahlil.items())) or "o'tkazilmagan"),
        ("Loyiha bilan solishtirish", "bor" if x.get("loyiha") else "loyiha kiritilmagan"),
        ("Koordinata va balandlik tizimi", _e(f"{x['tizim']}; {x.get('balandlik') or ''}" if x.get("tizim") else "—")),
        ("Topshirishga yaroqlilik", ("—" if "yaroqli" not in x else
                                     "<span class=\"o-nishon o-rasmiy\">yaroqli</span>" if x["yaroqli"] else
                                     f"<span class=\"o-nishon o-past\">yaroqsiz</span> · {_e(x.get('sabablar_soni', 0))} "
                                     "ta sabab hujjatning «Sifat» varag'ida")),
        ("PDF SHA-256", f"<code class=\"o-xesh\">{_e(h.get('sha256'))}</code>"),
    ]
    tana = (
        f"{banner}\n<h1 class=\"o-sarlavha\">{_e(h.get('raqam'))}</h1>\n"
        "<p class=\"o-izoh\">Ijro s'yomkasi hujjati (ГОСТ Р 51872-2024). Quyidagi ma'lumot hujjat yaratilgan paytda "
        "saqlangan.</p>\n"
        f"<dl class=\"o-maydon\">{_qatorlar(juftlar)}</dl>\n"
        f"<section class=\"o-karta\" id=\"xesh-tekshir\" data-sha256=\"{_e(h.get('sha256'))}\">"
        "<h2>Qo'lingizdagi PDF shu hujjatmi?</h2>"
        "<p>Faylni tanlang: xesh brauzeringizda hisoblanadi, fayl serverga yuborilmaydi.</p>"
        "<label class=\"o-fayl\"><input type=\"file\" id=\"xesh-fayl\" accept=\"application/pdf\"> PDF faylni tanlash</label>"
        "<p id=\"xesh-natija\" class=\"o-natija\" aria-live=\"polite\"></p>"
        "<p class=\"o-kichik\">Buyruq satrida: <code>sha256sum fayl.pdf</code> (Windows: <code>certutil -hashfile fayl.pdf "
        "SHA256</code>) — natija yuqoridagi xesh bilan bir xil bo'lishi kerak.</p></section>\n"
        "<p class=\"o-kichik\">Muhim infratuzilma: bu sahifada koordinatalar va chizma ko'rsatilmaydi. Hujjat geodezist "
        "imzosi bilan rasmiy kuchga ega.</p>")
    return qobiq(f"Hujjat {h.get('raqam')}", "Ijro hujjatini tekshirish", tana, "tekshir.js")


def topilmadi_sahifasi(nima="Hujjat"):
    tana = (f"<section class=\"o-holat o-holat-bekor\" role=\"status\"><b>{_e(nima)} topilmadi</b>"
            "<span>Havola noto'g'ri yoki to'liq ko'chirilmagan. QR kodni qayta skanerlang.</span></section>")
    return qobiq(f"{nima} topilmadi", "Tekshirish", tana)


def ulash_yopiq_sahifasi(u):
    """UL-03: muddat tugagan yoki bekor qilingan havola — 410."""
    sabab = "muddati tugagan" if u["holat"] == "muddati_tugagan" else "bekor qilingan"
    tana = (f"<section class=\"o-holat o-holat-bekor\" role=\"status\"><b>Havola {sabab}</b>"
            f"<span>Obyekt egasidan yangi havola so'rang.</span></section>")
    return qobiq("Havola yopiq", "Ulashilgan obyekt", tana)


def ulash_sahifasi(token, u, obyekt, liniyalar, hujjatlar, tahlillar, loyiha, tasdiq=None):
    """UL-02: bitta obyekt; hujjat PDF, DXF, CSV, 3D (o'qish uchun). Boshqa obyekt yoki ro'yxat yo'q."""
    b = f"/u/{_e(token)}"
    juftlar = [("Manzil", _e(obyekt.get("manzil") or "—")), ("Buyurtmachi", _e(obyekt.get("buyurtmachi") or "—")),
               ("Pudratchi", _e(obyekt.get("pudratchi") or "—")), ("Order (ruxsatnoma)", _e(_order(obyekt) or "—")),
               ("Havola kimga", _e(u["nomi"])), ("Amal qiladi", _e(_sana(u["muddati"])) + " gacha")]
    qator = []
    for l in liniyalar:
        qator.append(f"<tr><td>#{_e(l['id'])}</td><td>{_e(l['turi'])}</td><td>Ø{_e(l['diametr_mm'])}</td>"
                     f"<td>{_e(l.get('material') or '—')}</td><td class=\"o-son\">{_e(_son(l.get('uzunlik_m'), 1))}</td>"
                     f"<td class=\"o-son\">{_e(len(l['nuqtalar']))}</td>"
                     f"<td><span class=\"o-nishon o-{_e(l['sifat'].lower())}\">{_e(l['sifat'])}</span>"
                     + (" <span class=\"o-nishon o-rasmiy\">RTK tasdiq</span>" if (tasdiq or {}).get(l["id"]) == "tasdiqlangan"
                        else (" <span class=\"o-nishon o-past\">FARQ</span>" if (tasdiq or {}).get(l["id"]) == "farq" else ""))
                     + "</td></tr>")
    jadval = ("<table class=\"o-jadval\"><thead><tr><th>Liniya</th><th>Tarmoq</th><th>Diametr</th><th>Material</th>"
              "<th>Uzunlik, m</th><th>Nuqtalar</th><th>Sifat</th></tr></thead><tbody>" + "".join(qator) + "</tbody></table>"
              if qator else "<p class=\"o-izoh\">Obyektda hali liniya yo'q.</p>")
    hj = [f"<li><a href=\"{b}/hujjat/{_e(h['id'])}.pdf\">{_e(h['raqam'])}</a> · {_e(_sana(h['yaratilgan']))} · "
          f"{_e(h['varaqlar'])} varaq</li>" for h in hujjatlar if h["holat"] == "amal"]
    th = [f"<li><a href=\"{b}/3d?tahlil={_e(t['id'])}\">Skan #{_e(t['id'])} (muhr #{_e(t['muhr_id'])})</a> · "
          f"{_e(_sana(t.get('tugagan')))} · qayta hisob: {_e(t.get('xulosa') or t['holat'])}</li>"
          for t in tahlillar if t["holat"] == "tayyor" and t.get("korinish")]
    tana = (
        f"<h1 class=\"o-sarlavha\">{_e(obyekt['nomi'])}</h1>\n"
        "<p class=\"o-izoh\">Bu sahifa siz uchun muddatli ulashilgan: faqat shu obyekt, faqat o'qish uchun.</p>\n"
        f"<dl class=\"o-maydon\">{_qatorlar(juftlar)}</dl>\n"
        f"<section class=\"o-karta\"><h2>Tarmoqlar</h2>{jadval}</section>\n"
        "<section class=\"o-karta\"><h2>Ijro hujjati (PDF)</h2>"
        + (f"<ul class=\"o-royxat\">{''.join(hj)}</ul>" if hj else "<p class=\"o-izoh\">Hujjat hali yaratilmagan.</p>")
        + "</section>\n"
        "<section class=\"o-karta\"><h2>Chizma va katalog</h2>"
        + (f"<p class=\"o-tugmalar\"><a class=\"o-tugma\" href=\"{b}/chizma.dxf\">DXF ijro chizmasi</a>"
           f"<a class=\"o-tugma\" href=\"{b}/chizma.csv\">Koordinata katalogi (CSV)</a></p>"
           "<p class=\"o-kichik\">Koordinatalar WGS84 / UTM, balandlik WGS84 ellipsoid.</p>" if qator else
           "<p class=\"o-izoh\">Liniya yo'q.</p>")
        + (f"<p class=\"o-kichik\">Loyiha DXF: {_e(loyiha['fayl_nomi'])} (solishtirish hujjat va 3D da).</p>" if loyiha else "")
        + "</section>\n"
        "<section class=\"o-karta\"><h2>3D ko'rish</h2>"
        + (f"<ul class=\"o-royxat\">{''.join(th)}</ul>" if th else "<p class=\"o-izoh\">3D ko'rinish hali yo'q.</p>")
        + "</section>\n"
        "<p class=\"o-kichik\">Havolani boshqalarga uzatmang: unda kirish kaliti bor. Har ochilish qayd etiladi.</p>")
    return qobiq(obyekt["nomi"], "Ulashilgan obyekt", tana)


# ---------- T1: QR-belgi sahifasi ----------

_BELGI_TUR = {"quduq": "Quduq", "zadvijka": "Zadvijka", "burilish": "Burilish", "ulanish": "Ulanish", "boshqa": "Belgi"}
_TARMOQ = {"suv": "suv ta'minoti", "kanalizatsiya": "kanalizatsiya", "gaz": "gaz", "elektr": "elektr kabeli",
           "optika": "optik aloqa kabeli", "issiqlik": "issiqlik tarmog'i"}


def belgi_sahifasi(b, liniya, obyekt, egasi, toliq=False, atrof=None, ijro_hujjat=None):
    """T1-2/T1-3. `toliq=False` — kirishsiz: faqat belgi, tarmoq turi, egasi, aloqa va ogohlantirish (koordinata, chuqurlik,
    atrofdagi tarmoqlar yo'q). `toliq=True` — portal sessiyasi bilan: nuqta ma'lumoti va 30 m ichidagi tarmoqlar."""
    tarmoq = _TARMOQ.get((liniya or {}).get("turi"), (liniya or {}).get("turi") or "—")
    juftlar = [
        ("Belgi", _e(f"{_BELGI_TUR.get(b['tur'], b['tur'])} {b['raqam']}")),
        ("Tarmoq", _e(tarmoq + (f" · Ø{liniya['diametr_mm']}" if liniya and liniya.get("diametr_mm") else "")
                      + (f" {liniya['material']}" if liniya and liniya.get("material") else ""))),
        ("Tarmoq egasi", _e(egasi or "—")),
    ]
    if b.get("aloqa"):
        juftlar.append(("Aloqa", f"<a href=\"tel:{_e(''.join(ch for ch in b['aloqa'] if ch.isdigit() or ch == '+'))}\">{_e(b['aloqa'])}</a>"))
    ogoh = ("<section class=\"o-holat o-holat-bekor\" role=\"status\"><b>Bu joyda yer osti muhandislik tarmog'i bor</b>"
            "<span>Qazish va yer ishlarini faqat tarmoq egasi bilan kelishib boshlang.</span></section>")
    if not toliq:
        tana = (f"{ogoh}\n<h1 class=\"o-sarlavha\">{_e(b['raqam'])}</h1>\n<dl class=\"o-maydon\">{_qatorlar(juftlar)}</dl>\n"
                f"<p class=\"o-kichik\">Xodimlar uchun to'liq ma'lumot (chuqurlik va atrofdagi tarmoqlar): "
                f"<a href=\"/?keyin=/q/{_e(b['kod'])}\">tizimga kirish</a>. Muhim infratuzilma: bu sahifada koordinata va "
                "chizma ko'rsatilmaydi.</p>")
        return qobiq(f"Belgi {b['raqam']}", "Yer osti tarmog'i belgisi", tana)
    juftlar += [
        ("Obyekt", _e((obyekt or {}).get("nomi") or "—")),
        ("Liniya", _e(f"#{b['liniya_id']}" if b.get("liniya_id") else "—")
         + (f" · pikitaj {_son(b.get('pikitaj_m'), 2)} m" if b.get("pikitaj_m") is not None else "")),
        ("Chuqurlik (yer sirtidan quvur ustigacha)", _e(f"{_son(b.get('chuqurlik_m'), 2)} m" if b.get("chuqurlik_m") is not None else "o'lchanmagan")),
        ("Balandlik (quvur o'qi, ellipsoid)", _e(f"{_son(b.get('balandlik'), 3)} m" if b.get("balandlik") is not None else "—")),
        ("Koordinata (WGS-84)", _e(f"{b['lat']:.7f}, {b['lon']:.7f}")),
        ("Ijro hujjati", f"<a href=\"/api/v1/ijro-hujjat/{int(ijro_hujjat['id'])}.pdf\">{_e(ijro_hujjat['raqam'])}</a>" if ijro_hujjat else "tuzilmagan"),
        ("Skanerlangan", _e(f"{b.get('korishlar', 0)} marta")),
    ]
    qator = []
    for l in atrof or []:
        ch = l.get("chuqurlik_shu_yerda")
        shu = " <small>(shu belgi liniyasi)</small>" if l["id"] == b.get("liniya_id") else ""
        qator.append(f"<tr><td>{_e(_TARMOQ.get(l['turi'], l['turi']))}{shu}</td><td>Ø{_e(l['diametr_mm'])} {_e(l.get('material') or '')}</td>"
                     f"<td>{_e(_son(l['masofa_m'], 1))} m</td><td>{_e(_son(ch, 2) + ' m' if ch is not None else '—')}</td>"
                     f"<td>{_e(l.get('sifat') or '—')}</td><td>{_e(l.get('pudratchi') or '—')}</td></tr>")
    jadval = ("<table class=\"o-jadval\"><thead><tr><th>Tarmoq</th><th>Diametr</th><th>Masofa</th><th>Chuqurlik</th><th>Sifat</th>"
              "<th>Pudratchi</th></tr></thead><tbody>" + "".join(qator) + "</tbody></table>") if qator else \
        "<p class=\"o-kichik\">30 m ichida reestrda boshqa tarmoq yo'q (reestrda yo'q tarmoqlar bo'lishi mumkin).</p>"
    tana = (f"{ogoh}\n<h1 class=\"o-sarlavha\">{_e(b['raqam'])}</h1>\n<dl class=\"o-maydon\">{_qatorlar(juftlar)}</dl>\n"
            f"<section class=\"o-karta\"><h2>Atrofdagi tarmoqlar (30 m)</h2>{jadval}</section>\n"
            "<p class=\"o-kichik\">Masofa — belgidan tarmoq o'qigacha eng yaqin gorizontal masofa. Faqat TRACE4D reestridagi tarmoqlar.</p>")
    return qobiq(f"Belgi {b['raqam']}", "Yer osti tarmog'i belgisi — xodim ko'rinishi", tana)


def belgi_bekor_sahifasi(b):
    tana = (f"<section class=\"o-holat o-holat-bekor\" role=\"status\"><b>Belgi bekor qilingan</b>"
            f"<span>{_e(_sana(b.get('bekor_vaqt')))} · sabab: {_e(b.get('bekor_sabab') or '—')}</span></section>"
            "<p class=\"o-kichik\">Plastinka eskirgan. Tarmoq haqida tarmoq egasiga murojaat qiling.</p>")
    return qobiq("Belgi bekor qilingan", "Yer osti tarmog'i belgisi", tana)
