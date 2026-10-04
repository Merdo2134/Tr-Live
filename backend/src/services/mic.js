import { query } from '../database.js';

// Mikrofon oturumları yayın saatini hesaplar. Bir kullanıcı aynı anda tek odada sayılır (çift sayımı önler).
export async function openMicSession(userId, roomId, run = query) {
  await run(`UPDATE mic_sessions SET ended_at = NOW() WHERE user_id = $1 AND ended_at IS NULL AND room_id <> $2`, [userId, roomId]);
  await run(`INSERT INTO mic_sessions(user_id, room_id) VALUES($1,$2) ON CONFLICT (user_id, room_id) WHERE ended_at IS NULL DO NOTHING`, [userId, roomId]);
}

export async function closeMicSessions(userId, roomId, run = query) {
  await run(`UPDATE mic_sessions SET ended_at = NOW() WHERE user_id = $1 AND room_id = $2 AND ended_at IS NULL`, [userId, roomId]);
}

export async function closeRoomMicSessions(roomId, run = query) {
  await run(`UPDATE mic_sessions SET ended_at = NOW() WHERE room_id = $1 AND ended_at IS NULL`, [roomId]);
}

// Sunucu çöküp yeniden başladıktan sonra yetim kalan açık oturumları kapatır.
export async function closeStaleMicSessions(run = query) {
  const r = await run(
    `UPDATE mic_sessions s SET ended_at = NOW()
     WHERE s.ended_at IS NULL AND NOT EXISTS (
       SELECT 1 FROM room_members m WHERE m.room_id = s.room_id AND m.user_id = s.user_id AND m.microphone = TRUE)`,
  );
  return r.rowCount;
}
