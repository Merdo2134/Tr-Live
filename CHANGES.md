# Değişiklik ve inceleme raporu

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
| Saf mantık + güvenlik duvarı ara katmanı (sahte istek/yanıtla) | 29 birim testi geçiyor (`npm test`) |
| Uçtan uca testler (`backend/e2e`, ~15 senaryo) | **Yazıldı, çalıştırılmadı** — GitHub Actions'ta gerçek Postgres ile çalışır |
| Tüm backend modülleri import ediliyor, route'lar kayıt oluyor | Doğrulandı (sahte paketlerle) |
| İstemci ↔ sunucu uç nokta uyumu | 105 çağrı eşleştirildi |
| Dart sözdizimi (parantez/string), import'lar | Betikle tarandı |
| **SQL sorguları gerçek PostgreSQL'de** | **Çalıştırılmadı** |
| **Flutter derlemesi / LiveKit bağlantısı** | **Denenmedi** |

## Eksikler (mağaza ve gerçek kullanım öncesi)
Ayrıntılı ve öncelikli liste: [`docs/COMPARISON.md`](docs/COMPARISON.md). Başlıcalar: uygulama içi satın alma (Play/App Store) ·
telefon/Google/Apple girişi ve şifre sıfırlama · push bildirim · PK/oyunlar/karaoke · SVGA · web yönetim paneli ·
Redis/çoklu sunucu · ajans ödeme/maaş otomasyonu · yaş kapısı ve KVKK metinleri · token'ın `flutter_secure_storage` ile saklanması · yük testleri.
