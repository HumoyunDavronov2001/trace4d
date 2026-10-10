"""YEROSTI — IFC 4.3 (ISO 16739-1, STEP ISO 10303-21) eksporti (TALABLAR 20: KU-01). Faqat stdlib.

Har liniya — IfcPipeSegment, geometriyasi IfcSweptDiskSolidPolygonal (quvur o'qi bo'ylab doira), koordinatalar
IfcMapConversion bilan georeferenslangan (UTM EPSG:326xx yoki lokalizatsiya qilingan mahalliy tizim). YEROSTI xususiyatlari
TRACE4D_Ijro da (sifat, manba, RTK tasdiq, aniqlik, egasi, ishlash holati, hujjat). Fayl tashqi IFC tekshiruvchi bilan
tekshirilmagan (bu mashinada yo'q) — o'z sinovimiz STEP tuzilmasini va qiymatlarni qayta o'qiydi.
"""
import re
import uuid
from datetime import datetime, timezone

_GUID_ALIFBO = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$"
PSET_NOMI = "TRACE4D_Ijro"
TARMOQ_IFC = {"suv": "Suv ta'minoti", "kanalizatsiya": "Kanalizatsiya", "gaz": "Gaz", "elektr": "Elektr kabeli",
              "optika": "Aloqa (optika)", "issiqlik": "Issiqlik tarmog'i"}


def ifc_guid(u=None):
    """UUID → IFC 22 belgili GlobalId (buildingSMART siqish)."""
    b = (u or uuid.uuid4()).bytes
    n = int.from_bytes(b, "big")
    chiq = []
    for _ in range(22):
        chiq.append(_GUID_ALIFBO[n & 63])
        n >>= 6
    return "".join(reversed(chiq))


def _s(x):
    """STEP satri: apostrof ikkilanadi, ASCII bo'lmagan belgilar \\X2\\ kodlanadi."""
    t = str(x if x is not None else "").replace("'", "''")
    if all(ord(c) < 128 for c in t):
        return f"'{t}'"
    r = []
    for c in t:
        if ord(c) < 128:
            r.append(c)
        else:
            r.append("\\X2\\" + format(ord(c), "04X") + "\\X0\\")
    return "'" + "".join(r) + "'"


def _f(x):
    if x is None:
        return "$"
    t = f"{float(x):.6f}".rstrip("0")
    return t + "0" if t.endswith(".") else t


class _Yozuvchi:
    def __init__(self):
        self.qatorlar = []

    def q(self, matn):
        self.qatorlar.append(f"#{len(self.qatorlar) + 1}={matn};")
        return len(self.qatorlar)


