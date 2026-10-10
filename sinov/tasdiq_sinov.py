"""YEROSTI — quvur tasdig'i sinovi (TALABLAR 18: TQ-02…TQ-06). Bazasiz, sof funksiyalar.
Geometriya SUN'IY. Ishga tushirish: python3 sinov/tasdiq_sinov.py"""
import os
import sys

YEROSTI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, YEROSTI)
import yerosti_tasdiq as T  # noqa: E402

natijalar = []


def tekshir(nom, shart, izoh=""):
    natijalar.append((nom, bool(shart)))
    print(("PASS " if shart else "FAIL ") + nom + (f"  [{izoh}]" if (izoh and not shart) else ""))


LAT0, LON0 = 40.1151, 67.8421
k = T.enu(LAT0, LON0)
M_LAT, M_LON = k(LAT0 + 0.001, LON0 + 0.001)[1] / 0.001, k(LAT0, LON0 + 0.001)[0] / 0.001


def ll(e, n):
    return LAT0 + n / M_LAT, LON0 + e / M_LON


def liniya(lid, pts, manba="skan", d=160):
    nq = []
    for i, (e, n, h) in enumerate(pts):
        la, lo = ll(e, n)
        nq.append({"id": lid * 100 + i, "lat": la, "lon": lo, "balandlik": h, "chuqurlik_m": 1.5,
                   "sifat": "SKAN" if manba == "skan" else "RASMIY", "manba": manba, "sigma_h_sm": 1.0, "rtk_holat": "FIX"})
    return {"id": lid, "turi": "suv", "diametr_mm": d, "material": "PE100", "nuqtalar": nq}


def tasdiq(tid, e, n, h, joy="usti", liniya_id=None):
    la, lo = ll(e, n)
    return {"id": tid, "nomi": f"T{tid}", "lat": la, "lon": lo, "h": h, "joy": joy, "liniya_id": liniya_id}


