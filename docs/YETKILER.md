# Roller ve yetkiler

Uygulamada birbirinden bağımsız beş rol ekseni vardır. Bir kişi aynı anda birden fazlasına sahip olabilir
(ör. hem bayi hem bir odanın yardımcısı hem bir ailenin yöneticisi).

## 1. Sistem rolü (`users.system_role`)

| Yetki | `admin` (uygulama sahibi) | `support` (yardımcı admin) | `user` |
|---|:-:|:-:|:-:|
| Kullanıcı arama | ✅ | ✅ | — |
| Nick / profil fotoğrafı değiştirme | ✅ | ✅ yalnızca normal kullanıcıya | — |
| Süreli / süresiz ban, ban kaldırma | ✅ | ✅ yalnızca normal kullanıcıya | — |
| Destek sohbetlerini okuma / yanıtlama | ✅ | ✅ | — |
| Coin / Elmas düzeltme, bayi yükleme | ✅ | — | — |
| Hediye, çerçeve, giriş efekti, mağaza ürünü ekleme/silme | ✅ | — | — |
| WIP kademeleri, ajans ayarları, dönem kapatma, ödeme işaretleme | ✅ | — | — |
| Banner, duyuru, şikâyet yönetimi | ✅ | — | — |
| Yardımcı admin atama | ✅ | — | — |

Kural kaynağı: `backend/src/staff_logic.js` (`SUPPORT_ROUTES` beyaz liste; listede olmayan her yönetim ucu yardımcı admin için 403).
Yönetici kendi üzerinde işlem yapamaz; yardımcı admin başka bir personele dokunamaz (`mayActOnUser`).

## 2. Oda rolü (`room_members.role`)

Sıralama: `owner` (4) > `cohost` (3) > `moderator` (2) > `user` (1). Kural kaynağı: `backend/src/room_permissions.js`.

| İşlem | owner | cohost | moderator | user |
|---|:-:|:-:|:-:|:-:|
| At / engelle / mikrofonu kapat / sohbet sustur | ✅ | ✅ kendinden düşüğe | ✅ yalnızca `user`'a | — |
| Rol ver: cohost | ✅ | — | — | — |
| Rol ver: moderator / user | ✅ | ✅ (cohost'a dokunamaz) | — | — |
| Koltuk kilitle, mikrofon daveti | ✅ | ✅ | ✅ | — |
| Oda ayarları (ad, etiket, şifre, koltuk modu, mikrofon isteği modu) | ✅ | ✅ | — | — |
| Müzik yönetimi | ✅ | ✅ | ✅ | mikrofondaysa sıraya ekler |
| Odayı kapatma, yardımcı atama | ✅ | — | — | — |

Oda sahibine hiçbir işlem yapılamaz. Sahip odadan çıkarsa oda kapanır.
WIP ayrıcalıkları (varsayılan kademeler, panelden değişir): WIP 4+ moderatör/yardımcı tarafından sohbette susturulamaz,
WIP 6+ odadan atılamaz (oda sahibi ikisini de yapabilir). Vip sekmesindeki hediyeleri WIP 3+ gönderebilir.
SWIP hayalet modundaki kullanıcıyı oda sahibi ve yöneticiler dinleyici listesinde görmeye devam eder.

## 3. Aile rolü (`family_members.role`)

| İşlem | owner | admin | member |
|---|:-:|:-:|:-:|
| Aile adını değiştirme, sahipliği devretme, aileyi dağıtma | ✅ | — | — |
| Üye atma, rol değiştirme, başvuru onayı | ✅ | ✅ | — |
| Ayrılma | — (önce devretmeli) | ✅ | ✅ |

## 4. Ajans / yayıncı

* **Ajans sahibi:** ajans kodu (8 hane) ile yayıncı davet eder/başvuru onaylar, ekip panelini görür, yayıncıyı çıkarır.
  Ajans yönetici onayıyla `active` olur.
* **Yayıncı:** ajansa bağlı, onaylı (`broadcasters.status = approved`). Maaşa tabidir, Elmas bozduramaz.
* Durumlar: ajans `pending/active/suspended/rejected`, yayıncı `pending/approved/rejected/suspended`.

## 5. Bayi (`dealer_accounts`)

Yönetici tarafından atanır. Yalnızca kendi bakiyesinden kullanıcıya Coin satabilir; her satış denetim kaydına yazılır.

## Henüz olmayanlar (yol haritasında)

* Ajans yöneticisi / bölge moderatörü gibi ara roller.
* Rol bazlı ayrıntılı izin listesi (şu an yardımcı admin için sabit beyaz liste var).
* Tüm yönetici işlemleri için ayrı "işlem kaydı" ekranı (şu an yalnızca para hareketleri `financial_audit_logs`'a yazılıyor).
