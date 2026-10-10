# API uçları

> Otomatik üretildi: `node backend/scripts/gen_docs.mjs`. Elle düzenlemeyin.

Kimlik: **🔒** giriş gerekli · **👑** yalnızca yönetici · **🛠** yönetici + yardımcı admin (destek) · **⏱** hız sınırı adı

**Toplam 258 uç.**

## system.js  (`/api`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/app/config` | açık |  | Uygulama açılışında okunur: zorunlu/isteğe bağlı güncelleme bilgisi. Giriş gerektirmez. |
| POST | `/api/client-errors` | (isteğe bağlı) | client_errors | Giriş ekranındaki hatalar da gönderilebilsin diye oturum zorunlu değildir; IP başına sınırlıdır. |

## auth.js  (`/api/auth`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| POST | `/api/auth/register` | açık | register |  |
| POST | `/api/auth/login` | açık | login |  |
| POST | `/api/auth/refresh` | açık | refresh | Erişim token'ını yeniler. Yenileme token'ı her seferinde değişir; uygulama yenisini saklamalıdır. |
| POST | `/api/auth/session` | 🔒 | session_upgrade | Eski (30 günlük) token ile giriş yapmış uygulama güncellenince cihaz oturumuna geçer; yeniden giriş gerekmez. |
| POST | `/api/auth/logout` | (isteğe bağlı) | logout | Çıkış: bu cihazın oturumu sunucuda da kapanır (erişim token'ının süresi dolmuş olsa bile yenileme token'ıyla). |

## me.js  (`/api/me`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/me` | 🔒 |  |  |
| PATCH | `/api/me` | 🔒 |  |  |
| PUT | `/api/me/avatar` | 🔒 | avatar_upload |  |
| PUT | `/api/me/cover` | 🔒 | cover_upload |  |
| POST | `/api/me/password` | 🔒 | password |  |
| DELETE | `/api/me` | 🔒 | acct_delete | Mağaza kuralları gereği uygulama içinden hesap silme. |
| GET | `/api/me/sessions` | 🔒 |  | ---- Cihaz oturumları ("Oturumlarım") ---- |
| DELETE | `/api/me/sessions/:id` | 🔒 | session_revoke |  |
| POST | `/api/me/sessions/revoke-others` | 🔒 | session_revoke | geçersiz olur. Bu cihaz yeni bir erişim token'ı alır. |
| POST | `/api/me/kyc/request` | 🔒 |  |  |
| POST | `/api/me/diamonds/exchange` | 🔒 | diamond_exchange |  |
| GET | `/api/me/wallet` | 🔒 |  |  |
| GET | `/api/me/earnings/summary` | 🔒 |  |  |
| GET | `/api/me/earnings/history` | 🔒 |  | Canlı yayın geçmişi (video/sesli): mikrofonda geçirilen oturumlar ve o oturumda alınan elmas. |
| GET | `/api/me/levels` | 🔒 |  | Seviye Merkezi: kullanıcı seviyesi (gönderilen coin) ve yayıncı seviyesi (alınan elmas), 160 kademe. |
| GET | `/api/me/badges` | 🔒 |  | Kırmızı rozetler (yeni ziyaretçi, yeni takipçi, bekleyen arkadaş isteği). |
| POST | `/api/me/seen` | 🔒 |  | Liste açılınca rozet sıfırlanır. |
| GET | `/api/me/visitors` | 🔒 |  | Profil ziyaretçileri: sayı herkese açık, liste WIP kademesine bağlı (viewVisitors). |

## users.js  (`/api/users`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/users/search` | 🔒 | user_search | Gizli kullanıcılar aramada çıkmaz. |
| GET | `/api/users/:userId/card` | 🔒 |  | Oda içi profil kartı: "Yakın Arkadaşlarım" (bu kişiye en çok hediye gönderen 5 kişi) ve "Madalyalar" (rozetler). |
| GET | `/api/users/:userId` | 🔒 |  |  |
| POST | `/api/users/:userId/follow` | 🔒 | follow |  |
| DELETE | `/api/users/:userId/follow` | 🔒 |  |  |
| GET | `/api/users/:userId/followers` | 🔒 |  |  |
| GET | `/api/users/:userId/following` | 🔒 |  |  |

