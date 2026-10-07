#!/usr/bin/env bash
# Günlük PostgreSQL yedeği (cron: 0 4 * * * /opt/trlive/deploy/backup.sh). 14 gün saklanır.
set -euo pipefail
DIR=${BACKUP_DIR:-/var/backups/trlive}
mkdir -p "$DIR"
docker compose -f "$(dirname "$0")/docker-compose.yml" exec -T postgres pg_dump -U trlive trlive | gzip > "$DIR/trlive-$(date +%F).sql.gz"
find "$DIR" -name 'trlive-*.sql.gz' -mtime +14 -delete
echo "Yedek alındı: $DIR"