try:
    # L shaklli skan o'qi: (0,0)→(30,0)→(30,30), h 100, D160 (radius 0,08); Swift sinovi bilan bir xil raqamlar
    L = liniya(1, [(0, 0, 100.0), (30, 0, 100.0), (30, 30, 100.0)])
    lp = T._planar(L, k)
    b = T.baholash(lp, {"e": 10, "n": 0.03, "h": 100.10, "joy": "usti"})
    tekshir("TQ-02: stansiya 10 m, gorizontal 3 sm, vertikal +2 sm (usti = o'q + 8 sm) — o'tdi",
            abs(b["stansiya"] - 10) < 1e-6 and abs(b["d_gor"] - 0.03) < 1e-6 and abs(b["d_ver"] - 0.02) < 1e-6 and b["otdi"], str(b))
    c = T.baholash(lp, {"e": 30, "n": 30.2, "h": 100.0, "joy": "oq"})
    tekshir("TQ-02: oxiridan 20 sm tashqarida — oxiriga bog'lanadi, gorizontal 20 sm > 5 — o'tmadi",
            abs(c["stansiya"] - 60) < 1e-6 and abs(c["d_gor"] - 0.2) < 1e-6 and not c["otdi"] and "gorizontal" in c["sabab"], str(c))
    d = T.baholash(lp, {"e": 5, "n": 0.01, "h": 100.20, "joy": "usti"})
    tekshir("TQ-02: vertikal +12 sm > 8 — o'tmadi, sababda vertikal", not d["otdi"] and "vertikal" in d["sabab"], str(d))
    e_ = T.baholash(lp, {"e": 5, "n": 0.01, "h": None, "joy": "usti"})
    tekshir("TQ-02: tasdiq balandligi yo'q — faqat gorizontal baholanadi, izoh yoziladi",
            e_["otdi"] and e_["d_ver"] is None and "solishtirilmadi" in e_["sabab"], str(e_))
    tekshir("TQ-04: kerakli nuqtalar — boshi, burilish 30 m, oxiri 60 m",
            [(t, round(s, 3)) for t, s in T.kerakli_nuqtalar(lp)] == [("bosh", 0.0), ("burilish", 30.0), ("oxir", 60.0)],
            str(T.kerakli_nuqtalar(lp)))

    # hisobla: boshi va oxiri tasdiqlangan — qisman (burilish yo'q); burilish qo'shilsa — tasdiqlangan
    n = T.hisobla([L], [tasdiq(1, 0.2, 0, 100.08), tasdiq(2, 30, 29.9, 100.08)])
    h1 = n["liniyalar"][1]
    tekshir("TQ-05: 2 tasdiq (boshi, oxiri): qisman — burilish PK0+30 yo'q va oraliq 60 m > 50",
            h1["holat"] == "qisman" and len(h1["kamchiliklar"]) == 2 and "burilish (PK0+30,00)" in h1["kamchiliklar"][0]
            and "> 50 m" in h1["kamchiliklar"][1]
            and all(t["liniya_id"] == 1 and t["otdi"] for t in n["tasdiqlar"]), str(h1))
    n = T.hisobla([L], [tasdiq(1, 0.2, 0, 100.08), tasdiq(2, 30, 29.9, 100.08), tasdiq(3, 30.02, 0.3, 100.08)])
    tekshir("TQ-05: burilish ham tasdiqlandi — tasdiqlangan, pikitaj yoziladi",
            n["liniyalar"][1]["holat"] == "tasdiqlangan" and n["tasdiqlar"][2]["pk"] == "PK0+30,30", str(n["liniyalar"][1]))
    tekshir("tasdiqlangan() yordamchisi", T.tasdiqlangan(n["liniyalar"], 1) and not T.tasdiqlangan(n["liniyalar"], 9))
    n = T.hisobla([L], [tasdiq(1, 0.2, 0, 100.08), tasdiq(2, 30, 29.9, 100.08), tasdiq(3, 30.02, 0.3, 100.08),
                        tasdiq(4, 15, 0.4, 100.08)])
    tekshir("TQ-05: bitta tasdiq 40 sm chetda — FARQ, o'tgan 3/4",
            n["liniyalar"][1]["holat"] == "farq" and n["liniyalar"][1]["otgan"] == 3 and n["liniyalar"][1]["soni"] == 4, str(n["liniyalar"][1]))
    n = T.hisobla([L], [tasdiq(5, 15, 3.0, 100.08)])
    tekshir("TQ-03: liniyadan 3 m uzoq tasdiq hech qaysi liniyaga tegishli emas (sabab bilan), liniya 'yo'q'",
            n["tasdiqlar"][0]["liniya_id"] is None and "liniya yo'q" in n["tasdiqlar"][0]["sabab"] and n["liniyalar"][1]["holat"] == "yoq",
            str(n["tasdiqlar"][0]))
    R = liniya(2, [(100, 0, 100.0), (120, 0, 100.0)], manba="rtk")
    n = T.hisobla([L, R], [tasdiq(6, 110, 0.01, 100.08)])
    tekshir("TQ-05: RTK liniya tasdiqsiz — 'rtk' (shart emas); tasdiq eng yaqin liniyaga (#2) bog'lanadi",
            n["liniyalar"][2]["holat"] in ("rtk", "tasdiqlangan", "qisman") and n["tasdiqlar"][0]["liniya_id"] == 2
            and T.hisobla([L, R], [])["liniyalar"][2]["holat"] == "rtk", str(n["liniyalar"]))
    n = T.hisobla([L], [tasdiq(7, 10, 0.02, 100.08, liniya_id=1)])
    tekshir("TQ-03: liniya_id ko'rsatilgan tasdiq shu liniyaga bog'lanadi", n["tasdiqlar"][0]["liniya_id"] == 1)

    # 120 m to'g'ri: boshi va oxiri — oraliq 120 > 50; o'rtasi qo'shilsa — tasdiqlangan (G.1.1)
    U = liniya(3, [(0, 0, 50.0), (120, 0, 50.0)], d=200)
    n = T.hisobla([U], [tasdiq(1, 0, 0, 50.1), tasdiq(2, 120, 0, 50.1)])
    tekshir("TQ-04: 120 m da faqat uchlari — qisman, '120 m > 50 m'",
            n["liniyalar"][3]["holat"] == "qisman" and any("120 m > 50 m" in x for x in n["liniyalar"][3]["kamchiliklar"]),
            str(n["liniyalar"][3]))
    n = T.hisobla([U], [tasdiq(1, 0, 0, 50.1), tasdiq(2, 120, 0, 50.1), tasdiq(3, 60, 0.02, 50.1)])
    tekshir("TQ-04: o'rtasi qo'shildi, oraliq 60 m — hali qisman", n["liniyalar"][3]["holat"] == "qisman", str(n["liniyalar"][3]))
    n = T.hisobla([U], [tasdiq(1, 0, 0, 50.1), tasdiq(2, 120, 0, 50.1), tasdiq(3, 40, 0.02, 50.1), tasdiq(4, 80, 0, 50.1)])
    tekshir("TQ-04: har 40 m — tasdiqlangan", n["liniyalar"][3]["holat"] == "tasdiqlangan", str(n["liniyalar"][3]))
    tekshir("liniyasiz obyekt: tasdiqlar bog'lanmaydi, xato bermaydi",
            T.hisobla([], [tasdiq(1, 0, 0, 1)])["tasdiqlar"][0]["liniya_id"] is None)

    # TQ-06: CSV
    emlid = ("Name,Code,Description,Longitude,Latitude,Ellipsoidal height,Elevation RMS,Lateral RMS,Solution status,"
             "Averaging start,Averaging end,Samples\n"
             f"Q1,,,{LON0:.9f},{LAT0:.9f},100.08,0.012,0.008,FIX,2026-10-03 09:00:00.0 UTC+05:00,2026-10-03 09:00:06.0 UTC+05:00,6\n"
             f"Q2,oq,,{LON0:.9f},{LAT0:.9f},100.00,0.012,0.008,FIX,2026-10-03 09:01:00.0 UTC+05:00,2026-10-03 09:01:05.0 UTC+05:00,5\n")
    q, x = T.csv_oqi(emlid)
    tekshir("TQ-06: Emlid CSV — 2 qator, σ sm da, davomiylik 6 s, kod «oq» → joy oq",
            len(q) == 2 and not x and abs(q[0]["sigma_h_sm"] - 0.8) < 1e-9 and abs(q[0]["davomiylik_s"] - 6) < 1e-9
            and q[0]["joy"] == "usti" and q[1]["joy"] == "oq" and q[0]["epoxalar"] == 6, str(q))
    q, x = T.csv_oqi("nomi;lat;lon;h\nA;40,1151;67,8421;100,08;0,9;1,5;usti\nB;40,1152;67,8422;100,10")
    tekshir("TQ-06: oddiy CSV (o'nlik vergul, sarlavha qatori tashlanadi)", len(q) == 2 and not x and q[0]["sigma_h_sm"] == 0.9
            and q[1]["sigma_h_sm"] is None, str(q) + str(x))
except Exception as ex:   # noqa: BLE001
    import traceback
    traceback.print_exc()
    natijalar.append((f"istisno: {ex}", False))

fail = [n for n, ok in natijalar if not ok]
print(f"\nJAMI: {len(natijalar)} tekshiruv, {len(fail)} FAIL")
sys.exit(1 if fail else 0)
