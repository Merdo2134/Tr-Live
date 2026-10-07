# Mobil kurulum

`android/` ve `ios/` klasörleri depoda yok. Flutter 3.32+ ile üretin:

```bash
cd mobile
./setup_platforms.sh
```

Betik `flutter create --platforms=android,ios .` çalıştırır ve gerekli izinleri ekler. **Betik, üretilen dosyaları düzenler;
çalıştırdıktan sonra sonucu gözle kontrol edin.** Elle yapılması gerekenler:

**Android** (`android/app/src/main/AndroidManifest.xml`)
- İzinler: `INTERNET`, `RECORD_AUDIO`, `CAMERA`, `MODIFY_AUDIO_SETTINGS`, `ACCESS_NETWORK_STATE`, `BLUETOOTH_CONNECT`
- Yerel geliştirmede http kullanıyorsanız `<application android:usesCleartextTraffic="true">` (üretimde https kullanın, bunu kaldırın)
- `android/app/build.gradle(.kts)` içinde `minSdk = 24`

**iOS** (`ios/Runner/Info.plist`)
- `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`
- `UIBackgroundModes` → `audio`
- `ios/Podfile` → `platform :ios, '13.0'`

Çalıştırma:
```bash
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:3000   # Android emülatörü → bilgisayarınız
```
