"""YEROSTI data markaz ishchisi (DM-02) — muhrlangan skanlarni MUSTAQIL qayta hisoblaydi.

Muhr TASDIQLANGAN bo'lgach server navbatga ish qo'yadi (tahlil_ish). Ishchi uni oladi va telefon bilan BIR XIL
Swift yadrosini (Linux CLI `yerosti-tahlil`) ishga tushiradi: zanjir, PLY xeshi, juftlar ↔ xom NMEA, georeferens,
quvurlar qayta aniqlanadi va telefon natijasi bilan solishtiriladi. Natija bazaga (MOS / FARQ / XATO), 3D ko'ruvchi
buluti tahlil papkasiga yoziladi.

    python3 yerosti_ishchi.py              # doimiy ish (docker: ishchi xizmati)
    python3 yerosti_ishchi.py --bir-marta  # navbatni bo'shatib chiqish (sinov)
"""
import argparse
import json
import os
import signal
import subprocess
import sys
import time

import yerosti_baza as baza

ILDIZ = os.path.dirname(os.path.abspath(__file__))
CLI = os.environ.get("YEROSTI_TAHLIL_CLI") or os.path.join(ILDIZ, "Yadro", ".build", "release", "yerosti-tahlil")
VAQT_CHEK_S = int(os.environ.get("YEROSTI_TAHLIL_VAQT_S", "900"))
YURAK = os.path.join(baza.SKAN_PAPKA, ".ishchi_yurak")
_toxta = False


def _signal(*_):
    global _toxta
    _toxta = True


def yurak_ur():
    """Sog'liq tekshiruvi uchun: ishchi tirik (server /api/v1/salomatlik shu faylning yoshini beradi)."""
    try:
        with open(YURAK, "w") as f:
            f.write(str(int(time.time())))
    except OSError:
        pass


def tashqi_tayyorla(ish, papka):
    """LD-02: tashqi LAS/PLY → UTM PLY (yerosti_las). Xato bo'lsa matn qaytaradi."""
    import yerosti_las as las
    import yerosti_lokal as lokal
    sk = baza.skan_top(ish["ply_skan_id"])
    yol = baza.skan_yoli(ish["ply_skan_id"])
    if not (sk and yol and os.path.isfile(yol)):
        return None, "tashqi fayl diskda yo'q"
    lok = None
    if ish.get("koordinata") == "mahalliy":
        lq = baza.lokalizatsiya_top(ish["obyekt_id"])
        if not (lq and lq["natija"]["parametrlar"].get("gor")):
            return None, "mahalliy koordinata: obyekt lokalizatsiyasi yo'q"
        lok = lokal.Lokalizatsiya(lq["natija"]["parametrlar"])
    with open(yol, "rb") as f:
        xom = f.read()
    try:
        ply, malumot = las.tayyorla(xom, "las" if sk["turi"] == "nuqta_las" else "ply", ish.get("koordinata") or "utm",
                                    ish.get("zona"), lok)
    except las.LASXato as x:
        return None, f"fayl o'qilmadi: {x}"
    chiqish = os.path.join(papka, "utm.ply")
    with open(chiqish, "wb") as f:
        f.write(ply)
    with open(os.path.join(papka, "kirish.json"), "w", encoding="utf-8") as f:
        json.dump(malumot, f, ensure_ascii=False)
    return (chiqish, malumot), ""


