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
import { loadPublicRow, activeEntranceEffect } from '../services/users.js';
import { leaveRoom, closeRoom, SUPPORTED_SEATS } from '../services/rooms.js';

export const router = Router();

const roomJson = (r) => ({
  id: r.id, name: r.name, roomType: r.room_type, seatCount: r.seat_count, ownerId: r.owner_id, createdAt: r.created_at,
  tags: r.tags ?? [], locked: Boolean(r.password_hash), chatEnabled: r.chat_enabled !== false,
});

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
  const r = await query(
    `SELECT r.id AS room_id, r.name AS room_name, r.room_type, r.seat_count, r.owner_id, r.created_at AS room_created_at, r.tags,
       (r.password_hash IS NOT NULL) AS locked, ${USER_PUBLIC_COLUMNS},
       (SELECT COUNT(*)::int FROM room_members rm WHERE rm.room_id = r.id) AS member_count,
       (SELECT COUNT(*)::int FROM room_members rm WHERE rm.room_id = r.id AND rm.microphone = TRUE) AS mic_count
     FROM rooms r JOIN users u ON u.id = r.owner_id ${USER_PUBLIC_JOINS}
     WHERE r.is_active = TRUE AND ($1::text IS NULL OR r.room_type = $1) AND ($2::text IS NULL OR $2 = ANY(r.tags))
     ORDER BY member_count DESC, r.created_at DESC LIMIT 100`,
    [type, tag],
  );
  // Kullanıcı sütunlarındaki "id" (= sahip kimliği) oda kimliğiyle karışmasın diye oda alanları takma adla alınır.
  res.json({
    rooms: r.rows.map((x) => ({
      id: x.room_id, name: x.room_name, roomType: x.room_type, seatCount: x.seat_count, ownerId: x.owner_id, createdAt: x.room_created_at,
      memberCount: x.member_count, micCount: x.mic_count, tags: x.tags ?? [], locked: x.locked,
      owner: publicUser(x, req.user?.id ?? null),
    })),
  });
});

router.post('/', requireAuth, userLimit('room_create', 10, 3600e3), async (req, res) => {
  const name = text(req.body?.name || 'TR Live Odası', 'Oda adı', { min: 2, max: 60 });
  const tags = cleanTags(req.body?.tags);
  const password = text(req.body?.password, 'Oda şifresi', { min: 4, max: 12 });
  const passwordHash = password ? await hashPassword(password) : null;
  const roomType = req.body?.roomType === 'video' ? 'video' : 'audio';
  const seatCount = Number(req.body?.seatCount ?? 8);
  if (!SUPPORTED_SEATS.has(seatCount)) throw fail('Geçersiz koltuk sayısı.');
  const userId = req.user.id;

  const room = await tx(async (c) => {
    await c.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [userId]); // eşzamanlı oda oluşturmayı sıraya sokar
    const features = await featuresFor(userId, (t, p) => c.query(t, p));
    const owned = (await c.query(`SELECT COUNT(*)::int AS n FROM rooms WHERE owner_id = $1 AND is_active = TRUE`, [userId])).rows[0].n;
    if (owned >= features.maxRooms) {
      throw fail(`Aynı anda en fazla ${features.maxRooms} odanız açık olabilir. WIP seviyeniz arttıkça bu sınır artar.`, 409);
    }
    const r = (await c.query(
      `INSERT INTO rooms(name, room_type, seat_count, owner_id, tags, password_hash) VALUES($1,$2,$3,$4,$5,$6) RETURNING *`,
      [name, roomType, seatCount, userId, tags, passwordHash],
    )).rows[0];
    await c.query(`INSERT INTO room_members(room_id, user_id, role, microphone, seat_index) VALUES($1,$2,'owner',TRUE,0)`, [r.id, userId]);
    // Onaylı yayıncı ise yayın oturumu başlar (süre istatistikleri için).
    const b = (await c.query(`SELECT agency_id FROM broadcasters WHERE user_id = $1 AND status = 'approved'`, [userId])).rows[0];
    if (b) await c.query(`INSERT INTO broadcast_sessions(user_id, room_id, agency_id) VALUES($1,$2,$3)`, [userId, r.id, b.agency_id]);
    return r;
  });
  res.status(201).json({ room: roomJson(room) });
});

router.get('/:roomId', requireAuth, async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const r = (await query(
    `SELECT r.id AS room_id, r.name AS room_name, r.room_type, r.seat_count, r.owner_id, r.created_at AS room_created_at, r.tags, r.chat_enabled,
       (r.password_hash IS NOT NULL) AS locked, ${USER_PUBLIC_COLUMNS}
     FROM rooms r JOIN users u ON u.id = r.owner_id ${USER_PUBLIC_JOINS} WHERE r.id = $1 AND r.is_active = TRUE`,
    [roomId],
  )).rows[0];
  if (!r) throw fail('Oda bulunamadı.', 404);
  const me = await memberOf(roomId, req.user.id);
  res.json({
    room: {
      id: r.room_id, name: r.room_name, roomType: r.room_type, seatCount: r.seat_count, ownerId: r.owner_id, createdAt: r.room_created_at,
      tags: r.tags ?? [], locked: r.locked, chatEnabled: r.chat_enabled !== false,
      owner: publicUser(r, req.user.id),
    },
    me: me ? { role: me.role, microphone: me.microphone, seatIndex: me.seat_index } : null,
  });
});

