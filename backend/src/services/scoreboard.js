import { query } from '../database.js';

export async function scoreboardOf(roomId, run = query) {
  const r = await run(
    `SELECT t.user_id, t.total_coins, t.total_count, rm.seat_index
     FROM room_gift_totals t LEFT JOIN room_members rm ON rm.room_id = t.room_id AND rm.user_id = t.user_id
     WHERE t.room_id = $1 ORDER BY t.total_coins DESC LIMIT 50`, [roomId],
  );
  return r.rows.map((x) => ({ userId: x.user_id, coins: String(x.total_coins), count: String(x.total_count), seatIndex: x.seat_index }));
}
