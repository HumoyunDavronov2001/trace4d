"""DM-05 zaxira sinovi — FAQAT vaqtinchalik papkada (haqiqiy yerosti.db ga tegmaydi).

Yaratish → tekshirish → qattiq havola (dedup) → tiklash → tiklangan bazada server ishlaydi → buzilgan zaxira ushlanadi.
Ishga tushirish:  python3 sinov/zaxira_sinov.py
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

YEROSTI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP = tempfile.mkdtemp(prefix="yerosti_zaxira_")
os.environ.update(YEROSTI_BAZA=os.path.join(TMP, "asl", "yerosti.db"), YEROSTI_SKANLAR=os.path.join(TMP, "asl", "skanlar"))
os.makedirs(os.path.join(TMP, "asl"))
sys.path.insert(0, YEROSTI)
import yerosti_baza as baza  # noqa: E402  (muhit o'zgaruvchilaridan keyin)
import zaxira  # noqa: E402

natijalar = []


def tekshir(nom, shart, izoh=""):
    natijalar.append(bool(shart))
    print(("PASS " if shart else "FAIL ") + nom + (f"  [{izoh}]" if izoh and not shart else ""))


srv = None
try:
    baza.init()
    baza.foydalanuvchi_yarat("admin", "Zaxira-Sinov-1", rol="admin")
    oid = baza.obyekt_yarat("Zaxira sinovi obyekti")
    data = os.urandom(300_000)
    s = baza.skan_boshla(oid, "nuqta_ply", len(data), hashlib.sha256(data).hexdigest())
    baza.skan_bolak_yoz(s["skan_id"], 0, data, hashlib.sha256(data).hexdigest())
    baza.skan_yakunla(s["skan_id"])
    os.makedirs(os.path.join(baza.SKAN_PAPKA, "tahlil", "1"))
    with open(os.path.join(baza.SKAN_PAPKA, "tahlil", "1", "natija.json"), "w") as f:
        f.write('{"xulosa":"MOS"}')
    with open(os.path.join(baza.SKAN_PAPKA, ".ishchi_yurak"), "w") as f:
        f.write("1")

    ildiz = os.path.join(TMP, "zaxira")
    z1 = zaxira.yarat(ildiz)
    tekshir("zaxira yaratildi va atomik nomlandi", os.path.isdir(z1) and not os.path.exists(z1 + ".yarim"))
    tekshir("zaxira butun (xeshlar + integrity_check)", zaxira.tekshir(z1) == [], str(zaxira.tekshir(z1)))
    m = open(os.path.join(z1, "MANIFEST.sha256")).read()
    tekshir("manifestda baza, skan va tahlil fayllari; xizmat fayli (.ishchi_yurak) yo'q",
            "  yerosti.db" in m and f"skanlar/{s['skan_id']}.ply" in m and "tahlil/1/natija.json" in m and ".ishchi_yurak" not in m)
    info = json.load(open(os.path.join(z1, "zaxira.json")))
    tekshir("zaxira.json: jadval sonlari", info["jadvallar"].get("obyekt") == 1 and info["jadvallar"].get("skan") == 1, str(info))

    z2 = zaxira.yarat(ildiz)
    f1, f2 = (os.path.join(z, "skanlar", f"{s['skan_id']}.ply") for z in (z1, z2))
    tekshir("ikkinchi zaxirada o'zgarmagan skan qattiq havola (disk qayta sarflanmaydi)",
            z1 != z2 and os.stat(f1).st_ino == os.stat(f2).st_ino, f"{z1} {z2}")
    tekshir("ikkinchi zaxira ham butun", zaxira.tekshir(z2) == [])

    # tiklash → tiklangan bazada server ishlaydi
    tb, ts = os.path.join(TMP, "tiklangan", "yerosti.db"), os.path.join(TMP, "tiklangan", "skanlar")
    zaxira.tikla(z2, tb, ts)
    tekshir("tiklangan skan fayli asl nusxa bilan bir xil",
            hashlib.sha256(open(os.path.join(ts, f"{s['skan_id']}.ply"), "rb").read()).hexdigest() == hashlib.sha256(data).hexdigest())
    try:
        zaxira.tikla(z2, tb, ts)
        tekshir("band maqsadga --majburiy siz tiklash rad etiladi", False)
    except SystemExit:
        tekshir("band maqsadga --majburiy siz tiklash rad etiladi", True)
    port = int(os.environ.get("SINOV_PORT", "8349"))
    env = dict(os.environ, YEROSTI_BAZA=tb, YEROSTI_SKANLAR=ts)
    srv = subprocess.Popen([sys.executable, "-u", "yerosti_server.py", "--port", str(port)], cwd=YEROSTI, env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ok = None
    for _ in range(60):
        try:
            ok = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{port}/api/v1/salomatlik", timeout=1).read())
            break
        except Exception:
            time.sleep(0.1)
    tekshir("tiklangan bazada server sog' (salomatlik ok)", ok and ok.get("holat") == "ok", str(ok))
    r = urllib.request.Request(f"http://127.0.0.1:{port}/api/v1/kirish", method="POST",
                               data=json.dumps({"login": "admin", "parol": "Zaxira-Sinov-1"}).encode(),
                               headers={"Content-Type": "application/json", "X-Yerosti": "1"})
    j = urllib.request.urlopen(r, timeout=5)
    kuki = j.headers.get("Set-Cookie", "").split(";")[0]
    r = urllib.request.Request(f"http://127.0.0.1:{port}/api/v1/obyektlar", headers={"Cookie": kuki, "X-Yerosti": "1"})
    ob = json.loads(urllib.request.urlopen(r, timeout=5).read())["obyektlar"]
    tekshir("tiklangan bazada asl parol bilan kirish va obyekt bor", [o["nomi"] for o in ob] == ["Zaxira sinovi obyekti"], str(ob))

    # buzilgan zaxira ushlanadi (teskari isbot)
    buzuq = os.path.join(TMP, "buzuq")
    shutil.copytree(z2, buzuq)
    with open(os.path.join(buzuq, "skanlar", "tahlil", "1", "natija.json"), "a") as f:
        f.write(" ")
    tekshir("bitta bayt qo'shilgan zaxira BUZILGAN deb topiladi", any("xesh mos emas" in x for x in zaxira.tekshir(buzuq)))
    with open(os.path.join(buzuq, "begona.txt"), "w") as f:
        f.write("x")
    tekshir("manifestdan tashqari fayl ham ushlanadi", any("manifestda yo'q" in x for x in zaxira.tekshir(buzuq)))
    try:
        zaxira.tikla(buzuq, os.path.join(TMP, "t2", "y.db"), os.path.join(TMP, "t2", "s"))
        tekshir("buzilgan zaxiradan tiklash rad etiladi", False)
    except SystemExit:
        tekshir("buzilgan zaxiradan tiklash rad etiladi", True)

    tekshir("tozalash: faqat oxirgi 1 ta qoladi", zaxira.tozala(ildiz, 1) == 1 and zaxira.zaxiralar(ildiz) == [z2])
    tekshir("qolgan zaxira hali ham butun (qattiq havola o'chirilganda ma'lumot yo'qolmaydi)", zaxira.tekshir(z2) == [])
finally:
    if srv:
        srv.terminate()
        srv.wait(timeout=5)
    shutil.rmtree(TMP, ignore_errors=True)

yiq = natijalar.count(False)
print(f"\nJAMI: {len(natijalar)} tekshiruv, {yiq} FAIL")
sys.exit(1 if yiq else 0)
