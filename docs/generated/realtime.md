# Gerçek zamanlı olaylar (WebSocket `/ws`)

> Otomatik üretildi: `node backend/scripts/gen_docs.mjs`. Elle düzenlemeyin.

Bağlantı: `wss://SUNUCU/ws?token=JWT`. Mesajlar JSON, her mesajda `type` alanı var.

## İstemciden sunucuya

- `ping`
- `room_unsubscribe`
- `presence_watch`
- `typing`
- `room_subscribe`

## Sunucudan istemciye (36 tür)

| Tür | Kime | Gönderen dosya |
|---|---|---|
| `chat_restricted` | kişiye | routes/admin.js, services/moderation.js |
| `connected` | bağlantıya | realtime.js |
| `dm` | kişiye | routes/messages.js |
| `dm_read` | kişiye | routes/messages.js |
| `error` | bağlantıya | realtime.js |
| `friend_update` | kişiye | routes/friends.js, routes/store.js |
| `lucky_bag_claimed` | odaya | routes/luckybag.js |
| `lucky_bag_ended` | odaya | routes/luckybag.js |
| `lucky_bag_global` | herkese | routes/luckybag.js |
| `lucky_bag_new` | odaya | routes/luckybag.js |
| `lucky_gift_win` | herkese | routes/gifts.js |
| `mic_invite` | kişiye | routes/rooms.js, services/micqueue.js |
| `pk_invite` | kişiye | routes/pk.js |
| `pk_state` | odaya | routes/gifts.js |
| `pong` | bağlantıya | realtime.js |
| `presence` | izleyenlere | realtime.js |
| `presence_state` | bağlantıya | realtime.js |
| `room_chat_cleared` | odaya | routes/chat.js |
| `room_chat_muted` | kişiye | routes/chat.js |
| `room_closed` | odaya | services/rooms.js |
| `room_game_state` | odaya | services/games.js |
| `room_gift` | odaya | routes/gifts.js |
| `room_member_joined` | odaya | routes/rooms.js, services/ghost.js |
| `room_member_left` | odaya | routes/rooms.js, services/ghost.js, services/rooms.js |
| `room_message` | odaya | routes/chat.js |
| `room_message_deleted` | odaya | routes/chat.js |
| `room_mic_queue` | odaya | services/micqueue.js |
| `room_music_state` | odaya | services/music.js |
| `room_role_changed` | odaya | routes/rooms.js |
| `room_scoreboard` | odaya | routes/gifts.js, routes/rooms.js |
| `room_seat_changed` | odaya | routes/rooms.js |
| `room_seats_locked` | odaya | routes/rooms.js |
| `room_settings` | odaya | routes/rooms.js |
| `room_subscribed` | bağlantıya | realtime.js |
| `support_message` | kişiye | routes/admin.js |
| `typing` | kişiye | realtime.js |
