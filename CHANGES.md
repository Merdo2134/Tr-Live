# Değişiklik ve inceleme raporu

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