def ifc(liniyalar, obyekt, tizim, zona, hujjat_raqami=None):
    """liniyalar — ijro.planar_liniyalar natijasi (e sharq, n shimol, h o'q balandligi); tizim — ijro.tizim_tanla natijasi.
    Mahalliy tizimda IFC birinchi o'qi sharq (Y mahalliy), ikkinchisi shimol (X mahalliy) — TargetCRS tavsifida yoziladi."""
    if not liniyalar:
        raise ValueError("liniya yo'q")
    hamma = [p for l in liniyalar for p in l["nuqtalar"]]
    e0 = min(p["e"] for p in hamma)
    n0 = min(p["n"] for p in hamma)
    h0 = min((p["h"] for p in hamma if p.get("h") is not None), default=0.0)
    w = _Yozuvchi()
    nol = w.q("IFCCARTESIANPOINT((0.,0.,0.))")
    z = w.q("IFCDIRECTION((0.,0.,1.))")
    x = w.q("IFCDIRECTION((1.,0.,0.))")
    joy = w.q(f"IFCAXIS2PLACEMENT3D(#{nol},#{z},#{x})")
    shimol = w.q("IFCDIRECTION((0.,1.))")
    kontekst = w.q(f"IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#{joy},#{shimol})")
    metr = w.q("IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.)")
    radian = w.q("IFCSIUNIT(*,.PLANEANGLEUNIT.,$,.RADIAN.)")
    birlik = w.q(f"IFCUNITASSIGNMENT((#{metr},#{radian}))")
    if tizim["tur"] == "mahalliy":
        crs = w.q(f"IFCPROJECTEDCRS({_s(tizim['nomi'])},{_s('TRACE4D lokalizatsiyasi (nazorat punktlari bo' 'yicha); IFC o' 'qlari: X=sharq (mahalliy Y), Y=shimol (mahalliy X)')},"
                  f"{_s('mahalliy')},{_s(tizim['balandlik'])},$,$,#{metr})")
    else:
        crs = w.q(f"IFCPROJECTEDCRS({_s(f'EPSG:326{zona:02d}')},{_s(f'WGS 84 / UTM zone {zona}N')},{_s('WGS84')},"
                  f"{_s('WGS84 ellipsoid (Boltiq emas)')},{_s('Transverse Mercator (UTM)')},{_s(f'{zona}N')},#{metr})")
    w.q(f"IFCMAPCONVERSION(#{kontekst},#{crs},{_f(e0)},{_f(n0)},{_f(h0)},1.,0.,1.)")
    loyiha = w.q(f"IFCPROJECT({_s(ifc_guid())},$,{_s(obyekt.get('nomi'))},{_s('TRACE4D ijro s' 'yomkasi')},$,$,$,(#{kontekst}),#{birlik})")
    joylashuv = w.q(f"IFCLOCALPLACEMENT($,#{joy})")
    sayt = w.q(f"IFCSITE({_s(ifc_guid())},$,{_s(obyekt.get('nomi'))},{_s(obyekt.get('manzil'))},$,#{joylashuv},$,$,.ELEMENT.,$,$,$,$,$)")
    w.q(f"IFCRELAGGREGATES({_s(ifc_guid())},$,$,$,#{loyiha},(#{sayt}))")
    elementlar = []
    for l in liniyalar:
        nq = l["nuqtalar"]
        r = max((l.get("diametr_mm") or 50) / 2000.0, 0.01)
        nuqta_idlar = [w.q(f"IFCCARTESIANPOINT(({_f(p['e'] - e0)},{_f(p['n'] - n0)},{_f((p.get('h') if p.get('h') is not None else h0) - h0)}))")
                       for p in nq]
        poli = w.q("IFCPOLYLINE((" + ",".join(f"#{i}" for i in nuqta_idlar) + "))")
        jism = w.q(f"IFCSWEPTDISKSOLIDPOLYGONAL(#{poli},{_f(r)},$,$,$,$)")
        shakl = w.q(f"IFCSHAPEREPRESENTATION(#{kontekst},'Body','AdvancedSweptSolid',(#{jism}))")
        tarif = w.q(f"IFCPRODUCTDEFINITIONSHAPE($,$,(#{shakl}))")
        nom = f"{TARMOQ_IFC.get(l['turi'], l['turi'])} Ø{l.get('diametr_mm') or '?'} {l.get('material') or ''}".strip()
        turi = ".CABLESEGMENT." if l["turi"] in ("elektr", "optika") else ".RIGIDSEGMENT."
        # IFC 4.3 da kabel uchun alohida IfcCableSegment bor; quvur tarmog'i bo'lmagan turlar ham IfcPipeSegment bilan
        # emas, IfcCableSegment bilan beriladi
        if l["turi"] in ("elektr", "optika"):
            el = w.q(f"IFCCABLESEGMENT({_s(ifc_guid())},$,{_s(nom)},{_s(l.get('izoh'))},$,#{joylashuv},#{tarif},{_s(f'TRACE4D-{l['id']}')},{turi})")
        else:
            el = w.q(f"IFCPIPESEGMENT({_s(ifc_guid())},$,{_s(nom)},{_s(l.get('izoh'))},$,#{joylashuv},#{tarif},{_s(f'TRACE4D-{l['id']}')},{turi})")
        tasdiq = (l.get("tasdiq") or {}).get("holat") or "yo'q"
        xususiyat = [
            ("TarmoqTuri", "IFCLABEL", l["turi"]), ("Sifat", "IFCLABEL", l.get("sifat") or ""),
            ("RTKTasdiq_T031", "IFCLABEL", tasdiq),
            ("SifatDarajasi_PAS128", "IFCLABEL", "QL-A (ochib bevosita o'lchangan)"),
            ("Material", "IFCLABEL", l.get("material") or ""), ("DiametrMm", "IFCREAL", l.get("diametr_mm") or 0),
            ("SigmaHMaksSm", "IFCREAL", max((p.get("sigma_h_sm") or 0) for p in nq)),
            ("Egasi", "IFCLABEL", l.get("egasi") or obyekt.get("buyurtmachi") or ""),
            ("IshlashHolati", "IFCLABEL", l.get("ishlash_holati") or ""),
            ("OrnatilganYil", "IFCLABEL", str(l.get("ornatilgan_yil") or "")),
            ("Parametr", "IFCLABEL", l.get("parametr") or ""),
            ("Pudratchi", "IFCLABEL", obyekt.get("pudratchi") or ""), ("Order", "IFCLABEL", obyekt.get("order_raqami") or ""),
            ("OrderSana", "IFCLABEL", obyekt.get("order_sana") or ""),
            ("Hujjat", "IFCLABEL", hujjat_raqami or ""), ("KoordinataTizimi", "IFCLABEL", tizim["nomi"]),
            ("Balandlik", "IFCLABEL", tizim["balandlik"]), ("Manba", "IFCLABEL", "TRACE4D (LiDAR + RTK)"),
        ]
        pv = []
        for nomi, tur, qiymat in xususiyat:
            q = _f(qiymat) if tur == "IFCREAL" else _s(qiymat)
            pv.append(w.q(f"IFCPROPERTYSINGLEVALUE({_s(nomi)},$,{tur}({q}),$)"))
        pset = w.q(f"IFCPROPERTYSET({_s(ifc_guid())},$,{_s(PSET_NOMI)},$,(" + ",".join(f"#{i}" for i in pv) + "))")
        w.q(f"IFCRELDEFINESBYPROPERTIES({_s(ifc_guid())},$,$,$,(#{el}),#{pset})")
        elementlar.append(el)
    w.q(f"IFCRELCONTAINEDINSPATIALSTRUCTURE({_s(ifc_guid())},$,$,$,(" + ",".join(f"#{i}" for i in elementlar) + f"),#{sayt})")
    vaqt = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    sarlavha = ("ISO-10303-21;\nHEADER;\n"
                f"FILE_DESCRIPTION(('ViewDefinition [ReferenceView]','TRACE4D ijro s''yomkasi'),'2;1');\n"
                f"FILE_NAME({_s(f'trace4d_obyekt_{obyekt.get('id', 0)}.ifc')},'{vaqt}',('TRACE4D'),('TRACE4D'),'TRACE4D Cloud','TRACE4D','');\n"
                "FILE_SCHEMA(('IFC4X3_ADD2'));\nENDSEC;\nDATA;\n")
    return sarlavha + "\n".join(w.qatorlar) + "\nENDSEC;\nEND-ISO-10303-21;\n"


_ENT = re.compile(r"^#(\d+)=([A-Z0-9]+)\((.*)\);$")


def step_oqi(matn):
    """Sinov va tekshiruv uchun: STEP ma'lumot bo'limini {id: (tur, argumentlar matni)} ga o'qiydi; havolalar to'g'riligini tekshiradi."""
    ent = {}
    ichida = False
    for satr in matn.splitlines():
        if satr == "DATA;":
            ichida = True
            continue
        if satr == "ENDSEC;" and ichida:
            break
        if ichida:
            m = _ENT.match(satr)
            if not m:
                raise ValueError(f"STEP qatori o'qilmadi: {satr[:60]}")
            ent[int(m.group(1))] = (m.group(2), m.group(3))
    for i, (tur, arg) in ent.items():
        for h in re.findall(r"#(\d+)", re.sub(r"'(?:[^']|'')*'", "''", arg)):
            if int(h) not in ent:
                raise ValueError(f"#{i} {tur}: #{h} havolasi yo'q")
    return ent
