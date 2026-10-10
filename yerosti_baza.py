"""YEROSTI — baza qatlami.

SQLite, tashqi kutubxonasiz. Qoidalar: o'chirish yo'q (faqat versiyalash,
T-064), jurnal o'chmas (T-035), har nuqtada RTK holati va drayver
metama'lumoti (T-035), sifat qoidasi bitta joyda (T-103) — iOS drayverida
BIR XIL takrorlanadi.
"""
import hashlib
import json
import math
import os
import secrets
import sqlite3
from datetime import datetime, timedelta, timezone

ILDIZ = os.path.dirname(os.path.abspath(__file__))
# Sinov muhiti uchun env orqali almashtiriladi — haqiqiy bazaga sinov tegmaydi.
BAZA_YOL = os.environ.get("YEROSTI_BAZA") or os.path.join(ILDIZ, "yerosti.db")
SKAN_PAPKA = os.environ.get("YEROSTI_SKANLAR") or os.path.join(ILDIZ, "skanlar")

TARMOQ_TURLARI = ("suv", "kanalizatsiya", "gaz", "elektr", "optika", "issiqlik")
RTK_HOLATLAR = ("FIX", "FLOAT", "DGPS", "GPS", "YOQ")
# Nuqta manbasi: "rtk" — vexa uchi bilan bevosita RTK o'lchov; "skan" — LiDAR/fotogrammetriya + RTK
# georeferensdan hisoblangan (T-031: rasmiy hujjatga faqat RTK nazorat nuqtalari bilan tasdiqlangach).
NUQTA_MANBALARI = ("rtk", "skan")
SKAN_TURLARI = ("mesh_usdz", "mesh_obj", "nuqta_ply", "foto", "nmea_jurnal", "muhr_jurnal", "kadrlar", "nuqta_las")
SKAN_KENGAYTMA = {"mesh_usdz": "usdz", "mesh_obj": "obj", "nuqta_ply": "ply",
                  "foto": "jpg", "nmea_jurnal": "nmea.gz", "muhr_jurnal": "ymj", "kadrlar": "zip", "nuqta_las": "las"}
ROLLAR = ("admin", "operator", "koruvchi")
SESSIYA_MUDDAT_SOAT = 12
BOLAK_HAJMI = 4 * 1024 * 1024
SKAN_CHEK_BAYT = 300 * 1024 * 1024  # T-064

# T-103 — sifat qoidasi. Isbotsiz nuqta rasmiy bo'lmaydi.
SIGMA_H_CHEK_SM = 2.0
SIGMA_V_CHEK_SM = 5.0
TUZATMA_YOSHI_CHEK_S = 10.0


def sifat_hisobla(rtk_holat, sigma_h_sm, sigma_v_sm, tuzatma_yoshi_s):
    if rtk_holat != "FIX":
        return "PAST"
    if sigma_h_sm is None or float(sigma_h_sm) > SIGMA_H_CHEK_SM:
        return "PAST"
    if sigma_v_sm is None or float(sigma_v_sm) > SIGMA_V_CHEK_SM:
        return "PAST"
    if tuzatma_yoshi_s is None or float(tuzatma_yoshi_s) > TUZATMA_YOSHI_CHEK_S:
        return "PAST"
    return "RASMIY"


SCHEMA = """
CREATE TABLE IF NOT EXISTS foydalanuvchi(
  id INTEGER PRIMARY KEY,
  login TEXT UNIQUE NOT NULL,
  parol_hash TEXT NOT NULL,
  tuz TEXT NOT NULL,
  rol TEXT NOT NULL DEFAULT 'operator',
  ism TEXT DEFAULT '',
  faol INTEGER DEFAULT 1,
  yaratilgan TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessiya(
  id INTEGER PRIMARY KEY,
  foydalanuvchi_id INTEGER NOT NULL REFERENCES foydalanuvchi(id),
  token_hash TEXT UNIQUE NOT NULL,
  yaratilgan TEXT NOT NULL,
  muddati TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS dala_token(
  id INTEGER PRIMARY KEY,
  nomi TEXT NOT NULL,
  qurilma TEXT DEFAULT '',
  token_hash TEXT UNIQUE NOT NULL,
  faol INTEGER DEFAULT 1,
  yaratilgan TEXT NOT NULL,
  yaratuvchi_id INTEGER,
  oxirgi_ishlatilgan TEXT
);
CREATE TABLE IF NOT EXISTS obyekt(
  id INTEGER PRIMARY KEY,
  nomi TEXT NOT NULL,
  manzil TEXT DEFAULT '',
  buyurtmachi TEXT DEFAULT '',
  pudratchi TEXT DEFAULT '',
  order_raqami TEXT DEFAULT '',
  holat TEXT DEFAULT 'ochiq',
  yaratilgan TEXT NOT NULL,
  yaratuvchi_id INTEGER,
  dala_token_id INTEGER
);
CREATE TABLE IF NOT EXISTS liniya(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  versiya INTEGER DEFAULT 1,
  holat TEXT DEFAULT 'amal',
  turi TEXT NOT NULL,
  material TEXT DEFAULT '',
  diametr_mm INTEGER DEFAULT 0,
  izoh TEXT DEFAULT '',
  yaratilgan TEXT NOT NULL,
  yaratuvchi_id INTEGER,
  dala_token_id INTEGER
);
CREATE TABLE IF NOT EXISTS nuqta(
  id INTEGER PRIMARY KEY,
  liniya_id INTEGER NOT NULL REFERENCES liniya(id),
  tartib INTEGER NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  balandlik REAL,
  chuqurlik_m REAL,
  rtk_holat TEXT DEFAULT 'YOQ',
  aniqlik_sm REAL,
  izoh TEXT DEFAULT '',
  vaqt TEXT,
  qurilma_seriya TEXT,
  tuzatma_manbai TEXT,
  tuzatma_yoshi_s REAL,
  antenna_balandligi_m REAL,
  qiyshayish_deg REAL,
  sigma_h_sm REAL,
  sigma_v_sm REAL,
  sputnik_soni INTEGER,
  sifat TEXT DEFAULT 'PAST',
  manba TEXT DEFAULT 'rtk'
);
CREATE INDEX IF NOT EXISTS idx_nuqta_liniya ON nuqta(liniya_id, tartib);
CREATE INDEX IF NOT EXISTS idx_liniya_obyekt ON liniya(obyekt_id);
CREATE TABLE IF NOT EXISTS skan(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  liniya_id INTEGER REFERENCES liniya(id),
  turi TEXT NOT NULL,
  fayl_yol TEXT DEFAULT '',
  hajmi INTEGER NOT NULL,
  sha256 TEXT NOT NULL,
  bolak_soni INTEGER NOT NULL,
  qabul_bolaklar INTEGER DEFAULT 0,
  holat TEXT DEFAULT 'yuklanmoqda',
  xato TEXT DEFAULT '',
  rms_sm REAL,
  markerlar TEXT,
  meta TEXT,
  yaratilgan TEXT NOT NULL,
  yakunlangan TEXT,
  yaratuvchi_id INTEGER,
  dala_token_id INTEGER
);
CREATE INDEX IF NOT EXISTS idx_skan_obyekt ON skan(obyekt_id);
CREATE TABLE IF NOT EXISTS qurilma_kalit(
  id INTEGER PRIMARY KEY,
  dala_token_id INTEGER NOT NULL REFERENCES dala_token(id),
  ochiq_kalit TEXT NOT NULL,
  faol INTEGER DEFAULT 1,
  yaratilgan TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS muhr(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  dala_token_id INTEGER,
  qurilma_kalit_id INTEGER,
  manifest TEXT NOT NULL,
  imzo TEXT NOT NULL,
  holat TEXT NOT NULL,
  sabab TEXT DEFAULT '',
  zanjir_boshi TEXT,
  yozuv_soni INTEGER,
  yaratilgan TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_muhr_obyekt ON muhr(obyekt_id);
CREATE TABLE IF NOT EXISTS tahlil_ish(
  id INTEGER PRIMARY KEY,
  muhr_id INTEGER REFERENCES muhr(id),
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  jurnal_skan_id INTEGER REFERENCES skan(id),
  ply_skan_id INTEGER NOT NULL REFERENCES skan(id),
  holat TEXT NOT NULL DEFAULT 'kutmoqda',
  xulosa TEXT,
  natija TEXT,
  xato TEXT DEFAULT '',
  urinish INTEGER DEFAULT 0,
  yaratilgan TEXT NOT NULL,
  boshlangan TEXT,
  tugagan TEXT
);
CREATE INDEX IF NOT EXISTS idx_tahlil_holat ON tahlil_ish(holat, id);
CREATE INDEX IF NOT EXISTS idx_tahlil_obyekt ON tahlil_ish(obyekt_id);
CREATE TABLE IF NOT EXISTS jurnal(
  id INTEGER PRIMARY KEY,
  vaqt TEXT NOT NULL,
  foydalanuvchi_id INTEGER,
  amal TEXT NOT NULL,
  tafsilot TEXT DEFAULT ''
);
CREATE TABLE IF NOT EXISTS hujjat(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  raqam TEXT UNIQUE,
  kod TEXT UNIQUE NOT NULL,
  fayl TEXT DEFAULT '',
  sha256 TEXT DEFAULT '',
  hajmi INTEGER DEFAULT 0,
  varaqlar INTEGER DEFAULT 0,
  xulosa TEXT DEFAULT '{}',
  holat TEXT NOT NULL DEFAULT 'yasalmoqda',
  bekor_sabab TEXT DEFAULT '',
  bekor_vaqt TEXT,
  yaratuvchi_id INTEGER,
  yaratilgan TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_hujjat_obyekt ON hujjat(obyekt_id);
CREATE TABLE IF NOT EXISTS belgi(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  liniya_id INTEGER REFERENCES liniya(id),
  nuqta_tartib INTEGER,
  tur TEXT NOT NULL,
  raqam TEXT NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  balandlik REAL,
  chuqurlik_m REAL,
  pikitaj_m REAL,
  kod TEXT UNIQUE NOT NULL,
  aloqa TEXT DEFAULT '',
  izoh TEXT DEFAULT '',
  holat TEXT NOT NULL DEFAULT 'amal',
  bekor_sabab TEXT DEFAULT '',
  bekor_vaqt TEXT,
  korishlar INTEGER DEFAULT 0,
  oxirgi_korish TEXT,
  yaratuvchi_id INTEGER,
  yaratilgan TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_belgi_obyekt ON belgi(obyekt_id);
CREATE TABLE IF NOT EXISTS loyiha(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  fayl_nomi TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  hajmi INTEGER NOT NULL,
  z_turi TEXT NOT NULL,
  z_tizimi TEXT NOT NULL,
  chiziqlar TEXT NOT NULL,
  holat TEXT NOT NULL DEFAULT 'amal',
  yaratuvchi_id INTEGER,
  yaratilgan TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_loyiha_obyekt ON loyiha(obyekt_id);
CREATE TABLE IF NOT EXISTS ulash(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  token_hash TEXT UNIQUE NOT NULL,
  nomi TEXT NOT NULL,
  muddati TEXT NOT NULL,
  bekor INTEGER DEFAULT 0,
  bekor_vaqt TEXT,
  foydalanish INTEGER DEFAULT 0,
  oxirgi TEXT,
  yaratuvchi_id INTEGER,
  yaratilgan TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ulash_obyekt ON ulash(obyekt_id);
CREATE TABLE IF NOT EXISTS izoh(
  id INTEGER PRIMARY KEY,
  tahlil_id INTEGER NOT NULL REFERENCES tahlil_ish(id),
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  x REAL NOT NULL,
  y REAL NOT NULL,
  z REAL NOT NULL,
  matn TEXT NOT NULL,
  yaratuvchi_id INTEGER,
  yaratilgan TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_izoh_tahlil ON izoh(tahlil_id);
CREATE TABLE IF NOT EXISTS nazorat_punkt(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  nomi TEXT NOT NULL,
  x REAL,
  y REAL,
  h REAL,
  sinf TEXT DEFAULT '',
  manba TEXT DEFAULT '',
  holat TEXT NOT NULL DEFAULT 'amal',
  yaratuvchi_id INTEGER,
  yaratilgan TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_npunkt_obyekt ON nazorat_punkt(obyekt_id);
CREATE TABLE IF NOT EXISTS nazorat_olchov(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  punkt_id INTEGER NOT NULL REFERENCES nazorat_punkt(id),
  maqsad TEXT NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  h REAL,
  sigma_h_sm REAL,
  sigma_v_sm REAL,
  epoxalar INTEGER,
  davomiylik_s REAL,
  rtk_holat TEXT NOT NULL,
  antenna_m REAL,
  vaqt TEXT,
  manba TEXT DEFAULT 'rtk',
  holat TEXT NOT NULL DEFAULT 'amal',
  dala_token_id INTEGER,
  yaratuvchi_id INTEGER,
  yaratilgan TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_nolchov_obyekt ON nazorat_olchov(obyekt_id);
CREATE TABLE IF NOT EXISTS tasdiq(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  liniya_id INTEGER REFERENCES liniya(id),
  nomi TEXT DEFAULT '',
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  h REAL,
  sigma_h_sm REAL,
  sigma_v_sm REAL,
  epoxalar INTEGER,
  davomiylik_s REAL,
  rtk_holat TEXT NOT NULL,
  tuzatma_yoshi_s REAL,
  antenna_m REAL,
  vaqt TEXT,
  joy TEXT NOT NULL DEFAULT 'usti',
  manba TEXT DEFAULT 'rtk',
  holat TEXT NOT NULL DEFAULT 'amal',
  dala_token_id INTEGER,
  yaratuvchi_id INTEGER,
  yaratilgan TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tasdiq_obyekt ON tasdiq(obyekt_id);
CREATE TABLE IF NOT EXISTS lokalizatsiya(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  tizim_nomi TEXT NOT NULL,
  natija TEXT NOT NULL,
  olchovlar TEXT NOT NULL,
  holat TEXT NOT NULL DEFAULT 'amal',
  yaratuvchi_id INTEGER,
  yaratilgan TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_lok_obyekt ON lokalizatsiya(obyekt_id);
CREATE TABLE IF NOT EXISTS topo_asos(
  id INTEGER PRIMARY KEY,
  obyekt_id INTEGER NOT NULL REFERENCES obyekt(id),
  fayl_nomi TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  hajmi INTEGER NOT NULL,
  chiziq_soni INTEGER,
  matn_soni INTEGER,
  holat TEXT NOT NULL DEFAULT 'amal',
  yaratuvchi_id INTEGER,
  yaratilgan TEXT NOT NULL
);
"""

