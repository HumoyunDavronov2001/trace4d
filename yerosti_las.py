"""YEROSTI — tashqi LiDAR nuqta buluti (TALABLAR 19: LD). Faqat stdlib.

LAS 1.2–1.4 (siqilmagan, PDRF 0–10) va YEROSTI PLY fayllarini o'qiydi, koordinatani UTM ga keltiradi (utm | wgs84 |
mahalliy — lokalizatsiya bilan), voksel bilan siyraklashtiradi va yadro `yerosti-tahlil aniqla` o'qiydigan binary PLY
yozadi (Swift `PLY.yoz` formati: float32 nisbiy koordinata + `comment boshlangich E N H`).
LAZ (siqilgan) qo'llanmaydi — xato aniq aytiladi: laszip / CloudCompare bilan LAS ga oching.
"""
import math
import struct

import yerosti_chizma as chizma
import yerosti_lokal as lokal

MAKS_NUQTA = 3_000_000      # yadroga beriladigan eng ko'p nuqta: undan ko'p bo'lsa voksel kattalashadi
VOKSEL_M = 0.01             # QuvurTopish vokseli bilan bir xil — zichroq nuqta foyda bermaydi
KOORDINATA_TIZIMLARI = ("utm", "wgs84", "mahalliy")


class LASXato(ValueError):
    pass


def las_sarlavha(d):
    """LAS sarlavhasi → dict. Siqilgan (LAZ) bo'lsa LASXato."""
    if len(d) < 227 or d[:4] != b"LASF":
        raise LASXato("LAS emas (LASF imzosi yo'q)")
    major, minor = d[24], d[25]
    sarlavha_hajmi, ofset = struct.unpack_from("<HI", d, 94)
    pdrf, yozuv_uz = struct.unpack_from("<BH", d, 104)
    soni = struct.unpack_from("<I", d, 107)[0]
    sx, sy, sz, ox, oy, oz = struct.unpack_from("<6d", d, 131)
    if pdrf & 0x80 or pdrf & 0x40:
        raise LASXato("LAZ (siqilgan LAS): laszip yoki CloudCompare bilan siqilmagan LAS ga oching")
    if pdrf > 10:
        raise LASXato(f"noma'lum nuqta formati {pdrf}")
    if major == 1 and minor >= 4 and len(d) >= 255:
        soni64 = struct.unpack_from("<Q", d, 247)[0]
        if soni64:
            soni = soni64
    if yozuv_uz < 12:
        raise LASXato("nuqta yozuvi 12 baytdan qisqa")
    if ofset < sarlavha_hajmi or ofset > len(d):
        raise LASXato("nuqta ma'lumoti ofseti noto'g'ri")
    mavjud = (len(d) - ofset) // yozuv_uz
    if soni == 0 or soni > mavjud:
        soni = mavjud
    return {"versiya": f"{major}.{minor}", "pdrf": pdrf, "yozuv_uz": yozuv_uz, "soni": soni, "ofset": ofset,
            "masshtab": (sx, sy, sz), "siljish": (ox, oy, oz)}


def las_nuqtalar(d, qadam=1):
    """LAS nuqtalari (x, y, z) — fayl koordinatasida. `qadam` > 1 bo'lsa har qadam-nchi nuqta."""
    s = las_sarlavha(d)
    sx, sy, sz = s["masshtab"]
    ox, oy, oz = s["siljish"]
    fmt = struct.Struct(f"<iii{s['yozuv_uz'] - 12}x")
    bosh, oxir = s["ofset"], s["ofset"] + s["soni"] * s["yozuv_uz"]
    for i, (x, y, z) in enumerate(fmt.iter_unpack(d[bosh:oxir])):
        if qadam > 1 and i % qadam:
            continue
        yield x * sx + ox, y * sy + oy, z * sz + oz


