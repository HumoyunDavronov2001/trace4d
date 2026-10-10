# TRACE4D data markaz — joylash, zaxira va tiklash (DM-01…DM-07)

Bitta server (O'zbekistondagi data markaz), Docker Compose, tashqi xizmatlarsiz.

| Xizmat | Vazifasi |
|---|---|
| `server` | API + portal + 3D ko'ruvchi (`/3d`). Muhrni tekshiradi, tasdiqlangan skanni qayta hisob navbatiga qo'yadi |
| `ishchi` | DM-02: har muhrlangan skanni telefon bilan **bir xil** Swift yadrosida qayta hisoblaydi (`yerosti-tahlil`) |
| `zaxira` | DM-05: har 24 soatda baza + skanlar, SHA-256 manifest, 14 ta zaxira saqlanadi |
| `proksi` | Caddy: TLS, HSTS, siqish; mijoz IP sini `X-Real-IP` da uzatadi |

Doimiy ma'lumot `malumot` hajmida (baza, skanlar, tahlil natijalari). Zaxiralar hostdagi papkada (`YEROSTI_ZAXIRA_PAPKA`).

## 1. Talablar

* Ubuntu 24.04 (yoki Docker ishlaydigan boshqa Linux), Docker Engine + compose plagini.
* Disk: bitta skan asosan `mesh.ply` (≈ 24 bayt × nuqtalar soni) + muhr jurnali. Zaxira qattiq havola ishlatadi:
  o'zgarmagan skan har kungi zaxirada qayta joy olmaydi.
* Zaxira papkasi alohida diskda bo'lsin. Kuniga bir marta boshqa serverga ham ko'chirilsin (`rsync -aH`, qattiq havolalar
  saqlanadi).

## 2. O'rnatish

```bash
cp .env.example .env
nano .env                      # YEROSTI_DOMEN, YEROSTI_TASHQI_URL, YEROSTI_ADMIN_PAROL, YEROSTI_XARITA_USLUB
mkdir -p zaxira && sudo chown 10001 zaxira   # konteyner foydalanuvchisi (uid 10001) yoza olsin
docker compose up -d --build
docker compose ps              # hammasi "healthy" bo'lishi kerak
curl -s https://$DOMEN/api/v1/salomatlik
```

`salomatlik` javobi: `holat`, `baza`, `skan_papka_yoziladi`, qayta hisob navbati va ishchi oxirgi marta qachon tirik
bo'lgani (`ishchi_oxirgi_yurak_s`). Unda sir yo'q, kirishsiz ochiladi.

**Birinchi kirish.** `YEROSTI_ADMIN_PAROL` bo'sh qolsa, parol server jurnalida bir marta chiqadi:
`docker compose logs server | grep -A2 "BIRINCHI"`. Kirgach, dala qurilmalari uchun token portaldagi
«Dala qurilmalari» bo'limida yaratiladi.

Tasvir yig'ilishida o'zini tekshiradi: `yerosti-tahlil versiya` va python kutubxonalari ishga tushmasa, yig'ish to'xtaydi.

## 2a. Umumiy serverda — mavjud Caddy ortida

**Ishlab turgan joylash (SERVER_IP): `ornatish/server/`** — `trace4d.example.uz` (portal, QR sahifalari) va
`trace4dapi.example.uz` (faqat `/api/*`: iPhone ilovasi va tashqi tizimlar). Bitta buyruq: `ornatish/server/joylash.sh`;
tuzilish, parol joyi, zaxira va qaytarish — `ornatish/server/JOYLASHUV.md`. Quyidagi umumiy ko'rsatma boshqa serverlar uchun.

Serverda boshqa saytlar bilan birga bitta Caddy ishlayotgan bo'lsa, TRACE4D ning o'z proksisi kerak emas:

```bash
cp .env.example .env && nano .env         # YEROSTI_TASHQI_URL=https://<domen> albatta
docker compose -f docker-compose.yml -f docker-compose.umumiy.yml up -d --build
```

Server faqat `127.0.0.1:8342` da tinglaydi. Host Caddyfile ga blok qo'shing va `caddy reload`:

```
trace4d.example.uz {
	encode zstd gzip
	request_body {
		max_size 12MB
	}
	header Strict-Transport-Security "max-age=31536000; includeSubDomains"
	reverse_proxy 127.0.0.1:8342 {
		header_up X-Real-IP {remote_host}
	}
}
```

`X-Real-IP` ga server faqat `YEROSTI_PROKSI_TARMOQ` dan ishonadi; override faylida u compose tarmog'i shlyuzi
(`172.29.10.1/32`) — host Caddy dan kelgan ulanish shundan ko'rinadi. Kirish cheklovi shunda har mijozga alohida ishlaydi.
Tekshirish: `curl -s https://<domen>/api/v1/salomatlik`. Override fayli bu mashinada Docker yo'qligi sababli
`docker compose config` bilan tekshirilmagan — serverda birinchi marta ishga tushirishda `docker compose ... config` ni ko'ring.

## 2b. Dala yo'riqnomasi

Brigada uchun qisqa yo'riqnoma — `DALA_YORIQNOMA.md` (geodezik asos, skan, quvur tasdig'i T-031, Emlid Flow CSV, xatolar).

