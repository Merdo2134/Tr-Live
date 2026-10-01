# TR Live — teknik notlar ve API özeti

Tüm yanıtlar JSON ve **camelCase**'tir. Hatalar `{ "message": "..." }` biçimindedir. Para miktarları (Coin/Diamond) metin olarak döner.
Kimlik doğrulama: `Authorization: Bearer <token>`. WebSocket: `wss://host/ws?token=<token>`.

## Tek kaynak ilkesi
Coin, Diamond, hediye ve finans hareketleri `users`, `gift_transactions`, `wallet_transactions`, `financial_audit_logs` tablolarında tutulur.
Kullanıcı bakiyesi **asla** başka kullanıcılara gösterilmez (`views.js`).

## Uç noktalar
**Auth:** `POST /api/auth/register|login`
**Profil (`/api/me`):** `GET /`, `PATCH /`, `PUT /avatar|cover` (ham png/jpeg/webp, ≤3 MB), `POST /password`, `DELETE /` (şifre ile), `GET /wallet`, `GET /visitors` (WIP 2+)
**Kullanıcılar:** `GET /api/users/search?q=`, `GET /:id`, `POST|DELETE /:id/follow`, `GET /:id/followers|following`
**Envanter:** `GET /api/inventory`, `POST /equip|unequip {itemId}`, `GET /catalog/frames|entrance-effects`
**Odalar:** `GET /api/rooms?type=audio|video`, `POST /`, `GET /:id`, `POST /:id/join|leave|close`, `GET /:id/members`,
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

## Ajans komisyonu
`agency_commissions(diamond_amount)` = hediye Coin değeri × `commission_bps` / 10000 (aşağı yuvarlanır). Dönemler Türkiye saatine (UTC+3) göredir.
`POST /api/admin/agencies/:id/settle {period}` o dönemin `accrued` kayıtlarını `paid` yapar ve denetim kaydı yazar.

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
