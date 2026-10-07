import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, bigAmount, text, uuid } from '../http.js';
import { dealerSell } from '../services/dealers.js';

export const router = Router();
router.use(requireAuth);

async function myDealer(userId) {
  const d = (await query(`SELECT * FROM dealer_accounts WHERE owner_user_id = $1 AND is_active = TRUE`, [userId])).rows[0];
  if (!d) throw fail('Bayi hesabınız bulunmuyor.', 403);
  return d;
}

router.get('/me', async (req, res) => {
  const d = await myDealer(req.user.id);
  const tr = (await query(
    `SELECT t.id, t.type, t.coin_amount, t.description, t.created_at, u.username
     FROM dealer_transactions t LEFT JOIN users u ON u.id = t.user_id WHERE t.dealer_id = $1 ORDER BY t.created_at DESC LIMIT 50`,
    [d.id],
  )).rows;
  res.json({
    dealer: { id: d.id, name: d.name, coinBalance: String(d.coin_balance) },
    transactions: tr.map((t) => ({ id: t.id, type: t.type, coinAmount: String(t.coin_amount), description: t.description, username: t.username, createdAt: t.created_at })),
  });
});

// Bayi kendi bakiyesinden kullanıcıya Coin satar. Alıcı kullanıcı adı veya kimlik ile bulunur.
router.post('/sell', userLimit('dealer_sell', 60, 3600e3), async (req, res) => {
  const d = await myDealer(req.user.id);
  const coins = bigAmount(req.body?.amount, 'Satış Coin miktarı');
  let userId;
  if (req.body?.userId) userId = uuid(req.body.userId, 'Kullanıcı');
  else {
    const username = String(req.body?.username ?? '').trim().toLowerCase();
    const u = (await query(`SELECT id FROM users WHERE lower(username) = $1`, [username])).rows[0];
    if (!u) throw fail('Kullanıcı bulunamadı.', 404);
    userId = u.id;
  }
  if (userId === req.user.id) throw fail('Kendinize Coin satamazsınız.');
  const result = await tx((c) => dealerSell(c, {
    dealerId: d.id, userId, coins, actorId: req.user.id, description: text(req.body?.description, 'Açıklama', { max: 200 }),
  }));
  res.json(result);
});
