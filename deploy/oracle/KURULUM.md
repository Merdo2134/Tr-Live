# Oracle Cloud'a taşıma (telefonla, komut yazmadan)

Kurulan: PostgreSQL, uygulama sunucusu, LiveKit (ses/görüntü, dakika sınırı yok), HTTPS (Caddy), yönetim paneli,
günlük yedek ve otomatik güncelleme (GitHub'a zip yükleyince sunucu 5 dakika içinde kendini günceller).
GitHub deposu herkese açık (public) kalmalı; sunucu kodu oradan indirir.

## 1. Sunucuyu aç
1. cloud.oracle.com → hesap aç (kart doğrulaması ister; Always Free ücretsizdir). Bölge: Frankfurt (ya da yakın bir Avrupa bölgesi).
2. Compute → Instances → **Create instance**
   - Image: varsayılan **Oracle Linux 9** ya da **Canonical Ubuntu 24.04** (ikisi de olur)
   - Shape: **Ampere – VM.Standard.A1.Flex**, 2 OCPU, 12 GB bellek
   - SSH keys: "Generate a key pair for me" → özel anahtarı indir ve sakla (normalde gerekmez).
   - En altta **Show advanced options → Management → Paste cloud-init script**: `deploy/oracle/cloud-init.sh`
     dosyasının tamamını yapıştır, içindeki şifreyi kendi şifrenle değiştir (en az 10 karakter, harf ve rakam).
   - **Create**. "Out of capacity" hatası alırsan birkaç saat sonra tekrar dene.
3. Sunucunun **Public IP address** değerini not al (ör. 130.61.12.34).

## 2. Portları aç (hemen, sunucu açılırken)
Instance sayfası → Primary VNIC → **Subnet** → Security Lists → Default Security List → **Add Ingress Rules**.
Her biri için Source CIDR `0.0.0.0/0`:
- IP Protocol **TCP**, Destination Port **80**
- IP Protocol **TCP**, Destination Port **443**
- IP Protocol **TCP**, Destination Port **7881**
- IP Protocol **UDP**, Destination Port **7882**

## 3. Paneli aç
15-20 dakika sonra tarayıcıda: `https://130-61-12-34.sslip.io/panel` (IP'deki noktalar tire olur).
Kullanıcı adı herhangi bir şey, şifre cloud-init'e yazdığın şifre. "Uygulama sunucusu: ✅ çalışıyor" görmelisin.
- Sayfa "güvenli değil" derse ya da açılmazsa: portlar geç açıldıysa güvenlik sertifikası 1 saate kadar gecikebilir.
- Şifre kabul edilmezse: Instance → **Console connection / Console history** bölümünde "TR LIVE PANEL SIFRESI"
  satırında otomatik üretilen şifre yazar (cloud-init şifresi uygun değilse üretilir).

## 4. Verileri taşı
Panel → **Eski veritabanını aktar** → Render'daki `DATABASE_URL` değerini (dışarıdan erişilebilen "External" adres)
yapıştır → AKTAR yaz → Verileri aktar. Bittiğinde "BAŞARILI: sayılar eşit" yazar. Kullanıcıların az olduğu bir
saatte yapın; aktarma sırasında uygulama birkaç dakika kapalı olur. (Odaya yüklenen müzik dosyaları taşınmaz.)
Panel → **Ayarlar**: Render'da olan `ADMIN_USERNAMES`, `GOOGLE_*`, `FACEBOOK_*` vb. değerleri buraya da girin.

## 5. Uygulamayı yeni sunucuya bağla
1. GitHub → depo → Settings → Secrets and variables → Actions → **Variables** → New repository variable:
   `API_URL` = `https://130-61-12-34.sslip.io`
2. Actions → "Build Android APK" → Run workflow (adres kutusunu boş bırak) → yeni APK'yı dağıt.
3. Eski uygulamalar için: **eski** sunucuda (Render) Yönetim → Uygulama ayarları → En düşük sürüm = yeni sürüm,
   indirme bağlantısı = yeni APK. Böylece eski uygulamalar "Güncelleme gerekli" der.
4. Her şey yolundaysa birkaç gün sonra Render'ı durdurabilirsin.

## Notlar
- Google/Facebook girişinde yönlendirme adresleri yeni adresle (`https://…sslip.io/api/auth/oauth/google/callback`
  ve `…/facebook/callback`) güncellenmelidir. Google, sslip.io adreslerini yayın modunda kabul etmeyebilir; o
  durumda ucuz bir alan adı alınır (A kaydı ve `lk.` alt alanı sunucu IP'sini göstermeli) ve panelde "Alan adı"
  alanına yazılır. sslip.io adresi her zaman çalışmaya devam eder.
- Yedekler her gece sunucuda `/opt/trlive/backups` altında (son 7 gün).
