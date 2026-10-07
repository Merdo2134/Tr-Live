# Değişiklik ve inceleme raporu

## v2.17.3–2.17.4 — Yayıncı hedefi yalnızca yayıncı olduktan sonra
- **Kural:** Maaş hedefi (yayın süresi + Diamond) yalnızca **onaylı yayıncılar** için ve **yayıncı onayından sonraki** süre/hediyelerden hesaplanır. Ajansa katılma tarihi belirleyici değildir. Yayıncı olmayan kullanıcının hedefi/maaşı 0'dır; yalnızca Diamond'larını bozdurabilir.
- `hostMetrics` (hedef ekranı, ajans paneli, dönem kapanışı) buna göre düzeltildi; ajans e2e testi bu kurala göre yazıldı.
- Not: Diamond bozdurma (Diamond → Coin) özelliği henüz yok; oran belirlenince eklenecek.

## v2.17.2 — Derleme ve gizli oda düzeltmeleri
- **APK derleme hatası:** `NotificationVisibility` hem `flutter_foreground_task` hem `flutter_overlay_window` paketinde tanımlı olduğundan Dart "imported from both" hatası veriyordu (`background_service.dart`). Ön plan servisi paketinden bu ad gizlendi; balon için overlay paketininki kullanılıyor.
- **Gizli oda sızıntısı (sunucu):** `GET /api/rooms/:id` sorgusunda oda `is_hidden` alanı, sahibin `u.is_hidden` (gizli kullanıcı) alanıyla aynı adı taşıyordu; ikincisi birinciyi eziyor, gizli odanın ayrıntısı odada olmayan herkese açık dönüyordu. Oda alanı `room_hidden` takma adıyla alınıyor. (e2e testinde "expected 404, actual 200" hatasının nedeni buydu.)

## v2.17.1 — İzleyici kulübesi
- Oda başlığının sağında, odadaki en yüksek seviyeli ilk 3 kullanıcının üst üste binen altın çerçeveli avatarları görünür; dokununca üye listesi açılır.

## v2.17 — Oda içi ekran mekaniği (YoHo / Yalla ölçüleri)
- **Dikey bölünme:** üst başlık (~%15) · koltuk sahnesi (~%40) · canlı sohbet (~%35) · alt bar (~%10). Sahne ve sohbet oransal (flex 40 / 35) olduğundan her telefon boyunda aynı düzen korunur.
- **Klavye:** `resizeToAvoidBottomInset: false`; klavye açılınca koltuklar yukarı fırlamaz, yer sohbet bölgesinden alınır.
- **Koltuk ölçüleri:** ≤6 koltukta avatar 56dp, 8–9 koltukta 48dp, 12/15/20 koltukta 40dp (yazılar ve elmas rozeti de küçülür); koltuklar arası 8dp; avatarın çevresinde 3dp boşluk (konuşma/hediye halkası buraya oturur); uzun adlar `ellipsis` ile kesilir.
- **Hediye paneli:** alttan ekranın ~%45'ini kaplar, arkası kararmaz; koltuklar hediye seçerken de görünür.
- Not: Ölçüler kaynak olarak bir yapay zekâ özetine dayanır; telefonda görünce oranlar (%40/%35, avatar boyutları) tek satırlık değişiklikle ayarlanabilir.

