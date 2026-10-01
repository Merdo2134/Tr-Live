import { Router } from 'express';
import { query } from '../database.js';
import { requireAuth } from '../auth.js';
import { oneOf } from '../http.js';
import { periodStartIso } from '../periods.js';
import { loadPublicRows } from '../services/users.js';
import { publicUser } from '../views.js';

export const router = Router();
router.use(requireAuth);

const cache = new Map(); // anahtar -> { at, data }
const TTL_MS = 30_000;

// Kendine gönderilen hediyeler sıralamaya dahil edilmez (kendi kendine puan basmayı önlemek için).
router.get('/', async (req, res) => {
  const type = oneOf(String(req.query.type ?? 'senders'), ['senders', 'receivers', 'families'], 'Tür');
  const period = oneOf(String(req.query.period ?? 'weekly'), ['daily', 'weekly', 'monthly', 'all'], 'Dönem');
  const key = `${type}:${period}`;
  const hit = cache.get(key);
  let rows;
  if (hit && Date.now() - hit.at < TTL_MS) rows = hit.data;
  else {
    const start = periodStartIso(period);
    if (type === 'families') {
      rows = (await query(
        `SELECT f.id, f.name, f.logo_url, f.level, SUM(gt.coin_amount) AS total
         FROM gift_transactions gt JOIN family_members fm ON fm.user_id = gt.receiver_id JOIN families f ON f.id = fm.family_id AND f.is_active = TRUE
         WHERE gt.sender_id <> gt.receiver_id AND ($1::timestamptz IS NULL OR gt.created_at >= $1::timestamptz)
         GROUP BY f.id ORDER BY total DESC LIMIT 50`,
        [start],
      )).rows;
    } else {
      const col = type === 'senders' ? 'sender_id' : 'receiver_id';
      rows = (await query(
        `SELECT gt.${col} AS user_id, SUM(gt.coin_amount) AS total FROM gift_transactions gt
         WHERE gt.sender_id <> gt.receiver_id AND ($1::timestamptz IS NULL OR gt.created_at >= $1::timestamptz)
         GROUP BY gt.${col} ORDER BY total DESC LIMIT 50`,
        [start],
      )).rows;
    }
    cache.set(key, { at: Date.now(), data: rows });
  }

  if (type === 'families') {
    return res.json({ type, period, entries: rows.map((x, i) => ({ rank: i + 1, family: { id: x.id, name: x.name, logoUrl: x.logo_url, level: x.level }, total: String(x.total) })) });
  }
  const users = new Map((await loadPublicRows(rows.map((x) => x.user_id))).map((u) => [u.id, u]));
  res.json({
    type, period,
    entries: rows.filter((x) => users.has(x.user_id)).map((x, i) => ({ rank: i + 1, user: publicUser(users.get(x.user_id), req.user.id), total: String(x.total) })),
  });
});