# Eski bazani yangi sxemaga keltirish: (jadval, ustun, turi)
_YANGI_USTUNLAR = (
    ("obyekt", "dala_token_id", "INTEGER"),
    ("liniya", "dala_token_id", "INTEGER"),
    ("nuqta", "qurilma_seriya", "TEXT"),
    ("nuqta", "tuzatma_manbai", "TEXT"),
    ("nuqta", "tuzatma_yoshi_s", "REAL"),
    ("nuqta", "antenna_balandligi_m", "REAL"),
    ("nuqta", "qiyshayish_deg", "REAL"),
    ("nuqta", "sigma_h_sm", "REAL"),
    ("nuqta", "sigma_v_sm", "REAL"),
    ("nuqta", "sputnik_soni", "INTEGER"),
    ("nuqta", "sifat", "TEXT DEFAULT 'PAST'"),
    ("nuqta", "manba", "TEXT DEFAULT 'rtk'"),
    ("loyiha", "koordinata", "TEXT DEFAULT 'utm'"),
    # LD-02: tashqi LiDAR importi — muhrsiz tahlil ishi
    ("tahlil_ish", "tur", "TEXT DEFAULT 'muhr'"),
    ("tahlil_ish", "manba_nomi", "TEXT DEFAULT ''"),
    ("tahlil_ish", "aniqlik_sm", "REAL"),
    ("tahlil_ish", "koordinata", "TEXT"),
    ("tahlil_ish", "zona", "INTEGER"),
    ("tahlil_ish", "tarmoq_turi", "TEXT"),
    ("tahlil_ish", "yaratuvchi_id", "INTEGER"),
    ("tahlil_ish", "liniya_idlar", "TEXT"),
    ("tahlil_ish", "farq_a_id", "INTEGER"),
    ("tahlil_ish", "farq_b_id", "INTEGER"),
    # KU-02 (MUDDI / NUAR / PAS 128): tarmoq egasi, ishlash holati, o'rnatilgan yil, ish parametri (bosim, kuchlanish)
    ("liniya", "egasi", "TEXT DEFAULT ''"),
    ("liniya", "ishlash_holati", "TEXT DEFAULT 'ishlayapti'"),
    ("liniya", "ornatilgan_yil", "INTEGER"),
    ("liniya", "parametr", "TEXT DEFAULT ''"),
    ("obyekt", "tarmoq_egasi", "TEXT DEFAULT ''"),
    ("obyekt", "order_sana", "TEXT DEFAULT ''"),   # ShN-01: ShNK 3.01.03-24, 420-band
    ("hujjat", "tur", "TEXT DEFAULT 'ijro'"),       # ShN-05: 'ijro' — ijro s'yomkasi, 'yopiq' — yopiq ishlar dalolatnomasi
)
ISHLASH_HOLATLARI = ("loyiha", "qurilmoqda", "ishlayapti", "ishlamayapti", "tark_etilgan", "olib_tashlangan")  # MUDDI lifecycle
_OCHIRILADIGAN_USTUNLAR = (("obyekt", "demo"), ("liniya", "demo"))


def hozir():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def ulan():
    u = sqlite3.connect(BAZA_YOL)
    u.row_factory = sqlite3.Row
    u.execute("PRAGMA foreign_keys=ON")
    return u


def _ustunlar(u, jadval):
    return {r["name"] for r in u.execute(f"PRAGMA table_info({jadval})")}


def init():
    os.makedirs(SKAN_PAPKA, exist_ok=True)
    u = ulan()
    u.execute("PRAGMA journal_mode=WAL")
    u.executescript(SCHEMA)
    for jadval, ustun, turi in _YANGI_USTUNLAR:
        if ustun not in _ustunlar(u, jadval):
            u.execute(f"ALTER TABLE {jadval} ADD COLUMN {ustun} {turi}")
    for jadval, ustun in _OCHIRILADIGAN_USTUNLAR:
        if ustun in _ustunlar(u, jadval):
            u.execute(f"ALTER TABLE {jadval} DROP COLUMN {ustun}")
    u.commit()
    _tahlil_ish_migratsiya(u)
    u.close()


def _tahlil_ish_migratsiya(u):
    """LD-02/KU-04: eski bazada tahlil_ish.muhr_id va jurnal_skan_id NOT NULL — tashqi LiDAR (muhrsiz) va farq ishlari uchun
    NULL bo'lishi kerak. SQLite ustun cheklovini o'zgartirmaydi: jadval PRAGMA dagi MAVJUD ustunlari bilan (keyin qo'shilgan
    farq_a_id kabi ustunlar ham) qayta yasaladi; FK tekshiruvi vaqtincha o'chiriladi, bitta tranzaksiya, indekslar sqlite_master dan."""
    ustunlar = list(u.execute("PRAGMA table_info(tahlil_ish)"))
    notnull = {r[1]: r[3] for r in ustunlar}
    if not notnull.get("muhr_id") and not notnull.get("jurnal_skan_id"):
        return
    fk = {r[3]: (r[2], r[4]) for r in u.execute("PRAGMA foreign_key_list(tahlil_ish)")}   # ustun → (jadval, ustun)
    indekslar = [r[0] for r in u.execute(
        "SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name='tahlil_ish' AND sql IS NOT NULL")]
    tarif = []
    for _, nomi, turi, nn, default, pk in ustunlar:
        q = f"{nomi} {turi or 'TEXT'}"
        if pk:
            q += " PRIMARY KEY"
        elif nn and nomi not in ("muhr_id", "jurnal_skan_id"):
            q += " NOT NULL"
        if default is not None:
            q += f" DEFAULT {default}"
        if nomi in fk:
            q += f" REFERENCES {fk[nomi][0]}({fk[nomi][1]})"
        tarif.append(q)
    nomlar = ",".join(r[1] for r in ustunlar)
    u.execute("PRAGMA foreign_keys=OFF")
    try:
        u.execute("BEGIN")
        u.execute("CREATE TABLE tahlil_ish_yangi(" + ", ".join(tarif) + ")")
        u.execute(f"INSERT INTO tahlil_ish_yangi({nomlar}) SELECT {nomlar} FROM tahlil_ish")
        u.execute("DROP TABLE tahlil_ish")
        u.execute("ALTER TABLE tahlil_ish_yangi RENAME TO tahlil_ish")
        for sql in indekslar:
            u.execute(sql)
        u.execute("COMMIT")
    except Exception:
        u.execute("ROLLBACK")
        raise
    finally:
        u.execute("PRAGMA foreign_keys=ON")


# ---------- foydalanuvchi va sessiya ----------

def _parol_hash(parol, tuz_hex):
    return hashlib.pbkdf2_hmac(
        "sha256", parol.encode("utf-8"), bytes.fromhex(tuz_hex), 200_000
    ).hex()


def foydalanuvchi_yarat(login, parol, rol="operator", ism=""):
    if rol not in ROLLAR:
        raise ValueError("rol noto'g'ri")
    tuz = secrets.token_hex(16)
    u = ulan()
    k = u.execute(
        "INSERT INTO foydalanuvchi(login,parol_hash,tuz,rol,ism,yaratilgan)"
        " VALUES(?,?,?,?,?,?)",
        (login, _parol_hash(parol, tuz), tuz, rol, ism, hozir()),
    )
    fid = k.lastrowid
    u.commit()
    u.close()
    return fid


def parol_yangila(login, yangi_parol):
    tuz = secrets.token_hex(16)
    u = ulan()
    n = u.execute(
        "UPDATE foydalanuvchi SET parol_hash=?, tuz=? WHERE login=?",
        (_parol_hash(yangi_parol, tuz), tuz, login),
    ).rowcount
    u.execute("DELETE FROM sessiya WHERE foydalanuvchi_id="
              "(SELECT id FROM foydalanuvchi WHERE login=?)", (login,))
    u.commit()
    u.close()
    return n > 0


def foydalanuvchi_soni():
    u = ulan()
    n = u.execute("SELECT COUNT(*) FROM foydalanuvchi").fetchone()[0]
    u.close()
    return n


def kirish_tekshir(login, parol):
    u = ulan()
    q = u.execute(
        "SELECT * FROM foydalanuvchi WHERE login=? AND faol=1", (login,)
    ).fetchone()
    u.close()
    if not q:
        return None
    if secrets.compare_digest(q["parol_hash"], _parol_hash(parol, q["tuz"])):
        return dict(q)
    return None


def sessiya_och(foydalanuvchi_id):
    token = secrets.token_urlsafe(32)
    th = hashlib.sha256(token.encode()).hexdigest()
    muddati = (
        datetime.now(timezone.utc) + timedelta(hours=SESSIYA_MUDDAT_SOAT)
    ).isoformat(timespec="seconds")
    u = ulan()
    u.execute(
        "INSERT INTO sessiya(foydalanuvchi_id,token_hash,yaratilgan,muddati)"
        " VALUES(?,?,?,?)",
        (foydalanuvchi_id, th, hozir(), muddati),
    )
    u.commit()
    u.close()
    return token


def sessiya_top(token):
    if not token:
        return None
    th = hashlib.sha256(token.encode()).hexdigest()
    u = ulan()
    q = u.execute(
        "SELECT s.muddati, f.id, f.login, f.rol, f.ism FROM sessiya s"
        " JOIN foydalanuvchi f ON f.id=s.foydalanuvchi_id"
        " WHERE s.token_hash=? AND f.faol=1",
        (th,),
    ).fetchone()
    u.close()
    if not q or q["muddati"] < hozir():
        return None
    return {"id": q["id"], "login": q["login"], "rol": q["rol"], "ism": q["ism"],
            "token_id": None}


def sessiya_yop(token):
    if not token:
        return
    th = hashlib.sha256(token.encode()).hexdigest()
    u = ulan()
    u.execute("DELETE FROM sessiya WHERE token_hash=?", (th,))
    u.commit()
    u.close()


# ---------- dala tokenlari (iPhone ilovasi uchun, T-115) ----------

def dala_token_yarat(nomi, qurilma, yaratuvchi_id):
    token = "YRD." + secrets.token_urlsafe(32)
    th = hashlib.sha256(token.encode()).hexdigest()
    u = ulan()
    k = u.execute(
        "INSERT INTO dala_token(nomi,qurilma,token_hash,yaratilgan,yaratuvchi_id)"
        " VALUES(?,?,?,?,?)",
        (nomi, qurilma, th, hozir(), yaratuvchi_id),
    )
    tid = k.lastrowid
    u.commit()
    u.close()
    return tid, token


def dala_token_top(token):
    if not token or not token.startswith("YRD."):
        return None
    th = hashlib.sha256(token.encode()).hexdigest()
    u = ulan()
    q = u.execute(
        "SELECT id, nomi, qurilma FROM dala_token WHERE token_hash=? AND faol=1",
        (th,),
    ).fetchone()
    if q:
        u.execute("UPDATE dala_token SET oxirgi_ishlatilgan=? WHERE id=?",
                  (hozir(), q["id"]))
        u.commit()
    u.close()
    return dict(q) if q else None


def dala_token_bekor(token_id):
    u = ulan()
    n = u.execute("UPDATE dala_token SET faol=0 WHERE id=?", (token_id,)).rowcount
    u.commit()
    u.close()
    return n > 0


def dala_tokenlar():
    u = ulan()
    q = u.execute(
        "SELECT id,nomi,qurilma,faol,yaratilgan,oxirgi_ishlatilgan FROM dala_token"
        " ORDER BY id DESC"
    ).fetchall()
    u.close()
    return [dict(r) for r in q]


def jurnal_yoz(foydalanuvchi_id, amal, tafsilot=""):
    u = ulan()
    u.execute(
        "INSERT INTO jurnal(vaqt,foydalanuvchi_id,amal,tafsilot) VALUES(?,?,?,?)",
        (hozir(), foydalanuvchi_id, amal, tafsilot),
    )
    u.commit()
    u.close()


# ---------- obyekt va liniya ----------

def sana_tekshir(s):
    """ShN-01: ISO sana (YYYY-MM-DD) yoki bo'sh; aks holda ValueError."""
    s = str(s or "").strip()
    if not s:
        return ""
    try:
        return datetime.strptime(s, "%Y-%m-%d").date().isoformat()
    except ValueError:
        raise ValueError("sana YYYY-MM-DD shaklida bo'lsin") from None


def obyekt_yarat(nomi, manzil="", buyurtmachi="", pudratchi="", order_raqami="",
                 yaratuvchi_id=None, dala_token_id=None, order_sana=""):
    order_sana = sana_tekshir(order_sana)
    u = ulan()
    k = u.execute(
        "INSERT INTO obyekt(nomi,manzil,buyurtmachi,pudratchi,order_raqami,order_sana,"
        "yaratilgan,yaratuvchi_id,dala_token_id) VALUES(?,?,?,?,?,?,?,?,?)",
        (nomi, manzil, buyurtmachi, pudratchi, order_raqami, order_sana, hozir(),
         yaratuvchi_id, dala_token_id),
    )
    oid = k.lastrowid
    u.commit()
    u.close()
    return oid


