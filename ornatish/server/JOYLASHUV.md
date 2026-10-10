# TRACE4D — serverdagi joylashuv (trace4d.example.uz)

Server `SERVER_IP` (Ubuntu 26.04), unda 20 dan ortiq boshqa loyiha turadi. **TRACE4D ularning birortasiga tegmaydi**:
o'z tarmog'i, o'z hajmi, tashqariga port ochmaydi, umumiy Caddyfile da faqat o'z blokini yozadi.

## Domenlar

| Manzil | Nima | Qayerga |
|---|---|---|
| `https://trace4d.example.uz` | portal (TRACE4D Cloud), 3D (TRACE4D View), QR sahifalari `/t/`, `/u/`, `/q/` | `trace4d:8342` |
| `https://trace4dapi.example.uz` | faqat `/api/*`: iPhone ilovasi (TRACE4D Scan) va tashqi tizimlar | `trace4d:8342`; boshqa yo'l → portalga 302 |

Hujjatlardagi QR `YEROSTI_TASHQI_URL=https://trace4d.example.uz` bilan yasaladi. iPhone ilovasidagi server manzili:
`https://trace4dapi.example.uz`. Sertifikatlar Let's Encrypt, Caddy o'zi oladi va yangilaydi.

## Tuzilish

| Narsa | Qiymat |
|---|---|
| Manba | `/opt/trace4d` (oldingi versiya `/opt/trace4d.eski`) |
| Compose | `ornatish/server/docker-compose.server.yml`, loyiha nomi **`trace4d`** |
| Konteynerlar | `trace4d` (API + portal), `trace4d-ishchi` (DM-02 qayta hisob), `trace4d-zaxira` (DM-05) — uid 10001, `read_only`, `cap_drop: ALL` |
| Hajm | `trace4d_malumot` → baza, skanlar, hujjatlar |
| Tarmoq | `trace4d_ichki` — unga faqat `caddy` ulanadi; `X-Real-IP` faqat shu tarmoqdan qabul qilinadi |
| Sozlama | `/etc/trace4d/trace4d.env` (root 600): tashqi manzil va **birinchi admin paroli**; `/etc/trace4d/tarmoq.env` |
| Caddy | umumiy Caddyfile (`TRACE4D_CADDYFILE`, sukut `/opt/caddy/Caddyfile`), blok `# >>> TRACE4D` … `# <<< TRACE4D` (manba `Caddyfile.trace4d`) |
| Qorovul | `trace4d-caddy-qorovul.timer` (5 daqiqa): blok yo'qolsa yoki manbadan farq qilsa joyida tiklaydi, tarmoq uzilsa ulaydi; m17 va rasta bilan bir xil qulf |
| Zaxira | `trace4d-zaxira`: har 24 soatda `/var/backups/trace4d` (baza + skanlar + SHA-256 manifest, 14 ta) |

## Joylash va yangilash (mahalliy kompyuterdan, bitta buyruq)

```bash
YEROSTI/ornatish/server/joylash.sh
```

Paket (baza, parol, skan, sinov va `Yadro/.build` siz) → yuklash → serverda toza almashtirish va yig'ish (fonda, SSH uzilsa ham
to'xtamaydi) → konteynerlar sog'lom → qorovul blokni yozadi (`caddy validate` o'tmasa fayl qaytariladi) → tashqaridan
portal 200 va API `holat: ok` → qo'shni saytlarning javob kodlari joylashdan oldingi bilan solishtiriladi.
Yangi versiya sog'lom bo'lmasa server **o'zi eski versiyaga qaytadi**. Jurnal: serverda `/root/trace4d-yuklash/yangilash.log`.

## Kundalik buyruqlar (serverda)

```bash
cd /opt/trace4d && C="docker compose -f ornatish/server/docker-compose.server.yml"
$C ps                                        # holat (hammasi healthy)
docker logs --tail 50 trace4d                # server jurnali
journalctl -t trace4d-caddy --since today    # qorovul yozuvlari
ls -la /var/backups/trace4d                  # zaxiralar
```

**Birinchi kirish:** login `admin`, parol `/etc/trace4d/trace4d.env` dagi `YEROSTI_ADMIN_PAROL`. Parol faqat baza bo'sh
bo'lganda ishlatiladi. Portalda parol almashtirish oynasi yo'q — yangi tasodifiy parol serverda:
`docker exec trace4d python3 yerosti_server.py --parol-yangila admin` (ekranga chiqaradi; env fayldagi eski parol endi ishlamaydi).
Dala qurilmalari tokeni portaldagi «Dala qurilmalari» bo'limida.
