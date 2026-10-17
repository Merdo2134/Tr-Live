#!/usr/bin/env bash
# Günlük veritabanı yedeği: /opt/trlive/backups (son 7 gün saklanır).
set -euo pipefail
ROOT=/opt/trlive
F="$ROOT/backups/trlive-$(date +%F).sql.gz"
docker exec trlive-postgres-1 pg_dump -U trlive --no-owner trlive | gzip -6 > "$F.tmp" && mv "$F.tmp" "$F"
ls -1t "$ROOT"/backups/trlive-*.sql.gz | tail -n +8 | xargs -r rm -f
