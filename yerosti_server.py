"""YEROSTI — HTTP server (stdlib, tashqi kutubxonasiz).

API v1: portal (cookie sessiya) va dala ilovasi (Bearer YRD. token).
Xavfsizlik: token sha256 bazada, cookie-so'rovlarda X-Yerosti sarlavhasi (CSRF),
kirishga IP cheklovi, xavfsizlik sarlavhalari, skan bo'laklari sha256 bilan.
"""
import argparse
import json
import sqlite3
import math
import mimetypes
import os
import re
import secrets
import sys
import time
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import base64
import binascii
import hashlib
import ipaddress

import yerosti_baza as baza
import yerosti_chizma as chizma
import yerosti_belgi as belgi_mod
import yerosti_dalolatnoma as dalolatnoma
import yerosti_muvofiqlik as muvofiqlik
import yerosti_ijro as ijro
import yerosti_ifc as ifc_mod
import yerosti_ijro_geo as ijro_geo
import yerosti_lokal as lokal
import yerosti_muhr as muhr
import yerosti_ochiq as ochiq
import yerosti_tasdiq as tasdiq_mod
import yerosti_xarita as xarita_asos

ILDIZ = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(ILDIZ, "web")
JSON_CHEK = 2 * 1024 * 1024
BOLAK_CHEK = baza.BOLAK_HAJMI
COOKIE_NOMI = "yerosti_sessiya"
YOZUVCHI_ROLLAR = ("admin", "operator", "dala")

# DM-01: veb kutubxonalar serverning o'zidan (web/vendor). Tashqi manba faqat xarita uslubi/plitkalari —
# manzili sozlanadi (hokimlik data markazida mahalliy plitka serveri); "yoq" — asos xaritasiz rejim.
XARITA_USLUB = os.environ.get("YEROSTI_XARITA_USLUB", "https://tiles.openfreemap.org/styles/positron").strip()


def _manba(url):
    u = urlparse(url)
    return f"{u.scheme}://{u.netloc}" if u.scheme in ("http", "https") and u.netloc else ""


XARITA_MANBA = _manba(XARITA_USLUB)


def _ixtiyoriy_son(nom, tur=float):
    try:
        v = os.environ.get(nom, "").strip()
        return tur(v.replace(",", ".")) if v else None
    except ValueError:
        return None


# SY-01: shahar ortofotosi (MBTiles) — serverning o'zidan, faqat portalga kirganlarga
ORTOFOTO = None
if os.environ.get("YEROSTI_ORTOFOTO", "").strip():
    try:
        ORTOFOTO = xarita_asos.MBTiles(os.environ["YEROSTI_ORTOFOTO"].strip())
    except (OSError, sqlite3.Error) as _x:
        sys.stderr.write(f"[yerosti] ortofoto MBTiles ochilmadi: {_x}\n")
ORTOFOTO_ANIQLIK_M = _ixtiyoriy_son("YEROSTI_ORTOFOTO_ANIQLIK_M")
# SY-02: tashqi sun'iy yo'ldosh — faqat admin sozlasa va atributsiya bo'lsa; CSP faqat o'sha manzilga
SUNIY = xarita_asos.tashqi_tavsif(os.environ.get("YEROSTI_SUNIY_URL", "").strip(),
                                  os.environ.get("YEROSTI_SUNIY_ATRIBUTSIYA", "").strip(),
                                  _ixtiyoriy_son("YEROSTI_SUNIY_ANIQLIK_M"), _ixtiyoriy_son("YEROSTI_SUNIY_MAKS_ZOOM", int))
SUNIY_MANBA = SUNIY["manba"] if SUNIY else ""
_RASM_MANBALARI = " ".join(x for x in (XARITA_MANBA, SUNIY_MANBA) if x)
CSP = (
    "default-src 'self'; "
    "script-src 'self'; "
    "style-src 'self' 'unsafe-inline'; "
    f"img-src 'self' data: blob: {_RASM_MANBALARI}; ".replace(" ;", ";") +
    f"connect-src 'self' {_RASM_MANBALARI}; ".replace(" ;", ";") +
    "worker-src 'self'; "
    "font-src 'self' data:; "
    "base-uri 'none'; "
    "form-action 'self'; "
    "frame-ancestors 'none'"
)
VERSIYA = "TRACE4D server 1.2"
# IH-08/UL-01: QR va ulashish havolasidagi tashqi manzil (https://trace4d.uz). Bo'lmasa so'rov Host sarlavhasidan.
TASHQI_URL = os.environ.get("YEROSTI_TASHQI_URL", "").strip().rstrip("/")
LOYIHA_CHEK = 10 * 1024 * 1024
LOYIHA_UZOQ_M = 1000.0      # loyiha obyekt liniyalaridan shundan uzoq — zona yoki koordinata tizimi xato
TOPO_CHEK = 10 * 1024 * 1024
# DM-04/DM-07: TLS proksi (Caddy) ortida mijoz IP si X-Real-IP da. Unga FAQAT shu tarmoqlardan kelgan
# ulanishda ishoniladi — aks holda kirish cheklovi (8/daq) hamma uchun bitta proksi IP siga tushadi yoki soxtalashtiriladi.
PROKSI_TARMOQLAR = [ipaddress.ip_network(x.strip(), strict=False)
                    for x in os.environ.get("YEROSTI_PROKSI_TARMOQ", "").split(",") if x.strip()]

_SKAN_BOLAK = re.compile(r"^/api/v1/skan/(\d+)/bolak/(\d+)$")
_SKAN_ID = re.compile(r"^/api/v1/skan/(\d+)$")
_SKAN_YAKUN = re.compile(r"^/api/v1/skan/(\d+)/yakunla$")
_TOKEN_BEKOR = re.compile(r"^/api/v1/dala-tokenlar/(\d+)/bekor$")
_TAHLIL_ID = re.compile(r"^/api/v1/tahlil/(\d+)$")
_TAHLIL_KORINISH = re.compile(r"^/api/v1/tahlil/(\d+)/korinish\.ply$")
_TAHLIL_QAYTA = re.compile(r"^/api/v1/tahlil/(\d+)/qayta$")
_TAHLIL_IZOH = re.compile(r"^/api/v1/tahlil/(\d+)/izohlar$")
_HUJJAT_PDF = re.compile(r"^/api/v1/ijro-hujjat/(\d+)\.pdf$")
_HUJJAT_BEKOR = re.compile(r"^/api/v1/ijro-hujjat/(\d+)/bekor$")
_OBYEKT_QISM = re.compile(r"^/api/v1/obyekt/(\d+)/(loyiha|ulash|ulashlar|tarix|geodezik-asos|nazorat-punkt|nazorat-olchov|"
                          r"lokalizatsiya|topo|tasdiq|tashqi-skan|graf|farq|muvofiqlik)$")
_ASOS_BEKOR = re.compile(r"^/api/v1/obyekt/(\d+)/(nazorat-punkt|nazorat-olchov|tasdiq)/(\d+)/bekor$")
_LINIYA_ID = re.compile(r"^/api/v1/liniya/(\d+)$")
_OBYEKT_ID = re.compile(r"^/api/v1/obyekt/(\d+)$")   # ShN-01: obyekt rekvizitlarini tahrirlash
_ULASH_BEKOR = re.compile(r"^/api/v1/ulash/(\d+)/bekor$")
_TEKSHIR = re.compile(r"^/t/([A-Za-z0-9_-]{8,64})$")
_BELGI_YOL = re.compile(r"^/q/([A-Za-z0-9_-]{8,64})$")             # T1: QR-belgi
_BELGI_BEKOR = re.compile(r"^/api/v1/belgi/(\d+)/bekor$")
_ORTOFOTO = re.compile(r"^/xarita/ortofoto/(\d{1,2})/(\d{1,8})/(\d{1,8})(?:\.(?:png|jpg|jpeg|webp))?$")
_ULASH_YOL = re.compile(r"^/u/(YRU\.[A-Za-z0-9_-]{20,64})(/.*)?$")
PORTAL_ROLLAR = ("admin", "operator", "koruvchi")
HUJJAT_ROLLAR = ("admin", "operator")

_kirish_urinishlari = {}
_ochiq_urinishlar = {}


def _kirish_ruxsatmi(ip):
    hozir = time.time()
    tarix = [t for t in _kirish_urinishlari.get(ip, []) if hozir - t < 60]
    _kirish_urinishlari[ip] = tarix
    if len(tarix) >= 8:
        return False
    tarix.append(hozir)
    return True


def _ochiq_ruxsatmi(ip, chek=60):
    """/t/ va /u/ — kirishsiz sahifalar: IP ga daqiqasiga 60 so'rov (kod/token terish hujumiga qarshi)."""
    hozir = time.time()
    tarix = [t for t in _ochiq_urinishlar.get(ip, []) if hozir - t < 60]
    if len(_ochiq_urinishlar) > 5000:
        _ochiq_urinishlar.clear()
    _ochiq_urinishlar[ip] = tarix
    if len(tarix) >= chek:
        return False
    tarix.append(hozir)
    return True


