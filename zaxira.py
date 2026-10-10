"""YEROSTI zaxira (DM-05): baza (SQLite onlayn zaxira) + skan fayllari + SHA-256 manifest.

    python3 zaxira.py yarat  --papka /zaxira           # bitta zaxira
    python3 zaxira.py tekshir /zaxira/yerosti-20260927-020000
    python3 zaxira.py tikla  /zaxira/yerosti-20260927-020000 --baza /malumot/yerosti.db --skanlar /malumot/skanlar
    python3 zaxira.py davriy --papka /zaxira --soat 24 --saqlash 14   # docker: zaxira xizmati

Qoidalar:
* baza sqlite3 `backup()` bilan olinadi — server ishlab turganda ham izchil nusxa (WAL bilan);
* skan fayllari o'zgarmaydi (yuklangach faqat o'qiladi): oldingi zaxiradagi bir xil fayl (hajm + mtime) QATTIQ HAVOLA
  bilan ulanadi — har kungi to'liq surat, disk esa faqat yangi fayllarga sarflanadi;
* zaxira avval `<nom>.yarim` papkada yig'iladi va oxirida atomik nomlanadi — yarim zaxira hech qachon tayyor ko'rinmaydi;
* `tekshir` barcha xeshlarni QAYTA hisoblaydi va bazada `PRAGMA integrity_check` qiladi; `tikla` avval tekshiradi.
"""
import argparse
import hashlib
import json
import os
import shutil
import signal
import sqlite3
import sys
import time
from datetime import datetime, timezone

import yerosti_baza as baza

XIZMAT_FAYLLARI = {"MANIFEST.sha256", "fayllar.json", "zaxira.json"}
_toxta = False


