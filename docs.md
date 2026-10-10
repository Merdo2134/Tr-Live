# TR Live — teknik notlar ve API özeti

Tüm yanıtlar JSON ve **camelCase**'tir. Hatalar `{ "message": "..." }` biçimindedir. Para miktarları (Coin/Diamond) metin olarak döner.
Kimlik doğrulama: `Authorization: Bearer <token>`. WebSocket: `wss://host/ws?token=<token>`.

## Tek kaynak ilkesi
Coin, Diamond, hediye ve finans hareketleri `users`, `gift_transactions`, `wallet_transactions`, `financial_audit_logs` tablolarında tutulur.
Kullanıcı bakiyesi **asla** başka kullanıcılara gösterilmez (`views.js`).

## Uç noktalar
**Auth:** `POST /api/auth/register|login`
**Profil (`/api/me`):** `GET /`, `PATCH /`, `PUT /avatar|cover` (ham png/jpeg/webp, ≤3 MB), `POST /password`, `DELETE /` (şifre ile), `GET /wallet`, `GET /visitors` (WIP 2+), `PATCH / {ghostMode}` (SWIP)
**Kullanıcılar:** `GET /api/users/search?q=`, `GET /:id`, `POST|DELETE /:id/follow`, `GET /:id/followers|following`
**Envanter:** `GET /api/inventory`, `POST /equip|unequip {itemId}`, `GET /catalog/frames|entrance-effects`
**Odalar:** `GET /api/rooms?type=audio|video`, `GET /mine` (kalıcı oda profilleri), `POST /` (ilk seferde kurar, sonra açar; şifre yok), `GET /:id/managers`, `GET /:id`, `POST /:id/join|leave|close`, `GET /:id/members`,
`POST /:id/mic/take {seatIndex?}`, `POST /:id/mic/leave`, `POST /:id/livekit-token`,
`POST /:id/members/:uid/kick|block|mic-off|role {role}`, `DELETE /:id/blocks/:uid`
**Hediye:** `GET /api/gifts`, `GET /api/gifts/global/recent`, `POST /api/rooms/:id/gifts/send`
`{giftId, quantity, distribution: single|equal|random|selected, recipientId?, selectedUserIds?}`
**Aile (`/api/families`):** `GET /?q=`, `GET /mine`, `GET /:id`, `POST /`, `PATCH /:id`, `POST /:id/join|leave|transfer`,
`GET /:id/members`, `POST /:id/members/:uid/kick|role`, `DELETE /:id`
**WIP:** `GET /api/wip/tiers`, `GET /api/wip`, `POST /api/wip/purchase {planId}`
**Ajans/yayıncı:** `GET|POST /api/agencies`, `GET /agencies/mine`, `PATCH /agencies/:id`, `GET /agencies/:id/dashboard?period=YYYY-AA|requests`,
`POST /agencies/:id/invite|apply`, `POST /agency-requests/:id/respond {accept}`, `POST /agencies/:id/broadcasters/:uid/remove`,
`POST /broadcaster/apply`, `GET /broadcaster/me|requests`, `POST /broadcaster/leave-agency`
**Bayi:** `GET /api/dealer/me`, `POST /api/dealer/sell {username|userId, amount}`
**Yönetim (`/api/admin`, admin+support; `*` = yalnızca admin):** `GET /users?q=`, `POST /users/:id/status`, `POST /users/:id/coins*`,
`POST|DELETE /users/:id/wip`, `POST /users/:id/inventory`, `PATCH /wip/tiers/:level*`, `POST /wip/plans*`,
`POST /gifts*|frames*|entrance-effects*`, `POST /catalog/:kind/:id/active*`, `GET|POST /dealers*`, `POST /dealers/:id/coins*|sell*`,
`GET /agencies`, `POST /agencies/:id/status*|settle*`, `GET /broadcasters`, `POST /broadcasters/:uid/status`, `GET /finance/audit*`

## WebSocket olayları
İstemci → sunucu: `room_subscribe {roomId}`, `room_unsubscribe`, `ping`.
Sunucu → istemci: `connected`, `room_subscribed`, `room_member_joined|left`, `room_seat_changed`, `room_role_changed`, `room_gift`,
`global_gift_ribbon`, `room_closed`, `room_kicked`, `room_blocked`, `error {code: not_member}`.

