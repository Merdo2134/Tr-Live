#!/usr/bin/env bash
# TR Live tek sunucu kurulumu (Oracle Cloud Always Free; Ubuntu 22.04/24.04 ya da Oracle Linux 9; ARM ya da x86).
# Kurar: Docker, güvenlik duvarı kuralları, PostgreSQL, uygulama sunucusu, LiveKit (ses/görüntü), Caddy (HTTPS),
# yönetim paneli (/panel), günlük yedek ve otomatik güncelleme (GitHub main dalı 5 dakikada bir kontrol edilir).
# Tekrar çalıştırmak güvenlidir: eksik olanı tamamlar, sırları ve veritabanını korur.
#
# Kullanım:  sudo PANEL_PASSWORD='harf-ve-rakam' bash install.sh   (ilk kurulum)
#            sudo bash install.sh --apply                          (ayarları uygula, yeniden başlat)
set -euo pipefail
export HOME=${HOME:-/root}
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ROOT=/opt/trlive
SRC=$ROOT/src
ENVD=$ROOT/env
STATE=$ROOT/state
REPO=${TRLIVE_REPO:-https://github.com/Merdo2134/Tr-Live.git}
BRANCH=${TRLIVE_BRANCH:-main}
MODE=${1:-install}
PLACEHOLDER='BURAYA-EN-AZ-10-KARAKTER-SIFRE'
COMPOSE="docker compose -p trlive -f $SRC/deploy/oracle/compose.yml --env-file $ENVD/compose.env"

mkdir -p "$ENVD" "$STATE" "$ROOT/backups"
chmod 700 "$ENVD"
# Kayıt panelde de görünsün diye state/ altında.
exec > >(tee -a "$STATE/install.log") 2>&1
log() { echo "[trlive $(date '+%F %H:%M:%S')] $*"; }
console() { echo "$*" > /dev/console 2>/dev/null || true; echo "$*"; }
[ "$(id -u)" = 0 ] || { echo "root olarak çalıştırın (sudo)"; exit 1; }

# ---------- 1) Paketler (Ubuntu ya da Oracle Linux 9) ----------
if [ "$MODE" = install ]; then
  if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    # İlk açılışta otomatik güncellemeler apt kilidini tutar: beklenir.
    echo 'DPkg::Lock::Timeout "900";' > /etc/apt/apt.conf.d/99trlive
    for _ in $(seq 1 180); do
      fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1 || break
      sleep 5
    done
    log "Paketler kuruluyor (Ubuntu)"
    apt-get update -qq
    apt-get install -y -qq git curl ca-certificates psmisc >/dev/null
    if ! command -v docker >/dev/null; then
      log "Docker kuruluyor"
      curl -fsSL --retry 5 https://get.docker.com | sh >/dev/null
    fi
  elif command -v dnf >/dev/null; then
    log "Paketler kuruluyor (Oracle Linux)"
    dnf -y -q install git curl ca-certificates psmisc dnf-plugins-core >/dev/null
    if ! command -v docker >/dev/null; then
      log "Docker kuruluyor"
      dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null
      dnf -y -q install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
    fi
    # SELinux, konteynerlerin ayar dosyalarını okumasını engellemesin.
    if command -v setenforce >/dev/null; then
      setenforce 0 2>/dev/null || true
      sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
    fi
  else
    log "HATA: desteklenmeyen işletim sistemi (Ubuntu ya da Oracle Linux 9 gerekli)"; exit 1
  fi
  systemctl enable --now docker >/dev/null
  # Derleme sırasında bellek yetmezse diye 2 GB takas alanı.
  if ! swapon --show | grep -q /swapfile; then
    { fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none; } && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q /swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
fi

# ---------- 2) Kaynak kod ----------
if [ "$MODE" = install ] || [ ! -d "$SRC/.git" ]; then
  if [ -d "$SRC/.git" ]; then
    git -C "$SRC" fetch -q --depth 1 origin "$BRANCH" && git -C "$SRC" reset -q --hard "origin/$BRANCH"
  else
    log "Kod indiriliyor: $REPO"
    git clone -q --depth 1 -b "$BRANCH" "$REPO" "$SRC"
  fi
fi

# ---------- 3) Güvenlik duvarı (her açılışta trlive-firewall servisi de çalıştırır) ----------
bash "$SRC/deploy/oracle/firewall.sh"

# ---------- 4) Sırlar (bir kez üretilir, sonra korunur) ----------
rnd() { tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "$1" || true; }
if [ ! -f "$ENVD/secrets.env" ]; then
  log "Sırlar üretiliyor"
  cat > "$ENVD/secrets.env" <<EOF
POSTGRES_PASSWORD=$(rnd 32)
JWT_SECRET=$(rnd 48)
LIVEKIT_API_KEY=API$(rnd 12)
LIVEKIT_API_SECRET=$(rnd 40)
EOF
fi
if [ ! -f "$ENVD/panel.env" ]; then
  PW=${PANEL_PASSWORD:-}
  if [ ${#PW} -lt 10 ] || [ "$PW" = "$PLACEHOLDER" ] || ! [[ $PW =~ ^[A-Za-z0-9._@%+=:,!-]+$ ]]; then
    PW=$(rnd 16)
    console "=================================================================="
    console "TR LIVE PANEL SIFRESI (cloud-init sifresi uygun degildi): $PW"
    console "=================================================================="
  fi
  printf "PANEL_PASSWORD='%s'\n" "$PW" > "$ENVD/panel.env"
fi
touch "$ENVD/extra.env"
chmod 600 "$ENVD"/*.env
# shellcheck disable=SC1091
set -a; . "$ENVD/secrets.env"; set +a

# ---------- 5) Alan adı ----------
# sslip.io adı her zaman sunulur (kendi alan adı eklense bile panel ve uygulama bu adresle de çalışır).
if [ ! -s "$ENVD/sslip" ]; then
  IP=""
  for u in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    IP=$(curl -fsS --max-time 10 "$u" 2>/dev/null | tr -d ' \n\r' || true)
    [[ $IP =~ ^[0-9]+(\.[0-9]+){3}$ ]] && break
    IP=""
  done
  [ -n "$IP" ] || { log "HATA: sunucunun genel IP adresi bulunamadı"; exit 1; }
  echo "$(echo "$IP" | tr . -).sslip.io" > "$ENVD/sslip"
fi
SSLIP=$(tr -d ' \n\r' < "$ENVD/sslip")
[ -s "$ENVD/domain" ] || echo "$SSLIP" > "$ENVD/domain"
DOMAIN=$(tr -d ' \n\r' < "$ENVD/domain")
log "Adres: https://$DOMAIN  (LiveKit: wss://lk.$DOMAIN)"

# Sunucu ayarları (her çalıştırmada yeniden yazılır; panelden girilenler extra.env'de kalır). Değerler tek tırnaklı:
# docker compose içlerindeki $ ve # işaretlerini yorumlamasın.
cat > "$ENVD/stack.env" <<EOF
NODE_ENV='production'
PORT='3000'
DATABASE_URL='postgresql://trlive:${POSTGRES_PASSWORD}@postgres:5432/trlive'
DATABASE_SSL='false'
JWT_SECRET='${JWT_SECRET}'
LIVEKIT_URL='wss://lk.${DOMAIN}'
LIVEKIT_API_URL='http://host.docker.internal:7880'
LIVEKIT_API_KEY='${LIVEKIT_API_KEY}'
LIVEKIT_API_SECRET='${LIVEKIT_API_SECRET}'
TRUST_PROXY='1'
CORS_ORIGIN='*'
PUBLIC_BASE_URL='https://${DOMAIN}'
UPLOAD_DIR='/app/uploads'
EOF
printf "POSTGRES_PASSWORD='%s'\nDOMAIN='%s'\nSSLIP='%s'\n" "$POSTGRES_PASSWORD" "$DOMAIN" "$SSLIP" > "$ENVD/compose.env"
chmod 600 "$ENVD"/*.env

# Sunucunun genel IP'si (sslip adından): LiveKit telefonlara bu adresi bildirir. Dış IP'yi her açılışta STUN ile
# aramak yerine sabit yazmak, "Ses/görüntü bağlanamadı (Timeout)" hatasının sık bir sebebini ortadan kaldırır.
PUBIP=$(echo "$SSLIP" | sed -e 's/\.sslip\.io$//' -e 's/-/./g')
LK_OLD=$(md5sum "$ENVD/livekit.yaml" 2>/dev/null | cut -d' ' -f1)
cat > "$ENVD/livekit.yaml" <<EOF
port: 7880
bind_addresses: ["0.0.0.0"]
rtc:
  tcp_port: 7881
  # Tüm medya tek UDP portundan (7882): güvenlik duvarında tek kural yeter.
  udp_port: 7882
  node_ip: ${PUBIP}
  use_external_ip: false
keys:
  ${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}
logging:
  level: warn
EOF

HOSTS="$SSLIP"; LKHOSTS="lk.$SSLIP"
if [ "$DOMAIN" != "$SSLIP" ]; then HOSTS="$SSLIP, $DOMAIN"; LKHOSTS="lk.$SSLIP, lk.$DOMAIN"; fi
cat > "$ENVD/Caddyfile" <<EOF
$HOSTS {
  encode gzip
  handle /panel* {
    reverse_proxy 127.0.0.1:8090
  }
  handle {
    reverse_proxy 127.0.0.1:3000
  }
}
$LKHOSTS {
  reverse_proxy 127.0.0.1:7880
}
EOF

# ---------- 6) Başlat ----------
FREE_KB=$(df -Pk / | awk 'NR==2{print $4}')
log "Boş disk: $((FREE_KB / 1024)) MB"
if [ "${FREE_KB:-0}" -lt 5000000 ]; then
  log "Disk az: eski derleme artıkları temizleniyor"
  docker builder prune -af >/dev/null 2>&1 || true
  docker image prune -af >/dev/null 2>&1 || true
  log "Temizlikten sonra boş disk: $(( $(df -Pk / | awk 'NR==2{print $4}') / 1024 )) MB"
fi
mkdir -p "$STATE"
[ -e "$STATE/git-token" ] || install -m 622 /dev/null "$STATE/git-token" 2>/dev/null || true
[ "$(stat -c %a "$STATE/update" 2>/dev/null)" = 666 ] || { systemctl stop trlive-apply.path 2>/dev/null; touch "$STATE/update" && chmod 666 "$STATE/update"; systemctl start trlive-apply.path 2>/dev/null; } || true
log "Servisler derleniyor ve başlatılıyor (ilk seferde birkaç dakika sürer)"
$COMPOSE up -d --build --remove-orphans
if [ "$MODE" = --apply ]; then
  # Ayar dosyası değişince Caddy yeniden okusun. Uygulama sunucusu yalnızca panelden "Kaydet ve uygula" ile yeniden
  # başlatılır; GitHub güncellemesinde imaj değiştiyse compose zaten yeniler (her yüklemede gereksiz kesinti olmasın).
  $COMPOSE exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 || $COMPOSE restart caddy
  if [ "${TRLIVE_FROM_PANEL:-0}" = 1 ]; then $COMPOSE restart backend; fi
fi
# LiveKit ayarı değiştiyse ses sunucusu yeniden okusun.
if [ -n "$LK_OLD" ] && [ "$(md5sum "$ENVD/livekit.yaml" | cut -d' ' -f1)" != "$LK_OLD" ]; then
  log "LiveKit ayarı değişti, ses sunucusu yeniden başlatılıyor"
  $COMPOSE restart livekit
fi
docker image prune -f >/dev/null 2>&1 || true

# ---------- 7) Otomatik güncelleme, panel istekleri, yedek, güvenlik duvarı ----------
if [ "$MODE" = install ]; then
  unit() { cat > "/etc/systemd/system/$1"; }
  unit trlive-firewall.service <<EOF
[Unit]
Description=TR Live güvenlik duvarı kuralları
After=docker.service firewalld.service netfilter-persistent.service
Wants=docker.service
[Service]
Type=oneshot
ExecStart=/bin/bash $SRC/deploy/oracle/firewall.sh
[Install]
WantedBy=multi-user.target
EOF
  unit trlive-update.service <<EOF
[Unit]
Description=TR Live güncelleme kontrolü
After=docker.service
[Service]
Type=oneshot
Environment=HOME=/root
ExecStart=/bin/bash $SRC/deploy/oracle/update.sh
EOF
  unit trlive-update.timer <<'EOF'
[Unit]
Description=TR Live güncellemeyi 5 dakikada bir kontrol et
[Timer]
OnBootSec=3min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
EOF
  # Panelden gelen istekler ("Kaydet ve uygula", "Şimdi güncelle") bu dosyalarla gelir.
  unit trlive-apply.path <<EOF
[Path]
PathModified=$STATE/apply
PathModified=$STATE/update
[Install]
WantedBy=multi-user.target
EOF
  unit trlive-apply.service <<EOF
[Unit]
Description=TR Live panel isteği
[Service]
Type=oneshot
Environment=HOME=/root
ExecStart=/bin/bash $SRC/deploy/oracle/update.sh --from-panel
EOF
  unit trlive-import.path <<EOF
[Path]
PathModified=$STATE/import-request
[Install]
WantedBy=multi-user.target
EOF
  unit trlive-import.service <<EOF
[Unit]
Description=TR Live eski veritabanını aktarma
[Service]
Type=oneshot
Environment=HOME=/root
ExecStart=/bin/bash $SRC/deploy/oracle/import.sh
EOF
  unit trlive-backup.service <<EOF
[Unit]
Description=TR Live veritabanı yedeği
[Service]
Type=oneshot
ExecStart=/bin/bash $SRC/deploy/oracle/backup.sh
EOF
  unit trlive-backup.timer <<'EOF'
[Unit]
Description=TR Live günlük yedek
[Timer]
OnCalendar=*-*-* 04:30:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable trlive-firewall.service >/dev/null
  systemctl enable --now trlive-update.timer trlive-apply.path trlive-import.path trlive-backup.timer >/dev/null
fi

log "Bitti. Adres: https://${DOMAIN}  ·  Panel: https://${DOMAIN}/panel"
console "TR LIVE KURULUM TAMAM: https://${DOMAIN}/panel"
echo "$(date -Is) ok $DOMAIN" > "$STATE/installed"
