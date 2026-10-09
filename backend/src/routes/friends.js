import { Router } from 'express';
import { query } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, uuid } from '../http.js';
import { hub } from '../realtime.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';

export const router = Router();
router.use(requireAuth);

/** İki kullanıcı arkadaş mı? (kabul edilmiş istek, iki yönden biri) */
export async function areFriends(a, b, run = query) {
  const r = await run(
    `SELECT 1 FROM friend_requests WHERE status = 'accepted'
       AND ((requester_id = $1 AND target_id = $2) OR (requester_id = $2 AND target_id = $1))`,
    [a, b],
  );
  return r.rowCount > 0;
}

async function ensureUsable(me, other) {
  if (other === me) throw fail('Kendinizi arkadaş ekleyemezsiniz.');
  const u = (await query(`SELECT account_status FROM users WHERE id = $1`, [other])).rows[0];
  if (!u || u.account_status !== 'active') throw fail('Kullanıcı bulunamadı.', 404);
  const b = await query(`SELECT 1 FROM user_blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`, [me, other]);
  if (b.rowCount) throw fail('Bu kullanıcıyı arkadaş ekleyemezsiniz.', 403);
}

// Arkadaş listesi
router.get('/', async (req, res) => {
  const r = await query(
    `SELECT ${USER_PUBLIC_COLUMNS}, fr.responded_at
     FROM friend_requests fr
     JOIN users u ON u.id = CASE WHEN fr.requester_id = $1 THEN fr.target_id ELSE fr.requester_id END ${USER_PUBLIC_JOINS}
     WHERE fr.status = 'accepted' AND (fr.requester_id = $1 OR fr.target_id = $1) AND u.account_status = 'active'
     ORDER BY fr.responded_at DESC NULLS LAST LIMIT 500`,
    [req.user.id],
  );
  res.json({ users: r.rows.map((x) => publicUser(x, req.user.id)) });
});

// Bana gelen bekleyen istekler
router.get('/requests', async (req, res) => {
  const r = await query(
    `SELECT ${USER_PUBLIC_COLUMNS}, fr.created_at AS requested_at
     FROM friend_requests fr JOIN users u ON u.id = fr.requester_id ${USER_PUBLIC_JOINS}
     WHERE fr.target_id = $1 AND fr.status = 'pending' AND u.account_status = 'active'
     ORDER BY fr.created_at DESC LIMIT 100`,
    [req.user.id],
  );
  res.json({ requests: r.rows.map((x) => ({ user: publicUser(x, req.user.id), createdAt: x.requested_at })) });
});

// Arkadaşlık isteği gönder (karşı taraf zaten istek göndermişse otomatik kabul olur)
router.post('/request/:userId', userLimit('friendreq', 40, 3600e3), async (req, res) => {
  const other = uuid(req.params.userId, 'Kullanıcı');
  await ensureUsable(req.user.id, other);
  if (await areFriends(req.user.id, other)) return res.json({ ok: true, status: 'friends' });
  const reverse = await query(`SELECT 1 FROM friend_requests WHERE requester_id = $1 AND target_id = $2 AND status = 'pending'`, [other, req.user.id]);
  if (reverse.rowCount) {
    await query(`UPDATE friend_requests SET status = 'accepted', responded_at = NOW() WHERE requester_id = $1 AND target_id = $2`, [other, req.user.id]);
    hub.sendToUser(other, { type: 'friend_update' });
    return res.json({ ok: true, status: 'friends' });
  }
  await query(
    `INSERT INTO friend_requests(requester_id, target_id) VALUES($1,$2)
     ON CONFLICT (requester_id, target_id) DO NOTHING`,
    [req.user.id, other],
  );
  hub.sendToUser(other, { type: 'friend_update' });
  res.json({ ok: true, status: 'requested' });
});

router.post('/accept/:userId', async (req, res) => {
  const other = uuid(req.params.userId, 'Kullanıcı');
  const r = await query(
    `UPDATE friend_requests SET status = 'accepted', responded_at = NOW()
     WHERE requester_id = $1 AND target_id = $2 AND status = 'pending'`,
    [other, req.user.id],
  );
  if (!r.rowCount) throw fail('Bekleyen istek bulunamadı.', 404);
  hub.sendToUser(other, { type: 'friend_update' });
  res.json({ ok: true, status: 'friends' });
});

router.post('/decline/:userId', async (req, res) => {
  const other = uuid(req.params.userId, 'Kullanıcı');
  await query(`DELETE FROM friend_requests WHERE requester_id = $1 AND target_id = $2 AND status = 'pending'`, [other, req.user.id]);
  res.json({ ok: true, status: 'none' });
});

// Arkadaşlıktan çıkar veya gönderdiğim bekleyen isteği geri çek
router.delete('/:userId', async (req, res) => {
  const other = uuid(req.params.userId, 'Kullanıcı');
  await query(
    `DELETE FROM friend_requests
     WHERE (requester_id = $1 AND target_id = $2) OR (requester_id = $2 AND target_id = $1 AND status = 'accepted')`,
    [req.user.id, other],
  );
  hub.sendToUser(other, { type: 'friend_update' });
  res.json({ ok: true, status: 'none' });
});
