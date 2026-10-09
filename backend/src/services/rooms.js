import { query, tx } from '../database.js';
import { hub } from '../realtime.js';
import { removeParticipant, deleteRoom } from '../livekit.js';
import { clearRoomMusic } from './music.js';
import { closeMicSessions, closeRoomMicSessions } from './mic.js';
import { endPkForRoom } from './pk.js';
import { cancelRoomGame, forfeitUserInRoom } from './games.js';
import { nonOverlapping } from '../ticker.js';

export const SUPPORTED_SEATS = new Set([2, 4, 5, 6, 8, 9, 12, 15, 20, 30]);

// Odayı kapatır: üyeleri temizler, yayın oturumlarını bitirir, herkese bildirir.
export async function closeRoom(roomId) {
  await endPkForRoom(roomId).catch((e) => console.error('PK kapatma hatası:', e.message));
  const closed = await tx(async (c) => {
    const r = await c.query(`UPDATE rooms SET is_active = FALSE, closed_at = NOW() WHERE id = $1 AND is_active = TRUE RETURNING id`, [roomId]);
    if (!r.rowCount) return false;
    await c.query(`UPDATE broadcast_sessions SET ended_at = NOW() WHERE room_id = $1 AND ended_at IS NULL`, [roomId]);
    await c.query(`DELETE FROM room_members WHERE room_id = $1`, [roomId]);
    await clearRoomMusic(roomId, (t, p) => c.query(t, p));
    await closeRoomMicSessions(roomId, (t, p) => c.query(t, p));
    return true;
  });
  if (closed) {
    await cancelRoomGame(roomId).catch((e) => console.error('Oyun iptal hatası:', e.message));
    hub.broadcastRoom(roomId, { type: 'room_closed', roomId });
    hub.clearRoom(roomId);
    await deleteRoom(roomId);
  }
  return closed;
}

// Kullanıcıyı odadan çıkarır. Oda sahibi çıkarsa oda kapanır.
export async function leaveRoom(userId, roomId) {
  const r = await query(`DELETE FROM room_members WHERE room_id = $1 AND user_id = $2 RETURNING role`, [roomId, userId]);
  if (!r.rowCount) return false;
  await closeMicSessions(userId, roomId);
  await query(`DELETE FROM room_mic_queue WHERE room_id = $1 AND user_id = $2`, [roomId, userId]);
  await forfeitUserInRoom(userId, roomId).catch((e) => console.error('Oyundan çıkarma hatası:', e.message));
  if (r.rows[0].role === 'owner') {
    await closeRoom(roomId);
    return true;
  }
  hub.broadcastRoom(roomId, { type: 'room_member_left', roomId, userId });
  hub.detachUserFromRoom(userId, roomId);
  await removeParticipant(roomId, userId);
  return true;
}

export async function isRoomMember(userId, roomId) {
  const r = await query(`SELECT 1 FROM room_members WHERE room_id = $1 AND user_id = $2`, [roomId, userId]);
  return r.rowCount > 0;
}

// Uygulaması kapanmış / bağlantısı kopmuş kullanıcıları odadan temizler.
// Üye iki yoldan canlı sayılır: (1) WebSocket'ten odaya abone, (2) uygulamadan gelen "heartbeat" (last_seen_at).
// İkisi de bekleme süresinden uzun süredir yoksa çıkarılır: üye 5 dk, oda sahibi 15 dk
// (oda sahibi çıkınca oda kapanacağı için daha uzun). Arka plana alınan ya da interneti kesilen telefon hemen atılmaz.
const GRACE_SECONDS = { user: Number(process.env.ROOM_GRACE_SECONDS || 300), owner: Number(process.env.ROOM_OWNER_GRACE_SECONDS || 900) };

export function startRoomSweeper() {
  const timer = setInterval(nonOverlapping(async () => {
    try {
      const r = await query(
        `SELECT room_id, user_id FROM room_members
         WHERE joined_at < NOW() - INTERVAL '90 seconds'
           AND last_seen_at < NOW() - (CASE WHEN role = 'owner' THEN $2::int ELSE $1::int END) * INTERVAL '1 second'`,
        [GRACE_SECONDS.user, GRACE_SECONDS.owner],
      );
      for (const m of r.rows) {
        if (!hub.isUserInRoom(m.user_id, m.room_id)) await leaveRoom(m.user_id, m.room_id);
      }
    } catch (error) {
      console.error('Oda temizleyici hatası:', error.message);
    }
  }), 30000);
  timer.unref();
  return timer;
}
