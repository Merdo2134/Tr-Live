import { Router } from 'express';
import { query } from '../database.js';
import { requireAuth } from '../auth.js';
import { fail, uuid, positiveInt } from '../http.js';
import { userLimit } from '../firewall.js';
import { hub } from '../realtime.js';
import { config } from '../config.js';
import { cleanMultiline, containsBanned, looksLikeFlood } from '../text_safety.js';
import { areFriends } from './friends.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';

export const router = Router();
router.use(requireAuth);

const banned = config.bannedWords.map((w) => w.toLocaleLowerCase('tr'));
const msgJson = (m) => ({ id: m.id, senderId: m.sender_id, receiverId: m.receiver_id, text: m.body, createdAt: m.created_at, readAt: m.read_at });

router.get('/unread-count', async (req, res) => {
  const r = await query(`SELECT COUNT(*)::int AS n FROM direct_messages WHERE receiver_id = $1 AND read_at IS NULL`, [req.user.id]);
  res.json({ unread: r.rows[0].n });
});

router.get('/conversations', async (req, res) => {
  const r = await query(
    `WITH mine AS (
       SELECT CASE WHEN sender_id = $1 THEN receiver_id ELSE sender_id END AS peer,
              id AS message_id, body, created_at AS message_at, sender_id
       FROM direct_messages WHERE sender_id = $1 OR receiver_id = $1
     ), latest AS (
       SELECT DISTINCT ON (peer) peer, message_id, body, message_at, sender_id FROM mine ORDER BY peer, message_at DESC
     )
     SELECT l.message_id, l.body, l.message_at, l.sender_id,
            (SELECT COUNT(*)::int FROM direct_messages d WHERE d.sender_id = l.peer AND d.receiver_id = $1 AND d.read_at IS NULL) AS unread,
            ${USER_PUBLIC_COLUMNS}
     FROM latest l JOIN users u ON u.id = l.peer ${USER_PUBLIC_JOINS}
     WHERE u.account_status = 'active' AND NOT EXISTS (
       SELECT 1 FROM user_blocks b WHERE (b.blocker_id = $1 AND b.blocked_id = l.peer) OR (b.blocker_id = l.peer AND b.blocked_id = $1))
     ORDER BY l.message_at DESC LIMIT 50`,
    [req.user.id],
  );
  res.json({
    conversations: r.rows.map((x) => ({
      peer: publicUser(x, req.user.id), lastMessage: x.body, lastMessageAt: x.message_at, lastFromMe: x.sender_id === req.user.id, unread: x.unread,
    })),
  });
});

// Konuşma geçmişi (en yeni 50, eskiden yeniye). Karşı tarafın mesajları okundu işaretlenir.
router.get('/with/:userId', async (req, res) => {
  const peerId = uuid(req.params.userId, 'Kullanıcı');
  const limit = req.query.limit ? positiveInt(req.query.limit, 'Limit', 100) : 50;
  const r = await query(
    `SELECT * FROM direct_messages WHERE (sender_id = $1 AND receiver_id = $2) OR (sender_id = $2 AND receiver_id = $1)
     ORDER BY created_at DESC LIMIT $3`,
    [req.user.id, peerId, limit],
  );
  await query(`UPDATE direct_messages SET read_at = NOW() WHERE receiver_id = $1 AND sender_id = $2 AND read_at IS NULL`, [req.user.id, peerId]);
  res.json({ messages: r.rows.reverse().map(msgJson) });
});

router.post('/with/:userId', userLimit('dm10s', 6, 10e3), userLimit('dm1h', 200, 3600e3), async (req, res) => {
  const peerId = uuid(req.params.userId, 'Kullanıcı');
  if (peerId === req.user.id) throw fail('Kendinize mesaj gönderemezsiniz.');
  const body = cleanMultiline(req.body?.text, 1000);
  if (!body) throw fail('Mesaj boş olamaz.');
  if (looksLikeFlood(body)) throw fail('Mesaj spam olarak algılandı.', 422);
  if (containsBanned(body, banned)) throw fail('Mesajınız topluluk kurallarına aykırı ifadeler içeriyor.', 422);

  const peer = (await query(`SELECT who_can_dm, account_status FROM users WHERE id = $1`, [peerId])).rows[0];
  if (!peer || peer.account_status !== 'active') throw fail('Kullanıcı bulunamadı.', 404);
  const blocked = await query(
    `SELECT 1 FROM user_blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`, [req.user.id, peerId],
  );
  // Engelleme durumu karşı tarafa belli edilmez: genel bir ret mesajı döner.
  if (blocked.rowCount) throw fail('Bu kullanıcıya mesaj gönderemezsiniz.', 403);
  if (peer.who_can_dm === 'nobody') throw fail('Bu kullanıcı özel mesaj almıyor.', 403);
  // Yalnızca arkadaş olan kişiler mesajlaşabilir.
  if (!(await areFriends(req.user.id, peerId))) throw fail('Mesajlaşmak için önce arkadaş olmalısınız.', 403);
  const m = (await query(`INSERT INTO direct_messages(sender_id, receiver_id, body) VALUES($1,$2,$3) RETURNING *`, [req.user.id, peerId, body])).rows[0];
  const message = msgJson(m);
  hub.sendToUser(peerId, { type: 'dm', message });
  res.status(201).json({ message });
});