class Yerosti(BaseHTTPRequestHandler):
    server_version = "TRACE4D/1"
    protocol_version = "HTTP/1.1"

    # ---------- yordamchilar ----------

    def _sarlavhalar(self, kod, turi="application/json; charset=utf-8",
                     qoshimcha=None):
        self.send_response(kod)
        self.send_header("Content-Type", turi)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        # UL-03: kirishsiz sahifalar (/t/, /u/) — havola (token) Referer orqali chiqmasin, qidiruvga tushmasin
        if getattr(self, "_ochiq", False):
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Robots-Tag", "noindex, nofollow")
            self.send_header("Cache-Control", "no-store")
        else:
            self.send_header("Referrer-Policy", "same-origin")
        self.send_header("Content-Security-Policy", CSP)
        for k, v in (qoshimcha or {}).items():
            self.send_header(k, v)

    def _json(self, kod, obj, qoshimcha=None):
        tana = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self._sarlavhalar(kod, qoshimcha=qoshimcha)
        self.send_header("Content-Length", str(len(tana)))
        self.end_headers()
        self.wfile.write(tana)

    def _xato(self, kod, xabar):
        self._json(kod, {"xato": xabar})

    def _xom_tana(self, chek):
        uz = int(self.headers.get("Content-Length") or 0)
        if uz <= 0:
            return None
        if uz > chek:
            self._tanani_tashla()
            return None
        return self.rfile.read(uz)

    def _tana(self):
        xom = self._xom_tana(JSON_CHEK)
        if xom is None:
            return None
        try:
            return json.loads(xom.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            return None

    def _tanani_tashla(self):
        # Rad etilgan so'rov tanasini o'qib tashlash — keep-alive buzilmasin
        uz = int(self.headers.get("Content-Length") or 0)
        while uz > 0:
            b = self.rfile.read(min(uz, 65536))
            if not b:
                break
            uz -= len(b)

    def _token(self):
        c = SimpleCookie(self.headers.get("Cookie") or "")
        m = c.get(COOKIE_NOMI)
        return m.value if m else None

    def _bearer(self):
        a = self.headers.get("Authorization") or ""
        return a[7:].strip() if a.startswith("Bearer ") else None

    def _kim(self):
        b = self._bearer()
        if b is not None:
            t = baza.dala_token_top(b)
            if not t:
                return None
            return {"id": None, "login": f"dala:{t['nomi']}", "rol": "dala",
                    "ism": t["nomi"], "token_id": t["id"]}
        return baza.sessiya_top(self._token())

    def _https_ortida(self):
        """Ishonchli proksi (YEROSTI_PROKSI_TARMOQ) HTTPS orqali uzatgan so'rov: sessiya cookie `Secure` bilan beriladi."""
        try:
            ishonchli = any(ipaddress.ip_address(self.client_address[0]) in t for t in PROKSI_TARMOQLAR)
        except ValueError:
            return False
        return ishonchli and (self.headers.get("X-Forwarded-Proto") or "").strip() == "https"

    def _mijoz_ip(self):
        ip = self.client_address[0]
        try:
            ishonchli = any(ipaddress.ip_address(ip) in t for t in PROKSI_TARMOQLAR)
        except ValueError:
            ishonchli = False
        if ishonchli:
            r = (self.headers.get("X-Real-IP") or "").strip()
            try:
                return str(ipaddress.ip_address(r))
            except ValueError:
                pass
        return ip

    def _csrf_ok(self):
        return self._bearer() is not None or self.headers.get("X-Yerosti") == "1"

    def _jurnal(self, kim, amal, tafsilot=""):
        if kim and kim.get("token_id"):
            tafsilot = f"{kim['login']} {tafsilot}".strip()
        baza.jurnal_yoz(kim["id"] if kim else None, amal, tafsilot)

    # ---------- GET ----------

    def do_GET(self):
        yol = urlparse(self.path)
        self._ochiq = yol.path.startswith(("/t/", "/u/", "/q/"))
        if yol.path.startswith("/api/v1/"):
            return self._api_get(yol.path, parse_qs(yol.query))
        if yol.path.startswith("/t/"):
            return self._tekshirish(yol.path)
        if yol.path.startswith("/q/"):
            return self._belgi_sahifa(yol.path)
        if yol.path.startswith("/u/"):
            return self._ulash_get(yol.path, parse_qs(yol.query))
        if yol.path.startswith("/xarita/"):
            return self._ortofoto(yol.path)
        return self._statik(yol.path)

    def _api_get(self, qism, sorov):
        if qism == "/api/v1/salomatlik":
            return self._salomatlik()
        kim = self._kim()
        if not kim:
            return self._xato(401, "kirish kerak")

        if qism == "/api/v1/men":
            return self._json(200, {"foydalanuvchi": kim})
        if qism == "/api/v1/geojson":
            return self._json(200, baza.geojson())
        if qism == "/api/v1/statistika":
            return self._json(200, baza.statistika())
        if qism == "/api/v1/obyektlar":
            q = (sorov.get("q") or [""])[0][:100]
            return self._json(200, {"obyektlar": baza.obyektlar(q)})
        if qism == "/api/v1/skanlar":
            oid = (sorov.get("obyekt_id") or [None])[0]
            try:
                oid = int(oid) if oid is not None else None
            except ValueError:
                return self._xato(400, "obyekt_id noto'g'ri")
            return self._json(200, {"skanlar": baza.skanlar(oid)})
        m = _SKAN_ID.match(qism)
        if m:
            s = baza.skan_top(int(m.group(1)))
            return self._json(200, s) if s else self._xato(404, "skan topilmadi")
        if qism == "/api/v1/dala-tokenlar":
            if kim["rol"] != "admin":
                return self._xato(403, "faqat admin")
            return self._json(200, {"tokenlar": baza.dala_tokenlar()})
        if qism == "/api/v1/atrof":
            try:
                lat = float((sorov.get("lat") or [""])[0])
                lon = float((sorov.get("lon") or [""])[0])
                r = float((sorov.get("r") or ["60"])[0])
                if not (-90 <= lat <= 90 and -180 <= lon <= 180) or r <= 0:
                    raise ValueError
            except ValueError:
                return self._xato(400, "lat, lon va r (m) kerak")
            return self._json(200, {"tarmoqlar": baza.atrofdagi(lat, lon, r),
                                    "radius_m": min(r, baza.ATROF_MAKS_M)})
        if qism == "/api/v1/chizma":
            return self._chizma(sorov)
        if qism == "/api/v1/muhrlar":
            try:
                oid = int((sorov.get("obyekt_id") or [""])[0])
            except ValueError:
                return self._xato(400, "obyekt_id kerak")
            return self._json(200, {"muhrlar": baza.muhrlar(oid)})
        if qism == "/api/v1/xarita-sozlama":
            asoslar = []
            if ORTOFOTO and kim["rol"] in PORTAL_ROLLAR:
                asoslar.append(ORTOFOTO.tavsif(ORTOFOTO_ANIQLIK_M))
            if SUNIY:
                asoslar.append({k: v for k, v in SUNIY.items() if k != "manba"})
            return self._json(200, {"uslub": "" if XARITA_USLUB.lower() == "yoq" else XARITA_USLUB, "asoslar": asoslar})
        if qism == "/api/v1/tahlillar":
            try:
                oid = int((sorov.get("obyekt_id") or [""])[0])
            except ValueError:
                return self._xato(400, "obyekt_id kerak")
            return self._json(200, {"tahlillar": baza.tahlillar(oid)})
        m = _TAHLIL_ID.match(qism)
        if m:
            t = baza.tahlil_top(int(m.group(1)))
            return self._json(200, t) if t else self._xato(404, "tahlil topilmadi")
        m = _TAHLIL_KORINISH.match(qism)
        if m:
            return self._korinish(kim, int(m.group(1)))
        if qism == "/api/v1/ijro-hujjatlar":
            if kim["rol"] not in PORTAL_ROLLAR:
                return self._xato(403, "ruxsat yo'q")
            try:
                oid = int((sorov.get("obyekt_id") or [""])[0])
            except ValueError:
                return self._xato(400, "obyekt_id kerak")
            return self._json(200, {"hujjatlar": baza.hujjatlar(oid)})
        m = _HUJJAT_PDF.match(qism)
        if m:
            if kim["rol"] not in PORTAL_ROLLAR:
                return self._xato(403, "ruxsat yo'q")
            h = baza.hujjat_top(int(m.group(1)))
            if not h or h["holat"] not in ("amal", "bekor"):
                return self._xato(404, "hujjat topilmadi")
            return self._hujjat_fayl(h)
        m = _OBYEKT_QISM.match(qism)
        if m:
            if kim["rol"] not in PORTAL_ROLLAR and not (kim["rol"] == "dala" and m.group(2) in ("geodezik-asos", "tasdiq")):
                return self._xato(403, "ruxsat yo'q")
            oid, nima = int(m.group(1)), m.group(2)
            if not baza.obyekt_top(oid):
                return self._xato(404, "obyekt topilmadi")
            if nima == "loyiha":
                return self._json(200, {"loyiha": self._loyiha_utmda(oid), "tarix": baza.loyihalar(oid)})
            if nima == "geodezik-asos":
                return self._json(200, self._geodezik_asos(oid))
            if nima == "tasdiq":
                return self._json(200, baza.tasdiq_holati(oid))
            if nima == "graf":
                return self._json(200, baza.tarmoq_grafi(baza.liniyalar_toliq(obyekt_id=oid)))
            if nima == "muvofiqlik":
                # T3: loyiha–ijro muvofiqligi (JSON) — hujjat bilan bir xil hisob
                try:
                    m = ijro.malumot_yig(oid, "—", "", kim.get("ism") or kim["login"])
                    ijro.tayyorla(m)
                    return self._json(200, muvofiqlik.tahlil(m))
                except ValueError as x:
                    return self._xato(409, str(x))
            if nima == "lokalizatsiya":
                return self._json(200, {"lokalizatsiya": baza.lokalizatsiya_top(oid)})
            if nima == "topo":
                return self._json(200, {"tarix": baza.topolar(oid)})
            if nima == "ulashlar":
                return self._json(200, {"ulashlar": baza.ulashlar(oid)})
            if nima == "tarix":
                return self._json(200, {"tarix": baza.tarix(oid)})
            return self._xato(404, "topilmadi")
        m = _TAHLIL_IZOH.match(qism)
        if m:
            if kim["rol"] not in PORTAL_ROLLAR:
                return self._xato(403, "ruxsat yo'q")
            return self._json(200, {"izohlar": baza.izohlar(int(m.group(1)))})
        if qism == "/api/v1/belgilar":
            if kim["rol"] not in PORTAL_ROLLAR:
                return self._xato(403, "ruxsat yo'q")
            try:
                oid = int((sorov.get("obyekt_id") or [""])[0])
            except ValueError:
                return self._xato(400, "obyekt_id kerak")
            asos = self._tashqi_url()
            return self._json(200, {"belgilar": [dict(b, url=f"{asos}/q/{b['kod']}") for b in baza.belgilar(oid)]})
        if qism == "/api/v1/belgilar/plastinka.pdf":
            return self._belgi_plastinka(kim, sorov)
        if qism == "/api/v1/sifat-qoidasi":
            return self._json(200, {
                "sigma_h_chek_sm": baza.SIGMA_H_CHEK_SM,
                "sigma_v_chek_sm": baza.SIGMA_V_CHEK_SM,
                "tuzatma_yoshi_chek_s": baza.TUZATMA_YOSHI_CHEK_S,
                "rasmiy_uchun": "FIX va uchala chek ichida",
            })
        return self._xato(404, "topilmadi")

    # ---------- POST ----------

    def do_POST(self):
        qism = urlparse(self.path).path
        self._ochiq = False
        if not self._csrf_ok():
            self._tanani_tashla()
            return self._xato(403, "X-Yerosti sarlavhasi yo'q")

        if qism == "/api/v1/kirish":
            return self._kirish()
        if qism == "/api/v1/chiqish":
            self._tanani_tashla()
            baza.sessiya_yop(self._token())
            return self._json(200, {"holat": "chiqildi"}, qoshimcha={
                "Set-Cookie": f"{COOKIE_NOMI}=; Max-Age=0; Path=/; HttpOnly" + ("; Secure" if self._https_ortida() else "")
            })

        kim = self._kim()
        if not kim:
            self._tanani_tashla()
            return self._xato(401, "kirish kerak")

        if qism == "/api/v1/obyektlar":
            return self._obyekt_yarat(kim)
        if qism == "/api/v1/liniyalar":
            return self._liniya_yarat(kim)
        if qism == "/api/v1/order-tekshir":
            return self._order_tekshir(kim)
        if qism == "/api/v1/skan/boshla":
            return self._skan_boshla(kim)
        m = _SKAN_YAKUN.match(qism)
        if m:
            return self._skan_yakunla(kim, int(m.group(1)))
        if qism == "/api/v1/dala-tokenlar":
            return self._dala_token_yarat(kim)
        if qism == "/api/v1/qurilma-kalit":
            return self._qurilma_kalit(kim)
        if qism == "/api/v1/muhr":
            return self._muhr_tekshir(kim)
        m = _TAHLIL_QAYTA.match(qism)
        if m:
            return self._tahlil_qayta(kim, int(m.group(1)))
        if qism == "/api/v1/ijro-hujjat":
            return self._ijro_yarat(kim)
        if qism == "/api/v1/yopiq-dalolatnoma":
            return self._yopiq_yarat(kim)
        if qism == "/api/v1/belgilar":
            return self._belgi_yarat(kim)
        if qism == "/api/v1/muvofiqlik-hisobot":
            return self._muvofiqlik_yarat(kim)
        m = _HUJJAT_BEKOR.match(qism)
        if m:
            return self._hujjat_bekor(kim, int(m.group(1)))
        m = _OBYEKT_QISM.match(qism)
        if m and m.group(2) == "loyiha":
            return self._loyiha_yukla(kim, int(m.group(1)))
        if m and m.group(2) == "nazorat-punkt":
            return self._nazorat_punkt(kim, int(m.group(1)))
        if m and m.group(2) == "nazorat-olchov":
            return self._nazorat_olchov(kim, int(m.group(1)))
        if m and m.group(2) == "tasdiq":
            return self._tasdiq_qosh(kim, int(m.group(1)))
        if m and m.group(2) == "tashqi-skan":
            return self._tashqi_skan(kim, int(m.group(1)))
        if m and m.group(2) == "farq":
            return self._farq(kim, int(m.group(1)))
        if m and m.group(2) == "lokalizatsiya":
            return self._lokalizatsiya(kim, int(m.group(1)))
        if m and m.group(2) == "topo":
            return self._topo_yukla(kim, int(m.group(1)))
        if m and m.group(2) == "ulash":
            return self._ulash_yarat(kim, int(m.group(1)))
        m = _LINIYA_ID.match(qism)
        if m:
            return self._liniya_yangila(kim, int(m.group(1)))
        m = _OBYEKT_ID.match(qism)
        if m:
            return self._obyekt_yangila(kim, int(m.group(1)))

        m = _ASOS_BEKOR.match(qism)
        if m:
            return self._asos_bekor(kim, int(m.group(1)), m.group(2), int(m.group(3)))
        m = _ULASH_BEKOR.match(qism)
        if m:
            return self._ulash_bekor(kim, int(m.group(1)))
        m = _TAHLIL_IZOH.match(qism)
        if m:
            return self._izoh_qosh(kim, int(m.group(1)))
        m = _TOKEN_BEKOR.match(qism)
        if m:
            return self._dala_token_bekor(kim, int(m.group(1)))
        m = _BELGI_BEKOR.match(qism)
        if m:
            return self._belgi_bekor(kim, int(m.group(1)))
        self._tanani_tashla()
        return self._xato(404, "topilmadi")

    # ---------- PUT (skan bo'laklari) ----------

    def do_PUT(self):
        qism = urlparse(self.path).path
        self._ochiq = False
        m = _SKAN_BOLAK.match(qism)
        if not m:
            self._tanani_tashla()
            return self._xato(404, "topilmadi")
        if not self._csrf_ok():
            self._tanani_tashla()
            return self._xato(403, "X-Yerosti sarlavhasi yo'q")
        kim = self._kim()
        if not kim or kim["rol"] not in YOZUVCHI_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "ruxsat yo'q")
        sha = self.headers.get("X-Bolak-SHA256", "")
        if len(sha) != 64:
            self._tanani_tashla()
            return self._xato(400, "X-Bolak-SHA256 sarlavhasi kerak")
        data = self._xom_tana(BOLAK_CHEK)
        if data is None:
            return self._xato(400, f"bo'lak 1..{BOLAK_CHEK} bayt bo'lsin")
        try:
            natija = baza.skan_bolak_yoz(int(m.group(1)), int(m.group(2)), data, sha)
        except ValueError as x:
            return self._xato(409, str(x))
        return self._json(200, natija)

    # ---------- amallar ----------

    def _kirish(self):
        ip = self._mijoz_ip()
        if not _kirish_ruxsatmi(ip):
            self._tanani_tashla()
            return self._xato(429, "juda ko'p urinish — bir daqiqa kuting")
        t = self._tana()
        if not t or "login" not in t or "parol" not in t:
            return self._xato(400, "login/parol kerak")
        f = baza.kirish_tekshir(str(t["login"])[:64], str(t["parol"])[:128])
        if not f:
            baza.jurnal_yoz(None, "kirish_rad", f"login={t['login']!r} ip={ip}")
            return self._xato(401, "login yoki parol noto'g'ri")
        token = baza.sessiya_och(f["id"])
        baza.jurnal_yoz(f["id"], "kirish", f"ip={ip}")
        return self._json(200, {"foydalanuvchi": {
            "id": f["id"], "login": f["login"], "rol": f["rol"], "ism": f["ism"],
        }}, qoshimcha={
            "Set-Cookie": (f"{COOKIE_NOMI}={token}; Path=/; HttpOnly;"
                           f" SameSite=Lax; Max-Age={12 * 3600}" + ("; Secure" if self._https_ortida() else ""))
        })

    def _obyekt_yarat(self, kim):
        if kim["rol"] not in YOZUVCHI_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "ruxsat yo'q")
        t = self._tana()
        if not isinstance(t, dict) or not str(t.get("nomi", "")).strip():
            return self._xato(400, "nomi kerak")
        try:
            oid = baza.obyekt_yarat(
                nomi=str(t["nomi"]).strip()[:200], manzil=str(t.get("manzil", ""))[:300],
                buyurtmachi=str(t.get("buyurtmachi", ""))[:200],
                pudratchi=str(t.get("pudratchi", ""))[:200],
                order_raqami=str(t.get("order_raqami", ""))[:64],
                order_sana=t.get("order_sana", ""),
                yaratuvchi_id=kim["id"], dala_token_id=kim.get("token_id"),
            )
        except ValueError as x:
            return self._xato(400, f"order_sana: {x}")
        self._jurnal(kim, "obyekt_yaratildi", f"id={oid}")
        return self._json(200, {"id": oid})

    def _liniya_yarat(self, kim):
        if kim["rol"] not in YOZUVCHI_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "ruxsat yo'q")
        t = self._tana()
        if not t:
            return self._xato(400, "tana bo'sh yoki juda katta")
        try:
            lid = baza.liniya_yarat(
                obyekt_id=int(t["obyekt_id"]), turi=t.get("turi", ""),
                nuqtalar=t.get("nuqtalar", []),
                material=str(t.get("material", ""))[:100],
                diametr_mm=int(t.get("diametr_mm", 0)),
                izoh=str(t.get("izoh", ""))[:500],
                yaratuvchi_id=kim["id"], dala_token_id=kim.get("token_id"),
            )
        except (KeyError, ValueError, TypeError) as x:
            return self._xato(400, f"noto'g'ri ma'lumot: {x}")
        self._jurnal(kim, "liniya_yaratildi", f"id={lid}")
        return self._json(200, {"id": lid})

    def _order_tekshir(self, kim):
        t = self._tana()
        if not t or not isinstance(t.get("poligon"), list):
            return self._xato(400, "poligon kerak")
        try:
            poligon = [(float(p[0]), float(p[1])) for p in t["poligon"]][:100]
            topilgan = baza.order_tekshir(poligon)
        except (ValueError, TypeError, IndexError) as x:
            return self._xato(400, f"noto'g'ri poligon: {x}")
        self._jurnal(kim, "order_tekshirildi",
                     f"nuqta={len(poligon)} topildi={len(topilgan)}")
        return self._json(200, {"topilgan": topilgan, "soni": len(topilgan)})

    def _skan_boshla(self, kim):
        if kim["rol"] not in YOZUVCHI_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "ruxsat yo'q")
        t = self._tana()
        if not t:
            return self._xato(400, "tana bo'sh")
        try:
            natija = baza.skan_boshla(
                obyekt_id=int(t["obyekt_id"]), turi=t.get("turi", ""),
                hajmi=t["hajmi"], sha256=t.get("sha256", ""),
                liniya_id=int(t["liniya_id"]) if t.get("liniya_id") else None,
                rms_sm=t.get("rms_sm"), markerlar=t.get("markerlar"),
                meta=t.get("meta"), yaratuvchi_id=kim["id"],
                dala_token_id=kim.get("token_id"),
            )
        except (KeyError, ValueError, TypeError) as x:
            return self._xato(400, f"noto'g'ri ma'lumot: {x}")
        self._jurnal(kim, "skan_boshlandi", f"id={natija['skan_id']}")
        return self._json(200, natija)

    def _skan_yakunla(self, kim, skan_id):
        self._tanani_tashla()
        if kim["rol"] not in YOZUVCHI_ROLLAR:
            return self._xato(403, "ruxsat yo'q")
        try:
            s = baza.skan_yakunla(skan_id)
        except ValueError as x:
            return self._xato(404, str(x))
        self._jurnal(kim, "skan_yakunlandi", f"id={skan_id} holat={s['holat']}")
        return self._json(200 if s["holat"] == "tayyor" else 409, s)

    def _dala_token_yarat(self, kim):
        if kim["rol"] != "admin":
            self._tanani_tashla()
            return self._xato(403, "faqat admin")
        t = self._tana()
        if not t or not str(t.get("nomi", "")).strip():
            return self._xato(400, "nomi kerak")
        tid, token = baza.dala_token_yarat(
            str(t["nomi"]).strip()[:80], str(t.get("qurilma", ""))[:120], kim["id"])
        self._jurnal(kim, "dala_token_yaratildi", f"id={tid}")
        return self._json(200, {"id": tid, "token": token,
                                "eslatma": "token faqat shu javobda ko'rinadi"})

    def _chizma(self, sorov):
        """T-235: obyektning ijro chizmasi (DXF R12) yoki koordinata katalogi (CSV), UTM."""
        try:
            oid = int((sorov.get("obyekt_id") or [""])[0])
        except ValueError:
            return self._xato(400, "obyekt_id kerak")
        return self._chizma_ber(oid, (sorov.get("format") or ["dxf"])[0], (sorov.get("tizim") or [None])[0])

    def _chizma_ber(self, oid, fmt, tizim=None):
        """LK-09: lokalizatsiya bo'lsa standart — mahalliy tizim va Boltiq; ?tizim=utm bilan WGS84 / UTM."""
        o = baza.obyekt_top(oid)
        if not o or fmt not in ("dxf", "csv", "ifc") or tizim not in (None, "utm", "mahalliy"):
            return self._xato(404, "obyekt, format yoki tizim topilmadi")
        qator = baza.liniyalar_toliq(obyekt_id=oid)
        _, zona = chizma.liniyalar_utm(qator)
        t = ijro.tizim_tanla(baza.lokalizatsiya_top(oid), zona or 42)
        if tizim == "mahalliy" and t["tur"] != "mahalliy":
            return self._xato(409, "obyektda lokalizatsiya yo'q: mahalliy tizimda eksport qilib bo'lmaydi")
        if tizim == "utm":
            t = ijro.tizim_tanla(None, zona or 42)
        liniyalar, _ = ijro.planar_liniyalar(qator, t["lok"], zona)
        if not liniyalar:
            return self._xato(409, "obyektda chiziladigan liniya yo'q")
        m = baza.muhrlar(oid)
        sarlavha = {"obyekt": o["nomi"], "order": ijro.order_matn(o), "pudratchi": o["pudratchi"],
                    "buyurtmachi": o["buyurtmachi"], "sana": baza.hozir()[:10],
                    "muhr": (m[0]["holat"] + " #" + str(m[0]["id"])) if m else "yo'q",
                    "koordinata_tizimi": f"{t['nomi']}; balandlik {t['balandlik']}"}
        if fmt == "dxf":
            tana = chizma.dxf(liniyalar, sarlavha).encode("ascii", "replace")
            turi, kengaytma = "application/dxf", "dxf"
        elif fmt == "ifc":
            # KU-01: IFC 4.3 — har liniya IfcPipeSegment / IfcCableSegment, IfcMapConversion bilan georeferens
            tq = baza.tasdiq_holati(oid, qator).get("liniyalar", {})
            for l in liniyalar:
                l["tasdiq"] = tq.get(l["id"])
            hj = [h for h in baza.hujjatlar(oid) if h["holat"] == "amal"]
            tana = ifc_mod.ifc(liniyalar, o, t, zona or 42, hj[0]["raqam"] if hj else None).encode("utf-8")
            turi, kengaytma = "application/x-step", "ifc"
        else:
            tana = chizma.katalog_csv(liniyalar).encode("utf-8")
            turi, kengaytma = "text/csv; charset=utf-8", "csv"
        self._sarlavhalar(200, turi=turi, qoshimcha={
            "Content-Disposition": f'attachment; filename="trace4d_obyekt_{oid}.{kengaytma}"'})
        self.send_header("Content-Length", str(len(tana)))
        self.end_headers()
        self.wfile.write(tana)
        return None

    def _qurilma_kalit(self, kim):
        """iPhone Secure Enclave ochiq kaliti (x963, base64) — shu dala tokeniga bog'lanadi."""
        if kim["rol"] != "dala":
            self._tanani_tashla()
            return self._xato(403, "faqat dala qurilmasi")
        t = self._tana()
        try:
            x963 = base64.b64decode(str((t or {}).get("ochiq_kalit", "")), validate=True)
            muhr.ochiq_kalit_yukla(x963)
        except (binascii.Error, ValueError) as x:
            return self._xato(400, f"ochiq kalit noto'g'ri: {x}")
        kid = baza.qurilma_kalit_saqla(kim["token_id"], x963.hex())
        self._jurnal(kim, "qurilma_kalit", f"id={kid}")
        return self._json(200, {"id": kid})

    def _muhr_tekshir(self, kim):
        """K-05: imzo → fayllar → jurnal zanjiri. Natija (TASDIQLANGAN/BUZILGAN) har holda saqlanadi."""
        if kim["rol"] != "dala":
            self._tanani_tashla()
            return self._xato(403, "faqat dala qurilmasi")
        t = self._tana()
        try:
            obyekt_id = int(t["obyekt_id"])
            manifest_b = base64.b64decode(str(t["manifest"]), validate=True)
            imzo = base64.b64decode(str(t["imzo"]), validate=True)
            m = muhr.manifest_ajrat(manifest_b)
        except (KeyError, TypeError, ValueError, binascii.Error) as x:
            return self._xato(400, f"noto'g'ri muhr so'rovi: {x}")
        if int(m["obyekt_id"]) != obyekt_id or not baza.obyekt_top(obyekt_id):
            return self._xato(400, "obyekt mos emas")
        kalit = baza.qurilma_kalit_top(kim["token_id"])
        if not kalit:
            return self._xato(409, "qurilma kaliti ro'yxatdan o'tmagan")
        holat, sabab = "TASDIQLANGAN", ""
        if not muhr.imzo_tekshir(bytes.fromhex(kalit["ochiq_kalit"]), manifest_b, imzo):
            holat, sabab = "BUZILGAN", "imzo qurilma kalitiga mos emas"
        jurnal_skan = ply_skan = None
        if holat == "TASDIQLANGAN":
            for f in m["fayllar"]:
                sk = baza.skan_xesh_boyicha(obyekt_id, f["sha256"], f["hajm"])
                if not sk:
                    holat, sabab = "BUZILGAN", f"fayl yuklanmagan yoki xeshi mos emas: {f['nomi']}"
                    break
                if sk["turi"] == "muhr_jurnal":
                    jurnal_skan = sk
                elif sk["turi"] == "nuqta_ply":
                    ply_skan = sk
        if holat == "TASDIQLANGAN":
            if not jurnal_skan:
                holat, sabab = "BUZILGAN", "manifestda muhr jurnali yo'q"
            else:
                try:
                    bosh, soni = muhr.jurnal_tekshir(baza.skan_fayl_oqi(jurnal_skan))
                    if bosh != str(m["zanjir_boshi"]).lower() or soni != int(m["yozuv_soni"]):
                        holat, sabab = "BUZILGAN", "zanjir boshi yoki yozuvlar soni jurnalga mos emas"
                except ValueError as x:
                    holat, sabab = "BUZILGAN", f"jurnal o'qilmadi: {x}"
        mid = baza.muhr_saqla(obyekt_id, kim["token_id"], kalit["id"], manifest_b.decode("utf-8"), imzo.hex(),
                              holat, sabab, m["zanjir_boshi"], m["yozuv_soni"])
        self._jurnal(kim, "muhr", f"id={mid} holat={holat}")
        javob = {"id": mid, "holat": holat, "sabab": sabab}
        if holat == "TASDIQLANGAN" and jurnal_skan and ply_skan:
            # DM-02: telefon natijasi data markazda bir xil yadro bilan qayta hisoblanadi
            javob["tahlil_id"] = baza.tahlil_navbatga(mid, obyekt_id, jurnal_skan["id"], ply_skan["id"])
        return self._json(200, javob)

    def _salomatlik(self):
        """DM-04: docker healthcheck. Sir yo'q — faqat holat."""
        try:
            navbat = baza.navbat_holati()
            baza_ok = True
        except Exception:  # noqa: BLE001 — sog'liq tekshiruvi hech qachon yiqilmasin
            navbat, baza_ok = {}, False
        yozuv = os.access(baza.SKAN_PAPKA, os.W_OK)
        yurak = os.path.join(baza.SKAN_PAPKA, ".ishchi_yurak")
        ishchi = round(time.time() - os.path.getmtime(yurak)) if os.path.exists(yurak) else None
        ok = baza_ok and yozuv
        return self._json(200 if ok else 503, {"holat": "ok" if ok else "nosoz", "versiya": VERSIYA, "baza": baza_ok,
                                               "skan_papka_yoziladi": yozuv, "navbat": navbat,
                                               "ishchi_oxirgi_yurak_s": ishchi})

    def _korinish(self, kim, ish_id):
        """DM-03: 3D ko'ruvchi buluti — faqat portal foydalanuvchisiga, faqat tayyor tahlil uchun."""
        if kim["rol"] not in PORTAL_ROLLAR:
            return self._xato(403, "ruxsat yo'q")
        t = baza.tahlil_top(ish_id)
        yol = os.path.join(baza.tahlil_papka(ish_id), "korinish.ply")
        if not t or t["holat"] != "tayyor" or not os.path.isfile(yol):
            return self._xato(404, "ko'rinish fayli yo'q")
        hajm = os.path.getsize(yol)
        self._sarlavhalar(200, turi="application/octet-stream", qoshimcha={"Cache-Control": "private, max-age=3600"})
        self.send_header("Content-Length", str(hajm))
        self.end_headers()
        with open(yol, "rb") as f:
            while True:
                b = f.read(1024 * 1024)
                if not b:
                    break
                self.wfile.write(b)
        return None

    def _tahlil_qayta(self, kim, ish_id):
        self._tanani_tashla()
        if kim["rol"] != "admin":
            return self._xato(403, "faqat admin")
        if not baza.tahlil_qayta(ish_id):
            return self._xato(409, "tahlil topilmadi yoki hali ishlanmoqda")
        self._jurnal(kim, "tahlil_qayta", f"id={ish_id}")
        return self._json(200, {"holat": "kutmoqda"})

    def _dala_token_bekor(self, kim, tid):
        self._tanani_tashla()
        if kim["rol"] != "admin":
            return self._xato(403, "faqat admin")
        if not baza.dala_token_bekor(tid):
            return self._xato(404, "token topilmadi")
        self._jurnal(kim, "dala_token_bekor", f"id={tid}")
        return self._json(200, {"holat": "bekor qilindi"})

    # ---------- 14-bo'lim: ijro hujjati, loyiha, ulashish, izoh ----------

    def _tashqi_url(self):
        """QR va ulashish havolasining boshi. Env bo'lmasa — Host (faqat xavfsiz belgilar) va ishonchli proksi protokoli."""
        if TASHQI_URL:
            return TASHQI_URL
        host = (self.headers.get("Host") or "localhost").strip()
        if not re.fullmatch(r"[A-Za-z0-9.\-]+(:\d{1,5})?|\[[0-9A-Fa-f:]+\](:\d{1,5})?", host):
            host = "localhost"
        proto = "http"
        try:
            ishonchli = any(ipaddress.ip_address(self.client_address[0]) in t for t in PROKSI_TARMOQLAR)
        except ValueError:
            ishonchli = False
        if ishonchli and (self.headers.get("X-Forwarded-Proto") or "").strip() in ("http", "https"):
            proto = self.headers.get("X-Forwarded-Proto").strip()
        return f"{proto}://{host}"

    def _html(self, kod, matn):
        tana = matn.encode("utf-8")
        self._sarlavhalar(kod, turi="text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(tana)))
        self.end_headers()
        self.wfile.write(tana)

    def _fayl_ber(self, yol, turi, nomi):
        if not yol or not os.path.isfile(yol):
            return self._xato(404, "fayl topilmadi")
        hajm = os.path.getsize(yol)
        self._sarlavhalar(200, turi=turi, qoshimcha={"Content-Disposition": f'attachment; filename="{nomi}"'})
        self.send_header("Content-Length", str(hajm))
        self.end_headers()
        with open(yol, "rb") as f:
            while True:
                b = f.read(1024 * 1024)
                if not b:
                    break
                self.wfile.write(b)
        return None

    def _hujjat_fayl(self, h):
        return self._fayl_ber(os.path.join(baza.hujjat_papka(), os.path.basename(h["fayl"] or "")), "application/pdf",
                              f"{h['raqam']}.pdf")

    def _ijro_yarat(self, kim):
        """IH-01: obyekt uchun A3 ijro hujjati. Raqam va QR kodi PDF ichida; fayl xeshi bazada (IH-08)."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana()
        try:
            oid = int((t or {})["obyekt_id"])
        except (KeyError, TypeError, ValueError):
            return self._xato(400, "obyekt_id kerak")
        if not baza.obyekt_top(oid):
            return self._xato(404, "obyekt topilmadi")
        if not baza.liniyalar_toliq(obyekt_id=oid):
            return self._xato(409, "obyektda liniya yo'q: hujjat yasalmaydi")
        hid, raqam, kod = baza.hujjat_boshla(oid, kim["id"])
        url = f"{self._tashqi_url()}/t/{kod}"
        try:
            m = ijro.malumot_yig(oid, raqam, url, kim.get("ism") or kim["login"])
            pdf, varaqlar = ijro.hujjat_pdf(m)
        except ValueError as x:
            baza.hujjat_xato(hid, x)
            return self._xato(409, str(x))
        except Exception as x:  # noqa: BLE001 — yarim qolgan hujjat raqami "xato" holatida qoladi, ro'yxatda chiqmaydi
            baza.hujjat_xato(hid, f"{type(x).__name__}: {x}")
            sys.stderr.write(f"[yerosti] ijro hujjati xatosi: {type(x).__name__}: {x}\n")
            return self._xato(500, "hujjat yasalmadi")
        sha = self._hujjat_faylga(hid, raqam, pdf, varaqlar, ijro.tekshirish_xulosasi(m, varaqlar))
        self._jurnal(kim, "ijro_hujjat", f"id={hid} raqam={raqam} obyekt={oid}")
        return self._json(200, {"id": hid, "raqam": raqam, "varaqlar": varaqlar, "sha256": sha, "tekshirish_url": url})

    def _muvofiqlik_yarat(self, kim):
        """T3-4: loyiha–ijro muvofiqligi hisoboti — ro'yxatdan o'tgan A4 PDF (QR bilan), inspeksiyaga tayyor."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana()
        try:
            oid = int((t or {})["obyekt_id"])
        except (KeyError, TypeError, ValueError):
            return self._xato(400, "obyekt_id kerak")
        if not baza.obyekt_top(oid):
            return self._xato(404, "obyekt topilmadi")
        if not baza.liniyalar_toliq(obyekt_id=oid):
            return self._xato(409, "obyektda liniya yo'q")
        if not baza.loyiha_top(oid):
            return self._xato(409, "loyiha DXF yuklanmagan: muvofiqlik tekshirilmaydi")
        hid, raqam, kod = baza.hujjat_boshla(oid, kim["id"], "muvofiqlik")
        url = f"{self._tashqi_url()}/t/{kod}"
        try:
            m = ijro.malumot_yig(oid, raqam, url, kim.get("ism") or kim["login"])
            ijro.tayyorla(m)
            natija = muvofiqlik.tahlil(m)
            pdf, varaqlar = muvofiqlik.pdf(m, natija)
        except ValueError as x:
            baza.hujjat_xato(hid, x)
            return self._xato(409, str(x))
        except Exception as x:  # noqa: BLE001
            baza.hujjat_xato(hid, f"{type(x).__name__}: {x}")
            sys.stderr.write(f"[yerosti] muvofiqlik xatosi: {type(x).__name__}: {x}\n")
            return self._xato(500, "hisobot yasalmadi")
        sha = self._hujjat_faylga(hid, raqam, pdf, varaqlar, muvofiqlik.tekshirish_xulosasi(m, natija, varaqlar))
        self._jurnal(kim, "muvofiqlik_hisobot", f"id={hid} raqam={raqam} obyekt={oid}")
        return self._json(200, {"id": hid, "raqam": raqam, "varaqlar": varaqlar, "sha256": sha, "tekshirish_url": url,
                                "jami": natija["jami"]})

    # ---------- T1: QR-belgilar ----------

    def _belgi_yarat(self, kim):
        """T1-1: o'lchangan liniya nuqtasidan QR-belgi (admin/operator)."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana()
        if not isinstance(t, dict):
            return self._xato(400, "tana JSON obyekt bo'lsin")
        try:
            lid = int(t.get("liniya_id"))
        except (TypeError, ValueError):
            return self._xato(400, "liniya_id kerak")
        try:
            bid, kod = baza.belgi_yarat(lid, t.get("nuqta"), str(t.get("tur", "")), t.get("raqam", ""), t.get("aloqa", ""),
                                        t.get("izoh", ""), kim["id"])
        except LookupError as x:
            return self._xato(404, str(x))
        except ValueError as x:
            return self._xato(400, f"noto'g'ri ma'lumot: {x}")
        self._jurnal(kim, "belgi_yaratildi", f"id={bid} liniya={lid}")
        return self._json(200, {"id": bid, "kod": kod, "url": f"{self._tashqi_url()}/q/{kod}"})

    def _belgi_bekor(self, kim, bid):
        if kim["rol"] != "admin":
            self._tanani_tashla()
            return self._xato(403, "faqat admin")
        t = self._tana() or {}
        try:
            ok = baza.belgi_bekor(bid, t.get("sabab", "") if isinstance(t, dict) else "")
        except ValueError as x:
            return self._xato(400, str(x))
        if not ok:
            return self._xato(404, "belgi topilmadi yoki bekor qilingan")
        self._jurnal(kim, "belgi_bekor", f"id={bid}")
        return self._json(200, {"id": bid, "holat": "bekor"})

    def _belgi_plastinka(self, kim, sorov):
        """T1-4: A4 plastinka varag'i (8 yorliq). `idlar` bo'lmasa — obyektdagi barcha amaldagi belgilar."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            return self._xato(403, "faqat admin yoki operator")
        try:
            oid = int((sorov.get("obyekt_id") or [""])[0])
            idlar = {int(x) for x in (sorov.get("idlar") or [""])[0].split(",") if x.strip()}
        except ValueError:
            return self._xato(400, "obyekt_id va idlar butun son bo'lsin")
        o = baza.obyekt_top(oid)
        if not o:
            return self._xato(404, "obyekt topilmadi")
        tanlangan = [b for b in baza.belgilar(oid) if b["holat"] == "amal" and (not idlar or b["id"] in idlar)]
        if not tanlangan:
            return self._xato(409, "plastinka uchun amaldagi belgi yo'q")
        liniyalar = {l["id"]: l for l in baza.liniyalar_toliq(obyekt_id=oid)}
        pdf = belgi_mod.plastinka_pdf([(b, liniyalar.get(b["liniya_id"]), o) for b in tanlangan], self._tashqi_url())
        self._jurnal(kim, "belgi_plastinka", f"obyekt={oid} soni={len(tanlangan)}")
        return self._bayt_ber(pdf, "application/pdf", f"belgilar_obyekt_{oid}.pdf")

    def _bayt_ber(self, tana, turi, nomi):
        self._sarlavhalar(200, turi=turi, qoshimcha={"Content-Disposition": f'attachment; filename="{nomi}"'})
        self.send_header("Content-Length", str(len(tana)))
        self.end_headers()
        self.wfile.write(tana)

    def _belgi_sahifa(self, yol):
        """T1-2/T1-3: QR olib keladigan sahifa. Kirishsiz — qisqa; portal sessiyasi bilan — to'liq (har ko'rish jurnalga)."""
        if not _ochiq_ruxsatmi(self._mijoz_ip()):
            return self._html(429, ochiq.topilmadi_sahifasi("Juda ko'p so'rov: bir daqiqadan keyin"))
        m = _BELGI_YOL.match(yol)
        b = baza.belgi_kod_boyicha(m.group(1)) if m else None
        if not b:
            return self._html(404, ochiq.topilmadi_sahifasi("Belgi"))
        if b["holat"] != "amal":
            return self._html(410, ochiq.belgi_bekor_sahifasi(b))
        baza.belgi_korildi(b["id"])
        b["korishlar"] = (b.get("korishlar") or 0) + 1
        o = baza.obyekt_top(b["obyekt_id"])
        q = baza.liniyalar_toliq(idlar=[b["liniya_id"]]) if b.get("liniya_id") else []
        liniya = q[0] if q else None
        eg = belgi_mod.egasi(b, liniya, o)
        kim = baza.sessiya_top(self._token())
        if not kim or kim["rol"] not in PORTAL_ROLLAR:
            return self._html(200, ochiq.belgi_sahifasi(b, liniya, o, eg))
        self._jurnal(kim, "belgi_korildi", f"id={b['id']}")
        ijrolar = [h for h in baza.hujjatlar(b["obyekt_id"]) if (h.get("tur") or "ijro") == "ijro" and h["holat"] == "amal"]
        return self._html(200, ochiq.belgi_sahifasi(b, liniya, o, eg, toliq=True, atrof=belgi_mod.atrofdagilar(b),
                                                     ijro_hujjat=ijrolar[0] if ijrolar else None))

    def _hujjat_faylga(self, hid, raqam, pdf, varaqlar, xulosa):
        """PDF ni atomar yozadi (avval .yarim, keyin almashtirish) va reestrda yakunlaydi; SHA-256 qaytadi."""
        sha = hashlib.sha256(pdf).hexdigest()
        os.makedirs(baza.hujjat_papka(), exist_ok=True)
        fayl = f"{raqam}.pdf"
        vaqt = os.path.join(baza.hujjat_papka(), f".{fayl}.yarim")
        with open(vaqt, "wb") as f:
            f.write(pdf)
            f.flush()
            os.fsync(f.fileno())
        os.replace(vaqt, os.path.join(baza.hujjat_papka(), fayl))
        baza.hujjat_yakunla(hid, fayl, sha, len(pdf), varaqlar, xulosa)
        return sha

    def _yopiq_yarat(self, kim):
        """ShN-05: yopiq ishlar dalolatnomasi (ShNQ 3.01.01-22, 28-band, 6-ilova) va muhrlangan dalil to'plami — A4 PDF.
        Komissiya xulosasi va imzolar odamniki: kiritilmasa PDF da bo'sh chiziq qoladi."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana()
        try:
            oid = int((t or {})["obyekt_id"])
        except (KeyError, TypeError, ValueError):
            return self._xato(400, "obyekt_id kerak")
        try:
            k = dalolatnoma.kirish_tekshir(t)
        except ValueError as x:
            return self._xato(400, f"noto'g'ri ma'lumot: {x}")
        if not baza.obyekt_top(oid):
            return self._xato(404, "obyekt topilmadi")
        qator = baza.liniyalar_toliq(obyekt_id=oid)
        if not qator:
            return self._xato(409, "obyektda o'lchangan liniya yo'q: dalolatnoma yasalmaydi")
        if k["liniya_idlar"]:
            yoq = sorted(set(k["liniya_idlar"]) - {l["id"] for l in qator})
            if yoq:
                return self._xato(400, f"liniya shu obyektda topilmadi: {', '.join(map(str, yoq))}")
        hid, raqam, kod = baza.hujjat_boshla(oid, kim["id"], "yopiq")
        url = f"{self._tashqi_url()}/t/{kod}"
        try:
            m = dalolatnoma.malumot_yig(oid, k, raqam, url, kim.get("ism") or kim["login"])
            pdf, varaqlar = dalolatnoma.pdf(m)
        except ValueError as x:
            baza.hujjat_xato(hid, x)
            return self._xato(409, str(x))
        except Exception as x:  # noqa: BLE001
            baza.hujjat_xato(hid, f"{type(x).__name__}: {x}")
            sys.stderr.write(f"[yerosti] dalolatnoma xatosi: {type(x).__name__}: {x}\n")
            return self._xato(500, "dalolatnoma yasalmadi")
        sha = self._hujjat_faylga(hid, raqam, pdf, varaqlar, dalolatnoma.tekshirish_xulosasi(m, varaqlar))
        self._jurnal(kim, "yopiq_dalolatnoma", f"id={hid} raqam={raqam} obyekt={oid}")
        return self._json(200, {"id": hid, "raqam": raqam, "varaqlar": varaqlar, "sha256": sha, "tekshirish_url": url,
                                "toliq": not m["kamchiliklar"], "kamchiliklar": m["kamchiliklar"],
                                "ogohlantirishlar": m["ogohlantirishlar"], "rasmlar": len(m["rasmlar"])})

    def _hujjat_bekor(self, kim, hid):
        if kim["rol"] != "admin":
            self._tanani_tashla()
            return self._xato(403, "faqat admin")
        t = self._tana() or {}
        sabab = str(t.get("sabab", "")).strip()
        if not sabab:
            return self._xato(400, "bekor qilish sababi kerak")
        if not baza.hujjat_bekor(hid, sabab[:500]):
            return self._xato(409, "hujjat topilmadi yoki allaqachon bekor")
        self._jurnal(kim, "ijro_hujjat_bekor", f"id={hid}")
        return self._json(200, {"holat": "bekor"})

    def _loyiha_yukla(self, kim, oid):
        """IH-07: loyiha DXF (xom tana, ≤ 10 MB). ?fayl=nomi&z_turi=oq|usti|tubi&z_tizimi=ellipsoid|boltiq"""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        if not baza.obyekt_top(oid):
            self._tanani_tashla()
            return self._xato(404, "obyekt topilmadi")
        q = parse_qs(urlparse(self.path).query)
        nomi = re.sub(r"[^\w.\- ]", "_", (q.get("fayl") or ["loyiha.dxf"])[0])[:120] or "loyiha.dxf"
        z_turi = (q.get("z_turi") or ["usti"])[0]
        z_tizimi = (q.get("z_tizimi") or ["boltiq"])[0]
        lq = baza.lokalizatsiya_top(oid)
        # LK-07: lokalizatsiya bo'lsa loyiha odatda mahalliy tizimda keladi
        koordinata = (q.get("koordinata") or ["mahalliy" if lq else "utm"])[0]
        if z_turi not in baza.LOYIHA_Z_TURLARI or z_tizimi not in baza.LOYIHA_Z_TIZIMLARI \
                or koordinata not in ("utm", "mahalliy"):
            self._tanani_tashla()
            return self._xato(400, "z_turi (oq, usti, tubi), z_tizimi (ellipsoid, boltiq) yoki koordinata (utm, mahalliy) "
                                   "noto'g'ri")
        if koordinata == "mahalliy" and not (lq and lq["natija"]["parametrlar"].get("gor")):
            self._tanani_tashla()
            return self._xato(409, "mahalliy tizimdagi loyiha uchun avval obyektni lokalizatsiya qiling (Geodezik asos)")
        data = self._xom_tana(LOYIHA_CHEK)
        if data is None:
            return self._xato(400, f"DXF fayl kerak (≤ {LOYIHA_CHEK // 1048576} MB)")
        if data.startswith(b"AutoCAD Binary DXF"):
            return self._xato(400, "ikkilik DXF qo'llanmaydi: ASCII DXF sifatida saqlang")
        try:
            matn = data.decode("utf-8")
        except UnicodeDecodeError:
            matn = data.decode("cp1251", errors="replace")
        try:
            chiziqlar = ijro_geo.dxf_oqi(matn, utm=(koordinata == "utm"))
        except (ijro_geo.DXFXato, ValueError) as x:
            return self._xato(400, f"DXF o'qilmadi: {x}")
        eng = self._uzoqlik(oid, [(q2[0], q2[1]) for c in chiziqlar for q2 in c["nuqtalar"]],
                            lq if koordinata == "mahalliy" else None)
        if eng is not None and eng > LOYIHA_UZOQ_M:
            return self._xato(400, f"loyiha obyektdan {eng / 1000:.1f} km uzoqda: koordinata tizimi yoki zona noto'g'ri "
                                   f"(yuklangan: {'mahalliy tizim' if koordinata == 'mahalliy' else 'WGS84 / UTM'})")
        lid = baza.loyiha_saqla(oid, nomi, data, z_turi, z_tizimi, chiziqlar, kim["id"], koordinata)
        self._jurnal(kim, "loyiha_yuklandi", f"id={lid} obyekt={oid} chiziq={len(chiziqlar)}")
        return self._json(200, {"id": lid, "chiziqlar": len(chiziqlar),
                                "balandlik_bor": any(p[2] is not None for c in chiziqlar for p in c["nuqtalar"])})

    def _uzoqlik(self, oid, nuqtalar, lq=None):
        """Yuklangan chizma (e, n) qutisi va obyekt qutisi orasidagi masofa. lq berilsa — mahalliy tizimda (faqat
        gorizontal o'tish kerak; obyekt liniyalari yoki ular yo'q bo'lsa nazorat punktlari), aks holda UTM da.
        Solishtiradigan narsa yo'q — None."""
        if not nuqtalar:
            return None
        p = (lq or {}).get("natija", {}).get("parametrlar") or {}
        lok = lokal.Lokalizatsiya(p) if p.get("gor") else None
        lin, _ = ijro.planar_liniyalar(baza.liniyalar_toliq(obyekt_id=oid), lok)
        ob = [(q["e"], q["n"]) for l in lin for q in l["nuqtalar"]]
        if lok and not ob:
            ob = [(pk["y"], pk["x"]) for pk in baza.nazorat_punktlar(oid) if pk.get("x") is not None]
        if not ob:
            return None
        oe, on = [a for a, _ in ob], [b for _, b in ob]
        le, ln = [a for a, _ in nuqtalar], [b for _, b in nuqtalar]
        return math.hypot(max(0.0, min(le) - max(oe), min(oe) - max(le)), max(0.0, min(ln) - max(on), min(on) - max(ln)))

    def _loyiha_utmda(self, oid):
        """3D ko'ruvchi va portal uchun: mahalliy loyiha faol lokalizatsiya bilan UTM ga (Z Boltiq → ellipsoid)."""
        loy = baza.loyiha_top(oid)
        if not loy or (loy.get("koordinata") or "utm") == "utm":
            return loy
        lq = baza.lokalizatsiya_top(oid)
        if not (lq and lq["natija"]["parametrlar"].get("gor")):
            return None
        lok = lokal.Lokalizatsiya(lq["natija"]["parametrlar"])
        _, zona = chizma.liniyalar_utm(baza.liniyalar_toliq(obyekt_id=oid))
        bolt = loy.get("z_tizimi") == "boltiq" and lq["natija"]["parametrlar"].get("v")
        chiziqlar = []
        for ch in loy["chiziqlar"]:
            nq = []
            for y, x, z in ch["nuqtalar"]:
                lat, lon, h = lok.teskari(x, y, z if bolt else None)
                e, n, _ = chizma.utm(lat, lon, zona)
                nq.append([e, n, h if bolt else (z if loy.get("z_tizimi") == "ellipsoid" else None)])
            chiziqlar.append({**ch, "nuqtalar": nq})
        return {**loy, "chiziqlar": chiziqlar, "z_tizimi": "ellipsoid" if bolt else loy.get("z_tizimi"),
                "koordinata_asl": "mahalliy", "koordinata": "utm"}

    def _geodezik_asos(self, oid):
        punktlar, olchovlar = baza.nazorat_punktlar(oid), baza.nazorat_olchovlar(oid)
        lq = baza.lokalizatsiya_top(oid)
        tek = []
        if lq and lq["natija"]["parametrlar"].get("gor"):
            tek = lokal.tekshiruvlar(lokal.Lokalizatsiya(lq["natija"]["parametrlar"]), punktlar, olchovlar)
        return {"punktlar": punktlar, "olchovlar": olchovlar, "lokalizatsiya": lq, "tekshiruvlar": tek,
                "chegaralar": {"min_punkt": lokal.MIN_PUNKT, "qoldiq_gor_m": lokal.QOLDIQ_GOR_M,
                               "qoldiq_ver_m": lokal.QOLDIQ_VER_M, "tekshiruv_gor_m": lokal.TEKSHIRUV_GOR_M,
                               "tekshiruv_ver_m": lokal.TEKSHIRUV_VER_M, "olchov_min_s": baza.OLCHOV_MIN_S}}

    def _nazorat_punkt(self, kim, oid):
        """LK-01: {punktlar: [{nomi, x, y, h, sinf, manba}]} yoki {csv: "nomi;X;Y;H;sinf;manba"}."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana() or {}
        if not baza.obyekt_top(oid):
            return self._xato(404, "obyekt topilmadi")
        xatolar = []
        if t.get("csv"):
            qatorlar, xatolar = lokal.punkt_csv(str(t["csv"])[:500_000])
        else:
            qatorlar = t.get("punktlar") or []
        qoshildi = 0
        for r in qatorlar[:500]:
            try:
                baza.nazorat_punkt_qosh(oid, r.get("nomi", ""), r.get("x"), r.get("y"), r.get("h"), r.get("sinf", ""),
                                        r.get("manba", ""), kim["id"])
                qoshildi += 1
            except (ValueError, TypeError) as x:
                xatolar.append(str(x))
        if not qoshildi:
            return self._xato(400, "; ".join(xatolar) or "punkt yo'q")
        self._jurnal(kim, "nazorat_punkt", f"obyekt={oid} soni={qoshildi}")
        return self._json(200, {"qoshildi": qoshildi, "xatolar": xatolar})

    def _liniya_yangila(self, kim, lid):
        """KU-02: liniya atributlari (material, diametr, izoh, egasi, ishlash holati, yil, parametr) — admin/operator."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana() or {}
        try:
            yangi = baza.liniya_yangila(lid, t)
        except (ValueError, TypeError) as x:
            return self._xato(400, f"noto'g'ri ma'lumot: {x}")
        self._jurnal(kim, "liniya_yangilandi", f"id={lid} {','.join(yangi)}")
        return self._json(200, {"id": lid, "yangilandi": list(yangi)})

    def _obyekt_yangila(self, kim, oid):
        """ShN-01: obyekt rekvizitlari (order raqami va sanasi va b.) — admin/operator. Geometriya o'zgarmaydi."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana() or {}
        try:
            yangi = baza.obyekt_yangila(oid, t)
        except (ValueError, TypeError) as x:
            return self._xato(404 if "topilmadi" in str(x) else 400, f"noto'g'ri ma'lumot: {x}")
        self._jurnal(kim, "obyekt_yangilandi", f"id={oid} {','.join(yangi)}")
        return self._json(200, {"id": oid, "yangilandi": list(yangi)})

    def _farq(self, kim, oid):
        """KU-04: ikki tahlil (ko'rinish buluti) orasidagi M3C2 o'zgarish tahlili navbatga: {a, b}."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana() or {}
        if not baza.obyekt_top(oid):
            return self._xato(404, "obyekt topilmadi")
        try:
            tid = baza.farq_navbatga(oid, int(t.get("a") or 0), int(t.get("b") or 0), kim["id"])
        except (ValueError, TypeError) as x:
            return self._xato(400, f"noto'g'ri ma'lumot: {x}")
        self._jurnal(kim, "farq", f"obyekt={oid} tahlil={tid}")
        return self._json(200, {"tahlil_id": tid, "holat": "kutmoqda"})

    def _tashqi_skan(self, kim, oid):
        """LD-02: yuklangan LAS/PLY (skan jadvalida tayyor) uchun tashqi LiDAR tahlili navbatga.
        {skan_id, koordinata: utm|wgs84|mahalliy, zona, manba, aniqlik_sm, tarmoq_turi}."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana() or {}
        if not baza.obyekt_top(oid):
            return self._xato(404, "obyekt topilmadi")
        try:
            tid = baza.tashqi_navbatga(oid, int(t.get("skan_id") or 0), t.get("koordinata") or "utm", t.get("zona"),
                                       t.get("manba") or "", t.get("aniqlik_sm"), t.get("tarmoq_turi") or "", kim["id"])
        except (ValueError, TypeError) as x:
            return self._xato(400, f"noto'g'ri ma'lumot: {x}")
        self._jurnal(kim, "tashqi_skan", f"obyekt={oid} tahlil={tid}")
        return self._json(200, {"tahlil_id": tid, "holat": "kutmoqda"})

    def _tasdiq_qosh(self, kim, oid):
        """TQ-01/TQ-06: quvur tasdig'i — ilovadan bitta o'lchov (JSON) yoki Emlid Flow / oddiy CSV import {csv, joy}.
        Javobda yangilangan liniya holatlari (TQ-05) — ilova va portal darhol ko'radi."""
        if kim["rol"] not in YOZUVCHI_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "ruxsat yo'q")
        t = self._tana() or {}
        if not baza.obyekt_top(oid):
            return self._xato(404, "obyekt topilmadi")
        manba, xatolar = "rtk", []
        if t.get("csv"):
            qatorlar, xatolar = tasdiq_mod.csv_oqi(str(t["csv"])[:2_000_000], t.get("joy") or "usti")
            manba = "import"
        else:
            qatorlar = [t]
        idlar = []
        for r in qatorlar[:500]:
            try:
                idlar.append(baza.tasdiq_qosh(
                    oid, r.get("nomi") or "", r.get("lat"), r.get("lon"), r.get("h"), r.get("rtk_holat"), r.get("sigma_h_sm"),
                    r.get("sigma_v_sm"), r.get("epoxalar"), r.get("davomiylik_s"), r.get("tuzatma_yoshi_s"), r.get("antenna_m"),
                    r.get("vaqt"), r.get("joy") or "usti", r.get("liniya_id"), manba, kim.get("token_id"), kim["id"]))
            except (ValueError, TypeError) as x:
                xatolar.append(f"{r.get('nomi') or '?'}: {x}")
        if not idlar:
            return self._xato(400, "; ".join(xatolar) or "tasdiq yo'q")
        self._jurnal(kim, "tasdiq", f"obyekt={oid} soni={len(idlar)}")
        return self._json(200, {"idlar": idlar, "xatolar": xatolar, "tasdiq": baza.tasdiq_holati(oid)})

    def _nazorat_olchov(self, kim, oid):
        """LK-02: ilovadan bitta o'lchov (JSON) yoki Emlid Flow / oddiy CSV import {csv, maqsad}."""
        if kim["rol"] not in YOZUVCHI_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "ruxsat yo'q")
        t = self._tana() or {}
        if not baza.obyekt_top(oid):
            return self._xato(404, "obyekt topilmadi")
        manba = "rtk"
        xatolar = []
        if t.get("csv"):
            qatorlar, xatolar = lokal.olchov_csv(str(t["csv"])[:2_000_000], t.get("maqsad") or "kalibrlash")
            manba = "import"
        else:
            qatorlar = [t]
        idlar = []
        for r in qatorlar[:500]:
            try:
                idlar.append(baza.nazorat_olchov_qosh(
                    oid, r.get("punkt_id") or r.get("punkt"), r.get("maqsad") or "kalibrlash", r.get("lat"), r.get("lon"),
                    r.get("h"), r.get("rtk_holat"), r.get("sigma_h_sm"), r.get("sigma_v_sm"), r.get("epoxalar"),
                    r.get("davomiylik_s"), r.get("antenna_m"), r.get("vaqt"), manba, kim.get("token_id"), kim["id"]))
            except (ValueError, TypeError) as x:
                xatolar.append(f"{r.get('punkt') or r.get('punkt_id') or '?'}: {x}")
        if not idlar:
            return self._xato(400, "; ".join(xatolar) or "o'lchov yo'q")
        self._jurnal(kim, "nazorat_olchov", f"obyekt={oid} soni={len(idlar)}")
        return self._json(200, {"idlar": idlar, "xatolar": xatolar})

    def _lokalizatsiya(self, kim, oid):
        """LK-03/LK-04: faol punktlar va kalibrlash o'lchovlaridan hisob; natija saqlanadi (oldingisi 'eski')."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana() or {}
        tizim_nomi = str(t.get("tizim_nomi", "")).strip()[:80]
        if not tizim_nomi:
            return self._xato(400, "tizim nomi kerak (masalan: Jizzax sh. mahalliy tizimi)")
        if not baza.obyekt_top(oid):
            return self._xato(404, "obyekt topilmadi")
        juftlar, idlar = lokal.juftlar_yasash(baza.nazorat_punktlar(oid), baza.nazorat_olchovlar(oid))
        if not juftlar:
            return self._xato(409, "kalibrlash o'lchovi yo'q: punktlarni RTK bilan o'lchang yoki CSV import qiling")
        try:
            natija = lokal.hisobla(juftlar)
        except lokal.LokalizatsiyaXato as x:
            return self._xato(409, str(x))
        natija["juftlar"] = [{k: j[k] for k in ("nomi", "punkt_id", "olchov_soni", "lat", "lon", "h")} for j in juftlar]
        natija["qobiq"] = [list(q) for q in natija["qobiq"]]
        lid = baza.lokalizatsiya_saqla(oid, tizim_nomi, natija, idlar, kim["id"])
        self._jurnal(kim, "lokalizatsiya", f"id={lid} obyekt={oid} yaroqli={natija['yaroqli']}")
        return self._json(200, {"id": lid, **{k: natija[k] for k in ("yaroqli", "xatolar", "ogohlantirishlar", "n_gor",
                                                                      "n_ver", "maks_gor", "maks_ver", "rms_gor", "rms_ver",
                                                                      "masshtab_ppm", "burilish_grad", "qiyalik_ppm",
                                                                      "qoldiqlar", "loo")}})

    def _asos_bekor(self, kim, oid, tur, iid):
        self._tanani_tashla()
        if kim["rol"] not in HUJJAT_ROLLAR:
            return self._xato(403, "faqat admin yoki operator")
        if tur == "tasdiq":
            ok = baza.tasdiq_bekor(iid, oid)
        else:
            ok = baza.nazorat_punkt_bekor(iid, oid) if tur == "nazorat-punkt" else baza.nazorat_olchov_bekor(iid, oid)
        if not ok:
            return self._xato(409, "topilmadi yoki allaqachon bekor")
        self._jurnal(kim, f"{tur}_bekor", f"id={iid} obyekt={oid}")
        if tur == "tasdiq":
            return self._json(200, {"holat": "bekor", "tasdiq": baza.tasdiq_holati(oid)})
        return self._json(200, {"holat": "bekor", "eslatma": "lokalizatsiyani qayta hisoblang"})

    def _topo_yukla(self, kim, oid):
        """LK-08: shaharning topografik plani DXF (mahalliy tizimda, ≤ 10 MB). Lokalizatsiya shart."""
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        if not baza.obyekt_top(oid):
            self._tanani_tashla()
            return self._xato(404, "obyekt topilmadi")
        lq = baza.lokalizatsiya_top(oid)
        if not (lq and lq["natija"]["parametrlar"].get("gor")):
            self._tanani_tashla()
            return self._xato(409, "topoplan mahalliy tizimda: avval obyektni lokalizatsiya qiling (Geodezik asos)")
        nomi = re.sub(r"[^\w.\- ]", "_", (parse_qs(urlparse(self.path).query).get("fayl") or ["topo.dxf"])[0])[:120]
        data = self._xom_tana(TOPO_CHEK)
        if data is None:
            return self._xato(400, f"DXF fayl kerak (≤ {TOPO_CHEK // 1048576} MB)")
        if data.startswith(b"AutoCAD Binary DXF"):
            return self._xato(400, "ikkilik DXF qo'llanmaydi: ASCII DXF sifatida saqlang")
        try:
            matn = data.decode("utf-8")
        except UnicodeDecodeError:
            matn = data.decode("cp1251", errors="replace")
        try:
            ajr = ijro_geo.dxf_topo_oqi(matn)
        except (ijro_geo.DXFXato, ValueError) as x:
            return self._xato(400, f"DXF o'qilmadi: {x}")
        nuqtalar = [(q2[0], q2[1]) for c in ajr["chiziqlar"] for q2 in c["nuqtalar"]] + \
            [(t2["x"], t2["y"]) for t2 in ajr["matnlar"]]
        eng = self._uzoqlik(oid, nuqtalar, lq)
        if eng is not None and eng > LOYIHA_UZOQ_M:
            return self._xato(400, f"topoplan obyektdan {eng / 1000:.1f} km uzoqda: boshqa tizim yoki boshqa hudud")
        tid = baza.topo_saqla(oid, nomi, data, ajr, kim["id"])
        self._jurnal(kim, "topo_yuklandi", f"id={tid} obyekt={oid}")
        return self._json(200, {"id": tid, "chiziqlar": len(ajr["chiziqlar"]), "matnlar": len(ajr["matnlar"])})

    def _ulash_yarat(self, kim, oid):
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana() or {}
        nomi = str(t.get("nomi", "")).strip()[:120]
        if not nomi:
            return self._xato(400, "kimga berilishi (nomi) kerak")
        if not baza.obyekt_top(oid):
            return self._xato(404, "obyekt topilmadi")
        try:
            uid, token, muddati = baza.ulash_yarat(oid, nomi, t.get("kun", 30), kim["id"])
        except (TypeError, ValueError) as x:
            return self._xato(400, str(x))
        self._jurnal(kim, "ulash_yaratildi", f"id={uid} obyekt={oid}")
        return self._json(200, {"id": uid, "url": f"{self._tashqi_url()}/u/{token}", "muddati": muddati,
                                "eslatma": "havola faqat shu javobda ko'rinadi"})

    def _ulash_bekor(self, kim, uid):
        self._tanani_tashla()
        if kim["rol"] not in HUJJAT_ROLLAR:
            return self._xato(403, "faqat admin yoki operator")
        if not baza.ulash_bekor(uid):
            return self._xato(409, "havola topilmadi yoki allaqachon bekor")
        self._jurnal(kim, "ulash_bekor", f"id={uid}")
        return self._json(200, {"holat": "bekor"})

    def _izoh_qosh(self, kim, tid):
        if kim["rol"] not in HUJJAT_ROLLAR:
            self._tanani_tashla()
            return self._xato(403, "faqat admin yoki operator")
        t = self._tana() or {}
        try:
            iid = baza.izoh_qosh(tid, t.get("x"), t.get("y"), t.get("z"), t.get("matn", ""), kim["id"])
        except (TypeError, ValueError) as x:
            return self._xato(400, str(x))
        self._jurnal(kim, "izoh", f"id={iid} tahlil={tid}")
        return self._json(200, {"id": iid})

    def _tekshirish(self, yol):
        """IH-08: QR olib keladigan ochiq sahifa. Koordinata yo'q."""
        if not _ochiq_ruxsatmi(self._mijoz_ip()):
            return self._html(429, ochiq.topilmadi_sahifasi("Juda ko'p so'rov: bir daqiqadan keyin"))
        m = _TEKSHIR.match(yol)
        h = baza.hujjat_kod_boyicha(m.group(1)) if m else None
        if not h:
            return self._html(404, ochiq.topilmadi_sahifasi("Hujjat"))
        return self._html(200, ochiq.tekshirish_sahifasi(h, baza.obyekt_top(h["obyekt_id"])))

    def _ulash_get(self, yol, sorov):
        """UL-02/UL-03: bitta obyekt, faqat o'qish. Boshqa obyekt resursi — 404; muddat tugagan yoki bekor — 410."""
        if not _ochiq_ruxsatmi(self._mijoz_ip(), 240):
            return self._html(429, ochiq.topilmadi_sahifasi("Juda ko'p so'rov: bir daqiqadan keyin"))
        m = _ULASH_YOL.match(yol)
        u = baza.ulash_top(m.group(1)) if m else None
        if not u:
            return self._html(404, ochiq.topilmadi_sahifasi("Havola"))
        if u["holat"] != "amal":
            if (m.group(2) or "").startswith("/api/"):
                return self._xato(410, "havola yopiq")
            return self._html(410, ochiq.ulash_yopiq_sahifasi(u))
        token, qism, oid = m.group(1), m.group(2) or "", u["obyekt_id"]
        if qism in ("", "/"):
            baza.ulash_foydalan(u["id"])
            o = baza.obyekt_top(oid)
            lin = baza.liniyalar_toliq(obyekt_id=oid)
            return self._html(200, ochiq.ulash_sahifasi(token, u, o, lin, baza.hujjatlar(oid), baza.tahlillar(oid),
                                                        baza.loyiha_top(oid), baza.tasdiq_liniya_holatlari(lin)))
        hm = re.fullmatch(r"/hujjat/(\d+)\.pdf", qism)
        if hm:
            h = baza.hujjat_top(int(hm.group(1)))
            if not h or h["obyekt_id"] != oid or h["holat"] != "amal":
                return self._xato(404, "topilmadi")
            baza.ulash_foydalan(u["id"])
            return self._hujjat_fayl(h)
        if qism in ("/chizma.dxf", "/chizma.csv"):
            baza.ulash_foydalan(u["id"])
            return self._chizma_ber(oid, qism[-3:], (sorov.get("tizim") or [None])[0])
        if qism == "/3d":
            baza.ulash_foydalan(u["id"])
            return self._statik("/3d")
        if qism == "/api/tahlillar":
            return self._json(200, {"tahlillar": baza.tahlillar(oid)})
        if qism == "/api/loyiha":
            return self._json(200, {"loyiha": baza.loyiha_top(oid)})
        tm = re.fullmatch(r"/api/tahlil/(\d+)(/korinish\.ply|/izohlar)?", qism)
        if tm:
            t = baza.tahlil_top(int(tm.group(1)))
            if not t or t["obyekt_id"] != oid:
                return self._xato(404, "topilmadi")
            if tm.group(2) == "/korinish.ply":
                return self._korinish({"rol": "koruvchi"}, t["id"])
            if tm.group(2) == "/izohlar":
                return self._json(200, {"izohlar": baza.izohlar(t["id"])})
            return self._json(200, t)
        return self._xato(404, "topilmadi")

    def _ortofoto(self, yol):
        """SY-01: shahar ortofotosi plitkasi. Ortofoto cheklangan ma'lumot bo'lishi mumkin — faqat portal rollari."""
        m = _ORTOFOTO.match(yol)
        if not m or not ORTOFOTO:
            return self._xato(404, "topilmadi")
        kim = self._kim()
        if not kim:
            return self._xato(401, "kirish kerak")
        if kim["rol"] not in PORTAL_ROLLAR:
            return self._xato(403, "ruxsat yo'q")
        data = ORTOFOTO.plitka(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        if data is None:
            self.send_response(204)      # qamrovdan tashqari: bo'sh plitka, xarita xato yozmaydi
            self.send_header("Cache-Control", "private, max-age=86400")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        self._sarlavhalar(200, turi=xarita_asos.rasm_turi(data), qoshimcha={"Cache-Control": "private, max-age=86400"})
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        return None

    # ---------- statik ----------

    def _statik(self, qism):
        if qism == "/":
            fayl = os.path.join(WEB, "index.html")
        elif qism == "/3d":
            fayl = os.path.join(WEB, "3d.html")
        elif qism.startswith("/static/"):
            fayl = os.path.normpath(os.path.join(WEB, qism[len("/static/"):]))
            if not fayl.startswith(WEB + os.sep):
                return self._xato(404, "topilmadi")
        else:
            return self._xato(404, "topilmadi")
        if not os.path.isfile(fayl):
            return self._xato(404, "topilmadi")
        turi = mimetypes.guess_type(fayl)[0] or "application/octet-stream"
        if turi.startswith("text/") or turi in ("application/javascript",
                                                "application/json"):
            turi += "; charset=utf-8"
        with open(fayl, "rb") as f:
            tana = f.read()
        self._sarlavhalar(200, turi=turi)
        self.send_header("Content-Length", str(len(tana)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(tana)

    def log_message(self, fmt, *args):
        sys.stderr.write("[yerosti] %s %s\n" % (self._mijoz_ip(),
                                                fmt % args))


def admin_taminla():
    if baza.foydalanuvchi_soni() > 0:
        return None
    parol = os.environ.get("YEROSTI_ADMIN_PAROL") or secrets.token_urlsafe(9)
    baza.foydalanuvchi_yarat("admin", parol, rol="admin", ism="Administrator")
    return parol


def main():
    p = argparse.ArgumentParser(description="TRACE4D server")
    p.add_argument("--port", type=int, default=8342)
    p.add_argument("--parol-yangila", metavar="LOGIN",
                   help="foydalanuvchi parolini yangilab chiqish")
    a = p.parse_args()

    baza.init()

    if a.parol_yangila:
        yangi = secrets.token_urlsafe(9)
        if baza.parol_yangila(a.parol_yangila, yangi):
            print(f"Yangi parol [{a.parol_yangila}]: {yangi}")
        else:
            print("Bunday login topilmadi")
        return

    parol = admin_taminla()
    if parol:
        print("=" * 52)
        print("  BIRINCHI ISHGA TUSHIRISH — admin hisobi yaratildi")
        print(f"  login: admin    parol: {parol}")
        print("  (parol faqat shu yerda ko'rinadi — saqlab qo'ying)")
        print("=" * 52)

    server = ThreadingHTTPServer(("0.0.0.0", a.port), Yerosti)
    print(f"[yerosti] http://localhost:{a.port} — ishga tushdi")
    server.serve_forever()


if __name__ == "__main__":
    main()
