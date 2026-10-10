#!/bin/bash
# SERVERDA ishlaydi — joylash.sh uni fonda (setsid nohup) chaqiradi: SSH uzilsa ham to'xtamaydi.
#   /opt/trace4d.yangi (yangi paket) → /opt/trace4d ; oldingi versiya → /opt/trace4d.eski
# Baza, skanlar va hujjatlar trace4d_malumot hajmida — papka almashtirish ularga TEGMAYDI.
# Natija belgisi: /root/trace4d-yuklash/tayyor yoki /root/trace4d-yuklash/xato
set -u
YANGI=/opt/trace4d.yangi JORIY=/opt/trace4d ESKI=/opt/trace4d.eski BELGI=/root/trace4d-yuklash E=/etc/trace4d
CF=${TRACE4D_CADDYFILE:-/opt/caddy/Caddyfile}
C="docker compose -f ornatish/server/docker-compose.server.yml"
mkdir -p "$BELGI"; rm -f "$BELGI/tayyor" "$BELGI/xato"

xato() { echo "✗ $*"; echo "$*" > "$BELGI/xato"; exit 1; }
soglom() {                      # server va ishchi healthy bo'lguncha (≤ 5 daqiqa)
  for _ in $(seq 1 75); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' trace4d 2>/dev/null)" = healthy ] &&
    [ "$(docker inspect -f '{{.State.Health.Status}}' trace4d-ishchi 2>/dev/null)" = healthy ] && return 0
    sleep 4
  done
  return 1
}
qaytar() {                      # yangi versiya ishlamadi
  if [ -d "$ESKI" ]; then
    echo "▸ eski versiyaga qaytarish"
    rm -rf "$JORIY.xato"; mv "$JORIY" "$JORIY.xato"; mv "$ESKI" "$JORIY"
    (cd "$JORIY" && $C up -d --build)
    xato "$1 — eski versiya qaytarildi (yangisi: $JORIY.xato)"
  fi
  (cd "$JORIY" && $C stop) >/dev/null 2>&1     # birinchi o'rnatish: yarim holatda qoldirmaymiz, hajm saqlanadi
  xato "$1 — birinchi o'rnatish to'xtatildi (ma'lumot hajmi saqlandi)"
}

[ -d "$YANGI" ] || xato "$YANGI topilmadi"
[ -f "$CF" ] || xato "umumiy Caddyfile topilmadi: $CF"
docker inspect caddy >/dev/null 2>&1 || xato "caddy konteyneri topilmadi"
echo "▸ boshlandi: $(date)"

echo "▸ diskdagi bo'sh joy"
DR=$(docker info -f '{{.DockerRootDir}}' 2>/dev/null); [ -n "$DR" ] || DR=/var/lib/docker
BOSH=$(df -BG --output=avail "$DR" | tail -1 | tr -dc '0-9')
echo "  $DR: ${BOSH:-0} GB bo'sh"
[ "${BOSH:-0}" -ge 6 ] || xato "diskda joy kam (${BOSH:-0} GB, kamida 6 GB kerak) — boshqa dasturlarga zarar bermaslik uchun to'xtatildi"

echo "▸ sozlama, tarmoq, zaxira papkasi"
(umask 077; mkdir -p "$E")
if [ ! -f "$E/trace4d.env" ]; then
  (umask 077
   P=$(python3 -c 'import secrets; print(secrets.token_urlsafe(12))')
   printf '%s\n' \
     "# TRACE4D server sozlamalari: yangilash.sh birinchi o'rnatishda yozdi, keyin tegmaydi" \
     "YEROSTI_TASHQI_URL=https://trace4d.example.uz" \
     "YEROSTI_ADMIN_PAROL=$P" \
     "YEROSTI_XARITA_USLUB=yoq" \
     "YEROSTI_ZAXIRA_SOAT=24" \
     "YEROSTI_ZAXIRA_SAQLASH=14" > "$E/trace4d.env")
  echo "  birinchi o'rnatish: $E/trace4d.env yaratildi (birinchi admin paroli shu faylda)"
fi
docker network inspect trace4d_ichki >/dev/null 2>&1 || docker network create trace4d_ichki >/dev/null || xato "trace4d_ichki tarmog'i yaratilmadi"
SUB=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' trace4d_ichki | awk '{print $1}')
[ -n "$SUB" ] || xato "trace4d_ichki pastki tarmog'i aniqlanmadi"
(umask 077; echo "YEROSTI_PROKSI_TARMOQ=$SUB" > "$E/tarmoq.env")
echo "  trace4d_ichki: $SUB (X-Real-IP faqat shu tarmoqdan qabul qilinadi)"
mkdir -p /var/backups/trace4d && chown 10001:10001 /var/backups/trace4d && chmod 750 /var/backups/trace4d

echo "▸ almashtirish"
if [ -d "$JORIY" ]; then rm -rf "$ESKI"; mv "$JORIY" "$ESKI"; fi
mv "$YANGI" "$JORIY"
cd "$JORIY" || xato "cd $JORIY"

echo "▸ yig'ish va ishga tushirish (birinchi marta Swift tasviri yuklanadi, yadro yig'iladi)"
$C up -d --build || qaytar "yig'ish yoki ishga tushirish yiqildi"
soglom || qaytar "konteynerlar 5 daqiqada sog'lom bo'lmadi"

echo "▸ qorovul: Caddy bloki va tarmoq"
install -m 755 ornatish/server/trace4d-caddy-qorovul /usr/local/sbin/
install -m 644 ornatish/server/trace4d-caddy-qorovul.service ornatish/server/trace4d-caddy-qorovul.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now trace4d-caddy-qorovul.timer >/dev/null 2>&1
systemctl start trace4d-caddy-qorovul.service || xato "Caddy qorovuli xato bilan tugadi: journalctl -t trace4d-caddy"
grep -q '^# >>> TRACE4D' "$CF" || xato "Caddy bloki yozilmadi: journalctl -t trace4d-caddy"
docker inspect -f '{{json .NetworkSettings.Networks}}' caddy | grep -q '"trace4d_ichki"' || xato "caddy trace4d_ichki ga ulanmadi"

# Faqat TRACE4D ning osilgan eski tasvirlari (boshqa loyihalarnikiga tegilmaydi)
docker image prune -f --filter dangling=true --filter label=com.docker.compose.project=trace4d >/dev/null 2>&1 || true
echo "✓ tayyor: $(date)"
date > "$BELGI/tayyor"
