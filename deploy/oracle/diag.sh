#!/usr/bin/env bash
# Ses sunucusu (LiveKit) ve bağlantı testi. update.sh her çalıştığında (5 dakikada bir) çağırır;
# sonuç panelde "Ses sunucusu testi" bölümünde görünür.
set -uo pipefail
ROOT=/opt/trlive
ENVD=$ROOT/env
STATE=$ROOT/state
OUT=$STATE/diag.txt
COMPOSE="docker compose -p trlive -f $ROOT/src/deploy/oracle/compose.yml --env-file $ENVD/compose.env"
DOMAIN=$(tr -d ' \n\r' < "$ENVD/domain" 2>/dev/null)
ok() { echo "✅ $*"; }
bad() { echo "❌ $*"; }
{
  echo "Test zamanı: $(date '+%F %H:%M:%S')"
  echo
  echo "== Servisler =="
  $COMPOSE ps --format '{{.Service}}: {{.State}} {{.Status}}' 2>&1 || bad "docker compose okunamadı"
  echo
  echo "== LiveKit (ses sunucusu) =="
  r=$(curl -s -m 5 http://127.0.0.1:7880 2>&1)
  if [ "$r" = "OK" ]; then ok "LiveKit çalışıyor (iç adres)"; else bad "LiveKit iç adresten yanıt vermiyor: ${r:0:120}"; fi
  r=$(curl -s -m 8 --resolve "lk.$DOMAIN:443:127.0.0.1" "https://lk.$DOMAIN" 2>&1)
  if [ "$r" = "OK" ]; then ok "https://lk.$DOMAIN sertifikası ve yönlendirmesi tamam"; else bad "https://lk.$DOMAIN çalışmıyor (sertifika/Caddy): ${r:0:160}"; fi
  grep -E '^\s*(node_ip|use_external_ip|udp_port|tcp_port):' "$ENVD/livekit.yaml" 2>/dev/null | sed 's/^ */  ayar: /'
  echo
  echo "== Dinlenen portlar =="
  ss -lntup 2>/dev/null | grep -E ':(443|7880|7881|7882)\b' | awk '{print "  " $1 " " $5}' | sort -u
  echo
  echo "== Güvenlik duvarı =="
  if systemctl is-active --quiet firewalld 2>/dev/null; then
    p=" $(firewall-cmd --list-ports 2>/dev/null) "
    echo "  firewalld açık portlar:$p"
    for need in 80/tcp 443/tcp 7881/tcp 7882/udp; do
      if echo "$p" | grep -q " $need "; then ok "$need açık"; else bad "$need KAPALI"; fi
    done
  else
    for need in tcp:443 tcp:7881 udp:7882; do
      proto=${need%%:*}; port=${need##*:}
      if iptables -S INPUT 2>/dev/null | grep -qE -- "-p $proto .*--dport $port .*-j ACCEPT"; then ok "$port/$proto açık"; else echo "  ? $port/$proto (iptables kuralı bulunamadı)"; fi
    done
  fi
  echo "  Not: Oracle panelindeki Security List'te de 7881/TCP ve 7882/UDP açık olmalı."
  echo
  echo "== LiveKit kaydı (son satırlar) =="
  $COMPOSE logs --no-color --tail 25 livekit 2>&1 | cut -c1-220
  echo
  echo "== Caddy hataları (son) =="
  $COMPOSE logs --no-color --tail 200 caddy 2>&1 | grep -iE 'error|fail' | tail -n 8 | cut -c1-220
} > "$OUT.tmp" 2>&1
mv "$OUT.tmp" "$OUT"