## v2.16 — Telefondan müzik çalar
- **"Telefonum" sekmesi** (müzik panelinde): telefonun hafızasındaki mp3/m4a/aac/ogg/wav/flac dosyalarını seçip listeye ekler (sistem dosya seçici; ek izin gerekmez). Liste telefonda kalıcıdır, silinen dosyalar otomatik düşer. Arama, süre/boyut bilgisi, **telefonda dinle** (yalnızca kendin) ve listeden kaldırma var.
- **Odada çal:** yetkili (sahip / yardımcı / moderatör) şarkıyı tek dokunuşla odaya çalar; mikrofondaki kullanıcı sıraya ekler. Dosya sunucuya geçici yüklenir (en fazla 25 MB), odadaki herkes mevcut senkron müzik altyapısıyla aynı saniyede dinler; ilerleme çubuğu, duraklat, sonraki ve ses ayarı aynen çalışır.
- **Sunucu:** `POST /api/rooms/:id/music/upload` (ham ses; türü ilk baytlardan doğrular, kullanıcı başına 5 aktif parça, 10 yükleme/10 dk). Parçalar `is_temp` olarak işaretlenir, ortak kütüphanede görünmez, yalnızca yüklendiği odada çalınır, 12 saat sonra (çalmıyorsa/sırada değilse) dosyasıyla silinir. Migrasyon 014.
- **Sınır:** Telefonun sesini canlı olarak LiveKit'e aktarmak (Zula'daki "ses karıştırma") bu sürümde yok; bunun yerine dosya yüklenip herkeste senkron çalınır. Bu yöntem arka planda ve kötü ağda daha kararlıdır.

## v2.15 — Oda içi arayüz (Figma üst satır / alt satır)
- **Üst satır:** oda sahibinin avatarı + oda adı (dokununca oda bilgileri ve yöneticiler) + ID, dinleyici sayısı (dokununca üye listesi), X düğmesi. X → tam ekran **Küçült / Çıkış** seçimi.
- **İkinci satır:** odadaki toplam elmas sayacı, Favori (oda sahibine Ayarlar) rozeti, sağda altın taç (sıralamalar).
- **Sohbet:** kartlar halinde; avatar, ad, seviye rozeti, WIP. Yüksek seviyeli kullanıcıların mesajı mor / turuncu kart. Karta dokununca kullanıcı kartı açılır.
- **Alt satır:** 6 yuvarlak düğme: Sohbet (yazı alanını açar), Emoji, Oda sesi aç/kapat (yalnızca kendi cihazında), Mikrofon (konuşurken sustur/aç, uzun basınca mikrofondan in; mikrofonda değilken mikrofona çık / sıraya gir), Hediye, Oda araçları. Görüntülü odada kamera düğmesi de çıkar.
- Eski üst çubuk (AppBar) kaldırıldı; Odayı Kapat artık Oda araçlarında (yalnızca oda sahibi).

## v2.14.1 — "Oda bulunamadı" hatası
- **Neden:** Sunucu, odadaki kişinin canlı olup olmadığını yalnızca WebSocket aboneliğinden anlıyordu. Abonelik düşerse (ağ geçişi, sunucunun uyanması vb.) birkaç dakika sonra oda sahibi çıkarılıyor ve oda kapanıyordu; uygulama ise bunu öğrenemeyip kapalı odada kalıyor, her işlemde "Oda bulunamadı." diyordu.
- **Çözüm:** Uygulama odadayken her 25 sn'de HTTP "heartbeat" gönderir (`POST /api/rooms/:id/heartbeat`; `room_members.last_seen_at`, migrasyon 013). Temizleyici yalnızca WebSocket de heartbeat de uzun süredir yoksa çıkarır (üye 5 dk, oda sahibi 15 dk). Heartbeat oda kapanmışsa 404 döner; uygulama o zaman "Oda kapandı." deyip odadan çıkar, ölü odada takılmaz. Heartbeat aboneliği de yeniler.

