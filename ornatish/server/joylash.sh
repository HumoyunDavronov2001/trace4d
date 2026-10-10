#!/bin/bash
# TRACE4D ni serverga JOYLASH yoki YANGILASH — mahalliy kompyuterdan:   YEROSTI/ornatish/server/joylash.sh
# Paket → yuklash → serverda toza almashtirish + yig'ish (fonda) → sog'liq → tashqaridan tekshirish →
# qo'shni saytlar javobi joylashdan oldingi bilan solishtiriladi. Xato bo'lsa server o'zi eski versiyaga qaytadi.
set -eu
SERVER=${TRACE4D_SERVER:?TRACE4D_SERVER=root@SERVER_IP berilishi kerak}
ILDIZ=$(cd "$(dirname "$0")/../.." && pwd)
NOM=$(basename "$ILDIZ")
OTA=$(dirname "$ILDIZ")
mkdir -p "$HOME/.cache"
T=$(mktemp -d "$HOME/.cache/trace4d-joylash.XXXXXX"); trap 'rm -rf "$T"' EXIT     # /tmp to'lib qolishi mumkin
ssh_() { ssh -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=15 "$SERVER" "$@"; }
CF=${TRACE4D_CADDYFILE:-/opt/caddy/Caddyfile}
PORTAL=https://trace4d.example.uz
API=https://trace4dapi.example.uz

echo "▸ 1/5 paket"
MODULLAR=$(cd "$OTA" && ls -d "$NOM"/yerosti_*.py)
tar czf "$T/trace4d-manba.tgz" --exclude='Yadro/.build' --exclude='__pycache__' -C "$OTA" \
  "$NOM/Dockerfile" "$NOM/.dockerignore" "$NOM/zaxira.py" "$NOM/web" "$NOM/Yadro" "$NOM/ornatish/server" $MODULLAR \
  "$NOM/sinov/ijro_sinov.py" "$NOM/sinov/lokal_sinov.py" "$NOM/sinov/tasdiq_sinov.py" "$NOM/sinov/las_sinov.py"
if tar tzf "$T/trace4d-manba.tgz" | grep -qE '\.db($|-)|KIRISH|/\.env$|/skanlar/|/sinov/(toplam|server_sinov)|/\.build/'; then
  echo "✗ paketda baza, parol, skan yoki yig'ish qoldig'i bor — to'xtadim"; exit 1
fi
echo "  $(du -h "$T/trace4d-manba.tgz" | cut -f1), $(tar tzf "$T/trace4d-manba.tgz" | wc -l) fayl"

echo "▸ 2/5 qo'shni saytlar javobi (oldin)"
ssh_ "grep -E '^[^#[:space:]][^{]*\{[[:space:]]*\$' $CF" | tr -d '{' | tr ',' '\n' | sed -E 's#^[[:space:]]*(https?://)?##; s#[[:space:]]+$##' \
  | grep -E '^[a-z0-9.-]+\.[a-z]{2,}$' | grep -vE '^trace4d(api)?\.example\.uz$' | sort -u > "$T/domenlar" || true
holatlar() { while read -r d; do printf '%s %s\n' "$d" "$(curl -s -o /dev/null -m 15 -w '%{http_code}' "https://$d/" || true)"; done < "$T/domenlar"; }
holatlar > "$T/oldin"
echo "  $(wc -l < "$T/oldin") domen yozildi"

echo "▸ 3/5 yuklash"
ssh_ "install -d -m 700 /root/trace4d-yuklash && rm -rf /opt/trace4d.yangi /opt/trace4d.yangi.tmp"
scp -o BatchMode=yes -q "$T/trace4d-manba.tgz" "$SERVER:/root/trace4d-yuklash/trace4d-manba.tgz"
ssh_ "mkdir /opt/trace4d.yangi.tmp && tar xzf /root/trace4d-yuklash/trace4d-manba.tgz -C /opt/trace4d.yangi.tmp \
      && mv /opt/trace4d.yangi.tmp/$NOM /opt/trace4d.yangi && rmdir /opt/trace4d.yangi.tmp"

echo "▸ 4/5 serverda almashtirish va yig'ish (fonda, SSH uzilsa ham davom etadi)"
ssh_ "rm -f /root/trace4d-yuklash/tayyor /root/trace4d-yuklash/xato; \
      setsid nohup bash /opt/trace4d.yangi/ornatish/server/yangilash.sh > /root/trace4d-yuklash/yangilash.log 2>&1 < /dev/null &"
# Belgi FAYLI kutiladi — pgrep emas (pgrep -f o'z buyruq qatorini topib, abadiy kutib qoladi)
holat=kutish
for _ in $(seq 1 240); do                     # ≤ 40 daqiqa: birinchi marta Swift tasviri yuklanadi
  sleep 10
  holat=$(ssh_ "if [ -f /root/trace4d-yuklash/tayyor ]; then echo tayyor; elif [ -f /root/trace4d-yuklash/xato ]; then echo xato; else echo kutish; fi" 2>/dev/null || echo aloqa)
  if [ "$holat" = tayyor ] || [ "$holat" = xato ]; then break; fi
done
ssh_ "tail -6 /root/trace4d-yuklash/yangilash.log" || true
[ "$holat" = tayyor ] || { echo "✗ joylash tugamadi: $holat (to'liq: /root/trace4d-yuklash/yangilash.log)"; exit 1; }

echo "▸ 5/5 tashqaridan tekshirish"
k1=000
for _ in $(seq 1 24); do                      # birinchi marta Caddy sertifikat oladi — 2 daqiqagacha kutiladi
  k1=$(curl -s -o "$T/bosh.html" -m 20 -w '%{http_code}' "$PORTAL/" || true)
  [ "$k1" = 200 ] && break; sleep 5
done
[ "$k1" = 200 ] && grep -q '<title>TRACE4D Cloud' "$T/bosh.html" || { echo "✗ portal javobi $k1"; exit 1; }
k2=000
for _ in $(seq 1 24); do
  k2=$(curl -s -o "$T/sog.json" -m 20 -w '%{http_code}' "$API/api/v1/salomatlik" || true)
  [ "$k2" = 200 ] && break; sleep 5
done
[ "$k2" = 200 ] && python3 -c "import json,sys; sys.exit(0 if json.load(open('$T/sog.json')).get('holat') == 'ok' else 1)" \
  || { echo "✗ API sog'lik javobi $k2"; exit 1; }
k3=$(curl -s -o /dev/null -m 20 -w '%{http_code} %{redirect_url}' "$API/" || true)
echo "  200  $PORTAL/"
echo "  200  $API/api/v1/salomatlik (holat ok)"
echo "  $k3  $API/  (API dan tashqari yo'llar portalga yo'naltiriladi)"

holatlar > "$T/keyin"
if diff -q "$T/oldin" "$T/keyin" >/dev/null; then
  echo "  qo'shni saytlar: $(wc -l < "$T/keyin") ta, javoblar joylashdan oldingi bilan AYNAN bir xil"
else
  echo "  ⚠ qo'shni saytlar javobi o'zgardi (tarmoq tebranishi ham bo'lishi mumkin):"; diff "$T/oldin" "$T/keyin" | sed 's/^/    /' || true
fi
echo "✓ joylandi: $PORTAL  (API: $API)"
