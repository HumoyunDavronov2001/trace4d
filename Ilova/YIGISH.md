# TRACE4D Scan — iPhone ilovasini yig'ish va o'rnatish (Mac shart emas)

Kerak: **iPhone Pro yoki Pro Max** (LiDAR), USB kabel, **Apple ID**.
Shu kompyuterda tayyor: Swift 6.4 (`~/build/swift64`), xtool 1.20.1 (`~/build/xtool/xtool`), usbmuxd.

## Bir martalik (o'zingiz bajarasiz — Apple ID paroli faqat Apple'ga yuboriladi)

1. **Xcode 27** ni brauzerda, Apple ID bilan kirib yuklab oling:
   https://developer.apple.com/download/all/?q=Xcode → `Xcode_27….xip` (~ bir necha GB).
2. Sozlash:
   ```bash
   PATH=~/build/swift64/usr/bin:$PATH ~/build/xtool/xtool setup
   ```
   - kirish usuli: `1` — oddiy Apple ID (bepul; ilova 7 kunda qayta o'rnatiladi) yoki
     `0` — App Store Connect API kaliti ($99/yil dasturchi hisobi; 1 yil).
   - so'ralganda `.xip` fayl yo'lini kiriting — xtool iOS SDK ni o'zi chiqaradi.

## Har safar

3. iPhone'ni USB bilan ulang → telefonda «Bu kompyuterga ishonasizmi?» → **Ishonish**.
   Agar qurilma ko'rinmasa: `sudo systemctl start usbmuxd`.
4. Yig'ish va o'rnatish:
   ```bash
   cd <repo>/Ilova
   PATH=~/build/swift64/usr/bin:$PATH ~/build/xtool/xtool dev
   ```
5. Birinchi marta: iPhone → Sozlamalar → Umumiy → VPN va qurilmalar boshqaruvi → dasturchi sertifikatiga ishonish.

## Sinovlar (Linuxda, iPhone'siz)

```bash
cd <repo>/Yadro && ~/build/swift64/sw test   # yadro: 111 test + 2 atayin skip (to'plam yozuvchi, o'lchov)
cd <repo> && python3 sinov/server_sinov.py              # server: 157 tekshiruv
cd <repo> && python3 sinov/ijro_sinov.py                # ijro hujjati: 61 tekshiruv
cd <repo> && python3 sinov/tasdiq_sinov.py              # quvur tasdig'i (T-031): 18 tekshiruv
cd <repo> && python3 sinov/las_sinov.py                 # tashqi LiDAR (LD-02): 16 tekshiruv
cd <repo> && python3 sinov/lokal_sinov.py               # lokalizatsiya: 28 tekshiruv
cd <repo> && python3 sinov/zaxira_sinov.py              # zaxira: 15 tekshiruv
```

## Dala sozlamasi (ilova ichida)

- Sozlamalar → server manzili va **dala tokeni** (portal → «Dala qurilmalari»).
- Ulanish → «Emlid Reach (Bluetooth MFi)» — avval Emlid Flow'da RX2 ni juftlang va NMEA oqimini yoqing.
- NTRIP → caster, login, parol, «Eng yaqin mountpointlar».
- Antenna ofseti (skanerlash dastagida o'lchab) — georeferens aniqligi shunga bog'liq (T-095).