## v2.14 — Arka planda çalışma, odadan düşmeme, yüzen balon, çökme koruması
- **Odadan düşme / oda kapanma nedeni bulundu ve düzeltildi:** uygulama arka plana alınınca telefon bağlantıyı kesiyordu; sunucudaki temizleyici üyeyi hemen odadan çıkarıyordu (oda sahibiyse oda kapanıyordu). Artık bağlantısı kopan üye hemen atılmaz: üye 5 dk, oda sahibi 15 dk beklenir; geri bağlanınca sayaç sıfırlanır (`ROOM_GRACE_SECONDS`, `ROOM_OWNER_GRACE_SECONDS`).
- **Arka planda çalışma:** odadayken bildirimli bir ön plan servisi çalışır (oda sesi kesilmez; mikrofondaysanız mikrofon da açık kalır). Pil kısıtlaması ve bildirim izni ilk odada sorulur.
- **Diğer uygulamaların üzerinde yüzen balon:** uygulamadan çıkınca ekranda mikrofon balonu kalır (sürüklenebilir); dokununca uygulamaya dönülür. "Diğer uygulamaların üzerinde göster" izni ilk odada sorulur; Profil > "Arka plan ve balon izinleri"nden tekrar istenebilir.
- **Geri dönünce:** bağlantı hemen yenilenir, üyeler ve sohbet güncellenir. Ağ kesintisinde oda açık kalır, 5 sn arayla yeniden denenir (yalnızca sunucu açıkça reddederse odadan çıkarılır).
- **Çökme koruması:** yakalanmamış hatalar uygulamayı kapatmaz, kayda geçer. Profil > "Hata kaydı"ndan görülüp kopyalanabilir.
- Derleme akışı Android manifestine servisleri ve izinleri ekler.

## v2.13 — Oda içi kullanıcı kartı
- Odada bir kullanıcıya dokununca Figma'daki gibi kart açılır: üstte taşan büyük avatar (dokununca tam profil), ad, seviye / hediye seviyesi / WIP / rol / aile rozetleri, kopyalanabilir kimlik, **Yakın Arkadaşlarım** (ona en çok hediye gönderen 5 kişi), **Madalyalar** (rozet envanteri), Etiketle (sohbete @ad yazar), Hediye Gönder, Takip Et.
- **Yetkiye göre görünür:** Yönetici (moderatör / yardımcı sahip ata, yetkiyi al — yalnızca oda sahibi ve yardımcı sahip), Mic Aç / Mic Kapat, Sohbet (10 dk / 1 saat / 1 gün sustur, kaldır), Koltuk (koltuktan indir ve kilitle), Odadan At — yalnızca hedeften üst yetkisi olana görünür. Normal kullanıcı bu düğmeleri hiç görmez. Sunucu aynı kuralları ayrıca denetler.
- Sol üstteki ünlem: Şikâyet et, Kullanıcıyı engelle, (yetkiliye) Bu odadan engelle.
- Sunucu: `GET /api/users/:id/card`.

## v2.12 — Boyut ve ölçü standartları
Android / Material 3 standartlarına göre düzenlendi:
- **Yazı ölçeği:** Material 3 tablosu (gövde 14/16, etiket 11-12, başlık 16-22 sp, satır yüksekliğiyle). 10 sp'lik küçük yazılar 11 sp'ye çıkarıldı.
- **Dokunma hedefi:** tüm düğmeler en az 48×48 dp (düğme yüksekliği 46 → 48).
- **Kontrast:** soluk yazı rengi WCAG AA (4.5:1) için açıldı; çok soluk `white38` yazılar `white54` oldu.
- **Pencere sınıfları:** compact < 600, medium 600-839, expanded 840-1199, large ≥ 1200 dp. Ekran kenar boşluğu 16 / 24 / 32 dp (ana sayfa ızgarası ve banner buna uyar). Oda kartı sütunları 2 / 3 / 4 / 5.
- **Sistem yazı boyutu:** kullanıcının ayarı 0.85–1.3 kat arasında uygulanır (önceden 1.25).