## inventory.js  (`/api/inventory`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/inventory` | 🔒 |  |  |
| POST | `/api/inventory/equip` | 🔒 |  |  |
| POST | `/api/inventory/unequip` | 🔒 |  |  |
| GET | `/api/inventory/catalog/frames` | 🔒 |  |  |
| GET | `/api/inventory/catalog/entrance-effects` | 🔒 |  |  |

## rooms.js  (`/api/rooms`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/rooms` | (isteğe bağlı) |  | ---------- Liste ve ayrıntı ---------- |
| GET | `/api/rooms/mine` | 🔒 |  | Kayıtlı odalarım ve şu an açık olanlar. |
| POST | `/api/rooms` | 🔒 | room_create | Oda aç: kayıtlı oda varsa doğrudan açar; yoksa gövdedeki bilgilerle bir kez kurar. |
| GET | `/api/rooms/:roomId/managers` | 🔒 |  | Oda yöneticileri (oda kapalıyken de kalıcı). Oda sahibi ilk sırada. |
| GET | `/api/rooms/favorites` | 🔒 |  |  |
| GET | `/api/rooms/recent` | 🔒 |  |  |
| POST | `/api/rooms/hosts/:userId/favorite` | 🔒 | favorite |  |
| DELETE | `/api/rooms/hosts/:userId/favorite` | 🔒 |  |  |
| GET | `/api/rooms/hosts/:userId/favorite` | 🔒 |  |  |
| GET | `/api/rooms/:roomId` | 🔒 |  |  |
| POST | `/api/rooms/by-code` | 🔒 | room_code | Gizli odaya davet koduyla ulaşılır. Kaba kuvvet denemelerine karşı sıkı sınır vardır. |
| POST | `/api/rooms/:roomId/join` | 🔒 | room_join |  |
| PATCH | `/api/rooms/:roomId` | 🔒 | room_settings | Oda ayarları: ad, etiketler, şifre, sohbet açık/kapalı (oda sahibi ve yardımcı sahip). |
| PUT | `/api/rooms/:roomId/cover` | 🔒 | room_cover | Oda kapak fotoğrafı (oda sahibi / yardımcı sahip). |
| DELETE | `/api/rooms/:roomId/staff/:userId` | 🔒 | moderate | Yönetici silme: odada olmasa da kalıcı yönetici listesinden çıkarır (yalnızca oda sahibi). |
| GET | `/api/rooms/:roomId/contributions` | 🔒 |  | Katkı listesi: odaya en çok hediye gönderenler (24 saat / toplam). |
| POST | `/api/rooms/:roomId/leave` | 🔒 |  |  |
| POST | `/api/rooms/:roomId/close` | 🔒 |  |  |
| GET | `/api/rooms/:roomId/members` | 🔒 |  |  |
| POST | `/api/rooms/:roomId/heartbeat` | 🔒 | heartbeat | Uygulamadan düzenli gelen "oda açık" sinyali: üyeyi canlı tutar ve oda arada kapanmışsa istemciye hemen 404 döner. |
| POST | `/api/rooms/:roomId/mic/take` | 🔒 | mic | ---------- Mikrofon / koltuk ---------- |
| GET | `/api/rooms/:roomId/mic/queue` | 🔒 |  | ---------- Mikrofon sırası ---------- |
| POST | `/api/rooms/:roomId/mic/queue` | 🔒 | mic_queue |  |
| DELETE | `/api/rooms/:roomId/mic/queue` | 🔒 |  |  |
| DELETE | `/api/rooms/:roomId/mic/queue/:userId` | 🔒 |  | Yetkili: mikrofon isteğini reddeder (kullanıcıyı sıradan çıkarır). |
| POST | `/api/rooms/:roomId/mic/leave` | 🔒 |  |  |
| POST | `/api/rooms/:roomId/members/:userId/mic-off` | 🔒 | moderate |  |
| POST | `/api/rooms/:roomId/members/:userId/kick` | 🔒 | moderate |  |
| POST | `/api/rooms/:roomId/members/:userId/block` | 🔒 | moderate |  |
| DELETE | `/api/rooms/:roomId/blocks/:userId` | 🔒 |  |  |
| POST | `/api/rooms/:roomId/seats/:index/lock` | 🔒 | moderate | Koltuk kilitle / aç (oda sahibi ve moderatörler). Dolu koltuk kilitlenirse oturan kişi koltuktan indirilir (yetki yeterliyse). |
| POST | `/api/rooms/:roomId/members/:userId/mic-invite` | 🔒 | mic_invite | Mikrofona davet: davet edilen kişi kabul ederse mic/take ile oturur. |
| POST | `/api/rooms/:roomId/members/:userId/role` | 🔒 | moderate |  |
| GET | `/api/rooms/:roomId/scoreboard` | 🔒 |  | ---------- Hediye sayı tahtası (mikrofon koltuğu başına) ---------- |
| POST | `/api/rooms/:roomId/scoreboard/reset` | 🔒 | scoreboard_reset |  |
| POST | `/api/rooms/:roomId/livekit-token` | 🔒 |  | ---------- LiveKit ---------- |

