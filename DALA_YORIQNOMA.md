# TRACE4D — dala yo'riqnomasi (brigada uchun, sinov versiyasi 2026-10-03)

Hujjat shahar tizimida va **topshirishga yaroqli** chiqishi uchun uchta shart bir vaqtda bajariladi:

1. **Geodezik asos** — obyektni o'rab turgan kamida 4 ta ma'lum punkt RTK bilan o'lchangan (lokalizatsiya, TALABLAR 15).
2. **Kunlik tekshiruv** — har ish kuni kamida bitta punktda tekshiruv o'lchovi (≤ 3 sm gorizontal, ≤ 5 sm vertikal).
3. **Quvur tasdig'i (T-031)** — skan qilingan har quvurning boshi, oxiri, har burilishi va har ≤ 50 m da vexa uchi quvur
   USTIDA turganda RTK FIX o'lchovi; skan o'qidan og'ish ≤ 5 sm gorizontal, ≤ 8 sm vertikal (TALABLAR 18).

Shartlardan biri bajarilmasa hujjat baribir chiqadi, lekin har varaqda **TOPSHIRISHGA YAROQSIZ** va sababi yoziladi.

## 1. Jihoz va sozlash

| Nima | Talab |
|---|---|
| iPhone Pro (LiDAR) | TRACE4D Scan ilovasi, server manzili va dala tokeni kiritilgan (portal → Tizim → Dala qurilmalari) |
| Emlid Reach RX2 | zaryad ≥ 50 %, vexa 2 m, Bluetooth ulangan (ilova → RTK ulanish) |
| Tuzatma (NTRIP) | UzPOS yoki o'z bazasi; **tuzatma yoshi ≤ 10 s**, FIX yashil bo'lmaguncha o'lchov boshlanmaydi |
| Antenna balandligi | vexa uzunligi + RX2 hujjatidagi fazaviy markaz ofseti; ilovada «Vexa + antenna, m» maydoni. **Xato balandlik hamma balandlikni buzadi** |
| Punktlar katalogi | shahar geodezik tarmog'i yoki razbivka asosi: nomi, X (shimol), Y (sharq), H (Boltiq) — portal yoki ilovada kiritiladi |

## 2. Ish kuni boshi: geodezik asos (LK)

1. Portal yoki ilovada punktlar ro'yxati bor-yo'qligini tekshiring (Loyiha → Geodezik asos).
2. Har punktda vexani belgining markaziga qo'yib, tik tutib **«O'lchash»** — 30 s uzluksiz FIX kerak. FIX uzilsa hisob
   qaytadan boshlanadi; bu normal.
3. Kamida 4 punkt o'lchangach **«Hisoblash»** (portal, admin/operator). Natija: yaroqli / yaroqsiz, qoldiqlar. Qoldig'i
   katta punkt LOO ustunida ko'rinadi — uni qayta o'lchang yoki katalog qiymatini tekshiring.
4. Har keyingi ish kuni kamida bitta punktda **«Tekshiruv»** o'lchovi. O'tmasa (≤ 3 / 5 sm dan katta): baza yoki
   mountpoint xato, antenna balandligi xato yoki punkt buzilgan. Avval shuni hal qiling, keyin skan qiling.

## 3. Skan

* Transheya ochiq, quvur ko'rinadi, ustida tuproq yo'q. Quvur bo'ylab 1–2 m masofada **sekin** yuring, kamera quvurga
  qaragan bo'lsin.
* Yuqori chiziqda RTK **FIX** yashil turishi kerak. FIX yo'qolsa qizil banner chiqadi: to'xtab kuting, yozish davom etadi,
  lekin shu kadrlar «past» bo'ladi.
* Tugatganda sifat qarori: RASMIY kadrlar ulushi ≥ 90 % yashil. 50 % dan kam bo'lsa «Bekor qilish» va qaytadan.
* Skan nuqtalari hujjatda **SKAN** sifatida chiqadi: ular quvur tasdig'isiz rasmiy hisoblanmaydi (4-bo'lim).

## 4. Quvur tasdig'i (T-031) — skan tugagach, transheya yopilmasidan

1. Ilovada **Loyiha → Quvur tasdig'i → «Quvur ustida o'lchash»**. Nomi (T1, T2 …), vexa uchi qayerda: «quvur ustida»
   (odatiy) yoki «ochiq uchida, o'qda» (quvur uchi ochiq bo'lsa, uchni markazga qo'yganda).
2. Vexa uchini quvurning **eng yuqori nuqtasiga** qo'ying, vexani tik tuting, **«Boshlash»** — 5 s uzluksiz FIX,
   kamida 5 epoxa. Tarqoqlik σ chegaradan oshsa (2 / 5 sm) ilova qabul qilmaydi: qaytadan.
3. Qayerda o'lchash shart: **boshi, oxiri, har burilish** (yo'nalish ≥ 3° o'zgargan joy), to'g'ri qismda **har ≤ 50 m**.
   Ilova yetishmayotgan joyni «Kerakli joylar» va kamchiliklar ro'yxatida ko'rsatadi (PK — pikitaj, metrda).
4. Natija darhol: **Chegarada** (yashil) yoki **CHEGARADAN TASHQARIDA** (qizil, sabab bilan). Qizil chiqsa:
   avval vexani tekshiring (tik, to'g'ri joy, balandlik), qayta o'lchang; yana qizil bo'lsa skan georeferensi shubhali —
   skanni takrorlang. Bitta qizil tasdiq butun liniyani **FARQ** qiladi.
