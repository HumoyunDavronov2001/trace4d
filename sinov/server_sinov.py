"""YEROSTI server — uchma-uch regressiya sinovi.

Vaqtinchalik papkada ALOHIDA baza va skan papkasi bilan ishlaydi (YEROSTI_BAZA / YEROSTI_SKANLAR),
haqiqiy yerosti.db ga tegmaydi; oxirida vaqtinchalik papka o'chiriladi.
Ishga tushirish:  python3 sinov/server_sinov.py
"""
import base64
import hashlib
import http.client
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

YEROSTI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = int(os.environ.get("SINOV_PORT", "8345"))
TMP = tempfile.mkdtemp(prefix="yerosti_sinov_")


def png_1x1(rang):
    """Eng kichik to'g'ri PNG (1×1) — plitka mazmuni muhim emas, bayt-baybayt solishtiriladi."""
    import zlib

    def bolak(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + bolak(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
            + bolak(b"IDAT", zlib.compress(b"\x00" + bytes(rang))) + bolak(b"IEND", b""))


def xyz(lat, lon, z):
    import math
    n = 1 << z
    return (int((lon + 180) / 360 * n),
            int((1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n))


# SY-01: SUN'IY ortofoto (haqiqiy surat emas) — sinov obyekti atrofida bitta z=16 plitka
import sqlite3 as _sq  # noqa: E402
ORTO = os.path.join(TMP, "ortofoto.mbtiles")
PX, PY = xyz(40.1150, 67.8420, 16)
PLITKA = png_1x1((200, 120, 40))
_u = _sq.connect(ORTO)
_u.executescript("CREATE TABLE metadata(name TEXT, value TEXT); CREATE TABLE tiles(zoom_level INTEGER, tile_column INTEGER,"
                 " tile_row INTEGER, tile_data BLOB);")
_u.executemany("INSERT INTO metadata VALUES(?,?)", [("name", "SINOV ortofoto (sun'iy)"), ("format", "png"),
                                                    ("bounds", "67.83,40.10,67.85,40.13"), ("minzoom", "14"),
                                                    ("maxzoom", "18"), ("attribution", "SINOV")])
_u.execute("INSERT INTO tiles VALUES(16,?,?,?)", (PX, (1 << 16) - 1 - PY, PLITKA))
_u.commit()
_u.close()
env = dict(os.environ, YEROSTI_BAZA=os.path.join(TMP, "sinov.db"), YEROSTI_SKANLAR=os.path.join(TMP, "skanlar"),
           YEROSTI_ADMIN_PAROL="Sinov-Parol-1", YEROSTI_ORTOFOTO=ORTO, YEROSTI_ORTOFOTO_ANIQLIK_M="0,3",
           YEROSTI_SUNIY_URL="https://plitka.sinov.example/{z}/{x}/{y}.jpg", YEROSTI_SUNIY_ATRIBUTSIYA="SINOV manba",
           YEROSTI_SUNIY_ANIQLIK_M="5", YEROSTI_SUNIY_MAKS_ZOOM="19")
# SINOV_SERVER_LOG=<fayl> — server xato oqimini faylga (sukut bo'yicha yashirin: sinov chiqishi toza qolsin)
_srv_log = open(os.environ["SINOV_SERVER_LOG"], "w") if os.environ.get("SINOV_SERVER_LOG") else subprocess.DEVNULL
srv = subprocess.Popen([sys.executable, "-u", "yerosti_server.py", "--port", str(PORT)], cwd=YEROSTI, env=env,
                       stdout=subprocess.DEVNULL, stderr=_srv_log)
natijalar = []


def tekshir(nom, shart, izoh=""):
    natijalar.append((nom, bool(shart)))
    print(("PASS " if shart else "FAIL ") + nom + (f"  [{izoh}]" if (izoh and not shart) else ""))


def so(metod, yol, tana=None, sarlavha=None, xom=None):
    h = {"X-Yerosti": "1"}
    h.update(sarlavha or {})
    data = xom
    if tana is not None:
        data = json.dumps(tana).encode()
        h["Content-Type"] = "application/json"
    r = urllib.request.Request(f"http://127.0.0.1:{PORT}{yol}", data=data, method=metod, headers=h)
    try:
        j = urllib.request.urlopen(r, timeout=15)
        b, kod, sar = j.read(), j.status, dict(j.headers)
    except urllib.error.HTTPError as x:
        b, kod, sar = x.read(), x.code, dict(x.headers)
    try:
        m = json.loads(b.decode())
    except Exception:
        m = b
    return kod, m, sar


def matnda_son(matn, qiymat, tol=0.002, vergul=True):
    """Matnda qiymatga tol ichida yaqin son bormi (3 xonali kasr; yaxlitlash chegarasida sinov yolg'on yiqilmasin)."""
    import re
    naqsh = r"-?\d+,\d{3}" if vergul else r"-?\d+\.\d{3}"
    return any(abs(float(t.replace(",", ".")) - qiymat) <= tol for t in re.findall(naqsh, matn))


def urlparse_yol(url):
    """http://host:port/yol → /yol (sinov serveriga to'g'ridan-to'g'ri so'rov)."""
    return "/" + url.split("://", 1)[1].split("/", 1)[1]


def jurnal_yasa(yozuvlar):
    j = b"YMJ1"
    for tur, m in yozuvlar:
        j += bytes([tur]) + struct.pack(">I", len(m)) + m
    return j


def zanjir(yozuvlar):
    h = hashlib.sha256(b"YEROSTI-MUHR-v1").digest()
    for tur, m in yozuvlar:
        h = hashlib.sha256(h + bytes([tur]) + struct.pack(">I", len(m)) + m).digest()
    return h.hex()


try:
    for _ in range(80):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{PORT}/", timeout=1)
            break
        except Exception:
            time.sleep(0.1)

    # ---------- kirish, token, rollar ----------
    kod, m, sar = so("POST", "/api/v1/kirish", {"login": "admin", "parol": "Sinov-Parol-1"})
    tekshir("kirish 200", kod == 200, str(m))
    C = {"Cookie": sar.get("Set-Cookie", "").split(";")[0]}
    kod, m, _ = so("POST", "/api/v1/obyektlar", {"nomi": "x"}, sarlavha={**C, "X-Yerosti": ""})
    tekshir("CSRF: X-Yerosti siz POST 403", kod == 403)
    kod, m, _ = so("POST", "/api/v1/dala-tokenlar", {"nomi": "Brigada-1", "qurilma": "iPhone 17 Pro Max"}, sarlavha=C)
    tekshir("dala token yaratildi", kod == 200 and m["token"].startswith("YRD."), str(m))
    token, token_id = m["token"], m["id"]
    B = {"Authorization": f"Bearer {token}"}
    kod, m, _ = so("GET", "/api/v1/men", sarlavha={"Authorization": f"Bearer {token}", "X-Yerosti": ""})
    tekshir("Bearer: rol=dala", kod == 200 and m["foydalanuvchi"]["rol"] == "dala")
    kod, _, _ = so("GET", "/api/v1/men", sarlavha={"Authorization": "Bearer YRD.notogri"})
    tekshir("noto'g'ri Bearer 401", kod == 401)
    kod, _, _ = so("GET", "/api/v1/dala-tokenlar", sarlavha=B)
    tekshir("dala roli token ro'yxatini ko'rolmaydi", kod == 403)

    # ---------- obyekt, liniya, sifat qoidasi ----------
    kod, m, _ = so("POST", "/api/v1/obyektlar", {"nomi": "Sinov transheyasi", "pudratchi": "Sinov MChJ",
                                                "order_raqami": "S-1"}, sarlavha=B)
    tekshir("dala obyekt yaratdi", kod == 200, str(m))
    oid = m["id"]
    nq = [
        {"lat": 40.1150, "lon": 67.8420, "chuqurlik_m": 1.7, "rtk_holat": "FIX", "sigma_h_sm": 1.2, "sigma_v_sm": 3.0,
         "tuzatma_yoshi_s": 2, "qurilma_seriya": "RX2-0001", "tuzatma_manbai": "JIZ0", "antenna_balandligi_m": 2.0,
         "qiyshayish_deg": 3.1, "sputnik_soni": 27},
        {"lat": 40.1151, "lon": 67.8421, "chuqurlik_m": 1.7, "rtk_holat": "FIX", "sigma_h_sm": 3.5, "sigma_v_sm": 3.0,
         "tuzatma_yoshi_s": 2},
        {"lat": 40.1152, "lon": 67.8422, "chuqurlik_m": 1.8, "rtk_holat": "FLOAT", "sigma_h_sm": 1.0, "sigma_v_sm": 2.0,
         "tuzatma_yoshi_s": 1},
    ]
    kod, m, _ = so("POST", "/api/v1/liniyalar", {"obyekt_id": oid, "turi": "suv", "material": "PE100",
                                                "diametr_mm": 160, "nuqtalar": nq}, sarlavha=B)
    tekshir("liniya yaratildi", kod == 200, str(m))
    kod, g, _ = so("GET", "/api/v1/geojson", sarlavha=B)
    p = g["features"][0]["properties"]
    tekshir("bitta PAST nuqta → liniya PAST", p["nuqta_soni"] == 3 and p["sifat"] == "PAST", str(p))
    kod, st, _ = so("GET", "/api/v1/statistika", sarlavha=C)
    tekshir("statistika rasmiy=1 past=2", st["nuqta_rasmiy"] == 1 and st["nuqta_past"] == 2, str(st))
    kod, m, _ = so("POST", "/api/v1/liniyalar", {"obyekt_id": oid, "turi": "suv", "nuqtalar": [
        {"lat": 40.1, "lon": 67.8, "rtk_holat": "SUPER"}, {"lat": 40.1, "lon": 67.8}]}, sarlavha=B)
    tekshir("noto'g'ri rtk_holat 400", kod == 400)
    skan_nq = [dict(nq[0], manba="skan", lat=40.1160), dict(nq[0], manba="skan", lat=40.1161)]
    kod, m, _ = so("POST", "/api/v1/liniyalar", {"obyekt_id": oid, "turi": "suv", "nuqtalar": skan_nq}, sarlavha=B)
    kod, g, _ = so("GET", "/api/v1/geojson", sarlavha=B)
    tekshir("skandan chiqqan liniya FIX bo'lsa ham SKAN (RASMIY emas)", g["features"][-1]["properties"]["sifat"] == "SKAN",
            str(g["features"][-1]["properties"]["sifat"]))
    kod, m, _ = so("POST", "/api/v1/liniyalar", {"obyekt_id": oid, "turi": "suv", "nuqtalar": [
        dict(nq[0], manba="taxmin"), dict(nq[0], manba="taxmin")]}, sarlavha=B)
    tekshir("noma'lum manba 400", kod == 400)

    # ---------- AR-02: atrofdagi tarmoqlar ----------
    kod, m, _ = so("GET", "/api/v1/atrof?lat=40.1151&lon=67.8421&r=50", sarlavha=B)
    t = m.get("tarmoqlar", [])
    tekshir("atrof: 50 m ichidagi liniyalar keldi (dala tokeni bilan)", kod == 200 and len(t) >= 1, str(m)[:200])
    kalitlar = set(t[0]) if t else set()
    tekshir("atrof formati Swift GlobalTarmoq bilan bir xil",
            {"id", "turi", "diametr_mm", "material", "sifat", "pudratchi", "sigma_h_sm", "nuqtalar"} <= kalitlar
            and {"lat", "lon", "balandlik", "chuqurlik_m"} <= set(t[0]["nuqtalar"][0]), str(kalitlar))
    tekshir("atrof: liniya σH = nuqtalarning eng kattasi (UI-13)", any(x.get("sigma_h_sm") == 3.5 for x in t), str([x.get("sigma_h_sm") for x in t]))
    kod, m, _ = so("GET", "/api/v1/atrof?lat=40.2000&lon=67.9000&r=50", sarlavha=B)
    tekshir("atrof: uzoqda bo'sh", kod == 200 and m["tarmoqlar"] == [])
    kod, m, _ = so("GET", "/api/v1/atrof?lat=40.1151&lon=67.8421&r=99999", sarlavha=B)
    tekshir("atrof: radius 200 m bilan cheklanadi", kod == 200 and m["radius_m"] == 200.0)
    kod, _, _ = so("GET", "/api/v1/atrof?lat=abc&lon=67.8", sarlavha=B)
    tekshir("atrof: noto'g'ri lat 400", kod == 400)

    # ---------- T-235: ijro chizmasi (DXF) va katalog (CSV) ----------
    sys.path.insert(0, YEROSTI)
    import yerosti_chizma as ch
    nazorat = [(40.1158, 67.8422, 401336.5326, 4441252.3786), (41.3111, 69.2797, 523412.2580, 4573330.7733)]
    tekshir("Python UTM Swift nazorat qiymatlari bilan bir xil (≤1 mm)",
            all(abs(ch.utm(a, b, 42)[0] - e) < 0.001 and abs(ch.utm(a, b, 42)[1] - n) < 0.001 for a, b, e, n in nazorat))
    r = urllib.request.Request(f"http://127.0.0.1:{PORT}/api/v1/chizma?obyekt_id={oid}&format=dxf", headers=C)
    j = urllib.request.urlopen(r, timeout=15)
    dxf = j.read().decode("ascii")
    tekshir("DXF: 200, fayl sifatida", j.status == 200 and "attachment" in j.headers.get("Content-Disposition", ""))
    q = dxf.split("\n")
    juft = [(int(q[i]), q[i + 1]) for i in range(0, len(q) - 1, 2) if q[i].strip().lstrip("-").isdigit()]
    ob = [v for k, v in juft if k == 0]
    kod, g, _ = so("GET", "/api/v1/geojson", sarlavha=C)
    liniya_soni = sum(1 for f in g["features"] if f["properties"]["obyekt_id"] == oid and len(f["geometry"]["coordinates"]) >= 2)
    tekshir("DXF: har liniya 3D polilinya", ob.count("POLYLINE") == liniya_soni and ob[-1] == "EOF", f"{ob.count('POLYLINE')} vs {liniya_soni}")
    v = next(i for i, x in enumerate(juft) if x == (0, "VERTEX"))
    birinchi = g["features"][0]["geometry"]["coordinates"][0]
    e_kut, n_kut, _ = ch.utm(birinchi[1], birinchi[0], 42)
    tekshir("DXF: birinchi cho'qqi = bazadagi lat/lon ning UTM qiymati",
            abs(float(juft[v + 2][1]) - e_kut) < 0.001 and abs(float(juft[v + 3][1]) - n_kut) < 0.001)
    tekshir("DXF: faqat ASCII va sarlavhada muhr", all(ord(c) < 128 for c in dxf) and "Raqamli muhr:" in dxf)
    kod, m, _ = so("GET", f"/api/v1/chizma?obyekt_id={oid}&format=pdf", sarlavha=C)
    tekshir("noma'lum format 404", kod == 404)

    # ---------- bo'lakli yuklash ----------
    def yukla(turi, data, buz_sha=False):
        sha = hashlib.sha256(data).hexdigest()
        kod, m, _ = so("POST", "/api/v1/skan/boshla", {"obyekt_id": oid, "turi": turi, "hajmi": len(data), "sha256": sha},
                       sarlavha=B)
        assert kod == 200, m
        sid, bh = m["skan_id"], m["bolak_hajmi"]
        for n in range(m["bolak_soni"]):
            b = data[n * bh:(n + 1) * bh]
            kod, r, _ = so("PUT", f"/api/v1/skan/{sid}/bolak/{n}", xom=b,
                           sarlavha={**B, "X-Bolak-SHA256": hashlib.sha256(b).hexdigest(),
                                     "Content-Type": "application/octet-stream"})
            assert kod == 200, r
        kod, r, _ = so("POST", f"/api/v1/skan/{sid}/yakunla", sarlavha=B)
        return sid, sha, kod, r

    data = os.urandom(5 * 1024 * 1024 + 123)
    sid, sha, kod, r = yukla("mesh_usdz", data)
    tekshir("5 MB skan 2 bo'lakda yuklandi", kod == 200 and r["holat"] == "tayyor", str(r))
    kod, s, _ = so("GET", f"/api/v1/skan/{sid}", sarlavha=C)
    fayl = os.path.join(TMP, "skanlar", s["fayl_yol"])
    tekshir("diskdagi fayl xeshi mos", hashlib.sha256(open(fayl, "rb").read()).hexdigest() == sha)

    # keep-alive: katta tana rad etilgach ulanish yashaydi
    c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=15)
    c.request("POST", "/api/v1/obyektlar", body=b"x" * (3 * 1024 * 1024), headers={**C, "X-Yerosti": "1"})
    r1 = c.getresponse(); r1.read()
    c.request("GET", "/api/v1/men", headers={**C, "X-Yerosti": "1"})
    r2 = c.getresponse(); r2.read()
    tekshir("3 MB tana 400, o'sha ulanishda keyingisi 200", r1.status == 400 and r2.status == 200)
    c.close()

    # ---------- K-05 raqamli muhr ----------
    kalit = ec.generate_private_key(ec.SECP256R1())  # sinovda Secure Enclave o'rnida
    x963 = kalit.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
    tuzilgan = json.dumps({"versiya": "YEROSTI-MUHR-v1", "obyekt_id": oid, "qurilma": "x", "boshlandi": "a",
                           "tugadi": "b", "yozuv_soni": 1, "zanjir_boshi": "00",
                           "fayllar": [{"nomi": "a", "sha256": "0" * 64, "hajm": 1}]}).encode()
    kod, m, _ = so("POST", "/api/v1/muhr", {"obyekt_id": oid, "manifest": "e30=", "imzo": "AA=="}, sarlavha=B)
    tekshir("maydonsiz manifest → 400", kod == 400, str(m))
    kod, m, _ = so("POST", "/api/v1/muhr", {"obyekt_id": oid, "manifest": base64.b64encode(tuzilgan).decode(),
                                           "imzo": "AA=="}, sarlavha=B)
    tekshir("qurilma kaliti ro'yxatdan o'tmagan → 409", kod == 409, str(m))
    kod, m, _ = so("POST", "/api/v1/qurilma-kalit", {"ochiq_kalit": base64.b64encode(b"\x04" + b"\x00" * 64).decode()},
                   sarlavha=B)
    tekshir("egri ustida bo'lmagan kalit 400", kod == 400, str(m))
    kod, m, _ = so("POST", "/api/v1/qurilma-kalit", {"ochiq_kalit": base64.b64encode(x963).decode()}, sarlavha=C)
    tekshir("admin sessiyasi qurilma kalitini yozolmaydi", kod == 403)
    kod, m, _ = so("POST", "/api/v1/qurilma-kalit", {"ochiq_kalit": base64.b64encode(x963).decode()}, sarlavha=B)
    tekshir("qurilma kaliti ro'yxatga olindi", kod == 200, str(m))

    yozuvlar = [(1, b"$GNGGA,101010.00,4006.948,N,06750.532,E,4,27,0.6,350.10,M,-40.2,M,1.0,0001*6E"),
                (2, b'{"t":1.25,"q":"RASMIY"}'), (5, "mufta · 1,72 m".encode()), (7, b"")]
    jurnal = jurnal_yasa(yozuvlar)
    tekshir("Python zanjiri Swift bilan bir xil", zanjir(yozuvlar) == "2715b38babe661140f7879821d13ebb9215171d5ee7ad60710feb4f1e6bb42f0")
    jsid, jsha, kod, _ = yukla("muhr_jurnal", jurnal)

    def manifest(bosh, soni, fayllar):
        return json.dumps({"versiya": "YEROSTI-MUHR-v1", "obyekt_id": oid, "qurilma": "iPhone 17 Pro Max / RX2-0001",
                           "boshlandi": "2026-09-27T08:00:00Z", "tugadi": "2026-09-27T08:14:00Z", "yozuv_soni": soni,
                           "zanjir_boshi": bosh, "fayllar": fayllar}, sort_keys=True, separators=(",", ":")).encode()

    fayllar = [{"nomi": "jurnal.ymj", "sha256": jsha, "hajm": len(jurnal)},
               {"nomi": "mesh.usdz", "sha256": sha, "hajm": len(data)}]
    mb = manifest(zanjir(yozuvlar), 4, fayllar)
    imzo = kalit.sign(mb, ec.ECDSA(hashes.SHA256()))
    kod, m, _ = so("POST", "/api/v1/muhr", {"obyekt_id": oid, "manifest": base64.b64encode(mb).decode(),
                                           "imzo": base64.b64encode(imzo).decode()}, sarlavha=B)
    tekshir("to'g'ri muhr → TASDIQLANGAN", kod == 200 and m["holat"] == "TASDIQLANGAN", str(m))

    buzuq = bytearray(jurnal); buzuq[30] ^= 0x01
    bsid, bsha, _, _ = yukla("muhr_jurnal", bytes(buzuq))
    mb2 = manifest(zanjir(yozuvlar), 4, [{"nomi": "jurnal.ymj", "sha256": bsha, "hajm": len(buzuq)}])
    kod, m, _ = so("POST", "/api/v1/muhr", {"obyekt_id": oid, "manifest": base64.b64encode(mb2).decode(),
                                           "imzo": base64.b64encode(kalit.sign(mb2, ec.ECDSA(hashes.SHA256()))).decode()},
                   sarlavha=B)
    tekshir("jurnalda 1 bit o'zgargan → BUZILGAN", kod == 200 and m["holat"] == "BUZILGAN" and "zanjir" in m["sabab"], str(m))

    begona = ec.generate_private_key(ec.SECP256R1())
    kod, m, _ = so("POST", "/api/v1/muhr", {"obyekt_id": oid, "manifest": base64.b64encode(mb).decode(),
                                           "imzo": base64.b64encode(begona.sign(mb, ec.ECDSA(hashes.SHA256()))).decode()},
                   sarlavha=B)
    tekshir("begona kalit imzosi → BUZILGAN", m.get("holat") == "BUZILGAN" and "imzo" in m["sabab"], str(m))

    mb3 = manifest(zanjir(yozuvlar), 4, [{"nomi": "yoq.bin", "sha256": "0" * 64, "hajm": 10}])
    kod, m, _ = so("POST", "/api/v1/muhr", {"obyekt_id": oid, "manifest": base64.b64encode(mb3).decode(),
                                           "imzo": base64.b64encode(kalit.sign(mb3, ec.ECDSA(hashes.SHA256()))).decode()},
                   sarlavha=B)
    tekshir("yuklanmagan fayl → BUZILGAN", m.get("holat") == "BUZILGAN" and "yuklanmagan" in m["sabab"], str(m))

    kod, m, _ = so("GET", f"/api/v1/muhrlar?obyekt_id={oid}", sarlavha=C)
    holatlar = sorted(x["holat"] for x in m["muhrlar"])
    tekshir("barcha urinishlar saqlandi (1 tasdiq, 3 buzilgan)", holatlar == ["BUZILGAN"] * 3 + ["TASDIQLANGAN"], str(holatlar))

    # ---------- DM-01 / DM-04: CSP va sog'liq ----------
    kod, m, sar = so("GET", "/api/v1/salomatlik")
    tekshir("salomatlik kirishsiz 200 va holat ok", kod == 200 and m.get("holat") == "ok" and m.get("baza") is True, str(m))
    csp = sar.get("Content-Security-Policy", "")
    tekshir("CSP: skript faqat o'zidan, unpkg yo'q", "script-src 'self';" in csp and "unpkg" not in csp, csp)
    kod, m, _ = so("GET", "/api/v1/xarita-sozlama", sarlavha=C)
    tekshir("xarita uslubi sozlamadan keladi", kod == 200 and "uslub" in m, str(m))
    for yol in ("/static/vendor/maplibre-gl-csp.js", "/static/vendor/maplibre-gl-csp-worker.js", "/3d"):
        r = urllib.request.urlopen(f"http://127.0.0.1:{PORT}{yol}", timeout=15)
        tekshir(f"o'zidan beriladi: {yol}", r.status == 200 and len(r.read()) > 1000)

    # ---------- DM-02: mustaqil qayta hisob (sinov geometriyasi — haqiqiy skan emas) ----------
    toplam = os.path.join(YEROSTI, "sinov", "toplam")
    cli = os.path.join(YEROSTI, "Yadro", ".build", "release", "yerosti-tahlil")
    tayyor = os.path.isfile(cli) and os.path.isfile(os.path.join(toplam, "jurnal.ymj"))
    tekshir("DM-02 sinov to'plami va CLI bor (yo'q bo'lsa: SINOV_TOPLAM=sinov/toplam swift test --filter "
            "testToplamniYoz; swift build -c release --product yerosti-tahlil)", tayyor)
    if tayyor:
        sys.path.insert(0, YEROSTI)
        import yerosti_muhr as ym
        ply = open(os.path.join(toplam, "mesh.ply"), "rb").read()
        _, psha, _, _ = yukla("nuqta_ply", ply)

        def muhrla(jurnal_bayt):
            _, jsha2, _, _ = yukla("muhr_jurnal", jurnal_bayt)
            bosh, soni = ym.jurnal_tekshir(jurnal_bayt)
            mb4 = manifest(bosh, soni, [{"nomi": "jurnal.ymj", "sha256": jsha2, "hajm": len(jurnal_bayt)},
                                        {"nomi": "mesh.ply", "sha256": psha, "hajm": len(ply)}])
            return so("POST", "/api/v1/muhr", {"obyekt_id": oid, "manifest": base64.b64encode(mb4).decode(),
                                               "imzo": base64.b64encode(kalit.sign(mb4, ec.ECDSA(hashes.SHA256()))).decode()},
                      sarlavha=B)[1]

        def ishchi():
            return subprocess.run([sys.executable, "yerosti_ishchi.py", "--bir-marta"], cwd=YEROSTI, env=env,
                                  capture_output=True, timeout=300)

        m1 = muhrla(open(os.path.join(toplam, "jurnal.ymj"), "rb").read())
        tekshir("muhr TASDIQLANGAN → qayta hisob navbatga qo'yildi", m1.get("holat") == "TASDIQLANGAN" and m1.get("tahlil_id"),
                str(m1))
        kod, t, _ = so("GET", f"/api/v1/tahlil/{m1.get('tahlil_id')}", sarlavha=C)
        tekshir("tahlil ishchidan oldin 'kutmoqda'", kod == 200 and t["holat"] == "kutmoqda", str(t)[:200])
        r = ishchi()
        kod, t, _ = so("GET", f"/api/v1/tahlil/{m1.get('tahlil_id')}", sarlavha=C)
        tekshir("ishchi: toza skan → MOS (bir xil yadro, o'q farqi < 2 mm)",
                kod == 200 and t["holat"] == "tayyor" and t["xulosa"] == "MOS" and t["oq_farqi_maks_m"] < 0.002,
                str(t)[:300] + r.stderr.decode()[-300:])
        n = t.get("natija") or {}
        tekshir("natija: zanjir boshi server hisobi bilan bir xil, juftlar xom NMEA da",
                n.get("jurnal", {}).get("bosh") == ym.jurnal_tekshir(open(os.path.join(toplam, "jurnal.ymj"), "rb").read())[0]
                and n.get("georef", {}).get("juftlar_nmeada_topildi") == n.get("jurnal", {}).get("juftlar"), str(n)[:300])
        tekshir("natija: server quvuri UTM va WGS84 da", bool(n.get("quvurlar")) and n["quvurlar"][0].get("oq_wgs84"))

        m2 = muhrla(open(os.path.join(toplam, "jurnal_surilgan.ymj"), "rb").read())
        ishchi()
        kod, t2, _ = so("GET", f"/api/v1/tahlil/{m2.get('tahlil_id')}", sarlavha=C)
        tekshir("ishchi: telefon quvuri 5 sm surilgan → FARQ va farq raqami",
                t2.get("xulosa") == "FARQ" and abs((t2.get("oq_farqi_maks_m") or 0) - 0.05) < 0.01, str(t2)[:300])
        kod, tl, _ = so("GET", f"/api/v1/tahlillar?obyekt_id={oid}", sarlavha=C)
        tekshir("tahlillar ro'yxati (2 ta)", kod == 200 and len(tl["tahlillar"]) == 2, str(tl)[:200])

        yol = f"/api/v1/tahlil/{m1.get('tahlil_id')}/korinish.ply"
        kod, b, _ = so("GET", yol, sarlavha=C)
        tekshir("DM-03: ko'rinish buluti portal foydalanuvchisiga beriladi", kod == 200 and bytes(b).startswith(b"ply\n"))
        kod, _, _ = so("GET", yol, sarlavha=B)
        tekshir("DM-03: dala tokeni bulutni ololmaydi (403)", kod == 403)
        kod, _, _ = so("GET", yol)
        tekshir("DM-03: kirishsiz bulut yo'q (401)", kod == 401)
        kod, _, _ = so("GET", "/api/v1/tahlil/999999/korinish.ply", sarlavha=C)
        tekshir("DM-03: yo'q tahlil 404", kod == 404)

        kod, _, _ = so("POST", f"/api/v1/tahlil/{m1.get('tahlil_id')}/qayta", sarlavha=B)
        tekshir("qayta hisob: dala roli 403", kod == 403)
        kod, _, _ = so("POST", f"/api/v1/tahlil/{m1.get('tahlil_id')}/qayta", sarlavha=C)
        ishchi()
        kod2, t3, _ = so("GET", f"/api/v1/tahlil/{m1.get('tahlil_id')}", sarlavha=C)
        tekshir("qayta hisob: admin → yana MOS", kod == 200 and t3.get("xulosa") == "MOS" and t3.get("urinish") == 1, str(t3)[:200])
        kod, m, _ = so("GET", "/api/v1/salomatlik")
        tekshir("salomatlik: ishchi yuragi ko'rinadi", m.get("ishchi_oxirgi_yurak_s") is not None and m["navbat"].get("tayyor") == 2,
                str(m))
        # KU-04: M3C2 o'zgarish tahlili — bir xil bulut (surilgan telefon quvuri PLY ni o'zgartirmaydi) → o'zgarmagan
        kod, fj, _ = so("POST", f"/api/v1/obyekt/{oid}/farq", {"a": m1.get("tahlil_id"), "b": m2.get("tahlil_id")}, sarlavha=C)
        kodB, _, _ = so("POST", f"/api/v1/obyekt/{oid}/farq", {"a": m1.get("tahlil_id"), "b": m2.get("tahlil_id")}, sarlavha=B)
        kodX, mx, _ = so("POST", f"/api/v1/obyekt/{oid}/farq", {"a": m1.get("tahlil_id"), "b": m1.get("tahlil_id")}, sarlavha=C)
        tekshir("KU-04: farq navbatga qo'yildi; dala 403; bir xil tahlil 400", kod == 200 and fj.get("tahlil_id") and kodB == 403 and kodX == 400, str(fj) + str(mx))
        rf = ishchi()
        kod, ft, _ = so("GET", f"/api/v1/tahlil/{fj.get('tahlil_id')}", sarlavha=C)
        fx = ft.get("farq") or {}
        tekshir("KU-04: ishchi M3C2 ni hisobladi — xulosa OZGARMAGAN, maks |farq| < 1 sm, LoD95 > 0, yadro nuqtalar bor",
                ft.get("holat") == "tayyor" and ft.get("xulosa") == "OZGARMAGAN" and (fx.get("maks_abs_m") or 1) < 0.01
                and (fx.get("lod95_ortacha_m") or 0) > 0 and (fx.get("baholangan") or 0) > 50 and ft.get("tur") == "farq",
                str(ft)[:400] + rf.stderr.decode()[-300:])
        kod, fb, _ = so("GET", f"/api/v1/tahlil/{fj.get('tahlil_id')}/korinish.ply", sarlavha=C)
        tekshir("KU-04: farq buluti PLY (farq, lod xossalari)", kod == 200 and b"property float farq" in bytes(fb) and b"property float lod" in bytes(fb))

        # ---------- 21-bo'lim: DS-03…DS-07 — xom yozuvli skan (SUN'IY to'plam: ARKit suzishi 1 %, RTK kechikishi 120 ms) ----------
        xomp = os.path.join(YEROSTI, "sinov", "toplam_xom")
        tekshir("DS sinov to'plami bor (yo'q bo'lsa: SINOV_TOPLAM_XOM=sinov/toplam_xom swift test --filter testXomToplamniYoz)",
                os.path.isfile(os.path.join(xomp, "zich.ply")))
        if os.path.isfile(os.path.join(xomp, "zich.ply")):
            zply = open(os.path.join(xomp, "zich.ply"), "rb").read()
            _, zsha, _, _ = yukla("nuqta_ply", zply)
            jx = open(os.path.join(xomp, "jurnal.ymj"), "rb").read()
            _, jxsha, _, _ = yukla("muhr_jurnal", jx)
            bx, sx = ym.jurnal_tekshir(jx)
            mbx = manifest(bx, sx, [{"nomi": "jurnal.ymj", "sha256": jxsha, "hajm": len(jx)},
                                    {"nomi": "zich.ply", "sha256": zsha, "hajm": len(zply)}])
            mx = so("POST", "/api/v1/muhr", {"obyekt_id": oid, "manifest": base64.b64encode(mbx).decode(),
                                             "imzo": base64.b64encode(kalit.sign(mbx, ec.ECDSA(hashes.SHA256()))).decode()},
                    sarlavha=B)[1]
            rx = ishchi()
            kod, tx, _ = so("GET", f"/api/v1/tahlil/{mx.get('tahlil_id')}", sarlavha=C)
            tekshir("DS-04: xom jurnaldan RTK kechikishi 120 ± 10 ms topildi (sun'iy)",
                    kod == 200 and tx.get("kechikish_ms") is not None and abs(tx["kechikish_ms"] - 120) <= 10 and tx.get("kechikish_ishonchli"),
                    str({k: tx.get(k) for k in ("holat", "xulosa", "kechikish_ms", "xato")}) + rx.stderr.decode()[-300:])
            tekshir("DS-05: bo'lakli georeferens — PAST bo'lak yo'q, ARKit suzishi > 5 sm tuzatildi",
                    (tx.get("bolaklar") or 0) >= 3 and tx.get("past_bolaklar") == 0 and (tx.get("maks_tuzatish_m") or 0) > 0.05,
                    str({k: tx.get(k) for k in ("bolaklar", "past_bolaklar", "maks_tuzatish_m")}))
            qx = (tx.get("natija") or {}).get("quvurlar") or []
            tekshir("DS-05/06: zich.ply dan Ø110, o'q nuqtalari bo'lakli georeferensda, PAST nuqta yo'q",
                    tx.get("ply_nomi") == "zich.ply" and any(x.get("standart_mm") == 110 and x.get("georef_usul") == "bolakli"
                                                              and x.get("oq_past") and not any(x["oq_past"]) for x in qx),
                    str([(x.get("standart_mm"), x.get("georef_usul")) for x in qx]))
            kod, kb, _ = so("GET", f"/api/v1/tahlil/{mx.get('tahlil_id')}/korinish.ply", sarlavha=C)
            tekshir("DS-07: ko'rinish buluti rangli (red/green/blue)", kod == 200 and b"property uchar red" in bytes(kb))

    # ---------- 14-bo'lim: ijro hujjati (IH), loyiha (IH-07), ulashish (UL), tarix va izoh (TL) ----------
    import re
    import sqlite3
    import cv2
    sys.path.insert(0, YEROSTI)
    import yerosti_chizma as ych

    def pdf_matn(b):
        y = os.path.join(TMP, "h.pdf")
        open(y, "wb").write(b)
        return subprocess.run(["pdftotext", "-layout", y, "-"], capture_output=True, text=True).stdout

    def qr_oqi(b):
        y = os.path.join(TMP, "q.pdf")
        open(y, "wb").write(b)
        subprocess.run(["pdftoppm", "-r", "220", "-f", "1", "-l", "1", "-png", y, os.path.join(TMP, "q")], check=True)
        rasm = cv2.imread(os.path.join(TMP, "q-1.png"))
        h_, w_ = rasm.shape[:2]
        mm = w_ / 420.0
        import yerosti_ijro as yij
        # QR qutisi + atrofida 6 mm: bo'sh hoshiya kesilsa OpenCV ba'zi naqshlarni o'qimaydi (sinov shunda yiqilgan)
        k = rasm[int(h_ - (yij.QR_Y + yij.QR_O + 6) * mm):int(h_ - (yij.QR_Y - 6) * mm),
                 int((yij.QR_X - 6) * mm):int((yij.QR_X + yij.QR_O + 2.5) * mm)]
        return cv2.QRCodeDetector().detectAndDecode(k)[0]

    def xom(metod, yol, sarlavha=None, data=None):
        r = urllib.request.Request(f"http://127.0.0.1:{PORT}{yol}", data=data, method=metod,
                                   headers={"X-Yerosti": "1", **(sarlavha or {})})
        try:
            j = urllib.request.urlopen(r, timeout=30)
            return j.status, j.read(), dict(j.headers)
        except urllib.error.HTTPError as x:
            return x.code, x.read(), dict(x.headers)

    kod, _, _ = so("POST", "/api/v1/ijro-hujjat", {"obyekt_id": oid}, sarlavha=B)
    tekshir("IH: dala qurilmasi hujjat yasay olmaydi (403)", kod == 403)
    kod, hj, _ = so("POST", "/api/v1/ijro-hujjat", {"obyekt_id": oid}, sarlavha=C)
    tekshir("IH-01: admin hujjat yasadi, raqam YRS-YYYY-NNNNNN", kod == 200 and re.fullmatch(r"YRS-\d{4}-\d{6}", hj.get("raqam", ""))
            and hj.get("varaqlar", 0) >= 4, str(hj))
    kod, ro, _ = so("GET", f"/api/v1/ijro-hujjatlar?obyekt_id={oid}", sarlavha=C)
    tekshir("IH: ro'yxatda 1 hujjat, tekshirish kodi va fayl yo'li ko'rinmaydi",
            kod == 200 and len(ro["hujjatlar"]) == 1 and "kod" not in ro["hujjatlar"][0] and "fayl" not in ro["hujjatlar"][0], str(ro)[:300])
    kod, pdf, sar = xom("GET", f"/api/v1/ijro-hujjat/{hj['id']}.pdf", C)
    tekshir("IH: PDF yuklab olinadi, xeshi bazadagi bilan bir xil",
            kod == 200 and pdf.startswith(b"%PDF") and hashlib.sha256(pdf).hexdigest() == hj["sha256"]
            and sar.get("Content-Type") == "application/pdf", str(kod))
    kod, _, _ = xom("GET", f"/api/v1/ijro-hujjat/{hj['id']}.pdf", B)
    tekshir("IH: dala tokeni PDF ni ololmaydi (403)", kod == 403)
    tm = pdf_matn(pdf)
    kod, g, _ = so("GET", "/api/v1/geojson", sarlavha=C)
    birinchi = next(f for f in g["features"] if f["properties"]["obyekt_id"] == oid)
    lon0, lat0 = birinchi["geometry"]["coordinates"][0]
    e0, n0, _ = ych.utm(lat0, lon0)
    tekshir("IH-05: katalogda bazadagi birinchi nuqtaning X (shimol) va Y (sharq) qiymati",
            f"{n0:.3f}".replace(".", ",") in tm and f"{e0:.3f}".replace(".", ",") in tm and hj["raqam"] in tm, f"{n0:.3f} {e0:.3f}")
    url = qr_oqi(pdf)
    tekshir("IH-08: QR OpenCV bilan o'qildi, /t/<kod> ga olib boradi", bool(re.fullmatch(rf"http://127\.0\.0\.1:{PORT}/t/[A-Za-z0-9_-]{{16}}", url)), url)
    kod, sah, sar = xom("GET", urlparse_yol(url))
    sah = sah.decode()
    tekshir("IH-08: tekshirish sahifasi: raqam, xesh, 'amalda'", kod == 200 and hj["raqam"] in sah and hj["sha256"] in sah
            and "haqiqiy va amalda" in sah, sah[:300])
    tekshir("IH-08: sahifada koordinata yo'q (lat/lon va UTM)", f"{lat0:.4f}" not in sah and f"{lon0:.4f}" not in sah
            and f"{n0:.0f}"[:5] not in sah and f"{e0:.0f}"[:4] not in sah)
    tekshir("UL-03: ochiq sahifa noindex, no-referrer, no-store", sar.get("X-Robots-Tag", "").startswith("noindex")
            and sar.get("Referrer-Policy") == "no-referrer" and sar.get("Cache-Control") == "no-store", str(sar))
    kod, _, _ = xom("GET", "/t/YoqKod_12345678")
    tekshir("IH-08: noto'g'ri kod 404", kod == 404)
    kod, _, _ = so("POST", f"/api/v1/ijro-hujjat/{hj['id']}/bekor", {"sabab": "x"}, sarlavha=B)
    tekshir("IH: dala bekor qila olmaydi (403)", kod == 403)
    kod, _, _ = so("POST", f"/api/v1/ijro-hujjat/{hj['id']}/bekor", {}, sarlavha=C)
    tekshir("IH: sababsiz bekor 400", kod == 400)
    kod, _, _ = so("POST", f"/api/v1/ijro-hujjat/{hj['id']}/bekor", {"sabab": "loyiha qo'shildi, qayta tuzildi"}, sarlavha=C)
    kod2, _, _ = so("POST", f"/api/v1/ijro-hujjat/{hj['id']}/bekor", {"sabab": "yana"}, sarlavha=C)
    _, sah, _ = xom("GET", urlparse_yol(url))
    tekshir("IH-08: bekor qilingan hujjat 'bekor' deb chiqadi, ikkinchi bekor 409",
            kod == 200 and kod2 == 409 and "Hujjat bekor qilingan" in sah.decode() and "loyiha qo&#x27;shildi" in sah.decode())

    # IH-07: loyiha DXF — suv liniyasiga parallel, 0,12 m surilgan
    kod, gl, _ = so("GET", "/api/v1/geojson", sarlavha=C)
    suv = next(f for f in gl["features"] if f["properties"]["obyekt_id"] == oid and f["properties"]["turi"] == "suv")
    uq = [ych.utm(la, lo) for lo, la in suv["geometry"]["coordinates"]]
    lw = "".join(f"10\n{e:.3f}\n20\n{n + 0.12:.3f}\n" for e, n, _ in uq)
    dxf = f"0\nSECTION\n2\nENTITIES\n0\nLWPOLYLINE\n8\nLOYIHA\n90\n{len(uq)}\n{lw}0\nENDSEC\n0\nEOF\n".encode()
    yol_l = f"/api/v1/obyekt/{oid}/loyiha?fayl=suv_loyiha.dxf&z_turi=usti&z_tizimi=boltiq"
    kod, _, _ = xom("POST", yol_l, B, dxf)
    tekshir("IH-07: dala loyiha yuklay olmaydi (403)", kod == 403)
    kod, m, _ = xom("POST", f"/api/v1/obyekt/{oid}/loyiha?z_turi=xato", C, dxf)
    tekshir("IH-07: noto'g'ri z_turi 400", kod == 400)
    kod, m, _ = xom("POST", yol_l, C, b"0\nSECTION\n2\nENTITIES\n0\nLINE\n8\n0\n10\n12.5\n20\n7\n11\n20\n21\n9\n0\nENDSEC\n")
    tekshir("IH-07: UTM emas DXF rad etiladi (400)", kod == 400 and "UTM" in m.decode(), m[:200])
    uzoq = dxf.replace(f"{uq[0][1] + 0.12:.3f}".encode(), f"{uq[0][1] + 5000.12:.3f}".encode())
    uzoq = re.sub(rb"20\n(\d+\.\d+)\n", lambda q: b"20\n" + f"{float(q.group(1)) + 5000:.3f}".encode() + b"\n", dxf)
    kod, m, _ = xom("POST", yol_l, C, uzoq)
    tekshir("IH-07: obyektdan 5 km uzoq loyiha rad etiladi (zona/tizim xatosi)", kod == 400 and "uzoqda" in m.decode(), m[:200])
    kod, m, _ = xom("POST", yol_l, C, dxf)
    tekshir("IH-07: loyiha yuklandi", kod == 200 and json.loads(m)["chiziqlar"] == 1, m[:200])
    kod, ly, _ = so("GET", f"/api/v1/obyekt/{oid}/loyiha", sarlavha=C)
    tekshir("IH-07: loyiha qaytadi (chiziqlar, z turi va tizimi)", kod == 200 and ly["loyiha"]["z_tizimi"] == "boltiq"
            and len(ly["loyiha"]["chiziqlar"]) == 1 and len(ly["tarix"]) == 1, str(ly)[:200])
    kod, hj2, _ = so("POST", "/api/v1/ijro-hujjat", {"obyekt_id": oid}, sarlavha=C)
    _, pdf2, _ = xom("GET", f"/api/v1/ijro-hujjat/{hj2['id']}.pdf", C)
    tm2 = pdf_matn(pdf2)
    tekshir("IH-07: yangi hujjatda loyihadan og'ish 0,12 m va Boltiq izohi", kod == 200 and "Loyihadan og'ish" in tm2
            and " 0,12 " in tm2 and "Boltiq" in tm2, tm2[:200])

    # UL: ulashish
    kod, _, _ = so("POST", f"/api/v1/obyekt/{oid}/ulash", {"nomi": "Hokimlik", "kun": 7}, sarlavha=B)
    tekshir("UL-01: dala havola yarata olmaydi (403)", kod == 403)
    kod0, _, _ = so("POST", f"/api/v1/obyekt/{oid}/ulash", {"nomi": "Hokimlik", "kun": 0}, sarlavha=C)
    kod1, _, _ = so("POST", f"/api/v1/obyekt/{oid}/ulash", {"nomi": "Hokimlik", "kun": 400}, sarlavha=C)
    tekshir("UL-01: muddat 1…365 kun (0 va 400 → 400)", kod0 == 400 and kod1 == 400)
    kod, ul, _ = so("POST", f"/api/v1/obyekt/{oid}/ulash", {"nomi": "Shahar hokimligi", "kun": 7}, sarlavha=C)
    tekshir("UL-01: havola yaratildi (token faqat javobda)", kod == 200 and "/u/YRU." in ul.get("url", ""), str(ul))
    uyol = urlparse_yol(ul["url"])
    kod, ro, _ = so("GET", f"/api/v1/obyekt/{oid}/ulashlar", sarlavha=C)
    tekshir("UL-01: ro'yxatda token yoki xesh yo'q", kod == 200 and ul["url"].split("/u/")[1] not in json.dumps(ro)
            and "token_hash" not in json.dumps(ro) and ro["ulashlar"][0]["holat"] == "amal")
    kod, sah, sar = xom("GET", uyol)
    tekshir("UL-02: ulashish sahifasi: obyekt nomi, no-referrer, noindex", kod == 200 and "Sinov transheyasi" in sah.decode()
            and sar.get("Referrer-Policy") == "no-referrer" and "noindex" in sar.get("X-Robots-Tag", ""), str(kod))
    tekshir("UL-02: bekor qilingan hujjat ro'yxatda yo'q, yangisi bor",
            hj["raqam"] not in sah.decode() and hj2["raqam"] in sah.decode())
    kod, b1, _ = xom("GET", f"{uyol}/hujjat/{hj2['id']}.pdf")
    kod_b, _, _ = xom("GET", f"{uyol}/hujjat/{hj['id']}.pdf")
    tekshir("UL-02: amaldagi PDF beriladi, bekor qilingani 404", kod == 200 and b1.startswith(b"%PDF") and kod_b == 404)
    kod_d, d1, _ = xom("GET", f"{uyol}/chizma.dxf")
    kod_c, c1, _ = xom("GET", f"{uyol}/chizma.csv")
    tekshir("UL-02: DXF va CSV beriladi", kod_d == 200 and b"POLYLINE" in d1 and kod_c == 200 and c1.startswith(b"raqam;"))
    kod, m, _ = so("POST", "/api/v1/obyektlar", {"nomi": "Boshqa obyekt"}, sarlavha=C)
    oid2 = m["id"]
    so("POST", "/api/v1/liniyalar", {"obyekt_id": oid2, "turi": "gaz", "diametr_mm": 110, "nuqtalar": [
        {"lat": 40.2, "lon": 67.9, "rtk_holat": "FIX", "sigma_h_sm": 1, "sigma_v_sm": 2, "tuzatma_yoshi_s": 1},
        {"lat": 40.2001, "lon": 67.9001, "rtk_holat": "FIX", "sigma_h_sm": 1, "sigma_v_sm": 2, "tuzatma_yoshi_s": 1}]}, sarlavha=C)
    kod, hj3, _ = so("POST", "/api/v1/ijro-hujjat", {"obyekt_id": oid2}, sarlavha=C)
    kod_x, _, _ = xom("GET", f"{uyol}/hujjat/{hj3['id']}.pdf")
    kod_t, _, _ = xom("GET", f"{uyol}/api/tahlil/999999")
    tekshir("UL-02: boshqa obyekt hujjati va yo'q tahlil 404", kod == 200 and kod_x == 404 and kod_t == 404)
    kod, tl, _ = xom("GET", f"{uyol}/api/tahlillar")
    tekshir("UL-02: 3D uchun tahlillar ro'yxati (faqat shu obyekt)", kod == 200 and all(t["obyekt_id"] == oid for t in json.loads(tl)["tahlillar"]))
    kod, d3, _ = xom("GET", f"{uyol}/3d")
    tekshir("UL-02: 3D ko'ruvchi ulashish yo'lida ochiladi", kod == 200 and b"3d.js" in d3)
    kod, _, _ = xom("POST", f"{uyol}/api/tahlillar")
    tekshir("UL-02: ulashish yo'lida yozish yo'q (POST 401/404)", kod in (401, 404))
    kod, ro, _ = so("GET", f"/api/v1/obyekt/{oid}/ulashlar", sarlavha=C)
    tekshir("UL-01: foydalanish soni va oxirgi vaqt yoziladi", ro["ulashlar"][0]["foydalanish"] >= 5 and ro["ulashlar"][0]["oxirgi"])
    kod, _, _ = so("POST", f"/api/v1/ulash/{ul['id']}/bekor", sarlavha=C)
    kod_s, _, _ = xom("GET", uyol)
    kod_f, _, _ = xom("GET", f"{uyol}/chizma.dxf")
    kod_a, _, _ = xom("GET", f"{uyol}/api/tahlillar")
    tekshir("UL-03: bekor qilingach darhol 410 (sahifa, fayl, API)", kod == 200 and kod_s == 410 and kod_f == 410 and kod_a == 410,
            f"{kod_s} {kod_f} {kod_a}")
    kod, ul2, _ = so("POST", f"/api/v1/obyekt/{oid}/ulash", {"nomi": "Muddat sinovi", "kun": 1}, sarlavha=C)
    u = sqlite3.connect(env["YEROSTI_BAZA"])
    u.execute("UPDATE ulash SET muddati='2000-01-01T00:00:00+00:00' WHERE id=?", (ul2["id"],))
    u.commit()
    u.close()
    kod, sah, _ = xom("GET", urlparse_yol(ul2["url"]))
    tekshir("UL-03: muddati tugagan havola 410", kod == 410 and "muddati tugagan" in sah.decode())
    kod, _, _ = xom("GET", "/u/YRU.yoq_token_aaaaaaaaaaaaaaaaaaaa")
    tekshir("UL: noma'lum token 404", kod == 404)

    # TL-01 tarix
    kod, tr, _ = so("GET", f"/api/v1/obyekt/{oid}/tarix", sarlavha=C)
    turlar_t = {h["tur"] for h in tr.get("tarix", [])}
    tekshir("TL-01: tarixda obyekt, liniya, muhr, hujjat (yaratish va bekor), loyiha, ulashish",
            {"obyekt", "liniya", "muhr", "hujjat", "loyiha", "ulash"} <= turlar_t
            and any(h["tur"] == "hujjat" and h.get("holat") == "bekor" for h in tr["tarix"]), str(turlar_t))
    kod, _, _ = so("GET", f"/api/v1/obyekt/{oid}/tarix", sarlavha=B)
    tekshir("TL-01: dala tokeni tarixni ko'rmaydi (403)", kod == 403)

    # TL-03 izoh (tahlil bo'lsa)
    if tayyor:
        tid = m1.get("tahlil_id")
        kod, _, _ = so("POST", f"/api/v1/tahlil/{tid}/izohlar", {"x": 1, "y": 2, "z": 3, "matn": "Mufta"}, sarlavha=B)
        tekshir("TL-03: dala izoh yoza olmaydi (403)", kod == 403)
        kod, _, _ = so("POST", f"/api/v1/tahlil/{tid}/izohlar", {"x": 1, "y": 2, "z": 3, "matn": "  "}, sarlavha=C)
        tekshir("TL-03: bo'sh izoh 400", kod == 400)
        kod, iz, _ = so("POST", f"/api/v1/tahlil/{tid}/izohlar", {"x": 1.25, "y": -0.5, "z": 0.75,
                                                                  "matn": "Mufta, <b>tekshirilsin</b>"}, sarlavha=C)
        kod2, il, _ = so("GET", f"/api/v1/tahlil/{tid}/izohlar", sarlavha=C)
        tekshir("TL-03: admin izoh qo'shdi, ro'yxatda muallif bilan", kod == 200 and kod2 == 200
                and il["izohlar"][0]["matn"] == "Mufta, <b>tekshirilsin</b>" and il["izohlar"][0]["muallif"], str(il)[:200])
        kod, ul3, _ = so("POST", f"/api/v1/obyekt/{oid}/ulash", {"nomi": "3D", "kun": 2}, sarlavha=C)
        kod, iz2, _ = xom("GET", f"{urlparse_yol(ul3['url'])}/api/tahlil/{tid}/izohlar")
        kod_p, ply_u, _ = xom("GET", f"{urlparse_yol(ul3['url'])}/api/tahlil/{tid}/korinish.ply")
        tekshir("TL-03/UL-02: ulashishda izoh va 3D bulut o'qiladi", kod == 200 and len(json.loads(iz2)["izohlar"]) == 1
                and kod_p == 200 and ply_u.startswith(b"ply"))

    # ---------- 15-bo'lim: lokalizatsiya (LK) — SUN'IY mahalliy tizim, haqiqiy shahar tizimi emas ----------
    import math
    import yerosti_lokal as ylk
    from datetime import datetime, timezone

    def msk(lat, lon):
        e, n = ylk.tm(lat, lon, 67.80)
        c, s_ = math.cos(math.radians(0.37)) * 1.00012, math.sin(math.radians(0.37)) * 1.00012
        return s_ * e + c * n - 4435000.0 + 123.4, c * e - s_ * n + 54321.0

    def zeta(lat, lon):
        e, n = ylk.tm(lat, lon, 67.84)
        return -38.5 + 25e-6 * e - 15e-6 * (n - 4.44e6)

    pk = []
    for i, (dl, dn) in enumerate([(-0.004, -0.003), (0.004, -0.003), (0.004, 0.003), (-0.004, 0.003), (0.0005, 0.0)]):
        la, lo, h = 40.1151 + dn, 67.8421 + dl, 350.0 + 3 * i
        X, Y = msk(la, lo)
        pk.append((f"P{i + 1}", la, lo, h, X, Y, h - zeta(la, lo)))
    csv_p = "nomi;X;Y;H;sinf;manba\n" + "".join(f"{n};{X:.4f};{Y:.4f};{H:.4f};4-sinf;sun'iy sinov\n"
                                                  for n, la, lo, h, X, Y, H in pk).replace(".", ",")
    kod, _, _ = so("POST", f"/api/v1/obyekt/{oid}/nazorat-punkt", {"csv": csv_p}, sarlavha=B)
    tekshir("LK-01: dala nazorat punkti kirita olmaydi (403)", kod == 403)
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oid}/nazorat-punkt", {"csv": csv_p}, sarlavha=C)
    tekshir("LK-01: CSV dan 5 punkt (o'nlik vergul bilan)", kod == 200 and m["qoshildi"] == 5, str(m))
    kod, ga, _ = so("GET", f"/api/v1/obyekt/{oid}/geodezik-asos", sarlavha=B)
    tekshir("LK-10: dala qurilmasi punktlarni o'qiydi (joyida qoldiq uchun)", kod == 200 and len(ga["punktlar"]) == 5
            and abs(ga["punktlar"][0]["x"] - pk[0][4]) < 1e-3, str(ga)[:200])
    n1, la1, lo1, h1 = pk[0][:4]
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oid}/nazorat-olchov", {"punkt": n1, "maqsad": "kalibrlash", "lat": la1,
                   "lon": lo1, "h": h1, "rtk_holat": "FLOAT", "sigma_h_sm": 0.8, "sigma_v_sm": 1.2, "davomiylik_s": 35}, sarlavha=B)
    tekshir("LK-02: FLOAT o'lchov rad etiladi", kod == 400 and "FIX" in m.get("xato", ""), str(m))
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oid}/nazorat-olchov", {"punkt": n1, "maqsad": "kalibrlash", "lat": la1,
                   "lon": lo1, "h": h1, "rtk_holat": "FIX", "sigma_h_sm": 0.8, "sigma_v_sm": 1.2, "davomiylik_s": 10}, sarlavha=B)
    tekshir("LK-02: 30 s dan qisqa o'rtachalash rad etiladi", kod == 400 and "30" in m.get("xato", ""), str(m))
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oid}/nazorat-olchov", {"punkt": n1, "maqsad": "kalibrlash", "lat": la1,
                   "lon": lo1, "h": h1, "rtk_holat": "FIX", "sigma_h_sm": 0.8, "sigma_v_sm": 1.2, "davomiylik_s": 35,
                   "epoxalar": 35}, sarlavha=B)
    tekshir("LK-02: dala qurilmasidan to'g'ri o'lchov qabul qilindi", kod == 200, str(m))
    hozir = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.0 UTC+00:00")
    emlid = "Name,Code,Description,Longitude,Latitude,Ellipsoidal height,Elevation RMS,Lateral RMS,Solution status," \
            "Averaging start,Averaging end,Samples\n"
    for n, la, lo, h, X, Y, H in pk[1:]:
        emlid += f"{n},,,{lo:.9f},{la:.9f},{h:.4f},0.012,0.008,FIX,{hozir},{hozir},30\n"
    n5, la5, lo5, h5 = pk[4][:4]
    emlid += f"{n5},,tekshiruv,{lo5 + 2e-7:.9f},{la5:.9f},{h5 + 0.01:.4f},0.012,0.008,FIX,{hozir},{hozir},30\n"
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oid}/nazorat-olchov", {"csv": emlid}, sarlavha=C)
    tekshir("LK-02: Emlid Flow CSV import (4 kalibrlash + 1 tekshiruv)", kod == 200 and len(m["idlar"]) == 5 and not m["xatolar"],
            str(m))
    kod, _, _ = so("POST", f"/api/v1/obyekt/{oid}/lokalizatsiya", {"tizim_nomi": "SINOV MSK"}, sarlavha=B)
    kod0, _, _ = so("POST", f"/api/v1/obyekt/{oid}/lokalizatsiya", {}, sarlavha=C)
    tekshir("LK-03: dala hisoblay olmaydi (403), tizim nomisiz 400", kod == 403 and kod0 == 400)
    kod, lk, _ = so("POST", f"/api/v1/obyekt/{oid}/lokalizatsiya", {"tizim_nomi": "SINOV MSK (sun'iy)"}, sarlavha=C)
    tekshir("LK-03/04: lokalizatsiya: 5 punkt, qoldiq ≤ 1 mm, yaroqli", kod == 200 and lk["yaroqli"] and lk["n_gor"] == 5
            and lk["maks_gor"] < 1e-3 and lk["maks_ver"] < 1e-3, str(lk)[:300])
    kod, ga, _ = so("GET", f"/api/v1/obyekt/{oid}/geodezik-asos", sarlavha=C)
    tek = ga["tekshiruvlar"]
    tekshir("LK-05: tekshiruv o'lchovi baholandi (≈ 1,7 sm sharqqa, 1 sm yuqoriga — o'tdi)",
            len(tek) == 1 and tek[0]["otdi"] and 0.01 < tek[0]["gor"] < 0.025, str(tek))

    kod, hj4, _ = so("POST", "/api/v1/ijro-hujjat", {"obyekt_id": oid}, sarlavha=C)
    _, pdf4, _ = xom("GET", f"/api/v1/ijro-hujjat/{hj4['id']}.pdf", C)
    tm4 = pdf_matn(pdf4)
    birinchi_x, birinchi_y = msk(lat0, lon0)
    tekshir("LK-06: hujjat mahalliy tizimda: tizim nomi, Boltiq, birinchi nuqtaning mahalliy X va Y",
            "SINOV MSK" in tm4 and "Boltiq 1977" in tm4 and matnda_son(tm4, birinchi_x) and matnda_son(tm4, birinchi_y),
            f"{birinchi_x:.3f} {birinchi_y:.3f}")
    tekshir("LK-06: geodezik asos varag'i va yaroqsizlik sababi (PAST nuqtalar), lokalizatsiya sababi YO'Q",
            "Geodezik asos punktlari" in tm4 and "TOPSHIRISHGA YAROQSIZ" in tm4 and "RASMIY emas" in tm4
            and "lokalizatsiya qilinmagan" not in tm4)
    _, sah4, _ = xom("GET", urlparse_yol(qr_oqi(pdf4)))
    tekshir("IH-08: QR sahifasida tizim va yaroqlilik (koordinatasiz)", "SINOV MSK" in sah4.decode() and "yaroqsiz" in sah4.decode()
            and not matnda_son(sah4.decode(), birinchi_x, 5.0) and not matnda_son(sah4.decode(), birinchi_y, 5.0))
    kod, dxf_m, _ = xom("GET", f"/api/v1/chizma?obyekt_id={oid}&format=csv", C)
    kod2, dxf_u, _ = xom("GET", f"/api/v1/chizma?obyekt_id={oid}&format=csv&tizim=utm", C)
    kod3, _, _ = xom("GET", f"/api/v1/chizma?obyekt_id={oid2}&format=csv&tizim=mahalliy", C)
    tekshir("LK-09: CSV standart mahalliy tizimda, ?tizim=utm — UTM, lokalizatsiyasiz obyektda mahalliy 409",
            kod == 200 and matnda_son(dxf_m.decode(), birinchi_y, vergul=False) and kod2 == 200
            and matnda_son(dxf_u.decode(), e0, vergul=False) and kod3 == 409, dxf_m.decode()[:200])

    # LK-07: loyiha mahalliy tizimda (suv liniyasidan 0,12 m surilgan)
    suv_m = [msk(la, lo) for lo, la in suv["geometry"]["coordinates"]]
    lw_m = "".join(f"10\n{Y + 0.12:.4f}\n20\n{X:.4f}\n" for X, Y in suv_m)
    dxf_m2 = f"0\nSECTION\n2\nENTITIES\n0\nLWPOLYLINE\n8\nLOYIHA\n90\n{len(suv_m)}\n{lw_m}0\nENDSEC\n0\nEOF\n".encode()
    kod, m, _ = xom("POST", f"/api/v1/obyekt/{oid}/loyiha?fayl=mahalliy.dxf&z_turi=usti&z_tizimi=boltiq&koordinata=mahalliy",
                    C, dxf_m2)
    kod2, m2, _ = xom("POST", f"/api/v1/obyekt/{oid2}/loyiha?fayl=m.dxf&koordinata=mahalliy", C, dxf_m2)
    tekshir("LK-07: mahalliy loyiha qabul qilindi; lokalizatsiyasiz obyektda 409", kod == 200 and kod2 == 409, f"{m[:150]} {m2[:150]}")
    kod, ly2, _ = so("GET", f"/api/v1/obyekt/{oid}/loyiha", sarlavha=C)
    v0 = ly2["loyiha"]["chiziqlar"][0]["nuqtalar"][0]
    tekshir("LK-07: 3D uchun loyiha UTM ga o'tkazildi (liniyadan 0,12 m)",
            ly2["loyiha"].get("koordinata_asl") == "mahalliy" and abs(math.hypot(v0[0] - uq[0][0], v0[1] - uq[0][1]) - 0.12) < 0.002,
            f"{v0} {uq[0]}")
    kod, hj5, _ = so("POST", "/api/v1/ijro-hujjat", {"obyekt_id": oid}, sarlavha=C)
    _, pdf5, _ = xom("GET", f"/api/v1/ijro-hujjat/{hj5['id']}.pdf", C)
    tm5 = pdf_matn(pdf5)
    tekshir("LK-07: mahalliy loyihadan og'ish hujjatda 0,12 m", " 0,12 " in tm5 and "koordinata: mahalliy" in tm5.replace("\n", " "))

    # LK-08: topoplan
    topo = (f"0\nSECTION\n2\nENTITIES\n0\nTEXT\n8\nY\n10\n{suv_m[0][1] + 3:.3f}\n20\n{suv_m[0][0] + 3:.3f}\n40\n1.5\n1\n"
            f"SINOV ko\\U+0447asi\n0\nLINE\n8\nB\n10\n{suv_m[0][1] - 5:.3f}\n20\n{suv_m[0][0] - 5:.3f}\n11\n"
            f"{suv_m[0][1] + 5:.3f}\n21\n{suv_m[0][0] - 5:.3f}\n0\nENDSEC\n0\nEOF\n").encode()
    kod2, _, _ = xom("POST", f"/api/v1/obyekt/{oid2}/topo?fayl=t.dxf", C, topo)
    kod, m, _ = xom("POST", f"/api/v1/obyekt/{oid}/topo?fayl=topo_sinov.dxf", C, topo)
    tekshir("LK-08: topoplan qabul qilindi (1 chiziq, 1 matn); lokalizatsiyasiz 409",
            kod == 200 and json.loads(m) == {"id": json.loads(m)["id"], "chiziqlar": 1, "matnlar": 1} and kod2 == 409, m[:200])
    kod, hj6, _ = so("POST", "/api/v1/ijro-hujjat", {"obyekt_id": oid}, sarlavha=C)
    _, pdf6, _ = xom("GET", f"/api/v1/ijro-hujjat/{hj6['id']}.pdf", C)
    tm6 = pdf_matn(pdf6)
    tekshir("LK-08: rejada topoplan foni va kirill matni", "topografik plani" in tm6 and "SINOV koчasi" in tm6)

    kod, ga, _ = so("GET", f"/api/v1/obyekt/{oid}/geodezik-asos", sarlavha=C)
    p2_olchov = next(o for o in ga["olchovlar"] if o["punkt_nomi"] == "P2" and o["maqsad"] == "kalibrlash")
    kod, _, _ = so("POST", f"/api/v1/obyekt/{oid}/nazorat-olchov/{p2_olchov['id']}/bekor", sarlavha=C)
    kod2, lk2, _ = so("POST", f"/api/v1/obyekt/{oid}/lokalizatsiya", {"tizim_nomi": "SINOV MSK (sun'iy)"}, sarlavha=C)
    tekshir("LK-02: o'lchov bekor qilinadi, qayta hisobda 4 punkt", kod == 200 and kod2 == 200 and lk2["n_gor"] == 4, str(lk2)[:200])
    kod, tr, _ = so("GET", f"/api/v1/obyekt/{oid}/tarix", sarlavha=C)

    # ---------- 18-bo'lim: quvur tasdig'i (TQ, T-031) — SUN'IY geometriya ----------
    import yerosti_tasdiq as ytq
    from datetime import datetime as _dt, timezone as _tz
    kod, mt, _ = so("POST", "/api/v1/obyektlar", {"nomi": "SINOV TQ obyekt", "pudratchi": "Sinov MChJ", "order_raqami": "TQ-1", "order_sana": "2026-10-01"}, sarlavha=C)
    oidT = mt["id"]
    latT, lonT = 40.1181, 67.8451
    kT = ytq.enu(latT, lonT)
    mLat, mLon = kT(latT + 0.001, lonT)[1] / 0.001, kT(latT, lonT + 0.001)[0] / 0.001

    def llT(e, n):
        return latT + n / mLat, lonT + e / mLon

    def tq_nuqta(e, n, h):
        la, lo = llT(e, n)
        return {"lat": la, "lon": lo, "balandlik": h, "chuqurlik_m": 1.5, "rtk_holat": "FIX", "sigma_h_sm": 1.0, "sigma_v_sm": 2.0,
                "tuzatma_yoshi_s": 1, "manba": "skan"}

    def tq_tasdiq(e, n, h, **q):
        la, lo = llT(e, n)
        t = {"nomi": q.pop("nomi", "T"), "lat": la, "lon": lo, "h": h, "rtk_holat": "FIX", "sigma_h_sm": 0.9, "sigma_v_sm": 1.4,
             "epoxalar": 6, "davomiylik_s": 6, "joy": "usti"}
        t.update(q)
        return t

    # L shaklli skan o'qi: 30 m shimolga, keyin 30 m sharqqa; D160 → quvur usti = o'q + 0,08
    kod, ml, _ = so("POST", "/api/v1/liniyalar", {"obyekt_id": oidT, "turi": "suv", "material": "PE100", "diametr_mm": 160,
                    "nuqtalar": [tq_nuqta(0, 0, 400.0), tq_nuqta(0, 30, 400.0), tq_nuqta(30, 30, 400.0)]}, sarlavha=B)
    lidT = ml["id"]
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oidT}/tasdiq", tq_tasdiq(0.02, 0, 400.08, rtk_holat="FLOAT"), sarlavha=B)
    tekshir("TQ-01: FLOAT tasdiq rad etiladi (T-103)", kod == 400 and "FIX" in m.get("xato", ""), str(m))
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oidT}/tasdiq", tq_tasdiq(0.02, 0, 400.08, sigma_h_sm=3.5), sarlavha=B)
    tekshir("TQ-01: σH 3,5 sm > 2 rad etiladi", kod == 400 and "σH" in m.get("xato", ""), str(m))
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oidT}/tasdiq", tq_tasdiq(0.02, 0, 400.08, davomiylik_s=2), sarlavha=B)
    tekshir("TQ-01: 2 s o'rtachalash rad etiladi (kamida 5 s)", kod == 400 and "5 s" in m.get("xato", ""), str(m))
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oidT}/tasdiq", tq_tasdiq(0.02, 0, 400.08, nomi="T1"), sarlavha=B)
    h1 = (m.get("tasdiq") or {}).get("liniyalar", {}).get(str(lidT)) or {}
    tekshir("TQ-01/05: dala qurilmasidan boshi tasdig'i qabul qilindi; liniya QISMAN (burilish, oxiri yo'q), javobda holat",
            kod == 200 and h1.get("holat") == "qisman" and any("burilish" in x for x in h1.get("kamchiliklar", [])), str(m)[:400])
    hozir_t = _dt.now(_tz.utc).strftime("%Y-%m-%d %H:%M:%S.0 UTC+00:00")
    la2, lo2 = llT(30, 30.02)
    la3, lo3 = llT(0.01, 30)
    emlid_t = ("Name,Code,Description,Longitude,Latitude,Ellipsoidal height,Elevation RMS,Lateral RMS,Solution status,"
               "Averaging start,Averaging end,Samples\n"
               f"T2,,,{lo2:.9f},{la2:.9f},400.07,0.012,0.008,FIX,{hozir_t},{hozir_t},6\n"
               f"T3,,,{lo3:.9f},{la3:.9f},400.09,0.012,0.008,FIX,{hozir_t},{hozir_t},6\n")
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oidT}/tasdiq", {"csv": emlid_t}, sarlavha=C)
    hT = (m.get("tasdiq") or {}).get("liniyalar", {}).get(str(lidT)) or {}
    tekshir("TQ-06: Emlid CSV import (oxiri + burilish) → liniya TASDIQLANGAN", kod == 200 and len(m["idlar"]) == 2
            and hT.get("holat") == "tasdiqlangan", str(m)[:400])
    kod, g, _ = so("GET", "/api/v1/geojson", sarlavha=C)
    fT = next(f for f in g["features"] if f["properties"]["id"] == lidT)
    tekshir("TQ-05: geojson da liniya tasdiq=tasdiqlangan, sifat SKAN (xaritada yaxlit chiziq)",
            fT["properties"]["tasdiq"] == "tasdiqlangan" and fT["properties"]["sifat"] == "SKAN", str(fT["properties"]))
    kod, tqj, _ = so("GET", f"/api/v1/obyekt/{oidT}/tasdiq", sarlavha=B)
    tekshir("TQ-03: dala qurilmasi holatni o'qiydi; 3 tasdiq liniyaga bog'langan, pikitajlar 0 / 30 / 60",
            kod == 200 and len(tqj["tasdiqlar"]) == 3 and all(t["liniya_id"] == lidT and t["otdi"] for t in tqj["tasdiqlar"])
            and sorted(round(t["stansiya"], 1) for t in tqj["tasdiqlar"]) == [0.0, 30.0, 60.0], str([(t["pk"], t["stansiya"]) for t in tqj["tasdiqlar"]]))
    kod, hjT, _ = so("POST", "/api/v1/ijro-hujjat", {"obyekt_id": oidT}, sarlavha=C)
    _, pdfT, _ = xom("GET", f"/api/v1/ijro-hujjat/{hjT['id']}.pdf", C)
    tmT = pdf_matn(pdfT).replace("\n", " ")
    tekshir("TQ-07: PDF — tasdiq bo'limi, liniya TASDIQLANGAN, katalogda «skan, RTK tasdiq», SKAN sababi YO'Q",
            "Quvur tasdig'i (T-031)" in tmT and "TASDIQLANGAN" in tmT and "skan, RTK tasdiq" in tmT
            and "SKAN nuqta RASMIY emas" not in tmT, tmT[:300])
    _, sahT, _ = xom("GET", urlparse_yol(qr_oqi(pdfT)))
    sahT_m = sahT.decode()
    tekshir("IH-08: QR sahifasida tasdiq sanog'i (koordinatasiz)", "1 / 1 skan liniyasi RTK bilan tasdiqlangan" in sahT_m,
            sahT_m[max(0, sahT_m.find("Quvur") - 40):][:400] if "Quvur" in sahT_m else sahT_m[:600])
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oidT}/tasdiq", tq_tasdiq(0.4, 15, 400.08, nomi="T4"), sarlavha=C)
    hF = (m.get("tasdiq") or {}).get("liniyalar", {}).get(str(lidT)) or {}
    tekshir("TQ-05: 40 sm chetdagi tasdiq → FARQ (3/4 chegarada)", kod == 200 and hF.get("holat") == "farq" and hF.get("otgan") == 3, str(hF))
    tid4 = m["idlar"][0]
    kod_b, _, _ = so("POST", f"/api/v1/obyekt/{oidT}/tasdiq/{tid4}/bekor", sarlavha=B)
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oidT}/tasdiq/{tid4}/bekor", sarlavha=C)
    tekshir("TQ: dala bekor qila olmaydi (403); admin bekor qilgach yana TASDIQLANGAN", kod_b == 403 and kod == 200
            and m["tasdiq"]["liniyalar"][str(lidT)]["holat"] == "tasdiqlangan", str(m)[:200])

    # ---------- 20-bo'lim: kuchaytirish (KU) — IFC, liniya atributlari, graf ----------
    kod, ifc_b, sar_i = xom("GET", f"/api/v1/chizma?obyekt_id={oidT}&format=ifc", C)
    tekshir("KU-01: IFC 4.3 fayli yuklanadi (IfcPipeSegment, IfcMapConversion, TRACE4D_Ijro tasdiq holati)",
            kod == 200 and ifc_b.startswith(b"ISO-10303-21") and b"IFCPIPESEGMENT" in ifc_b and b"IFCMAPCONVERSION" in ifc_b
            and b"IFCLABEL('tasdiqlangan')" in ifc_b and ".ifc" in sar_i.get("Content-Disposition", ""), str(ifc_b[:200]))
    kod, m, _ = so("POST", f"/api/v1/liniya/{lidT}", {"egasi": "Sinov Suvsoz", "ishlash_holati": "ishlayapti", "ornatilgan_yil": 2026,
                   "parametr": "0,6 MPa"}, sarlavha=C)
    kodB, _, _ = so("POST", f"/api/v1/liniya/{lidT}", {"egasi": "x"}, sarlavha=B)
    kodX, mx, _ = so("POST", f"/api/v1/liniya/{lidT}", {"ishlash_holati": "noma'lum"}, sarlavha=C)
    kod_g, g, _ = so("GET", "/api/v1/geojson", sarlavha=C)
    fT2 = next(f for f in g["features"] if f["properties"]["id"] == lidT)
    tekshir("KU-02: liniya atributlari (MUDDI) saqlandi va geojson da; dala 403; noto'g'ri holat 400",
            kod == 200 and set(m["yangilandi"]) == {"egasi", "ishlash_holati", "ornatilgan_yil", "parametr"} and kodB == 403 and kodX == 400
            and fT2["properties"]["egasi"] == "Sinov Suvsoz" and fT2["properties"]["ornatilgan_yil"] == 2026, str(m) + str(mx))
    kod, gr, _ = so("GET", f"/api/v1/obyekt/{oidT}/graf", sarlavha=C)
    tekshir("KU-03: tarmoq grafi — L shaklli liniya: 2 tugun (uchlar), 1 qirra", kod == 200 and gr["xulosa"]["tugun"] == 2
            and gr["xulosa"]["uch"] == 2 and len(gr["qirralar"]) == 1 and gr["qirralar"][0]["liniya_id"] == lidT, str(gr["xulosa"]))

    # ---------- 22-bo'lim: me'yorga moslik (ShN-01) — qazish orderi raqami va sanasi, ShNK 3.01.03-24, 420-band ----------
    kod, dxf_b, _ = xom("GET", f"/api/v1/chizma?obyekt_id={oidT}&format=dxf", C)
    tekshir("ShN-01: DXF shtampida «Order: TQ-1, 01.10.2026»", kod == 200 and b"Order: TQ-1, 01.10.2026" in dxf_b, str(dxf_b[:120]))
    kodS, mS, _ = so("POST", "/api/v1/obyektlar", {"nomi": "SINOV ShN obyekt", "order_raqami": "ShN-7", "order_sana": "2026-10-01"},
                     sarlavha=C)
    kodY, mY, _ = so("POST", "/api/v1/obyektlar", {"nomi": "SINOV ShN xato sana", "order_sana": "01.10.2026"}, sarlavha=C)
    kodR, _, _ = so("POST", "/api/v1/obyektlar", ["ro'yxat"], sarlavha=C)
    oidS = mS["id"]
    _, ol, _ = so("GET", "/api/v1/obyektlar", sarlavha=C)
    obS = next(o for o in ol["obyektlar"] if o["id"] == oidS)
    tekshir("ShN-01: obyekt order sanasi bilan yaratiladi; DD.MM.YYYY shakli 400; ro'yxat tanasi 400 (500 emas)",
            kodS == 200 and obS["order_sana"] == "2026-10-01" and kodY == 400 and "YYYY-MM-DD" in str(mY) and kodR == 400
            and not any(o["nomi"] == "SINOV ShN xato sana" for o in ol["obyektlar"]), str(mY))
    subprocess.run([sys.executable, "-c", "import yerosti_baza as b; b.foydalanuvchi_yarat('sinov_koruvchi', 'Sinov-Koruvchi-1', 'koruvchi')"],
                   cwd=YEROSTI, env=env, check=True)
    kodK, _, sarK = so("POST", "/api/v1/kirish", {"login": "sinov_koruvchi", "parol": "Sinov-Koruvchi-1"})
    K = {"Cookie": sarK.get("Set-Cookie", "").split(";")[0]}
    kodE, mE, _ = so("POST", f"/api/v1/obyekt/{oidS}", {"order_raqami": "ShN-8", "order_sana": "2026-10-02",
                                                       "tarmoq_egasi": "Sinov Suvsoz"}, sarlavha=C)
    kod_d, _, _ = so("POST", f"/api/v1/obyekt/{oidS}", {"order_sana": "2026-10-03"}, sarlavha=B)
    kod_k, _, _ = so("POST", f"/api/v1/obyekt/{oidS}", {"order_sana": "2026-10-03"}, sarlavha=K)
    kod_h, m_h, _ = so("POST", f"/api/v1/obyekt/{oidS}", {"holat": "yopiq"}, sarlavha=C)
    kod_s, _, _ = so("POST", f"/api/v1/obyekt/{oidS}", {"order_sana": "2026-02-30"}, sarlavha=C)
    kod_r, _, _ = so("POST", f"/api/v1/obyekt/{oidS}", [1, 2], sarlavha=C)
    kod_b, _, _ = so("POST", f"/api/v1/obyekt/{oidS}", {"nomi": "  "}, sarlavha=C)
    kod_y, _, _ = so("POST", "/api/v1/obyekt/999999", {"order_sana": "2026-10-03"}, sarlavha=C)
    _, ol2, _ = so("GET", "/api/v1/obyektlar", sarlavha=C)
    obS2 = next(o for o in ol2["obyektlar"] if o["id"] == oidS)
    tekshir("ShN-01: rekvizit tahriri — admin 200; dala va ko'ruvchi 403; ruxsatsiz maydon, 30-fevral, ro'yxat, bo'sh nom 400; "
            "yo'q obyekt 404; qiymatlar saqlangan",
            kodK == 200 and kodE == 200 and set(mE["yangilandi"]) == {"order_raqami", "order_sana", "tarmoq_egasi"}
            and kod_d == 403 and kod_k == 403 and kod_h == 400 and "holat" in str(m_h) and kod_s == 400 and kod_r == 400
            and kod_b == 400 and kod_y == 404 and obS2["order_raqami"] == "ShN-8" and obS2["order_sana"] == "2026-10-02"
            and obS2["tarmoq_egasi"] == "Sinov Suvsoz" and obS2["holat"] == "ochiq",
            f"{kodK} {kodE} {kod_d} {kod_k} {kod_h} {kod_s} {kod_r} {kod_b} {kod_y} {obS2}")
    _u = _sq.connect(os.path.join(TMP, "sinov.db"))
    jur = _u.execute("SELECT tafsilot FROM jurnal WHERE amal='obyekt_yangilandi'").fetchall()
    _u.close()
    tekshir("ShN-01: tahrir jurnalga yoziladi (bitta muvaffaqiyatli tahrir — bitta yozuv)",
            len(jur) == 1 and f"id={oidS}" in jur[0][0] and "order_sana" in jur[0][0], str(jur))

    # ---------- 22-bo'lim: ShN-05 — yopiq ishlar dalolatnomasi (ShNQ 3.01.01-22, 6-ilova) + muhrlangan rasmlar ----------
    import io as _io
    from PIL import Image as _Img
    sys.path.insert(0, YEROSTI)
    import yerosti_muhr as ym5

    def jpeg(rang):
        b = _io.BytesIO()
        _Img.new("RGB", (64, 48), rang).save(b, "JPEG", quality=90)
        return b.getvalue()
    r1, r2, r3 = jpeg((40, 90, 200)), jpeg((120, 92, 60)), jpeg((10, 200, 10))

    def yukla_ob(o, turi, data):
        sha = hashlib.sha256(data).hexdigest()
        kod, m, _ = so("POST", "/api/v1/skan/boshla", {"obyekt_id": o, "turi": turi, "hajmi": len(data), "sha256": sha}, sarlavha=B)
        assert kod == 200, m
        for n in range(m["bolak_soni"]):
            b = data[n * m["bolak_hajmi"]:(n + 1) * m["bolak_hajmi"]]
            kod, r, _ = so("PUT", f"/api/v1/skan/{m['skan_id']}/bolak/{n}", xom=b,
                           sarlavha={**B, "X-Bolak-SHA256": hashlib.sha256(b).hexdigest(), "Content-Type": "application/octet-stream"})
            assert kod == 200, r
        kod, r, _ = so("POST", f"/api/v1/skan/{m['skan_id']}/yakunla", sarlavha=B)
        assert kod == 200, r
        return sha
    # jurnal: kalit kadr yozuvlarida r1 va r2 xeshi (r3 jurnalda yo'q — muhrlangan hisoblanmaydi)
    jr = bytearray(ym5.JURNAL_SARLAVHA)
    bosh5, soni5 = ym5.boshlangich(), 0
    for tur, obj in [(7, {"loyiha": "sinov", "tarmoq": "suv"}),
                     (2, {"i": 0, "t": 10.0, "fayl": "kadr_00000.jpg", "jpeg": hashlib.sha256(r1).hexdigest(), "sifat": "RASMIY",
                          "rtk": {"lat": 40.1, "lon": 67.8, "rtk": "FIX", "sigmaH": 1.2}}),
                     (2, {"i": 7, "t": 12.0, "fayl": "kadr_00007.jpg", "jpeg": hashlib.sha256(r2).hexdigest(), "sifat": "RASMIY",
                          "rtk": {"lat": 40.1, "lon": 67.8, "rtk": "FIX", "sigmaH": 1.4}})]:
        d = json.dumps(obj, sort_keys=True).encode()
        jr += bytes([tur]) + struct.pack(">I", len(d)) + d
        bosh5 = ym5.zanjir_qadami(bosh5, tur, d)
        soni5 += 1
    jr = bytes(jr)
    jsha5 = yukla_ob(oidT, "muhr_jurnal", jr)
    for r in (r1, r2, r3):
        yukla_ob(oidT, "foto", r)
    mb5 = json.dumps({"versiya": "YEROSTI-MUHR-v1", "obyekt_id": oidT, "qurilma": "sinov", "boshlandi": "2026-10-05T05:00:00Z",
                      "tugadi": "2026-10-05T05:10:00Z", "yozuv_soni": soni5, "zanjir_boshi": bosh5.hex(),
                      "fayllar": [{"nomi": "jurnal.ymj", "sha256": jsha5, "hajm": len(jr)}]}, sort_keys=True, separators=(",", ":")).encode()
    kod, m5, _ = so("POST", "/api/v1/muhr", {"obyekt_id": oidT, "manifest": base64.b64encode(mb5).decode(),
                                            "imzo": base64.b64encode(kalit.sign(mb5, ec.ECDSA(hashes.SHA256()))).decode()}, sarlavha=B)
    tekshir("ShN-05: rasm xeshlari bor jurnal muhrlandi (TASDIQLANGAN)", kod == 200 and m5.get("holat") == "TASDIQLANGAN", str(m5))
    dal = {"obyekt_id": oidT, "sana": "2026-10-05", "chetga_chiqish": "yoq", "boshlanish": "2026-10-01", "tugash": "2026-10-04",
           "loyiha_hujjati": "Sinov loyiha instituti, 12-SU-01, 15.08.2026",
           "vakillar": {"pudratchi": {"fio": "Sinov Pudratchiyev", "lavozim": "uchastka boshlig'i"}}}
    kod, d5, _ = so("POST", "/api/v1/yopiq-dalolatnoma", dal, sarlavha=C)
    tekshir("ShN-05: dalolatnoma tuzildi — YDA raqami, 2 ta muhrlangan rasm (jurnalda yo'q rasm hisoblanmaydi)",
            kod == 200 and d5["raqam"].startswith("YDA-") and d5["rasmlar"] == 2 and isinstance(d5["kamchiliklar"], list), str(d5))
    kod, pdf5, _ = xom("GET", f"/api/v1/ijro-hujjat/{d5.get('id')}.pdf", C)
    mt5 = " ".join(pdf_matn(pdf5).split())
    tekshir("ShN-05: PDF — 6-ilova shakli: sarlavha, 1-band matni, vakil F.I.O., loyiha, ilova bo'limlari",
            kod == 200 and "YOPIQ ISHLAR DALOLATNOMASI" in mt5 and "Aniqlik kiritishga quyidagi ishlar taqdim etilgan" in mt5
            and "Sinov Pudratchiyev" in mt5 and "ShNQ 3.01.01-22, 6-ilova" in mt5 and "Muhrlangan rasmlar (2 ta)" in mt5
            and "yo'l qo'yilmagan" in mt5 and "Raqamli muhrlar" in mt5, mt5[:400])
    pd5 = os.path.join(TMP, "dal.pdf")
    open(pd5, "wb").write(pdf5)
    rd5 = os.path.join(TMP, "dalrasm")
    os.makedirs(rd5, exist_ok=True)
    subprocess.run(["pdfimages", "-j", pd5, os.path.join(rd5, "r")], check=True)
    chiqqan = sorted(hashlib.sha256(open(os.path.join(rd5, f), "rb").read()).hexdigest() for f in os.listdir(rd5) if f.endswith(".jpg"))
    tekshir("ShN-05: PDF dagi rasmlar muhrlangan baytlar bilan aynan bir xil (qayta kodlanmagan)",
            chiqqan == sorted([hashlib.sha256(r1).hexdigest(), hashlib.sha256(r2).hexdigest()]), str(len(chiqqan)))
    kod, t5, _ = so("GET", "/t/" + d5["tekshirish_url"].rsplit("/t/", 1)[1])
    t5 = bytes(t5).decode() if isinstance(t5, (bytes, bytearray)) else str(t5)
    tekshir("ShN-05: QR sahifasi — dalolatnoma turi, rasmlar soni; komissiya ismi va koordinata YO'Q",
            kod == 200 and "Yopiq ishlar dalolatnomasi" in t5 and "Muhrlangan rasmlar" in t5 and "Sinov Pudratchiyev" not in t5
            and "40.1" not in t5 and "67.8" not in t5, t5[:300])
    kod_d, _, _ = so("POST", "/api/v1/yopiq-dalolatnoma", dal, sarlavha=B)
    kod_k, _, _ = so("POST", "/api/v1/yopiq-dalolatnoma", dal, sarlavha=K)
    kod_s, _, _ = so("POST", "/api/v1/yopiq-dalolatnoma", {**dal, "sana": "05.10.2026"}, sarlavha=C)
    kod_c, _, _ = so("POST", "/api/v1/yopiq-dalolatnoma", {**dal, "chetga_chiqish": "balki"}, sarlavha=C)
    kod_l, ml, _ = so("POST", "/api/v1/yopiq-dalolatnoma", {**dal, "liniya_idlar": [999999]}, sarlavha=C)
    kod_t, _, _ = so("POST", "/api/v1/yopiq-dalolatnoma", {**dal, "boshlanish": "2026-10-05", "tugash": "2026-10-01"}, sarlavha=C)
    kod_b, mb_, _ = so("POST", "/api/v1/yopiq-dalolatnoma", {**dal, "obyekt_id": oidS}, sarlavha=C)
    tekshir("ShN-05: dala va ko'ruvchi 403; noto'g'ri sana, tanlov, begona liniya, teskari sanalar 400; liniyasiz obyekt 409",
            (kod_d, kod_k, kod_s, kod_c, kod_l, kod_t, kod_b) == (403, 403, 400, 400, 400, 400, 409), f"{kod_d} {kod_k} {kod_s} {kod_c} {kod_l} {kod_t} {kod_b} {ml} {mb_}")
    _, hl5, _ = so("GET", f"/api/v1/ijro-hujjatlar?obyekt_id={oidT}", sarlavha=C)
    tekshir("ShN-05: hujjatlar ro'yxatida tur 'yopiq', xulosada dalil holati", any(h.get("tur") == "yopiq" and h["xulosa"].get("rasmlar") == 2
                                                                               for h in hl5["hujjatlar"]), str(hl5)[:300])

    # ---------- 23-bo'lim: T1 — quduq/zadvijka QR-belgisi (/q/<kod>) ----------
    bt = {"liniya_id": lidT, "nuqta": 0, "tur": "quduq", "raqam": "Q-1", "aloqa": "+998 72 000 00 00"}
    kod, b1, _ = so("POST", "/api/v1/belgilar", bt, sarlavha=C)
    k_takror, _, _ = so("POST", "/api/v1/belgilar", bt, sarlavha=C)
    k_tur, _, _ = so("POST", "/api/v1/belgilar", {**bt, "raqam": "Q-2", "tur": "quvur"}, sarlavha=C)
    k_nuqta, _, _ = so("POST", "/api/v1/belgilar", {**bt, "raqam": "Q-2", "nuqta": 999}, sarlavha=C)
    k_lin, _, _ = so("POST", "/api/v1/belgilar", {**bt, "raqam": "Q-2", "liniya_id": 999999}, sarlavha=C)
    k_dala, _, _ = so("POST", "/api/v1/belgilar", {**bt, "raqam": "Q-3"}, sarlavha=B)
    k_kor, _, _ = so("POST", "/api/v1/belgilar", {**bt, "raqam": "Q-3"}, sarlavha=K)
    tekshir("T1-1: belgi liniya nuqtasidan yaratildi (16 belgili kod); takror raqam, noto'g'ri tur, nuqta 400; yo'q liniya 404; "
            "dala va ko'ruvchi 403", kod == 200 and len(b1.get("kod", "")) == 16 and "/q/" in b1.get("url", "")
            and (k_takror, k_tur, k_nuqta, k_lin, k_dala, k_kor) == (400, 400, 400, 404, 403, 403),
            f"{b1} {k_takror} {k_tur} {k_nuqta} {k_lin} {k_dala} {k_kor}")
    qyol = "/q/" + b1["kod"]
    kod, qa, _ = so("GET", qyol)
    qa = bytes(qa).decode()
    _, lt, _ = so("GET", "/api/v1/geojson", sarlavha=C)
    lt_k = next(f for f in lt["features"] if f["properties"]["id"] == lidT)["geometry"]["coordinates"][0]
    tekshir("T1-2: kirishsiz — belgi, tarmoq egasi, aloqa, ogohlantirish; koordinata, chuqurlik va atrofdagi tarmoqlar YO'Q",
            kod == 200 and "Q-1" in qa and "Quduq" in qa and "Sinov Suvsoz" in qa and "+998 72 000 00 00" in qa
            and "yer osti muhandislik tarmog'i bor" in qa and f"{lt_k[1]:.5f}" not in qa and f"{lt_k[0]:.5f}" not in qa
            and "Atrofdagi" not in qa and "Chuqurlik" not in qa and "keyin=/q/" in qa, qa[:400])
    kod, qt, _ = so("GET", qyol, sarlavha=C)
    qt = bytes(qt).decode()
    _, bl, _ = so("GET", f"/api/v1/belgilar?obyekt_id={oidT}", sarlavha=C)
    kod_bl_d, _, _ = so("GET", f"/api/v1/belgilar?obyekt_id={oidT}", sarlavha=B)
    tekshir("T1-3/T1-5: sessiya bilan — to'liq (koordinata, chuqurlik, atrofdagi tarmoqlar); ko'rishlar soni 2; ro'yxat dala uchun 403",
            kod == 200 and "Atrofdagi tarmoqlar (30 m)" in qt and "Koordinata (WGS-84)" in qt and "Chuqurlik" in qt
            and f"{lt_k[1]:.5f}" in qt and bl["belgilar"][0]["korishlar"] == 2 and kod_bl_d == 403, qt[:300])
    kod, plast, sar_p = xom("GET", f"/api/v1/belgilar/plastinka.pdf?obyekt_id={oidT}", C)
    kod_pd, _, _ = xom("GET", f"/api/v1/belgilar/plastinka.pdf?obyekt_id={oidT}", B)
    yp = os.path.join(TMP, "plast.pdf")
    open(yp, "wb").write(plast)
    subprocess.run(["pdftoppm", "-r", "220", "-f", "1", "-l", "1", "-png", yp, os.path.join(TMP, "plast")], check=True)
    rp = cv2.imread(os.path.join(TMP, "plast-1.png"))
    mmp = rp.shape[1] / 210.0
    # 1-yorliq QR qutisi: x 55…97 mm, yuqoridan 28…70 mm (+ 6 mm bo'sh hoshiya)
    kp = rp[int(22 * mmp):int(76 * mmp), int(49 * mmp):int(103 * mmp)]
    qr_url = cv2.QRCodeDetector().detectAndDecode(kp)[0]
    tekshir("T1-4: plastinka PDF (A4) — QR o'qiladi va belgi havolasiga olib boradi; dala 403",
            kod == 200 and plast.startswith(b"%PDF") and qr_url == b1["url"] and kod_pd == 403, f"{qr_url!r} {b1['url']}")
    kod_bk, _, _ = so("POST", f"/api/v1/belgi/{b1['id']}/bekor", {"sabab": "x"}, sarlavha=K)
    kod_bs, _, _ = so("POST", f"/api/v1/belgi/{b1['id']}/bekor", {}, sarlavha=C)
    kod_b, _, _ = so("POST", f"/api/v1/belgi/{b1['id']}/bekor", {"sabab": "quduq qayta qurildi"}, sarlavha=C)
    kod_q, qb, _ = so("GET", qyol)
    kod_y, _, _ = so("GET", "/q/YoqBelgi_123456")
    kod_p2, _, _ = xom("GET", f"/api/v1/belgilar/plastinka.pdf?obyekt_id={oidT}", C)
    tekshir("T1-5: bekor — ko'ruvchi 403, sababsiz 400, admin 200; skanerda 410 «bekor qilingan»; yo'q kod 404; plastinka 409",
            (kod_bk, kod_bs, kod_b, kod_q, kod_y, kod_p2) == (403, 400, 200, 410, 404, 409) and "bekor qilingan" in bytes(qb).decode(),
            f"{kod_bk} {kod_bs} {kod_b} {kod_q} {kod_y} {kod_p2}")

    # ---------- 23-bo'lim: T3 — loyiha–ijro muvofiqligi ----------
    kod, mvj, _ = so("GET", f"/api/v1/obyekt/{oid}/muvofiqlik", sarlavha=C)
    kod_ly, _, _ = so("GET", f"/api/v1/obyekt/{oidT}/muvofiqlik", sarlavha=C)
    tekshir("T3: muvofiqlik JSON — liniyalar, joylar, qamrov, qaror qoidasi; loyihasiz obyekt 409",
            kod == 200 and mvj["liniyalar"] and "joylar" in mvj and mvj["qamrov"] and "2σ" in mvj["qoida"] and kod_ly == 409, str(mvj)[:300])
    kod, mh, _ = so("POST", "/api/v1/muvofiqlik-hisobot", {"obyekt_id": oid}, sarlavha=C)
    kod_md, _, _ = so("POST", "/api/v1/muvofiqlik-hisobot", {"obyekt_id": oid}, sarlavha=B)
    kod_ml, _, _ = so("POST", "/api/v1/muvofiqlik-hisobot", {"obyekt_id": oidT}, sarlavha=C)
    kod, mpdf, _ = xom("GET", f"/api/v1/ijro-hujjat/{mh.get('id')}.pdf", C)
    tm3 = " ".join(pdf_matn(mpdf).split())
    tekshir("T3-4: hisobot ro'yxatdan o'tdi (YLM), PDF da sarlavha va manba; dala 403, loyihasiz 409",
            mh.get("raqam", "").startswith("YLM-") and "LOYIHA–IJRO MUVOFIQLIGI HISOBOTI" in tm3 and "SNiP 3.05.04-85*" in tm3
            and kod_md == 403 and kod_ml == 409, str(mh)[:200])
    kod, tm3p, _ = so("GET", "/t/" + mh["tekshirish_url"].rsplit("/t/", 1)[1])
    tekshir("T3: QR sahifasi — hisobot turi va sanoqlar", kod == 200 and "Loyiha–ijro muvofiqligi" in bytes(tm3p).decode(), str(kod))

    # ---------- 19-bo'lim: tashqi LiDAR importi (LD-02) — SUN'IY LAS ----------
    import yerosti_las as ylas
    import yerosti_chizma as ychz
    latL, lonL = 40.1191, 67.8461
    eL, nL, zL = ychz.utm(latL, lonL, None)
    # 6 m quvur D160 (radius 0,08) sharqqa, usti ko'rinadigan yoy; transheya tubi va yer sirti
    nuq = []
    import math as _m
    for i in range(0, 601):
        sx = i * 0.01
        for teta in range(-100, 101, 7):
            a = _m.radians(teta)
            nuq.append((eL + sx, nL + 0.08 * _m.sin(a), 398.0 + 0.08 * _m.cos(a)))
    for i in range(0, 121):
        sx = i * 0.05
        for yy in range(-30, 31, 5):
            y = yy * 0.01
            if abs(y) > 0.12:
                nuq.append((eL + sx, nL + y, 397.7))        # transheya tubi (quvur ostida ko'rinmaydi)
            nuq.append((eL + sx, nL + (1.0 if yy >= 0 else -1.0) + y, 399.5))   # yer sirti
    las_b = ylas.las_yoz(nuq)
    kod, mL, _ = so("POST", "/api/v1/obyektlar", {"nomi": "SINOV LD obyekt", "pudratchi": "Sinov MChJ"}, sarlavha=C)
    oidL = mL["id"]
    sha_l = hashlib.sha256(las_b).hexdigest()
    kod, bl, _ = so("POST", "/api/v1/skan/boshla", {"obyekt_id": oidL, "turi": "nuqta_las", "hajmi": len(las_b), "sha256": sha_l}, sarlavha=C)
    tekshir("LD-02: admin LAS faylini skan API bilan yuklay boshlaydi (turi nuqta_las)", kod == 200 and bl["bolak_soni"] >= 1, str(bl))
    for i in range(bl["bolak_soni"]):
        b = las_b[i * bl["bolak_hajmi"]:(i + 1) * bl["bolak_hajmi"]]
        kod, _, _ = so("PUT", f"/api/v1/skan/{bl['skan_id']}/bolak/{i}", xom=b,
                       sarlavha={**C, "Content-Type": "application/octet-stream", "X-Bolak-SHA256": hashlib.sha256(b).hexdigest()})
    kod, y, _ = so("POST", f"/api/v1/skan/{bl['skan_id']}/yakunla", {}, sarlavha=C)
    tekshir("LD-02: LAS yuklandi va xeshi tekshirildi", kod == 200 and y["holat"] == "tayyor", str(y))
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oidL}/tashqi-skan", {"skan_id": bl["skan_id"], "koordinata": "utm", "zona": zL,
                   "manba": "SINOV SLAM skaner", "aniqlik_sm": 3, "tarmoq_turi": "suv"}, sarlavha=B)
    tekshir("LD-02: dala tokeni tashqi import qila olmaydi (403)", kod == 403)
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oidL}/tashqi-skan", {"skan_id": bl["skan_id"], "koordinata": "mahalliy",
                   "manba": "x", "aniqlik_sm": 3, "tarmoq_turi": "suv"}, sarlavha=C)
    tekshir("LD-02: lokalizatsiyasiz obyektda mahalliy koordinata 400", kod == 400 and "lokalizatsiya" in m.get("xato", ""), str(m))
    kod, m, _ = so("POST", f"/api/v1/obyekt/{oidL}/tashqi-skan", {"skan_id": bl["skan_id"], "koordinata": "utm", "zona": zL,
                   "manba": "SINOV SLAM skaner", "aniqlik_sm": 3, "tarmoq_turi": "suv"}, sarlavha=C)
    tekshir("LD-02: tashqi tahlil navbatga qo'yildi", kod == 200 and m.get("holat") == "kutmoqda", str(m))
    tidL = m.get("tahlil_id")
    if tayyor:
        rL = subprocess.run([sys.executable, "yerosti_ishchi.py", "--bir-marta"], cwd=YEROSTI, env=env, capture_output=True, text=True, timeout=600)
        kod, tL, _ = so("GET", f"/api/v1/tahlil/{tidL}", sarlavha=C)
        q = (tL.get("natija") or {}).get("quvurlar") or []
        tekshir("LD-02: ishchi LAS ni UTM PLY ga keltirib quvurni topdi (TASHQI, 1 quvur, Ø160 ± 10 mm, uzunlik ≈ 6 m)",
                tL.get("holat") == "tayyor" and tL.get("xulosa") == "TASHQI" and len(q) == 1
                and abs((q[0].get("standart_mm") or q[0]["diametr_mm"]) - 160) <= 10 and 5.5 <= q[0]["uzunlik_m"] <= 6.5,
                str(tL)[:400] + rL.stdout[-300:] + rL.stderr[-300:])
        kod, g, _ = so("GET", "/api/v1/geojson", sarlavha=C)
        fL = [f for f in g["features"] if f["properties"]["obyekt_id"] == oidL]
        tekshir("LD-02: natijadan SKAN liniya yaratildi (manba skan, izohda skaner nomi va aniqlik 3 sm), o'q UTM da ≤ 3 sm",
                len(fL) == 1 and fL[0]["properties"]["sifat"] == "SKAN" and "SINOV SLAM" in fL[0]["properties"]["izoh"]
                and "aniqlik 3 sm" in fL[0]["properties"]["izoh"]
                and all(abs(ychz.utm(la, lo, zL)[1] - nL) <= 0.03 for lo, la in fL[0]["geometry"]["coordinates"]),
                str(fL)[:400])
        kod, kL, _ = xom("GET", f"/api/v1/tahlil/{tidL}/korinish.ply", C)
        tekshir("LD-02: 3D ko'rinish buluti bor; tasdiqsiz hujjat sababida T-031", kod == 200 and kL[:3] == b"ply")
    else:
        tekshir("LD-02: ishchi sinovi o'tkazilmadi (CLI yo'q)", False, "yerosti-tahlil release yig'ilmagan")

    # ---------- 16-bo'lim: xarita asoslari (SY) ----------
    kod, xs, sar = so("GET", "/api/v1/xarita-sozlama", sarlavha=C)
    a = {x["id"]: x for x in xs.get("asoslar", [])}
    tekshir("SY-01/02: sozlamada ortofoto (MBTiles metama'lumoti, ±0,3 m) va tashqi sun'iy yo'ldosh (atributsiya, ±5 m)",
            kod == 200 and a.get("ortofoto", {}).get("maks_zoom") == 18 and a["ortofoto"]["aniqlik_m"] == 0.3
            and a["ortofoto"]["chegara"] == [67.83, 40.10, 67.85, 40.13] and a.get("suniy", {}).get("atributsiya") == "SINOV manba"
            and a["suniy"]["aniqlik_m"] == 5 and "manba" not in a["suniy"], str(xs))
    csp = sar.get("Content-Security-Policy", "")
    tekshir("SY-02: CSP faqat sozlangan sun'iy yo'ldosh manziliga ochilgan (img-src va connect-src)",
            "img-src 'self' data: blob: https://tiles.openfreemap.org https://plitka.sinov.example;" in csp
            and "connect-src 'self' https://tiles.openfreemap.org https://plitka.sinov.example;" in csp, csp)
    kod, xd, _ = so("GET", "/api/v1/xarita-sozlama", sarlavha=B)
    tekshir("SY-01: dala tokeniga ortofoto berilmaydi (sozlamada yo'q)", kod == 200 and all(x["id"] != "ortofoto" for x in xd["asoslar"]))
    yol_p = f"/xarita/ortofoto/16/{PX}/{PY}"
    k1, _, _ = xom("GET", yol_p)
    k2, b2, s2 = xom("GET", yol_p, C)
    k3, _, _ = xom("GET", f"/xarita/ortofoto/16/{PX + 1}/{PY}", C)
    k4, _, _ = xom("GET", yol_p, B)
    k5, _, _ = xom("GET", "/xarita/ortofoto/16/x/1", C)
    tekshir("SY-01: plitka: kirishsiz 401, dala 403, portal 200 bayt-baybayt, qamrovdan tashqari 204, noto'g'ri yo'l 404",
            k1 == 401 and k4 == 403 and k2 == 200 and b2 == PLITKA and s2.get("Content-Type") == "image/png"
            and k3 == 204 and k5 == 404, f"{k1} {k4} {k2} {k3} {k5}")

    # ochiq sahifalar: daqiqasiga 60 so'rov
    kodlar = [xom("GET", "/t/YoqKod_12345678")[0] for _ in range(62)]
    tekshir("IH-08: /t/ kod terishga qarshi cheklov (429)", kodlar[-1] == 429 and kodlar[0] == 404, str(kodlar[-3:]))

    # ---------- DM-07: X-Real-IP faqat ishonchli proksidan (kirish cheklovi aylanib o'tilmaydi) ----------
    kodlar = [so("POST", "/api/v1/kirish", {"login": "admin", "parol": "xato"}, sarlavha={"X-Real-IP": f"10.9.0.{i}"})[0]
              for i in range(9)]
    # boshdagi admin kirishi ham shu daqiqadagi 8 urinishga kiradi — muhimi: X-Real-IP almashtirib cheklov aylanib o'tilmaydi
    tekshir("ishonchsiz manbadan X-Real-IP e'tiborsiz: cheklov baribir ishlaydi (429)", 429 in kodlar, str(kodlar))
    # ikkinchi server uchun bo'sh port (PORT + 1 band bo'lsa so'rovlar boshqa jarayonga ketib, sinov yolg'on yiqilardi)
    import socket
    with socket.socket() as sk:
        sk.bind(("127.0.0.1", 0))
        port2 = sk.getsockname()[1]
    # ikkinchi server: proksi sinovi + SY-02 atributsiyasiz tashqi manba yoqilmasligi
    env2 = {k: v for k, v in env.items() if k not in ("YEROSTI_ORTOFOTO", "YEROSTI_SUNIY_ATRIBUTSIYA")}
    srv2 = subprocess.Popen([sys.executable, "-u", "yerosti_server.py", "--port", str(port2)], cwd=YEROSTI,
                            env=dict(env2, YEROSTI_PROKSI_TARMOQ="127.0.0.1/32"), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(80):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{port2}/api/v1/salomatlik", timeout=1)
                break
            except Exception:
                time.sleep(0.1)

        def kir2(ip):
            r = urllib.request.Request(f"http://127.0.0.1:{port2}/api/v1/kirish", method="POST",
                                       data=json.dumps({"login": "admin", "parol": "xato"}).encode(),
                                       headers={"Content-Type": "application/json", "X-Yerosti": "1", "X-Real-IP": ip})
            try:
                return urllib.request.urlopen(r, timeout=5).status
            except urllib.error.HTTPError as x:
                return x.code
        r2 = urllib.request.urlopen(f"http://127.0.0.1:{port2}/api/v1/salomatlik", timeout=5)
        csp2 = r2.headers.get("Content-Security-Policy", "")
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port2}/xarita/ortofoto/16/{PX}/{PY}", timeout=5)
            k_o = 200
        except urllib.error.HTTPError as x:
            k_o = x.code
        tekshir("SY-02: atributsiyasiz tashqi manba yoqilmaydi (CSP da yo'q); ortofoto sozlanmagan — 404",
                "plitka.sinov.example" not in csp2 and k_o == 404, f"{csp2} {k_o}")
        a = [kir2("10.9.1.1") for _ in range(9)]
        tekshir("ishonchli proksi: har mijoz alohida cheklanadi (A bloklandi, B yo'q)",
                a[-1] == 429 and kir2("10.9.1.2") != 429, str(a))

        def kir2_cookie(proto):
            r = urllib.request.Request(f"http://127.0.0.1:{port2}/api/v1/kirish", method="POST",
                                       data=json.dumps({"login": "admin", "parol": env["YEROSTI_ADMIN_PAROL"]}).encode(),
                                       headers={"Content-Type": "application/json", "X-Yerosti": "1", "X-Real-IP": "10.9.2.7",
                                                **({"X-Forwarded-Proto": proto} if proto else {})})
            return urllib.request.urlopen(r, timeout=5).headers.get("Set-Cookie", "")
        ck_s, ck_o = kir2_cookie("https"), kir2_cookie(None)
        tekshir("HTTPS proksi ortida sessiya cookie Secure + HttpOnly; proksisiz HTTP da Secure yo'q",
                "; Secure" in ck_s and "HttpOnly" in ck_s and "Secure" not in ck_o, f"{ck_s[-40:]} | {ck_o[-40:]}")
    finally:
        srv2.terminate()
        srv2.wait(timeout=5)

    kod, _, _ = so("POST", f"/api/v1/dala-tokenlar/{token_id}/bekor", sarlavha=C)
    kod, _, _ = so("GET", "/api/v1/men", sarlavha=B)
    tekshir("bekor qilingan token 401", kod == 401)
finally:
    srv.terminate()
    try:
        srv.wait(timeout=5)
    except Exception:
        srv.kill()
    shutil.rmtree(TMP, ignore_errors=True)

yiq = sum(1 for _, ok in natijalar if not ok)
print(f"\nJAMI: {len(natijalar)} tekshiruv, {yiq} FAIL")
sys.exit(1 if yiq else 0)