## chat.js  (`/api/rooms`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| POST | `/api/rooms/:roomId/messages` | 🔒 | chat10s, chat1m |  |
| GET | `/api/rooms/:roomId/messages` | 🔒 |  |  |
| DELETE | `/api/rooms/:roomId/messages` | 🔒 | chat_clear | Sohbeti temizle: yalnızca oda sahibi, yardımcı sahip ve moderatör. |
| DELETE | `/api/rooms/:roomId/messages/:messageId` | 🔒 |  |  |
| POST | `/api/rooms/:roomId/members/:userId/chat-mute` | 🔒 | moderate | Sohbette susturma: 0 = susturmayı kaldır, en fazla 24 saat. |

## messages.js  (`/api/messages`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/messages/unread-count` | 🔒 |  |  |
| GET | `/api/messages/conversations` | 🔒 |  |  |
| GET | `/api/messages/with/:userId` | 🔒 |  | Konuşma geçmişi (en yeni 50, eskiden yeniye). Karşı tarafın mesajları okundu işaretlenir. |
| POST | `/api/messages/with/:userId` | 🔒 | dm10s, dm1h |  |

## friends.js  (`/api/friends`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/friends` | 🔒 |  | Arkadaş listesi |
| GET | `/api/friends/requests` | 🔒 |  | Bana gelen bekleyen istekler |
| POST | `/api/friends/request/:userId` | 🔒 | friendreq | Arkadaşlık isteği gönder (karşı taraf zaten istek göndermişse otomatik kabul olur) |
| POST | `/api/friends/accept/:userId` | 🔒 |  |  |
| POST | `/api/friends/decline/:userId` | 🔒 |  |  |
| DELETE | `/api/friends/:userId` | 🔒 |  | Arkadaşlıktan çıkar veya gönderdiğim bekleyen isteği geri çek |

## store.js  (`/api/store`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/store/coin-packages` | 🔒 |  | Yükleme Merkezi paketleri |
| GET | `/api/store/items` | 🔒 |  |  |
| POST | `/api/store/buy` | 🔒 | store_buy | Satın al (kendin için) veya "Gönder" (başka bir kullanıcıya hediye). Süre: ürünün gün sayısı; aynı ürün tekrar alınırsa süre uzar. |

## support.js  (`/api/support`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/support/messages` | 🔒 |  | Kendi müşteri hizmetleri yazışmam (son 200). Okunmamış destek yanıtları okundu olur. |
| GET | `/api/support/unread` | 🔒 |  |  |
| POST | `/api/support/messages` | 🔒 | support10s, support1h |  |

## leaderboards.js  (`/api/leaderboards`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/leaderboards` | 🔒 |  | Kendine gönderilen hediyeler sıralamaya dahil edilmez (kendi kendine puan basmayı önlemek için). |

