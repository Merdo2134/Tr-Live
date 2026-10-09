import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, uuid } from '../http.js';
import { hub } from '../realtime.js';
import { validDuration } from '../pk_logic.js';
import { pkView, broadcastPk, activePkOfRoom, finishPk } from '../services/pk.js';

export const router = Router();
router.use(requireAuth);

async function roomRow(id, run = query) {
  const r = (await run(`SELECT id, owner_id, name FROM rooms WHERE id = $1 AND is_active = TRUE`, [id])).rows[0];
  if (!r) throw fail('Oda bulunamadı.', 404);
  return r;
}

// Meydan okuma: yalnızca kendi odanızın sahibi başka bir odaya PK daveti gönderir.
router.post('/pk/challenge', userLimit('pk', 20, 60e3), async (req, res) => {
  const roomId = uuid(req.body?.roomId, 'Oda');
  const targetRoomId = uuid(req.body?.targetRoomId, 'Hedef oda');
  const durationSeconds = Number(req.body?.durationSeconds ?? 300);
  if (!validDuration(durationSeconds)) throw fail('Süre 60-1800 saniye arasında olmalı.');
  if (roomId === targetRoomId) throw fail('Kendi odanıza meydan okuyamazsınız.');
  const id = await tx(async (c) => {
    // Kilit sırası sabit (id sıralı) → deadlock yok.
    const rooms = (await c.query(`SELECT id, owner_id FROM rooms WHERE id = ANY($1::uuid[]) AND is_active = TRUE ORDER BY id FOR UPDATE`, [[roomId, targetRoomId]])).rows;
    const mine = rooms.find((r) => r.id === roomId); const theirs = rooms.find((r) => r.id === targetRoomId);
    if (!mine || !theirs) throw fail('Oda bulunamadı.', 404);
    if (mine.owner_id !== req.user.id) throw fail('PK başlatmak için oda sahibi olmalısınız.', 403);
    if (await activePkOfRoom(roomId, (t, p) => c.query(t, p))) throw fail('Odanızda zaten bir PK var.', 409);
    if (await activePkOfRoom(targetRoomId, (t, p) => c.query(t, p))) throw fail('Hedef odada zaten bir PK var.', 409);
    const b = (await c.query(
      `INSERT INTO pk_battles(room_a, room_b, host_a, host_b, duration_seconds) VALUES($1,$2,$3,$4,$5) RETURNING id`,
      [roomId, targetRoomId, mine.owner_id, theirs.owner_id, durationSeconds],
    )).rows[0];
    return b.id;
  });
  const view = await pkView(id);
  hub.sendToUser(view.b.host.id, { type: 'pk_invite', pk: view });
  await broadcastPk(id);
  res.status(201).json({ pk: view });
});

router.post('/pk/:id/respond', userLimit('pk', 20, 60e3), async (req, res) => {
  const id = uuid(req.params.id, 'PK');
  const accept = req.body?.accept === true;
  await tx(async (c) => {
    const b = (await c.query(`SELECT * FROM pk_battles WHERE id = $1 FOR UPDATE`, [id])).rows[0];
    if (!b || b.status !== 'pending') throw fail('Davet bulunamadı veya süresi doldu.', 404);
    if (b.host_b !== req.user.id) throw fail('Bu daveti yanıtlama yetkiniz yok.', 403);
    if (accept) {
      await c.query(
        `UPDATE pk_battles SET status = 'active', started_at = NOW(), ends_at = NOW() + ($2::int * INTERVAL '1 second') WHERE id = $1`,
        [id, b.duration_seconds],
      );
    } else {
      await c.query(`UPDATE pk_battles SET status = 'declined', finished_at = NOW() WHERE id = $1`, [id]);
    }
  });
  await broadcastPk(id);
  res.json({ ok: true, accepted: accept });
});

// Bekleyen daveti geri çek (davet eden) veya süren PK'yı erken bitir (iki oda sahibinden biri).
router.post('/pk/:id/cancel', async (req, res) => {
  const id = uuid(req.params.id, 'PK');
  const b = (await query(`SELECT * FROM pk_battles WHERE id = $1`, [id])).rows[0];
  if (!b || !['pending', 'active'].includes(b.status)) throw fail('PK bulunamadı.', 404);
  if (![b.host_a, b.host_b].includes(req.user.id)) throw fail('Bu işlem için yetkiniz yok.', 403);
  if (b.status === 'pending') {
    await query(`UPDATE pk_battles SET status = 'cancelled', finished_at = NOW() WHERE id = $1 AND status = 'pending'`, [id]);
    await broadcastPk(id);
  } else {
    await finishPk(id);
  }
  res.json({ ok: true });
});

router.get('/rooms/:roomId/pk', async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const room = (await query(`SELECT owner_id, is_hidden FROM rooms WHERE id = $1`, [roomId])).rows[0];
  if (room?.is_hidden && room.owner_id !== req.user.id
    && !(await query(`SELECT 1 FROM room_members WHERE room_id = $1 AND user_id = $2`, [roomId, req.user.id])).rowCount) {
    throw fail('Oda bulunamadı.', 404);
  }
  const id = await activePkOfRoom(roomId);
  res.json({ pk: id ? await pkView(id) : null });
});

// PK için aday odalar: açık, PK'sı olmayan, gizli olmayan odalar.
router.get('/pk/rooms', async (req, res) => {
  const r = await query(
    `SELECT r.id, r.name, r.owner_id, u.username, u.display_name,
            (SELECT COUNT(*)::int FROM room_members m WHERE m.room_id = r.id) AS members
     FROM rooms r JOIN users u ON u.id = r.owner_id
     WHERE r.is_active = TRUE AND r.is_hidden = FALSE AND r.owner_id <> $1
       AND NOT EXISTS (SELECT 1 FROM pk_battles b WHERE (b.room_a = r.id OR b.room_b = r.id) AND b.status IN ('pending','active'))
     ORDER BY members DESC, r.created_at DESC LIMIT 50`,
    [req.user.id],
  );
  res.json({ rooms: r.rows.map((x) => ({ id: x.id, name: x.name, ownerId: x.owner_id, ownerName: x.display_name || x.username, memberCount: x.members })) });
});
