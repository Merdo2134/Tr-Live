# Rakiplerle karşılaştırma ve yol haritası

**Kaynak notu.** Yoho için uygulama mağazası sayfalarında yer alan özellik açıklamalarına baktım (oda içi yazılı sohbet,
özel sohbet, konu etiketleri, oda gizliliği, oyunlar, karaoke/müzik, ülkeye özel hediyeler, SVIP, onur madalyaları,
liderlik tabloları, kullanıcı içeriği moderasyonu). **Zula Live için resmi bir kaynak bulamadım**; bu yüzden onun adına
iddiada bulunmuyorum. Zula/Bigo gibi sesli oda uygulamalarında yaygın olan özellikler (PK, SVGA animasyonlu hediyeler,
ajans maaş/hedef portalı, oyun merkezi, VIP, web yönetim paneli) için sektör şablonlarını ölçüt aldım.
Bu uygulamaların iç mimarisini bilmiyorum; aşağıdaki karşılaştırma **özellik düzeyindedir**.

| Özellik | TR Live | Not |
|---|---|---|
| Sesli oda + mikrofon koltukları | ✅ | LiveKit |
| Görüntülü oda | ✅ | LiveKit |
| Oda içi yazılı sohbet | ✅ | susturma, silme, kapatma, flood/yasaklı kelime filtresi |
| Özel mesaj | ✅ | yalnızca metin; sesli/görsel mesaj yok |
| Müzik çalar | ✅ | senkron çalma, lisanslı kütüphane. Karaoke (söz/skor) yok |
| Hediyeler, Coin/Diamond, global şerit | ✅ | animasyon: Lottie/PNG. SVGA/MP4 yok |
| Kendine hediye | ✅ | istismar korumalı (komisyon/sıralama dışı) |
| Liderlik tabloları | ✅ | günlük/haftalık/aylık/tümü; gönderen, alan, aile |
| Aile | ✅ | seviye, rol, puan. Aile görevleri/savaşları yok |
| WIP (5 kademe) | ✅ | |
| Ajans / yayıncı | ✅ | kod, panel, hedefli maaş kademeleri, kademeli komisyon, dönem kapatma. **Ödeme platform dışında; KYC manuel; oranlar örnek** |
| Profil (takip, ziyaretçi, çerçeve, kapak) | ✅ | |
| Oda etiketleri, şifreli oda | ✅ | |
| Şikâyet, engelleme, gizlilik | ✅ | manuel inceleme; otomatik görsel/ses moderasyonu yok |
| Uygulama içi güvenlik duvarı | ✅ | WAF-lite; DDoS için Cloudflare gerekir |
| Giriş efekti | 🟡 | Lottie; SVGA yok |
| Uygulama içi satın alma (Play/App Store) | ❌ | **Coin satışının ana yolu; makbuz doğrulama gerekir** |
| Telefon/Google/Apple girişi, şifre sıfırlama, e-posta doğrulama | ❌ | |
| Push bildirim (FCM/APNs) | ❌ | |
| PK savaşları | ✅ | iki oda, süreli, skor + destekçi listesi |
| Oyunlar (Ludo, Uno, şans çarkı…) | 🟡 | yalnızca Ludo (bahissiz); Okey/Uno yok |
| Görevler, günlük ödül, onur madalyaları | ❌ | **Bedava Coin = para basma riski; Diamond çekimiyle birlikte tasarlanmalı** |
| Diamond çekimi (payout), vergi/KYC | ❌ | hukuki danışmanlık gerekir |
| Yaş doğrulama / 18+ politikası, gizlilik politikası, KVKK | ❌ | mağaza ve yasal zorunluluk |
| Web yönetim paneli | ❌ | şu an mobil içi panel |
| Çok dil, ülke/dil keşfi | ❌ | yalnızca Türkçe arayüz |
| Ölçek: Redis, çoklu sunucu, LiveKit cluster, CDN, izleme | ❌ | şu an tek sunucu |

## Gerçekçi konum
Çekirdek döngü ve yönetim/güvenlik temeli var: **çalışan bir MVP**. Bigo/Yoho/Zula'nın asıl farkı; ölçek (milyonlarca
eşzamanlı kullanıcı), gelir altyapısı (IAP, ödeme, ajans maaşları), oyunlaştırma (PK, oyunlar, görevler), içerik
moderasyonu otomasyonu ve yüzlerce kişilik ekip emeğidir. Bu kod tabanıyla **kapalı beta (yüzlerce kullanıcı)**
yapılabilir; "o seviyede" olmak için aşağıdaki yol haritası aylar sürer.

## Önerilen sıra
1. **CI'ı çalıştırıp hataları düzeltin** (e2e + flutter analyze), gerçek cihazda ses/müzik/kamera testi
   (müzik + WebRTC ses oturumu çakışması bazı cihazlarda ses seviyesini etkileyebilir).
2. Telefon/Google/Apple girişi + şifre sıfırlama; gizlilik politikası, kullanım şartları, yaş kapısı.
3. Google Play Billing / StoreKit + sunucu tarafı makbuz doğrulama (Coin satışı).
4. FCM/APNs push; sesli mesaj.
5. PK savaşları; SVGA/MP4 hediye animasyonu; karaoke.
6. Web yönetim paneli; otomatik moderasyon (görsel/ses); Redis ve çoklu sunucu.
7. Ajans maaş/hedef sistemi + Diamond çekimi (hukuki/vergi danışmanlığıyla).