## v2.11 — Hediye paneli ve şeffaf MP4 hediye animasyonu
- **Yeni hediye paneli (Figma):** üstte mikrofondaki kişilerin avatarları (koltuk numarasıyla; seçili olan pembe halkalı), ok düğmesiyle odadaki herkesi göster; sekmeler Etkinlik / Popüler / Kişiye Özel / Vip; sayfalı 4'lü hediye ızgarası (seçili hediye pembe çerçeve); altta bakiye (cüzdana gider), adet seçici ve Gönder.
- **Alıcı seçimi:** tek kişi, birden çok kişi (HER birine seçilen adet gider, toplam = fiyat × adet × kişi), "Listele" menüsünden **Tüm Koltuk** (mikrofondakiler) ve **Tüm Oda** (kendin hariç, en fazla 50 kişi). Sunucu: `distribution: each | all_mic | all_room`.
- **Şeffaf MP4 hediye:** hediyeye animasyon adresi (.mp4) girilince odadaki herkeste tam ekran oynar. Format Tencent **VAP** (alfa kanallı H.264 MP4) olmalıdır; Lottie ve WebP/GIF de desteklenir. Animasyonlar sırayla oynar.
- **Hediye sekmesi:** `gifts.category` (migrasyon 012). Yönetici panelinde hediye eklerken sekme ve animasyon biçimi seçilir.
- Hediye listesi yanıtına `globalMinCoins` eklendi (dünya simgesi bu tutarın üstündeki hediyelerde görünür).

## v2.10 — Oda içi araçlar penceresi, mikrofon modu, koltuk yerleşimi
- **Oda araçları:** alt çubuktaki ⊞ düğmesi kayar pencere açar. İnteraktif Özellikler (PK, Oyunlar) ve Temel Araçlar: Yayını Paylaş (davet metnini kopyalar), Efekt ve Ses, Sohbet Yasağı/Açma, Müzik, Sohbet Temizleme, Oda Kilidi (şifre), Özel Temalar, Oda Gizleme, Mikrofon Modu, Oda Ayarları. Yetkisi olmayana uyarı verir.
- **Mikrofon Modu:** 2/5/8/9/12/15/20 mikrofon; seçince koltuk sayısı herkes için canlı değişir. Azaltınca taşan koltuktakiler dinleyiciye iner. `PATCH /api/rooms/:id {seatCount}` (oda sahibi / yardımcı sahip).
- **Koltuk yerleşimi** Figma'daki gibi: 5 → 1+4, 9 → 1+4+4, 12 → 2+5+5, 15 → 5×3, 20 → 5×4; kısa satırlar ortalanır.
- **Hata düzeltmesi:** oda sahibi başka koltuğa geçince kendi 0. koltuğuna geri dönemiyordu; artık dokunarak dönebilir.
- Henüz yok ("çok yakında" uyarısı verir): Günlük Görev, Şanslı Çanta.

## v2.9 — Kalıcı oda, şifresiz kurulum, yerleşim düzeltmesi
- **Yerleşim düzeltildi:** üst satır = TRLive tacı + oda aç düğmesi; alt satır = Sesli | Akış | Görüntülü | Mesajlar | Profil.
- **Oda bir kez kurulur:** ilk "Sesli oda aç / Görüntülü yayın aç"ta ad, etiket, koltuk düzeni ve tema sorulur. Sonraki açışlarda tek dokunuşla doğrudan odaya girilir; ad ve etiketler sabit kalır.
- **Şifre kurulumdan kaldırıldı;** yalnızca oda içindeki ayarlardan konur/kaldırılır.
- **Oda adına dokununca** "Oda bilgileri" açılır: sahip/yardımcı sahip ad ve etiketleri düzenler, herkes oda yöneticilerini görür.
- **Banner sonsuz döngü:** birden fazla banner hep ileri kayar; sonuncudan sonra yine ilkine geçer.
- Yöneticiler (yardımcı sahip, moderatör) oda kapanınca da korunur. Sunucu: `room_profiles`, `room_staff` (migrasyon 011), `GET /api/rooms/mine`, `GET /api/rooms/:id/managers`.

## v2.8 — Üst satır / alt satır düzeni
- **Üst satır:** Sesli | Akış | Görüntülü | Mesajlar | Profil. Alt menü kaldırıldı.
- **Alt satır:** altın taç + "TRLive" (sıralamaları açar) ve oda açma düğmesi. Sesli tarafta "Sesli oda aç", görüntülü tarafta "Görüntülü yayın aç".
- **Sıralamalar:** Günlük / Haftalık / Aylık × Yayıncı, Destekçi, Ajans, Aile, Oda, CP. Sunucu: `GET /api/leaderboards?type=receivers|senders|agencies|families|rooms|cp&period=daily|weekly|monthly`.
- Aile, favoriler, gizli odaya kodla giriş ve kullanıcı arama oda listesindeki ⋮ menüsünde.

