# Coin / Elmas ekonomisi

## Birimler

| Birim | Kimde | Nasıl gelir | Nereye gider |
|---|---|---|---|
| **Coin** | Her kullanıcı | Bayi satışı, yönetici yüklemesi, günlük seri ödülü, şanslı çanta, elmas bozdurma | Hediye, mağaza, WIP, şanslı çanta |
| **Elmas (Diamond)** | Hediye alan | Alınan hediyenin Coin değeri kadar (1 Coin = 1 Elmas) | Bozdurma (5 Elmas = 1 Coin) veya yayıncı maaşı |
| **Bayi bakiyesi** | Bayi hesabı | Yönetici yükler | Kullanıcıya Coin satışı |

Bakiye hiçbir zaman eksiye düşemez (veritabanı kısıtı `users_balances_nonneg`, `dealer_balance_nonneg`).
Kullanıcı bakiyesi başkalarına gösterilmez (`views.js`).

## Para hareketi kuralları (değişmez)

1. Bakiye değiştiren her işlem **tek veritabanı işlemi** (`tx`) içindedir; yarıda kalırsa hiçbir şey değişmez.
2. İlgili kullanıcı satırları **tek sorguda, id sırasıyla** `FOR UPDATE` ile kilitlenir (aynı anda iki hediye çifte harcama yapamaz, kilitlenme olmaz).
3. Her hareket `wallet_transactions`'a yazılır. Yönetici/bayi/mağaza/WIP hareketleri ayrıca `financial_audit_logs`'a önce-sonra bakiyesiyle yazılır.
4. Miktarlar sunucuda `BigInt` ile hesaplanır, istemciye metin olarak döner (büyük sayılarda hassasiyet kaybı olmaz).

`wallet_transactions.transaction_type` değerleri:
`gift_sent`, `gift_received`, `diamond_exchange`, `dealer_credit`, `admin_adjustment`, `daily_bonus`,
`lucky_bag_sent`, `lucky_bag_received`, `lucky_bag_refund`, `store_purchase`, `wip_purchase`, `lucky_gift_win`.

## Hediye

`POST /api/rooms/:roomId/gifts/send` — gönderen odada olmalı, alıcılar odada olmalı.

* Dağıtım: `single`, `each` (seçilenlerin her birine), `all_mic`, `all_room`, `equal`, `random`, `selected`.
* Toplam = hediye fiyatı × dağıtılan toplam adet. Gönderenden düşer; her alıcıya kendi payı kadar Elmas eklenir.
* Gönderenin `total_sent_coins` → kullanıcı seviyesi, alıcının `total_received_diamonds` → yayıncı seviyesi (160 kademe).
* Kendine hediye serbesttir, ama **ajans/maaş, PK puanı ve liderlik tablolarına sayılmaz**.
* Değeri `GLOBAL_GIFT_MIN_COINS` (varsayılan 1000) ve üstü hediyeler tüm kullanıcılara global şerit olarak gider.

## Elmas bozdurma

`POST /api/me/diamonds/exchange` — 5'in katı Elmas → Coin. Onaylı yayıncılar bozdurma yapamaz (Elmasları maaş hesabına sayılır).

## Bayi

Yönetici bayiye Coin yükler (`POST /api/admin/dealers/:id/coins`). Bayi, kullanıcı adı/ID ile kullanıcıya satar (`POST /api/dealer/sell`).
Gerçek para ödemesi uygulama dışında yapılır. Her satış denetim kaydına yazılır.
Mağazadaki "Yükleme Merkezi" paketleri (`coin_packages`) şu an yalnızca fiyat bilgisidir; Google Play ödemesi yoktur.

## Ajans / yayıncı maaşı

* Dönem: haftalık (Pzt–Paz) veya aylık, Türkiye saati.
* Yayıncı saati = mikrofonda geçirilen süre (`mic_sessions`).
* Yayıncı maaşı: Elmas hedefine göre kademe; kademenin saat hedefi tutmazsa `penalty_bps` kadar kesinti.
* Ajans komisyonu: ekibin toplam Elmasına göre kademeli oran (ajansa özel oran tanımlanabilir).
* Sayılanlar: yalnızca onaylı yayıncıya, aktif ajansa gelen, kendine gönderilmeyen hediyeler.
* Dönem kapatma `POST /api/admin/payouts/close` → `host_statements`, `agency_statements`. Kapanan dönem değişmez.
* Ödeme platform dışında yapılır; panelde "ödendi" işaretlenir. Yayıncı maaşı için KYC onayı şarttır.