def obyektlar(qidiruv=""):
    u = ulan()
    if qidiruv:
        s = f"%{qidiruv}%"
        q = u.execute(
            "SELECT * FROM obyekt WHERE nomi LIKE ? OR pudratchi LIKE ?"
            " OR order_raqami LIKE ? ORDER BY id DESC",
            (s, s, s),
        ).fetchall()
    else:
        q = u.execute("SELECT * FROM obyekt ORDER BY id DESC").fetchall()
    u.close()
    return [dict(r) for r in q]


def obyekt_top(obyekt_id):
    u = ulan()
    q = u.execute("SELECT * FROM obyekt WHERE id=?", (obyekt_id,)).fetchone()
    u.close()
    return dict(q) if q else None


def _son(x):
    return None if x is None or x == "" else float(x)


def liniya_yarat(obyekt_id, turi, nuqtalar, material="", diametr_mm=0, izoh="",
                 yaratuvchi_id=None, dala_token_id=None):
    """nuqtalar: [{lat, lon, chuqurlik_m, rtk_holat, sigma_h_sm, sigma_v_sm,
    tuzatma_yoshi_s, tuzatma_manbai, qurilma_seriya, antenna_balandligi_m,
    qiyshayish_deg, sputnik_soni, balandlik, aniqlik_sm, izoh, vaqt}]"""
    if turi not in TARMOQ_TURLARI:
        raise ValueError("tarmoq turi noto'g'ri")
    if len(nuqtalar) < 2:
        raise ValueError("kamida 2 nuqta kerak")
    if not obyekt_top(obyekt_id):
        raise ValueError("obyekt topilmadi")
    tayyor = []
    for n in nuqtalar:
        lat, lon = float(n["lat"]), float(n["lon"])
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError("koordinata chegaradan tashqarida")
        rtk = n.get("rtk_holat", "YOQ")
        if rtk not in RTK_HOLATLAR:
            raise ValueError("rtk_holat noto'g'ri")
        manba = n.get("manba", "rtk")
        if manba not in NUQTA_MANBALARI:
            raise ValueError("manba noto'g'ri")
        sh, sv, ty = _son(n.get("sigma_h_sm")), _son(n.get("sigma_v_sm")), \
            _son(n.get("tuzatma_yoshi_s"))
        tayyor.append((
            lat, lon, _son(n.get("balandlik")), _son(n.get("chuqurlik_m")), rtk,
            _son(n.get("aniqlik_sm")), str(n.get("izoh", ""))[:300],
            n.get("vaqt") or hozir(), str(n.get("qurilma_seriya", ""))[:64],
            str(n.get("tuzatma_manbai", ""))[:120], ty,
            _son(n.get("antenna_balandligi_m")), _son(n.get("qiyshayish_deg")),
            int(n["sputnik_soni"]) if n.get("sputnik_soni") not in (None, "") else None,
            sh, sv, "SKAN" if manba == "skan" else sifat_hisobla(rtk, sh, sv, ty), manba,
        ))
    u = ulan()
    k = u.execute(
        "INSERT INTO liniya(obyekt_id,turi,material,diametr_mm,izoh,"
        "yaratilgan,yaratuvchi_id,dala_token_id) VALUES(?,?,?,?,?,?,?,?)",
        (obyekt_id, turi, material, int(diametr_mm), izoh, hozir(),
         yaratuvchi_id, dala_token_id),
    )
    lid = k.lastrowid
    for i, t in enumerate(tayyor):
        u.execute(
            "INSERT INTO nuqta(liniya_id,tartib,lat,lon,balandlik,chuqurlik_m,"
            "rtk_holat,aniqlik_sm,izoh,vaqt,qurilma_seriya,tuzatma_manbai,"
            "tuzatma_yoshi_s,antenna_balandligi_m,qiyshayish_deg,sputnik_soni,"
            "sigma_h_sm,sigma_v_sm,sifat,manba)"
            " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (lid, i) + t,
        )
    u.commit()
    u.close()
    return lid


# ---------- skan fayllari (bo'lakli yuklash, T-112/T-114) ----------

def skan_boshla(obyekt_id, turi, hajmi, sha256, liniya_id=None, rms_sm=None,
                markerlar=None, meta=None, yaratuvchi_id=None, dala_token_id=None):
    if turi not in SKAN_TURLARI:
        raise ValueError("skan turi noto'g'ri")
    hajmi = int(hajmi)
    if hajmi <= 0 or hajmi > SKAN_CHEK_BAYT:
        raise ValueError(f"hajm 1..{SKAN_CHEK_BAYT} bayt oralig'ida bo'lsin")
    sha256 = str(sha256).lower()
    if len(sha256) != 64 or any(c not in "0123456789abcdef" for c in sha256):
        raise ValueError("sha256 noto'g'ri")
    if not obyekt_top(obyekt_id):
        raise ValueError("obyekt topilmadi")
    bolak_soni = math.ceil(hajmi / BOLAK_HAJMI)
    u = ulan()
    k = u.execute(
        "INSERT INTO skan(obyekt_id,liniya_id,turi,hajmi,sha256,bolak_soni,"
        "rms_sm,markerlar,meta,yaratilgan,yaratuvchi_id,dala_token_id)"
        " VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
        (obyekt_id, liniya_id, turi, hajmi, sha256, bolak_soni, _son(rms_sm),
         json.dumps(markerlar, ensure_ascii=False) if markerlar is not None else None,
         json.dumps(meta, ensure_ascii=False) if meta is not None else None,
         hozir(), yaratuvchi_id, dala_token_id),
    )
    sid = k.lastrowid
    yol = f"{sid}.{SKAN_KENGAYTMA[turi]}"
    u.execute("UPDATE skan SET fayl_yol=? WHERE id=?", (yol, sid))
    u.commit()
    u.close()
    return {"skan_id": sid, "bolak_hajmi": BOLAK_HAJMI, "bolak_soni": bolak_soni}


def skan_top(skan_id):
    u = ulan()
    q = u.execute("SELECT * FROM skan WHERE id=?", (skan_id,)).fetchone()
    u.close()
    return dict(q) if q else None


def skan_bolak_yoz(skan_id, n, data, bolak_sha256):
    """Ketma-ket bo'laklar; takror bo'lak jimgina qabul (idempotent)."""
    s = skan_top(skan_id)
    if not s:
        raise ValueError("skan topilmadi")
    if s["holat"] != "yuklanmoqda":
        raise ValueError(f"skan holati: {s['holat']}")
    if n < s["qabul_bolaklar"]:
        return {"holat": "takror", "qabul_bolaklar": s["qabul_bolaklar"]}
    if n != s["qabul_bolaklar"]:
        raise ValueError(f"tartib buzildi: kutilgan {s['qabul_bolaklar']}, kelgan {n}")
    if n >= s["bolak_soni"]:
        raise ValueError("bo'lak raqami chegaradan tashqarida")
    oxirgi = n == s["bolak_soni"] - 1
    kutilgan = (s["hajmi"] - n * BOLAK_HAJMI) if oxirgi else BOLAK_HAJMI
    if len(data) != kutilgan:
        raise ValueError(f"bo'lak hajmi {len(data)}, kutilgan {kutilgan}")
    if hashlib.sha256(data).hexdigest() != str(bolak_sha256).lower():
        raise ValueError("bo'lak sha256 mos kelmadi")
    yol = os.path.join(SKAN_PAPKA, s["fayl_yol"])
    with open(yol, "ab" if n == 0 else "r+b") as f:
        f.seek(n * BOLAK_HAJMI)
        f.write(data)
    u = ulan()
    u.execute("UPDATE skan SET qabul_bolaklar=? WHERE id=?", (n + 1, skan_id))
    u.commit()
    u.close()
    return {"holat": "qabul", "qabul_bolaklar": n + 1}


def skan_yakunla(skan_id):
    s = skan_top(skan_id)
    if not s:
        raise ValueError("skan topilmadi")
    if s["holat"] == "tayyor":
        return s
    if s["qabul_bolaklar"] != s["bolak_soni"]:
        # Muddatidan oldin yakunlash yuklashni O'LDIRMAYDI — holat saqlanadi
        return dict(s, xato=f"bo'laklar to'liq emas: {s['qabul_bolaklar']}/{s['bolak_soni']}")
    xato = ""
    if True:
        yol = os.path.join(SKAN_PAPKA, s["fayl_yol"])
        h = hashlib.sha256()
        hajm = 0
        with open(yol, "rb") as f:
            while True:
                b = f.read(1024 * 1024)
                if not b:
                    break
                h.update(b)
                hajm += len(b)
        if hajm != s["hajmi"]:
            xato = f"fayl hajmi {hajm}, kutilgan {s['hajmi']}"
        elif h.hexdigest() != s["sha256"]:
            xato = "fayl sha256 mos kelmadi"
    u = ulan()
    if xato:
        u.execute("UPDATE skan SET holat='xato', xato=? WHERE id=?", (xato, skan_id))
    else:
        u.execute("UPDATE skan SET holat='tayyor', yakunlangan=? WHERE id=?",
                  (hozir(), skan_id))
    u.commit()
    u.close()
    return skan_top(skan_id)


def skanlar(obyekt_id=None):
    u = ulan()
    if obyekt_id is not None:
        q = u.execute("SELECT * FROM skan WHERE obyekt_id=? ORDER BY id DESC",
                      (obyekt_id,)).fetchall()
    else:
        q = u.execute("SELECT * FROM skan ORDER BY id DESC").fetchall()
    u.close()
    return [dict(r) for r in q]


# ---------- geometriya ----------

