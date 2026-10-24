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
# Depo gizliyse: uygulamadaki yönetim sayfasından girilen GitHub erişim anahtarı (yalnızca okuma) kullanılır.
# Anahtar komut satırında görünmesin diye git ayarı ortam değişkeniyle verilir.
[ -e "$STATE/git-token" ] || install -m 622 /dev/null "$STATE/git-token" 2>/dev/null || true
chmod 622 "$STATE/git-token" 2>/dev/null || true
export GIT_TERMINAL_PROMPT=0
GH_TOKEN_VALUE="$(tr -d ' \r\n' 2>/dev/null < "$STATE/git-token" || true)"
if [ -n "$GH_TOKEN_VALUE" ]; then
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader"
  GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN_VALUE" | base64 | tr -d '\n')"
  export GIT_CONFIG_VALUE_0
fi
unset GH_TOKEN_VALUE
# Anahtarla indirilemezse (süresi dolmuş / silinmiş) anahtarsız da denenir (depo açıksa yine güncellenir).
if git -C "$SRC" fetch -q --depth 1 origin "$BRANCH" 2>>"$STATE/update.log" \
   || { [ -n "${GIT_CONFIG_COUNT:-}" ] && note "anahtarla indirilemedi (süresi dolmuş olabilir); anahtarsız deneniyor" \
        && unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 \
        && git -C "$SRC" fetch -q --depth 1 origin "$BRANCH" 2>>"$STATE/update.log"; }; then
  if [ "$(git -C "$SRC" rev-parse HEAD)" != "$(git -C "$SRC" rev-parse "origin/$BRANCH")" ]; then
    git -C "$SRC" reset -q --hard "origin/$BRANCH" && changed=true
    # Eski sürümlerin dosyaları diskte birikmesin (disk dolarsa kurulum yapılamaz).
    git -C "$SRC" reflog expire --expire=now --all >/dev/null 2>&1 || true
    git -C "$SRC" gc -q --prune=now >/dev/null 2>&1 || true
  fi
else
  note "GitHub'a ulaşılamadı (depo gizliyse uygulamadan GitHub erişim anahtarı girin); mevcut sürümle devam ediliyor"
fi
unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

HEADNOW="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo yok)"
APPLIED="$(cat "$STATE/applied" 2>/dev/null || true)"
# Son uygulama başarısız olduysa (ya da hiç kaydı yoksa) 20 dakikada bir yeniden denenir; eskiden yeni bir yükleme
# gelene kadar sunucu eski sürümde kalıyordu.
retry=false
if [ "$changed" = false ] && [ "$APPLIED" != "$HEADNOW" ]; then
  if [ ! -f "$STATE/apply-attempt" ] || [ -n "$(find "$STATE/apply-attempt" -mmin +20 2>/dev/null)" ]; then retry=true; fi
fi

if [ "$changed" = true ] || [ "$retry" = true ] || [ "${1:-}" = --from-panel ]; then
  note "uygulanıyor (yeni sürüm: $changed, yeniden deneme: $retry)"
  touch "$STATE/apply-attempt"
  FROM_PANEL=0; [ "${1:-}" = --from-panel ] && FROM_PANEL=1
  if TRLIVE_FROM_PANEL=$FROM_PANEL bash "$SRC/deploy/oracle/install.sh" --apply; then
    echo "$HEADNOW" > "$STATE/applied"
    note "tamam · sürüm $(git -C "$SRC" rev-parse --short HEAD)"
  else
    note "HATA: kurulum tamamlanamadı. Kurulum kaydının son satırları:"
    sleep 2
    tail -n 15 "$STATE/install.log" 2>/dev/null | sed 's/^/    /' >> "$STATE/update.log"
  fi
fi
# Uygulama içindeki yönetim sayfası (süper yönetici) güncelleme isteği yazabilsin ve kayıtları okuyabilsin.
# Yalnızca izni yanlışsa dokunulur (her dokunuş "panel isteği" sayılıp sunucuyu yeniden başlatırdı).
[ "$(stat -c %a "$STATE/update" 2>/dev/null)" = 666 ] || { systemctl stop trlive-apply.path 2>/dev/null; touch "$STATE/update" && chmod 666 "$STATE/update"; systemctl start trlive-apply.path 2>/dev/null; } || true
chmod 644 "$STATE/update.log" "$STATE/install.log" 2>/dev/null || true
# Ses sunucusu testi (panelde "Ses sunucusu testi" bölümünde görünür).
bash "$SRC/deploy/oracle/diag.sh" >/dev/null 2>&1 || true
tail -n 200 "$STATE/update.log" > "$STATE/update.log.tmp" 2>/dev/null && mv "$STATE/update.log.tmp" "$STATE/update.log"
tail -n 2000 "$STATE/install.log" > "$STATE/install.log.tmp" 2>/dev/null && mv "$STATE/install.log.tmp" "$STATE/install.log"
exit 0
