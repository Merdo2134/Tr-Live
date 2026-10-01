import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { fail, uuid } from '../http.js';
import { userLimit } from '../firewall.js';
import { clampPosition, positionAt, queueDecision, MUSIC_MANAGERS } from '../music_logic.js';
import { musicState, broadcastMusic, advanceQueue } from '../services/music.js';

export const router = Router();
router.use(requireAuth);

const trackJson = (t) => ({ id: t.id, title: t.title, artist: t.artist, url: t.url, coverUrl: t.cover_url, durationMs: t.duration_ms });
const ELAPSED = `(EXTRACT(EPOCH FROM (NOW() - updated_at)) * 1000)::bigint`;

async function context(roomId, userId) {
  const room = (await query(`SELECT id FROM rooms WHERE id = $1 AND is_active = TRUE`, [roomId])).rows[0];
  if (!room) throw fail('Oda bulunamadı.', 404);
  const member = (await query(`SELECT role, microphone FROM room_members WHERE room_id = $1 AND user_id = $2`, [roomId, userId])).rows[0];
  if (!member) throw fail('Önce odaya girin.', 403);
  return member;
}

async function managerContext(roomId, userId) {
  const m = await context(roomId, userId);
  if (!MUSIC_MANAGERS.includes(m.role)) throw fail('Müziği yalnızca oda yetkilileri yönetebilir.', 403);
  return m;
}

// Müzik kütüphanesi (yalnızca yönetici tarafından eklenen, lisansı kayıtlı parçalar).
router.get('/music/tracks', async (req, res) => {
  const q = String(req.query.q ?? '').trim().toLowerCase();
  const r = await query(
    `SELECT id, title, artist, url, cover_url, duration_ms FROM music_tracks
     WHERE is_active = TRUE AND ($1 = '' OR lower(title) LIKE $2 ESCAPE '\\' OR lower(COALESCE(artist, '')) LIKE $2 ESCAPE '\\')
     ORDER BY title LIMIT 50`,
    [q, `%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`],
  );
  res.json({ tracks: r.rows.map(trackJson) });
});

router.get('/rooms/:roomId/music', async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await context(roomId, req.user.id);
  res.json({ state: await musicState(roomId) });
});

router.post('/rooms/:roomId/music/queue', userLimit('music_queue', 20, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const trackId = uuid(req.body?.trackId, 'Şarkı');
  const member = await context(roomId, req.user.id);
  if (!MUSIC_MANAGERS.includes(member.role) && member.microphone !== true) throw fail('Şarkı eklemek için mikrofonda olmalısınız.', 403);

  await tx(async (c) => {
    await c.query(`SELECT id FROM rooms WHERE id = $1 FOR UPDATE`, [roomId]); // sıra sınırı yarışını önler
    const track = (await c.query(`SELECT id FROM music_tracks WHERE id = $1 AND is_active = TRUE`, [trackId])).rows[0];
    if (!track) throw fail('Şarkı bulunamadı.', 404);
    const counts = (await c.query(
      `SELECT COUNT(*)::int AS total, COUNT(*) FILTER (WHERE added_by = $2)::int AS mine FROM room_music_queue WHERE room_id = $1`, [roomId, req.user.id],
    )).rows[0];
    const d = queueDecision({ queueLength: counts.total, userCount: counts.mine });
    if (!d.ok) throw fail(d.message, 409);
    await c.query(`INSERT INTO room_music_queue(room_id, track_id, added_by) VALUES($1,$2,$3)`, [roomId, trackId, req.user.id]);
    // Hiçbir şey çalmıyorsa ilk eklenen şarkı hemen başlar.
    const st = (await c.query(`SELECT status FROM room_music WHERE room_id = $1`, [roomId])).rows[0];
    if (!st) await c.query(`INSERT INTO room_music(room_id, status) VALUES($1,'stopped')`, [roomId]);
  });
  const st = await musicState(roomId);
  if (st.status === 'stopped') await advanceQueue(roomId);
  else await broadcastMusic(roomId);
  res.status(201).json({ state: await musicState(roomId) });
});

router.delete('/rooms/:roomId/music/queue/:itemId', async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const itemId = uuid(req.params.itemId, 'Sıra öğesi');
  const member = await context(roomId, req.user.id);
  const item = (await query(`SELECT added_by FROM room_music_queue WHERE id = $1 AND room_id = $2`, [itemId, roomId])).rows[0];
  if (!item) throw fail('Sıra öğesi bulunamadı.', 404);
  if (item.added_by !== req.user.id && !MUSIC_MANAGERS.includes(member.role)) throw fail('Bu şarkıyı kaldırma yetkiniz yok.', 403);
  await query(`DELETE FROM room_music_queue WHERE id = $1`, [itemId]);
  await broadcastMusic(roomId);
  res.json({ ok: true });
});