## v2.6 — Figma (HİLLİVE) yerleşimine geçiş, 1. aşama
- Alt menü: Party | Keşfet | Giriş Sayfası | Mesajlar | Profil. Aile, liderlik, favoriler, kodla giriş ve kullanıcı arama "Giriş Sayfası"nda.
- Party ana sayfası: Takip / Popüler / Yakında sekmeleri, dikey görsel kartlar (tür rozeti, etiket, dinleyici sayısı, altında başlık).
- Yayın başlat: Sesli / Görüntülü seçimi tek pencerede.
- Giriş ekranı Figma düzenine yaklaştırıldı (taç + logo, hap butonlar). Renkler uygulamanın kendi temasıdır.
- Sunucu: `region=near` (aynı şehirdeki yayıncılar).

## v2.7 — Figma yerleşimi, 2. aşama
- **Keşfet gönderi akışı:** gönderi (yazı + görsel), beğeni, yorum, "Takip Edilen | Genel" sekmeleri; başkasının profilinde "Paylaşım" sekmesi. Uçlar: `GET/POST /api/posts`, `PUT /api/posts/image`, `DELETE /api/posts/:id`, `POST|DELETE /api/posts/:id/like`, `GET|POST /api/posts/:id/comments`. Gönderi sahibi veya yetkili (admin/yardımcı admin) siler.
- **Banner:** ana sayfanın üstünde kayan banner. Yönetici panelinde "Banner/Duyuru" sekmesinden yüklenir. Uçlar: `GET /api/banners`, `/api/admin/banners` (GET, PUT image, POST, PATCH, DELETE).
- **Mesajlar kartları:** Arkadaşlık isteği (yeni takipçiler), Ekip, Etkinlik duyurusu, Ödül bildirimleri; okunmamış rozetleri. Uçlar: `GET /api/announcements`, `GET /api/inbox-summary`, `POST /api/inbox-summary/seen`, `POST|DELETE /api/admin/announcements`.
- **Koltuk düzeni:** 4 ve 6 koltuk eklendi (migration 010); oda açarken düzen önizlemesi.
- Migration 009 (gönderi, banner, duyuru) ve 010 (koltuk düzenleri).

## v2.5 — Yeni tema ve duyarlı (responsive) ana sayfa
- Tüm uygulama tek renk kaynağına bağlandı: `mobile/lib/widgets/app_theme.dart` (koyu lacivert zemin, turkuaz vurgu, pembe CANLI rozeti, altın bildirim). Renk değiştirmek için yalnızca bu dosya düzenlenir.
- Ana sayfa yeniden tasarlandı: yuvarlak aksiyon düğmeleri, Trend / Arkadaşlar anahtarı, Global / Türkiye / Diğer bölge çipleri, görselli 2 sütunlu oda kartları.
- Duyarlılık: sütun sayısı ekran genişliğine göre (2–5), yazı ölçeği sınırlandı (0.85–1.25), geniş ekranda içerik ortalanır, oda koltuk ızgarası genişliğe uyar.
- Sunucu: `GET /api/rooms` artık `region` (`tr` | `other` | `friends`) kabul eder ve `themeImageUrl` döndürür.