// ---------- Katılma / ayrılma ----------
router.post('/:roomId/join', requireAuth, userLimit('room_join', 40, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const userId = req.user.id;
  const room = await activeRoom(roomId);
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

  const ins = await query(
    `INSERT INTO room_members(room_id, user_id, role) VALUES($1,$2,$3) ON CONFLICT (room_id, user_id) DO NOTHING RETURNING user_id`,
    [roomId, userId, room.owner_id === userId ? 'owner' : 'user'],
  );
  if (ins.rowCount) {
    const row = await loadPublicRow(userId);
    // Gizli kullanıcı odaya giriş efektiyle duyurulmaz.
    const effect = row.is_hidden ? null : await activeEntranceEffect(userId);
    hub.broadcastRoom(roomId, { type: 'room_member_joined', roomId, user: publicUser(row, null), entranceEffect: effect });
  }
  const me = await memberOf(roomId, userId);
  res.json({
    room: { id: room.id, name: room.name, roomType: room.room_type, seatCount: room.seat_count, ownerId: room.owner_id, tags: room.tags ?? [], locked: Boolean(room.password_hash), chatEnabled: room.chat_enabled !== false },
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
  if (b.name !== undefined) set('name', text(b.name, 'Oda adı', { min: 2, max: 60, required: true }));
  if (b.tags !== undefined) set('tags', cleanTags(b.tags));
  if (b.chatEnabled !== undefined) { if (typeof b.chatEnabled !== 'boolean') throw fail('chatEnabled true/false olmalı.'); set('chat_enabled', b.chatEnabled); }
  if (b.password !== undefined) {
    if (me.role !== 'owner') throw fail('Oda şifresini yalnızca oda sahibi değiştirebilir.', 403);
    set('password_hash', b.password === null || b.password === '' ? null : await hashPassword(text(b.password, 'Oda şifresi', { min: 4, max: 12, required: true })));
  }
  if (!sets.length) throw fail('Değiştirilecek alan yok.');
  values.push(roomId);
  const r = (await query(`UPDATE rooms SET ${sets.join(', ')} WHERE id = $${values.length} RETURNING *`, values)).rows[0];
  hub.broadcastRoom(roomId, { type: 'room_settings', roomId, name: r.name, tags: r.tags, locked: Boolean(r.password_hash), chatEnabled: r.chat_enabled });
  res.json({ room: roomJson(r) });
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
      for (let i = first; i < room.seat_count; i += 1) if (!taken.has(i)) { target = i; break; }
      if (target === undefined) throw fail('Boş mikrofon yok.', 409);
    } else {
      target = Number(target);
      if (!Number.isInteger(target) || target < 0 || target >= room.seat_count) throw fail('Geçersiz koltuk.');
      if (target === 0 && member.role !== 'owner') throw fail('Bu koltuk oda sahibine ayrılmıştır.', 403);
      if (taken.has(target)) throw fail('Koltuk dolu.', 409);
    }
    await c.query(`UPDATE room_members SET seat_index = $3, microphone = TRUE WHERE room_id = $1 AND user_id = $2`, [roomId, userId, target]);
    return target;
  });
  await setCanPublish(roomId, userId, true);
  hub.broadcastRoom(roomId, { type: 'room_seat_changed', roomId, userId, seatIndex, microphone: true });
  res.json({ ok: true, seatIndex });
});

async function releaseSeat(roomId, userId) {
  await query(`UPDATE room_members SET seat_index = NULL, microphone = FALSE WHERE room_id = $1 AND user_id = $2`, [roomId, userId]);
  await setCanPublish(roomId, userId, false);
  hub.broadcastRoom(roomId, { type: 'room_seat_changed', roomId, userId, seatIndex: null, microphone: false });
}

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

router.post('/:roomId/members/:userId/role', requireAuth, userLimit('moderate', 60, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  const role = oneOf(req.body?.role, ['user', 'moderator', 'cohost'], 'Rol');
  await activeRoom(roomId);
  const { actor, target } = await moderationContext(roomId, req.user.id, targetId);
  if (!target) throw fail('Kullanıcı odada değil.', 404);
  if (!canManage(actor.role, target.role, 'role', role)) throw fail('Bu işlem için yetkiniz yok.', 403);
  await query(`UPDATE room_members SET role = $3 WHERE room_id = $1 AND user_id = $2`, [roomId, targetId, role]);
  hub.broadcastRoom(roomId, { type: 'room_role_changed', roomId, userId: targetId, role });
  res.json({ ok: true, role });
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
