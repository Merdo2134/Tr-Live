# Veritabanı sağlayıcısı

Sunucu sürekli çalışır ve veritabanına birkaç saniyede bir sorgu atar (oda temizliği, müzik sırası, PK süresi,
şanslı çanta ...). Bu yüzden **"işlem saati" kotası olan ücretsiz planlar** (ör. Neon Free: ayda 100 CU-saat)
ay ortasında biter ve veritabanı ay sonuna kadar kapanır. Uygun olan: kotası saat değil yalnızca disk olan, sürekli açık plan.

| Sağlayıcı (ücretsiz) | Disk | Sınır | Uygun mu |
|---|---|---|---|
| **Aiven Free** | 1 GB | Saat kotası yok, trafik kotası yok; uzun süre hiç kullanılmazsa kapanır (bizde sürekli kullanım var) | ✅ önerilen |
| Supabase Free | 500 MB | Ayda 5 GB veri trafiği (sunucu sorguları dahil), 1 hafta hareketsizlikte durur | 🟡 küçük |
| Neon Free | 1 GB | Ayda 100 CU-saat → sürekli açık sunucuda ~2 hafta | ⛔ |
| Render Free PostgreSQL | 1 GB | 30 gün sonra silinir | ⛔ |

Ücretli gerekirse: Aiven Developer (aylık ~5 $, 8 GB, kapanmaz).

## Aiven'e geçiş

1. aiven.io → kayıt (kart gerekmez) → **Create service** → **PostgreSQL** → **Free plan** → bölge: **Europe** → oluştur.
2. Servis açılınca **Service URI** değerini kopyalayın (`postgres://avnadmin:...@...aivencloud.com:PORT/defaultdb?sslmode=require`).
   Sondaki `?sslmode=require` kalabilir; sunucu bunu kendisi ayarlar.
3. **Eski verileri taşımak için** (kullanıcılar, Coin, hediyeler ...):
   GitHub depo → Settings → Secrets and variables → Actions → iki secret: `ESKI_DATABASE_URL` (Neon adresi),
   `YENI_DATABASE_URL` (Aiven Service URI). Sonra Actions → **Veritabanını taşı** → önce "Yalnızca kontrol" ile çalıştırın,
   sonra onay kutusuna `EVET` yazıp çalıştırın. "BİTTİ" görünce devam edin.
   Neon'un işlem kotası dolduysa eski veritabanı kota yenilenene kadar okunamaz; o zaman ya yenilenmeyi bekleyin
   ya da 4. adımla sıfırdan başlayın.
4. Render → backend → Environment: `DATABASE_URL` = Aiven Service URI → Save (sunucu yeniden başlar; tablolar yoksa
   kendiliğinden oluşturulur).
5. **Sıfırdan başlandıysa yönetici hesabı:** Render'a `ADMIN_USERNAMES` = kendi kullanıcı adınız (virgülle birden çok)
   ekleyin. O adla kayıt olunca (ya da sunucu yeniden başlayınca) hesap yönetici olur.

## Ayarlar

| Değişken | Açıklama |
|---|---|
| `DATABASE_URL` | Bağlantı adresi. Adresteki `sslmode` parametresi yok sayılır (sağlayıcının kendi sertifikasıyla hata vermesin). |
| `DATABASE_SSL` | `no-verify` (varsayılan: şifreli, sertifika doğrulanmaz) · `true` (tam doğrulama) · `false` (şifresiz, yalnızca yerel) |
| `DATABASE_CA` | İsteğe bağlı: sağlayıcının CA sertifikası (Aiven → "CA certificate"); verilirse sertifika tam doğrulanır. |
| `ADMIN_USERNAMES` | İsteğe bağlı: bu kullanıcı adları yönetici yapılır (listeden çıkarmak yetkiyi geri almaz). |

## Disk kullanımı

Hediye animasyonları ve görseller de veritabanında (`media_files`) durur; 1 GB'ın en büyük kullanıcısı onlardır.
"Veritabanını taşı" iş akışı en büyük tabloları boyutlarıyla gösterir. Disk dolmaya yaklaşırsa animasyonlar ücretsiz bir
nesne deposuna (ör. Cloudflare R2, 10 GB) taşınmalıdır (yol haritasında).