## Orijinal kodda bulunan kritik hatalar (düzeltildi)
1. **Bakiye sızıntısı:** odaya giriş ve hediye şeridi olaylarında herkese Coin/Diamond bakiyesi yayınlanıyordu.
2. **`JWT_SECRET` yoksa üretimde bile `dev-only-change-me` kullanılıyordu.** Artık üretimde 32+ karakter zorunlu.
3. **Aile katılımı:** başka bir ailedeyken katılmak sessizce "başarılı" dönüyordu; sahip ayrılmayı denediğinde de sessiz başarı vardı. Aile üye sıralaması alfabetik (yanlış) yapılıyordu.
4. **Mikrofon sistemi yoktu:** koltuk alma/bırakma uç noktası olmadığı için "eşit/rastgele dağıtım" yalnızca oda sahibine çalışıyordu.
5. **Deadlock riski:** karşılıklı hediyelerde kilit sırası tutarsızdı. Artık tüm satırlar tek sorguda sıralı kilitleniyor.
6. **Giriş efekti** seçilen değil en yeni öğeyi kullanıyordu.
7. **Yetki:** `support` rolü Coin düzenleyebiliyordu; artık para/katalog işlemleri yalnızca `admin`.
8. **Girdi doğrulama:** `BigInt("0x10")` gibi girdiler kabul ediliyor, geçersiz UUID 500 hatası veriyordu, uzun alanlar DB hatasına düşüyordu.
9. **Kullanıcı adı** büyük/küçük harf duyarlıydı (`Ali` ≠ `ali`).
10. **Bayi sınırsız:** `commission_bps` kullanılmıyor, bayi sahibi kendi satışını yapamıyordu; katalog (hediye/çerçeve/efekt) için admin uç noktası yoktu.
11. **Çoklu cihaz/bağlantı:** WebSocket kaydı kullanıcı başına tek soketti, ölü bağlantılar temizlenmiyordu; odaya abonelik yetkisiz yapılabiliyordu.
12. **Operasyon:** migration çalışma dizinine bağlıydı, CI var olmayan `package-lock.json`'a dayanıyordu, Dockerfile root çalışıyordu, DB SSL zorla `rejectUnauthorized:false`'tı.
13. **Flutter:** çıkış yap ana ekranda `Navigator.pop` ile çöküyordu; hiçbir ekranda hata yönetimi yoktu; LiveKit hiç bağlanmıyordu (ses/görüntü yok); hediye gönderme arayüzü yoktu; global şerit hiç görünmüyordu; boş asset klasörleri git'te kaybolur ve derlemeyi bozar; `android/ios` klasörleri yoktu.

## v2.4 — roller ayrıldı
**Dört ayrı rol** (karıştırılmaz):
- **Admin (yönetici):** uygulama sahibi; admin panelindeki her şey.
- **Yardımcı admin:** yalnızca admin, admin panelinden (Yetkililer sekmesi) atar/alır. Yetkisi: kullanıcının **nickini** ve **profil fotoğrafını** değiştirmek/kaldırmak, **süreli veya süresiz ban** atmak/kaldırmak. Para, WIP, ajans, maaş, katalog, güvenlik, şikâyet ekranlarına giremez; admini ve diğer yardımcıları banlayamaz. (Sunucuda `staff_logic.js` içindeki izin listesiyle zorlanır.)
- **Oda sahibi:** yayını açan kişi.
- **Moderatör:** yalnızca oda sahibi (ve yardımcı sahip) atar. Yetkisi: sohbeti silme/temizleme, susturma, mikrofona davet, koltuk kilitleme/açma, koltuktan kaldırma, normal kullanıcıyı odadan atma/engelleme. Rol dağıtamaz, oda sahibine dokunamaz.
Ayrıca v2.4: **oda küçültme** (oda arka planda açık kalır, ses kesilmez; küçük çubuktan geri açılır/kapatılır), **yukarı/aşağı kaydırarak oda değiştirme** (oda sahibi hariç, şifreli odalar atlanır), **oda arama** (ad, yayıncı, etiket), **favori yayıncılar** ve **son girilen odalar** (★ ekranı; oda kapanınca silindiği için favori yayıncı bazlıdır), **mikrofon sırası** (boş koltuk yoksa "Sıraya gir"; koltuk boşalınca sıradaki davet alır, kabul ederse oturur). Migration 008.
Yeni: süreli ban (`banned_until`, süre dolunca otomatik açılır, giriş ekranında neden/bitiş gösterilir), kilitli koltuklar (`rooms.locked_seats`), mikrofon daveti (`mic_invite` olayı). Eski `/admin/users/:id/status` kaldırıldı → `/ban` ve `/unban`. Migration 007.

