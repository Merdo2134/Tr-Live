import { Router } from 'express';
import { query } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, uuid } from '../http.js';
import { loadProfile } from '../services/profile.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';

export const router = Router();
router.use(requireAuth);

const like = (q) => `%${q.toLowerCase().replace(/[\\%_]/g, (m) => `\\${m}`)}%`;
const paging = (req) => ({ limit: Math.min(Math.max(Number(req.query.limit) || 30, 1), 100), offset: Math.max(Number(req.query.offset) || 0, 0) });

// Gizli kullanıcılar aramada çıkmaz.
router.get('/search', async (req, res) => {
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

router.get('/:userId', async (req, res) => {
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  const profile = await loadProfile(req.user.id, targetId);
  if (!profile) throw fail('Kullanıcı bulunamadı.', 404);
  if (targetId !== req.user.id && !profile.isHidden) {
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