## families.js  (`/api/families`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/families` | 🔒 |  |  |
| GET | `/api/families/mine` | 🔒 |  |  |
| GET | `/api/families/:familyId` | 🔒 |  |  |
| POST | `/api/families` | 🔒 |  |  |
| PATCH | `/api/families/:familyId` | 🔒 |  |  |
| POST | `/api/families/:familyId/join` | 🔒 |  |  |
| POST | `/api/families/:familyId/leave` | 🔒 |  |  |
| GET | `/api/families/:familyId/members` | 🔒 |  |  |
| POST | `/api/families/:familyId/members/:userId/kick` | 🔒 |  |  |
| POST | `/api/families/:familyId/members/:userId/role` | 🔒 |  |  |
| POST | `/api/families/:familyId/transfer` | 🔒 |  |  |
| DELETE | `/api/families/:familyId` | 🔒 |  |  |

## wip.js  (`/api/wip`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/wip/tiers` | 🔒 |  | Kademeler ve satın alınabilir paketler. |
| GET | `/api/wip` | 🔒 |  |  |
| POST | `/api/wip/purchase` | 🔒 | wip_buy | düşük seviye aktifken satın alınamaz. |

## dealers.js  (`/api/dealer`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/dealer/me` | 🔒 |  |  |
| POST | `/api/dealer/sell` | 🔒 | dealer_sell | Bayi kendi bakiyesinden kullanıcıya Coin satar. Alıcı kullanıcı adı veya kimlik ile bulunur. |