Rakamlar örnektir; yönetici panelindeki "Maaş/Dönem" sekmesinden değiştirilir.

## Şanslı çanta

`backend/src/services/rewards_config.js` → `BAG_TIERS`.

| Kademe | Toplam Coin | Kişi | Geri sayım | Açık kalma |
|---|---|---|---|---|
| n3 / n6 / n9 | 3.000 / 6.000 / 9.000 | 10 / 20 / 30 | yok | 30 dk |
| s30 / s60 / s90 (süper) | 30.000 / 60.000 / 90.000 | 50 | 60 sn | 120 sn |

Dağıtılmayan Coin göndericiye iade edilir (`lucky_bag_refund`). Süper çanta tüm kullanıcılara duyurulur.

## Günlük görevler

Odaya gir, mikrofona otur, 5 mesaj yaz, hediye gönder. Görev başına 10 XP, gün tamamlanınca 50 XP; 7 gün üst üste tamamlanınca 1.000 Coin.

## Seviyeler

* Kullanıcı seviyesi: gönderilen Coin (EXP); yayıncı seviyesi: alınan Elmas. 160 kademe, `levels.js`.
* Aile seviyesi: aile puanı; kapasite 30 → 200 üye.
* WIP 1–10 + SWIP: satın alınan süreli ayrıcalık. Ayrıntı aşağıda "WIP kademeleri".

## Henüz olmayanlar (yol haritasında)

Google Play ile Coin satın alma, iade/geri ödeme akışı, vergi kesintisi, hazine kutusu, CP hediyesi, yayıncı bonusu,
hazine kutusu.

## Tekrar koruması (v2.37)

Para harcayan her istek (hediye, mağaza, WIP, bozdurma, bayi satışı, şanslı çanta, yönetici Coin düzeltmesi) uygulamadan
bir `Idempotency-Key` ile gelir. Sunucu aynı anahtarı ikinci kez görürse işlemi **yapmaz**, ilk yanıtı aynen döndürür.
Bu yüzden zayıf ağda uygulama isteği kendiliğinden bir kez daha deneyebilir; Coin iki kez düşmez. Hatalı istekte anahtar
silinir (düzeltilip tekrar denenebilir). Anahtarlar 24 saat saklanır (`idempotency_keys`).

## Combo hediye (v2.37)

Hediye gönderildikten sonra pencere açık kalır ve 5 sn boyunca "COMBO xN" düğmesi görünür; her dokunuş aynı hediyeyi aynı
kişilere tekrar gönderir (her biri ayrı ödenir, ayrı tekrar korumalıdır). Sunucu 6 sn içindeki aynı gönderimi sayar,
odadaki şerit yeni şerit açmak yerine büyüyen "xN" sayacıyla uzar.

## WIP kademeleri (v2.38)

Yoho'daki VIP kademelerinin ayrıcalıkları 10 kademeye sıkıştırıldı: Yoho'nun en üst kademesi = **WIP 10**. Üstünde tek bir
**SWIP** (seviye 11) var; ek olarak hayalet mod verir. Ayrıcalıklar birikimlidir. Değerler Panel > WIP kademelerinden değişir.

