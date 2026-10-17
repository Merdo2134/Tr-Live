#!/usr/bin/env bash
# GitHub'daki main dalında yeni sürüm varsa indirir ve yeniden başlatır. Panelden gelen istekte (--from-panel)
# ayarları her durumda uygular. Aynı anda iki kez çalışmaz.
set -uo pipefail
export HOME=${HOME:-/root}
ROOT=/opt/trlive
SRC=$ROOT/src
STATE=$ROOT/state
BRANCH=${TRLIVE_BRANCH:-main}
note() { echo "$(date '+%F %H:%M:%S') $*" >> "$STATE/update.log"; }

exec 9>"$STATE/update.lock"
if [ "${1:-}" = --from-panel ]; then
  flock -w 1800 9 || { note "HATA: başka bir işlem bitmedi"; exit 1; }
else
  flock -n 9 || exit 0
fi

changed=false
if git -C "$SRC" fetch -q --depth 1 origin "$BRANCH" 2>/dev/null; then
  if [ "$(git -C "$SRC" rev-parse HEAD)" != "$(git -C "$SRC" rev-parse "origin/$BRANCH")" ]; then
    git -C "$SRC" reset -q --hard "origin/$BRANCH" && changed=true
  fi
else
  [ "${1:-}" = --from-panel ] && note "GitHub'a ulaşılamadı; mevcut sürümle devam ediliyor"
fi

if [ "$changed" = true ] || [ "${1:-}" = --from-panel ]; then
  note "uygulanıyor (yeni sürüm: $changed)"
  if bash "$SRC/deploy/oracle/install.sh" --apply; then
    note "tamam · sürüm $(git -C "$SRC" rev-parse --short HEAD)"
  else
    note "HATA: kurulum tamamlanamadı (ayrıntı: kurulum kaydı)"
  fi
fi
tail -n 200 "$STATE/update.log" > "$STATE/update.log.tmp" 2>/dev/null && mv "$STATE/update.log.tmp" "$STATE/update.log"
tail -n 2000 "$STATE/install.log" > "$STATE/install.log.tmp" 2>/dev/null && mv "$STATE/install.log.tmp" "$STATE/install.log"
exit 0
