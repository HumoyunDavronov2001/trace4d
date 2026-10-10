"""YEROSTI — lokalizatsiya sinovi (TALABLAR 15: LK-03…LK-08). Bazasiz.

"Mahalliy tizim" SUN'IY: o'z markaziy meridiani, burilish, masshtab va siljish bilan yasalgan, balandlik anomaliyasi
qiya tekislik. Haqiqiy shahar tizimi emas — usul to'g'ri ishlashini isbotlash uchun.
Ishga tushirish:  python3 sinov/lokal_sinov.py      (pdftotext kerak)
"""
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
import yerosti_lokal as L  # noqa: E402

TMP = tempfile.mkdtemp(prefix="yerosti_lokal_")
natijalar = []


def tekshir(nom, shart, izoh=""):
    natijalar.append((nom, bool(shart)))
    print(("PASS " if shart else "FAIL ") + nom + (f"  [{izoh}]" if (izoh and not shart) else ""))


# sun'iy mahalliy tizim (MSK o'rnida)
LON_T, ROT, SC = 67.80, math.radians(0.37), 1.000120
X0, Y0 = -4435000.0 + 123.4, 54321.0


def msk(lat, lon):
    e, n = L.tm(lat, lon, LON_T)
    c, s = math.cos(ROT) * SC, math.sin(ROT) * SC
    return s * e + c * n + X0, c * e - s * n + Y0          # X shimol, Y sharq


def zeta(lat, lon):
    e, n = L.tm(lat, lon, 67.84)
    return -38.5 + 25e-6 * e - 15e-6 * (n - 4.44e6)


LAT0, LON0 = 40.115, 67.842
JOYLAR = [(-0.004, -0.003), (0.004, -0.003), (0.004, 0.003), (-0.004, 0.003), (0.0005, 0.0)]


def punktlar(shovqin=None, ruxsat=None):
    rnd = random.Random(shovqin)
    natija = []
    for i, (dl, dn) in enumerate(JOYLAR):
        if ruxsat is not None and i not in ruxsat:
            continue
        la, lo = LAT0 + dn, LON0 + dl
        h = 350.0 + 3 * i
        X, Y = msk(la, lo)
        H = h - zeta(la, lo)
        if shovqin is not None:
            X, Y, H = X + rnd.gauss(0, 0.006), Y + rnd.gauss(0, 0.006), H + rnd.gauss(0, 0.01)
        natija.append({"nomi": f"P{i + 1}", "lat": la, "lon": lo, "h": h, "X": X, "Y": Y, "H": H})
    return natija