def _sha(yol):
    h = hashlib.sha256()
    with open(yol, "rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()


def zaxiralar(ildiz):
    """Tayyor zaxiralar (eski → yangi)."""
    if not os.path.isdir(ildiz):
        return []
    return sorted(os.path.join(ildiz, n) for n in os.listdir(ildiz)
                  if n.startswith("yerosti-") and not n.endswith(".yarim") and os.path.isdir(os.path.join(ildiz, n)))


def yarat(ildiz):
    os.makedirs(ildiz, exist_ok=True)
    nom = "yerosti-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    papka, k = os.path.join(ildiz, nom), 1
    while os.path.exists(papka):          # bir soniyada ikkinchi zaxira
        k += 1
        papka = os.path.join(ildiz, f"{nom}-{k}")
    yarim = papka + ".yarim"
    shutil.rmtree(yarim, ignore_errors=True)
    os.makedirs(os.path.join(yarim, "skanlar"))

    # 1) baza — onlayn zaxira
    manba = sqlite3.connect(baza.BAZA_YOL)
    nusxa = sqlite3.connect(os.path.join(yarim, "yerosti.db"))
    with nusxa:
        manba.backup(nusxa)
    # nusxa asl bazadan WAL bayrog'ini oladi — ochilganda yonida -wal/-shm paydo bo'lib, manifestni buzardi
    nusxa.execute("PRAGMA journal_mode=DELETE")
    jadvallar = {r[0]: nusxa.execute(f'SELECT COUNT(*) FROM "{r[0]}"').fetchone()[0]
                 for r in nusxa.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")}
    manba.close()
    nusxa.close()

    # 2) skan fayllari — oldingi zaxiradan qattiq havola yoki nusxa
    oldingi = zaxiralar(ildiz)
    eski = {}
    if oldingi:
        try:
            with open(os.path.join(oldingi[-1], "fayllar.json"), encoding="utf-8") as f:
                eski = json.load(f)
        except (OSError, ValueError):
            eski = {}
    fayllar, havola, nusxalandi = {}, 0, 0
    for ildiz_s, papkalar, nomlar in os.walk(baza.SKAN_PAPKA):
        papkalar[:] = sorted(p for p in papkalar if not p.startswith("."))
        for n in sorted(nomlar):
            if n.startswith(".") or n.endswith(".yarim"):
                continue
            manba_f = os.path.join(ildiz_s, n)
            nisbiy = os.path.relpath(manba_f, baza.SKAN_PAPKA)
            st = os.stat(manba_f)
            maqsad = os.path.join(yarim, "skanlar", nisbiy)
            os.makedirs(os.path.dirname(maqsad), exist_ok=True)
            e = eski.get(nisbiy)
            if e and e["hajm"] == st.st_size and e["mtime_ns"] == st.st_mtime_ns:
                try:
                    os.link(os.path.join(oldingi[-1], "skanlar", nisbiy), maqsad)
                    fayllar[nisbiy] = e
                    havola += 1
                    continue
                except OSError:
                    pass
            shutil.copy2(manba_f, maqsad)
            fayllar[nisbiy] = {"hajm": st.st_size, "mtime_ns": st.st_mtime_ns, "sha256": _sha(maqsad)}
            nusxalandi += 1

    # 3) manifest — sha256sum formatida (tashqi vosita bilan ham tekshiriladi: `sha256sum -c MANIFEST.sha256`)
    qatorlar = [f"{_sha(os.path.join(yarim, 'yerosti.db'))}  yerosti.db"]
    qatorlar += [f"{m['sha256']}  skanlar/{n}" for n, m in sorted(fayllar.items())]
    with open(os.path.join(yarim, "MANIFEST.sha256"), "w", encoding="utf-8") as f:
        f.write("\n".join(qatorlar) + "\n")
    with open(os.path.join(yarim, "fayllar.json"), "w", encoding="utf-8") as f:
        json.dump(fayllar, f, ensure_ascii=False, sort_keys=True)
    with open(os.path.join(yarim, "zaxira.json"), "w", encoding="utf-8") as f:
        json.dump({"vaqt": baza.hozir(), "jadvallar": jadvallar, "fayllar": len(fayllar), "havola": havola,
                   "nusxa": nusxalandi, "hajm_bayt": sum(m["hajm"] for m in fayllar.values())}, f, ensure_ascii=False, indent=1)
    os.rename(yarim, papka)
    return papka


def tekshir(papka):
    """Muammolar ro'yxati (bo'sh — zaxira butun)."""
    muammo = []
    manifest = os.path.join(papka, "MANIFEST.sha256")
    if not os.path.isfile(manifest):
        return ["MANIFEST.sha256 yo'q"]
    royxat = set()
    with open(manifest, encoding="utf-8") as f:
        for q in f:
            q = q.rstrip("\n")
            if not q:
                continue
            sha, nisbiy = q.split("  ", 1)
            royxat.add(nisbiy)
            yol = os.path.join(papka, nisbiy)
            if not os.path.isfile(yol):
                muammo.append(f"yo'q: {nisbiy}")
            elif _sha(yol) != sha:
                muammo.append(f"xesh mos emas: {nisbiy}")
    for ildiz_s, _, nomlar in os.walk(papka):
        for n in nomlar:
            nisbiy = os.path.relpath(os.path.join(ildiz_s, n), papka)
            if nisbiy not in royxat and nisbiy not in XIZMAT_FAYLLARI:
                muammo.append(f"manifestda yo'q fayl: {nisbiy}")
    db = os.path.join(papka, "yerosti.db")
    if os.path.isfile(db):
        u = sqlite3.connect(f"file:{db}?mode=ro&immutable=1", uri=True)   # zaxiraga hech narsa yozilmaydi
        natija = u.execute("PRAGMA integrity_check").fetchone()[0]
        u.close()
        if natija != "ok":
            muammo.append(f"baza butun emas: {natija}")
    return muammo


def tikla(papka, baza_yol, skan_papka, majburiy=False):
    muammo = tekshir(papka)
    if muammo:
        raise SystemExit("zaxira buzilgan, tiklanmaydi:\n  " + "\n  ".join(muammo))
    band = os.path.exists(baza_yol) or (os.path.isdir(skan_papka) and os.listdir(skan_papka))
    if band and not majburiy:
        raise SystemExit("maqsad bo'sh emas — ustiga yozish uchun --majburiy (avval serverni to'xtating)")
    os.makedirs(os.path.dirname(os.path.abspath(baza_yol)), exist_ok=True)
    for qoshimcha in ("", "-wal", "-shm"):
        if os.path.exists(baza_yol + qoshimcha):
            os.remove(baza_yol + qoshimcha)
    manba = sqlite3.connect(f"file:{os.path.join(papka, 'yerosti.db')}?mode=ro&immutable=1", uri=True)
    maqsad = sqlite3.connect(baza_yol)
    with maqsad:
        manba.backup(maqsad)
    manba.close()
    maqsad.close()
    if os.path.isdir(skan_papka):
        shutil.rmtree(skan_papka)
    shutil.copytree(os.path.join(papka, "skanlar"), skan_papka)


def tozala(ildiz, saqlash):
    bor = zaxiralar(ildiz)
    ortiqcha = bor[:-saqlash] if saqlash > 0 else []
    for p in ortiqcha:
        shutil.rmtree(p)
    for n in os.listdir(ildiz):   # qulagan urinishlardan qolgan yarim zaxiralar
        yol = os.path.join(ildiz, n)
        if n.endswith(".yarim") and time.time() - os.path.getmtime(yol) > 6 * 3600:
            shutil.rmtree(yol, ignore_errors=True)
    return len(ortiqcha)


def _signal(*_):
    global _toxta
    _toxta = True


def main():
    p = argparse.ArgumentParser(description="YEROSTI zaxira (DM-05)")
    q = p.add_subparsers(dest="buyruq", required=True)
    a = q.add_parser("yarat"); a.add_argument("--papka", required=True)
    a = q.add_parser("tekshir"); a.add_argument("zaxira")
    a = q.add_parser("tikla"); a.add_argument("zaxira"); a.add_argument("--baza", required=True)
    a.add_argument("--skanlar", required=True); a.add_argument("--majburiy", action="store_true")
    a = q.add_parser("davriy"); a.add_argument("--papka", required=True)
    a.add_argument("--soat", type=float, default=float(os.environ.get("YEROSTI_ZAXIRA_SOAT", "24")))
    a.add_argument("--saqlash", type=int, default=int(os.environ.get("YEROSTI_ZAXIRA_SAQLASH", "14")))
    x = p.parse_args()
    if x.buyruq == "yarat":
        print(yarat(x.papka))
    elif x.buyruq == "tekshir":
        m = tekshir(x.zaxira)
        print("zaxira butun" if not m else "MUAMMO:\n  " + "\n  ".join(m))
        sys.exit(1 if m else 0)
    elif x.buyruq == "tikla":
        tikla(x.zaxira, x.baza, x.skanlar, x.majburiy)
        print("tiklandi")
    else:
        signal.signal(signal.SIGTERM, _signal)
        signal.signal(signal.SIGINT, _signal)
        while not _toxta:
            try:
                z = yarat(x.papka)
                print(f"[zaxira] {z} · o'chirildi: {tozala(x.papka, x.saqlash)}", flush=True)
            except Exception as e:  # noqa: BLE001 — xizmat to'xtamasin, keyingi urinishda yana
                print(f"[zaxira] XATO: {e}", file=sys.stderr, flush=True)
            kutish = time.time() + x.soat * 3600
            while not _toxta and time.time() < kutish:
                time.sleep(5)


if __name__ == "__main__":
    main()