| Kademe | 30 gün | Yeni açılan | İsim efekti | Giriş aracı |
|---|---|---|---|---|
| WIP 1 Bronz | 5.000 | Rozet, renkli isim, balon, çerçeve | renkli | 🛵 Scooter |
| WIP 2 Gümüş | 12.000 | Ziyaretçileri görme | renkli | 🏍️ Motosiklet |
| WIP 3 Altın | 25.000 | Vip hediyeler | kalın | 🚗 Klasik Araba |
| WIP 4 Zümrüt | 50.000 | Susturulamaz, 2 oda | parlayan | 🚙 Arazi Aracı |
| WIP 5 Ametist | 90.000 | Profil ışık efekti | neon nabız | 🏎️ Yarış Arabası |
| WIP 6 Kraliyet | 150.000 | Odadan atılamaz, özel oda teması, hareketli çerçeve | altın parıltı | 🛥️ Lüks Yat |
| WIP 7 Yeşim | 250.000 | Gizli ziyaret, 3 oda | yeşim parıltı | 🚁 Helikopter |
| WIP 8 Buz | 400.000 | Hareketli profil fotoğrafı, çerçevede yıldızlar | buz | 🛩️ Özel Jet |
| WIP 9 Gökkuşağı | 650.000 | 4 oda | gökkuşağı | 🚀 Roket |
| WIP 10 Ateş | 1.000.000 | 5 oda | ateş | 🐉 Ejderha |
| SWIP Hayalet | 2.000.000 | Hayalet mod | hayalet | 🛸 Hayalet UFO |

Eski 5 kademe oransal taşındı (1→2, 2→4, 3→6, 4→8, 5→10): kimse ödediği ayrıcalığı kaybetmez. Eski paketler satıştan kalktı.

**Hayalet mod (SWIP):** Ayarlar > Hayalet mod. Açıkken odaya giriş duyurulmaz; dinleyici listesinde, oda kişi sayısında,
toplu hediye alıcılarında ve çevrimiçi göstergelerde görünmez; profil ziyareti iz bırakmaz. Mikrofona çıkınca görünür olur,
inince yeniden görünmez olur (yazı yazar veya hediye gönderirse adı da görünür). Odadan çıkışı da duyurulmaz. Mod açılıp
kapanınca, SWIP alınınca veya yönetici WIP verip alınca bulunduğu odalarda ve çevrimiçi göstergelerde anında güncellenir.
Üyelik bitince kendiliğinden etkisiz kalır (`is_ghost()` SQL işlevi, toplu sayımlarda `active_ghosts` görünümü).

## Şanslı hediye (v2.38)

Hediye penceresindeki **Şanslı** sekmesi (ör. Şanslı Çan 10 Coin, Şanslı Yonca 100 Coin; yeni şanslı hediye Panel > Katalog'dan "Şanslı" sekmesiyle eklenir).

* Gönderen hediye bedelini normal öder. Alıcıya hediye değerinin **alıcı payı** kadarı Elmas olarak geçer (varsayılan %10;
  ajans/maaş, PK, sayı tahtası, aile puanı ve liderlik tablosu bu Elmas'la hesaplanır — `gift_transactions.diamond_amount`).
* Her adet ayrı bir çekiliştir: x2, x5, x10, x50, x100, x500. Kazanç = toplam çarpan × hediye fiyatı, gönderenin Coin'ine eklenir
  (`lucky_gift_win`), tek gönderimde en fazla `luckyMaxWin` (varsayılan 5.000.000).
* **Geri dönüş oranı (RTP)**: uzun vadede gönderilen Coin'in çekilişle geri dönen kısmı (varsayılan %70). Olasılık tablosu bu
  orana göre ölçeklenir. Kural: RTP + alıcı payı ≤ %95 (sunucu ve panel denetler) — platform her zaman en az %5 kazanır.
* Çarpan ≥ `luckyAnnounceMultiplier` (varsayılan x100) **ve** tek isabetin değeri global hediye eşiğinin üstündeyse tüm
  uygulamaya şerit duyurusu (gizli odalar hariç). PK destekçi sıralaması gönderenin harcadığı Coin'le, PK puanı alıcıya geçen Elmas'la sayılır.
* Ayarlar çekiliş anında da sınırlanır (RTP ≤ %95 − alıcı payı); ayar kaydı tek işlemde yapılır.
* Panel > Uygulama ayarları > Şanslı hediye: aç/kapa, RTP %, alıcı payı %, en fazla kazanç, duyuru çarpanı. Kapalıyken sekme görünmez.
* Not: Coin gerçek parayla satılıyorsa şans mekaniği bazı mağaza/mevzuat kurallarında "şans oyunu" sayılabilir; panelden tek
  dokunuşla kapatılabilir.
