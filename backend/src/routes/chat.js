import { Router } from 'express';
import { query } from '../database.js';
import { requireAuth } from '../auth.js';
import { config } from '../config.js';
import { fail, uuid, positiveInt } from '../http.js';
import { userLimit } from '../firewall.js';
import { hub } from '../realtime.js';
import { cleanLine, containsBanned, looksLikeFlood } from '../text_safety.js';
import { canManage } from '../room_permissions.js';
import { featuresFor } from '../services/wip.js';
import { noteTask } from '../services/daily.js';
import { loadPublicRow } from '../services/users.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';

export const router = Router();
router.use(requireAuth);

const MANAGERS = ['owner', 'cohost', 'moderator'];
const banned = config.bannedWords.map((w) => w.toLocaleLowerCase('tr'));

async function roomAndMember(roomId, userId) {
  const room = (await query(`SELECT id, chat_enabled FROM rooms WHERE id = $1 AND is_active = TRUE`, [roomId])).rows[0];
  if (!room) throw fail('Oda bulunamadı.', 404);
  // Susturma odadan çıkıp girince kaybolmasın: kalıcı kayıt (room_mutes) ile üyelikteki süre birleştirilir.
  const member = (await query(
    `SELECT m.role, GREATEST(m.chat_muted_until, mu.until) AS chat_muted_until
     FROM room_members m LEFT JOIN room_mutes mu ON mu.room_id = m.room_id AND mu.user_id = m.user_id
     WHERE m.room_id = $1 AND m.user_id = $2`, [roomId, userId])).rows[0];
  if (!member) throw fail('Önce odaya girin.', 403);
  return { room, member };
}

router.post('/:roomId/messages', userLimit('chat10s', 8, 10e3), userLimit('chat1m', 40, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const { room, member } = await roomAndMember(roomId, req.user.id);
  if (room.chat_enabled === false && !MANAGERS.includes(member.role)) throw fail('Bu odada sohbet kapalı.', 403);
  if (member.chat_muted_until && new Date(member.chat_muted_until) > new Date()) throw fail('Bu odada sohbette susturuldunuz.', 403);

  const body = cleanLine(req.body?.text, 300);
  if (!body) throw fail('Mesaj boş olamaz.');
  if (looksLikeFlood(body)) throw fail('Mesaj spam olarak algılandı.', 422);
  if (containsBanned(body, banned)) throw fail('Mesajınız topluluk kurallarına aykırı ifadeler içeriyor.', 422);

  const m = (await query(`INSERT INTO room_messages(room_id, user_id, body) VALUES($1,$2,$3) RETURNING id, created_at`, [roomId, req.user.id, body])).rows[0];
  const row = await loadPublicRow(req.user.id);
  const message = { id: m.id, roomId, user: publicUser(row, null), text: body, createdAt: m.created_at };
  hub.broadcastRoom(roomId, { type: 'room_message', ...message });
  noteTask(req.user.id, 'chat');
  res.status(201).json({ message });
});

router.get('/:roomId/messages', async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await roomAndMember(roomId, req.user.id);
  const limit = req.query.limit ? positiveInt(req.query.limit, 'Limit', 100) : 50;
  const r = await query(
    `SELECT m.id AS message_id, m.body, m.created_at AS message_at, ${USER_PUBLIC_COLUMNS}
     FROM room_messages m JOIN users u ON u.id = m.user_id ${USER_PUBLIC_JOINS}
     WHERE m.room_id = $1 AND m.deleted = FALSE ORDER BY m.created_at DESC LIMIT $2`,
    [roomId, limit],
  );
  res.json({
    messages: r.rows.reverse().map((x) => ({ id: x.message_id, roomId, user: publicUser(x, req.user.id), text: x.body, createdAt: x.message_at })),
  });
});

// Sohbeti temizle: yalnızca oda sahibi, yardımcı sahip ve moderatör.
router.delete('/:roomId/messages', userLimit('chat_clear', 10, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const { member } = await roomAndMember(roomId, req.user.id);
  if (!MANAGERS.includes(member.role)) throw fail('Sohbeti yalnızca oda yetkilileri temizleyebilir.', 403);
  const r = await query(`UPDATE room_messages SET deleted = TRUE WHERE room_id = $1 AND deleted = FALSE`, [roomId]);
  hub.broadcastRoom(roomId, { type: 'room_chat_cleared', roomId, by: req.user.id });
  res.json({ ok: true, cleared: r.rowCount });
});

router.delete('/:roomId/messages/:messageId', async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const messageId = uuid(req.params.messageId, 'Mesaj');
  const { member } = await roomAndMember(roomId, req.user.id);
  const msg = (await query(`SELECT user_id FROM room_messages WHERE id = $1 AND room_id = $2 AND deleted = FALSE`, [messageId, roomId])).rows[0];
  if (!msg) throw fail('Mesaj bulunamadı.', 404);
  if (msg.user_id !== req.user.id && !MANAGERS.includes(member.role)) throw fail('Bu mesajı silme yetkiniz yok.', 403);
  await query(`UPDATE room_messages SET deleted = TRUE WHERE id = $1`, [messageId]);
  hub.broadcastRoom(roomId, { type: 'room_message_deleted', roomId, messageId });
  res.json({ ok: true });
});

// Sohbette susturma: 0 = susturmayı kaldır, en fazla 24 saat.
router.post('/:roomId/members/:userId/chat-mute', userLimit('moderate', 60, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  const minutes = Number(req.body?.minutes);
  if (!Number.isInteger(minutes) || minutes < 0 || minutes > 1440) throw fail('Süre 0-1440 dakika arasında olmalı.');
  if (targetId === req.user.id) throw fail('Kendinizi susturamazsınız.');
  const { member } = await roomAndMember(roomId, req.user.id);
  const target = (await query(`SELECT role FROM room_members WHERE room_id = $1 AND user_id = $2`, [roomId, targetId])).rows[0];
  if (!target) throw fail('Kullanıcı odada değil.', 404);
  if (!canManage(member.role, target.role, 'moderate')) throw fail('Bu işlem için yetkiniz yok.', 403);
  if (member.role !== 'owner' && (await featuresFor(targetId)).kickImmunity) throw fail('Bu kullanıcı susturulamaz (WIP ayrıcalığı).', 403);
  await query(
    `UPDATE room_members SET chat_muted_until = CASE WHEN $3::int = 0 THEN NULL ELSE NOW() + ($3::int * INTERVAL '1 minute') END WHERE room_id = $1 AND user_id = $2`,
    [roomId, targetId, minutes],
  );
  if (minutes === 0) await query(`DELETE FROM room_mutes WHERE room_id = $1 AND user_id = $2`, [roomId, targetId]);
  else await query(
    `INSERT INTO room_mutes(room_id, user_id, until) VALUES($1,$2, NOW() + ($3::int * INTERVAL '1 minute'))
     ON CONFLICT (room_id, user_id) DO UPDATE SET until = EXCLUDED.until`, [roomId, targetId, minutes]);
  hub.sendToUser(targetId, { type: 'room_chat_muted', roomId, minutes });
  res.json({ ok: true, minutes });
});