## admin.js  (`/api/admin`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/admin/me/permissions` | 🛠 |  |  |
| GET | `/api/admin/users` | 🛠 |  | ---------------- Kullanıcı arama ve durum ---------------- |
| POST | `/api/admin/users/:userId/ban` | 🛠 |  | Süreli veya süresiz ban. hours yoksa/0 ise süresiz. |
| POST | `/api/admin/users/:userId/unban` | 🛠 |  |  |
| POST | `/api/admin/users/:userId/display-name` | 🛠 |  | Kullanıcının görünen adını (nick) değiştirir. Yasaklı kelime denetimi uygulanmaz (yetkili işlemi) ama uzunluk denetlenir. |
| POST | `/api/admin/users/:userId/avatar` | 🛠 |  | Profil fotoğrafını kaldırır (avatarUrl boş) veya https adresiyle değiştirir. |
| POST | `/api/admin/users/:userId/staff-role` | 👑 |  | Yardımcı admin atama/alma: yalnızca yönetici, admin panelinden. |
| GET | `/api/admin/staff` | 👑 |  |  |
| POST | `/api/admin/users/:userId/coins` | 👑 |  | ---------------- Coin (yalnızca yönetici) ---------------- |
| POST | `/api/admin/users/:userId/wip` | 🛠 |  | ---------------- WIP ---------------- |
| DELETE | `/api/admin/users/:userId/wip` | 🛠 |  |  |
| PATCH | `/api/admin/wip/tiers/:level` | 👑 |  |  |
| POST | `/api/admin/wip/plans` | 👑 |  |  |
| POST | `/api/admin/users/:userId/inventory` | 🛠 |  | ---------------- Envanter ---------------- |
| GET | `/api/admin/support/threads` | 🛠 |  | ---------------- Müşteri hizmetleri (admin + yardımcı admin) ---------------- |
| GET | `/api/admin/support/:userId` | 🛠 |  |  |
| POST | `/api/admin/support/:userId/reply` | 🛠 |  |  |
| GET | `/api/admin/coin-packages` | 👑 |  | ---------------- Coin paketleri (yönetici) ---------------- |
| POST | `/api/admin/coin-packages` | 👑 |  |  |
| POST | `/api/admin/coin-packages/:id/active` | 👑 |  |  |
| GET | `/api/admin/grantables` | 👑 |  | Yönetici "öğe ver" listesi: kategoriye göre tüm katalog öğeleri. |
| POST | `/api/admin/users/:userId/grant` | 👑 |  | Seçilen katalog öğesini kullanıcıya ver. days boş/0 = süresiz. |
| POST | `/api/admin/media` | 👑 |  |  |
| POST | `/api/admin/gifts` | 👑 |  |  |
| POST | `/api/admin/frames` | 👑 |  |  |
| POST | `/api/admin/entrance-effects` | 👑 |  |  |
| GET | `/api/admin/store/items` | 👑 |  |  |
| POST | `/api/admin/store/items` | 👑 |  |  |
| POST | `/api/admin/store/items/:id/active` | 👑 |  |  |
| DELETE | `/api/admin/gifts/:id` | 👑 |  |  |
| DELETE | `/api/admin/store/items/:id` | 👑 |  |  |
| DELETE | `/api/admin/frames/:id` | 👑 |  |  |
| GET | `/api/admin/catalog` | 👑 |  |  |
| POST | `/api/admin/catalog/:kind/:id/active` | 👑 |  |  |
| GET | `/api/admin/dealers` | 👑 |  | ---------------- Bayi (yalnızca yönetici) ---------------- |
| POST | `/api/admin/dealers` | 👑 |  |  |
| POST | `/api/admin/dealers/:dealerId/coins` | 👑 |  |  |
| POST | `/api/admin/dealers/:dealerId/sell` | 👑 |  |  |
| GET | `/api/admin/agencies` | 🛠 |  | ---------------- Ajans ve yayıncı ---------------- |
| POST | `/api/admin/agencies/:agencyId/status` | 👑 |  | Komisyon para etkisi taşıdığı için yalnızca yönetici. |
| GET | `/api/admin/broadcasters` | 🛠 |  |  |
| POST | `/api/admin/broadcasters/:userId/status` | 🛠 |  |  |
| GET | `/api/admin/agency-config` | 🛠 |  | ---------------- Ajans ayarları, etkinlikler, dönem kapatma, KYC ---------------- |
| PUT | `/api/admin/agency-config` | 👑 |  |  |
| POST | `/api/admin/agencies/:agencyId/commission-override` | 👑 |  |  |
| POST | `/api/admin/broadcasters/:userId/contract` | 👑 |  |  |
| POST | `/api/admin/events` | 🛠 |  |  |
| GET | `/api/admin/events` | 🛠 |  |  |
| POST | `/api/admin/events/:id/attendance` | 🛠 |  |  |
| POST | `/api/admin/payouts/close` | 👑 |  | Dönemi kapat (hesap özetleri üretir). period boş ise bir önceki dönem. |
| GET | `/api/admin/payouts` | 🛠 |  |  |
| GET | `/api/admin/payouts/:id` | 🛠 |  |  |
| POST | `/api/admin/statements/:kind/:id/pay` | 👑 |  | Ödeme platform dışında yapılır; burada yalnızca "ödendi" işaretlenir. Yayıncı için KYC onayı şarttır. |
| GET | `/api/admin/kyc` | 🛠 |  |  |
| POST | `/api/admin/users/:userId/kyc` | 👑 |  |  |
| GET | `/api/admin/finance/audit` | 👑 |  |  |
| POST | `/api/admin/music/tracks` | 👑 |  | Telif: yalnızca kullanım hakkına sahip olduğunuz parçaları ekleyin; lisans notu zorunludur. |
| GET | `/api/admin/music/tracks` | 👑 |  |  |
| GET | `/api/admin/reports` | 🛠 |  | ---------------- Şikâyetler (admin + support) ---------------- |
| POST | `/api/admin/reports/:id/resolve` | 🛠 |  |  |
| GET | `/api/admin/security/events` | 👑 |  | ---------------- Güvenlik duvarı (yalnızca yönetici) ---------------- |
| GET | `/api/admin/security/blocks` | 👑 |  |  |
| POST | `/api/admin/security/blocks` | 👑 |  |  |
| DELETE | `/api/admin/security/blocks/:ip` | 👑 |  |  |
| GET | `/api/admin/banners` | 🛠 |  | ---------- Banner ve duyuru yönetimi (yalnızca yönetici) ---------- |
| PUT | `/api/admin/banners/image` | 🛠 |  |  |
| POST | `/api/admin/banners` | 🛠 |  |  |
| PATCH | `/api/admin/banners/:id` | 🛠 |  |  |
| DELETE | `/api/admin/banners/:id` | 🛠 |  |  |
| POST | `/api/admin/announcements` | 🛠 |  |  |
| DELETE | `/api/admin/announcements/:id` | 🛠 |  |  |
| GET | `/api/admin/dashboard` | 👑 |  |  |
| GET | `/api/admin/client-errors` | 👑 |  |  |
| DELETE | `/api/admin/client-errors` | 👑 |  |  |
| GET | `/api/admin/actions` | 👑 |  | Yönetici/yardımcı admin işlemleri ve para hareketleri tek listede: kim, ne zaman, kime, ne yaptı. |
| GET | `/api/admin/app-config` | 👑 |  |  |
| PUT | `/api/admin/app-config` | 👑 |  |  |
| GET | `/api/admin/moderation/strikes` | 👑 |  |  |
| POST | `/api/admin/users/:userId/chat-restriction` | 🛠 |  | Sohbet kısıtı: dakika (0 = kaldır). Yardımcı admin de kullanabilir (yalnızca normal kullanıcılara). |
| GET | `/api/admin/users/:userId/devices` | 👑 |  | Cihazlar: kullanıcının oturumları ve aynı cihazı kullanan diğer hesaplar (çoklu hesap / hile tespiti). |
| POST | `/api/admin/users/:userId/sessions/revoke-all` | 👑 |  | Kullanıcının tüm cihazlarındaki oturumları kapatır (hesap çalındı şüphesi vb.). |

