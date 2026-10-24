// Kişiye özel telefon bildirimleri (arkadaşlık isteği, yeni takipçi, arkadaşın oda açması).
// Kayıt veritabanına yazılır ve kullanıcıya soketten anında gönderilir; uygulama kapalıyken gelenler,
// uygulama açılınca /api/me/notifications/pending ile alınır. Hata asıl işlemi bozmaz.
import { query } from '../database.js';
import { hub } from '../realtime.js';

/** Tercih anahtarları: friend (arkadaşlık), follow (takipçi), room (arkadaş oda açtı). Yoksa açık. */
export const NOTIFY_KINDS = {
  friend_request: 'friend', friend_accept: 'friend', follow: 'follow', room_open: 'room',
  post_like: 'moment', post_comment: 'moment', family_notice: 'family', family_join: 'family',
};

const clip = (s, n) => String(s ?? '').slice(0, n);

function push(row) {
  hub.sendToUser(row.user_id, {
    type: 'notify', id: String(row.id), kind: row.kind, title: row.title, body: row.body, data: row.data ?? {},
  });
}

/** Tek kişiye bildirim (kişi bu türü kapattıysa gönderilmez). */
export async function notifyUser(userId, kind, title, body, data = {}) {
  try {
    const pref = NOTIFY_KINDS[kind];
    const r = await query(
      `INSERT INTO user_notifications(user_id, kind, title, body, data)
       SELECT $1, $2, $3, $4, $5 FROM users u
       WHERE u.id = $1 AND u.account_status = 'active' AND COALESCE((u.notify_prefs->>$6)::boolean, TRUE)
       RETURNING id, user_id, kind, title, body, data`,
      [userId, kind, clip(title, 80), clip(body, 300), JSON.stringify(data), pref ?? kind],
    );
    if (r.rows[0]) push(r.rows[0]);
  } catch (error) {
    console.error('[bildirim]', kind, error.message);
  }
}

/**
 * Oda açıldı: sahibin arkadaşlarına "X oda açtı" bildirimi. Aynı kişiye aynı sahipten 30 dakikada bir kez
 * (oda kapatılıp açılınca bildirim yağmasın). Gizli kullanıcı / gizli oda için çağrılmaz.
 */
export async function notifyFriendsRoomOpen(owner, room) {
  try {
    const name = clip(owner.display_name || owner.username, 40);
    const r = await query(
      `INSERT INTO user_notifications(user_id, kind, title, body, data)
       SELECT f.uid, 'room_open', $2, $3, $4::jsonb FROM (
         SELECT CASE WHEN fr.requester_id = $1 THEN fr.target_id ELSE fr.requester_id END AS uid
         FROM friend_requests fr WHERE fr.status = 'accepted' AND (fr.requester_id = $1 OR fr.target_id = $1)
       ) f JOIN users u ON u.id = f.uid
       WHERE u.account_status = 'active' AND COALESCE((u.notify_prefs->>'room')::boolean, TRUE)
         AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE (b.blocker_id = f.uid AND b.blocked_id = $1) OR (b.blocker_id = $1 AND b.blocked_id = f.uid))
         AND NOT EXISTS (SELECT 1 FROM user_notifications n WHERE n.user_id = f.uid AND n.kind = 'room_open'
                         AND n.data->>'ownerId' = $1::text AND n.created_at > NOW() - INTERVAL '30 minutes')
       RETURNING id, user_id, kind, title, body, data`,
      [owner.id, '🎙️ Arkadaşın oda açtı', clip(`${name} şu an "${room.name}" odasında. Hemen katıl!`, 300),
        JSON.stringify({ ownerId: owner.id, roomId: room.id, roomName: room.name })],
    );
    for (const row of r.rows) push(row);
  } catch (error) {
    console.error('[bildirim] oda açıldı:', error.message);
  }
}

/** Eski bildirimler (30 günden eski) temizlenir; sunucu açılışında ve günde bir. */
export function startNotificationJanitor() {
  const run = () => query(`DELETE FROM user_notifications WHERE created_at < NOW() - INTERVAL '30 days'`).catch(() => {});
  setTimeout(run, 60e3).unref();
  const t = setInterval(run, 24 * 3600e3);
  t.unref();
  return t;
}
