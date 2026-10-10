import { query } from '../database.js';
import { hub } from '../realtime.js';

/**
 * Çevrimiçi durumu görünümü. Gizli kullanıcı modu veya "çevrimiçi durumumu gizle" açıksa null döner
 * (istemci hiçbir şey göstermez). row: id, show_presence, is_hidden, last_seen_at.
 */
export function presenceView(row) {
  if (!row || row.show_presence === false || row.is_hidden || row.ghost) return null;
  const online = hub.isOnline(row.id);
  return { online, lastSeenAt: online ? null : (row.last_seen_at ?? null) };
}

/** WebSocket "presence_watch" isteği için anlık durum. Engelleme ilişkisi olan kişiler listeye girmez. */
export async function presenceSnapshot(viewerId, ids) {
  const r = await query(
    `SELECT u.id, u.show_presence, u.is_hidden, u.last_seen_at, is_ghost(u.id) AS ghost FROM users u
     WHERE u.id = ANY($2::uuid[]) AND u.account_status = 'active'
       AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE (b.blocker_id = u.id AND b.blocked_id = $1) OR (b.blocker_id = $1 AND b.blocked_id = u.id))`,
    [viewerId, ids],
  );
  const out = [];
  for (const row of r.rows) {
    const p = presenceView(row);
    if (p) out.push({ userId: row.id, ...p });
  }
  return out;
}

/** SWIP hayalet modu şu an etkin mi (tercih açık + aktif kademe izin veriyor). */
export async function isGhost(userId) {
  const r = await query(`SELECT is_ghost($1) AS g`, [userId]);
  return r.rows[0]?.g === true;
}

/** Bağlantı açılınca/kapanınca son görülme zamanı yazılır. */
export async function recordPresence(userId) {
  await query(`UPDATE users SET last_seen_at = NOW() WHERE id = $1`, [userId]);
}

// ---- "Yazıyor..." ----
// Yalnızca birbirine mesaj atabilen kişiler arasında iletilir (arkadaş, engel yok, DM kapalı değil).
// Sonuç 60 sn önbelleklenir: her tuş vuruşunda veritabanına gidilmesin.
const typingCache = new Map(); // "a|b" -> { ok, at }
export async function canSignalTyping(from, to) {
  const k = `${from}|${to}`;
  const hit = typingCache.get(k);
  if (hit && Date.now() - hit.at < 60e3) return hit.ok;
  const r = await query(
    `SELECT 1 FROM users u
     WHERE u.id = $2 AND u.account_status = 'active' AND COALESCE(u.who_can_dm, 'everyone') <> 'nobody'
       AND EXISTS (SELECT 1 FROM friend_requests f WHERE f.status = 'accepted'
                     AND ((f.requester_id = $1 AND f.target_id = $2) OR (f.requester_id = $2 AND f.target_id = $1)))
       AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE (b.blocker_id = $1 AND b.blocked_id = $2) OR (b.blocker_id = $2 AND b.blocked_id = $1))`,
    [from, to],
  );
  if (typingCache.size > 20000) typingCache.clear();
  typingCache.set(k, { ok: r.rowCount > 0, at: Date.now() });
  return r.rowCount > 0;
}

/** Engelleme / arkadaşlıktan çıkarma sonrası önbellek hemen düşer. */
export function forgetTyping(a, b) {
  typingCache.delete(`${a}|${b}`);
  typingCache.delete(`${b}|${a}`);
}
