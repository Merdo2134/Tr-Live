# GitHub'a yükleme

Bu projeyi sizin adınıza GitHub'a **yükleyemiyorum** (hesabınıza ve ağa erişimim yok). Depo hazır: yerel bir git geçmişi
oluşturuldu (`main` dalı, ilk commit yapıldı). İki yol:

## 1) Boş bir depo oluşturup gönderin
GitHub'da **boş** (README/lisans eklemeden) bir depo açın, sonra zip'i açtığınız klasörde:
```bash
git remote add origin https://github.com/KULLANICI/tr-live.git
git push -u origin main
```
GitHub CLI ile: `gh repo create tr-live --private --source=. --push`

## 2) Git bundle ile
```bash
git clone TR-Live.bundle tr-live && cd tr-live
git remote set-url origin https://github.com/KULLANICI/tr-live.git
git push -u origin main
```

## Push sonrası ilk adımlar
1. Actions sekmesinde **Backend** ve **Mobile** iş akışlarının sonucuna bakın. `e2e` işi gerçek PostgreSQL ile çalışır:
   burada çıkan hatalar gerçek SQL/mantık hatalarıdır; çıktıyı bana yapıştırırsanız birlikte düzeltiriz.
2. **Settings → Secrets** içine üretim anahtarlarını koyun; depoya `.env` **koymayın**.
3. Depoyu **private** tutmanızı öneririm (yönetim ve para mantığı içerir).