## 3. TLS

* Ochiq internetda domen DNS da serverga qaragan bo'lsa, Caddy sertifikatni o'zi oladi.
* Yopiq data markazda `Caddyfile` ga quyidagilardan birini qo'shing:
  * `tls internal`: Caddy'ning o'z CA si, brauzerlarga CA ni o'rnatish kerak;
  * `tls /sertifikat/yerosti.crt /sertifikat/yerosti.key`: data markaz sertifikati. Sertifikat papkasini
    `proksi` xizmatiga `volumes` orqali ulang.

## 4. Xarita (DM-01)

Portal skriptlari va MapLibre serverning o'zidan beriladi (`web/vendor`, xeshlari `web/vendor/MANBA.md` da). CSP
tashqi skriptga ruxsat bermaydi. Xarita asosi `YEROSTI_XARITA_USLUB` bilan sozlanadi:

* `yoq`: asos xaritasiz, to'liq oflayn rejim (standart). Tarmoqlar fon ustida chiziladi.
* Mahalliy plitka serveri uslubi, masalan `https://xarita.ichki.uz/styles/positron`.
* `https://tiles.openfreemap.org/styles/positron`: tashqi manba. CSP faqat shu manzilga ochiladi.

## 5. Mustaqil qayta hisob (DM-02)

Telefon muhr jurnalini (`jurnal.ymj`), `mesh.ply` ni va imzolangan manifestni yuklaydi. Muhr TASDIQLANGAN bo'lsa,
server navbatga ish qo'yadi. Ishchi quyidagilarni bajaradi:

1. Zanjirni noldan tiklaydi. PLY jurnalda muhrlangan fayl ekanini xesh va hajm bo'yicha tekshiradi.
2. Har georeferens juftini xom NMEA (GGA) bilan solishtiradi va T-103 bo'yicha RASMIY ekanini qayta baholaydi.
3. Georeferensni juftlardan qayta hisoblaydi. Telefonniki bilan farq 1 mm va 0,001° dan oshmasligi kerak.
4. Quvurlarni PLY dan qayta aniqlaydi. O'q farqi 2 sm dan, diametr farqi 10 mm dan oshmasligi kerak.

