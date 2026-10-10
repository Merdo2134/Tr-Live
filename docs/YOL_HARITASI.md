# Yol haritası

Durum işaretleri: ✅ var · 🟡 kısmen · ⬜ yok. "Faz" sütunu yapılacak sırayı gösterir.

## Faz 1 — Temel sağlamlık (v2.36)

| Konu | Durum | Not |
|---|---|---|
| Kalıcı medya (profil/kapak/gönderi/banner görselleri veritabanında) | ✅ v2.36 | Render diski her dağıtımda silindiği için görseller kayboluyordu. Sonra: Cloudflare R2 + CDN |
| Çevrimiçi durumu, son görülme | ✅ v2.36 | Profil, sohbet listesi, DM başlığı. Gizli kullanıcı (WIP) gösterilmez |
| Yenileme token'ı + cihaz oturumları | ✅ v2.36 | "Oturumlarım": cihaz listesi, uzaktan çıkış, diğer tüm cihazlardan çıkış |
| Yönetici canlı paneli | ✅ v2.36 | Çevrimiçi kullanıcı, aktif oda, soket, bellek/CPU, veritabanı gecikmesi, günlük sayılar, hata kayıtları |
| Uygulama hata kayıtlarının sunucuya gönderilmesi | ✅ v2.36 | Telefondaki çökme/hata satırları yönetici paneline düşer |
| Link / reklam engeli + otomatik susturma | ✅ v2.36 | Oda sohbeti, DM, gönderi, yorum. Tekrarlayan ihlalde süreli otomatik susturma |
| Yönetici işlem kaydı | ✅ v2.36 | Ban, nick/fotoğraf değişikliği, bakiye düzeltme ... kim, ne zaman, kime |
| Zorunlu güncelleme (en düşük sürüm) | ✅ v2.36 | Eski APK'lar "Güncelleme gerekli" ekranı görür |
| Push bildirim (FCM) | ⬜ | Firebase projesi gerekiyor (sizden: `google-services.json` + servis hesabı, GitHub secret olarak) |

## Faz 2 — Ekonomi ve etkileşim

| Konu | Durum | Not |
|---|---|---|
| Para işlemlerinde idempotency anahtarı | ✅ v2.37 | Hediye, mağaza, WIP, bozdurma, bayi satışı, şanslı çanta, yönetici Coin düzeltmesi |
| Coin geçmişi ekranı (filtreli) | ✅ v2.37 | Tür süzgeci (hediye, yükleme, bozdurma, mağaza/WIP, çanta) + "daha fazla" |
| Combo hediye | ✅ v2.37 | Combo düğmesi (5 sn), şeritte büyüyen xN sayacı |
| Şanslı hediye (Yoho çanı) | ✅ v2.38 | x2–x500, geri dönüş oranı ve alıcı payı panelden; panelden kapatılabilir |
| Hazine kutusu, CP hediyesi | ⬜ | |
| WIP 1–10 + SWIP (hayalet mod) | ✅ v2.38 | Yoho VIP ayrıcalıkları 10 kademeye sıkıştırıldı; her kademeye isim efekti, sohbet balonu, çerçeve, giriş aracı |
| Oda seviyesi, oda görevleri | ⬜ | |
| Mikrofon süre sınırı | ⬜ | |
| Sesli mesaj, çıkartma, GIF | ⬜ | Sesli mesaj için kalıcı depolama (R2) önce gelmeli |
| "Yazıyor..." ve "görüldü" | ✅ | "Görüldü" v2.36, "yazıyor..." v2.37 (sohbet ekranı ve listede) |
| Google Play ile Coin satın alma | ⬜ | Play Console hesabı + sunucu tarafı makbuz doğrulaması |

## Faz 3 — Ölçek ve operasyon

| Konu | Durum | Not |
|---|---|---|
| Redis (hub pub/sub, hız sınırı, önbellek) | ⬜ | Tek sunucu örneğinden fazlası için şart |
| BullMQ iş kuyruğu (dönem kapatma, toplu bildirim) | ⬜ | |
| Cloudflare R2 + CDN | ⬜ | Faz 1'deki veritabanı depolamanın yerini alır (geçiş betiği yazılacak) |
| Hazırlık (staging) ortamı | ⬜ | Ayrı Render servisi + ayrı veritabanı |
| Otomatik yedek + geri yükleme provası | 🟡 | `deploy/backup.sh` var; Render tarafında günlük yedek ücretli planda |
| Analitik: DAU/MAU, gelir, elde tutma | 🟡 | Panelde günlük sayılar var; dönemsel grafik yok |

## Faz 4 — Güvenlik derinleştirme

| Konu | Durum | Not |
|---|---|---|
| Root / emülatör tespiti | ⬜ | Yalnızca uyarı + sunucuya bildirim (engellemek meşru kullanıcıyı da üzer) |
| SSL pinning | ⬜ | Kendi alan adınıza geçtikten sonra (Render sertifikası değişince uygulama kilitlenmesin) |
| Cihaz bazlı çoklu hesap tespiti | 🟡 | Faz 1'de oturumlarda cihaz kimliği tutuluyor; panelde "aynı cihazdaki hesaplar" görünümü sonraki adım |
| Şikâyet / moderasyon kuyruğu | 🟡 | Şikâyet var; otomatik susturmalar ve tekrar eden ihlaller için tek ekran sonraki adım |
| Özellik bayrakları (uzaktan aç/kapa) | 🟡 | `app_config` tablosu Faz 1'de geldi; şimdilik yalnızca sürüm ayarı |

## Bilinçli olarak YAPMADIKLARIMIZ

* **Prisma / Socket.IO'ya geçiş:** mevcut ham SQL + `ws` yapısı çalışıyor ve testli; yeniden yazım risk getirir, kullanıcıya yeni bir şey kazandırmaz.
* **React Native:** uygulama Flutter; listedeki React Native maddeleri Flutter karşılıklarıyla ele alındı.
* **Mikroservis:** bu ölçekte tek servis + Redis yeterli; bölmek dağıtımı zorlaştırır.

## Ek fikirler (öneri)

1. **Kalıcı medya → R2 geçişi** tek betikle: veritabanındaki dosyalar R2'ye taşınır, adresler değişmez (`/media/:id` yönlendirir).
2. **Idempotency anahtarı** tüm para uçlarında (hediye, mağaza, WIP, bozdurma, bayi satışı).
3. **Uzaktan ayar (remote config):** etkinlik banner'ı, hediye indirimleri, bakım modu — APK yayınlamadan.
4. **Zorunlu güncelleme:** kritik düzeltmede eski sürümleri durdurmak için (Faz 1'de geldi).
5. **Hata kayıtlarının toplanması:** cihazda yakalanan hatalar panele düşer (Faz 1'de geldi).
6. **Hile tespiti:** aynı cihazdan çok hesap, kendine hediye döngüsü, bayi→hesap→bozdurma zincirleri için panel uyarıları.
7. **Moderasyon kuyruğu:** otomatik susturmalar + şikâyetler tek listede, tek tıkla ban/uyarı.
8. **Yedek provası:** ayda bir yedekten boş veritabanına geri yükleme denemesi (yedek gerçekten çalışıyor mu).
