"""YEROSTI — raqamli muhr tekshiruvi (K-05), server tomoni.

iPhone ilova: Secure Enclave P-256 kaliti (qurilmadan chiqmaydi) bilan manifestni imzolaydi.
Manifestda xesh-zanjir boshi va yuklangan fayllar xeshlari bor. Server:
  1) imzoni qurilma ochiq kaliti bilan tekshiradi,
  2) manifestdagi har fayl haqiqatan yuklangan va xeshi mos ekanini tekshiradi,
  3) muhr jurnalini (YMJ1) qayta o'qib zanjirni noldan hisoblaydi — bosh va yozuvlar soni mos kelishi shart.
Zanjir formulasi Swift `MuhrZanjir` bilan bir xil (ikkala tomonda test bilan qotirilgan).
"""
import hashlib
import json
import struct

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec

VERSIYA = "YEROSTI-MUHR-v1"
JURNAL_SARLAVHA = b"YMJ1"
YOZUV_TURLARI = {1, 2, 3, 4, 5, 6, 7, 8}


def boshlangich():
    return hashlib.sha256(VERSIYA.encode()).digest()


def zanjir_qadami(bosh, tur, malumot):
    return hashlib.sha256(bosh + bytes([tur]) + struct.pack(">I", len(malumot)) + malumot).digest()


def jurnal_tekshir(jurnal: bytes):
    """Jurnal baytlaridan zanjirni tiklaydi → (bosh_hex, soni) yoki ValueError."""
    if not jurnal.startswith(JURNAL_SARLAVHA):
        raise ValueError("jurnal sarlavhasi YMJ1 emas")
    bosh = boshlangich()
    i, soni = 4, 0
    while i < len(jurnal):
        if i + 5 > len(jurnal):
            raise ValueError("jurnal kesilgan (yozuv sarlavhasi)")
        tur = jurnal[i]
        if tur not in YOZUV_TURLARI:
            raise ValueError(f"noma'lum yozuv turi {tur}")
        n = struct.unpack(">I", jurnal[i + 1:i + 5])[0]
        if i + 5 + n > len(jurnal):
            raise ValueError("jurnal kesilgan (yozuv ma'lumoti)")
        bosh = zanjir_qadami(bosh, tur, jurnal[i + 5:i + 5 + n])
        soni += 1
        i += 5 + n
    return bosh.hex(), soni


def jurnal_yozuvlari(jurnal: bytes):
    """ShN-05: jurnal yozuvlari ketma-ket (tur, ma'lumot). Tuzilish `jurnal_tekshir` bilan bir xil tekshiriladi."""
    if not jurnal.startswith(JURNAL_SARLAVHA):
        raise ValueError("jurnal sarlavhasi YMJ1 emas")
    i = 4
    while i < len(jurnal):
        if i + 5 > len(jurnal):
            raise ValueError("jurnal kesilgan (yozuv sarlavhasi)")
        tur = jurnal[i]
        if tur not in YOZUV_TURLARI:
            raise ValueError(f"noma'lum yozuv turi {tur}")
        n = struct.unpack(">I", jurnal[i + 1:i + 5])[0]
        if i + 5 + n > len(jurnal):
            raise ValueError("jurnal kesilgan (yozuv ma'lumoti)")
        yield tur, jurnal[i + 5:i + 5 + n]
        i += 5 + n


def ochiq_kalit_yukla(x963: bytes):
    """65 baytli siqilmagan P-256 nuqtasi (CryptoKit `x963Representation`)."""
    if len(x963) != 65 or x963[0] != 0x04:
        raise ValueError("ochiq kalit 65 baytli siqilmagan P-256 nuqta bo'lishi kerak")
    return ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), x963)


def imzo_tekshir(x963: bytes, manifest: bytes, imzo_der: bytes) -> bool:
    """CryptoKit `P256.Signing` imzosi: ECDSA(SHA-256) — DER ko'rinishida."""
    try:
        ochiq_kalit_yukla(x963).verify(imzo_der, manifest, ec.ECDSA(hashes.SHA256()))
        return True
    except (InvalidSignature, ValueError):
        return False


def manifest_ajrat(manifest: bytes) -> dict:
    m = json.loads(manifest.decode("utf-8"))
    kerak = {"versiya", "obyekt_id", "qurilma", "boshlandi", "tugadi", "yozuv_soni", "zanjir_boshi", "fayllar"}
    if not isinstance(m, dict) or not kerak.issubset(m):
        raise ValueError("manifest maydonlari to'liq emas")
    if m["versiya"] != VERSIYA:
        raise ValueError(f"manifest versiyasi {m['versiya']!r}")
    if not isinstance(m["fayllar"], list) or not m["fayllar"]:
        raise ValueError("manifestda fayllar yo'q")
    for f in m["fayllar"]:
        if not {"nomi", "sha256", "hajm"}.issubset(f):
            raise ValueError("manifest fayl yozuvi to'liq emas")
    return m