Xulosa: **MOS**, **FARQ** (sabablari raqam bilan) yoki **XATO** (fayl o'qilmadi). Natija portaldagi obyekt panelida
ko'rinadi, «3D ko'rish» esa `/3d?tahlil=ID` ni ochadi (nuqta buluti, quvurlar, masofa, kesim). Admin qayta hisoblatishi
mumkin: `POST /api/v1/tahlil/{id}/qayta`.

## 5a. Ijro hujjati, ulashish, tarix (TALABLAR 14)

* **Ijro hujjati (IH)**: portalda obyekt panelidagi «Ijro hujjatini yaratish». Server A3 PDF yasaydi: reja, koordinatalar
  katalogi va kesishuvlar, har liniyaga bo'ylama profil, sifat va kelib chiqish varag'i. Har varaqda shtamp, imzo joylari,
  `YRS-YYYY-NNNNNN` raqami va QR. Fayl `malumot` hajmida (`skanlar/hujjat/`), xeshi bazada. Admin hujjatni sabab bilan
  bekor qiladi (o'chirilmaydi).
* **QR tekshiruvi**: QR `YEROSTI_TASHQI_URL/t/<kod>` ga olib boradi. Sahifa kirishsiz ochiladi va koordinata
  ko'rsatmaydi: raqam, holat, PDF xeshi, muhr va qayta hisob holati. `YEROSTI_TASHQI_URL` to'ldirilmasa, QR so'rov
  kelgan manzilni oladi: ichki IP yoki `localhost` bilan chop etilgan hujjatni tashqaridan tekshirib bo'lmaydi.
* **Loyiha DXF (IH-07)**: LINE, POLYLINE, LWPOLYLINE, koordinatalar WGS84 / UTM da, ≤ 10 MB. Obyektdan 1 km dan uzoq
  loyiha rad etiladi (zona yoki koordinata tizimi xatosi). Balandlik Boltiq tizimida bo'lsa, faqat gorizontal og'ish
  hisoblanadi.
* **Ulashish (UL)**: muddatli havola (`/u/<token>`, 1…365 kun). Faqat bitta obyekt, faqat o'qish: PDF, DXF, CSV, 3D.
  Token bazada xesh ko'rinishida, bekor qilinsa darhol 410. Sahifalar `noindex` va `no-referrer`.
* PDF shriftlari tasvirdagi `fonts-dejavu-core` dan. Boshqa joyda ishga tushirilsa: `YEROSTI_SHRIFT_PAPKA`.

## 5b. Mahalliy tizim va Boltiq balandligi (TALABLAR 15, LK)

Shahar hujjatni o'z koordinata tizimida va Boltiq balandligida qabul qiladi [ГОСТ Р 51872 5.4, 6.10]. Kalit (o'tish
parametrlari) kerak emas: har obyekt o'z punktlari bo'yicha lokalizatsiya qilinadi.

1. Portal → obyekt → "Geodezik asos" → "Punktlar": shahar tarmog'i yoki razbivka asosi katalogidan kamida 4 ta punkt
   (nomi; X; Y; H; sinf; manba). Punktlar obyektni o'rab tursin.
2. Har punkt kamida 30 s uzluksiz RTK FIX bilan o'lchanadi: iPhone ilovasida "Geodezik asos" ekrani yoki Emlid Flow
   ("All columns" CSV eksporti portalga import qilinadi; punkt nomlari katalogdagidek).
3. "Hisoblash": qoldiq gorizontalda ≤ 2 sm, vertikalda ≤ 4 sm bo'lsa lokalizatsiya yaroqli. "Batafsil" da LOO
   ustuni xato punktni ko'rsatadi: uni bekor qilib yoki qayta o'lchab, qayta hisoblang.
4. Har o'lchov kuni bitta ma'lum punktda tekshiruv o'lchovi (≤ 3 / 5 sm). Bu baza koordinatasi, antenna balandligi va
   mountpoint xatosini ushlaydi; tekshiruvsiz kun hujjatda "yaroqsiz" sababi bo'ladi.
5. Loyiha DXF va topoplan DXF mahalliy tizimda yuklanadi. DXF/CSV eksport standart holda mahalliy tizimda
   (`?tizim=utm` bilan WGS84 / UTM).

## 5c. Ortofoto va sun'iy yo'ldosh surati (TALABLAR 16, SY)

Surat o'lchov aniqligini oshirmaydi: u kontekst va metrlab xatoni ko'zda ushlash uchun. O'lchov suratga moslanmaydi.

* **Shahar ortofotosi (tavsiya).** Kadastr agentligi yoki shahar GIS bo'limidan ortofotoplan oling. QGIS da: Processing
  → Raster tools → "Generate XYZ tiles (MBTiles)", format PNG yoki JPG, zoom 15…20. Faylni `malumot` hajmiga qo'ying,
  `.env` da `YEROSTI_ORTOFOTO=/malumot/ortofoto.mbtiles` va pasportdagi aniqlikni `YEROSTI_ORTOFOTO_ANIQLIK_M` ga
  yozing. Plitkalar faqat portalga kirganlarga beriladi, tashqariga so'rov ketmaydi.
* **Tashqi sun'iy yo'ldosh (ixtiyoriy).** `YEROSTI_SUNIY_URL` (https, {z}/{x}/{y}), `YEROSTI_SUNIY_ATRIBUTSIYA`,
  `YEROSTI_SUNIY_ANIQLIK_M`. Litsenziya sizning zimmangizda: Esri World Imagery tijoriy ilovada ArcGIS hisobi va kalit
  talab qiladi, aniqligi 4–10 m. Har plitka so'rovi qaysi hudud ko'rilayotganini provayderga ko'rsatadi.
* iPhone ilovasi Apple sun'iy yo'ldosh suratini MapKit orqali ko'rsatadi, sozlash kerak emas.

## 5d. Tashqi LiDAR importi (TALABLAR 19, LD)

SLAM skaner yoki boshqa qurilma buluti (LAS/PLY) portaldan yuklanadi, `ishchi` uni UTM PLY ga keltirib `yerosti-tahlil aniqla`
bilan quvurlarni topadi va SKAN liniyalar yaratadi. Alohida sozlama yo'q; faqat **yadro CLI yangi bo'lsin**: tasvirni qayta
yig'ing (`docker compose build`), chunki eski `yerosti-tahlil` da `aniqla` buyrug'i yo'q. Katta fayl (≥ 100 MB) ishchida bir
necha daqiqa oladi; `YEROSTI_TAHLIL_VAQT_S` yetarli bo'lsin.

## 6. Zaxira va tiklash (DM-05)

Zaxira xizmati har `YEROSTI_ZAXIRA_SOAT` soatda `yerosti-YYYYmmdd-HHMMSS/` papka yaratadi. Ichida:

* `yerosti.db`: server ishlab turganda ham izchil onlayn nusxa;
* `skanlar/`: skan va tahlil fayllari, ijro hujjatlari (`hujjat/`), loyiha DXF lari (`loyiha/`) va topoplanlar (`topo/`);
* `MANIFEST.sha256`: `sha256sum -c` bilan ham tekshiriladi;
* `zaxira.json`: jadval sonlari va hajm.

Zaxira avval `.yarim` nom bilan yig'iladi va oxirida atomik nomlanadi.

```bash
# qo'lda zaxira va tekshirish
docker compose exec zaxira python3 zaxira.py yarat --papka /zaxira
docker compose exec zaxira python3 zaxira.py tekshir /zaxira/yerosti-20260927-020000

# TIKLASH: xizmatlarni to'xtatib, tanlangan zaxiradan (avval o'zi tekshiradi, buzilgan bo'lsa rad etadi)
docker compose stop server ishchi zaxira
docker compose run --rm --no-deps zaxira python3 zaxira.py tikla /zaxira/yerosti-20260927-020000 \
    --baza /malumot/yerosti.db --skanlar /malumot/skanlar --majburiy
docker compose up -d
```

Tiklash sinovi: `python3 sinov/zaxira_sinov.py`. U vaqtinchalik papkada zaxira yaratadi, tekshiradi, tiklaydi va
tiklangan bazada serverni ko'taradi. Keyin asl parol bilan kirishni sinaydi va buzilgan zaxirani ushlashini tekshiradi.

## 7. Yangilash

```bash
docker compose up -d --build     # hajmlar saqlanadi; baza sxemasi server ishga tushganda o'zi yangilanadi
```

## 8. Kengayish (DM-06)

Hozir SQLite (WAL), baza qatlami bitta modulda (`yerosti_baza.py`). Shahar yoki viloyat miqyosida, ko'p yozuvchi ishchi
yoki fazoviy so'rovlar kerak bo'lganda PostgreSQL + PostGIS ga o'tiladi. Bu O-10 savoli, qaror shartnomada. API o'zgarmaydi.

## 9. Xavfsizlik (DM-07)

* TLS va HSTS (proksi).
* Tokenlar va parollar bazada xesh ko'rinishida.
* Kirish cheklovi: bir IP dan daqiqada 8 urinish. `X-Real-IP` ga **faqat** proksi manzilidan ishoniladi
  (`YEROSTI_PROKSI_TARMOQ`), aks holda uni almashtirib cheklovni aylanib o'tib bo'lmaydi.
* Qattiq CSP: skript faqat o'zidan, `eval` yo'q.
* Fayllar ruxsat bo'yicha beriladi: 3D bulutni faqat portal foydalanuvchisi oladi, dala tokeni ham, kirishsiz so'rov ham
  ololmaydi.
* Muhr urinishlari, jumladan BUZILGANlari, o'chmaydi. Amallar jurnali saqlanadi.
* Konteynerlar root emas (uid 10001).
* Kirishsiz sahifalar (`/t/`, `/u/`): bir IP dan daqiqada 60 (tekshirish) va 240 (ulashish) so'rov; tekshirish kodi
  96 bit tasodifiy, ulashish tokeni 192 bit.

**Holat (2026-09-27):** `docker compose config` tekshirilgan. Tasvirning o'zi hali haqiqiy serverda yig'ilmagan, chunki
bu ish kompyuterida Docker demoniga ruxsat yo'q. Birinchi yig'ish maqsadli serverda bo'ladi, Dockerfile ichidagi
o'z-o'zini tekshirish shu yerda isbotlaydi.
