# Test planı

## 1. Otomatik testler (GitHub Actions, her gönderimde)

| İş | Ne yapar | Dosya |
|---|---|---|
| Backend · unit | Tüm dosyalarda sözdizimi + saf mantık testleri (Node 20 ve 22) | `backend/test/*.test.js` |
| Backend · e2e | Gerçek PostgreSQL 16 + gerçek sunucu süreci, uçtan uca API senaryoları | `backend/e2e/api.e2e.js` |
| Mobile | Sürüm tutarlılığı, `flutter analyze`, `flutter test` | `mobile/test/` |
| APK | Analiz hatası varsa durur ve satırları özet sayfasına yazar; sonra APK | `.github/workflows/apk_build.yml` |

Birim testlerinin kapsadığı başlıca konular: güvenlik duvarı (sınırlayıcı, kilit, yasak, WAF), metin temizliği ve küfür filtresi,
link/telefon tespiti (yanlış alarm örnekleriyle), moderasyon sınıflandırması, uzaktan ayar doğrulaması, sürüm karşılaştırma,
cihaz bilgisi temizliği, maaş dönemi hesapları, yetki kuralları, Ludo, medya türü tespiti, müzik sırası.

Uçtan uca senaryolar: kayıt/giriş/kilit · profil, arama, takip, gizli mod, fotoğraf yükleme · oda, mikrofon, rol, atma, engelleme ·
hediye (tekli, kendine, dağıtım modları, muhasebe doğruluğu) · sohbet, susturma, spam · müzik · aile · WIP · ajans/maaş dönemi ·
bayi · mağaza · şanslı çanta · PK · oyunlar · gönderi akışı · yönetici/yardımcı admin yetkileri ·
**v2.37:** para işlemi tekrar koruması, combo, Coin geçmişi süzme/sayfalama · **v2.36:** cihaz oturumu (yenileme, rotasyon, çalıntı token, uzaktan çıkış, eski token yükseltme) · otomatik moderasyon ve kısıt ·
çevrimiçi durumu (soket, izleme, gizleme) · yönetim paneli, hata kayıtları, işlem kaydı, zorunlu güncelleme.

Yerelde çalıştırma:

```bash
cd backend
npm run check && npm test
TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/trlive_test npm run test:e2e
```

## 2. Cihazda elle kontrol listesi (her APK'dan sonra)

Her madde ✅ / ❌ ile işaretlenir; ❌ olanın ekran görüntüsü alınır.

### Giriş ve oturum
- [ ] Eski sürümden güncelleme: uygulama açılınca yeniden giriş istemiyor.
- [ ] Ayarlar > Oturumlarım: bu telefon "Bu cihaz" olarak, model adıyla görünüyor.
- [ ] İkinci telefondan giriş → birinci telefonda listede ikinci cihaz görünüyor → "Çıkış" → ikinci telefon giriş ekranına düşüyor.
- [ ] "Diğer tüm cihazlardan çıkış" sonrası bu telefon çalışmaya devam ediyor.
- [ ] Uygulama 1 saatten uzun arka planda kaldıktan sonra açılınca oturum sürüyor (token kendiliğinden yenileniyor).
- [ ] Şifre değişince diğer cihazlar çıkış yapıyor.

### Çevrimiçi durumu
- [ ] Mesajlar listesinde çevrimiçi arkadaşın avatarında yeşil nokta var; arkadaş uygulamayı kapatınca ~20 sn içinde kayboluyor.
- [ ] Sohbet ekranının başlığında "Çevrimiçi" / "Son görülme ... önce".
- [ ] Mesajımı karşı taraf açınca altında "Görüldü" çıkıyor.
- [ ] Ayarlar > "Çevrimiçi durumumu göster" kapalıyken karşı tarafta nokta ve son görülme görünmüyor.

