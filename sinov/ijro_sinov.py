"""YEROSTI — ijro hujjati sinovi (TALABLAR 14: IH-01…IH-08). Bazasiz: geometriya, DXF o'quvchi, PDF mazmuni, QR.

Sinov geometriyasi sun'iy (haqiqiy skan EMAS) va faqat vaqtinchalik papkaga yoziladi.
Ishga tushirish:  python3 sinov/ijro_sinov.py      (pdftotext, pdftoppm, OpenCV kerak)
"""
import json
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile

YEROSTI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, YEROSTI)
import yerosti_chizma as chizma  # noqa: E402
import yerosti_ijro as ijro  # noqa: E402
import yerosti_ijro_geo as geo  # noqa: E402
import yerosti_ochiq as ochiq  # noqa: E402

TMP = tempfile.mkdtemp(prefix="yerosti_ijro_")
natijalar = []


def tekshir(nom, shart, izoh=""):
    natijalar.append((nom, bool(shart)))
    print(("PASS " if shart else "FAIL ") + nom + (f"  [{izoh}]" if (izoh and not shart) else ""))


E0, N0, H0 = 362300.0, 4445250.0, 402.0


def nuqta(e, n, h, ch, sifat="RASMIY", manba="rtk", i=0):
    return {"id": i, "e": e, "n": n, "h": h, "chuqurlik": ch, "sifat": sifat, "manba": manba, "sigma_h_sm": 1.2,
            "rtk_holat": "FIX", "izoh": ""}


def liniya(lid, turi, d, mat, pts, sifat="RASMIY", manba="rtk"):
    return {"id": lid, "turi": turi, "diametr_mm": d, "material": mat, "sifat": sifat, "obyekt_nomi": "", "izoh": "",
            "versiya": 1, "nuqtalar": [nuqta(*p, sifat=sifat, manba=manba, i=lid * 1000 + i) for i, p in enumerate(pts)]}


def turlar(l):
    return [(p["turi"], round(p["stansiya"], 2)) for p in geo.xarakterli(l) if p["turi"] != "olchangan"]


