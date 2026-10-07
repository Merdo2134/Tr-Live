import { Router } from 'express';
import express from 'express';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { config } from '../config.js';
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
     WHERE is_active = TRUE AND is_temp = FALSE AND ($1 = '' OR lower(title) LIKE $2 ESCAPE '\\' OR lower(COALESCE(artist, '')) LIKE $2 ESCAPE '\\')
     ORDER BY title LIMIT 50`,
    [q, `%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`],
  );
  res.json({ tracks: r.rows.map(trackJson) });
});


// ---- Telefondan odaya müzik yükleme (Zula/Yoho tarzı "yerel müzik") ----
const AUDIO_TYPES = { 'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/aac': 'aac', 'audio/ogg': 'ogg', 'audio/wav': 'wav', 'audio/flac': 'flac' };
const MAX_AUDIO_BYTES = 25 * 1024 * 1024;
const TEMP_TRACK_TTL_HOURS = 12;
const MAX_TEMP_PER_USER = 5;

/** Dosyanın gerçekten ses olduğunu ilk baytlarından doğrular; istemcinin bildirdiği türe güvenmez. */
export function detectAudio(buf) {
  if (buf.length < 12) return null;
  if (buf.toString('ascii', 0, 3) === 'ID3') return 'audio/mpeg';
  if (buf[0] === 0xff && (buf[1] & 0xe0) === 0xe0) {
    const layer = (buf[1] >> 1) & 3; // 0 = ADTS (AAC), 1-3 = MPEG katmanları
    return layer === 0 ? 'audio/aac' : 'audio/mpeg';
  }
  if (buf.toString('ascii', 4, 8) === 'ftyp') return 'audio/mp4';
  if (buf.toString('ascii', 0, 4) === 'OggS') return 'audio/ogg';
  if (buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WAVE') return 'audio/wav';
  if (buf.toString('ascii', 0, 4) === 'fLaC') return 'audio/flac';
  return null;
}

router.post('/rooms/:roomId/music/upload',
  userLimit('music_upload', 10, 10 * 60e3),
  express.raw({ type: () => true, limit: MAX_AUDIO_BYTES }),
  async (req, res) => {
    const roomId = uuid(req.params.roomId, 'Oda');
    const member = await context(roomId, req.user.id);
    if (!MUSIC_MANAGERS.includes(member.role) && member.microphone !== true) throw fail('Müzik çalmak için mikrofonda olmalısınız.', 403);
    const buf = req.body;
    if (!Buffer.isBuffer(buf) || !buf.length) throw fail('Müzik dosyası gönderilmedi.');
    const kind = detectAudio(buf);
    if (!kind) throw fail('Desteklenmeyen ses dosyası (mp3, m4a, aac, ogg, wav, flac).');
    const durationMs = Math.floor(Number(req.query.durationMs));
    if (!Number.isFinite(durationMs) || durationMs < 1000 || durationMs > 7200000) throw fail('Şarkı süresi geçersiz.');
    const title = String(req.query.title ?? '').replace(/[\u0000-\u001f]/g, '').trim().slice(0, 120) || 'Adsız parça';
    const artist = String(req.query.artist ?? '').replace(/[\u0000-\u001f]/g, '').trim().slice(0, 120) || null;

    const mine = (await query(`SELECT COUNT(*)::int AS n FROM music_tracks WHERE is_temp AND created_by = $1 AND expires_at > NOW()`, [req.user.id])).rows[0].n;
    if (mine >= MAX_TEMP_PER_USER) throw fail(`Aynı anda en fazla ${MAX_TEMP_PER_USER} yüklenmiş parçanız olabilir. Biri bitince tekrar deneyin.`, 409);

    const dir = path.join(config.uploadDir, 'music');
    await fs.mkdir(dir, { recursive: true });
    const name = `${crypto.randomUUID()}.${AUDIO_TYPES[kind]}`;
    await fs.writeFile(path.join(dir, name), buf);
    const t = (await query(
      `INSERT INTO music_tracks(title, artist, url, duration_ms, license_note, created_by, is_temp, owner_room_id, expires_at, size_bytes)
       VALUES($1,$2,$3,$4,'Kullanıcı cihazından (geçici)',$5,TRUE,$6, NOW() + make_interval(hours => $7::int), $8)
       RETURNING id, title, artist, url, cover_url, duration_ms`,
      [title, artist, `/uploads/music/${name}`, durationMs, req.user.id, roomId, TEMP_TRACK_TTL_HOURS, buf.length],
    )).rows[0];
    res.status(201).json({ track: trackJson(t) });
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
    const track = (await c.query(`SELECT id FROM music_tracks WHERE id = $1 AND is_active = TRUE AND (owner_room_id IS NULL OR owner_room_id = $2)`, [trackId, roomId])).rows[0];
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
    const t = (await query(`SELECT id FROM music_tracks WHERE id = $1 AND is_active = TRUE AND (owner_room_id IS NULL OR owner_room_id = $2)`, [trackId, roomId])).rows[0];
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
