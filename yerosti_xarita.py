"""YEROSTI — xarita asoslari (TALABLAR 16: SY-01, SY-02). Faqat stdlib.

- Shahar ortofotosi: MBTiles 1.3 fayli (QGIS "Generate XYZ tiles (MBTiles)" bilan Web Mercator da yasaladi), serverning
  o'zidan beriladi — tashqi xizmatga so'rov yo'q, ko'rilayotgan hudud oshkor bo'lmaydi.
- Tashqi sun'iy yo'ldosh: XYZ shablon; atributsiyasiz yoqilmaydi (Esri, Google, MapTiler shartlari).
Surat o'lchov aniqligini oshirmaydi: e'lon qilingan aniqlik ekranda doim yoziladi, o'lchov suratga moslanmaydi.
"""
import os
import sqlite3
from urllib.parse import urlparse

FORMATLAR = {b"\x89PNG": "image/png", b"\xff\xd8\xff": "image/jpeg"}


def rasm_turi(data):
    for bosh, tur in FORMATLAR.items():
        if data.startswith(bosh):
            return tur
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return "application/octet-stream"


def _son(x, tur=float):
    try:
        return tur(x) if x not in (None, "") else None
    except (TypeError, ValueError):
        return None


class MBTiles:
    """Faqat o'qish (immutable): har so'rovda yangi ulanish — ThreadingHTTPServer oqimlari bir-biriga xalaqit bermaydi."""

    def __init__(self, yol):
        self.yol = os.path.abspath(yol)
        if not os.path.isfile(self.yol):
            raise FileNotFoundError(self.yol)
        u = self._ulan()
        try:
            self.meta = {r[0]: r[1] for r in u.execute("SELECT name, value FROM metadata")}
            u.execute("SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles LIMIT 1").fetchall()
        finally:
            u.close()

    def _ulan(self):
        return sqlite3.connect(f"file:{self.yol}?mode=ro&immutable=1", uri=True, check_same_thread=False)

    def plitka(self, z, x, y):
        """XYZ (y — shimoldan) → MBTiles TMS qatori (y — janubdan): tile_row = 2^z − 1 − y."""
        if not (0 <= z <= 25 and 0 <= x < (1 << z) and 0 <= y < (1 << z)):
            return None
        u = self._ulan()
        try:
            r = u.execute("SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?",
                          (z, x, (1 << z) - 1 - y)).fetchone()
        finally:
            u.close()
        return bytes(r[0]) if r and r[0] else None

    def tavsif(self, aniqlik_m=None):
        m = self.meta
        chegara = [_son(v) for v in (m.get("bounds") or "").split(",")] if m.get("bounds") else None
        if chegara and (len(chegara) != 4 or None in chegara):
            chegara = None
        return {"id": "ortofoto", "nomi": m.get("name") or "Shahar ortofotosi", "tiles": "/xarita/ortofoto/{z}/{x}/{y}",
                "min_zoom": _son(m.get("minzoom"), int) or 0, "maks_zoom": _son(m.get("maxzoom"), int) or 19,
                "chegara": chegara, "atributsiya": m.get("attribution") or "", "aniqlik_m": aniqlik_m,
                "format": m.get("format") or ""}


def tashqi_tavsif(url, atributsiya, aniqlik_m, maks_zoom):
    """SY-02: shablon {z} {x} {y} ni o'z ichiga olsin, https bo'lsin, {s} kabi pastki domen shabloni yo'q (CSP aniq
    manzilga ochiladi), atributsiya majburiy. Yaroqsiz bo'lsa — None (o'chiq)."""
    if not url or not atributsiya:
        return None
    p = urlparse(url)
    if p.scheme != "https" or not p.netloc or "{" in p.netloc or not all(k in url for k in ("{z}", "{x}", "{y}")):
        return None
    return {"id": "suniy", "nomi": "Sun'iy yo'ldosh", "tiles": url, "min_zoom": 0, "maks_zoom": maks_zoom or 19,
            "chegara": None, "atributsiya": atributsiya, "aniqlik_m": aniqlik_m, "manba": f"{p.scheme}://{p.netloc}"}