## Hediye işlemi
Tek PostgreSQL transaction. İlgili tüm kullanıcı satırları tek sorguda `ORDER BY id FOR UPDATE` ile kilitlenir (deadlock önlemi).
Gönderici odada olmalı. Kendine hediye serbesttir (bkz. README kuralları).

## Ajans / yayıncı maaş sistemi (v2.3, Yoho tarzı)
**Rakamlar ÖRNEKTİR** (Yoho'nun gerçek oranları açıklanmıyor); yönetici panelindeki "Maaş/Dönem" sekmesinden veya `PUT /api/admin/agency-config` ile değiştirilir.
- **Dönem:** haftalık (Pzt–Paz) veya aylık, Türkiye saati (UTC+3). Anahtar: `2026-10` veya `W2026-09-28`.
- **Yayıncı saati:** `mic_sessions` (mikrofon koltuğunda geçen süre; bir kullanıcı aynı anda tek odada sayılır).
- **Yayıncı maaşı (`host_salary_tiers`):** Diamond hedefine göre kademe bulunur; o kademenin saat hedefi tutmadıysa (veya zorunlu resmi etkinlik sayısı tamamlanmadıysa) maaş `penalty_bps` (varsayılan %50) kadar kesilir — tek sefer. Hiçbir kademenin Diamond hedefi tutmazsa maaş 0.
- **Ajans komisyonu (`agency_commission_tiers`):** ekip Diamond toplamına göre kademeli oran; ajansa özel sabit oran (`commission_override_bps`) tanımlanabilir.
- **Sayılanlar:** yalnızca onaylı yayıncıya ve aktif ajansa gelen, KENDİNE GÖNDERİLMEYEN hediyeler (`gift_transactions.receiver_agency_id` hediye anında etiketlenir).
- **Dönem kapatma:** `POST /api/admin/payouts/close {period?, force?}` her yayıncı ve ajans için `host_statements` / `agency_statements` üretir. Kapatılan dönem değiştirilemez; ayarlar o anki hâliyle `payout_periods.config` içinde saklanır.
- **Ödeme:** platform dışında yapılır; `POST /api/admin/statements/{host|agency}/:id/pay` yalnızca "ödendi" işaretler. Yayıncı maaşı için KYC (`users.kyc_status = approved`) şarttır (manuel durum bayrağı).
- **Ajans kodu:** 8 haneli; `GET /api/agencies/by-code/:code`, `POST /api/agencies/apply-by-code`.
- Yayıncı: `GET /api/broadcaster/me` (canlı ilerleme), `GET /api/broadcaster/statements`. Ajans: `GET /api/agencies/:id/dashboard`, `/statements`.
- Resmi etkinlikler: `POST|GET /api/admin/events`, `POST /api/admin/events/:id/attendance`. KYC: `POST /api/me/kyc/request`, `GET /api/admin/kyc`, `POST /api/admin/users/:id/kyc`.

## Roller (v2.4)
| Rol | Kim atar | Yapabildikleri |
|---|---|---|
| Admin | — (uygulama sahibi) | Admin panelindeki her şey |
| Yardımcı admin (`system_role=support`) | Yalnızca admin: `POST /api/admin/users/:id/staff-role` | `GET /admin/users`, `POST /admin/users/:id/ban` (`hours` boşsa süresiz), `/unban`, `/display-name`, `/avatar` |
| Oda sahibi | Odayı açan | Oda üzerindeki her şey |
| Moderatör (oda rolü) | Oda sahibi: `POST /rooms/:id/members/:uid/role` | sohbet silme, `chat-mute`, `mic-invite`, `seats/:i/lock`, `mic-off` (koltuktan kaldır), `kick`, `block` |
Yardımcı admin başka bir admin uç noktasına gidince 403 alır. Olay: `mic_invite`, `room_seats_locked`.

## Oda gezinme ve sıra (v2.4)
`GET /api/rooms?q=` arama · `GET /api/rooms/favorites` · `GET /api/rooms/recent` · `POST|DELETE|GET /api/rooms/hosts/:userId/favorite` ·
`GET|POST|DELETE /api/rooms/:id/mic/queue` · olaylar: `room_mic_queue`, `mic_invite` (sıra gelince `fromName: "Sıra sizde"`).
Mobil: `RoomDock` (açık oda tek yerde yaşar, küçültülünce Offstage), `DiscoverScreen`.

## Oda özellikleri (v2.3)
- **Gizli oda:** `hidden:true` ile 6 karakterlik davet kodu (0/O/1/I yok); listede görünmez; `POST /api/rooms/by-code`, `join {code}`. Kod yalnızca sahip/yardımcı sahibe görünür; tahmin denemeleri sınırlı.
- **Tema:** default, neon, galaxy, sunset, forest, royal, ocean, rose; özel görsel `themeImageUrl` için WIP 6+ (`customRoomTheme`).
- **Koltuk hediye sayacı:** `room_gift_totals`; `GET /api/rooms/:id/scoreboard`, `POST .../scoreboard/reset`; olay `room_scoreboard`.
- **Sohbet temizleme:** `DELETE /api/rooms/:id/messages` (sahip, yardımcı sahip, moderatör); olay `room_chat_cleared`.
- **PK:** `POST /api/pk/challenge`, `/pk/:id/respond`, `/pk/:id/cancel`, `GET /api/rooms/:id/pk`, `/api/pk/rooms`. Skor: odanın sahibine gelen, kendine gönderilmeyen hediyeler. Olaylar: `pk_invite`, `pk_state`, `pk_tick`.
- **Oyun (Ludo):** `GET /api/rooms/:id/game`, `POST /api/rooms/:id/games`, `/api/games/:id/{join,leave,start,cancel,roll,move}`. Sunucu-otoriter (`ludo.js`), 30 sn tur süresi, AFK'da otomatik oynama (3 kez sonra elenme). **Bahis yoktur.** Olay: `room_game_state`.

## Giriş efekti
Önce **seçili** (equipped) `entrance_effect`, yoksa en yeni öğe kullanılır. Gizli kullanıcı efektle duyurulmaz.

## Eklenenler (v2.2)
**Oda sohbeti:** `POST /api/rooms/:id/messages {text}`, `GET /:id/messages`, `DELETE /:id/messages/:mid`, `POST /:id/members/:uid/chat-mute {minutes}`
**Oda ayarları:** `PATCH /api/rooms/:id {name?, tags?, password?, chatEnabled?}`; katılma: `POST /:id/join {password?}`; liste: `GET /api/rooms?type=&tag=`
**Müzik:** `GET /api/music/tracks?q=`, `GET /api/rooms/:id/music`, `POST /music/queue {trackId}`, `DELETE /music/queue/:itemId`,
`POST /music/play {trackId?}|pause|next|stop|seek {positionMs}`. İstemci senkronu: `positionMs` + (şimdi − alındığı an).
**Özel mesaj:** `GET /api/messages/conversations|unread-count`, `GET|POST /api/messages/with/:userId`
**Güvenlik/sosyal:** `GET /api/blocks`, `POST|DELETE /api/blocks/:uid`, `POST /api/reports {kind, reason, targetUserId?, roomId?, messageId?, details?}`
**Liderlik:** `GET /api/leaderboards?type=senders|receivers|families&period=daily|weekly|monthly|all`
**Yönetim:** `POST /api/admin/music/tracks*`, `GET /admin/music/tracks*`, `GET /admin/reports`, `POST /admin/reports/:id/resolve`,
`GET /admin/security/events*`, `GET|POST /admin/security/blocks*`, `DELETE /admin/security/blocks/:ip*`
WebSocket yeni olaylar: `room_message`, `room_message_deleted`, `room_chat_muted`, `room_settings`, `room_music_state`, `dm`.

## Güvenlik duvarı (özet)
`firewall()` her istekte: IP yasağı → WAF (yol geçişi, null bayt, SQLi/XSS/komut imzaları, tarayıcı User-Agent) → IP başına hız sınırı.
`bodyGuard()`: derin/dev JSON ve `__proto__` anahtarları. `userLimit/ipLimit`: uç nokta başına limitler (hediye, sohbet, mesaj, şikâyet...).
`loginGuard`: IP+kullanıcı adı başına 5, kullanıcı adı başına 20 hatalı denemede geçici kilit.
İhlaller puanlanır (WAF=5, limit=1); 10 dk'da eşik (varsayılan 30) aşılırsa IP otomatik yasaklanır (15 dk → 1 sa → 24 sa). İzin listesindeki IP'ler yasaklanmaz.
WebSocket: IP başına 30, kullanıcı başına 5 bağlantı; 10 sn'de 40 mesaj üstü bağlantı kapatılır.