router.post('/rooms/:roomId/music/play', userLimit('music_ctl', 40, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await managerContext(roomId, req.user.id);
  const trackId = req.body?.trackId ? uuid(req.body.trackId, 'Şarkı') : null;

  if (trackId) {
    const t = (await query(`SELECT id FROM music_tracks WHERE id = $1 AND is_active = TRUE`, [trackId])).rows[0];
    if (!t) throw fail('Şarkı bulunamadı.', 404);
    await query(
      `INSERT INTO room_music(room_id, track_id, status, position_ms, updated_at, controlled_by) VALUES($1,$2,'playing',0,NOW(),$3)
       ON CONFLICT (room_id) DO UPDATE SET track_id = EXCLUDED.track_id, status = 'playing', position_ms = 0, updated_at = NOW(), controlled_by = EXCLUDED.controlled_by`,
      [roomId, trackId, req.user.id],
    );
  } else {
    const r = await query(
      `UPDATE room_music SET status = 'playing', updated_at = NOW(), controlled_by = $2 WHERE room_id = $1 AND status = 'paused' RETURNING room_id`,
      [roomId, req.user.id],
    );
    if (!r.rowCount) {
      if (!(await advanceQueue(roomId))) throw fail('Çalınacak şarkı yok. Önce bir şarkı seçin.', 409);
      return res.json({ state: await musicState(roomId) });
    }
  }
  await broadcastMusic(roomId);
  res.json({ state: await musicState(roomId) });
});

// Duraklat ve ara: konumu veritabanı saatiyle bir transaction içinde hesaplar.
async function withLockedState(roomId, fn) {
  return tx(async (c) => {
    const st = (await c.query(
      `SELECT rm.status, rm.position_ms, (EXTRACT(EPOCH FROM (NOW() - rm.updated_at)) * 1000)::bigint AS elapsed_ms, t.duration_ms
       FROM room_music rm JOIN music_tracks t ON t.id = rm.track_id WHERE rm.room_id = $1 FOR UPDATE OF rm`,
      [roomId],
    )).rows[0];
    if (!st) throw fail('Şu an çalan bir şarkı yok.', 409);
    await fn(c, st);
  });
}

router.post('/rooms/:roomId/music/pause', userLimit('music_ctl', 40, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await managerContext(roomId, req.user.id);
  await withLockedState(roomId, async (c, st) => {
    if (st.status !== 'playing') throw fail('Müzik zaten duraklatılmış.', 409);
    const pos = clampPosition(positionAt('playing', st.position_ms, st.elapsed_ms), st.duration_ms);
    await c.query(`UPDATE room_music SET status = 'paused', position_ms = $2, updated_at = NOW(), controlled_by = $3 WHERE room_id = $1`, [roomId, pos, req.user.id]);
  });
  await broadcastMusic(roomId);
  res.json({ state: await musicState(roomId) });
});

router.post('/rooms/:roomId/music/seek', userLimit('music_ctl', 40, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await managerContext(roomId, req.user.id);
  const requested = Number(req.body?.positionMs);
  if (!Number.isFinite(requested) || requested < 0) throw fail('Konum geçersiz.');
  await withLockedState(roomId, async (c, st) => {
    await c.query(`UPDATE room_music SET position_ms = $2, updated_at = NOW(), controlled_by = $3 WHERE room_id = $1`, [roomId, clampPosition(requested, st.duration_ms), req.user.id]);
  });
  await broadcastMusic(roomId);
  res.json({ state: await musicState(roomId) });
});

router.post('/rooms/:roomId/music/next', userLimit('music_ctl', 40, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await managerContext(roomId, req.user.id);
  await advanceQueue(roomId);
  res.json({ state: await musicState(roomId) });
});

router.post('/rooms/:roomId/music/stop', userLimit('music_ctl', 40, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await managerContext(roomId, req.user.id);
  await query(`UPDATE room_music SET track_id = NULL, status = 'stopped', position_ms = 0, updated_at = NOW(), controlled_by = $2 WHERE room_id = $1`, [roomId, req.user.id]);
  await broadcastMusic(roomId);
  res.json({ state: await musicState(roomId) });
});
