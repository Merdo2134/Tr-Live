# TR Live

Sesli/görüntülü canlı oda uygulaması: **Flutter** (mobil) + **Node.js/Express** + **PostgreSQL** + **LiveKit** + **WebSocket**.

> **Durum: MVP / kapalı beta adayı.** Mantık katmanı 29 birim testiyle doğrulandı. SQL sorguları ve Flutter derlemesi
> geliştirme ortamında gerçek PostgreSQL/Flutter ile çalıştırılamadı; bu yüzden depoda **GitHub Actions** ile gerçek
> PostgreSQL'e karşı uçtan uca test (`backend/e2e`) ve `flutter analyze` hazırdır. **İlk işiniz CI'ı çalıştırıp çıkan
> hataları düzeltmek olmalıdır.** Rakiplerle karşılaştırma ve eksikler: [`docs/COMPARISON.md`](docs/COMPARISON.md).

## Özellikler
- **Hesap/profil:** kayıt-giriş (kaba kuvvet kilidi), profil düzenleme, avatar/kapak yükleme, takip, ziyaretçiler, gizli mod, mesaj gizliliği, hesap silme.
- **Odalar:** sesli ve görüntülü (LiveKit), 2–20 koltuk, mikrofon, **etiketler**, **şifreli oda**, yetkili rolleri, atma/engelleme/susturma, oda ayarları.
- **Yazılı sohbet** (oda içi) ve **özel mesaj** (gizlilik + engelleme + şikâyet).
- **Müzik çalar:** odada herkes için senkron müzik; lisans kaydı zorunlu kütüphane, sıra, duraklat/ara/sonraki, otomatik geçiş, yerel ses seviyesi.
- **Hediye:** tekli / eşit / rastgele / seçilenlere; **kendine hediye serbest**; Coin→Diamond muhasebesi; global şerit; liderlik tabloları.
- **WIP:** 5 kademe (renkli isim, rozet, oda sayısı, ziyaretçi listesi, atılamama, profil efekti).
- **Ajans/yayıncı:** başvuru, davet, onay, panel, aylık Diamond ve süre, komisyon, ödeme işaretleme.
- **Aile:** rol, seviye/kapasite, puan, sahiplik devri.
- **Bayilik, yönetim paneli, şikâyet yönetimi, güvenlik duvarı yönetimi.**
- **Güvenlik duvarı:** IP yasağı, WAF kuralları, kullanıcı/uç nokta limitleri, WebSocket sel koruması, otomatik yasaklama, denetim kaydı ([`deploy/README.md`](deploy/README.md)).

## Kurallar (kısaca)
| Konu | Kural |
|---|---|
| Kendine hediye | Serbest: Coin düşer, Diamond artar. **Ajans komisyonu, yayıncı kazancı ve liderlik dışı bırakılır** (suistimali önlemek için); aile puanı verilir. |
| Müzik | Yalnızca yönetici lisans notuyla şarkı ekler. Yetkililer (sahip/yardımcı/moderatör) yönetir; mikrofondakiler sıraya ekler. |
| Oda sahibi çıkarsa | Oda kapanır. Bağlantısı 90 sn kopan üyeler otomatik çıkarılır. |
| WIP | Aynı seviye süre uzatır, yüksek seviye yükseltir, düşük seviye aktifken alınamaz. |
| Komisyon | `commission_bps` (100 = %1); ödeme platform dışında, "ödendi" işaretlenir. |

## Hızlı başlangıç
```bash
# Backend
cd backend && cp .env.example .env     # değerleri doldurun
npm install && npm run migrate && npm test && npm start
# Uçtan uca (boş bir test veritabanı ile)
TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/trlive_test npm run test:e2e

# Mobil (android/ios klasörlerini üretir ve izinleri ekler)
cd mobile && ./setup_platforms.sh && flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:3000
```
Üretim kurulumu: [`deploy/`](deploy/). GitHub'a yükleme: [`docs/GITHUB.md`](docs/GITHUB.md). API: [`docs.md`](docs.md).

## Güvenlik
Gerçek anahtarlar depoya konmaz (`.env.example` kopyalanır). Üretimde `JWT_SECRET` 32+ karakter olmalıdır; aksi halde sunucu açılmaz.
