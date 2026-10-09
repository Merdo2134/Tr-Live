import { Router } from 'express';
import express from 'express';
import { query } from '../database.js';
import { requireAuth, optionalAuth } from '../auth.js';
import { fail, uuid } from '../http.js';
import { userLimit } from '../firewall.js';
import { config } from '../config.js';
import { cleanMultiline, containsBanned, looksLikeFlood } from '../text_safety.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';
import { saveUpload, removeUpload, IMAGE_TYPES } from '../services/images.js';

export const router = Router();
const banned = config.bannedWords.map((w) => w.toLocaleLowerCase('tr'));
const PAGE = 20;

function checkText(value, max) {
  const body = cleanMultiline(value, max);
  if (body && looksLikeFlood(body)) throw fail('Metin spam olarak algılandı.', 422);
  if (body && containsBanned(body, banned)) throw fail('Metin topluluk kurallarına aykırı ifadeler içeriyor.', 422);
  return body;
}

const postJson = (x, viewerId) => ({
  id: x.post_id, text: x.body, imageUrl: x.image_url, likeCount: x.like_count, commentCount: x.comment_count,
  liked: Boolean(x.liked), createdAt: x.post_created_at, mine: x.owner_id === viewerId,
  user: publicUser(x, viewerId), following: Boolean(x.following),
});

// Kullanıcı sütunlarındaki "id" gönderi kimliğiyle karışmasın diye gönderi alanları takma adla alınır.
const POST_SELECT = `p.id AS post_id, p.body, p.image_url, p.like_count, p.comment_count, p.created_at AS post_created_at, p.user_id AS owner_id,
  EXISTS (SELECT 1 FROM post_likes l WHERE l.post_id = p.id AND l.user_id = $1::uuid) AS liked,
  EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = $1::uuid AND f.followed_id = p.user_id) AS following,
  ${USER_PUBLIC_COLUMNS}`;
const NOT_BLOCKED = `NOT EXISTS (SELECT 1 FROM user_blocks b WHERE (b.blocker_id = $1::uuid AND b.blocked_id = p.user_id) OR (b.blocker_id = p.user_id AND b.blocked_id = $1::uuid))`;

// ---------- Banner'lar ----------
router.get('/banners', async (_req, res) => {
  const r = await query(`SELECT id, image_url, title, link_url FROM banners WHERE is_active = TRUE ORDER BY sort_order, created_at DESC LIMIT 10`);
  res.json({ banners: r.rows.map((b) => ({ id: b.id, imageUrl: b.image_url, title: b.title, linkUrl: b.link_url })) });
});

// ---------- Duyurular (Mesajlar ekranındaki kartlar) ----------
router.get('/announcements', requireAuth, async (req, res) => {
  const kind = ['team', 'event', 'reward'].includes(req.query.kind) ? req.query.kind : null;
  const r = await query(
    `SELECT id, kind, title, body, created_at FROM announcements WHERE ($1::text IS NULL OR kind = $1) ORDER BY created_at DESC LIMIT 50`,
    [kind],
  );
  res.json({ announcements: r.rows.map((a) => ({ id: a.id, kind: a.kind, title: a.title, text: a.body, createdAt: a.created_at })) });
});

// Kart rozetleri: okunmamış duyuru sayıları ve yeni takipçiler.
router.get('/inbox-summary', requireAuth, async (req, res) => {
  const r = await query(
    `SELECT
       (SELECT COUNT(*)::int FROM announcements a WHERE a.kind = 'team' AND a.created_at > u.announcements_seen_at) AS team,
       (SELECT COUNT(*)::int FROM announcements a WHERE a.kind = 'event' AND a.created_at > u.announcements_seen_at) AS event,
       (SELECT COUNT(*)::int FROM announcements a WHERE a.kind = 'reward' AND a.created_at > u.announcements_seen_at) AS reward,
       (SELECT COUNT(*)::int FROM follows f WHERE f.followed_id = u.id AND f.created_at > u.announcements_seen_at) AS followers
     FROM users u WHERE u.id = $1`,
    [req.user.id],
  );
  res.json(r.rows[0] ?? { team: 0, event: 0, reward: 0, followers: 0 });
});

router.post('/inbox-summary/seen', requireAuth, async (req, res) => {
  await query(`UPDATE users SET announcements_seen_at = NOW() WHERE id = $1`, [req.user.id]);
  res.json({ ok: true });
});

// ---------- Gönderi akışı ----------
router.get('/posts', optionalAuth, async (req, res) => {
  const scope = req.query.scope === 'following' ? 'following' : 'all';
  if (scope === 'following' && !req.user) throw fail('Takip ettiklerinizi görmek için giriş yapın.', 401);
  const author = req.query.userId ? uuid(req.query.userId, 'Kullanıcı') : null;
  const before = req.query.before ? new Date(String(req.query.before)) : null;
  if (before && Number.isNaN(before.getTime())) throw fail('Geçersiz tarih.');
  const r = await query(
    `SELECT ${POST_SELECT}
     FROM posts p JOIN users u ON u.id = p.user_id ${USER_PUBLIC_JOINS}
     WHERE p.is_removed = FALSE AND u.account_status = 'active'
       AND ($2::timestamptz IS NULL OR p.created_at < $2)
       AND ($3::uuid IS NULL OR p.user_id = $3)
       AND ($4::text <> 'following' OR p.user_id = $1::uuid OR EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = $1::uuid AND f.followed_id = p.user_id))
       AND ($1::uuid IS NULL OR ${NOT_BLOCKED})
     ORDER BY p.created_at DESC LIMIT ${PAGE + 1}`,
    [req.user?.id ?? null, before, author, scope],
  );
  const rows = r.rows.slice(0, PAGE);
  res.json({ posts: rows.map((x) => postJson(x, req.user?.id ?? null)), hasMore: r.rows.length > PAGE });
});

