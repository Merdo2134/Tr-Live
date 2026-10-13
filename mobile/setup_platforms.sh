#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v flutter >/dev/null || { echo "Flutter bulunamadı."; exit 1; }
[ -d android ] || flutter create --platforms=android,ios --org com.trlive --project-name tr_live .

python3 - <<'PY'
import pathlib, re
# ---- Android izinleri ----
m = pathlib.Path('android/app/src/main/AndroidManifest.xml')
if m.exists():
    s = m.read_text()
    perms = ['INTERNET','RECORD_AUDIO','CAMERA','MODIFY_AUDIO_SETTINGS','ACCESS_NETWORK_STATE','BLUETOOTH_CONNECT']
    add = ''.join(f'    <uses-permission android:name="android.permission.{p}"/>\n' for p in perms
                  if f'android.permission.{p}"' not in s)
    if add:
        s = s.replace('<application', add + '    <application', 1)
        m.write_text(s)
    print('Android izinleri tamam.')
# ---- iOS izinleri ----
p = pathlib.Path('ios/Runner/Info.plist')
if p.exists():
    s = p.read_text()
    keys = {
      'NSMicrophoneUsageDescription': 'Odalarda konuşabilmeniz için mikrofon gerekir.',
      'NSCameraUsageDescription': 'Görüntülü odalarda yayın yapabilmeniz için kamera gerekir.',
      'NSPhotoLibraryUsageDescription': 'Profil fotoğrafı seçebilmeniz için galeri erişimi gerekir.',
    }
    add = ''.join(f'\t<key>{k}</key>\n\t<string>{v}</string>\n' for k, v in keys.items() if k not in s)
    if 'UIBackgroundModes' not in s:
        add += '\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>audio</string>\n\t</array>\n'
    if add:
        i = s.rfind('</dict>')
        s = s[:i] + add + s[i:]
        p.write_text(s)
    print('iOS izinleri tamam.')
PY
echo "Bitti. minSdk (24) ve iOS platform sürümünü (13.0) SETUP.md'ye göre kontrol edin."