5. Liniya holati «RTK tasdiqlangan» bo'lgach shu liniyaning SKAN nuqtalari hujjatga rasmiy kiradi.
6. Server bo'lmasa o'lchovlar telefonda saqlanadi, skan yuklanganda birga yuboriladi.

## 5. Emlid Flow bilan ishlash (ilova yo'q yoki ikkinchi odam)

* Loyiha koordinata tizimi **WGS84** (ellipsoid balandlik). Nuqta yig'ish: FIX, 5 s (tasdiq) yoki 30 s (nazorat punkti).
* Nuqta nomi: nazorat punkti uchun **katalogdagi nomi aynan** (Pp-112), tasdiq uchun T1, T2 …
* Description / Code: kunlik tekshiruv o'lchoviga **«tekshiruv»**, ochiq uchida o'qda o'lchangan tasdiqqa **«oq»**.
* Eksport: **CSV, «All columns»** (Name, Latitude, Longitude, Ellipsoidal height, Solution status, Lateral RMS, Elevation
  RMS, Averaging start/end, Samples, Description, Code).
* Portal: obyekt → **Asos** tabi → «O'lchovlar» → faylni tashlang (nazorat); obyekt → **Liniya** tabi → «RTK tasdiq CSV
  import» (tasdiq). Server FIX bo'lmagan va σ chegaradan oshgan qatorlarni rad etadi, sababini yozadi.

## 5a. SLAM skaner (CHCNAV, XGRIDS, LiGrip va h.k.) bilan ishlash

* Skanerning absolyut aniqligi (3–5 sm) bizning 2 sm talabdan yomon: uning buluti ham **SKAN**, 4-bo'limdagi quvur
  tasdig'i baribir shart. Tasdiqni RX2 vexa bilan (yoki skanerning o'z RTK vexasi FIX da, 5 s) oling.
* Eksport: **LAS siqilmagan** (LAZ bo'lsa CloudCompare yoki laszip bilan oching) yoki PLY; koordinata **UTM 42N (EPSG:32642),
  balandlik ellipsoid** — eng ishonchlisi. WGS84 bo'lsa X = uzunlik, Y = kenglik. Mahalliy tizimda bo'lsa obyekt avval
  lokalizatsiya qilingan bo'lsin.
* Portal: obyekt → **Liniya** tabi → «Tashqi LiDAR skan (LAS/PLY)»: fayl, koordinata, skaner nomi, e'lon qilingan
  aniqlik (sm), tarmoq turi. Server quvurlarni topib SKAN liniyalar yaratadi (bir necha daqiqa), natija 3D da ko'rinadi.
* Fayl ≤ 300 MB; katta bulutni skaner dasturida transheya atrofiga kesib oling (ko'cha, uylar kerak emas).

## 6. Yuklash va hujjat

* Wi-Fi da **«Yuklash»**: muhr jurnali, 3D mesh, quvur o'qlari, tasdiqlar, imzolangan muhr. Portalda skan «tayyor»,
  muhr «TASDIQLANGAN», qayta hisob «MOS» bo'lishi kerak.
* **Hujjat** tabi → «Ijro hujjatini yaratish». Har varaqdagi belgi: **TOPSHIRISHGA YAROQLI** yoki **YAROQSIZ** + sabablar
  (Sifat varag'i). QR orqali hujjat haqiqiyligi tekshiriladi, koordinata chiqmaydi.

## 7. Ko'p uchraydigan xatolar

| Belgi | Sabab | Nima qilish |
|---|---|---|
| Tekshiruv o'lchovi o'tmadi (≥ 3 / 5 sm) | baza/mountpoint xato, antenna balandligi, punkt buzilgan | mountpointni tekshiring, balandlikni qayta kiriting, boshqa punktda tekshiring |
| Lokalizatsiya «masshtab chegaradan tashqarida» | katalog boshqa birlikda yoki boshqa tizimda | katalogni geodeziya bo'limi bilan aniqlang |
| Tasdiq «CHEGARADAN TASHQARIDA» | vexa qiyshaygan, noto'g'ri joy (quvur yoni), skan georeferensi xato | qayta o'lchang; yana qizil bo'lsa skanni takrorlang |
| Liniya «qisman tasdiqlangan» | boshi/oxiri/burilish yoki 50 m oralig'i o'lchanmagan | kamchiliklar ro'yxatidagi PK larda o'lchang |
| Hujjat «lokalizatsiya qilinmagan» | punktlar yo'q yoki hisoblanmagan | 2-bo'lim |
| Hujjatda «tekshiruv o'lchovisiz ish kunlari» | o'sha kuni tekshiruv qilinmagan | keyingi kunlarga odat: ishni tekshiruvdan boshlang |

## 8. Tekshirish ro'yxati (bir kun)

- [ ] RX2 zaryadi, NTRIP ulangan, FIX yashil, tuzatma yoshi ≤ 10 s
- [ ] Antenna balandligi ilovada to'g'ri
- [ ] Nazorat punkti tekshiruvi o'tdi
- [ ] Skan: FIX saqlangan, RASMIY kadrlar ≥ 90 %
- [ ] Tasdiq: boshi, oxiri, burilishlar, har ≤ 50 m — hammasi yashil
- [ ] Yuklash tugadi: muhr TASDIQLANGAN, qayta hisob MOS
- [ ] Hujjat yaroqli, imzoga tayyor