try:
    # ---------- pikitaj ----------
    tekshir("pikitaj formati", [geo.pikitaj(s) for s in (0, 12.5, 99.999, 250.3)] ==
            ["PK0+00,00", "PK0+12,50", "PK1+00,00", "PK2+50,30"], str([geo.pikitaj(s) for s in (0, 12.5, 99.999, 250.3)]))

    # ---------- G.1.1: xarakterli nuqtalar ----------
    l = liniya(1, "suv", 160, "PE", [(E0, N0, H0 - 2, 1.5), (E0 + 130, N0, H0 - 2.65, 1.8)])
    x = geo.xarakterli(l)
    oraliq = [p for p in x if p["turi"] == "oraliq"]
    st = [p["stansiya"] for p in x]
    tekshir("130 m to'g'ri: 2 oraliq nuqta, hammasi hisoblangan, oralig'i ≤ 50 m",
            len(oraliq) == 2 and all(p["hisoblangan"] for p in oraliq) and max(b - a for a, b in zip(st, st[1:])) <= 50.0001,
            str(st))
    tekshir("oraliq nuqta balandligi va chuqurligi chiziqli",
            abs(oraliq[0]["h"] - (H0 - 2 - 0.65 / 3)) < 1e-9 and abs(oraliq[0]["chuqurlik"] - 1.6) < 1e-9, str(oraliq[0]))
    tekshir("usti = o'q + D/2, yer = usti + chuqurlik",
            abs(x[0]["usti"] - (H0 - 2 + 0.08)) < 1e-9 and abs(x[0]["yer"] - (H0 - 2 + 0.08 + 1.5)) < 1e-9)
    L = liniya(2, "suv", 160, "PE", [(E0, N0, H0, 1), (E0 + 30, N0, H0, 1), (E0 + 30, N0 + 30, H0, 1)])
    tekshir("L shakl: burchakda burilish", turlar(L) == [("bosh", 0), ("burilish", 30.0), ("oxir", 60.0)], str(turlar(L)))
    rnd = random.Random(7)
    zich = [(E0 + i * 0.5, N0 + rnd.gauss(0, 0.01), H0 - 2 - i * 0.5 * 0.004 + rnd.gauss(0, 0.003), 2.0) for i in range(121)]
    tekshir("zich skan (0,5 m; yon shovqin 1 sm, balandlik 3 mm): soxta burilish va nishab yo'q",
            turlar(liniya(3, "suv", 160, "PE", zich)) == [("bosh", 0), ("oxir", round(geo.stansiyalar(
                liniya(3, "suv", 160, "PE", zich)["nuqtalar"])[-1], 2))], str(turlar(liniya(3, "suv", 160, "PE", zich))))
    egik = []
    for i in range(81):
        s = i * 0.5
        if s <= 20:
            egik.append((E0 + s, N0, H0, 2.0))
        else:
            a = math.radians(20)
            egik.append((E0 + 20 + (s - 20) * math.cos(a), N0 + (s - 20) * math.sin(a), H0, 2.0))
    t = turlar(liniya(4, "suv", 160, "PE", egik))
    bur = [s for k, s in t if k == "burilish"]
    tekshir("zich skan, haqiqiy 20° egilish: bitta burilish, 1 m ichida", len(bur) == 1 and abs(bur[0] - 20) <= 1.0, str(t))
    nish = [(E0 + s, N0, H0 - (s * 0.01 if s <= 30 else 0.3 + (s - 30) * 0.03), 2.0) for s in range(0, 61, 5)]
    t = turlar(liniya(5, "kanalizatsiya", 200, "PVC", nish))
    tekshir("nishab 10 ‰ → 30 ‰ (RTK, har 5 m): nishab o'zgarish nuqtasi 30 m da", t == [("bosh", 0), ("nishab", 30.0),
                                                                                         ("oxir", 60.0)], str(t))
    zn = [(E0 + i * 0.5, N0, H0 - (i * 0.5 * 0.01 if i <= 60 else 0.3 + (i * 0.5 - 30) * 0.03) + rnd.gauss(0, 0.003), 2.0)
          for i in range(121)]
    t = turlar(liniya(5, "kanalizatsiya", 200, "PVC", zn))
    tekshir("zich skanda nishab 10 → 30 ‰: bitta nishab nuqtasi, 1 m ichida",
            [k for k, _ in t] == ["bosh", "nishab", "oxir"] and abs(t[1][1] - 30) <= 1.0, str(t))
    a = liniya(6, "suv", 160, "PE", [(E0, N0, H0, 1), (E0 + 20, N0, H0, 1)])
    b = liniya(7, "suv", 110, "PE", [(E0 + 20, N0, H0, 1), (E0 + 40, N0, H0, 1)])
    xa = geo.xarakterli(a, [(E0 + 20, N0, 110, "PE"), (E0 + 40, N0, 110, "PE")])
    tekshir("tutashuvda diametr o'zgarishi belgilanadi", xa[-1]["turi"] == "tutashuv" and xa[0]["turi"] == "bosh",
            str([p["turi"] for p in xa]))

    # ---------- IH-04: kesishuvlar ----------
    s1 = liniya(10, "suv", 160, "PE", [(E0, N0, H0 - 2.0, 1.5), (E0 + 40, N0, H0 - 2.0, 1.5)])
    g1 = liniya(11, "gaz", 110, "PE", [(E0 + 10, N0 - 20, H0 - 1.2, 1.0), (E0 + 10, N0 + 20, H0 - 1.2, 1.0)])
    k = geo.kesishuvlar(s1, [g1])
    tekshir("kesishuv: joyi, stansiyasi va vertikal oraliq = |Δh| − (r1 + r2)",
            len(k) == 1 and abs(k[0]["e"] - (E0 + 10)) < 1e-9 and abs(k[0]["stansiya"] - 10) < 1e-9
            and abs(k[0]["oraliq"] - (0.8 - 0.08 - 0.055)) < 1e-9 and k[0]["boshqa_ustida"] is True, str(k))
    t1 = liniya(12, "suv", 160, "PE", [(E0 + 40, N0, H0, 1), (E0 + 60, N0, H0, 1)])
    tekshir("uchma-uch tutashuv kesishuv emas", geo.kesishuvlar(s1, [t1]) == [])
    tarmoq_s = liniya(13, "suv", 110, "PE", [(E0 + 20, N0, H0, 1), (E0 + 20, N0 + 15, H0, 1)])
    tarmoq_e = liniya(14, "elektr", 50, "Cu", [(E0 + 25, N0, H0 - 0.5, 1), (E0 + 25, N0 + 15, H0 - 0.5, 1)])
    tekshir("bir xil turdagi tarmoqlanish (T) kesishuv emas", geo.kesishuvlar(s1, [tarmoq_s]) == [])
    tekshir("boshqa turdagi liniya uchi tegsa — kesishuv", len(geo.kesishuvlar(s1, [tarmoq_e])) == 1)
    par = liniya(15, "gaz", 110, "PE", [(E0, N0 + 3, H0, 1), (E0 + 40, N0 + 3, H0, 1)])
    tekshir("parallel liniya kesishmaydi", geo.kesishuvlar(s1, [par]) == [])
    ikki = liniya(16, "gaz", 110, "PE", [(E0 + 10, N0 - 5, H0, 1), (E0 + 10, N0, H0, 1), (E0 + 10, N0 + 5, H0, 1)])
    tekshir("kesishuv cho'qqiga to'g'ri kelsa bir marta sanaladi", len(geo.kesishuvlar(s1, [ikki])) == 1)

    # ---------- IH-04a: kesishuvda vertikal oraliq me'yori ----------
    tekshir("me'yor jadvali: quvur–quvur 0,2; suv–kanalizatsiya 0,4 (suv yuqorida); quvur–kabel 0,5; kabel–kabel 0,5",
            geo.kesishuv_meyori("gaz", "issiqlik")[0] == 0.2 and geo.kesishuv_meyori("suv", "kanalizatsiya")[:2] == (0.4, "suv_yuqorida")
            and geo.kesishuv_meyori("suv", "elektr")[0] == 0.5 and geo.kesishuv_meyori("elektr", "optika")[0] == 0.5)
    tekshir("gaz bilan kesishuv 0,665 m ≥ 0,2 — mos", k[0]["xulosa"] == "mos" and k[0]["meyor_m"] == 0.2, str(k[0]))
    kan = liniya(17, "kanalizatsiya", 200, "PVC", [(E0 + 20, N0 - 10, H0 - 2.3, 1.5), (E0 + 20, N0 + 10, H0 - 2.3, 1.5)])
    kk = geo.kesishuvlar(s1, [kan])[0]
    tekshir("suv kanalizatsiya ustida, oraliq 0,12 m < 0,4 — MOS EMAS (oraliq)", kk["xulosa"] == "MOS EMAS" and abs(kk["oraliq"] - 0.12) < 1e-9
            and "0.12 m < 0.4 m" in kk["izoh"] and "ostida" not in kk["izoh"], str(kk))
    kan2 = liniya(18, "kanalizatsiya", 200, "PVC", [(E0 + 20, N0 - 10, H0 - 1.5, 1.0), (E0 + 20, N0 + 10, H0 - 1.5, 1.0)])
    kk2 = geo.kesishuvlar(s1, [kan2])[0]
    tekshir("suv kanalizatsiya OSTIDA — MOS EMAS (yo'nalish sharti), kanalizatsiya tomonidan ham bir xil",
            kk2["xulosa"] == "MOS EMAS" and "ostida" in kk2["izoh"] and geo.kesishuvlar(kan2, [s1])[0]["xulosa"] == "MOS EMAS", str(kk2))
    kan3 = liniya(19, "kanalizatsiya", 200, "PVC", [(E0 + 20, N0 - 10, H0 - 2.7, 1.5), (E0 + 20, N0 + 10, H0 - 2.7, 1.5)])
    tekshir("suv yuqorida, oraliq 0,52 m ≥ 0,4 — mos", geo.kesishuvlar(s1, [kan3])[0]["xulosa"] == "mos")
    kab = liniya(21, "elektr", 50, "Cu", [(E0 + 30, N0 - 10, H0 - 1.7, 0.7), (E0 + 30, N0 + 10, H0 - 1.7, 0.7)])
    kab2 = liniya(22, "elektr", 50, "Cu", [(E0 + 30, N0 - 10, H0 - 1.3, 0.7), (E0 + 30, N0 + 10, H0 - 1.3, 0.7)])
    tekshir("kabel–suv: 0,195 m < 0,5 MOS EMAS; 0,595 m — mos", geo.kesishuvlar(s1, [kab])[0]["xulosa"] == "MOS EMAS"
            and geo.kesishuvlar(s1, [kab2])[0]["xulosa"] == "mos")
    bal = liniya(23, "gaz", 110, "PE", [(E0 + 35, N0 - 10, None, 1.0), (E0 + 35, N0 + 10, None, 1.0)])
    tekshir("balandliksiz kesishuv — baholanmadi", geo.kesishuvlar(s1, [bal])[0]["xulosa"] == "baholanmadi")

    # ---------- IH-07: loyiha DXF ----------
    def dxf_matn(qismlar):
        return "0\nSECTION\n2\nENTITIES\n" + "".join(qismlar) + "0\nENDSEC\n0\nEOF\n"

    lw = f"0\nLWPOLYLINE\n8\nLOYIHA_SUV\n90\n2\n70\n0\n38\n399.5\n10\n{E0}\n20\n{N0 + 0.12}\n10\n{E0 + 40}\n20\n{N0 + 0.12}\n"
    ln = f"0\nLINE\n8\nL2\n10\n{E0}\n20\n{N0 + 50}\n30\n0.0\n11\n{E0 + 10}\n21\n{N0 + 50}\n31\n0.0\n"
    pl = (f"0\nPOLYLINE\n8\nP3\n66\n1\n70\n9\n0\nVERTEX\n8\nP3\n10\n{E0}\n20\n{N0 - 50}\n30\n398.0\n"
          f"0\nVERTEX\n8\nP3\n10\n{E0 + 5}\n20\n{N0 - 50}\n30\n398.5\n0\nVERTEX\n8\nP3\n10\n{E0 + 5}\n20\n{N0 - 45}\n30\n399\n"
          "0\nSEQEND\n")
    ch = geo.dxf_oqi(dxf_matn([lw, ln, pl]))
    tekshir("DXF: LWPOLYLINE (38 balandlik), LINE, yopiq 3D POLYLINE o'qildi",
            len(ch) == 3 and ch[0]["nuqtalar"][0][2] == 399.5 and ch[0]["qatlam"] == "LOYIHA_SUV"
            and ch[1]["nuqtalar"][0][2] is None and len(ch[2]["nuqtalar"]) == 4 and ch[2]["nuqtalar"][1][2] == 398.5,
            json.dumps(ch)[:300])
    for nom, matn in (("mahalliy (UTM emas) koordinata rad etiladi", dxf_matn(["0\nLINE\n8\n0\n10\n1234.5\n20\n567.8\n11\n1240\n21\n570\n"])),
                      ("chiziqsiz DXF rad etiladi", dxf_matn(["0\nCIRCLE\n8\n0\n10\n362300\n20\n4445250\n40\n1\n"])),
                      ("buzilgan DXF rad etiladi", "salom\ndunyo\n")):
        try:
            geo.dxf_oqi(matn)
            tekshir(nom, False)
        except geo.DXFXato:
            tekshir(nom, True)
    utm_l = [{"turi": "suv", "diametr_mm": 160, "material": "PE", "sifat": "RASMIY",
              "nuqtalar": [{"e": E0, "n": N0, "h": 400.0, "chuqurlik": 1.5, "sifat": "RASMIY"},
                           {"e": E0 + 25, "n": N0 + 10, "h": 399.8, "chuqurlik": 1.6, "sifat": "RASMIY"}]}]
    qayta = geo.dxf_oqi(chizma.dxf(utm_l, {"obyekt": "sinov"}))
    tekshir("o'z DXF chizmamiz qayta o'qiladi (3D polilinya cho'qqilari mos)",
            any(len(c["nuqtalar"]) == 2 and abs(c["nuqtalar"][1][0] - (E0 + 25)) < 1e-3 and abs(c["nuqtalar"][1][2] - 399.8) < 1e-3
                for c in qayta), str(qayta[:2])[:300])
    og = geo.loyihadan_ogish(geo.xarakterli(s1), ch, geo.radius(s1), "usti")
    tekshir("loyihadan gorizontal og'ish 0,12 m", all(abs(g["gorizontal"] - 0.12) < 1e-6 for g in og[:1]), str(og[:2]))
    tekshir("vertikal og'ish: H usti − loyiha Z", abs(og[0]["vertikal"] - ((H0 - 2.0 + 0.08) - 399.5)) < 1e-9, str(og[0]))
    uzoq = geo.loyihadan_ogish([{"e": E0, "n": N0 + 30, "h": 400}], ch)
    tekshir("5 m dan uzoq loyiha chizig'i belgisi olinmaydi", uzoq[0]["yaqin"] is False and uzoq[0]["loyiha_z"] is None,
            str(uzoq))

    # ---------- IH-01…IH-03, IH-05, IH-06, IH-08: PDF ----------
    zich_skan = [(E0 + 30 + i * 0.1, N0 - 10 + i * 0.5, H0 - 2.6 - i * 0.0025, 2.2) for i in range(81)]
    m = {"raqam": "YRS-2026-000042", "sana": "03.10.2026", "url": "https://yerosti.example/t/Sinov_Kodi_12345",
         "obyekt": {"nomi": "SINOV <obyekt> & ko'cha", "manzil": "Jizzax", "buyurtmachi": "B", "pudratchi": "P MChJ",
                    "order_raqami": "ORD-1", "order_sana": "2026-10-01"},
         "zona": 42,
         "liniyalar": [liniya(1, "suv", 160, "PE100", [(E0, N0, H0 - 1.8, 1.6), (E0 + 70, N0 + 5, H0 - 2.0, 1.7),
                                                      (E0 + 70, N0 + 65, H0 - 2.2, 1.65)]),
                       liniya(2, "kanalizatsiya", 200, "PVC", zich_skan, sifat="SKAN", manba="skan")],
         "reestr": [dict(liniya(9, "gaz", 110, "PE", [(E0 + 20, N0 - 15, H0 - 1.2, 1.0), (E0 + 25, N0 + 40, H0 - 1.25, 1.0)]),
                         obyekt_nomi="Boshqa obyekt")],
         "loyiha": {"fayl_nomi": "loyiha.dxf", "sha256": "ab" * 32, "z_turi": "usti", "z_tizimi": "ellipsoid",
                    "yaratilgan": "2026-10-03T05:00:00+00:00",
                    "chiziqlar": geo.dxf_oqi(dxf_matn([f"0\nLWPOLYLINE\n8\nL\n38\n400.3\n10\n{E0}\n20\n{N0 + 0.12}\n"
                                                       f"10\n{E0 + 70}\n20\n{N0 + 5.12}\n10\n{E0 + 70.12}\n20\n{N0 + 65}\n"]))},
         "muhrlar": [{"id": 3, "holat": "TASDIQLANGAN", "sabab": "", "zanjir_boshi": "f" * 64, "yozuv_soni": 812,
                      "yaratilgan": "2026-10-02T09:00:00+00:00"}],
         "tahlillar": [{"id": 5, "muhr_id": 3, "holat": "tayyor", "xulosa": "MOS", "quvur_soni": 1, "oq_farqi_maks_m": 0.0012,
                        "tugagan": "2026-10-02T09:03:00+00:00", "sabablar": [], "ogohlantirishlar": []}],
         "yaratuvchi": "operator1"}
    pdf, N = ijro.hujjat_pdf(m)
    yol = os.path.join(TMP, "h.pdf")
    open(yol, "wb").write(pdf)
    katalog_v, asos_v, sifat_v = (len(f(m)) for f in (ijro._katalog_varaqlar, ijro._asos_varaqlar, ijro._sifat_varaqlar))
    tekshir("PDF: varaqlar = reja + katalog + geodezik asos + har liniyaga profil + sifat",
            pdf.startswith(b"%PDF") and N == 1 + katalog_v + asos_v + 2 + sifat_v, f"N={N} {katalog_v} {asos_v} {sifat_v}")
    info = subprocess.run(["pdfinfo", yol], capture_output=True, text=True).stdout
    tekshir("PDF: A3 albom, sarlavhada raqam", "1190.55 x 841.89" in info and "YRS-2026-000042" in info, info[:300])

    def matn(k=None):
        a = ["pdftotext", "-layout"] + (["-f", str(k), "-l", str(k)] if k else []) + [yol, "-"]
        return subprocess.run(a, capture_output=True, text=True).stdout

    hamma = matn()
    tekshir("har varaqda shtamp: raqam va obyekt nomi", all("YRS-2026-000042" in matn(k) and "SINOV <obyekt>" in matn(k)
                                                            for k in range(1, N + 1)))
    tekshir("imzo joylari: geodezist, litsenziya, pudratchi, texnik nazorat",
            all(s in matn(1) for s in ("Geodezist", "Litsenziya", "Pudratchi", "Texnik nazorat")))
    tekshir("reja: masshtab yozilgan (1:500)", "Masshtab 1:500" in matn(1), matn(1)[:400])
    xn = [p for l in m["liniyalar"] for p in l["xn"]]
    yoq = [p["raqam"] for p in xn if f"{p['n']:.3f}".replace(".", ",") not in hamma or f"{p['e']:.3f}".replace(".", ",") not in hamma]
    tekshir(f"katalog: {len(xn)} nuqtaning X (shimol) va Y (sharq) qiymati PDF da", not yoq, str(yoq[:10]))
    tekshir("katalog: raqamlar 1…N uzluksiz", [p["raqam"] for p in xn] == list(range(1, len(xn) + 1)))
    tekshir("katalog: oraliq nuqta 'hisoblangan' deb yozilgan", "oraliq (hisoblangan)" in hamma)
    tekshir("kesishuv jadvali: K1 va vertikal oraliq", "K1" in hamma and "Vertikal oraliq" in hamma)
    kesh = [k for l in m["liniyalar"] for k in l["kesishuv"] if not k["takror"]]
    tekshir("bir obyekt ichidagi kesishuv bitta K raqam oladi (ikki liniya profilida bir xil)",
            len({k["k"] for l in m["liniyalar"] for k in l["kesishuv"]}) == len(kesh) == 2, str(kesh))
    tekshir("loyihadan og'ish ustuni va 0,12 m", "Loyihadan og'ish" in hamma and " 0,12 " in hamma)
    tekshir("profil: loyiha belgisi qatori to'ldirilgan (usti, ellipsoid)", "Loyiha belgisi (quvur usti)" in hamma)
    tekshir("RASMIY emas ogohlantirishi rejada", "RASMIY emas" in matn(1))
    tekshir("sifat varag'i: muhr, qayta hisob, bayonotlar", all(s in hamma for s in ("TASDIQLANGAN", "MOS", "Bayonotlar",
                                                                                    "Boltiq emas")))
    tekshir("LK-06: lokalizatsiyasiz hujjat har varaqda YAROQSIZ va sababi yozilgan",
            all("TOPSHIRISHGA YAROQSIZ" in matn(k) for k in range(1, N + 1)) and "Lokalizatsiya qilinmagan" in hamma
            and "lokalizatsiya qilinmagan [G2 5.4, 6.10]" in hamma.replace("\n", " "))

    # QR: rasterlab OpenCV bilan o'qish
    import cv2
    subprocess.run(["pdftoppm", "-r", "220", "-f", "1", "-l", "1", "-png", yol, os.path.join(TMP, "v")], check=True)
    rasm = cv2.imread(os.path.join(TMP, "v-1.png"))
    h_, w_ = rasm.shape[:2]
    mm = w_ / 420.0
    kesik = rasm[int(h_ - (ijro.QR_Y + ijro.QR_O + 6) * mm):int(h_ - (ijro.QR_Y - 6) * mm),
                 int((ijro.QR_X - 6) * mm):int((ijro.QR_X + ijro.QR_O + 2.5) * mm)]
    qiymat, _, _ = cv2.QRCodeDetector().detectAndDecode(kesik)
    tekshir("QR OpenCV bilan o'qildi va tekshirish havolasiga teng", qiymat == m["url"], repr(qiymat))

    # IH-08: tekshirish xulosasida koordinata yo'q
    x = ijro.tekshirish_xulosasi(m, N)
    j = json.dumps(x, ensure_ascii=False)
    tekshir("tekshirish xulosasida koordinata yo'q", "4445" not in j and "3623" not in j and "40." not in j, j)
    sah = ochiq.tekshirish_sahifasi({"raqam": "YRS-2026-000042", "holat": "amal", "sha256": "ab" * 32, "varaqlar": N,
                                     "xulosa": x, "yaratilgan": "2026-10-03T05:00:00+00:00"}, m["obyekt"])
    tekshir("tekshirish sahifasi: HTML qochirilgan, koordinata yo'q",
            "SINOV &lt;obyekt&gt; &amp; ko&#x27;cha" in sah and "<obyekt>" not in sah and "4445" not in sah, sah[:200])

    # bo'sh holatlar: muhrsiz, loyihasiz, balandliksiz liniya
    m2 = {**m, "raqam": "YRS-2026-000043", "loyiha": None, "muhrlar": [], "tahlillar": [], "reestr": [],
          "liniyalar": [liniya(1, "elektr", 50, "Cu", [(E0, N0, None, 0.8), (E0 + 12, N0, None, 0.9)], sifat="PAST")]}
    pdf2, N2 = ijro.hujjat_pdf(m2)
    open(yol, "wb").write(pdf2)
    t2 = matn()
    tekshir("loyihasiz va balandliksiz: 'loyiha kiritilmagan', 'Balandlik o'lchanmagan', muhr yo'q",
            all(s in t2 for s in ("loyiha kiritilmagan", "Balandlik o'lchanmagan", "Muhr yo'q", "kesishuv topilmadi")), t2[:500])
    # ---------- KU-01: IFC 4.3 eksporti ----------
    import yerosti_ifc as yifc
    lin_ifc = [liniya(1, "suv", 160, "PE100", [(E0, N0, H0 - 2, 1.5), (E0 + 40, N0, H0 - 2.2, 1.6)]),
               liniya(2, "elektr", 50, "Cu", [(E0 + 20, N0 - 10, H0 - 1.2, 0.8), (E0 + 20, N0 + 10, H0 - 1.2, 0.8)])]
    lin_ifc[0]["egasi"] = "Sinov Suvsoz"; lin_ifc[0]["ishlash_holati"] = "ishlayapti"; lin_ifc[0]["ornatilgan_yil"] = 2026
    lin_ifc[0]["tasdiq"] = {"holat": "tasdiqlangan"}
    ob = {"id": 7, "nomi": "SINOV ob'ekt «ko'cha»", "manzil": "Jizzax", "buyurtmachi": "B", "pudratchi": "P", "order_raqami": "O-1", "order_sana": "2026-10-01"}
    utm_t = ijro.tizim_tanla(None, 42)
    matn_ifc = yifc.ifc(lin_ifc, ob, utm_t, 42, "YRS-2026-000050")
    ent = yifc.step_oqi(matn_ifc)
    turlar = [t for t, _ in ent.values()]
    mk = next(a for t, a in ent.values() if t == "IFCMAPCONVERSION")
    crs = next(a for t, a in ent.values() if t == "IFCPROJECTEDCRS")
    sds = [a for t, a in ent.values() if t == "IFCSWEPTDISKSOLIDPOLYGONAL"]
    tekshir("IFC: sxema IFC4X3_ADD2, 1 IfcPipeSegment + 1 IfcCableSegment, IfcSite/IfcProject, hamma havolalar bor",
            "FILE_SCHEMA(('IFC4X3_ADD2'))" in matn_ifc and turlar.count("IFCPIPESEGMENT") == 1 and turlar.count("IFCCABLESEGMENT") == 1
            and "IFCSITE" in turlar and "IFCPROJECT" in turlar and "IFCRELCONTAINEDINSPATIALSTRUCTURE" in turlar, str(turlar[:20]))
    tekshir("IFC: IfcMapConversion boshlang'ichi = eng kichik E/N/H (kabel N0−10 gacha), IfcProjectedCRS EPSG:32642",
            f"{E0:.1f}" in mk and f"{N0 - 10:.1f}" in mk and f"{H0 - 2.2:.1f}" in mk and "'EPSG:32642'" in crs and "'42N'" in crs, mk + " | " + crs)
    tekshir("IFC: swept disk radiuslari 0,08 va 0,025 m, polilinya 2 nuqta", any(",0.08,$" in a for a in sds) and any(",0.025,$" in a for a in sds)
            and turlar.count("IFCPOLYLINE") == 2 and turlar.count("IFCCARTESIANPOINT") == 5, str(sds))
    pset = [a for t, a in ent.values() if t == "IFCPROPERTYSINGLEVALUE"]
    tekshir("IFC: TRACE4D_Ijro — sifat, RTK tasdiq, egasi, PAS 128 darajasi, hujjat raqami; apostrof va kirill belgilar kodlangan",
            any("'RTKTasdiq_T031',$,IFCLABEL('tasdiqlangan')" in a for a in pset) and any("IFCLABEL('Sinov Suvsoz')" in a for a in pset)
            and any("'SifatDarajasi_PAS128'" in a for a in pset) and any("IFCLABEL('YRS-2026-000050')" in a for a in pset)
            and "\\X2\\00AB\\X0\\" in matn_ifc and "ob''ekt" in matn_ifc, str(pset[:3]))
    tekshir("ShN-01: IFC TRACE4D_Ijro da OrderSana", any("'OrderSana',$,IFCLABEL('2026-10-01')" in a for a in pset), str(pset[-6:]))
    tekshir("IFC: 22 belgili GlobalId lar yagona (2 element, sayt, loyiha, 2 pset)", len({a.split(",")[0] for t, a in ent.values() if t in ("IFCPIPESEGMENT", "IFCCABLESEGMENT", "IFCSITE", "IFCPROJECT", "IFCPROPERTYSET")}) == 6
            and all(len(a.split(",")[0]) == 24 for t, a in ent.values() if t == "IFCPIPESEGMENT"))

    # ---------- T-031: tasdiqlangan skan liniyasi hujjatda rasmiy (TQ-07) ----------
    import yerosti_tasdiq as tq_mod
    sk = liniya(20, "suv", 160, "PE100", [(E0, N0 + 100, H0 - 1.9, 1.6), (E0 + 40, N0 + 100, H0 - 1.95, 1.6)], sifat="SKAN", manba="skan")

    def tq_holat(holat, kam):
        return {"holat": holat, "soni": 2, "otgan": 2, "kamchiliklar": kam, "maks_gor": 0.012, "maks_ver": 0.02, "skan": True,
                "kerakli": [{"turi": "bosh", "stansiya": 0.0, "pk": "PK0+00,00"}, {"turi": "oxir", "stansiya": 40.0, "pk": "PK0+40,00"}]}

    tasdiqlar = [{"id": 1, "nomi": "T1", "liniya_id": 20, "pk": "PK0+00,00", "stansiya": 0.0, "e": E0, "n": N0 + 100, "h": H0 - 1.82,
                  "joy": "usti", "d_gor": 0.012, "d_ver": 0.0, "otdi": True, "sabab": "", "sigma_h_sm": 0.9, "sigma_v_sm": 1.4,
                  "vaqt": "2026-10-03T05:00:00+00:00", "manba": "rtk"},
                 {"id": 2, "nomi": "T2", "liniya_id": 20, "pk": "PK0+40,00", "stansiya": 40.0, "e": E0 + 40, "n": N0 + 100, "h": H0 - 1.85,
                  "joy": "usti", "d_gor": 0.008, "d_ver": 0.02, "otdi": True, "sabab": "", "sigma_h_sm": 0.9, "sigma_v_sm": 1.4,
                  "vaqt": "2026-10-03T05:01:00+00:00", "manba": "import"}]
    m3 = {**m, "raqam": "YRS-2026-000044", "liniyalar": [liniya(1, "suv", 160, "PE", [(E0, N0, H0 - 2, 1.5), (E0 + 40, N0, H0 - 2.2, 1.6)]), sk],
          "tasdiq": {"tasdiqlar": tasdiqlar, "liniyalar": {20: tq_holat("tasdiqlangan", [])}, "chegaralar": tq_mod.chegaralar()}}
    pdf3, N3 = ijro.hujjat_pdf(m3)
    sab = m3["yaroqlilik"]["sabablar"]
    tekshir("T-031: tasdiqlangan SKAN liniyasi yaroqsizlik sababi EMAS (faqat lokalizatsiya sababi qoladi)",
            not any("SKAN" in s_ for s_ in sab) and len(sab) == 1, str(sab))
    open(yol, "wb").write(pdf3)
    t3 = matn().replace("\n", " ")
    tekshir("T-031: PDF — tasdiq bo'limi, liniya TASDIQLANGAN, katalogda «skan, RTK tasdiq», rejada uchburchak belgisi",
            "Quvur tasdig'i (T-031)" in t3 and "TASDIQLANGAN" in t3 and "skan, RTK tasdiq" in t3 and "RTK tasdiq nuqtasi" in t3, t3[:300])
    x3 = ijro.tekshirish_xulosasi(m3, N3)
    sah3 = ochiq.tekshirish_sahifasi({"raqam": "YRS-2026-000044", "holat": "amal", "sha256": "ab" * 32, "varaqlar": N3, "xulosa": x3,
                                      "yaratilgan": "2026-10-03T05:00:00+00:00"}, m["obyekt"])
    tekshir("T-031: xulosada tasdiq sanog'i (1/1, 2 o'lchov) va QR sahifasida matn",
            x3["tasdiq"] == {"kerak": 1, "tasdiqlangan": 1, "farq": 0, "olchovlar": 2}
            and "1 / 1 skan liniyasi RTK bilan tasdiqlangan" in sah3, str(x3["tasdiq"]))
    m5 = {**m, "raqam": "YRS-2026-000046", "reestr": [], "liniyalar": [
        liniya(1, "suv", 160, "PE", [(E0, N0, H0 - 2, 1.5), (E0 + 40, N0, H0 - 2.0, 1.5)]),
        liniya(2, "kanalizatsiya", 200, "PVC", [(E0 + 20, N0 - 10, H0 - 2.3, 1.5), (E0 + 20, N0 + 10, H0 - 2.3, 1.5)])]}
    pdf5, _ = ijro.hujjat_pdf(m5)
    open(yol, "wb").write(pdf5)
    t5 = matn().replace("\n", " ")
    tekshir("IH-04a: PDF kesishuv jadvalida me'yor ustuni va MOS EMAS (0,12 m < 0,4 m)",
            "Me'yor, m" in t5 and "MOS EMAS" in t5 and "0.12 m < 0.4 m" in t5 and "Kesishuv (mos emas)" in t5, t5[:300])
    x5 = ijro.tekshirish_xulosasi(m5, 5)
    tekshir("IH-04a: xulosada mos emas kesishuvlar soni", x5["kesishuv_mos_emas"] == 1 and x5["kesishuvlar"] == 1, str(x5))
    m4 = {**m3, "raqam": "YRS-2026-000045", "liniyalar": [liniya(1, "suv", 160, "PE", [(E0, N0, H0 - 2, 1.5), (E0 + 40, N0, H0 - 2.2, 1.6)]),
                                                         liniya(20, "suv", 160, "PE100", [(E0, N0 + 100, H0 - 1.9, 1.6), (E0 + 40, N0 + 100, H0 - 1.95, 1.6)], sifat="SKAN", manba="skan")],
          "tasdiq": {"tasdiqlar": tasdiqlar[:1], "liniyalar": {20: tq_holat("qisman", ["oxiri (PK0+40,00) 1 m ichida tasdiqlanmagan"])},
                     "chegaralar": tq_mod.chegaralar()}}
    ijro.hujjat_pdf(m4)
    tekshir("T-031: qisman tasdiqlangan liniya — sabab T-031 va kamchilik bilan, RASMIY emas",
            any("T-031" in s_ and "oxiri" in s_ and "RASMIY emas" in s_ for s_ in m4["yaroqlilik"]["sabablar"]), str(m4["yaroqlilik"]["sabablar"]))

    # ---------- ShN-01, ShN-02: qazish orderi sanasi va o'lchov usuli (ShNK 3.01.03-24, 420 va 406–407-bandlar) ----------
    open(yol, "wb").write(pdf)
    t1 = " ".join(matn().split())
    tekshir("ShN-01: shtampda order raqami va sanasi «ORD-1, 01.10.2026»; sana bor — order sababi yo'q",
            "Order (ruxsatnoma): ORD-1, 01.10.2026" in t1 and not any("orderining" in s_ for s_ in m["yaroqlilik"]["sabablar"]),
            str(m["yaroqlilik"]["sabablar"]))
    tekshir("ShN-02: sifat varag'ida o'lchov usuli — rasmiy RTK GNSS, LiDAR tasdiqlovchi 3D dalil, 406–407-bandlar",
            "O'lchov usuli: rasmiy koordinata va balandliklar — RTK GNSS (FIX)" in t1 and "tasdiqlovchi 3D dalili" in t1
            and "406–407-bandlarida LiDAR usuli nomlanmagan" in t1, t1[t1.find("O'lchov usuli"):][:300])
    yangi_lin = lambda: [liniya(1, "suv", 160, "PE", [(E0, N0, H0 - 2, 1.5), (E0 + 40, N0, H0 - 2.2, 1.6)])]
    m6 = {**m, "raqam": "YRS-2026-000047", "liniyalar": yangi_lin(), "reestr": [], "loyiha": None,
          "obyekt": {**m["obyekt"], "order_raqami": "", "order_sana": ""}}
    m7 = {**m, "raqam": "YRS-2026-000048", "liniyalar": yangi_lin(), "reestr": [], "loyiha": None,
          "obyekt": {**m["obyekt"], "order_sana": ""}}
    pdf6, _ = ijro.hujjat_pdf(m6)
    ijro.hujjat_pdf(m7)
    s6 = [s_ for s_ in m6["yaroqlilik"]["sabablar"] if "orderining" in s_]
    s7 = [s_ for s_ in m7["yaroqlilik"]["sabablar"] if "orderining" in s_]
    tekshir("ShN-01: order yo'q — «raqami va sanasi», faqat sana yo'q — «sanasi»; 420-band havolasi bilan YAROQSIZ",
            s6 == ["qazish orderining raqami va sanasi ko'rsatilmagan [ShNK 3.01.03-24, 420-band]"]
            and s7 == ["qazish orderining sanasi ko'rsatilmagan [ShNK 3.01.03-24, 420-band]"]
            and not m6["yaroqlilik"]["yaroqli"], str(s6 + s7))
    open(yol, "wb").write(pdf6)
    t6 = " ".join(matn().split())
    tekshir("ShN-01: order yo'q hujjatda shtamp «—» va sabab PDF da ko'rinadi",
            "Order (ruxsatnoma): —" in t6 and "qazish orderining raqami va sanasi ko'rsatilmagan" in t6, t6[:300])
    x1 = ijro.tekshirish_xulosasi(m, N)
    sah1 = ochiq.tekshirish_sahifasi({"raqam": m["raqam"], "holat": "amal", "sha256": "cd" * 32, "varaqlar": N, "xulosa": x1,
                                      "yaratilgan": "2026-10-03T05:00:00+00:00"}, m["obyekt"])
    tekshir("ShN-01: QR xulosasida order sanasi, ochiq sahifada «ORD-1, 01.10.2026»",
            x1["order"] == "ORD-1" and x1["order_sana"] == "2026-10-01" and "ORD-1, 01.10.2026" in sah1, str(x1.get("order_sana")))
    juft = [{"order_raqami": "A-1", "order_sana": "2026-01-31"}, {"order_raqami": "A-1"}, {"order_sana": "2026-01-31"}, {}, None]
    tekshir("ShN-01: order matni hujjatda va ochiq sahifada bir xil (5 holat)",
            all(ijro.order_matn(o) == ochiq._order(o) for o in juft)
            and [ijro.order_matn(o) for o in juft] == ["A-1, 31.01.2026", "A-1, sana yo'q", "raqam yo'q, 31.01.2026", "", ""],
            str([ijro.order_matn(o) for o in juft]))

    # ---------- T3: loyiha–ijro muvofiqligi (SNiP 3.05.04-85*, 3.6-band; qaror o'lchov xatosi bilan, k = 2) ----------
    import yerosti_muvofiqlik as mv
    tekshir("T3: qaror qoidasi — me'yorda / tashqari / noaniq / me'yor yo'q",
            [mv.qaror(0.05, 0.01, 0.10), mv.qaror(0.15, 0.01, 0.10), mv.qaror(0.09, 0.01, 0.10), mv.qaror(0.30, 0.01, None),
             mv.qaror(-0.15, 0.01, 0.10)] == ["meyorda", "tashqari", "noaniq", "meyor_yoq", "tashqari"])
    tekshir("T3: rejim — suv bosimli, kanalizatsiya bosimsiz (parametrda MPa bo'lsa bosimli), gaz — me'yor yo'q",
            [mv.rejim({"turi": "suv"}), mv.rejim({"turi": "kanalizatsiya"}), mv.rejim({"turi": "kanalizatsiya", "parametr": "0,6 MPa"}),
             mv.rejim({"turi": "gaz"})] == ["bosimli", "bosimsiz", "bosimli", None])
    t3 = mv.tahlil(m)
    l1 = next(x for x in t3["liniyalar"] if x["id"] == 1)
    l2 = next(x for x in t3["liniyalar"] if x["id"] == 2)
    tekshir("T3: suv (bosimli) loyihadan 12 sm, σH 1,2 sm — ruxsat ±10 sm chegarasida isbotlanmaydi: «noaniq» (tashqari emas)",
            l1["rejim"] == "bosimli" and abs(l1["maks_g_m"] - 0.12) < 1e-6 and l1["holat_g"].get("noaniq", 0) >= 1
            and not l1["holat_g"].get("tashqari") and l1["ruxsat_g_m"] == 0.100, str(l1))
    tekshir("T3: loyihadan uzoq kanalizatsiya skani — loyihadan tashqari oraliq; bosimsiz rejada me'yor yo'q",
            l2["rejim"] == "bosimsiz" and l2["ruxsat_g_m"] is None and any(x["liniya"] == 2 for x in t3["loyihadan_tashqari"]), str(t3["loyihadan_tashqari"]))
    uzoq = {"qatlam": "LOYIHA_UZOQ", "nuqtalar": [[E0 + 200, N0, 400.0], [E0 + 230, N0, 400.0]]}
    t3q = mv.tahlil({**m, "loyiha": {**m["loyiha"], "chiziqlar": m["loyiha"]["chiziqlar"] + [uzoq]}})
    q = [x for x in t3q["qurilmagan"] if x["qatlam"] == "LOYIHA_UZOQ"]
    tekshir("T3: ijrosi yo'q 30 m loyiha chizig'i — «qurilmagan» 30 m, qamrov 0 %",
            len(q) == 1 and abs(q[0]["uzunlik_m"] - 30) < 1.01 and next(x for x in t3q["qamrov"] if x["qatlam"] == "LOYIHA_UZOQ")["qamrov_foiz"] == 0,
            str(q))
    # bosimli, katta og'ish (25 sm) aniq o'lchov bilan — isbotlangan «tashqari»
    surilgan = {**m["loyiha"], "chiziqlar": [{"qatlam": "S", "nuqtalar": [[e, n + 0.25, z] for e, n, z in m["loyiha"]["chiziqlar"][0]["nuqtalar"]]}]}
    m_s = {**m, "raqam": "YLM-2026-000051", "loyiha": surilgan, "liniyalar": [liniya(1, "suv", 160, "PE100", [(E0, N0, H0 - 1.8, 1.6),
                                                                                                              (E0 + 70, N0 + 5, H0 - 2.0, 1.7)])], "reestr": []}
    ijro.tayyorla(m_s)
    t3s = mv.tahlil(m_s)
    tekshir("T3: 25 sm og'ish, σH 1,2 sm — me'yordan tashqari isbotlangan", t3s["jami"]["tashqari"] >= 2, str(t3s["jami"]))
    pdf_m, N_m = mv.pdf(m_s, t3s)
    open(yol, "wb").write(pdf_m)
    tm = " ".join(matn().split())
    tekshir("T3: hisobot PDF — sarlavha, qaror qoidasi, manba bandi, «ME'YORDAN TASHQARI» va pikitaj",
            "LOYIHA–IJRO MUVOFIQLIGI HISOBOTI" in tm and "SNiP 3.05.04-85*, 3.6-band" in tm and "ME'YORDAN TASHQARI" in tm
            and "0+00,00" in tm and "2σ" in tm, tm[:300])
finally:
    shutil.rmtree(TMP, ignore_errors=True)

yiq = sum(1 for _, ok in natijalar if not ok)
print(f"\nJAMI: {len(natijalar)} tekshiruv, {yiq} FAIL")
sys.exit(1 if yiq else 0)
