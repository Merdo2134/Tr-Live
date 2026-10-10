# Mimari

## Bileşenler

```
 Android uygulaması (Flutter)
   │  HTTPS  /api/*          JSON, Bearer token
   │  WSS    /ws?token=...   oda ve kişi olayları
   │  WebRTC (LiveKit)       ses / görüntü
   ▼
 Node.js 20 + Express 5  (backend/src/server.js, tek süreç)
   ├─ firewall ─ helmet ─ cors ─ json(100 KB) ─ bodyGuard
   ├─ 23 router  →  /api/...
   ├─ ws hub (realtime.js)  →  /ws
   ├─ /media/:id   (veritabanındaki tüm görseller ve animasyonlar, bellek önbellekli)
   ├─ /uploads/*   (yalnızca 12 saatlik geçici oda müzikleri + eski dosyalar)
   └─ zamanlayıcılar (ticker.js ile üst üste binmez)
   ▼
 PostgreSQL 16  (75 tablo, 29 migration)
 LiveKit Cloud / kendi LiveKit sunucusu (ses-görüntü yönlendirme)
```

| Katman | Teknoloji | Neden |
|---|---|---|
| Mobil | Flutter (Dart 3.8+), yalnızca Android | Tek kod tabanı, akıcı animasyon |
| Ses/görüntü | `livekit_client` 2.x | SFU; 30 koltuğa kadar ses, video odası |
| Hediye animasyonu | Lottie, VAP (şeffaf mp4), kendi SVGA oynatıcımız, webp/gif | Yoho/Bigo varlıklarıyla uyum |
| API | Express 5 | Async hatalar otomatik `next(err)`'e gider |
| Veritabanı | PostgreSQL, ham SQL | Para işlemleri için satır kilidi (`FOR UPDATE`) ve kısıtlar |
| Gerçek zamanlı | `ws` (Socket.IO yok) | Hafif; istemci yeniden bağlanmayı kendisi yönetir |
| Dağıtım | Render (web servisi + PostgreSQL) | Basit; `deploy/` klasöründe kendi sunucu (docker, nginx, ufw, fail2ban) seçeneği de var |

## İstek akışı

1. `firewall()` — IP yasağı, WAF kuralları (SQLi/yol gezintisi kalıpları), IP başına dakikalık sınır. Kötü davranış puanı eşiği geçen IP otomatik yasaklanır.
2. `helmet` başlıkları, `cors`, `express.json({limit: 100kb})`, `bodyGuard` (aşırı derin JSON, `__proto__` anahtarları).
3. Zorunlu güncelleme kapısı: `X-App-Version` başlığı yönetim panelindeki en düşük sürümün altındaysa 426.
4. Router: `requireAuth` → `authenticateToken` her istekte kullanıcıyı (ve cihaz oturumunu) veritabanından okur: hesap aktif mi, ban süresi doldu mu, `token_version` güncel mi, oturum kapatılmış mı.
5. Uç bazlı hız sınırı `userLimit(ad, adet, süre)`.
6. İş mantığı. Para/bakiye değişen her işlem tek `tx()` içinde; ilgili satırlar **id sırasıyla** kilitlenir (deadlock önlemi).
7. Hata yakalayıcı: 4xx mesajı aynen, PostgreSQL hata kodları Türkçe mesaja çevrilir, 5xx ayrıntısı istemciye gitmez.

## Gerçek zamanlı katman

