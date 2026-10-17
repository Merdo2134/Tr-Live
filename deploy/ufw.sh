#!/usr/bin/env bash
# Sunucu güvenlik duvarı (UFW). Yalnızca gerekli portlar açılır; PostgreSQL (5432) ve backend (3000) ASLA dışarı açılmaz.
set -euo pipefail
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw limit 22/tcp comment 'SSH (hız sınırlı)'
ufw allow 80/tcp comment 'HTTP (yönlendirme + certbot)'
ufw allow 443/tcp comment 'HTTPS (API + WebSocket)'
ufw allow 7880/tcp comment 'LiveKit sinyal'
ufw allow 7881/tcp comment 'LiveKit TCP medya'
ufw allow 50000:50100/udp comment 'LiveKit UDP medya'
ufw --force enable
ufw status verbose
