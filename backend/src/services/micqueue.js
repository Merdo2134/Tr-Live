import { query } from '../database.js';
import { hub } from '../realtime.js';
import { pickNext, hasFreeSeat } from '../mic_queue_logic.js';

export async function queueOf(roomId) {
  const r = await query(`SELECT user_id FROM room_mic_queue WHERE room_id = $1 ORDER BY created_at, user_id`, [roomId]);
  return r.rows.map((x) => x.user_id);
}

export async function broadcastQueue(roomId) {
  hub.broadcastRoom(roomId, { type: 'room_mic_queue', roomId, queue: await queueOf(roomId) });
}

export async function removeFromQueue(roomId, userId) {
  const r = await query(`DELETE FROM room_mic_queue WHERE room_id = $1 AND user_id = $2`, [roomId, userId]);
  if (r.rowCount) await broadcastQueue(roomId);
  return r.rowCount > 0;
}

// Koltuk boşalınca sıradaki uygun kişiyi mikrofona davet eder (otomatik oturtmaz; kişi kabul eder).
export async function notifyNext(roomId) {
  const room = (await query(`SELECT seat_count, locked_seats FROM rooms WHERE id = $1 AND is_active = TRUE`, [roomId])).rows[0];
  if (!room) return null;
  const taken = (await query(`SELECT seat_index FROM room_members WHERE room_id = $1 AND seat_index IS NOT NULL`, [roomId])).rows.map((x) => x.seat_index);
  if (!hasFreeSeat(room.seat_count, room.locked_seats, taken)) return null;
  const queue = (await query(`SELECT user_id FROM room_mic_queue WHERE room_id = $1 ORDER BY created_at, user_id`, [roomId])).rows;
  if (!queue.length) return null;
  const elig = new Set((await query(
    `SELECT user_id FROM room_members WHERE room_id = $1 AND seat_index IS NULL`, [roomId],
  )).rows.map((x) => x.user_id));
  const { next, drop } = pickNext(queue, elig);
  const rm = next ? [...drop, next] : drop;
  if (rm.length) await query(`DELETE FROM room_mic_queue WHERE room_id = $1 AND user_id = ANY($2::uuid[])`, [roomId, rm]);
  if (next) hub.sendToUser(next, { type: 'mic_invite', roomId, seatIndex: null, fromUserId: null, fromName: 'Sıra sizde' });
  if (rm.length) await broadcastQueue(roomId);
  return next;
}