### Hediye ve para (v2.37)
- [ ] Hediye gönderince pencere açık kalıyor, "COMBO xN" düğmesi 5 sn görünüyor; dokununca aynı hediye tekrar gidiyor, odadaki şeritte sayı büyüyor.
- [ ] Hediye, adet veya alıcı değişince combo düğmesi kayboluyor.
- [ ] Zayıf ağda (uçak modu aç/kapa) hediye gönder: Coin bir kez düşüyor.
- [ ] Cüzdan > süzgeçler (Hediye, Yükleme, Bozdurma, Mağaza/WIP, Çanta) ve "Daha fazla göster" çalışıyor.
- [ ] Arkadaşın yazarken sohbet başlığında ve mesaj listesinde "yazıyor..." görünüyor.

### WIP 1–10, SWIP, şanslı hediye (v2.38)
- [ ] Profil > WIP: üstte WIP 1 … WIP 10 ve SWIP; her birinde çerçeve, isim efekti, sohbet balonu ve giriş aracı önizlemesi değişiyor.
- [ ] Eski WIP'i olan hesap güncellemeden sonra 2 katı kademede (ör. eski WIP 3 → WIP 6) ve süresi aynı.
- [ ] WIP'li kullanıcının odadaki sohbet balonu renkli; koltuğunda (takılı çerçeve yoksa) WIP çerçevesi var; girişte aracıyla şerit geçiyor.
- [ ] WIP olmayan kullanıcı Vip sekmesinden hediye gönderemiyor ("WIP 3 ve üzeri"), WIP 3 gönderebiliyor.
- [ ] SWIP alıp Ayarlar > Hayalet mod açılınca: başka telefondan odaya girişi görünmüyor, dinleyici listesinde ve kişi sayısında yok; mikrofona çıkınca görünüyor.
- [ ] Şanslı sekmesi: Şanslı Çan x10 gönder → Coin 100 azalıyor, alıcıya 10 Elmas; kazanç çıkarsa "xN vurdun" ve bakiye artıyor, Cüzdan'da "Şanslı hediye kazancı".
- [ ] Panel > Uygulama ayarları > Şanslı hediye kapatılınca sekme kayboluyor; %90 + %10 kaydetmeye çalışınca reddediliyor.

### Moderasyon
- [ ] Oda sohbetinde `www.site.com` → "Link ... paylaşılamaz".
- [ ] "saat 10.30 da" gibi normal noktalı cümle gidiyor.
- [ ] 10 dk içinde 3 ihlal → "... dakika boyunca mesaj gönderemezsiniz"; temiz mesaj da gitmiyor.
- [ ] Panel > Otomatik moderasyon: ihlaller görünüyor, "Kısıtı kaldır" çalışıyor.

### Medya
- [ ] Profil fotoğrafı, kapak, gönderi görseli ve banner yüklendikten sonra **Render yeniden dağıtılınca da** görünüyor.

### Yönetim paneli (yönetici hesabı)
- [ ] Panel sekmesi 10 sn'de bir yenileniyor; çevrimiçi kullanıcı, oda, CPU, bellek, veritabanı, LiveKit dolu.
- [ ] Uygulama hata kayıtları: telefonda oluşan bir hata birkaç dakika içinde listede.
- [ ] İşlem kaydı: yapılan ban/kısıt/Coin düzeltmesi görünüyor.
- [ ] Uygulama ayarları > en düşük sürümü bu sürümden yüksek yapmaya çalışınca reddediliyor.
- [ ] Kullanıcı > Cihazlar: oturumlar ve aynı cihazı kullanan hesaplar görünüyor.

### Oda (her sürümde tekrar)
- [ ] Sesli oda aç → mikrofon al → ikinci telefondan ses geliyor.
- [ ] Hediye gönder → animasyon + bakiye doğru.
- [ ] Oda küçült → balon → geri aç; müzik yalnızca oda içinde.
- [ ] Koltuk modu değiştir → pencere kapanıyor, koltuklar doğru dizilimde.

## 3. Yayın öncesi

1. GitHub Actions: Backend, Mobile ve APK işleri yeşil.
2. Render: "Manual Deploy" sonrası günlükte `Uygulandı: 029_wip10_swip_lucky.sql` (yeni sürümde son migration) ve `Migration tamamlandı.`
3. `/health` → `{"ok":true}`.
4. Yukarıdaki elle kontrol listesi.
