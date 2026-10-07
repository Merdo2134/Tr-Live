import fs from 'node:fs/promises';
import path from 'node:path';
import { query, tx } from '../database.js';
import { config } from '../config.js';
import { hub } from '../realtime.js';
import { positionAt, hasEnded } from '../music_logic.js';

const trackOf = (r) => ({ id: r.track_id ?? r.id, title: r.title, artist: r.artist, url: r.url, coverUrl: r.cover_url, durationMs: r.duration_ms });
const ELAPSED = `(EXTRACT(EPOCH FROM (NOW() - rm.updated_at)) * 1000)::bigint`;

// İstemciler "positionMs" ve "serverTime" ile senkronize olur: şimdiki konum = positionMs + (yerelSaat - alındığıAn).
export async function musicState(roomId, run = query) {
  const st = (await run(
    `SELECT rm.status, rm.position_ms, ${ELAPSED} AS elapsed_ms, rm.track_id, t.title, t.artist, t.url, t.cover_url, t.duration_ms
     FROM room_music rm LEFT JOIN music_tracks t ON t.id = rm.track_id WHERE rm.room_id = $1`,
    [roomId],
  )).rows[0];
  const queue = (await run(
    `SELECT q.id, q.added_by, t.id AS track_id, t.title, t.artist, t.url, t.cover_url, t.duration_ms
     FROM room_music_queue q JOIN music_tracks t ON t.id = q.track_id WHERE q.room_id = $1 ORDER BY q.created_at LIMIT 50`,
    [roomId],
  )).rows;
  const track = st?.track_id ? trackOf(st) : null;
  return {
    status: st?.status ?? 'stopped',
    track,
    positionMs: st && track ? positionAt(st.status, st.position_ms, st.elapsed_ms, track.durationMs) : 0,
    serverTime: Date.now(),
    queue: queue.map((q) => ({ id: q.id, addedBy: q.added_by, track: trackOf(q) })),
  };
}

export async function broadcastMusic(roomId) {
  hub.broadcastRoom(roomId, { type: 'room_music_state', roomId, state: await musicState(roomId) });
}

/** Sıradaki şarkıya geçer. onlyIfEnded=true ise yalnızca şarkı gerçekten bittiyse (ticker için). */
export async function advanceQueue(roomId, { onlyIfEnded = false } = {}) {
  const changed = await tx(async (c) => {
    const st = (await c.query(
      `SELECT rm.status, rm.position_ms, ${ELAPSED} AS elapsed_ms, t.duration_ms
       FROM room_music rm LEFT JOIN music_tracks t ON t.id = rm.track_id WHERE rm.room_id = $1 FOR UPDATE OF rm`,
      [roomId],
    )).rows[0];
    if (!st) return false;
    if (onlyIfEnded && !hasEnded(st.status, st.position_ms, st.elapsed_ms, st.duration_ms)) return false;
    const next = (await c.query(
      `SELECT id, track_id FROM room_music_queue WHERE room_id = $1 ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED`, [roomId],
    )).rows[0];
    if (next) {
      await c.query(`DELETE FROM room_music_queue WHERE id = $1`, [next.id]);
      await c.query(`UPDATE room_music SET track_id = $2, status = 'playing', position_ms = 0, updated_at = NOW() WHERE room_id = $1`, [roomId, next.track_id]);
    } else {
      await c.query(`UPDATE room_music SET track_id = NULL, status = 'stopped', position_ms = 0, updated_at = NOW() WHERE room_id = $1`, [roomId]);
    }
    return true;
  });
  if (changed) await broadcastMusic(roomId);
  return changed;
}

export async function clearRoomMusic(roomId, run = query) {
  await run(`DELETE FROM room_music_queue WHERE room_id = $1`, [roomId]);
  await run(`DELETE FROM room_music WHERE room_id = $1`, [roomId]);
}

/** Süresi dolmuş, hiçbir odada çalmayan/sırada olmayan geçici parçaları ve dosyalarını siler. */
export async function purgeTempTracks() {
  const r = await query(
    `DELETE FROM music_tracks t WHERE t.is_temp AND t.expires_at < NOW()
       AND NOT EXISTS (SELECT 1 FROM room_music m WHERE m.track_id = t.id)
       AND NOT EXISTS (SELECT 1 FROM room_music_queue q WHERE q.track_id = t.id)
     RETURNING t.url`,
  );
  for (const row of r.rows) {
    try { await fs.unlink(path.join(config.uploadDir, 'music', path.basename(row.url))); } catch (_) { /* dosya zaten yok */ }
  }
  return r.rowCount;
}

// Biten şarkıları 2 sn'de bir kontrol eder; yeniden başlatmaya dayanıklıdır (durum veritabanındadır).
export function startMusicTicker() {
  const timer = setInterval(async () => {
    try {
      const r = await query(
        `SELECT rm.room_id FROM room_music rm JOIN music_tracks t ON t.id = rm.track_id
         WHERE rm.status = 'playing' AND rm.position_ms + ${ELAPSED} >= t.duration_ms`,
      );
      for (const row of r.rows) await advanceQueue(row.room_id, { onlyIfEnded: true });
    } catch (error) {
      console.error('Müzik zamanlayıcı hatası:', error.message);
    }
  }, 2000);
  timer.unref();
  const purge = setInterval(() => purgeTempTracks().catch((e) => console.error('Geçici müzik temizliği hatası:', e.message)), 10 * 60e3);
  purge.unref();
  return timer;
}
