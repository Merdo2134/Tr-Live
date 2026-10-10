#!/usr/bin/env bash
# Eski PostgreSQL veritabanını (ör. Neon) yeni, BOŞ bir veritabanına (ör. Aiven) birebir kopyalar. Eski veritabanı değişmez.
# GitHub Actions > "Veritabanını taşı" iş akışı bunu postgres:18 kabında çalıştırır (ESKI, YENI, KONTROL ortam değişkenleri).
set -uo pipefail
fail() { echo "::error::$*"; exit 1; }

# Adreste sslmode yoksa şifreli bağlantı zorunlu tutulur (sertifika doğrulanmaz; bulut sağlayıcıların çoğu kendi CA'sını kullanır).
addssl() { case "$1" in *sslmode=*) printf '%s' "$1" ;; *\?*) printf '%s&sslmode=require' "$1" ;; *) printf '%s?sslmode=require' "$1" ;; esac; }
OLD=$(addssl "${ESKI:-}")
NEW=$(addssl "${YENI:-}")
[ -n "${ESKI:-}" ] || fail "ESKI_DATABASE_URL secret'ı eksik."
[ -n "${YENI:-}" ] || fail "YENI_DATABASE_URL secret'ı eksik."

echo "== Eski veritabanı =="
psql "$OLD" -Atc "select version()" || fail "Eski veritabanına bağlanılamadı. (Neon'da işlem süresi kotası dolduysa kota yenilenene kadar okunamaz.)"
psql "$OLD" -c "select pg_size_pretty(pg_database_size(current_database())) as \"toplam boyut\""
psql "$OLD" -c "select c.relname as tablo, pg_size_pretty(pg_total_relation_size(c.oid)) as boyut
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' order by pg_total_relation_size(c.oid) desc limit 12"

echo "== Yeni veritabanı =="
psql "$NEW" -Atc "select version()" || fail "Yeni veritabanına bağlanılamadı (adres/şifre doğru mu?)."
n=$(psql "$NEW" -Atc "select count(*) from information_schema.tables where table_schema = 'public'")
if [ "${KONTROL:-false}" = "true" ]; then
  echo "Yalnızca kontrol yapıldı, kopyalama yapılmadı. Yeni veritabanının public şemasında $n tablo var."
  exit 0
fi
[ "$n" = "0" ] || fail "Yeni veritabanının public şemasında $n tablo var. Kopyalama yalnızca BOŞ veritabanına yapılır."

echo "== Yedek alınıyor =="
pg_dump "$OLD" --schema=public --no-owner --no-privileges --no-statistics -Fc -f /tmp/db.dump || fail "Eski veritabanının yedeği alınamadı."
ls -lh /tmp/db.dump

echo "== Yeni veritabanına yükleniyor =="
pg_restore --no-owner --no-privileges -d "$NEW" /tmp/db.dump 2> /tmp/restore.log
# "public şeması zaten var" gibi zararsız uyarılar gizlenir; gerisi gösterilir.
grep -v -i "already exists\|errors ignored on restore\|COMMENT ON SCHEMA\|must be owner of schema public\|Command was: CREATE SCHEMA public\|^\s*$" /tmp/restore.log | head -40

echo "== Doğrulama (her tablonun satır sayısı) =="
tables=$(psql "$OLD" -Atc "select tablename from pg_tables where schemaname = 'public' order by 1")
bad=0
count=0
for t in $tables; do
  count=$((count + 1))
  a=$(psql "$OLD" -Atc "select count(*) from public.\"$t\"")
  b=$(psql "$NEW" -Atc "select count(*) from public.\"$t\"" 2>/dev/null || echo "YOK")
  if [ "$a" != "$b" ]; then echo "UYUŞMUYOR: $t (eski $a, yeni $b)"; bad=1; fi
done
[ "$bad" = 0 ] || fail "Bazı tablolar eksik kopyalandı (yukarıda). Yeni veritabanını boşaltıp tekrar deneyin; eski uygulama çalışıyorsa veri değişmiş olabilir."
psql "$NEW" -c "select pg_size_pretty(pg_database_size(current_database())) as \"yeni boyut\""
echo "BİTTİ: $count tablo birebir kopyalandı. Şimdi Render > backend > Environment > DATABASE_URL değerini yeni adresle değiştirin."