def masofa_m(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def _tekislikka(nuqtalar, lat0, lon0):
    # Shahar masshtabida mahalliy tekis proyeksiya yetarli (xato <0.1%).
    kx = 111320.0 * math.cos(math.radians(lat0))
    ky = 110540.0
    return [((lon - lon0) * kx, (lat - lat0) * ky) for lat, lon in nuqtalar]


def _nuqta_poligonda(p, poligon):
    x, y = p
    ichida = False
    j = len(poligon) - 1
    for i in range(len(poligon)):
        xi, yi = poligon[i]
        xj, yj = poligon[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            ichida = not ichida
        j = i
    return ichida


def _kesishadi(a, b, c, d):
    def yon(p, q, r):
        v = (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
        return 0 if abs(v) < 1e-12 else (1 if v > 0 else -1)
    return (yon(a, b, c) != yon(a, b, d)) and (yon(c, d, a) != yon(c, d, b))


def obyekt_yangila(obyekt_id, maydonlar):
    """ShN-01: obyekt rekvizitlari (nomi, manzil, buyurtmachi, pudratchi, order raqami va sanasi, tarmoq egasi).
    Geometriya va holat bu yerda o'zgarmaydi. Noma'lum maydon xato."""
    ruxsat = {"nomi": lambda v: str(v or "").strip()[:200], "manzil": lambda v: str(v or "")[:300],
              "buyurtmachi": lambda v: str(v or "")[:200], "pudratchi": lambda v: str(v or "")[:200],
              "order_raqami": lambda v: str(v or "").strip()[:64], "order_sana": sana_tekshir,
              "tarmoq_egasi": lambda v: str(v or "")[:120]}
    if not isinstance(maydonlar, dict):
        raise ValueError("tana JSON obyekt bo'lsin")
    yangi = {}
    for k, v in maydonlar.items():
        if k not in ruxsat:
            raise ValueError(f"maydon o'zgartirilmaydi: {k}")
        yangi[k] = ruxsat[k](v)
    if "nomi" in yangi and not yangi["nomi"]:
        raise ValueError("nomi bo'sh bo'lmasin")
    if not yangi:
        raise ValueError("o'zgartiriladigan maydon yo'q")
    u = ulan()
    if not u.execute("SELECT id FROM obyekt WHERE id=?", (obyekt_id,)).fetchone():
        u.close()
        raise ValueError("obyekt topilmadi")
    u.execute("UPDATE obyekt SET " + ", ".join(f"{k}=?" for k in yangi) + " WHERE id=?", (*yangi.values(), obyekt_id))
    u.commit()
    u.close()
    return yangi


def liniya_yangila(liniya_id, maydonlar):
    """KU-02: liniyaning tavsif atributlarini yangilash (geometriya emas): material, diametr_mm, izoh, egasi, ishlash_holati,
    ornatilgan_yil, parametr. Noma'lum maydon xato."""
    ruxsat = {"material": lambda v: str(v or "")[:100], "diametr_mm": lambda v: int(v or 0), "izoh": lambda v: str(v or "")[:500],
              "egasi": lambda v: str(v or "")[:120], "parametr": lambda v: str(v or "")[:60],
              "ornatilgan_yil": lambda v: None if v in (None, "") else int(v),
              "ishlash_holati": lambda v: str(v)}
    yangi = {}
    for k, v in (maydonlar or {}).items():
        if k not in ruxsat:
            raise ValueError(f"maydon o'zgartirilmaydi: {k}")
        yangi[k] = ruxsat[k](v)
    if "ishlash_holati" in yangi and yangi["ishlash_holati"] not in ISHLASH_HOLATLARI:
        raise ValueError("ishlash_holati: " + ", ".join(ISHLASH_HOLATLARI))
    if "ornatilgan_yil" in yangi and yangi["ornatilgan_yil"] is not None and not (1900 <= yangi["ornatilgan_yil"] <= 2100):
        raise ValueError("o'rnatilgan yil 1900…2100")
    if "diametr_mm" in yangi and not (0 <= yangi["diametr_mm"] <= 5000):
        raise ValueError("diametr 0…5000 mm")
    if not yangi:
        raise ValueError("o'zgartiriladigan maydon yo'q")
    u = ulan()
    bor = u.execute("SELECT id FROM liniya WHERE id=? AND holat='amal'", (liniya_id,)).fetchone()
    if not bor:
        u.close()
        raise ValueError("liniya topilmadi")
    u.execute("UPDATE liniya SET " + ", ".join(f"{k}=?" for k in yangi) + " WHERE id=?", (*yangi.values(), liniya_id))
    u.commit()
    u.close()
    return yangi


def tarmoq_grafi(liniyalar, tutashuv_m=0.05):
    """KU-03: liniyalardan topologiya — tugunlar (uchlar 5 sm ichida birlashadi) va qirralar. Tugun turi: uch (1 qirra),
    tutashuv (2), tarmoqlanish (≥ 3). Hisoblangan ko'rinish, saqlanmaydi."""
    import math
    tugunlar = []

    def tugun(lat, lon, h):
        for t in tugunlar:
            d = math.hypot((t["lat"] - lat) * 110_574, (t["lon"] - lon) * 111_320 * math.cos(math.radians(lat)))
            if d <= tutashuv_m:
                t["liniyalar"].append(None)
                return t
        t = {"id": len(tugunlar) + 1, "lat": lat, "lon": lon, "h": h, "liniyalar": [None]}
        tugunlar.append(t)
        return t

    qirralar = []
    for l in liniyalar:
        nq = l["nuqtalar"]
        if len(nq) < 2:
            continue
        a, b = tugun(nq[0]["lat"], nq[0]["lon"], nq[0].get("balandlik")), tugun(nq[-1]["lat"], nq[-1]["lon"], nq[-1].get("balandlik"))
        a["liniyalar"][-1] = l["id"]
        b["liniyalar"][-1] = l["id"]
        qirralar.append({"liniya_id": l["id"], "turi": l["turi"], "bosh": a["id"], "oxir": b["id"], "uzunlik_m": l.get("uzunlik_m")})
    for t in tugunlar:
        t["liniyalar"] = [x for x in t["liniyalar"] if x is not None]
        d = len(t["liniyalar"])
        t["daraja"] = d
        t["turi"] = "uch" if d == 1 else "tutashuv" if d == 2 else "tarmoqlanish"
        turlar = {l["turi"] for l in liniyalar if l["id"] in t["liniyalar"]}
        if d >= 2 and len(turlar) > 1:
            t["turi"] = "turli_tarmoq_tutashuvi"
    return {"tugunlar": tugunlar, "qirralar": qirralar,
            "xulosa": {"tugun": len(tugunlar), "uch": sum(1 for t in tugunlar if t["turi"] == "uch"),
                       "tutashuv": sum(1 for t in tugunlar if t["turi"] == "tutashuv"),
                       "tarmoqlanish": sum(1 for t in tugunlar if t["turi"] == "tarmoqlanish"),
                       "turli_tarmoq_tutashuvi": sum(1 for t in tugunlar if t["turi"] == "turli_tarmoq_tutashuvi")}}


def liniya_poligonni_kesadimi(liniya_latlon, poligon_latlon):
    lat0 = sum(p[0] for p in poligon_latlon) / len(poligon_latlon)
    lon0 = sum(p[1] for p in poligon_latlon) / len(poligon_latlon)
    chiz = _tekislikka(liniya_latlon, lat0, lon0)
    pol = _tekislikka(poligon_latlon, lat0, lon0)
    for p in chiz:
        if _nuqta_poligonda(p, pol):
            return True
    for i in range(len(chiz) - 1):
        for j in range(len(pol)):
            if _kesishadi(chiz[i], chiz[i + 1], pol[j], pol[(j + 1) % len(pol)]):
                return True
    return False


# ---------- chiqarish ----------

_RTK_DARAJA = {"FIX": 0, "FLOAT": 1, "DGPS": 2, "GPS": 3, "YOQ": 4}


def _liniya_tafsilot(u, liniya_qator):
    r = dict(liniya_qator)
    nq = u.execute(
        "SELECT * FROM nuqta WHERE liniya_id=? ORDER BY tartib", (r["id"],)
    ).fetchall()
    koordlar = [(n["lat"], n["lon"]) for n in nq]
    uz = sum(
        masofa_m(*koordlar[i], *koordlar[i + 1]) for i in range(len(koordlar) - 1)
    )
    chuqurliklar = [n["chuqurlik_m"] for n in nq if n["chuqurlik_m"] is not None]
    r["nuqtalar"] = [dict(n) for n in nq]
    r["uzunlik_m"] = round(uz, 1)
    r["chuqurlik_min"] = round(min(chuqurliklar), 2) if chuqurliklar else None
    r["chuqurlik_max"] = round(max(chuqurliklar), 2) if chuqurliklar else None
    r["rtk_eng_yomon"] = max((n["rtk_holat"] for n in nq),
                             key=lambda h: _RTK_DARAJA.get(h, 4), default="YOQ")
    sifatlar = {n["sifat"] for n in nq}
    r["sifat"] = ("PAST" if (not nq or "PAST" in sifatlar) else "SKAN" if "SKAN" in sifatlar else "RASMIY")
    return r


def liniyalar_toliq(faqat_amal=True, obyekt_id=None, idlar=None):
    u = ulan()
    shartlar, qiymatlar = [], []
    if faqat_amal:
        shartlar.append("l.holat='amal'")
    if obyekt_id is not None:
        shartlar.append("l.obyekt_id=?")
        qiymatlar.append(obyekt_id)
    if idlar is not None:
        if not idlar:
            u.close()
            return []
        shartlar.append("l.id IN (%s)" % ",".join("?" * len(idlar)))
        qiymatlar.extend(int(i) for i in idlar)
    sh = ("WHERE " + " AND ".join(shartlar)) if shartlar else ""
    q = u.execute(
        f"SELECT l.*, o.nomi AS obyekt_nomi, o.pudratchi, o.order_raqami, o.order_sana, o.tarmoq_egasi AS obyekt_egasi"
        f" FROM liniya l JOIN obyekt o ON o.id=l.obyekt_id {sh} ORDER BY l.id",
        qiymatlar,
    ).fetchall()
    natija = [_liniya_tafsilot(u, r) for r in q]
    u.close()
    return natija


def _chuqurlik_matn(r):
    if r["chuqurlik_min"] is None:
        return ""
    if abs(r["chuqurlik_max"] - r["chuqurlik_min"]) < 0.15:
        return f"{r['chuqurlik_min']:.1f} m"
    return f"{r['chuqurlik_min']:.1f}–{r['chuqurlik_max']:.1f} m"


def geojson():
    xususiyatlar = []
    qatorlar = liniyalar_toliq()
    tasdiq = tasdiq_liniya_holatlari(qatorlar)
    for r in qatorlar:
        xususiyatlar.append({
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": [[n["lon"], n["lat"]] for n in r["nuqtalar"]],
            },
            "properties": {
                "id": r["id"],
                "obyekt_id": r["obyekt_id"],
                "obyekt_nomi": r["obyekt_nomi"],
                "pudratchi": r["pudratchi"],
                "order_raqami": r["order_raqami"],
                "order_sana": r["order_sana"],
                "turi": r["turi"],
                "material": r["material"],
                "diametr_mm": r["diametr_mm"],
                "uzunlik_m": r["uzunlik_m"],
                "nuqta_soni": len(r["nuqtalar"]),
                "chuqurlik_matn": _chuqurlik_matn(r),
                "chuqurlik_min": r["chuqurlik_min"],
                "chuqurlik_max": r["chuqurlik_max"],
                "rtk": r["rtk_eng_yomon"],
                "sifat": r["sifat"],
                "tasdiq": tasdiq.get(r["id"], "yoq"),
                "egasi": r["egasi"] or r["obyekt_egasi"] or "",
                "ishlash_holati": r["ishlash_holati"] or "ishlayapti",
                "ornatilgan_yil": r["ornatilgan_yil"],
                "parametr": r["parametr"] or "",
                "versiya": r["versiya"],
                "yaratilgan": r["yaratilgan"],
                "izoh": r["izoh"],
            },
        })
    return {"type": "FeatureCollection", "features": xususiyatlar}


def statistika():
    tur_stat = {t: {"soni": 0, "uzunlik_m": 0.0} for t in TARMOQ_TURLARI}
    rasmiy = past = skan = 0
    for r in liniyalar_toliq():
        tur_stat[r["turi"]]["soni"] += 1
        tur_stat[r["turi"]]["uzunlik_m"] += r["uzunlik_m"]
        for n in r["nuqtalar"]:
            if n["sifat"] == "RASMIY":
                rasmiy += 1
            elif n["sifat"] == "SKAN":
                skan += 1
            else:
                past += 1
    for t in tur_stat.values():
        t["uzunlik_m"] = round(t["uzunlik_m"], 1)
    u = ulan()
    ob = u.execute("SELECT COUNT(*) FROM obyekt").fetchone()[0]
    sk = u.execute("SELECT COUNT(*) FROM skan WHERE holat='tayyor'").fetchone()[0]
    u.close()
    return {
        "obyekt_soni": ob,
        "skan_soni": sk,
        "turlar": tur_stat,
        "jami_uzunlik_m": round(sum(t["uzunlik_m"] for t in tur_stat.values()), 1),
        "nuqta_rasmiy": rasmiy,
        "nuqta_past": past,
        "nuqta_skan": skan,
    }


def order_tekshir(poligon_latlon):
    """Qazish poligoni bilan kesishadigan amaldagi liniyalar ro'yxati."""
    if len(poligon_latlon) < 3:
        raise ValueError("poligon kamida 3 nuqta")
    topilgan = []
    for r in liniyalar_toliq():
        koordlar = [(n["lat"], n["lon"]) for n in r["nuqtalar"]]
        if liniya_poligonni_kesadimi(koordlar, poligon_latlon):
            topilgan.append({
                "id": r["id"],
                "turi": r["turi"],
                "material": r["material"],
                "diametr_mm": r["diametr_mm"],
                "chuqurlik_min": r["chuqurlik_min"],
                "chuqurlik_max": r["chuqurlik_max"],
                "obyekt_nomi": r["obyekt_nomi"],
                "pudratchi": r["pudratchi"],
                "order_raqami": r["order_raqami"],
                "order_sana": r["order_sana"],
                "rtk": r["rtk_eng_yomon"],
                "sifat": r["sifat"],
            })
    return topilgan


# ---------- qurilma kaliti va muhr (K-05) ----------

def qurilma_kalit_saqla(dala_token_id, ochiq_kalit_hex):
    """Bitta dala tokeniga bitta faol kalit: yangisi eskisini o'chiradi (o'chirilmaydi — tarix)."""
    u = ulan()
    u.execute("UPDATE qurilma_kalit SET faol=0 WHERE dala_token_id=?", (dala_token_id,))
    k = u.execute("INSERT INTO qurilma_kalit(dala_token_id,ochiq_kalit,yaratilgan) VALUES(?,?,?)",
                  (dala_token_id, ochiq_kalit_hex, hozir()))
    kid = k.lastrowid
    u.commit()
    u.close()
    return kid


def qurilma_kalit_top(dala_token_id):
    u = ulan()
    q = u.execute("SELECT * FROM qurilma_kalit WHERE dala_token_id=? AND faol=1 ORDER BY id DESC LIMIT 1",
                  (dala_token_id,)).fetchone()
    u.close()
    return dict(q) if q else None


def skan_xesh_boyicha(obyekt_id, sha256, hajmi):
    u = ulan()
    q = u.execute("SELECT * FROM skan WHERE obyekt_id=? AND sha256=? AND hajmi=? AND holat='tayyor'"
                  " ORDER BY id DESC LIMIT 1", (obyekt_id, str(sha256).lower(), int(hajmi))).fetchone()
    u.close()
    return dict(q) if q else None


def skan_fayl_oqi(skan):
    with open(os.path.join(SKAN_PAPKA, skan["fayl_yol"]), "rb") as f:
        return f.read()


def skan_yoli(skan_id):
    s = skan_top(skan_id)
    return os.path.join(SKAN_PAPKA, s["fayl_yol"]) if s else None


def muhr_saqla(obyekt_id, dala_token_id, qurilma_kalit_id, manifest_matn, imzo_hex, holat, sabab,
               zanjir_boshi, yozuv_soni):
    u = ulan()
    k = u.execute(
        "INSERT INTO muhr(obyekt_id,dala_token_id,qurilma_kalit_id,manifest,imzo,holat,sabab,zanjir_boshi,"
        "yozuv_soni,yaratilgan) VALUES(?,?,?,?,?,?,?,?,?,?)",
        (obyekt_id, dala_token_id, qurilma_kalit_id, manifest_matn, imzo_hex, holat, sabab, zanjir_boshi,
         yozuv_soni, hozir()))
    mid = k.lastrowid
    u.commit()
    u.close()
    return mid


def muhrlar(obyekt_id):
    u = ulan()
    q = u.execute("SELECT id,obyekt_id,dala_token_id,holat,sabab,zanjir_boshi,yozuv_soni,yaratilgan FROM muhr"
                  " WHERE obyekt_id=? ORDER BY id DESC", (obyekt_id,)).fetchall()
    u.close()
    return [dict(r) for r in q]


# ---------- AR ko'rish: atrofdagi tarmoqlar (AR-02, K-09) ----------

ATROF_MAKS_M = 200.0


def atrofdagi(lat, lon, radius_m):
    """Istalgan nuqtasi (lat, lon) dan radius_m ichida bo'lgan barcha amaldagi liniyalar — hamma pudratchilardan.
    Format Swift `GlobalTarmoq` bilan bir xil. `balandlik` — quvur o'qi (markazi) ellipsoid balandligi (AR-08)."""
    radius_m = max(1.0, min(float(radius_m), ATROF_MAKS_M))
    # tez oldindan saralash: kenglik/uzunlik qutisi
    dlat = radius_m / 110_540.0
    dlon = radius_m / (111_320.0 * max(math.cos(math.radians(lat)), 1e-6))
    u = ulan()
    ids = [r[0] for r in u.execute(
        "SELECT DISTINCT n.liniya_id FROM nuqta n JOIN liniya l ON l.id=n.liniya_id"
        " WHERE l.holat='amal' AND n.lat BETWEEN ? AND ? AND n.lon BETWEEN ? AND ?",
        (lat - dlat, lat + dlat, lon - dlon, lon + dlon)).fetchall()]
    u.close()
    natija = []
    for r in liniyalar_toliq(idlar=ids[:500]):
        if not any(masofa_m(lat, lon, n["lat"], n["lon"]) <= radius_m for n in r["nuqtalar"]):
            continue
        sigmalar = [n["sigma_h_sm"] for n in r["nuqtalar"] if n.get("sigma_h_sm") is not None]
        natija.append({
            "id": r["id"], "turi": r["turi"], "diametr_mm": r["diametr_mm"], "material": r["material"],
            "sifat": r["sifat"], "pudratchi": r["pudratchi"],
            # UI-13: AR noaniqlik yo'lagi — liniyaning eng yomon gorizontal σ si (bo'lmasa sifat sinfidan olinadi)
            "sigma_h_sm": max(sigmalar) if sigmalar else None,
            "nuqtalar": [{"lat": n["lat"], "lon": n["lon"], "balandlik": n["balandlik"],
                          "chuqurlik_m": n["chuqurlik_m"]} for n in r["nuqtalar"]],
        })
    return natija


# ---------- DM-02: mustaqil qayta hisob navbati ----------
# holat: kutmoqda → ishlanmoqda → tayyor | xato. xulosa: CLI natijasi (MOS / FARQ / XATO).
TAHLIL_URINISH_MAKS = 3


def tahlil_papka(ish_id):
    return os.path.join(SKAN_PAPKA, "tahlil", str(int(ish_id)))


def tahlil_navbatga(muhr_id, obyekt_id, jurnal_skan_id, ply_skan_id):
    u = ulan()
    k = u.execute("INSERT INTO tahlil_ish(muhr_id,obyekt_id,jurnal_skan_id,ply_skan_id,yaratilgan) VALUES(?,?,?,?,?)",
                  (muhr_id, obyekt_id, jurnal_skan_id, ply_skan_id, hozir()))
    tid = k.lastrowid
    u.commit()
    u.close()
    return tid


def skan_ichki_yarat(obyekt_id, turi, data, meta=None, yaratuvchi_id=None):
    """Server o'zi yasagan fayl (masalan LAS dan PLY) — skan jadvaliga tayyor holatda yoziladi."""
    if turi not in SKAN_TURLARI:
        raise ValueError("skan turi noto'g'ri")
    sha = hashlib.sha256(data).hexdigest()
    u = ulan()
    k = u.execute("INSERT INTO skan(obyekt_id,turi,hajmi,sha256,bolak_soni,qabul_bolaklar,holat,meta,yaratilgan,yakunlangan,"
                  "yaratuvchi_id) VALUES(?,?,?,?,1,1,'tayyor',?,?,?,?)",
                  (obyekt_id, turi, len(data), sha, json.dumps(meta, ensure_ascii=False) if meta is not None else None,
                   hozir(), hozir(), yaratuvchi_id))
    sid = k.lastrowid
    yol = f"{sid}.{SKAN_KENGAYTMA[turi]}"
    with open(os.path.join(SKAN_PAPKA, yol), "wb") as f:
        f.write(data)
    u.execute("UPDATE skan SET fayl_yol=? WHERE id=?", (yol, sid))
    u.commit()
    u.close()
    return sid


def tashqi_navbatga(obyekt_id, skan_id, koordinata, zona, manba_nomi, aniqlik_sm, tarmoq_turi, yaratuvchi_id=None):
    """LD-02: tashqi LiDAR fayli (LAS/PLY, skan jadvalida 'tayyor') uchun muhrsiz tahlil ishi. Ishchi faylni UTM PLY ga
    keltiradi, quvurlarni topadi va SKAN liniyalar yaratadi."""
    import yerosti_las as las
    s = skan_top(skan_id)
    if not s or s["obyekt_id"] != obyekt_id:
        raise ValueError("skan topilmadi yoki boshqa obyektniki")
    if s["turi"] not in ("nuqta_las", "nuqta_ply"):
        raise ValueError("fayl turi nuqta_las yoki nuqta_ply bo'lsin")
    if s["holat"] != "tayyor":
        raise ValueError(f"fayl hali yuklanmagan: {s['holat']}")
    if koordinata not in las.KOORDINATA_TIZIMLARI:
        raise ValueError("koordinata: utm, wgs84 yoki mahalliy")
    if koordinata == "utm" and not (zona and 1 <= int(zona) <= 60):
        raise ValueError("UTM zonasi 1…60 kerak")
    if koordinata == "mahalliy":
        lq = lokalizatsiya_top(obyekt_id)
        if not (lq and lq["natija"]["parametrlar"].get("gor")):
            raise ValueError("mahalliy koordinata uchun avval obyekt lokalizatsiyasi kerak (LK)")
    if tarmoq_turi not in TARMOQ_TURLARI:
        raise ValueError("tarmoq turi noto'g'ri")
    a = _son_yoki_none(aniqlik_sm, "aniqlik")
    if a is None or a <= 0 or a > 50:
        raise ValueError("skanerning e'lon qilingan aniqligi kerak (sm, 0 < a ≤ 50)")
    u = ulan()
    k = u.execute("INSERT INTO tahlil_ish(muhr_id,obyekt_id,jurnal_skan_id,ply_skan_id,yaratilgan,tur,manba_nomi,aniqlik_sm,"
                  "koordinata,zona,tarmoq_turi,yaratuvchi_id) VALUES(NULL,?,NULL,?,?,'tashqi',?,?,?,?,?,?)",
                  (obyekt_id, skan_id, hozir(), str(manba_nomi or "")[:120], a, koordinata,
                   int(zona) if zona else None, tarmoq_turi, yaratuvchi_id))
    tid = k.lastrowid
    u.commit()
    u.close()
    return tid


def farq_navbatga(obyekt_id, a_id, b_id, yaratuvchi_id=None):
    """KU-04: ikki tayyor tahlil (ko'rinish buluti bor) orasidagi M3C2 farqi uchun ish."""
    a, b = tahlil_top(a_id), tahlil_top(b_id)
    for t in (a, b):
        if not t or t["obyekt_id"] != obyekt_id:
            raise ValueError("tahlil topilmadi yoki boshqa obyektniki")
        if t["holat"] != "tayyor" or not t.get("korinish"):
            raise ValueError(f"tahlil #{t['id']} tayyor emas yoki ko'rinish buluti yo'q")
        if not ((t.get("natija") or {}).get("georef") or {}).get("server"):
            raise ValueError(f"tahlil #{t['id']} da georeferens yo'q — ikki skan bir ramkaga keltirilmaydi")
    if a_id == b_id:
        raise ValueError("ikki xil tahlil kerak")
    u = ulan()
    k = u.execute("INSERT INTO tahlil_ish(muhr_id,obyekt_id,jurnal_skan_id,ply_skan_id,yaratilgan,tur,farq_a_id,farq_b_id,yaratuvchi_id)"
                  " VALUES(NULL,?,NULL,?,?,'farq',?,?,?)",
                  (obyekt_id, a["ply_skan_id"], hozir(), a_id, b_id, yaratuvchi_id))
    tid = k.lastrowid
    u.commit()
    u.close()
    return tid


def tashqi_liniyalar_yarat(ish, natija):
    """Tashqi tahlil natijasidagi quvurlar → SKAN liniyalar (manba skan, σ — skaner aniqligi, RTK holati yo'q)."""
    idlar = []
    for q in natija.get("quvurlar") or []:
        oq = q.get("oq_wgs84") or []
        if len(oq) < 2:
            continue
        nq = [{"lat": p[0], "lon": p[1], "balandlik": p[2], "chuqurlik_m": q.get("chuqurlik_m"), "rtk_holat": "YOQ",
               "sigma_h_sm": ish["aniqlik_sm"], "sigma_v_sm": ish["aniqlik_sm"], "manba": "skan"} for p in oq]
        d = q.get("standart_mm") or q.get("diametr_mm") or 0
        lid = liniya_yarat(ish["obyekt_id"], ish["tarmoq_turi"], nq, material="", diametr_mm=int(round(d)),
                           izoh=f"Tashqi LiDAR: {ish.get('manba_nomi') or 'noma\'lum skaner'} (ishonch {int((q.get('ishonch') or 0) * 100)} %, "
                                f"e'lon qilingan aniqlik {ish['aniqlik_sm']:g} sm, muhrsiz)",
                           yaratuvchi_id=ish.get("yaratuvchi_id"))
        idlar.append(lid)
    u = ulan()
    u.execute("UPDATE tahlil_ish SET liniya_idlar=? WHERE id=?", (json.dumps(idlar), ish["id"]))
    u.commit()
    u.close()
    return idlar


def tahlil_ol():
    """Navbatdagi ishni atomik egallaydi (bir nechta ishchi bo'lsa ham bitta ish bitta ishchiga)."""
    u = ulan()
    try:
        u.execute("BEGIN IMMEDIATE")
        q = u.execute("UPDATE tahlil_ish SET holat='ishlanmoqda', boshlangan=?, urinish=urinish+1 WHERE id="
                      "(SELECT id FROM tahlil_ish WHERE holat='kutmoqda' ORDER BY id LIMIT 1) RETURNING *",
                      (hozir(),)).fetchone()
        u.commit()
    finally:
        u.close()
    return dict(q) if q else None


def tahlil_yakunla(ish_id, holat, xulosa=None, natija=None, xato=""):
    u = ulan()
    u.execute("UPDATE tahlil_ish SET holat=?, xulosa=?, natija=?, xato=?, tugagan=? WHERE id=?",
              (holat, xulosa, natija, str(xato)[:2000], hozir(), ish_id))
    u.commit()
    u.close()


def tahlil_osilganlar(daqiqa=20):
    """Ishchi qulagan bo'lsa: uzoq 'ishlanmoqda' qolgan ishlar navbatga qaytadi (urinishlar tugasa — xato)."""
    chek = (datetime.now(timezone.utc) - timedelta(minutes=daqiqa)).isoformat(timespec="seconds")
    u = ulan()
    u.execute("UPDATE tahlil_ish SET holat='xato', xato='urinishlar tugadi (ishchi javob bermadi)', tugagan=?"
              " WHERE holat='ishlanmoqda' AND boshlangan<? AND urinish>=?", (hozir(), chek, TAHLIL_URINISH_MAKS))
    k = u.execute("UPDATE tahlil_ish SET holat='kutmoqda' WHERE holat='ishlanmoqda' AND boshlangan<?", (chek,))
    n = k.rowcount
    u.commit()
    u.close()
    return n


def tahlil_qayta(ish_id):
    u = ulan()
    k = u.execute("UPDATE tahlil_ish SET holat='kutmoqda', urinish=0, xato='', xulosa=NULL, natija=NULL, tugagan=NULL"
                  " WHERE id=? AND holat IN ('tayyor','xato')", (ish_id,))
    n = k.rowcount
    u.commit()
    u.close()
    return n == 1


def _tahlil_qisqa(r):
    d = {k: r[k] for k in ("id", "muhr_id", "obyekt_id", "holat", "xulosa", "xato", "urinish", "yaratilgan",
                           "boshlangan", "tugagan")}
    d["tur"] = r["tur"] if "tur" in r.keys() else "muhr"
    d["ply_skan_id"] = r["ply_skan_id"]
    d["jurnal_skan_id"] = r["jurnal_skan_id"]
    for k in ("manba_nomi", "aniqlik_sm", "koordinata", "zona", "tarmoq_turi"):
        d[k] = r[k] if k in r.keys() else None
    d["liniya_idlar"] = json.loads(r["liniya_idlar"]) if ("liniya_idlar" in r.keys() and r["liniya_idlar"]) else []
    d["farq_a_id"] = r["farq_a_id"] if "farq_a_id" in r.keys() else None
    d["farq_b_id"] = r["farq_b_id"] if "farq_b_id" in r.keys() else None
    if d["tur"] == "farq" and r["natija"]:
        try:
            d["farq"] = json.loads(r["natija"])
        except ValueError:
            d["farq"] = None
    if r["natija"]:
        try:
            n = json.loads(r["natija"])
        except ValueError:
            n = {}
        oq = [t["oq_farqi_m"] for t in n.get("taqqos", []) if t.get("oq_farqi_m") is not None]
        g = n.get("georef") or {}
        d.update({"sabablar": n.get("sabablar", []), "ogohlantirishlar": n.get("ogohlantirishlar", []),
                  "quvur_soni": len(n.get("quvurlar", [])), "oq_farqi_maks_m": max(oq) if oq else None,
                  "georef_siljish_m": g.get("siljish_farqi_m"), "korinish": bool(n.get("korinish")),
                  "vaqt_s": n.get("vaqt_s")})
        # DS-03…DS-06: xom yozuvdan kechikish, bo'lakli georeferens, ofset tekshiruvi, zich bulut
        k, b, x, o = n.get("kechikish") or {}, n.get("bolakli") or {}, n.get("xom") or {}, n.get("ofset") or {}
        d.update({"kechikish_ms": round(k["kechikish_s"] * 1000, 1) if k.get("kechikish_s") is not None else None,
                  "kechikish_ishonchli": bool(k.get("ishonchli")),
                  "bolaklar": len(b.get("bolaklar") or []) if b else None, "past_bolaklar": b.get("past_bolaklar"),
                  "maks_tuzatish_m": b.get("maks_tuzatish_m"), "ply_nomi": x.get("ply_nomi"),
                  "chuqurlik_kadrlar": x.get("chuqurlik_kadrlar"), "ofset_farq_m": o.get("profildan_farq_m") if o.get("kuzatiladi") else None})
    return d


def tahlillar(obyekt_id):
    u = ulan()
    q = u.execute("SELECT * FROM tahlil_ish WHERE obyekt_id=? ORDER BY id DESC", (obyekt_id,)).fetchall()
    u.close()
    return [_tahlil_qisqa(r) for r in q]


def tahlil_top(ish_id):
    u = ulan()
    r = u.execute("SELECT * FROM tahlil_ish WHERE id=?", (ish_id,)).fetchone()
    u.close()
    if not r:
        return None
    d = _tahlil_qisqa(r)
    d["natija"] = json.loads(r["natija"]) if r["natija"] else None
    o = obyekt_top(r["obyekt_id"])
    d["obyekt_nomi"] = o["nomi"] if o else None
    return d


def navbat_holati():
    u = ulan()
    q = u.execute("SELECT holat, COUNT(*) n FROM tahlil_ish GROUP BY holat").fetchall()
    u.close()
    return {r["holat"]: r["n"] for r in q}


# ---------- 14-bo'lim: ijro hujjati (IH), loyiha (IH-07), ulashish (UL), tarix va izoh (TL) ----------

def hujjat_papka():
    return os.path.join(SKAN_PAPKA, "hujjat")


def loyiha_papka():
    return os.path.join(SKAN_PAPKA, "loyiha")


def reestr_qutida(lat0, lat1, lon0, lon1, istisno_obyekt_id):
    """Boshqa obyektlarning amaldagi liniyalari: nuqtalar qutisi berilgan qutini kesib o'tsa (uzun to'g'ri kesma
    qutini nuqtasiz kesib o'tganda ham topiladi)."""
    u = ulan()
    ids = [r[0] for r in u.execute(
        "SELECT n.liniya_id FROM nuqta n JOIN liniya l ON l.id=n.liniya_id"
        " WHERE l.holat='amal' AND l.obyekt_id<>? GROUP BY n.liniya_id"
        " HAVING MIN(n.lat)<=? AND MAX(n.lat)>=? AND MIN(n.lon)<=? AND MAX(n.lon)>=?",
        (istisno_obyekt_id, lat1, lat0, lon1, lon0)).fetchall()]
    u.close()
    return liniyalar_toliq(idlar=ids[:2000])


def _tashkent_yil():
    return (datetime.now(timezone.utc) + timedelta(hours=5)).year


HUJJAT_TURLARI = {"ijro": "YRS", "yopiq": "YDA", "muvofiqlik": "YLM"}   # YDA — yopiq ishlar dalolatnomasi (ShN-05), YLM — loyiha–ijro muvofiqligi (T3)


def hujjat_boshla(obyekt_id, yaratuvchi_id, tur="ijro"):
    """Raqam (YRS-/YDA-YYYY-NNNNNN) va tasodifiy tekshirish kodi PDF yasalishidan oldin beriladi — ikkalasi ham hujjat ichida."""
    if tur not in HUJJAT_TURLARI:
        raise ValueError("hujjat turi noto'g'ri")
    kod = secrets.token_urlsafe(12)
    u = ulan()
    k = u.execute("INSERT INTO hujjat(obyekt_id,kod,yaratuvchi_id,yaratilgan,tur) VALUES(?,?,?,?,?)",
                  (obyekt_id, kod, yaratuvchi_id, hozir(), tur))
    hid = k.lastrowid
    raqam = f"{HUJJAT_TURLARI[tur]}-{_tashkent_yil()}-{hid:06d}"
    u.execute("UPDATE hujjat SET raqam=? WHERE id=?", (raqam, hid))
    u.commit()
    u.close()
    return hid, raqam, kod


def hujjat_yakunla(hid, fayl, sha256, hajmi, varaqlar, xulosa):
    u = ulan()
    u.execute("UPDATE hujjat SET fayl=?, sha256=?, hajmi=?, varaqlar=?, xulosa=?, holat='amal' WHERE id=?",
              (fayl, sha256, hajmi, varaqlar, json.dumps(xulosa, ensure_ascii=False), hid))
    u.commit()
    u.close()


def hujjat_xato(hid, xato):
    u = ulan()
    u.execute("UPDATE hujjat SET holat='xato', bekor_sabab=? WHERE id=?", (str(xato)[:500], hid))
    u.commit()
    u.close()


def _hujjat_dict(r):
    d = dict(r)
    try:
        d["xulosa"] = json.loads(d.get("xulosa") or "{}")
    except ValueError:
        d["xulosa"] = {}
    return d


def hujjatlar(obyekt_id):
    u = ulan()
    q = u.execute("SELECT h.*, f.login AS yaratuvchi FROM hujjat h LEFT JOIN foydalanuvchi f ON f.id=h.yaratuvchi_id"
                  " WHERE h.obyekt_id=? AND h.holat IN ('amal','bekor') ORDER BY h.id DESC", (obyekt_id,)).fetchall()
    u.close()
    natija = []
    for r in q:
        d = _hujjat_dict(r)
        d.pop("kod", None)
        d.pop("fayl", None)
        natija.append(d)
    return natija


def hujjat_top(hid):
    u = ulan()
    r = u.execute("SELECT * FROM hujjat WHERE id=?", (hid,)).fetchone()
    u.close()
    return _hujjat_dict(r) if r else None


def hujjat_kod_boyicha(kod):
    if not kod or len(kod) > 64:
        return None
    u = ulan()
    r = u.execute("SELECT * FROM hujjat WHERE kod=? AND holat IN ('amal','bekor')", (kod,)).fetchone()
    u.close()
    return _hujjat_dict(r) if r else None


def hujjat_bekor(hid, sabab):
    u = ulan()
    n = u.execute("UPDATE hujjat SET holat='bekor', bekor_sabab=?, bekor_vaqt=? WHERE id=? AND holat='amal'",
                  (str(sabab)[:500], hozir(), hid)).rowcount
    u.commit()
    u.close()
    return n == 1


LOYIHA_Z_TURLARI = ("oq", "usti", "tubi")
LOYIHA_Z_TIZIMLARI = ("ellipsoid", "boltiq")


def loyiha_saqla(obyekt_id, fayl_nomi, data, z_turi, z_tizimi, chiziqlar, yaratuvchi_id, koordinata="utm"):
    """Yangi loyiha DXF — oldingisi 'eski' bo'ladi (o'chirilmaydi). Asl fayl ham saqlanadi (iz).
    koordinata: 'utm' yoki 'mahalliy' (LK-07: chiziqlar asl tizimda saqlanadi, kerakda lokalizatsiya bilan o'tkaziladi)."""
    if z_turi not in LOYIHA_Z_TURLARI or z_tizimi not in LOYIHA_Z_TIZIMLARI or koordinata not in ("utm", "mahalliy"):
        raise ValueError("z_turi, z_tizimi yoki koordinata noto'g'ri")
    sha = hashlib.sha256(data).hexdigest()
    u = ulan()
    u.execute("UPDATE loyiha SET holat='eski' WHERE obyekt_id=? AND holat='amal'", (obyekt_id,))
    k = u.execute("INSERT INTO loyiha(obyekt_id,fayl_nomi,sha256,hajmi,z_turi,z_tizimi,chiziqlar,yaratuvchi_id,yaratilgan,"
                  "koordinata) VALUES(?,?,?,?,?,?,?,?,?,?)", (obyekt_id, fayl_nomi, sha, len(data), z_turi, z_tizimi,
                                                             json.dumps(chiziqlar), yaratuvchi_id, hozir(), koordinata))
    lid = k.lastrowid
    os.makedirs(loyiha_papka(), exist_ok=True)
    with open(os.path.join(loyiha_papka(), f"{lid}.dxf"), "wb") as f:
        f.write(data)
    u.commit()
    u.close()
    return lid


def loyiha_top(obyekt_id):
    u = ulan()
    r = u.execute("SELECT * FROM loyiha WHERE obyekt_id=? AND holat='amal' ORDER BY id DESC LIMIT 1",
                  (obyekt_id,)).fetchone()
    u.close()
    if not r:
        return None
    d = dict(r)
    d["chiziqlar"] = json.loads(d["chiziqlar"])
    return d


def loyihalar(obyekt_id):
    u = ulan()
    q = u.execute("SELECT id,obyekt_id,fayl_nomi,sha256,hajmi,z_turi,z_tizimi,koordinata,holat,yaratilgan FROM loyiha"
                  " WHERE obyekt_id=? ORDER BY id DESC", (obyekt_id,)).fetchall()
    u.close()
    return [dict(r) for r in q]


ULASH_MAKS_KUN = 365


def ulash_yarat(obyekt_id, nomi, kun, yaratuvchi_id):
    """UL-01: token faqat shu javobda; bazada sha256."""
    kun = int(kun)
    if not 1 <= kun <= ULASH_MAKS_KUN:
        raise ValueError(f"muddat 1…{ULASH_MAKS_KUN} kun")
    token = "YRU." + secrets.token_urlsafe(24)
    muddati = (datetime.now(timezone.utc) + timedelta(days=kun)).isoformat(timespec="seconds")
    u = ulan()
    k = u.execute("INSERT INTO ulash(obyekt_id,token_hash,nomi,muddati,yaratuvchi_id,yaratilgan) VALUES(?,?,?,?,?,?)",
                  (obyekt_id, hashlib.sha256(token.encode()).hexdigest(), nomi, muddati, yaratuvchi_id, hozir()))
    uid = k.lastrowid
    u.commit()
    u.close()
    return uid, token, muddati


def _ulash_holat(d):
    if d["bekor"]:
        return "bekor"
    return "muddati_tugagan" if d["muddati"] <= hozir() else "amal"


def ulashlar(obyekt_id):
    u = ulan()
    q = u.execute("SELECT s.id,s.obyekt_id,s.nomi,s.muddati,s.bekor,s.bekor_vaqt,s.foydalanish,s.oxirgi,s.yaratilgan,"
                  " f.login AS yaratuvchi FROM ulash s LEFT JOIN foydalanuvchi f ON f.id=s.yaratuvchi_id"
                  " WHERE s.obyekt_id=? ORDER BY s.id DESC", (obyekt_id,)).fetchall()
    u.close()
    return [dict(dict(r), holat=_ulash_holat(r)) for r in q]


def ulash_top(token):
    if not token or not token.startswith("YRU.") or len(token) > 80:
        return None
    u = ulan()
    r = u.execute("SELECT * FROM ulash WHERE token_hash=?", (hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
    u.close()
    return dict(dict(r), holat=_ulash_holat(r)) if r else None


def ulash_foydalan(uid):
    u = ulan()
    u.execute("UPDATE ulash SET foydalanish=foydalanish+1, oxirgi=? WHERE id=?", (hozir(), uid))
    u.commit()
    u.close()


def ulash_bekor(uid, obyekt_id=None):
    u = ulan()
    sh, q = ("id=? AND bekor=0", [uid])
    if obyekt_id is not None:
        sh += " AND obyekt_id=?"
        q.append(obyekt_id)
    n = u.execute(f"UPDATE ulash SET bekor=1, bekor_vaqt=? WHERE {sh}", [hozir()] + q).rowcount
    u.commit()
    u.close()
    return n == 1


def ulash_id_top(uid):
    u = ulan()
    r = u.execute("SELECT id,obyekt_id,bekor FROM ulash WHERE id=?", (uid,)).fetchone()
    u.close()
    return dict(r) if r else None


IZOH_MAKS = 1000


def izoh_qosh(tahlil_id, x, y, z, matn, yaratuvchi_id):
    t = tahlil_top(tahlil_id)
    if not t:
        raise ValueError("tahlil topilmadi")
    matn = str(matn).strip()
    if not matn or len(matn) > IZOH_MAKS:
        raise ValueError(f"izoh 1…{IZOH_MAKS} belgi")
    x, y, z = float(x), float(y), float(z)
    if not all(math.isfinite(v) and abs(v) < 1e7 for v in (x, y, z)):
        raise ValueError("koordinata noto'g'ri")
    u = ulan()
    k = u.execute("INSERT INTO izoh(tahlil_id,obyekt_id,x,y,z,matn,yaratuvchi_id,yaratilgan) VALUES(?,?,?,?,?,?,?,?)",
                  (tahlil_id, t["obyekt_id"], x, y, z, matn, yaratuvchi_id, hozir()))
    iid = k.lastrowid
    u.commit()
    u.close()
    return iid


def izohlar(tahlil_id):
    u = ulan()
    q = u.execute("SELECT i.id,i.tahlil_id,i.x,i.y,i.z,i.matn,i.yaratilgan, COALESCE(NULLIF(f.ism,''), f.login) AS muallif"
                  " FROM izoh i LEFT JOIN foydalanuvchi f ON f.id=i.yaratuvchi_id WHERE i.tahlil_id=? ORDER BY i.id",
                  (tahlil_id,)).fetchall()
    u.close()
    return [dict(r) for r in q]


def tarix(obyekt_id):
    """TL-01: obyekt bo'yicha barcha hodisalar, yangisi birinchi. Koordinata yo'q — faqat nima, qachon, kim."""
    u = ulan()
    h = []
    o = u.execute("SELECT o.*, f.login FROM obyekt o LEFT JOIN foydalanuvchi f ON f.id=o.yaratuvchi_id WHERE o.id=?",
                  (obyekt_id,)).fetchone()
    if not o:
        u.close()
        return None
    h.append({"vaqt": o["yaratilgan"], "tur": "obyekt", "matn": f"Obyekt yaratildi: {o['nomi']}", "kim": o["login"]})
    for r in u.execute("SELECT l.id,l.turi,l.diametr_mm,l.versiya,l.holat,l.yaratilgan,f.login,d.nomi AS dala FROM liniya l"
                       " LEFT JOIN foydalanuvchi f ON f.id=l.yaratuvchi_id LEFT JOIN dala_token d ON d.id=l.dala_token_id"
                       " WHERE l.obyekt_id=?", (obyekt_id,)):
        h.append({"vaqt": r["yaratilgan"], "tur": "liniya", "id": r["id"],
                  "matn": f"Liniya #{r['id']}: {r['turi']} Ø{r['diametr_mm']} (v{r['versiya']}, {r['holat']})",
                  "kim": r["login"] or (f"dala: {r['dala']}" if r["dala"] else None)})
    for r in u.execute("SELECT id,turi,hajmi,holat,yaratilgan,yakunlangan FROM skan WHERE obyekt_id=?", (obyekt_id,)):
        h.append({"vaqt": r["yakunlangan"] or r["yaratilgan"], "tur": "skan", "id": r["id"],
                  "matn": f"Skan fayli #{r['id']}: {r['turi']}, {round(r['hajmi'] / 1048576, 1)} MB ({r['holat']})"})
    for r in u.execute("SELECT id,holat,sabab,yaratilgan FROM muhr WHERE obyekt_id=?", (obyekt_id,)):
        h.append({"vaqt": r["yaratilgan"], "tur": "muhr", "id": r["id"], "holat": r["holat"],
                  "matn": f"Muhr #{r['id']}: {r['holat']}" + (f" ({r['sabab']})" if r["sabab"] else "")})
    for r in u.execute("SELECT id,muhr_id,holat,xulosa,yaratilgan,tugagan FROM tahlil_ish WHERE obyekt_id=?", (obyekt_id,)):
        h.append({"vaqt": r["tugagan"] or r["yaratilgan"], "tur": "tahlil", "id": r["id"], "holat": r["xulosa"] or r["holat"],
                  "matn": f"Qayta hisob #{r['id']} (muhr #{r['muhr_id']}): " + (r["xulosa"] or r["holat"])})
    for r in u.execute("SELECT h.id,h.raqam,h.holat,h.yaratilgan,h.bekor_vaqt,h.bekor_sabab,f.login FROM hujjat h"
                       " LEFT JOIN foydalanuvchi f ON f.id=h.yaratuvchi_id WHERE h.obyekt_id=? AND h.holat IN ('amal','bekor')",
                       (obyekt_id,)):
        h.append({"vaqt": r["yaratilgan"], "tur": "hujjat", "id": r["id"], "matn": f"Ijro hujjati {r['raqam']} yaratildi",
                  "kim": r["login"]})
        if r["bekor_vaqt"]:
            h.append({"vaqt": r["bekor_vaqt"], "tur": "hujjat", "id": r["id"], "holat": "bekor",
                      "matn": f"Ijro hujjati {r['raqam']} bekor qilindi: {r['bekor_sabab']}"})
    for r in u.execute("SELECT l.id,l.fayl_nomi,l.yaratilgan,f.login FROM loyiha l"
                       " LEFT JOIN foydalanuvchi f ON f.id=l.yaratuvchi_id WHERE l.obyekt_id=?", (obyekt_id,)):
        h.append({"vaqt": r["yaratilgan"], "tur": "loyiha", "id": r["id"], "matn": f"Loyiha DXF yuklandi: {r['fayl_nomi']}",
                  "kim": r["login"]})
    for r in u.execute("SELECT s.id,s.nomi,s.muddati,s.yaratilgan,s.bekor_vaqt,f.login FROM ulash s"
                       " LEFT JOIN foydalanuvchi f ON f.id=s.yaratuvchi_id WHERE s.obyekt_id=?", (obyekt_id,)):
        h.append({"vaqt": r["yaratilgan"], "tur": "ulash", "id": r["id"],
                  "matn": f"Ulashish havolasi: {r['nomi']} ({r['muddati'][8:10]}.{r['muddati'][5:7]}.{r['muddati'][:4]} gacha)",
                  "kim": r["login"]})
        if r["bekor_vaqt"]:
            h.append({"vaqt": r["bekor_vaqt"], "tur": "ulash", "id": r["id"], "holat": "bekor",
                      "matn": f"Ulashish havolasi bekor qilindi: {r['nomi']}"})
    for r in u.execute("SELECT i.id,i.tahlil_id,i.yaratilgan,f.login FROM izoh i LEFT JOIN foydalanuvchi f"
                       " ON f.id=i.yaratuvchi_id WHERE i.obyekt_id=?", (obyekt_id,)):
        h.append({"vaqt": r["yaratilgan"], "tur": "izoh", "id": r["id"], "matn": f"3D izoh (tahlil #{r['tahlil_id']})",
                  "kim": r["login"]})
    u.close()
    h.sort(key=lambda x: (x["vaqt"] or ""), reverse=True)
    return h


# ---------- 15-bo'lim: geodezik asos — nazorat punktlari, o'lchovlar, lokalizatsiya (LK) ----------
OLCHOV_MAQSADLARI = ("kalibrlash", "tekshiruv")
OLCHOV_SIGMA_H_SM = 3.0       # LK-02: o'rtachalangan o'lchov shundan yomon bo'lsa — rad (punkt ustida turish xatosi)
OLCHOV_SIGMA_V_SM = 5.0
OLCHOV_MIN_S = 30.0           # LK-02: ilovadan kelgan o'lchov kamida 30 s o'rtachalanadi


def _son_yoki_none(x, nom):
    if x is None or x == "":
        return None
    try:
        v = float(str(x).replace(",", "."))
    except ValueError:
        raise ValueError(f"{nom} son emas: {x!r}") from None
    if not math.isfinite(v):
        raise ValueError(f"{nom} noto'g'ri")
    return v


def nazorat_punkt_qosh(obyekt_id, nomi, x, y, h, sinf="", manba="", yaratuvchi_id=None):
    """LK-01. Shu nomli amaldagi punkt bo'lsa — u 'eski' bo'ladi (o'chirilmaydi), yangisi kuchga kiradi."""
    nomi = str(nomi).strip()[:40]
    if not nomi:
        raise ValueError("punkt nomi kerak")
    x, y, h = _son_yoki_none(x, "X"), _son_yoki_none(y, "Y"), _son_yoki_none(h, "H")
    if (x is None) != (y is None):
        raise ValueError(f"{nomi}: X va Y birga beriladi")
    if x is None and h is None:
        raise ValueError(f"{nomi}: X, Y yoki H dan kamida biri kerak")
    if h is not None and not -500 <= h <= 9000:
        raise ValueError(f"{nomi}: H {h} m — Boltiq balandligi emas")
    u = ulan()
    u.execute("UPDATE nazorat_punkt SET holat='eski' WHERE obyekt_id=? AND nomi=? AND holat='amal'", (obyekt_id, nomi))
    k = u.execute("INSERT INTO nazorat_punkt(obyekt_id,nomi,x,y,h,sinf,manba,yaratuvchi_id,yaratilgan) VALUES(?,?,?,?,?,?,?,?,?)",
                  (obyekt_id, nomi, x, y, h, str(sinf)[:60], str(manba)[:120], yaratuvchi_id, hozir()))
    pid = k.lastrowid
    u.commit()
    u.close()
    return pid


def nazorat_punktlar(obyekt_id):
    u = ulan()
    q = u.execute("SELECT * FROM nazorat_punkt WHERE obyekt_id=? AND holat='amal' ORDER BY nomi", (obyekt_id,)).fetchall()
    u.close()
    return [dict(r) for r in q]


def nazorat_punkt_bekor(punkt_id, obyekt_id):
    u = ulan()
    n = u.execute("UPDATE nazorat_punkt SET holat='eski' WHERE id=? AND obyekt_id=? AND holat='amal'",
                  (punkt_id, obyekt_id)).rowcount
    u.commit()
    u.close()
    return n == 1


def nazorat_olchov_qosh(obyekt_id, punkt, maqsad, lat, lon, h, rtk_holat, sigma_h_sm=None, sigma_v_sm=None,
                        epoxalar=None, davomiylik_s=None, antenna_m=None, vaqt=None, manba="rtk",
                        dala_token_id=None, yaratuvchi_id=None):
    """LK-02. `punkt` — id yoki nomi (shu obyektning amaldagi punkti). Faqat FIX; σ va davomiylik chegarasi."""
    if maqsad not in OLCHOV_MAQSADLARI:
        raise ValueError("maqsad: kalibrlash yoki tekshiruv")
    lat, lon, h = _son_yoki_none(lat, "lat"), _son_yoki_none(lon, "lon"), _son_yoki_none(h, "h")
    if lat is None or lon is None or not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError("lat/lon noto'g'ri")
    if str(rtk_holat).upper() != "FIX":
        raise ValueError("nazorat o'lchovi faqat RTK FIX da (LK-02)")
    sh, sv = _son_yoki_none(sigma_h_sm, "σH"), _son_yoki_none(sigma_v_sm, "σV")
    if sh is not None and sh > OLCHOV_SIGMA_H_SM:
        raise ValueError(f"σH {sh} sm > {OLCHOV_SIGMA_H_SM} sm: o'lchovni takrorlang")
    if sv is not None and sv > OLCHOV_SIGMA_V_SM:
        raise ValueError(f"σV {sv} sm > {OLCHOV_SIGMA_V_SM} sm: o'lchovni takrorlang")
    dav = _son_yoki_none(davomiylik_s, "davomiylik")
    if manba == "rtk" and (dav is None or dav < OLCHOV_MIN_S):
        raise ValueError(f"o'rtachalash kamida {OLCHOV_MIN_S:.0f} s (LK-02)")
    u = ulan()
    if isinstance(punkt, int) or str(punkt).isdigit():
        r = u.execute("SELECT id FROM nazorat_punkt WHERE id=? AND obyekt_id=? AND holat='amal'",
                      (int(punkt), obyekt_id)).fetchone()
    else:
        r = u.execute("SELECT id FROM nazorat_punkt WHERE nomi=? AND obyekt_id=? AND holat='amal'",
                      (str(punkt).strip(), obyekt_id)).fetchone()
    if not r:
        u.close()
        raise ValueError(f"nazorat punkti topilmadi: {punkt}")
    k = u.execute("INSERT INTO nazorat_olchov(obyekt_id,punkt_id,maqsad,lat,lon,h,sigma_h_sm,sigma_v_sm,epoxalar,davomiylik_s,"
                  "rtk_holat,antenna_m,vaqt,manba,dala_token_id,yaratuvchi_id,yaratilgan) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                  (obyekt_id, r["id"], maqsad, lat, lon, h, sh, sv, epoxalar, dav, "FIX",
                   _son_yoki_none(antenna_m, "antenna"), vaqt or hozir(), manba, dala_token_id, yaratuvchi_id, hozir()))
    oid = k.lastrowid
    u.commit()
    u.close()
    return oid


def nazorat_olchovlar(obyekt_id):
    u = ulan()
    q = u.execute("SELECT o.*, p.nomi AS punkt_nomi FROM nazorat_olchov o JOIN nazorat_punkt p ON p.id=o.punkt_id"
                  " WHERE o.obyekt_id=? AND o.holat='amal' AND p.holat='amal' ORDER BY o.vaqt, o.id", (obyekt_id,)).fetchall()
    u.close()
    return [dict(r) for r in q]


def nazorat_olchov_bekor(olchov_id, obyekt_id):
    u = ulan()
    n = u.execute("UPDATE nazorat_olchov SET holat='bekor' WHERE id=? AND obyekt_id=? AND holat='amal'",
                  (olchov_id, obyekt_id)).rowcount
    u.commit()
    u.close()
    return n == 1


# ---------- 18-bo'lim: quvur tasdig'i (TQ, T-031) ----------

TASDIQ_JOYLAR = ("usti", "oq")


def tasdiq_qosh(obyekt_id, nomi, lat, lon, h, rtk_holat, sigma_h_sm=None, sigma_v_sm=None, epoxalar=None,
                davomiylik_s=None, tuzatma_yoshi_s=None, antenna_m=None, vaqt=None, joy="usti", liniya_id=None,
                manba="rtk", dala_token_id=None, yaratuvchi_id=None):
    """TQ-01: vexa uchi quvur ustida (yoki ochiq uchida o'qda) turganda RTK FIX o'lchovi. T-103 chegaralari: FIX,
    σH ≤ 2 sm, σV ≤ 5 sm, tuzatma yoshi ≤ 10 s; ilovadan kelgan o'lchov ≥ 5 s va ≥ 5 epoxa o'rtachalanadi. Isbotsiz
    (σ siz) tasdiq qabul qilinmaydi. `liniya_id` ixtiyoriy — bo'lmasa server eng yaqin liniyaga bog'laydi."""
    import yerosti_tasdiq as tq
    if joy not in TASDIQ_JOYLAR:
        raise ValueError("joy: usti (vexa quvur ustida) yoki oq (ochiq uchida o'qda)")
    lat, lon, h = _son_yoki_none(lat, "lat"), _son_yoki_none(lon, "lon"), _son_yoki_none(h, "h")
    if lat is None or lon is None or not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError("lat/lon noto'g'ri")
    if not obyekt_top(obyekt_id):
        raise ValueError("obyekt topilmadi")
    if str(rtk_holat).upper() != "FIX":
        raise ValueError("tasdiq faqat RTK FIX da (T-103)")
    sh, sv = _son_yoki_none(sigma_h_sm, "σH"), _son_yoki_none(sigma_v_sm, "σV")
    if sh is None or sv is None:
        raise ValueError("σH va σV kerak: isbotsiz tasdiq qabul qilinmaydi (T-103)")
    if sh > tq.SIGMA_H_SM:
        raise ValueError(f"σH {sh:g} sm > {tq.SIGMA_H_SM:g} sm (T-103): o'lchovni takrorlang")
    if sv > tq.SIGMA_V_SM:
        raise ValueError(f"σV {sv:g} sm > {tq.SIGMA_V_SM:g} sm (T-103): o'lchovni takrorlang")
    ty = _son_yoki_none(tuzatma_yoshi_s, "tuzatma yoshi")
    if ty is not None and ty > tq.TUZATMA_S:
        raise ValueError(f"tuzatma yoshi {ty:g} s > {tq.TUZATMA_S:g} s (T-103)")
    dav = _son_yoki_none(davomiylik_s, "davomiylik")
    if manba == "rtk" and (dav is None or dav < tq.MIN_S):
        raise ValueError(f"o'rtachalash kamida {tq.MIN_S:.0f} s (TQ-01)")
    ep = int(epoxalar) if epoxalar not in (None, "") else None
    if ep is not None and ep < tq.MIN_EPOXA:
        raise ValueError(f"kamida {tq.MIN_EPOXA} epoxa (TQ-01)")
    u = ulan()
    lid = None
    if liniya_id not in (None, "", 0):
        r = u.execute("SELECT id FROM liniya WHERE id=? AND obyekt_id=? AND holat='amal'", (int(liniya_id), obyekt_id)).fetchone()
        if not r:
            u.close()
            raise ValueError(f"liniya topilmadi: {liniya_id}")
        lid = r["id"]
    k = u.execute("INSERT INTO tasdiq(obyekt_id,liniya_id,nomi,lat,lon,h,sigma_h_sm,sigma_v_sm,epoxalar,davomiylik_s,rtk_holat,"
                  "tuzatma_yoshi_s,antenna_m,vaqt,joy,manba,dala_token_id,yaratuvchi_id,yaratilgan)"
                  " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                  (obyekt_id, lid, str(nomi or "")[:80], lat, lon, h, sh, sv, ep, dav, "FIX", ty,
                   _son_yoki_none(antenna_m, "antenna"), vaqt or hozir(), joy, manba, dala_token_id, yaratuvchi_id, hozir()))
    tid = k.lastrowid
    u.commit()
    u.close()
    return tid


def tasdiqlar(obyekt_id):
    u = ulan()
    q = u.execute("SELECT * FROM tasdiq WHERE obyekt_id=? AND holat='amal' ORDER BY vaqt, id", (obyekt_id,)).fetchall()
    u.close()
    return [dict(r) for r in q]


def tasdiq_bekor(tasdiq_id, obyekt_id):
    u = ulan()
    n = u.execute("UPDATE tasdiq SET holat='bekor' WHERE id=? AND obyekt_id=? AND holat='amal'", (tasdiq_id, obyekt_id)).rowcount
    u.commit()
    u.close()
    return n > 0


def tasdiq_holati(obyekt_id, liniyalar=None):
    """TQ-03/05: obyektning tasdiqlari liniyalarga bog'lanib baholanadi (yerosti_tasdiq.hisobla)."""
    import yerosti_tasdiq as tq
    return tq.hisobla(liniyalar if liniyalar is not None else liniyalar_toliq(obyekt_id=obyekt_id), tasdiqlar(obyekt_id))


def tasdiq_liniya_holatlari(qatorlar):
    """Hamma obyektlar liniyalari uchun {liniya_id: holat}. Tasdig'i yo'q va skan nuqtasi yo'q obyektlar hisoblanmaydi."""
    import yerosti_tasdiq as tq
    u = ulan()
    tq_hamma = {}
    for r in u.execute("SELECT * FROM tasdiq WHERE holat='amal' ORDER BY vaqt, id"):
        tq_hamma.setdefault(r["obyekt_id"], []).append(dict(r))
    u.close()
    guruh = {}
    for l in qatorlar:
        guruh.setdefault(l["obyekt_id"], []).append(l)
    natija = {}
    for oid, lin in guruh.items():
        skan = any(n.get("manba") == "skan" or n.get("sifat") == "SKAN" for l in lin for n in l["nuqtalar"])
        if not skan and oid not in tq_hamma:
            for l in lin:
                natija[l["id"]] = "rtk"
            continue
        for lid, h in tq.hisobla(lin, tq_hamma.get(oid, [])).get("liniyalar", {}).items():
            natija[lid] = h["holat"]
    return natija



def lokalizatsiya_saqla(obyekt_id, tizim_nomi, natija, olchov_idlar, yaratuvchi_id):
    u = ulan()
    u.execute("UPDATE lokalizatsiya SET holat='eski' WHERE obyekt_id=? AND holat='amal'", (obyekt_id,))
    k = u.execute("INSERT INTO lokalizatsiya(obyekt_id,tizim_nomi,natija,olchovlar,yaratuvchi_id,yaratilgan) VALUES(?,?,?,?,?,?)",
                  (obyekt_id, tizim_nomi, json.dumps(natija), json.dumps(olchov_idlar), yaratuvchi_id, hozir()))
    lid = k.lastrowid
    u.commit()
    u.close()
    return lid


def lokalizatsiya_top(obyekt_id):
    u = ulan()
    r = u.execute("SELECT * FROM lokalizatsiya WHERE obyekt_id=? AND holat='amal' ORDER BY id DESC LIMIT 1",
                  (obyekt_id,)).fetchone()
    u.close()
    if not r:
        return None
    d = dict(r)
    d["natija"] = json.loads(d["natija"])
    d["olchovlar"] = json.loads(d["olchovlar"])
    return d


def topo_papka():
    return os.path.join(SKAN_PAPKA, "topo")


def topo_saqla(obyekt_id, fayl_nomi, data, ajratilgan, yaratuvchi_id):
    """LK-08: shaharning topografik plani (mahalliy tizimda). Ajratilgan chiziq va matnlar JSON faylda (katta bo'lishi
    mumkin), bazada faqat iz; oldingisi 'eski'."""
    sha = hashlib.sha256(data).hexdigest()
    u = ulan()
    u.execute("UPDATE topo_asos SET holat='eski' WHERE obyekt_id=? AND holat='amal'", (obyekt_id,))
    k = u.execute("INSERT INTO topo_asos(obyekt_id,fayl_nomi,sha256,hajmi,chiziq_soni,matn_soni,yaratuvchi_id,yaratilgan)"
                  " VALUES(?,?,?,?,?,?,?,?)", (obyekt_id, fayl_nomi, sha, len(data), len(ajratilgan["chiziqlar"]),
                                               len(ajratilgan["matnlar"]), yaratuvchi_id, hozir()))
    tid = k.lastrowid
    os.makedirs(topo_papka(), exist_ok=True)
    with open(os.path.join(topo_papka(), f"{tid}.dxf"), "wb") as f:
        f.write(data)
    with open(os.path.join(topo_papka(), f"{tid}.json"), "w", encoding="utf-8") as f:
        json.dump(ajratilgan, f, ensure_ascii=False)
    u.commit()
    u.close()
    return tid


def topo_top(obyekt_id):
    u = ulan()
    r = u.execute("SELECT * FROM topo_asos WHERE obyekt_id=? AND holat='amal' ORDER BY id DESC LIMIT 1",
                  (obyekt_id,)).fetchone()
    u.close()
    if not r:
        return None
    d = dict(r)
    try:
        with open(os.path.join(topo_papka(), f"{d['id']}.json"), encoding="utf-8") as f:
            d.update(json.load(f))
    except (OSError, ValueError):
        return None
    return d


def topolar(obyekt_id):
    u = ulan()
    q = u.execute("SELECT id,obyekt_id,fayl_nomi,sha256,hajmi,chiziq_soni,matn_soni,holat,yaratilgan FROM topo_asos"
                  " WHERE obyekt_id=? ORDER BY id DESC", (obyekt_id,)).fetchall()
    u.close()
    return [dict(r) for r in q]


# ---------- ShN-05: muhrlangan dalillar (yopiq ishlar dalolatnomasi uchun) ----------

def muhr_jurnali(muhr_id):
    """TASDIQLANGAN muhr manifestidagi jurnal fayli (skan qatori) — bo'lmasa None."""
    u = ulan()
    r = u.execute("SELECT obyekt_id, manifest, holat FROM muhr WHERE id=?", (muhr_id,)).fetchone()
    u.close()
    if not r or r["holat"] != "TASDIQLANGAN":
        return None
    try:
        fayllar = json.loads(r["manifest"] or "{}").get("fayllar") or []
    except ValueError:
        return None
    for f in fayllar:
        sk = skan_xesh_boyicha(r["obyekt_id"], f.get("sha256", ""), f.get("hajm", -1))
        if sk and sk["turi"] == "muhr_jurnal":
            return sk
    return None


def muhrlangan_rasmlar(obyekt_id):
    """ShN-05: obyektga yuklangan rasmlardan TASDIQLANGAN muhr jurnalida xeshi bor bo'lganlari (kalit kadrlar).
    Har biri: skan_id, sha256, muhr_id, kadr tartibi, RTK holati va σ (jurnaldagi kadr yozuvidan)."""
    import yerosti_muhr as ym
    kadrlar = {}
    for m in muhrlar(obyekt_id):
        if m["holat"] != "TASDIQLANGAN":
            continue
        sk = muhr_jurnali(m["id"])
        if not sk:
            continue
        try:
            for tur, d in ym.jurnal_yozuvlari(skan_fayl_oqi(sk)):
                if tur != 2:
                    continue
                try:
                    k = json.loads(d)
                except ValueError:
                    continue
                if isinstance(k, dict) and k.get("jpeg") and "tur" not in k:
                    kadrlar.setdefault(str(k["jpeg"]).lower(), dict(k, muhr_id=m["id"], muhr_vaqt=m["yaratilgan"]))
        except ValueError:
            continue
    natija = []
    for s in skanlar(obyekt_id):
        if s["turi"] != "foto" or s["holat"] != "tayyor":
            continue
        k = kadrlar.get(s["sha256"].lower())
        if k:
            rtk = k.get("rtk") or {}
            natija.append({"skan_id": s["id"], "sha256": s["sha256"], "hajmi": s["hajmi"], "muhr_id": k["muhr_id"],
                           "muhr_vaqt": k["muhr_vaqt"], "kadr": k.get("i"), "sifat": k.get("sifat"),
                           "rtk": rtk.get("rtk"), "sigma_h_sm": rtk.get("sigmaH"), "lat": rtk.get("lat"), "lon": rtk.get("lon")})
    natija.sort(key=lambda x: (x["muhr_id"], x["kadr"] if x["kadr"] is not None else 0))
    return natija


# ---------- T1: quduq, zadvijka va burilishdagi QR-belgilar ----------

BELGI_TURLARI = {"quduq": "Quduq", "zadvijka": "Zadvijka", "burilish": "Burilish", "ulanish": "Ulanish", "boshqa": "Belgi"}


def belgi_yarat(liniya_id, nuqta, tur, raqam, aloqa="", izoh="", yaratuvchi_id=None):
    """T1-1: o'lchangan liniya nuqtasidan QR-belgi. Raqam obyekt ichida takrorlanmaydi; kod — 16 belgi (96 bit)."""
    if tur not in BELGI_TURLARI:
        raise ValueError("tur: " + ", ".join(BELGI_TURLARI))
    raqam = str(raqam or "").strip()
    if not raqam or len(raqam) > 20:
        raise ValueError("raqam 1…20 belgi bo'lsin")
    aloqa, izoh = str(aloqa or "").strip(), str(izoh or "").strip()
    if len(aloqa) > 60 or len(izoh) > 300:
        raise ValueError("aloqa 60, izoh 300 belgidan oshmasin")
    q = liniyalar_toliq(idlar=[int(liniya_id)])
    if not q:
        raise LookupError("liniya topilmadi")
    l = q[0]
    nq = l["nuqtalar"]
    if not isinstance(nuqta, int) or not 0 <= nuqta < len(nq):
        raise ValueError(f"nuqta 0…{len(nq) - 1} oralig'ida bo'lsin")
    pik = sum(masofa_m(nq[i]["lat"], nq[i]["lon"], nq[i + 1]["lat"], nq[i + 1]["lon"]) for i in range(nuqta))
    p = nq[nuqta]
    u = ulan()
    if u.execute("SELECT 1 FROM belgi WHERE obyekt_id=? AND raqam=? AND holat='amal'", (l["obyekt_id"], raqam)).fetchone():
        u.close()
        raise ValueError(f"«{raqam}» raqamli belgi bu obyektda bor")
    kod = secrets.token_urlsafe(12)
    k = u.execute("INSERT INTO belgi(obyekt_id,liniya_id,nuqta_tartib,tur,raqam,lat,lon,balandlik,chuqurlik_m,pikitaj_m,kod,aloqa,izoh,"
                  "yaratuvchi_id,yaratilgan) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                  (l["obyekt_id"], l["id"], nuqta, tur, raqam, p["lat"], p["lon"], p.get("balandlik"), p.get("chuqurlik_m"),
                   round(pik, 2), kod, aloqa, izoh, yaratuvchi_id, hozir()))
    bid = k.lastrowid
    u.commit()
    u.close()
    return bid, kod


def belgilar(obyekt_id):
    u = ulan()
    q = u.execute("SELECT * FROM belgi WHERE obyekt_id=? ORDER BY id", (obyekt_id,)).fetchall()
    u.close()
    return [dict(r) for r in q]


def belgi_top(belgi_id):
    u = ulan()
    r = u.execute("SELECT * FROM belgi WHERE id=?", (belgi_id,)).fetchone()
    u.close()
    return dict(r) if r else None


def belgi_kod_boyicha(kod):
    if not kod or len(kod) > 64:
        return None
    u = ulan()
    r = u.execute("SELECT * FROM belgi WHERE kod=?", (kod,)).fetchone()
    u.close()
    return dict(r) if r else None


def belgi_korildi(belgi_id):
    """T1-5: ko'rishlar soni va oxirgi vaqt (IP saqlanmaydi)."""
    u = ulan()
    u.execute("UPDATE belgi SET korishlar=korishlar+1, oxirgi_korish=? WHERE id=?", (hozir(), belgi_id))
    u.commit()
    u.close()


def belgi_bekor(belgi_id, sabab):
    sabab = str(sabab or "").strip()
    if not sabab:
        raise ValueError("sabab kerak")
    u = ulan()
    n = u.execute("UPDATE belgi SET holat='bekor', bekor_sabab=?, bekor_vaqt=? WHERE id=? AND holat='amal'",
                  (sabab[:300], hozir(), belgi_id)).rowcount
    u.commit()
    u.close()
    return n > 0