try:
    # ---------- LK-03: proyeksiya ----------
    e, n = L.tm(40.1162, 67.8431, 69.0)
    ue, un, _ = chizma.utm(40.1162, 67.8431, 42)
    tekshir("mahalliy TM (k0=1) UTM bilan mos: E = 500 km + 0,9996·e, N = 0,9996·n (≤ 1 mm)",
            abs(500000 + 0.9996 * e - ue) < 1e-3 and abs(0.9996 * n - un) < 1e-3, f"{ue} {un}")
    la, lo = L.tm_teskari(*L.tm(40.1162, 67.8431, 67.84), 67.84)
    tekshir("TM oldinga → teskari ≤ 1 mm", abs(la - 40.1162) * 111000 < 1e-3 and abs(lo - 67.8431) * 85000 < 1e-3)
    la, lo = L.utm_teskari(ue, un, 42)
    tekshir("UTM teskari ≤ 1 mm", abs(la - 40.1162) * 111000 < 1e-3 and abs(lo - 67.8431) * 85000 < 1e-3)

    # ---------- LK-03: sun'iy tizimni tiklash ----------
    nt = L.hisobla(punktlar())
    tekshir("shovqinsiz: qoldiqlar ≤ 1 mm (gorizontal va vertikal)", nt["maks_gor"] < 1e-3 and nt["maks_ver"] < 1e-3,
            f"{nt['maks_gor']} {nt['maks_ver']}")
    # boshqa markaziy meridian: masshtab farqi ~0,15 ppm, burilishga meridianlar yaqinlashuvi qo'shiladi
    yaqinlashuv = math.degrees(math.radians(nt["parametrlar"]["lon0"] - LON_T) * math.sin(math.radians(LAT0)))
    tekshir("masshtab va burilish tiklandi (+120 ppm, 0,37° + meridian yaqinlashuvi)",
            abs(nt["masshtab_ppm"] - 120) < 1 and abs(nt["burilish_grad"] - (0.37 + yaqinlashuv)) < 1e-3,
            f"{nt['masshtab_ppm']} {nt['burilish_grad']} {0.37 + yaqinlashuv}")
    tekshir("5 punkt: vertikal model qiya tekislik, xulosa yaroqli", nt["parametrlar"]["v"]["model"] == "qiya tekislik"
            and nt["yaroqli"] and not nt["xatolar"], str(nt["xatolar"]))
    lok = L.Lokalizatsiya(nt["parametrlar"])
    X, Y = msk(40.1162, 67.8431)
    la, lo, h = lok.teskari(X, Y, 400.0)
    X2, Y2, H2 = lok.oldinga(la, lo, h)
    tekshir("mahalliy → WGS84 → mahalliy ≤ 1 mm (LK-07)", max(abs(X2 - X), abs(Y2 - Y), abs(H2 - 400.0)) < 1e-3)
    Xs, Ys, Hs = lok.oldinga(40.1162, 67.8431, 380.0)
    tekshir("ichki nuqta: lokalizatsiya bashorati haqiqiy tizim bilan ≤ 1 mm",
            abs(Xs - X) < 1e-3 and abs(Ys - Y) < 1e-3 and abs(Hs - (380.0 - zeta(40.1162, 67.8431))) < 1e-3)

    # ---------- LK-04: chegaralar ----------
    nt3 = L.hisobla(punktlar(ruxsat={0, 1, 2}))
    tekshir("3 punkt: vertikal doimiy, 'kamida 4' xatosi", nt3["parametrlar"]["v"]["model"] == "doimiy"
            and any("kamida 4" in x for x in nt3["xatolar"]) and not nt3["yaroqli"])
    yomon = punktlar(shovqin=3)
    yomon[2]["X"] += 0.06
    nty = L.hisobla(yomon)
    eng = max(nty["loo"], key=lambda r: r["gor"] or 0)
    tekshir("6 sm xato punkt: yaroqsiz va LOO aynan P3 ni ko'rsatadi", not nty["yaroqli"] and eng["nomi"] == "P3",
            f"{nty['xatolar']} {[(r['nomi'], r['gor']) for r in nty['loo']]}")
    birlik = [dict(p, X=p["X"] * 1.01, Y=p["Y"] * 1.01) for p in punktlar()]
    ntb = L.hisobla(birlik)
    tekshir("koordinata 1 % cho'zilgan (birlik yoki tizim xatosi): masshtab rad etiladi",
            not ntb["yaroqli"] and any("masshtab" in x for x in ntb["xatolar"]), str(ntb["xatolar"]))
    chiziqda = punktlar()
    for i, p in enumerate(chiziqda[:4]):
        p.update(lat=LAT0, lon=LON0 + 0.002 * i)
        p["X"], p["Y"] = msk(p["lat"], p["lon"])
        p["H"] = p["h"] - zeta(p["lat"], p["lon"])
    ntc = L.hisobla(chiziqda[:4])
    tekshir("4 punkt bir chiziqda: tekislik emas, doimiy model", ntc["parametrlar"]["v"]["model"].startswith("doimiy"),
            ntc["parametrlar"]["v"]["model"])
    faqat_h = punktlar()
    for p in faqat_h[:2]:
        p["X"] = p["Y"] = None          # reperlar: faqat balandligi ma'lum
    nth = L.hisobla(faqat_h)
    tekshir("faqat balandligi ma'lum reperlar vertikalga kiradi, gorizontalga kirmaydi", nth["n_gor"] == 3 and nth["n_ver"] == 5)

    # ---------- LK-05: tekshiruv o'lchovi va kunlar ----------
    la, lo = LAT0 + 0.001, LON0 - 0.001
    X, Y = msk(la, lo)
    t_ok = L.tekshiruv(lok, {"lat": la, "lon": lo, "h": 360.0}, {"X": X + 0.01, "Y": Y, "H": 360.0 - zeta(la, lo) - 0.02})
    t_yomon = L.tekshiruv(lok, {"lat": la, "lon": lo, "h": 360.0}, {"X": X + 0.05, "Y": Y, "H": 360.0 - zeta(la, lo)})
    tekshir("tekshiruv: 1 sm / 2 sm o'tadi, 5 sm o'tmaydi (baza koordinatasi xatosi ushlanadi)",
            t_ok["otdi"] and not t_yomon["otdi"] and abs(t_yomon["gor"] - 0.05) < 1e-3)
    kun = L.kunlik_nazorat({"2026-10-01", "2026-10-02"}, [{"vaqt": "2026-10-02T05:00:00+00:00", "otdi": True}],
                           [{"vaqt": "2026-10-01T04:00:00+00:00"}], True)
    kun2 = L.kunlik_nazorat({"2026-10-01", "2026-10-03"}, [], [{"vaqt": "2026-09-30T20:30:00+00:00"}], True)
    tekshir("ish kunlari: kalibrlash kuni va tekshiruv kuni o'tadi; UTC 20:30 Toshkentda keyingi kun",
            all(k["tekshirilgan"] for k in kun) and kun2 == [{"kun": "2026-10-01", "tekshirilgan": True},
                                                            {"kun": "2026-10-03", "tekshirilgan": False}], str(kun2))
    tekshir("qamrov: ichki nuqta 0, tashqi nuqta masofasi",
            L.qamrovdan_tashqari(nt["qobiq"], (Y, X)) == 0.0 and 500 < L.qamrovdan_tashqari(nt["qobiq"], (Y + 1000, X)) < 700)

    # ---------- LK-06: mahalliy tizimdagi hujjat ----------
    def baza_liniyasi(lid, turi, d, nuqtalar, sifat="RASMIY", vaqt="2026-10-02T06:00:00+00:00"):
        return {"id": lid, "turi": turi, "diametr_mm": d, "material": "PE100", "sifat": sifat, "obyekt_nomi": "",
                "izoh": "", "versiya": 1, "yaratilgan": vaqt,
                "nuqtalar": [{"id": lid * 100 + i, "lat": a, "lon": o, "balandlik": h, "chuqurlik_m": 1.6, "sifat": sifat,
                              "manba": "rtk", "sigma_h_sm": 1.1, "rtk_holat": "FIX", "izoh": "", "vaqt": vaqt}
                             for i, (a, o, h) in enumerate(nuqtalar)]}

    pk = punktlar()
    juftlar = [dict(p) for p in pk]
    natija = L.hisobla(juftlar)
    natija["juftlar"] = [{"nomi": p["nomi"], "olchov_soni": 1} for p in pk]
    lq = {"id": 7, "tizim_nomi": "SINOV MSK (sun'iy)", "natija": natija, "olchovlar": [1, 2, 3, 4, 5],
          "yaratilgan": "2026-10-02T04:00:00+00:00"}
    tizim = ijro.tizim_tanla(lq, 42)
    yolak = [(LAT0 - 0.0010 + 0.0001 * i, LON0 - 0.0010 + 0.00012 * i, 360.0 - 0.02 * i) for i in range(12)]
    baza_lin = [baza_liniyasi(1, "suv", 160, yolak)]
    lin, _ = ijro.planar_liniyalar(baza_lin, tizim["lok"])
    db_punkt = [{"id": i + 1, "nomi": p["nomi"], "x": p["X"], "y": p["Y"], "h": p["H"], "sinf": "4-sinf poligonometriya",
                 "manba": "shahar tarmog'i (sun'iy)"} for i, p in enumerate(pk)]
    olch = [{"id": i + 1, "punkt_id": i + 1, "maqsad": "kalibrlash", "lat": p["lat"], "lon": p["lon"], "h": p["h"],
             "vaqt": "2026-10-02T04:00:00+00:00"} for i, p in enumerate(pk)]
    tek = L.tekshiruvlar(tizim["lok"], db_punkt, olch)
    asos = {"punktlar": db_punkt, "olchovlar": olch, "lok": lq, "tekshiruvlar": tek,
            "kunlar": L.kunlik_nazorat({"2026-10-02"}, tek, olch, True)}

    def hujjat(lin, asos, nomi):
        m = {"raqam": "YRS-2026-000099", "sana": "03.10.2026", "url": "https://yerosti.example.uz/t/sinov_kodi_12345",
             "obyekt": {"nomi": nomi, "manzil": "", "buyurtmachi": "", "pudratchi": "", "order_raqami": "SINOV-ORD-7",
                        "order_sana": "2026-10-01"}, "zona": 42,
             "tizim": tizim, "liniyalar": lin, "reestr": [], "loyiha": None, "asos": asos, "muhrlar": [], "tahlillar": [],
             "yaratuvchi": "sinov"}
        pdf, N = ijro.hujjat_pdf(m)
        y = os.path.join(TMP, "m.pdf")
        open(y, "wb").write(pdf)
        sahifalar = [subprocess.run(["pdftotext", "-layout", "-f", str(k), "-l", str(k), y, "-"], capture_output=True,
                                    text=True).stdout for k in range(1, N + 1)]
        return m, N, sahifalar

    m, N, sah = hujjat(lin, asos, "SINOV: mahalliy tizim (sun'iy)")
    hamma = "\n".join(sah)
    p0 = m["liniyalar"][0]["xn"][0]
    Xk, Yk = msk(yolak[0][0], yolak[0][1])
    tekshir("katalogda mahalliy X va Y (sun'iy tizim qiymati, ≤ 1 mm)",
            f"{p0['n']:.3f}".replace(".", ",") in hamma and abs(p0["n"] - Xk) < 1e-3 and abs(p0["e"] - Yk) < 1e-3,
            f"{p0['n']} {Xk}")
    Hk = yolak[0][2] - zeta(yolak[0][0], yolak[0][1])
    tekshir("katalogda Boltiq H o'q (≤ 1 mm)", abs(p0["h"] - Hk) < 1e-3 and f"{p0['h']:.3f}".replace(".", ",") in hamma)
    tekshir("shtamp va katalogda tizim nomi va 'Boltiq 1977'", all("SINOV MSK" in s and "Boltiq 1977" in s for s in sah))
    tekshir("hamma shart bajarilgan: har varaqda TOPSHIRISHGA YAROQLI", all("TOPSHIRISHGA YAROQLI" in s for s in sah)
            and m["yaroqlilik"]["yaroqli"], str(m["yaroqlilik"]))
    tekshir("geodezik asos varag'i: punkt katalogi, qoldiqlar, ish kunlari",
            "Geodezik asos punktlari" in hamma and f"{pk[0]['X']:.3f}".replace(".", ",") in hamma
            and "Ish kunlari nazorati" in hamma and "tekshirilgan" in hamma)

    lin2, _ = ijro.planar_liniyalar([baza_liniyasi(1, "suv", 160, yolak, sifat="SKAN",
                                                   vaqt="2026-10-04T06:00:00+00:00")], tizim["lok"])
    asos2 = dict(asos, kunlar=L.kunlik_nazorat({"2026-10-04"}, tek, olch, True))
    m2, N2, sah2 = hujjat(lin2, asos2, "SINOV: tekshiruvsiz kun (sun'iy)")
    tekshir("tekshiruvsiz kun va SKAN nuqtalar: YAROQSIZ, ikkala sabab yozilgan",
            not m2["yaroqlilik"]["yaroqli"] and any("tekshiruv o'lchovisiz" in x for x in m2["yaroqlilik"]["sabablar"])
            and any("RASMIY emas" in x for x in m2["yaroqlilik"]["sabablar"]) and "TOPSHIRISHGA YAROQSIZ" in sah2[0],
            str(m2["yaroqlilik"]))
    uzoq = [(LAT0 + 0.02 + 0.0001 * i, LON0, 360.0) for i in range(3)]
    lin3, _ = ijro.planar_liniyalar([baza_liniyasi(1, "suv", 160, uzoq)], tizim["lok"])
    m3, _, _ = hujjat(lin3, asos, "SINOV: qamrovdan tashqari (sun'iy)")
    tekshir("punktlar qamrovidan 2 km tashqaridagi liniya: ekstrapolyatsiya sababi",
            any("ekstrapolyatsiya" in x for x in m3["yaroqlilik"]["sabablar"]), str(m3["yaroqlilik"]))

    # ---------- LK-07: UTM dagi loyiha mahalliy hujjatga ----------
    ue, un, _ = chizma.utm(yolak[3][0], yolak[3][1], 42)
    loy = {"koordinata": "utm", "z_tizimi": "ellipsoid", "z_turi": "oq", "chiziqlar": [{"qatlam": "L",
           "nuqtalar": [[ue, un, 350.0], [ue + 5, un, 350.0]]}]}
    mloy, _ = ijro.loyiha_tizimga(loy, tizim)
    Xl, Yl, Hl = tizim["lok"].oldinga(yolak[3][0], yolak[3][1], 350.0)
    v0 = mloy["chiziqlar"][0]["nuqtalar"][0]
    tekshir("UTM loyiha → mahalliy: cho'qqi to'g'ridan-to'g'ri hisob bilan ≤ 1 mm, Z Boltiqqa o'tdi",
            abs(v0[0] - Yl) < 1e-3 and abs(v0[1] - Xl) < 1e-3 and abs(v0[2] - Hl) < 1e-3 and mloy["z_mos"])
    mloy2, izoh2 = ijro.loyiha_tizimga({"koordinata": "mahalliy", "z_tizimi": "boltiq", "chiziqlar": []},
                                       ijro.tizim_tanla(None, 42))
    tekshir("mahalliy loyiha, lokalizatsiya yo'q: hujjatga qo'yilmaydi, izohi bor", mloy2 is None and "lokalizatsiya" in izoh2)

    # ---------- LK-08: topoplan DXF ----------
    topo_dxf = ("0\nSECTION\n2\nENTITIES\n"
                "0\nTEXT\n8\nYOZUV\n10\n54500.5\n20\n5200.25\n40\n2.5\n50\n15\n1\nMustaqillik ko\\U+0447.\n"
                "0\nMTEXT\n8\nYOZUV\n10\n54510\n20\n5210\n40\n1.8\n1\n{\\fArial|b1;Uy}\\P12A\n"
                "0\nLWPOLYLINE\n8\nBINO\n90\n4\n70\n1\n10\n54490\n20\n5190\n10\n54495\n20\n5190\n10\n54495\n20\n5195\n10\n54490\n20\n5195\n"
                "0\nENDSEC\n0\nEOF\n")
    tp = geo.dxf_topo_oqi(topo_dxf)
    tekshir("topoplan: TEXT (\\U+ kirill), MTEXT formatlashsiz, yopiq bino konturi",
            tp["matnlar"][0]["matn"] == "Mustaqillik koч." and tp["matnlar"][0]["burchak"] == 15.0
            and tp["matnlar"][1]["matn"] == "Uy 12A" and len(tp["chiziqlar"][0]["nuqtalar"]) == 5, str(tp)[:300])
    try:
        geo.dxf_oqi("0\nSECTION\n2\nENTITIES\n0\nLINE\n8\n0\n10\n54500\n20\n5200\n11\n54510\n21\n5200\n0\nENDSEC\n")
        tekshir("mahalliy koordinatali loyiha utm=True da rad etiladi", False)
    except geo.DXFXato as x:
        tekshir("mahalliy koordinatali loyiha utm=True da rad etiladi, xabar lokalizatsiyani taklif qiladi",
                "lokalizatsiya" in str(x))
    tekshir("utm=False — mahalliy loyiha o'qiladi",
            len(geo.dxf_oqi("0\nSECTION\n2\nENTITIES\n0\nLINE\n8\n0\n10\n54500\n20\n5200\n11\n54510\n21\n5200\n0\nENDSEC\n",
                            utm=False)) == 1)
finally:
    shutil.rmtree(TMP, ignore_errors=True)

yiq = sum(1 for _, ok in natijalar if not ok)
print(f"\nJAMI: {len(natijalar)} tekshiruv, {yiq} FAIL")
sys.exit(1 if yiq else 0)