def las_yoz(nuqtalar, masshtab=0.001):
    """Sinov va eksport uchun: LAS 1.2, PDRF 0 (20 bayt) yozadi. nuqtalar — [(x, y, z)]."""
    n = list(nuqtalar)
    if not n:
        raise LASXato("nuqta yo'q")
    ox = min(p[0] for p in n); oy = min(p[1] for p in n); oz = min(p[2] for p in n)
    sarlavha = bytearray(227)
    sarlavha[0:4] = b"LASF"
    sarlavha[24], sarlavha[25] = 1, 2
    struct.pack_into("<HI", sarlavha, 94, 227, 227)
    struct.pack_into("<BH", sarlavha, 104, 0, 20)
    struct.pack_into("<I", sarlavha, 107, len(n))
    struct.pack_into("<6d", sarlavha, 131, masshtab, masshtab, masshtab, ox, oy, oz)
    struct.pack_into("<6d", sarlavha, 179, max(p[0] for p in n), ox, max(p[1] for p in n), oy, max(p[2] for p in n), oz)
    tana = bytearray()
    for x, y, z in n:
        tana += struct.pack("<iiiHBBbBH", round((x - ox) / masshtab), round((y - oy) / masshtab), round((z - oz) / masshtab),
                            0, 0, 0, 0, 0, 0)
    return bytes(sarlavha) + bytes(tana)


def ply_oqi(d):
    """YEROSTI PLY (binary little endian, float x y z [nx ny nz], `comment boshlangich`) yoki oddiy ASCII PLY → (x, y, z)."""
    k = d.find(b"end_header\n")
    if k < 0:
        raise LASXato("PLY sarlavhasi yo'q")
    sarl = d[:k].decode("ascii", "replace").split("\n")
    soni, bosh, xossalar, format_ = 0, (0.0, 0.0, 0.0), [], ""
    for q in sarl:
        m = q.split()
        if len(m) >= 2 and m[0] == "format":
            format_ = m[1]
        if len(m) == 3 and m[0] == "element" and m[1] == "vertex":
            soni = int(m[2])
        if len(m) == 3 and m[0] == "property":
            xossalar.append((m[1], m[2]))
        if len(m) == 5 and m[0] == "comment" and m[1] == "boshlangich":
            bosh = (float(m[2]), float(m[3]), float(m[4]))
    tana = d[k + len(b"end_header\n"):]
    nomlar = [n for _, n in xossalar]
    if not {"x", "y", "z"} <= set(nomlar):
        raise LASXato("PLY da x y z yo'q")
    if format_ == "ascii":
        for satr in tana.decode("ascii", "replace").splitlines()[:soni]:
            q = satr.split()
            if len(q) < len(nomlar):
                continue
            v = dict(zip(nomlar, q))
            yield float(v["x"]) + bosh[0], float(v["y"]) + bosh[1], float(v["z"]) + bosh[2]
        return
    if format_ != "binary_little_endian":
        raise LASXato(f"PLY formati qo'llanmaydi: {format_}")
    turlar = {"float": "f", "float32": "f", "double": "d", "float64": "d", "uchar": "B", "uint8": "B", "char": "b", "int8": "b",
              "short": "h", "int16": "h", "ushort": "H", "uint16": "H", "int": "i", "int32": "i", "uint": "I", "uint32": "I"}
    fmt = "<" + "".join(turlar.get(t, "f") for t, _ in xossalar)
    st = struct.Struct(fmt)
    ix, iy, iz = nomlar.index("x"), nomlar.index("y"), nomlar.index("z")
    for v in st.iter_unpack(tana[:soni * st.size]):
        yield v[ix] + bosh[0], v[iy] + bosh[1], v[iz] + bosh[2]