def bitta(ish):
    papka = baza.tahlil_papka(ish["id"])
    os.makedirs(papka, exist_ok=True)
    malumot = None
    natija_yol, korinish = os.path.join(papka, "natija.json"), os.path.join(papka, "korinish.ply")
    if ish.get("tur") == "farq":
        a, b = baza.tahlil_top(ish["farq_a_id"]), baza.tahlil_top(ish["farq_b_id"])
        if not (a and b):
            baza.tahlil_yakunla(ish["id"], "xato", xato="tahlillar topilmadi")
            return "xato"
        pa = os.path.join(baza.tahlil_papka(a["id"]), "korinish.ply")
        pb = os.path.join(baza.tahlil_papka(b["id"]), "korinish.ply")
        if not (os.path.isfile(pa) and os.path.isfile(pb)):
            baza.tahlil_yakunla(ish["id"], "xato", xato="ko'rinish buluti diskda yo'q")
            return "xato"

        def g(t):
            s = ((t.get("natija") or {}).get("georef") or {}).get("server") or {}
            return f"{s.get('burchak_grad', 0)},{s['t'][0]},{s['t'][1]},{s['t'][2]}" if s.get("t") else ""
        buyruq = [CLI, "farq", "--ply1", pa, "--ply2", pb, "--georef1", g(a), "--georef2", g(b), "--korinish", korinish,
                  "--chiqish", natija_yol]
    elif ish.get("tur") == "tashqi":
        t, xato = tashqi_tayyorla(ish, papka)
        if xato:
            baza.tahlil_yakunla(ish["id"], "xato", xato=xato)
            return "xato"
        ply, malumot = t
        buyruq = [CLI, "aniqla", "--ply", ply, "--zona", str(malumot["zona"]), "--korinish", korinish, "--chiqish", natija_yol]
        if ish.get("tarmoq_turi"):
            buyruq += ["--tarmoq", ish["tarmoq_turi"]]
    else:
        jurnal, ply = baza.skan_yoli(ish["jurnal_skan_id"]), baza.skan_yoli(ish["ply_skan_id"])
        if not (jurnal and ply and os.path.isfile(jurnal) and os.path.isfile(ply)):
            baza.tahlil_yakunla(ish["id"], "xato", xato="skan fayli diskda yo'q")
            return "xato"
        buyruq = [CLI, "tekshir", "--jurnal", jurnal, "--ply", ply, "--korinish", korinish, "--chiqish", natija_yol]
    try:
        r = subprocess.run(buyruq, capture_output=True, timeout=VAQT_CHEK_S, check=False)
    except subprocess.TimeoutExpired:
        baza.tahlil_yakunla(ish["id"], "xato", xato=f"vaqt chegarasi {VAQT_CHEK_S} s")
        return "xato"
    except OSError as x:
        baza.tahlil_yakunla(ish["id"], "xato", xato=f"yerosti-tahlil ishga tushmadi: {x}")
        return "xato"
    if r.returncode != 0:
        baza.tahlil_yakunla(ish["id"], "xato", xato=r.stderr.decode("utf-8", "replace")[-1000:] or f"kod {r.returncode}")
        return "xato"
    try:
        with open(natija_yol, encoding="utf-8") as f:
            n = json.load(f)
    except (OSError, ValueError) as x:
        baza.tahlil_yakunla(ish["id"], "xato", xato=f"natija o'qilmadi: {x}")
        return "xato"
    if ish.get("tur") == "tashqi" and malumot:
        n["kirish"] = malumot
    if ish.get("tur") == "farq":
        # M3C2 xulosasi yadroda (o'zgarish dog'i ≥ 25 yadro nuqta yoki ahamiyatli ulush > 5 %); eski CLI — faqat ulush
        if n.get("xulosa") not in ("OZGARISH", "OZGARMAGAN"):
            ulush = (n.get("ahamiyatli") or 0) / max(n.get("baholangan") or 1, 1)
            n["xulosa"] = "OZGARISH" if ulush > 0.05 else "OZGARMAGAN"
            n["ahamiyatli_ulush"] = round(ulush, 4)
        n["farq_a"], n["farq_b"] = ish["farq_a_id"], ish["farq_b_id"]
    baza.tahlil_yakunla(ish["id"], "tayyor", n.get("xulosa"), json.dumps(n, ensure_ascii=False))
    if ish.get("tur") == "tashqi" and n.get("quvurlar"):
        try:
            idlar = baza.tashqi_liniyalar_yarat(ish, n)
            print(f"[ishchi] tashqi #{ish['id']}: {len(idlar)} ta SKAN liniya yaratildi", flush=True)
        except (ValueError, TypeError) as x:
            baza.tahlil_yakunla(ish["id"], "tayyor", n.get("xulosa"), json.dumps(n, ensure_ascii=False),
                                xato=f"liniya yaratilmadi: {x}")
    return n.get("xulosa")


def main():
    p = argparse.ArgumentParser(description="TRACE4D qayta hisob ishchisi (DM-02)")
    p.add_argument("--bir-marta", action="store_true", help="navbatni bo'shatib chiqish")
    a = p.parse_args()
    baza.init()
    signal.signal(signal.SIGTERM, _signal)
    signal.signal(signal.SIGINT, _signal)
    if not os.path.isfile(CLI):
        print(f"[ishchi] DIQQAT: {CLI} topilmadi — `swift build -c release --product yerosti-tahlil`", file=sys.stderr)
    oxirgi_tekshiruv = 0.0
    while not _toxta:
        yurak_ur()
        if time.time() - oxirgi_tekshiruv > 60:
            qaytgan = baza.tahlil_osilganlar()
            if qaytgan:
                print(f"[ishchi] {qaytgan} ta osilgan ish navbatga qaytdi", flush=True)
            oxirgi_tekshiruv = time.time()
        ish = baza.tahlil_ol()
        if not ish:
            if a.bir_marta:
                break
            time.sleep(2)
            continue
        t0 = time.time()
        x = bitta(ish)
        print(f"[ishchi] tahlil #{ish['id']} ({'tashqi ' + str(ish.get('manba_nomi') or '') if ish.get('tur') == 'tashqi' else 'muhr #' + str(ish['muhr_id'])}): "
              f"{x} · {time.time() - t0:.1f} s", flush=True)


if __name__ == "__main__":
    main()
