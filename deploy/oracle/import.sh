#!/usr/bin/env bash
# Panelden istenen eski veritabanı aktarımı. Sunucu durdurulur, public şeması silinip eski veriler kopyalanır,
# sunucu yeniden başlar (eksik tablolar migration ile tamamlanır). Eski veritabanı değişmez.
set -uo pipefail
ROOT=/opt/trlive
SRC=$ROOT/src
ENVD=$ROOT/env
STATE=$ROOT/state
REQ=$STATE/import-request
LOG=$STATE/import.log
COMPOSE="docker compose -p trlive -f $SRC/deploy/oracle/compose.yml --env-file $ENVD/compose.env"
[ -s "$REQ" ] || exit 0
exec 8>"$STATE/import.lock"
flock -n 8 || exit 0
OLD=$(cat "$REQ"); : > "$REQ"   # adres diskte kalmasın
say() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }
: > "$LOG"
say "Aktarma başladı. Uygulama birkaç dakika kapalı olacak."
$COMPOSE stop backend >/dev/null 2>&1
# shellcheck disable=SC1091
set -a; . "$ENVD/secrets.env"; set +a
NEW="postgresql://trlive:${POSTGRES_PASSWORD}@postgres:5432/trlive"
$COMPOSE run --rm --no-deps -T -e OLD="$OLD" -e NEW="$NEW" -e PGCONNECT_TIMEOUT=20 panel bash -c '
set -o pipefail
psql "$NEW" -q -v ON_ERROR_STOP=1 -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public; CREATE EXTENSION IF NOT EXISTS pgcrypto;" || exit 3
pg_dump "$OLD" --schema=public --no-owner --no-acl --no-publications --no-subscriptions |
  psql "$NEW" -q -o /dev/null -v ON_ERROR_STOP=0 2>&1 | { grep -v "already exists" || true; } | tail -n 40
a=$(psql "$OLD" -At -c "SELECT COUNT(*) FROM users" 2>&1)
b=$(psql "$NEW" -At -c "SELECT COUNT(*) FROM users" 2>&1)
echo "Kullanıcı sayısı: eski $a, yeni $b"
[ "$a" = "$b" ] && echo "BAŞARILI: sayılar eşit." || echo "DİKKAT: sayılar farklı ya da okunamadı; yukarıdaki hatalara bakın."
' >> "$LOG" 2>&1
say "Uygulama sunucusu yeniden başlatılıyor."
$COMPOSE up -d backend >/dev/null 2>&1
$COMPOSE restart backend >/dev/null 2>&1
say "Bitti."
