"""YEROSTI — tashqi LiDAR fayllari sinovi (TALABLAR 19: LD-02). Bazasiz. Geometriya SUN'IY.
Ishga tushirish: python3 sinov/las_sinov.py"""
import math
import os
import struct
import sys

YEROSTI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, YEROSTI)
import yerosti_chizma as chizma  # noqa: E402
import yerosti_las as L  # noqa: E402

natijalar = []


def tekshir(nom, shart, izoh=""):
    natijalar.append((nom, bool(shart)))
    print(("PASS " if shart else "FAIL ") + nom + (f"  [{izoh}]" if (izoh and not shart) else ""))


try:
    E0, N0, H0 = 362300.0, 4445250.0, 400.0
    pts = [(E0 + i * 0.01, N0 + 0.5 * math.sin(i / 30), H0 + 0.002 * i) for i in range(3000)]
    las = L.las_yoz(pts)
    s = L.las_sarlavha(las)
    oqilgan = list(L.las_nuqtalar(las))
    tekshir("LAS 1.2 PDRF 0 yoziladi va o'qiladi (3000 nuqta, 1 mm masshtab)",
            s["soni"] == 3000 and s["pdrf"] == 0 and len(oqilgan) == 3000
            and max(abs(a - b) for p, q in zip(pts, oqilgan) for a, b in zip(p, q)) < 0.0006, str(s))
    tekshir("qadam 10 — har o'ninchi nuqta", len(list(L.las_nuqtalar(las, 10))) == 300)
    laz = bytearray(las)
    laz[104] |= 0x80
    try:
        L.las_sarlavha(bytes(laz))
        tekshir("LAZ (siqilgan) aniq xato bilan rad etiladi", False)
    except L.LASXato as x:
        tekshir("LAZ (siqilgan) aniq xato bilan rad etiladi", "laszip" in str(x), str(x))
    try:
        L.las_sarlavha(b"PLYF" + bytes(300))
        tekshir("LAS bo'lmagan fayl rad etiladi", False)
    except L.LASXato:
        tekshir("LAS bo'lmagan fayl rad etiladi", True)
    # LAS 1.4: 375 baytli sarlavha, 64 bitli soni
    s14 = bytearray(375)
    s14[0:4] = b"LASF"; s14[24], s14[25] = 1, 4
    struct.pack_into("<HI", s14, 94, 375, 375); struct.pack_into("<BH", s14, 104, 6, 30); struct.pack_into("<I", s14, 107, 0)
    struct.pack_into("<6d", s14, 131, 0.01, 0.01, 0.01, 100.0, 200.0, 10.0); struct.pack_into("<Q", s14, 247, 2)
    tana = struct.pack("<iii18x", 100, 200, 300) + struct.pack("<iii18x", 110, 220, 330)
    q = list(L.las_nuqtalar(bytes(s14) + tana))
    tekshir("LAS 1.4 PDRF 6 (30 bayt), 64 bitli soni, masshtab 1 sm", q == [(101.0, 202.0, 13.0), (101.1, 202.2, 13.3)], str(q))

    # PLY: Swift formati bilan mos sarlavha; o'qish teskari
    ply = L.ply_yoz(pts[:5])
    sarl = ply[:ply.find(b"end_header")].decode()
    tekshir("PLY sarlavhasi Swift PLY.oqi kutganidek (binary_little_endian, boshlangich, float x y z)",
            "format binary_little_endian 1.0" in sarl and f"comment boshlangich {E0:.4f} {N0:.4f} {H0:.4f}" in sarl
            and "property float x" in sarl and "element vertex 5" in sarl, sarl)
    qayta = list(L.ply_oqi(ply))
    tekshir("PLY o'qish: boshlang'ich qo'shilib absolyut UTM qaytadi (float32 → < 1 mm)",
            len(qayta) == 5 and max(abs(a - b) for p, r in zip(pts[:5], qayta) for a, b in zip(p, r)) < 1e-3, str(qayta[:2]))
    ascii_ply = ("ply\nformat ascii 1.0\nelement vertex 2\nproperty float x\nproperty float y\nproperty float z\n"
                 "property uchar red\nend_header\n1 2 3 255\n4 5 6 0\n").encode()
    tekshir("ASCII PLY (qo'shimcha ustun bilan) o'qiladi", list(L.ply_oqi(ascii_ply)) == [(1.0, 2.0, 3.0), (4.0, 5.0, 6.0)])

    # koordinata tizimlari
    lat, lon = 40.1151, 67.8421
    e, n, z = chizma.utm(lat, lon, None)
    w1 = list(L.utm_ga([(lon, lat, 400.0)], "wgs84"))
    w2 = list(L.utm_ga([(40.0, 100.0, 1.0)], "wgs84"))
    tekshir("wgs84: X = lon, Y = lat (GIS tartibi) → UTM 42; aniq teskari tartib (40, 100) almashtiriladi",
            abs(w1[0][0] - e) < 1e-6 and abs(w1[0][1] - n) < 1e-6 and w1[0][3] == z == 42 and w2[0][3] == 47, str((w1, w2)))
    tekshir("utm: zona shart", any(True for _ in [0]) and (lambda: (list(L.utm_ga([(1, 2, 3)], "utm", 42))[0][3] == 42))())
    try:
        list(L.utm_ga([(1, 2, 3)], "utm"))
        tekshir("utm zonasiz xato", False)
    except L.LASXato:
        tekshir("utm zonasiz xato", True)
    try:
        list(L.utm_ga([(1, 2, 3)], "mahalliy"))
        tekshir("mahalliy lokalizatsiyasiz xato", False)
    except L.LASXato:
        tekshir("mahalliy lokalizatsiyasiz xato", True)

    # voksel
    zich = [(i * 0.002, 0.0, 0.0) for i in range(1000)]
    t, v = L.voksel(zich, 0.01, 100000)
    tekshir("voksel 1 sm: 2 mm qadamli 1000 nuqta → ~200", 195 <= len(t) <= 201 and v == 0.01, str((len(t), v)))
    t2, v2 = L.voksel(zich, 0.01, 50)
    tekshir("maksdan oshsa voksel kattalashadi (≤ 50 nuqta)", len(t2) <= 50 and v2 > 0.01, str((len(t2), v2)))

    # tayyorla: LAS → PLY + ma'lumot
    ply2, m = L.tayyorla(las, "las", "utm", 42)
    tekshir("tayyorla(las, utm 42): PLY va ma'lumot (soni, voksel, zona, chegara)",
            m["zona"] == 42 and m["asl_soni"] == 3000 and 0 < m["soni"] <= 3000 and m["chegara"][0] <= E0 + 1e-6 and len(ply2) > 100, str(m))
    try:
        L.tayyorla(las, "xyz", "utm", 42)
        tekshir("noma'lum kengaytma xato", False)
    except L.LASXato:
        tekshir("noma'lum kengaytma xato", True)
except Exception as ex:   # noqa: BLE001
    import traceback
    traceback.print_exc()
    natijalar.append((f"istisno: {ex}", False))

fail = [n for n, ok in natijalar if not ok]
print(f"\nJAMI: {len(natijalar)} tekshiruv, {len(fail)} FAIL")
sys.exit(1 if fail else 0)