router.put('/posts/image', requireAuth, userLimit('post_image', 20, 3600e3), express.raw({ type: Object.keys(IMAGE_TYPES), limit: '3mb' }), async (req, res) => {
  res.json({ url: await saveUpload(req) });
});

router.post('/posts', requireAuth, userLimit('post_create', 20, 3600e3), async (req, res) => {
  const body = checkText(req.body?.text, 1000);
  let imageUrl = null;
  if (req.body?.imageUrl !== undefined && req.body.imageUrl !== null) {
    imageUrl = String(req.body.imageUrl);
    if (!/^\/uploads\/[0-9a-f-]{36}\.(png|jpg|webp)$/.test(imageUrl)) throw fail('Görsel adresi geçersiz.');
    const own = await query(`SELECT 1 FROM upload_owners WHERE url = $1 AND owner_id = $2`, [imageUrl, req.user.id]);
    if (!own.rowCount) throw fail('Yalnızca kendi yüklediğin görseli paylaşabilirsin.', 403);
  }
  if (!body && !imageUrl) throw fail('Gönderi boş olamaz.');
  const r = await query(`INSERT INTO posts(user_id, body, image_url) VALUES($1,$2,$3) RETURNING id`, [req.user.id, body, imageUrl]);
  const row = (await query(
    `SELECT ${POST_SELECT} FROM posts p JOIN users u ON u.id = p.user_id ${USER_PUBLIC_JOINS} WHERE p.id = $2`,
    [req.user.id, r.rows[0].id],
  )).rows[0];
  res.status(201).json({ post: postJson(row, req.user.id) });
});

router.delete('/posts/:id', requireAuth, async (req, res) => {
  const id = uuid(req.params.id);
  const post = (await query(`SELECT user_id, image_url FROM posts WHERE id = $1 AND is_removed = FALSE`, [id])).rows[0];
  if (!post) throw fail('Gönderi bulunamadı.', 404);
  // Yardımcı admin (support) yetkileri staff_logic ile sınırlı; gönderi silme yalnızca yönetici ve sahibine açık.
  if (post.user_id !== req.user.id && req.user.system_role !== 'admin') throw fail('Bu gönderiyi silemezsiniz.', 403);
  await query(`UPDATE posts SET is_removed = TRUE WHERE id = $1`, [id]);
  // Dosya yalnızca gönderi sahibinin yüklediği ve başka hiçbir gönderide kullanılmayan görselse silinir.
  if (post.image_url) {
    const own = await query(
      `SELECT 1 FROM upload_owners uo WHERE uo.url = $1 AND uo.owner_id = $2
         AND NOT EXISTS (SELECT 1 FROM posts p WHERE p.image_url = $1 AND p.id <> $3 AND p.is_removed = FALSE)`,
      [post.image_url, post.user_id, id]);
    if (own.rowCount) await removeUpload(post.image_url);
  }
  res.json({ ok: true });
});

async function setLike(req, res, like) {
  const id = uuid(req.params.id);
  const post = (await query(`SELECT 1 FROM posts WHERE id = $1 AND is_removed = FALSE`, [id])).rowCount;
  if (!post) throw fail('Gönderi bulunamadı.', 404);
  const q = like
    ? `INSERT INTO post_likes(post_id, user_id) VALUES($1,$2) ON CONFLICT DO NOTHING`
    : `DELETE FROM post_likes WHERE post_id = $1 AND user_id = $2`;
  const changed = (await query(q, [id, req.user.id])).rowCount;
  if (changed) await query(`UPDATE posts SET like_count = GREATEST(0, like_count + $2) WHERE id = $1`, [id, like ? 1 : -1]);
  const n = (await query(`SELECT like_count FROM posts WHERE id = $1`, [id])).rows[0].like_count;
  res.json({ liked: like, likeCount: n });
}
router.post('/posts/:id/like', requireAuth, userLimit('post_like', 300, 3600e3), (req, res) => setLike(req, res, true));
router.delete('/posts/:id/like', requireAuth, (req, res) => setLike(req, res, false));

router.get('/posts/:id/comments', optionalAuth, async (req, res) => {
  const id = uuid(req.params.id);
  const r = await query(
    `SELECT c.id AS comment_id, c.body, c.created_at AS comment_created_at, ${USER_PUBLIC_COLUMNS}
     FROM post_comments c JOIN users u ON u.id = c.user_id ${USER_PUBLIC_JOINS}
     WHERE c.post_id = $1 AND u.account_status = 'active' ORDER BY c.created_at ASC LIMIT 200`,
    [id],
  );
  res.json({ comments: r.rows.map((c) => ({ id: c.comment_id, text: c.body, createdAt: c.comment_created_at, user: publicUser(c, req.user?.id ?? null) })) });
});

router.post('/posts/:id/comments', requireAuth, userLimit('post_comment', 60, 3600e3), async (req, res) => {
  const id = uuid(req.params.id);
  const body = checkText(req.body?.text, 300);
  if (!body) throw fail('Yorum boş olamaz.');
  const post = (await query(`SELECT 1 FROM posts WHERE id = $1 AND is_removed = FALSE`, [id])).rowCount;
  if (!post) throw fail('Gönderi bulunamadı.', 404);
  const c = (await query(`INSERT INTO post_comments(post_id, user_id, body) VALUES($1,$2,$3) RETURNING id, created_at`, [id, req.user.id, body])).rows[0];
  await query(`UPDATE posts SET comment_count = comment_count + 1 WHERE id = $1`, [id]);
  res.status(201).json({ comment: { id: c.id, text: body, createdAt: c.created_at } });
});