## feed.js  (`/api`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/banners` | açık |  | ---------- Banner'lar ---------- |
| GET | `/api/announcements` | 🔒 |  | ---------- Duyurular (Mesajlar ekranındaki kartlar) ---------- |
| GET | `/api/inbox-summary` | 🔒 |  | Kart rozetleri: okunmamış duyuru sayıları ve yeni takipçiler. |
| POST | `/api/inbox-summary/seen` | 🔒 |  |  |
| GET | `/api/posts` | (isteğe bağlı) |  | ---------- Gönderi akışı ---------- |
| PUT | `/api/posts/image` | 🔒 | post_image |  |
| POST | `/api/posts` | 🔒 | post_create |  |
| DELETE | `/api/posts/:id` | 🔒 |  |  |
| POST | `/api/posts/:id/like` | 🔒 | post_like |  |
| DELETE | `/api/posts/:id/like` | 🔒 |  |  |
| GET | `/api/posts/:id/comments` | (isteğe bağlı) |  |  |
| POST | `/api/posts/:id/comments` | 🔒 | post_comment |  |

## gifts.js  (`/api`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/gifts` | 🔒 |  |  |
| GET | `/api/gifts/global/recent` | 🔒 |  | Uygulama açılışında şeridi doldurmak için son global hediyeler. |
| POST | `/api/rooms/:roomId/gifts/send` | 🔒 | gift | - Kendine hediye; ajans/maaş hesabına, PK puanına ve liderlik tablolarına SAYILMAZ (suistimali önlemek için). |

## agencies.js  (`/api`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/agencies` | 🔒 |  | ---------------- Ajans ---------------- |
| POST | `/api/agencies` | 🔒 |  |  |
| GET | `/api/agencies/mine` | 🔒 |  |  |
| PATCH | `/api/agencies/:agencyId` | 🔒 |  |  |
| GET | `/api/agencies/:agencyId/dashboard` | 🔒 |  | Ajans paneli: canlı dönem verileri, komisyon kademesi, bir sonraki kademeye kalan, yayıncı bazında ilerleme. |
| GET | `/api/agencies/:agencyId/statements` | 🔒 |  |  |
| GET | `/api/agencies/by-code/:code` | 🔒 |  | Ajans koduyla ajans bilgisi ve başvuru. |
| POST | `/api/agencies/apply-by-code` | 🔒 |  |  |
| GET | `/api/agencies/:agencyId/requests` | 🔒 |  |  |
| POST | `/api/agencies/:agencyId/invite` | 🔒 |  |  |
| POST | `/api/agencies/:agencyId/apply` | 🔒 |  |  |
| POST | `/api/agency-requests/:requestId/respond` | 🔒 |  | Davet eden değil, karşı taraf yanıtlar: davete kullanıcı, başvuruya ajans sahibi. |
| POST | `/api/agencies/:agencyId/broadcasters/:userId/remove` | 🔒 |  |  |
| POST | `/api/broadcaster/apply` | 🔒 |  | ---------------- Yayıncı ---------------- |
| GET | `/api/broadcaster/me` | 🔒 |  |  |
| GET | `/api/broadcaster/statements` | 🔒 |  |  |
| GET | `/api/broadcaster/requests` | 🔒 |  |  |
| POST | `/api/broadcaster/leave-agency` | 🔒 |  |  |

