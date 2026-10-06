import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth, optionalAuth, hashPassword, checkPassword } from '../auth.js';
import { userLimit, hitLimit, noteViolation, clientIp } from '../firewall.js';
import { cleanTags } from '../text_safety.js';
import { fail, uuid, text, oneOf } from '../http.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';
import { hub } from '../realtime.js';
import { token as livekitToken, setCanPublish, removeParticipant } from '../livekit.js';
import { canManage } from '../room_permissions.js';
import { featuresFor } from '../services/wip.js';
import { loadPublicRow, loadPublicRows, activeEntranceEffect } from '../services/users.js';
import { leaveRoom, closeRoom, SUPPORTED_SEATS } from '../services/rooms.js';
import { openMicSession, closeMicSessions } from '../services/mic.js';
import { scoreboardOf } from '../services/scoreboard.js';
import { queueOf, broadcastQueue, removeFromQueue, notifyNext } from '../services/micqueue.js';
import { cleanPublic } from '../safe_text.js';
import crypto from 'node:crypto';

export const router = Router();

const SEAT_MANAGERS = ['owner', 'cohost', 'moderator'];
export const THEMES = ['default', 'neon', 'galaxy', 'sunset', 'forest', 'royal', 'ocean', 'rose'];
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 0/O/1/I yok
const newCode = () => Array.from(crypto.randomBytes(6), (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join('');

// showCode: davet kodunu yalnızca oda sahibi / yardımcı sahip görür.
const roomJson = (r, { showCode = false } = {}) => ({
  id: r.id, name: r.name, roomType: r.room_type, seatCount: r.seat_count, ownerId: r.owner_id, createdAt: r.created_at,
  tags: r.tags ?? [], locked: Boolean(r.password_hash), chatEnabled: r.chat_enabled !== false,
  hidden: Boolean(r.is_hidden), theme: r.theme ?? 'default', themeImageUrl: r.theme_image_url ?? null, scoreboardEnabled: r.scoreboard_enabled !== false, lockedSeats: r.locked_seats ?? [],
  ...(showCode && r.join_code ? { joinCode: r.join_code } : {}),
});

async function uniqueCode(run) {
  for (let i = 0; i < 8; i += 1) {
    const code = newCode();
    if (!(await run(`SELECT 1 FROM rooms WHERE join_code = $1 AND is_active = TRUE`, [code])).rowCount) return code;
  }
  throw fail('Davet kodu üretilemedi, tekrar deneyin.', 503);
}

async function activeRoom(roomId) {
  const room = (await query(`SELECT * FROM rooms WHERE id = $1 AND is_active = TRUE`, [roomId])).rows[0];
  if (!room) throw fail('Oda bulunamadı.', 404);
  return room;
}

async function memberOf(roomId, userId) {
  return (await query(`SELECT * FROM room_members WHERE room_id = $1 AND user_id = $2`, [roomId, userId])).rows[0] || null;
}

// ---------- Liste ve ayrıntı ----------
router.get('/', optionalAuth, async (req, res) => {
  const type = req.query.type === 'video' ? 'video' : req.query.type === 'audio' ? 'audio' : null;
  const tag = req.query.tag ? String(req.query.tag).trim().toLocaleLowerCase('tr').slice(0, 20) : null;
  const q = String(req.query.q ?? '').trim().toLowerCase().slice(0, 40);
  const like = q ? `%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%` : null;
  const region = ['tr', 'other', 'friends', 'near'].includes(req.query.region) ? req.query.region : null;
  if ((region === 'friends' || region === 'near') && !req.user) throw fail('Arkadaşları görmek için giriş yapın.', 401);
  const r = await query(
    `SELECT r.id AS room_id, r.theme_image_url, r.name AS room_name, r.room_type, r.seat_count, r.owner_id, r.created_at AS room_created_at, r.tags,
       (r.password_hash IS NOT NULL) AS locked, r.theme, ${USER_PUBLIC_COLUMNS},
       (SELECT COUNT(*)::int FROM room_members rm WHERE rm.room_id = r.id) AS member_count,
       (SELECT COUNT(*)::int FROM room_members rm WHERE rm.room_id = r.id AND rm.microphone = TRUE) AS mic_count
     FROM rooms r JOIN users u ON u.id = r.owner_id ${USER_PUBLIC_JOINS}
     WHERE r.is_active = TRUE AND ($1::text IS NULL OR r.room_type = $1) AND ($2::text IS NULL OR $2 = ANY(r.tags))
       AND (r.is_hidden = FALSE OR r.owner_id = $3::uuid OR EXISTS (SELECT 1 FROM room_members hm WHERE hm.room_id = r.id AND hm.user_id = $3::uuid))
       AND ($4::text IS NULL OR lower(r.name) LIKE $4 ESCAPE '\\' OR lower(u.display_name) LIKE $4 ESCAPE '\\' OR lower(u.username) LIKE $4 ESCAPE '\\'
            OR EXISTS (SELECT 1 FROM unnest(r.tags) t WHERE lower(t) LIKE $4 ESCAPE '\\'))
       AND ($5::text IS NULL
            OR ($5 = 'tr' AND lower(COALESCE(u.country, '')) IN ('türkiye', 'turkiye', 'turkey', 'tr', 'türkiye cumhuriyeti'))
            OR ($5 = 'other' AND lower(COALESCE(u.country, '')) NOT IN ('türkiye', 'turkiye', 'turkey', 'tr', 'türkiye cumhuriyeti'))
            OR ($5 = 'friends' AND EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = $3::uuid AND f.followed_id = r.owner_id))
            OR ($5 = 'near' AND EXISTS (SELECT 1 FROM users me WHERE me.id = $3::uuid AND me.city IS NOT NULL AND lower(me.city) = lower(COALESCE(u.city, '')))))
     ORDER BY member_count DESC, r.created_at DESC LIMIT 100`,
    [type, tag, req.user?.id ?? null, like, region],
  );
  // Kullanıcı sütunlarındaki "id" (= sahip kimliği) oda kimliğiyle karışmasın diye oda alanları takma adla alınır.
  res.json({
    rooms: r.rows.map((x) => ({
      id: x.room_id, name: x.room_name, roomType: x.room_type, seatCount: x.seat_count, ownerId: x.owner_id, createdAt: x.room_created_at,
      memberCount: x.member_count, micCount: x.mic_count, tags: x.tags ?? [], locked: x.locked, theme: x.theme ?? 'default', themeImageUrl: x.theme_image_url ?? null,
      owner: publicUser(x, req.user?.id ?? null),
    })),
  });
});

// ---------- Kalıcı oda ----------
// Kullanıcı sesli ve görüntülü için birer kez oda kurar (ad, etiketler, koltuk düzeni, tema). Sonraki "oda aç"lar bu bilgilerle
// tek adımda açar; ad ve etiketler yalnızca oda içinden (oda adına dokunarak) değiştirilir.
const profileJson = (p) => ({ roomType: p.room_type, name: p.name, tags: p.tags ?? [], seatCount: p.seat_count, theme: p.theme });

async function profileOf(userId, roomType, run = query) {
  return (await run(`SELECT * FROM room_profiles WHERE owner_id = $1 AND room_type = $2`, [userId, roomType])).rows[0] || null;
}

/** Profilden oda açar. Aynı türde zaten açık odası varsa onu döndürür (yeni oda açılmaz). */
async function openFromProfile(userId, profile, hidden) {
  return tx(async (c) => {
    await c.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [userId]); // eşzamanlı açmayı sıraya sokar
    const existing = (await c.query(`SELECT * FROM rooms WHERE owner_id = $1 AND room_type = $2 AND is_active = TRUE ORDER BY created_at DESC LIMIT 1`, [userId, profile.room_type])).rows[0];
    if (existing) return { room: existing, created: false };
    const r = (await c.query(
      `INSERT INTO rooms(name, room_type, seat_count, owner_id, tags, is_hidden, join_code, theme) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
      [profile.name, profile.room_type, profile.seat_count, userId, profile.tags, hidden, hidden ? await uniqueCode((t, p) => c.query(t, p)) : null, profile.theme],
    )).rows[0];
    await c.query(`INSERT INTO room_members(room_id, user_id, role, microphone, seat_index) VALUES($1,$2,'owner',TRUE,0)`, [r.id, userId]);
    // Onaylı yayıncı ise yayın oturumu başlar (süre istatistikleri için).
    const b = (await c.query(`SELECT agency_id FROM broadcasters WHERE user_id = $1 AND status = 'approved'`, [userId])).rows[0];
    if (b) await c.query(`INSERT INTO broadcast_sessions(user_id, room_id, agency_id) VALUES($1,$2,$3)`, [userId, r.id, b.agency_id]);
    await openMicSession(userId, r.id, (t, p) => c.query(t, p));
    return { room: r, created: true };
  });
}

// Kayıtlı odalarım ve şu an açık olanlar.
router.get('/mine', requireAuth, async (req, res) => {
  const profiles = (await query(`SELECT * FROM room_profiles WHERE owner_id = $1`, [req.user.id])).rows;
  const active = (await query(`SELECT id, room_type FROM rooms WHERE owner_id = $1 AND is_active = TRUE`, [req.user.id])).rows;
  const out = {};
  for (const type of ['audio', 'video']) {
    const p = profiles.find((x) => x.room_type === type);
    out[type] = p ? { ...profileJson(p), activeRoomId: active.find((x) => x.room_type === type)?.id ?? null } : null;
  }
  res.json({ rooms: out });
});

// Oda aç: kayıtlı oda varsa doğrudan açar; yoksa gövdedeki bilgilerle bir kez kurar.
router.post('/', requireAuth, userLimit('room_create', 20, 3600e3), async (req, res) => {
  const roomType = req.body?.roomType === 'video' ? 'video' : 'audio';
  const userId = req.user.id;
  let profile = await profileOf(userId, roomType);
  if (!profile) {
    const name = cleanPublic(text(req.body?.name, 'Oda adı', { min: 2, max: 60, required: true }), 'Oda adı');
    const tags = cleanTags(req.body?.tags);
    const seatCount = Number(req.body?.seatCount ?? 8);
    if (!SUPPORTED_SEATS.has(seatCount)) throw fail('Geçersiz koltuk sayısı.');
    const theme = req.body?.theme === undefined ? 'default' : oneOf(req.body.theme, THEMES, 'Tema');
    profile = (await query(
      `INSERT INTO room_profiles(owner_id, room_type, name, tags, seat_count, theme) VALUES($1,$2,$3,$4,$5,$6)
       ON CONFLICT (owner_id, room_type) DO UPDATE SET updated_at = room_profiles.updated_at RETURNING *`,
      [userId, roomType, name, tags, seatCount, theme],
    )).rows[0];
  }
  const { room, created } = await openFromProfile(userId, profile, req.body?.hidden === true);
  res.status(created ? 201 : 200).json({ room: roomJson(room, { showCode: true }), created });
});

// Oda yöneticileri (oda kapalıyken de kalıcı). Oda sahibi ilk sırada.
router.get('/:roomId/managers', requireAuth, async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const room = await activeRoom(roomId);
  const r = await query(
    `SELECT s.role, ${USER_PUBLIC_COLUMNS}
     FROM room_staff s JOIN users u ON u.id = s.user_id ${USER_PUBLIC_JOINS}
     WHERE s.owner_id = $1 AND s.room_type = $2 AND u.account_status = 'active'
     ORDER BY (s.role = 'cohost') DESC, s.created_at`,
    [room.owner_id, room.room_type],
  );
  const owner = (await loadPublicRows([room.owner_id]))[0];
  res.json({
    managers: [
      ...(owner ? [{ role: 'owner', user: publicUser(owner, req.user.id) }] : []),
      ...r.rows.map((m) => ({ role: m.role, user: publicUser(m, req.user.id) })),
    ],
  });
});

// ---------- Favori yayıncılar ve son girilen odalar ----------
// Oda kapanınca silindiği için favori "oda" değil "yayıncı"dır; yayıncı yeni oda açınca listede açık görünür.
const ACTIVE_ROOM_BY_HOST = `
  (SELECT json_build_object('id', r.id, 'name', r.name, 'roomType', r.room_type, 'seatCount', r.seat_count, 'locked', (r.password_hash IS NOT NULL),
      'memberCount', (SELECT COUNT(*)::int FROM room_members rm WHERE rm.room_id = r.id))
   FROM rooms r WHERE r.owner_id = h.host_id AND r.is_active = TRUE AND r.is_hidden = FALSE ORDER BY r.created_at DESC LIMIT 1)`;

router.get('/favorites', requireAuth, async (req, res) => {
  const r = await query(
    `SELECT ${USER_PUBLIC_COLUMNS}, ${ACTIVE_ROOM_BY_HOST} AS room, f.created_at AS fav_at
     FROM favorite_hosts f JOIN users u ON u.id = f.host_id ${USER_PUBLIC_JOINS}
     CROSS JOIN LATERAL (SELECT f.host_id) h
     WHERE f.user_id = $1 AND u.account_status = 'active'
     ORDER BY (SELECT 1 FROM rooms r WHERE r.owner_id = f.host_id AND r.is_active = TRUE AND r.is_hidden = FALSE LIMIT 1) NULLS LAST, f.created_at DESC LIMIT 200`,
    [req.user.id],
  );
  res.json({ hosts: r.rows.map((x) => ({ user: publicUser(x, req.user.id), room: x.room })) });
});

router.get('/recent', requireAuth, async (req, res) => {
  const r = await query(
    `SELECT ${USER_PUBLIC_COLUMNS}, rr.room_name, rr.room_type, rr.visited_at, ${ACTIVE_ROOM_BY_HOST} AS room
     FROM recent_rooms rr JOIN users u ON u.id = rr.host_id ${USER_PUBLIC_JOINS}
     CROSS JOIN LATERAL (SELECT rr.host_id) h
     WHERE rr.user_id = $1 AND u.account_status = 'active' ORDER BY rr.visited_at DESC LIMIT 30`,
    [req.user.id],
  );
  res.json({ recent: r.rows.map((x) => ({ user: publicUser(x, req.user.id), roomName: x.room_name, roomType: x.room_type, visitedAt: x.visited_at, room: x.room })) });
});

router.post('/hosts/:userId/favorite', requireAuth, userLimit('favorite', 60, 60e3), async (req, res) => {
  const hostId = uuid(req.params.userId, 'Yayıncı');
  if (hostId === req.user.id) throw fail('Kendinizi favorilere ekleyemezsiniz.');
  const h = (await query(`SELECT 1 FROM users WHERE id = $1 AND account_status = 'active'`, [hostId])).rowCount;
  if (!h) throw fail('Kullanıcı bulunamadı.', 404);
  const n = (await query(`SELECT COUNT(*)::int AS n FROM favorite_hosts WHERE user_id = $1`, [req.user.id])).rows[0].n;
  if (n >= 200) throw fail('En fazla 200 favori ekleyebilirsiniz.', 409);
  await query(`INSERT INTO favorite_hosts(user_id, host_id) VALUES($1,$2) ON CONFLICT DO NOTHING`, [req.user.id, hostId]);
  res.json({ ok: true, favorite: true });
});

router.delete('/hosts/:userId/favorite', requireAuth, async (req, res) => {
  const hostId = uuid(req.params.userId, 'Yayıncı');
  await query(`DELETE FROM favorite_hosts WHERE user_id = $1 AND host_id = $2`, [req.user.id, hostId]);
  res.json({ ok: true, favorite: false });
});

router.get('/hosts/:userId/favorite', requireAuth, async (req, res) => {
  const hostId = uuid(req.params.userId, 'Yayıncı');
  const r = await query(`SELECT 1 FROM favorite_hosts WHERE user_id = $1 AND host_id = $2`, [req.user.id, hostId]);
  res.json({ favorite: r.rowCount > 0 });
});

router.get('/:roomId', requireAuth, async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const r = (await query(
    `SELECT r.id AS room_id, r.name AS room_name, r.room_type, r.seat_count, r.owner_id, r.created_at AS room_created_at, r.tags, r.chat_enabled,
       r.is_hidden, r.join_code, r.theme, r.theme_image_url, r.scoreboard_enabled, r.locked_seats,
       (r.password_hash IS NOT NULL) AS locked, ${USER_PUBLIC_COLUMNS}
     FROM rooms r JOIN users u ON u.id = r.owner_id ${USER_PUBLIC_JOINS} WHERE r.id = $1 AND r.is_active = TRUE`,
    [roomId],
  )).rows[0];
  if (!r) throw fail('Oda bulunamadı.', 404);
  const me = await memberOf(roomId, req.user.id);
  if (r.is_hidden && !me && r.owner_id !== req.user.id) throw fail('Oda bulunamadı.', 404);
  const canSeeCode = me && ['owner', 'cohost'].includes(me.role);
  res.json({
    room: {
      id: r.room_id, name: r.room_name, roomType: r.room_type, seatCount: r.seat_count, ownerId: r.owner_id, createdAt: r.room_created_at,
      tags: r.tags ?? [], locked: r.locked, chatEnabled: r.chat_enabled !== false,
      hidden: r.is_hidden, theme: r.theme, themeImageUrl: r.theme_image_url, scoreboardEnabled: r.scoreboard_enabled, lockedSeats: r.locked_seats ?? [],
      ...(canSeeCode && r.join_code ? { joinCode: r.join_code } : {}),
      owner: publicUser(r, req.user.id),
    },
    me: me ? { role: me.role, microphone: me.microphone, seatIndex: me.seat_index } : null,
  });
});

// ---------- Katılma / ayrılma ----------
// Gizli odaya davet koduyla ulaşılır. Kaba kuvvet denemelerine karşı sıkı sınır vardır.
router.post('/by-code', requireAuth, userLimit('room_code', 15, 10 * 60e3), async (req, res) => {
  const code = String(req.body?.code ?? '').trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(code)) throw fail('Davet kodu 6 karakter olmalı.');
  const r = (await query(`SELECT id, name FROM rooms WHERE join_code = $1 AND is_active = TRUE`, [code])).rows[0];
  if (!r) {
    noteViolation(clientIp(req), 'room_code_guess', { userId: req.user.id, weight: 1 });
    throw fail('Bu koda ait oda bulunamadı.', 404);
  }
  res.json({ roomId: r.id, name: r.name });
});

router.post('/:roomId/join', requireAuth, userLimit('room_join', 40, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const userId = req.user.id;
  const room = await activeRoom(roomId);
  if (room.is_hidden && room.owner_id !== userId && !(await memberOf(roomId, userId))) {
    const code = String(req.body?.code ?? '').trim().toUpperCase();
    if (!code || code !== room.join_code) throw fail('Bu oda gizli; davet kodu gerekli.', 403);
  }
  const blocked = await query(`SELECT 1 FROM room_blocks WHERE room_id = $1 AND blocked_user_id = $2`, [roomId, userId]);
  if (blocked.rowCount) throw fail('Bu odaya girişiniz engellenmiş.', 403);

  // Şifreli oda: zaten üye olanlar (yeniden bağlanma) ve oda sahibi şifre girmeden geçer.
  if (room.password_hash && room.owner_id !== userId && !(await memberOf(roomId, userId))) {
    if (!hitLimit(`roompw:${roomId}:${userId}`, 5, 10 * 60e3).allowed) {
      noteViolation(clientIp(req), 'room_password_bruteforce', { userId, weight: 3 });
      throw fail('Çok fazla hatalı şifre denemesi. Biraz sonra tekrar deneyin.', 429);
    }
    const pw = String(req.body?.password ?? '');
    if (!pw || !(await checkPassword(pw, room.password_hash))) throw fail('Oda şifresi hatalı.', 403);
  }

  const staffRole = room.owner_id === userId ? null
    : (await query(`SELECT role FROM room_staff WHERE owner_id = $1 AND room_type = $2 AND user_id = $3`, [room.owner_id, room.room_type, userId])).rows[0]?.role ?? null;
  const ins = await query(
    `INSERT INTO room_members(room_id, user_id, role) VALUES($1,$2,$3) ON CONFLICT (room_id, user_id) DO NOTHING RETURNING user_id`,
    [roomId, userId, room.owner_id === userId ? 'owner' : (staffRole ?? 'user')],
  );
  if (ins.rowCount) {
    const row = await loadPublicRow(userId);
    // Gizli kullanıcı odaya giriş efektiyle duyurulmaz.
    const effect = row.is_hidden ? null : await activeEntranceEffect(userId);
    hub.broadcastRoom(roomId, { type: 'room_member_joined', roomId, user: publicUser(row, null), entranceEffect: effect });
  }
  if (room.owner_id !== userId && !room.is_hidden) {
    await query(
      `INSERT INTO recent_rooms(user_id, host_id, room_name, room_type) VALUES($1,$2,$3,$4)
       ON CONFLICT (user_id, host_id) DO UPDATE SET room_name = EXCLUDED.room_name, room_type = EXCLUDED.room_type, visited_at = NOW()`,
      [userId, room.owner_id, room.name, room.room_type],
    );
    await query(
      `DELETE FROM recent_rooms WHERE user_id = $1 AND host_id NOT IN (SELECT host_id FROM recent_rooms WHERE user_id = $1 ORDER BY visited_at DESC LIMIT 30)`,
      [userId],
    );
  }
  const me = await memberOf(roomId, userId);
  res.json({
    room: roomJson(room, { showCode: ['owner', 'cohost'].includes(me.role) }),
    me: { role: me.role, microphone: me.microphone, seatIndex: me.seat_index },
    joined: ins.rowCount > 0,
  });
});

// Oda ayarları: ad, etiketler, şifre, sohbet açık/kapalı (oda sahibi ve yardımcı sahip).
router.patch('/:roomId', requireAuth, userLimit('room_settings', 20, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await activeRoom(roomId);
  const me = await memberOf(roomId, req.user.id);
  if (!me || !['owner', 'cohost'].includes(me.role)) throw fail('Oda ayarlarını yalnızca oda sahibi ve yardımcı sahip değiştirebilir.', 403);
  const sets = []; const values = [];
  const set = (col, v) => { values.push(v); sets.push(`${col} = $${values.length}`); };
  const b = req.body ?? {};
  if (b.name !== undefined) set('name', cleanPublic(text(b.name, 'Oda adı', { min: 2, max: 60, required: true }), 'Oda adı'));
  if (b.tags !== undefined) set('tags', cleanTags(b.tags));
  if (b.chatEnabled !== undefined) { if (typeof b.chatEnabled !== 'boolean') throw fail('chatEnabled true/false olmalı.'); set('chat_enabled', b.chatEnabled); }
  if (b.theme !== undefined) set('theme', oneOf(b.theme, THEMES, 'Tema'));
  if (b.themeImageUrl !== undefined) {
    if (b.themeImageUrl !== null && b.themeImageUrl !== '') {
      if (!(await featuresFor(req.user.id)).customRoomTheme) throw fail('Özel tema görseli için WIP 4 veya üzeri gerekir.', 403);
      const u = String(b.themeImageUrl);
      if (u.length > 500 || !/^https:\/\//.test(u)) throw fail('Tema görseli https adresi olmalı.');
      set('theme_image_url', u);
    } else set('theme_image_url', null);
  }
  if (b.scoreboardEnabled !== undefined) { if (typeof b.scoreboardEnabled !== 'boolean') throw fail('scoreboardEnabled true/false olmalı.'); set('scoreboard_enabled', b.scoreboardEnabled); }
  if (b.hidden !== undefined) {
    if (typeof b.hidden !== 'boolean') throw fail('hidden true/false olmalı.');
    if (me.role !== 'owner') throw fail('Odayı yalnızca oda sahibi gizleyebilir.', 403);
    const cur = await activeRoom(roomId);
    set('is_hidden', b.hidden);
    if (!b.hidden) set('join_code', null);
    else if (!cur.is_hidden || cur.join_code === null || b.regenerateCode === true) set('join_code', await uniqueCode(query));
  } else if (b.regenerateCode === true) {
    const cur = await activeRoom(roomId);
    if (!cur.is_hidden) throw fail('Davet kodu yalnızca gizli odalarda vardır.');
    if (me.role !== 'owner') throw fail('Kodu yalnızca oda sahibi yenileyebilir.', 403);
    set('join_code', await uniqueCode(query));
  }
  if (b.password !== undefined) {
    if (me.role !== 'owner') throw fail('Oda şifresini yalnızca oda sahibi değiştirebilir.', 403);
    set('password_hash', b.password === null || b.password === '' ? null : await hashPassword(text(b.password, 'Oda şifresi', { min: 4, max: 12, required: true })));
  }
  if (!sets.length) throw fail('Değiştirilecek alan yok.');
  values.push(roomId);
  const r = (await query(`UPDATE rooms SET ${sets.join(', ')} WHERE id = $${values.length} RETURNING *`, values)).rows[0];
  // Kalıcı oda bilgisi (ad, etiket, tema) bir sonraki açılış için saklanır.
  if (b.name !== undefined || b.tags !== undefined || b.theme !== undefined) {
    await query(
      `UPDATE room_profiles SET name = $3, tags = $4, theme = $5, updated_at = NOW() WHERE owner_id = $1 AND room_type = $2`,
      [r.owner_id, r.room_type, r.name, r.tags ?? [], r.theme],
    );
  }
  hub.broadcastRoom(roomId, {
    type: 'room_settings', roomId, name: r.name, tags: r.tags, locked: Boolean(r.password_hash), chatEnabled: r.chat_enabled,
    theme: r.theme, themeImageUrl: r.theme_image_url, scoreboardEnabled: r.scoreboard_enabled, hidden: r.is_hidden,
  });
  res.json({ room: roomJson(r, { showCode: true }) });
});

router.post('/:roomId/leave', requireAuth, async (req, res) => {
  await leaveRoom(req.user.id, uuid(req.params.roomId, 'Oda'));
  res.json({ ok: true });
});

router.post('/:roomId/close', requireAuth, async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const room = await activeRoom(roomId);
  if (room.owner_id !== req.user.id) throw fail('Odayı yalnızca sahibi kapatabilir.', 403);
  await closeRoom(roomId);
  res.json({ ok: true });
});

router.get('/:roomId/members', requireAuth, async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const r = await query(
    `SELECT rm.role, rm.microphone, rm.seat_index, rm.joined_at, ${USER_PUBLIC_COLUMNS}
     FROM room_members rm JOIN users u ON u.id = rm.user_id ${USER_PUBLIC_JOINS}
     WHERE rm.room_id = $1 ORDER BY rm.seat_index NULLS LAST, rm.joined_at`,
    [roomId],
  );
  res.json({
    members: r.rows.map((m) => ({
      userId: m.id, role: m.role, microphone: m.microphone, seatIndex: m.seat_index, joinedAt: m.joined_at,
      user: publicUser(m, req.user.id),
    })),
  });
});

// ---------- Mikrofon / koltuk ----------
router.post('/:roomId/mic/take', requireAuth, userLimit('mic', 60, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const userId = req.user.id;
  const room = await activeRoom(roomId);
  const member = await memberOf(roomId, userId);
  if (!member) throw fail('Önce odaya girin.', 403);

  const seatIndex = await tx(async (c) => {
    await c.query(`SELECT id FROM rooms WHERE id = $1 FOR UPDATE`, [roomId]); // koltuk atamalarını sıraya sokar
    const others = (await c.query(
      `SELECT seat_index FROM room_members WHERE room_id = $1 AND seat_index IS NOT NULL AND user_id <> $2`, [roomId, userId],
    )).rows;
    const taken = new Set(others.map((x) => x.seat_index));
    let target = req.body?.seatIndex;
    if (target === undefined || target === null) {
      if (member.seat_index !== null) return member.seat_index;
      const first = member.role === 'owner' ? 0 : 1;
      target = undefined;
      const lockedNow = SEAT_MANAGERS.includes(member.role) ? [] : (room.locked_seats ?? []);
      for (let i = first; i < room.seat_count; i += 1) if (!taken.has(i) && !lockedNow.includes(i)) { target = i; break; }
      if (target === undefined) throw fail('Boş mikrofon yok.', 409);
    } else {
      target = Number(target);
      if (!Number.isInteger(target) || target < 0 || target >= room.seat_count) throw fail('Geçersiz koltuk.');
      if (target === 0 && member.role !== 'owner') throw fail('Bu koltuk oda sahibine ayrılmıştır.', 403);
      if (taken.has(target)) throw fail('Koltuk dolu.', 409);
      if ((room.locked_seats ?? []).includes(target) && !SEAT_MANAGERS.includes(member.role)) throw fail('Bu koltuk kilitli.', 403);
    }
    await c.query(`UPDATE room_members SET seat_index = $3, microphone = TRUE WHERE room_id = $1 AND user_id = $2`, [roomId, userId, target]);
    await openMicSession(userId, roomId, (t, p) => c.query(t, p));
    return target;
  });
  await setCanPublish(roomId, userId, true);
  await removeFromQueue(roomId, userId);
  hub.broadcastRoom(roomId, { type: 'room_seat_changed', roomId, userId, seatIndex, microphone: true });
  res.json({ ok: true, seatIndex });
});

async function releaseSeat(roomId, userId) {
  await query(`UPDATE room_members SET seat_index = NULL, microphone = FALSE WHERE room_id = $1 AND user_id = $2`, [roomId, userId]);
  await closeMicSessions(userId, roomId);
  await setCanPublish(roomId, userId, false);
  hub.broadcastRoom(roomId, { type: 'room_seat_changed', roomId, userId, seatIndex: null, microphone: false });
  await notifyNext(roomId).catch((e) => console.error('Mikrofon sırası hatası:', e.message));
}

// ---------- Mikrofon sırası ----------
router.get('/:roomId/mic/queue', requireAuth, async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await activeRoom(roomId);
  if (!(await memberOf(roomId, req.user.id))) throw fail('Önce odaya girin.', 403);
  res.json({ queue: await queueOf(roomId) });
});

router.post('/:roomId/mic/queue', requireAuth, userLimit('mic_queue', 30, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await activeRoom(roomId);
  const me = await memberOf(roomId, req.user.id);
  if (!me) throw fail('Önce odaya girin.', 403);
  if (me.seat_index !== null) throw fail('Zaten mikrofondasınız.', 409);
  const n = (await query(`SELECT COUNT(*)::int AS n FROM room_mic_queue WHERE room_id = $1`, [roomId])).rows[0].n;
  if (n >= 50) throw fail('Sıra dolu.', 409);
  await query(`INSERT INTO room_mic_queue(room_id, user_id) VALUES($1,$2) ON CONFLICT DO NOTHING`, [roomId, req.user.id]);
  await broadcastQueue(roomId);
  await notifyNext(roomId).catch(() => {}); // boş koltuk zaten varsa hemen davet edilir
  res.json({ ok: true, queue: await queueOf(roomId) });
});

router.delete('/:roomId/mic/queue', requireAuth, async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await removeFromQueue(roomId, req.user.id);
  res.json({ ok: true, queue: await queueOf(roomId) });
});

router.post('/:roomId/mic/leave', requireAuth, async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  if (!(await memberOf(roomId, req.user.id))) throw fail('Önce odaya girin.', 403);
  await releaseSeat(roomId, req.user.id);
  res.json({ ok: true });
});

// ---------- Moderasyon ----------
async function moderationContext(roomId, actorId, targetId) {
  if (actorId === targetId) throw fail('Bu işlemi kendiniz üzerinde yapamazsınız.');
  const rows = (await query(
    `SELECT user_id, role FROM room_members WHERE room_id = $1 AND user_id = ANY($2::uuid[])`, [roomId, [actorId, targetId]],
  )).rows;
  const actor = rows.find((x) => x.user_id === actorId);
  if (!actor) throw fail('Önce odaya girin.', 403);
  const target = rows.find((x) => x.user_id === targetId) || null;
  return { actor, target };
}

async function assertNotImmune(actor, targetId) {
  if (actor.role === 'owner') return; // oda sahibi her zaman işlem yapabilir
  const f = await featuresFor(targetId);
  if (f.kickImmunity) throw fail('Bu kullanıcı yetkililer tarafından uzaklaştırılamaz (WIP ayrıcalığı).', 403);
}

router.post('/:roomId/members/:userId/mic-off', requireAuth, userLimit('moderate', 60, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  await activeRoom(roomId);
  const { actor, target } = await moderationContext(roomId, req.user.id, targetId);
  if (!target) throw fail('Kullanıcı odada değil.', 404);
  if (!canManage(actor.role, target.role, 'moderate')) throw fail('Bu işlem için yetkiniz yok.', 403);
  await assertNotImmune(actor, targetId);
  await releaseSeat(roomId, targetId);
  res.json({ ok: true });
});

async function removeFromRoom(roomId, targetId, type) {
  await leaveRoom(targetId, roomId);
  hub.sendToUser(targetId, { type, roomId });
  await removeParticipant(roomId, targetId);
}

router.post('/:roomId/members/:userId/kick', requireAuth, userLimit('moderate', 60, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  await activeRoom(roomId);
  const { actor, target } = await moderationContext(roomId, req.user.id, targetId);
  if (!target) throw fail('Kullanıcı odada değil.', 404);
  if (!canManage(actor.role, target.role, 'moderate')) throw fail('Bu işlem için yetkiniz yok.', 403);
  await assertNotImmune(actor, targetId);
  await removeFromRoom(roomId, targetId, 'room_kicked');
  res.json({ ok: true });
});

router.post('/:roomId/members/:userId/block', requireAuth, userLimit('moderate', 60, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  await activeRoom(roomId);
  const { actor, target } = await moderationContext(roomId, req.user.id, targetId);
  if (!canManage(actor.role, target?.role ?? 'user', 'moderate')) throw fail('Bu işlem için yetkiniz yok.', 403);
  await assertNotImmune(actor, targetId);
  await query(
    `INSERT INTO room_blocks(room_id, blocked_user_id, blocked_by_user_id) VALUES($1,$2,$3) ON CONFLICT (room_id, blocked_user_id) DO NOTHING`,
    [roomId, targetId, req.user.id],
  );
  if (target) await removeFromRoom(roomId, targetId, 'room_blocked');
  res.json({ ok: true });
});

router.delete('/:roomId/blocks/:userId', requireAuth, async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  const me = await memberOf(roomId, req.user.id);
  if (!me || !['owner', 'cohost', 'moderator'].includes(me.role)) throw fail('Bu işlem için yetkiniz yok.', 403);
  await query(`DELETE FROM room_blocks WHERE room_id = $1 AND blocked_user_id = $2`, [roomId, targetId]);
  res.json({ ok: true });
});

// Koltuk kilitle / aç (oda sahibi ve moderatörler). Dolu koltuk kilitlenirse oturan kişi koltuktan indirilir (yetki yeterliyse).
router.post('/:roomId/seats/:index/lock', requireAuth, userLimit('moderate', 60, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const room = await activeRoom(roomId);
  const idx = Number(req.params.index);
  if (!Number.isInteger(idx) || idx < 1 || idx >= room.seat_count) throw fail('Bu koltuk kilitlenemez.');
  const me = await memberOf(roomId, req.user.id);
  if (!me || !SEAT_MANAGERS.includes(me.role)) throw fail('Koltukları yalnızca oda sahibi ve moderatörler kilitleyebilir.', 403);
  const locked = req.body?.locked !== false;
  const occupant = (await query(`SELECT user_id, role FROM room_members WHERE room_id = $1 AND seat_index = $2`, [roomId, idx])).rows[0];
  if (locked && occupant && occupant.user_id !== req.user.id && !canManage(me.role, occupant.role, 'moderate')) throw fail('Koltuktaki kişiyi indirme yetkiniz yok.', 403);
  const r = await query(
    locked
      ? `UPDATE rooms SET locked_seats = (SELECT ARRAY(SELECT DISTINCT x FROM unnest(locked_seats || $2::int) x ORDER BY x)) WHERE id = $1 RETURNING locked_seats`
      : `UPDATE rooms SET locked_seats = array_remove(locked_seats, $2::int) WHERE id = $1 RETURNING locked_seats`,
    [roomId, idx],
  );
  if (locked && occupant && occupant.user_id !== req.user.id) await releaseSeat(roomId, occupant.user_id);
  hub.broadcastRoom(roomId, { type: 'room_seats_locked', roomId, lockedSeats: r.rows[0].locked_seats });
  res.json({ ok: true, lockedSeats: r.rows[0].locked_seats });
});

// Mikrofona davet: davet edilen kişi kabul ederse mic/take ile oturur.
router.post('/:roomId/members/:userId/mic-invite', requireAuth, userLimit('mic_invite', 30, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  const room = await activeRoom(roomId);
  const { actor, target } = await moderationContext(roomId, req.user.id, targetId);
  if (!SEAT_MANAGERS.includes(actor.role)) throw fail('Mikrofona yalnızca oda sahibi ve moderatörler davet edebilir.', 403);
  if (!target) throw fail('Kullanıcı odada değil.', 404);
  const t = (await query(`SELECT seat_index FROM room_members WHERE room_id = $1 AND user_id = $2`, [roomId, targetId])).rows[0];
  if (t.seat_index !== null) throw fail('Kullanıcı zaten mikrofonda.', 409);
  let seatIndex = req.body?.seatIndex ?? null;
  if (seatIndex !== null) {
    seatIndex = Number(seatIndex);
    if (!Number.isInteger(seatIndex) || seatIndex < 1 || seatIndex >= room.seat_count) throw fail('Geçersiz koltuk.');
  }
  hub.sendToUser(targetId, { type: 'mic_invite', roomId, seatIndex, fromUserId: req.user.id, fromName: req.user.display_name });
  res.json({ ok: true });
});

router.post('/:roomId/members/:userId/role', requireAuth, userLimit('moderate', 60, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  const role = oneOf(req.body?.role, ['user', 'moderator', 'cohost'], 'Rol');
  await activeRoom(roomId);
  const { actor, target } = await moderationContext(roomId, req.user.id, targetId);
  if (!target) throw fail('Kullanıcı odada değil.', 404);
  if (!canManage(actor.role, target.role, 'role', role)) throw fail('Bu işlem için yetkiniz yok.', 403);
  await query(`UPDATE room_members SET role = $3 WHERE room_id = $1 AND user_id = $2`, [roomId, targetId, role]);
  // Yöneticiler oda kapanıp yeniden açılsa da korunur.
  const roomRow = await activeRoom(roomId);
  if (role === 'user') await query(`DELETE FROM room_staff WHERE owner_id = $1 AND room_type = $2 AND user_id = $3`, [roomRow.owner_id, roomRow.room_type, targetId]);
  else await query(
    `INSERT INTO room_staff(owner_id, room_type, user_id, role) VALUES($1,$2,$3,$4) ON CONFLICT (owner_id, room_type, user_id) DO UPDATE SET role = EXCLUDED.role`,
    [roomRow.owner_id, roomRow.room_type, targetId, role],
  );
  hub.broadcastRoom(roomId, { type: 'room_role_changed', roomId, userId: targetId, role });
  res.json({ ok: true, role });
});

// ---------- Hediye sayı tahtası (mikrofon koltuğu başına) ----------
router.get('/:roomId/scoreboard', requireAuth, async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await activeRoom(roomId);
  if (!(await memberOf(roomId, req.user.id))) throw fail('Önce odaya girin.', 403);
  res.json({ scoreboard: await scoreboardOf(roomId) });
});

router.post('/:roomId/scoreboard/reset', requireAuth, userLimit('scoreboard_reset', 10, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await activeRoom(roomId);
  const me = await memberOf(roomId, req.user.id);
  if (!me || !['owner', 'cohost'].includes(me.role)) throw fail('Sayaçları yalnızca oda sahibi ve yardımcı sahip sıfırlayabilir.', 403);
  await query(`DELETE FROM room_gift_totals WHERE room_id = $1`, [roomId]);
  hub.broadcastRoom(roomId, { type: 'room_scoreboard', roomId, scoreboard: [], reset: true });
  res.json({ ok: true });
});

// ---------- LiveKit ----------
router.post('/:roomId/livekit-token', requireAuth, async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await activeRoom(roomId);
  const m = (await query(
    `SELECT rm.user_id, rm.microphone, u.username, u.display_name, u.is_hidden
     FROM room_members rm JOIN users u ON u.id = rm.user_id WHERE rm.room_id = $1 AND rm.user_id = $2`,
    [roomId, req.user.id],
  )).rows[0];
  if (!m) throw fail('Önce odaya girin.', 403);
  const jwt = await livekitToken({
    identity: m.user_id,
    name: m.is_hidden ? 'Gizli Kullanıcı' : (m.display_name || m.username),
    room: roomId,
    canPublish: m.microphone === true,
  });
  res.json({ token: jwt, url: process.env.LIVEKIT_URL });
});