* Bağlantı: `wss://SUNUCU/ws?token=JWT[&roomId=...]`. Kullanıcı başına en fazla 5, IP başına 30 bağlantı; 10 sn'de 40 mesaj sınırı.
* İstemci `room_subscribe` ile odaya abone olur; sunucu üyeliği doğrular.
* "Yazıyor...": istemci `typing {to}` gönderir (en fazla 2,5 sn'de bir); sunucu yalnızca arkadaş, engelsiz ve DM'i açık kişiye `typing` iletir.
* Çevrimiçi durumu: istemci ekranda gördüğü kişileri `presence_watch` ile bildirir; sunucu anlık durumu (`presence_state`) ve değişiklikleri (`presence`) gönderir. Son bağlantı kapanınca 20 sn tolerans vardır (ağ geçişlerinde durum titremesin); sonra `users.last_seen_at` yazılır.
* Sunucu olayları: `hub.sendToUser`, `hub.broadcastRoom`, `hub.broadcastGlobal` (tam liste: [generated/realtime.md](generated/realtime.md)).
* Sunucu 30 sn'de bir ping atar; mobil istemci 70 sn sessizlikte bağlantıyı yarı açık sayıp yeniden kurar.
* **Sınır:** hub bellek içidir; birden fazla sunucu örneği çalıştırılacaksa Redis pub/sub gerekir (yol haritasında).

## Zamanlayıcılar (backend)

| Ad | Görev |
|---|---|
| room sweeper | Kalp atışı kesilen üyeleri odadan çıkarır, boş odayı kapatır |
| music ticker | Oda müzik sırasını ilerletir, süresi dolan geçici parçaları siler |
| bag ticker | Şanslı çanta geri sayımı / bitişi, kalan iadesi |
| avatar sweeper | WIP süresi biten (hareketli profil fotoğrafı ayrıcalığı kalmayan) kullanıcının hareketli fotoğrafını sabit fotoğrafa döndürür |
| pk ticker | PK süresi bitince kazananı belirler |
| game ticker | Oyun zaman aşımları |
| firewall janitor | Süresi dolan IP yasaklarını ve sayaçları temizler |

## Mobil uygulama yapısı

```
mobile/lib/
  main.dart                 tema, Türkçe yerelleştirme, hata ekranı, kaydırma davranışı
  services/
    api.dart                HTTP istemcisi (zaman aşımı, Türkçe hata, token yenileme, zorunlu güncelleme)
    auth_service.dart       giriş/çıkış, token ve yenileme token'ı saklama, eski oturum yükseltme
    device_info.dart        cihaz adı/modeli, kuruluma özel cihaz kimliği
    presence_service.dart   çevrimiçi durumu (izleme + canlı güncelleme)
    socket_service.dart     WebSocket, yeniden bağlanma, yarı açık bağlantı tespiti
    session.dart            oturum durumu
    room_dock.dart          oda küçültme (mini baloncuk)
    music_service.dart      oda içi müzik çalar (just_audio)
    background_service.dart ön plan servisi (odada iken ses kesilmesin)
    inbox_service.dart      okunmamış sayaçları
    media_cache.dart        animasyon/görsel önbelleği
    error_log.dart          yakalanan hatalar (Profil > Hata kaydı + sunucuya gönderim)
  screens/                  25 ekran (oda, ana sayfa, profil, mesajlar, yönetim, ajans, aile ...)
  widgets/                  ortak bileşenler: tema (Pal/Gap/Rad), koltuk düzeni, hediye şeridi, SVGA ...
```

Tasarım ölçüleri: `widgets/app_theme.dart` (renk `Pal`, boşluk `Gap`, köşe `Rad`), koltuk yerleşimi `widgets/seat_picker.dart` (`seatLayouts`, ekran genişliğine oranlı).

## Backend dosya yapısı

```
backend/
  src/server.js            uygulama, ara katmanlar, router bağlama, kapanış
  src/realtime.js          WebSocket hub
  src/firewall*.js         IP sınırı, WAF, yasak
  src/auth.js              JWT, şifre, rol kontrolleri
  src/*_logic.js           saf (veritabanısız, test edilebilir) iş kuralları
  src/routes/*.js          REST uçları (23 dosya)
  src/services/*.js        veritabanı kullanan yardımcılar
  src/migrations/*.sql     sıralı şema değişiklikleri (geri alınmaz, yalnızca ileri)
  scripts/check.mjs        tüm dosyalarda sözdizimi denetimi
  scripts/gen_docs.mjs     docs/generated/* üretir
  test/                    birim testleri (node --test)
  e2e/                     uçtan uca API testleri (gerçek PostgreSQL ister)
```

## Dağıtım

* GitHub Actions: `backend.yml` (sözdizimi + test), `mobile.yml` (flutter analyze), `apk_build.yml` (APK; derleme hatasında erken durur ve hatayı özet sayfasına yazar), `db_tasi.yml` (elle: veritabanını başka sağlayıcıya birebir kopyalar).
* Render: `npm run migrate && npm start`. Migration'lar her açılışta sırayla ve bir kez uygulanır.
* Uzaktan ayarlar (`app_config` tablosu, Panel > Uygulama ayarları): en düşük/güncel sürüm, indirme bağlantısı, moderasyon kuralları, şanslı hediye oranları — APK yayınlamadan değişir.
* Ortam değişkenleri: `DATABASE_URL` (sağlayıcı seçimi: [VERITABANI.md](VERITABANI.md)), `DATABASE_SSL`, `DATABASE_CA`, `ADMIN_USERNAMES`, `JWT_SECRET` (≥32 karakter), `LIVEKIT_URL/API_KEY/API_SECRET`, `TRUST_PROXY`, `CORS_ORIGIN`, `BANNED_WORDS`, `FIREWALL_*`, `GLOBAL_GIFT_MIN_COINS`.