## music.js  (`/api`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/music/tracks` | 🔒 |  | Müzik kütüphanesi (yalnızca yönetici tarafından eklenen, lisansı kayıtlı parçalar). |
| POST | `/api/rooms/:roomId/music/upload` | 🔒 |  |  |
| GET | `/api/rooms/:roomId/music` | 🔒 |  |  |
| POST | `/api/rooms/:roomId/music/queue` | 🔒 | music_queue |  |
| DELETE | `/api/rooms/:roomId/music/queue/:itemId` | 🔒 |  |  |
| POST | `/api/rooms/:roomId/music/play` | 🔒 | music_ctl |  |
| POST | `/api/rooms/:roomId/music/pause` | 🔒 | music_ctl |  |
| POST | `/api/rooms/:roomId/music/seek` | 🔒 | music_ctl |  |
| POST | `/api/rooms/:roomId/music/next` | 🔒 | music_ctl |  |
| POST | `/api/rooms/:roomId/music/stop` | 🔒 | music_ctl |  |

## luckybag.js  (`/api`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/lucky-bags/config` | 🔒 |  |  |
| GET | `/api/rooms/:roomId/lucky-bags` | 🔒 |  |  |
| POST | `/api/rooms/:roomId/lucky-bags` | 🔒 | lucky_send |  |
| POST | `/api/lucky-bags/:id/claim` | 🔒 | lucky_claim |  |
| GET | `/api/me/daily` | 🔒 |  | Günlük görevler |

## pk.js  (`/api`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| POST | `/api/pk/challenge` | 🔒 | pk | Meydan okuma: yalnızca kendi odanızın sahibi başka bir odaya PK daveti gönderir. |
| POST | `/api/pk/:id/respond` | 🔒 | pk |  |
| POST | `/api/pk/:id/cancel` | 🔒 |  | Bekleyen daveti geri çek (davet eden) veya süren PK'yı erken bitir (iki oda sahibinden biri). |
| GET | `/api/rooms/:roomId/pk` | 🔒 |  |  |
| GET | `/api/pk/rooms` | 🔒 |  | PK için aday odalar: açık, PK'sı olmayan, gizli olmayan odalar. |

## games.js  (`/api`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/rooms/:roomId/game` | 🔒 |  |  |
| POST | `/api/rooms/:roomId/games` | 🔒 | game_create | Oyun kurma: oda sahibi / yardımcı sahip / moderatör. Ücretsizdir, Coin bahsi yoktur. |
| POST | `/api/games/:id/join` | 🔒 | game |  |
| POST | `/api/games/:id/leave` | 🔒 |  |  |
| POST | `/api/games/:id/start` | 🔒 |  |  |
| POST | `/api/games/:id/cancel` | 🔒 |  |  |
| POST | `/api/games/:id/roll` | 🔒 | game_move |  |
| POST | `/api/games/:id/move` | 🔒 | game_move |  |

## safety.js  (`/api`)

| Yöntem | Yol | Kimlik | ⏱ | Not |
|---|---|---|---|---|
| GET | `/api/blocks` | 🔒 |  | ---------------- Kullanıcı engelleme ---------------- |
| POST | `/api/blocks/:userId` | 🔒 | block |  |
| DELETE | `/api/blocks/:userId` | 🔒 |  |  |
| POST | `/api/reports` | 🔒 | report | ---------------- Şikâyet ---------------- |