def utm_ga(nuqtalar, koordinata, zona=None, lok=None):
    """Nuqtalarni (E, N, H) UTM ga keltiradi. utm — o'zgarmaydi (zona kerak); wgs84 — (lon, lat, h) yoki (lat, lon, h);
    mahalliy — (X shimol, Y sharq, H Boltiq) lokalizatsiya teskarisi bilan (ellipsoid balandlik qaytadi)."""
    if koordinata not in KOORDINATA_TIZIMLARI:
        raise LASXato("koordinata tizimi: utm, wgs84 yoki mahalliy")
    if koordinata == "utm":
        if not zona:
            raise LASXato("UTM zonasi kerak (masalan 42)")
        for e, n, h in nuqtalar:
            yield e, n, h, zona
        return
    if koordinata == "mahalliy":
        if lok is None:
            raise LASXato("mahalliy koordinata uchun obyekt lokalizatsiyasi kerak")
        for x, y, h in nuqtalar:
            lat, lon, hh = lok.teskari(x, y, h)
            e, n, z = chizma.utm(lat, lon, zona)
            yield e, n, hh if hh is not None else h, z
        return
    # wgs84: GIS/LAS tartibi — X = uzunlik (lon), Y = kenglik (lat). Faqat aniq bo'lsa (birinchisi ≤ 90, ikkinchisi > 90)
    # almashtiriladi; O'zbekistonda ikkalasi ham ≤ 90 — tartib foydalanuvchiga portalda yoziladi.
    birinchi = True
    lat_avval = False
    for a, b, h in nuqtalar:
        if birinchi:
            lat_avval = abs(a) <= 90 < abs(b)
            birinchi = False
        lat, lon = (a, b) if lat_avval else (b, a)
        e, n, z = chizma.utm(lat, lon, zona)
        yield e, n, h, z


def voksel(nuqtalar, v=VOKSEL_M, maks=MAKS_NUQTA):
    """Voksel bilan siyraklashtirish (har katakda birinchi nuqta). `maks` dan oshsa voksel 1,4 marta kattalashib qayta."""
    n = list(nuqtalar)
    while True:
        korilgan, tanlangan = set(), []
        for p in n:
            k = (math.floor(p[0] / v), math.floor(p[1] / v), math.floor(p[2] / v))
            if k not in korilgan:
                korilgan.add(k)
                tanlangan.append(p)
        if len(tanlangan) <= maks:
            return tanlangan, v
        v *= 1.4


def ply_yoz(nuqtalar, izoh="TRACE4D tashqi LiDAR"):
    """Swift `PLY.yoz` bilan bir xil: float32 nisbiy koordinata, `comment boshlangich E N H` (birinchi nuqta)."""
    n = list(nuqtalar)
    if not n:
        raise LASXato("nuqta yo'q")
    e0, n0, h0 = n[0][0], n[0][1], n[0][2]
    sarl = (f"ply\nformat binary_little_endian 1.0\ncomment {izoh}\ncomment boshlangich {e0:.4f} {n0:.4f} {h0:.4f}\n"
            f"element vertex {len(n)}\nproperty float x\nproperty float y\nproperty float z\nend_header\n")
    tana = bytearray()
    st = struct.Struct("<fff")
    for e, nn, h in n:
        tana += st.pack(e - e0, nn - n0, h - h0)
    return sarl.encode("ascii") + bytes(tana)


def tayyorla(fayl, kengaytma, koordinata, zona=None, lok=None):
    """Tashqi fayl → (PLY baytlari, ma'lumot). ma'lumot: nuqta soni (asl, tanlangan), voksel, zona, chegara."""
    if kengaytma == "las":
        s = las_sarlavha(fayl)
        qadam = max(1, math.ceil(s["soni"] / (MAKS_NUQTA * 4)))     # xotira: avval har qadam-nchi nuqta
        xom = las_nuqtalar(fayl, qadam)
        asl = s["soni"]
    elif kengaytma == "ply":
        xom = list(ply_oqi(fayl))
        asl = len(xom)
    else:
        raise LASXato("fayl turi: las yoki ply")
    utm = list(utm_ga(xom, koordinata, zona, lok))
    if not utm:
        raise LASXato("faylda nuqta yo'q")
    zona_ = utm[0][3]
    if any(z != zona_ for _, _, _, z in utm[: min(len(utm), 1000)]):
        raise LASXato("nuqtalar ikki UTM zonasiga tushadi")
    tanlangan, v = voksel([(e, n, h) for e, n, h, _ in utm])
    e = [p[0] for p in tanlangan]; n = [p[1] for p in tanlangan]; h = [p[2] for p in tanlangan]
    return ply_yoz(tanlangan), {"asl_soni": asl, "soni": len(tanlangan), "voksel_m": round(v, 4), "zona": zona_,
                                "chegara": [min(e), min(n), min(h), max(e), max(n), max(h)]}
