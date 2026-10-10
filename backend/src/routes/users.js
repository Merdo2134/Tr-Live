import { Router } from 'express';
import { query } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, uuid } from '../http.js';
import { loadProfile } from '../services/profile.js';
import { loadPublicRows } from '../services/users.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';
import { featuresFor } from '../services/wip.js';
import { isGhost } from '../services/presence.js';

export const router = Router();
router.use(requireAuth);

const like = (q) => `%${q.toLowerCase().replace(/[\\%_]/g, (m) => `\\${m}`)}%`;
const paging = (req) => ({ limit: Math.min(Math.max(Number(req.query.limit) || 30, 1), 100), offset: Math.max(Number(req.query.offset) || 0, 0) });

// Gizli kullanıcılar aramada çıkmaz.
router.get('/search', userLimit('user_search', 60, 60e3), async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  if (q.length < 2) throw fail('Arama için en az 2 karakter girin.');
  const r = await query(
    `SELECT ${USER_PUBLIC_COLUMNS} FROM users u ${USER_PUBLIC_JOINS}
     WHERE u.account_status = 'active' AND u.is_hidden = FALSE AND u.id <> $3
       AND (lower(u.username) LIKE $1 ESCAPE '\\' OR lower(u.display_name) LIKE $1 ESCAPE '\\')
       AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE (b.blocker_id = $3 AND b.blocked_id = u.id) OR (b.blocker_id = u.id AND b.blocked_id = $3))
     ORDER BY (lower(u.username) = $2) DESC, u.username LIMIT 20`,
    [like(q), q.toLowerCase(), req.user.id],
  );
  res.json({ users: r.rows.map((x) => publicUser(x, req.user.id)) });
});

// Oda içi profil kartı: "Yakın Arkadaşlarım" (bu kişiye en çok hediye gönderen 5 kişi) ve "Madalyalar" (rozetler).
router.get('/:userId/card', async (req, res) => {
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  const t = (await query(`SELECT id, is_hidden FROM users WHERE id = $1 AND account_status <> 'deleted'`, [targetId])).rows[0];
  if (!t) throw fail('Kullanıcı bulunamadı.', 404);
  if (t.is_hidden && targetId !== req.user.id) return res.json({ supporters: [], medals: [], gifts: [] });
  const sup = await query(
    `SELECT sender_id, SUM(coin_amount)::text AS coins FROM gift_transactions
     WHERE receiver_id = $1 AND sender_id <> $1 GROUP BY sender_id ORDER BY SUM(coin_amount) DESC LIMIT 5`,
    [targetId],
  );
  const users = new Map((await loadPublicRows(sup.rows.map((x) => x.sender_id))).map((u) => [u.id, u]));
  const medals = await query(
    `SELECT item_name, metadata->>'assetUrl' AS asset_url FROM inventory_items
     WHERE user_id = $1 AND item_type = 'badge' AND is_active = TRUE AND (expires_at IS NULL OR expires_at > NOW())
     ORDER BY created_at DESC LIMIT 12`,
    [targetId],
  );
  // Başarılar: en çok alınan hediyeler (adet).
  const gifts = await query(
    `SELECT g.name, g.icon_url, SUM(t.quantity)::text AS qty FROM gift_transactions t JOIN gifts g ON g.id = t.gift_id
     WHERE t.receiver_id = $1 GROUP BY g.id, g.name, g.icon_url ORDER BY SUM(t.quantity) DESC LIMIT 24`,
    [targetId],
  );
  res.json({
    gifts: gifts.rows.map((g) => ({ name: g.name, iconUrl: g.icon_url, quantity: g.qty })),
    supporters: sup.rows.filter((x) => users.has(x.sender_id)).map((x) => ({ user: publicUser(users.get(x.sender_id), req.user.id), coins: x.coins })),
    medals: medals.rows.map((m) => ({ name: m.item_name, assetUrl: m.asset_url })),
  });
});

router.get('/:userId', async (req, res) => {
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  const profile = await loadProfile(req.user.id, targetId);
  if (!profile) throw fail('Kullanıcı bulunamadı.', 404);
  // "Gizli ziyaret" (WIP ayrıcalığı) olan kişi ziyaretçi listesine düşmez.
  if (targetId !== req.user.id && !profile.isHidden && !(await featuresFor(req.user.id)).invisibleVisit && !(await isGhost(req.user.id))) {
    // Ziyaret kaydı; gizli kullanıcı ziyaretçi listesinde "Gizli Kullanıcı" görünür.
    await query(
      `INSERT INTO profile_visitors(profile_user_id, visitor_id) VALUES($1,$2)
       ON CONFLICT (profile_user_id, visitor_id) DO UPDATE SET visit_count = profile_visitors.visit_count + 1, last_visited_at = NOW()`,
      [targetId, req.user.id],
    );
  }
  res.json({ profile });
});

router.post('/:userId/follow', userLimit('follow', 60, 3600e3), async (req, res) => {
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  if (targetId === req.user.id) throw fail('Kendinizi takip edemezsiniz.');
  const t = (await query(`SELECT is_hidden, account_status FROM users WHERE id = $1`, [targetId])).rows[0];
  if (!t || t.account_status !== 'active') throw fail('Kullanıcı bulunamadı.', 404);
  if (t.is_hidden) throw fail('Gizli kullanıcı takip edilemez.', 403);
  const blocked = await query(`SELECT 1 FROM user_blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`, [req.user.id, targetId]);
  if (blocked.rowCount) throw fail('Bu kullanıcıyı takip edemezsiniz.', 403);
  await query(`INSERT INTO follows(follower_id, followed_id) VALUES($1,$2) ON CONFLICT (follower_id, followed_id) DO NOTHING`, [req.user.id, targetId]);
  res.json({ ok: true, isFollowing: true });
});

router.delete('/:userId/follow', async (req, res) => {
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  await query(`DELETE FROM follows WHERE follower_id = $1 AND followed_id = $2`, [req.user.id, targetId]);
  res.json({ ok: true, isFollowing: false });
});

async function followList(req, res, column, otherColumn) {
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  const { limit, offset } = paging(req);
  const r = await query(
    `SELECT ${USER_PUBLIC_COLUMNS} FROM follows f JOIN users u ON u.id = f.${otherColumn} ${USER_PUBLIC_JOINS}
     WHERE f.${column} = $1 AND u.account_status = 'active' ORDER BY f.created_at DESC LIMIT $2 OFFSET $3`,
    [targetId, limit, offset],
  );
  res.json({ users: r.rows.map((x) => publicUser(x, req.user.id)) });
}
router.get('/:userId/followers', (req, res) => followList(req, res, 'followed_id', 'follower_id'));
router.get('/:userId/following', (req, res) => followList(req, res, 'follower_id', 'followed_id'));