## v2.3 — yeni eklenenler
Gizli oda + davet kodu · oda temaları (WIP 4 özel görsel) · koltuk başına hediye sayacı · sohbet temizleme (sahip/moderatör) · PK karşılaşmaları ·
oda içi Ludo (sunucu-otoriter, bahissiz) · **ajans sistemi yeniden yazıldı:** ajans kodu, yayın saati takibi, maaş kademeleri, kesinti, kademeli komisyon,
resmi etkinlikler, dönem kapatma + hesap özetleri, KYC şartı · APK için `.github/workflows/apk_build.yml`.
Kendine hediye artık ajans/maaş, PK ve liderlik hesabına SAYILMAZ (suistimal önlemi); eski hediye-başı komisyon (`agency_commissions`) kullanımdan kalktı.
Okey yapılmadı (yalnızca Ludo).

## v2.2 — yeni eklenenler
Müzik çalar · oda içi yazılı sohbet · özel mesaj · oda etiketleri/şifre/ayarlar · engelleme/şikâyet/gizlilik · liderlik tabloları · **uygulama içi güvenlik duvarı** ·
Nginx/UFW/fail2ban/Docker Compose altyapısı · uçtan uca test paketi · GitHub Actions (backend + e2e + Flutter analiz).

## v2.1 — yeni eklenenler
Kendine hediye · WIP 5 kademe + satın alma · ajans/yayıncı sistemi (başvuru, davet, panel, komisyon, ödeme işaretleme) · zengin profil
(avatar/kapak yükleme, takip, ziyaretçi, çerçeve) · aile yönetimi · oda moderasyonu · bayi paneli · yönetim paneli · hesap silme ·
şifre değişince oturumları geçersiz kılma · cüzdan geçmişi · yasaklama.

## Doğrulama durumu (dürüst özet)
| Konu | Durum |
|---|---|
| Saf mantık + güvenlik duvarı ara katmanı (sahte istek/yanıtla) | 50 birim testi geçiyor (`npm test`) |
| Migrasyonlar 001–006 ve 006'daki ana SQL sorguları | Gerçek PostgreSQL 16'da elle çalıştırıldı, hata yok |
| Uçtan uca testler (`backend/e2e`, 19 senaryo) | **Yazıldı, çalıştırılmadı** — GitHub Actions'ta gerçek Postgres ile çalışır |
| Tüm backend modülleri import ediliyor, route'lar kayıt oluyor | Doğrulandı (sahte paketlerle) |
| İstemci ↔ sunucu uç nokta uyumu | 105 çağrı eşleştirildi |
| Dart sözdizimi (parantez/string), import'lar | Betikle tarandı |
| **SQL sorguları gerçek PostgreSQL'de** | **Çalıştırılmadı** |
| **Flutter derlemesi / LiveKit bağlantısı** | **Denenmedi** |

## Eksikler (mağaza ve gerçek kullanım öncesi)
Ayrıntılı ve öncelikli liste: [`docs/COMPARISON.md`](docs/COMPARISON.md). Başlıcalar: uygulama içi satın alma (Play/App Store) ·
telefon/Google/Apple girişi ve şifre sıfırlama · push bildirim · PK/oyunlar/karaoke · SVGA · web yönetim paneli ·
Redis/çoklu sunucu · ajans ödeme/maaş otomasyonu · yaş kapısı ve KVKK metinleri · token'ın `flutter_secure_storage` ile saklanması · yük testleri.

## v2.3.1
Yasaklı kelime denetimi artık yalnızca sohbet/DM'de değil; oda adı, kullanıcı adı/görünen ad, biyografi, aile adı ve ajans adında da uygulanır (`backend/src/safe_text.js`).
