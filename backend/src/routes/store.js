import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, uuid } from '../http.js';
import { hub } from '../realtime.js';
import { idempotent } from '../idempotency.js';

export const router = Router();
router.use(requireAuth);

export const STORE_CATEGORIES = ['frame', 'chat_bubble', 'entrance_effect', 'mini_card', 'mic_wave', 'vehicle'];

const view = (x) => ({
  id: x.id, category: x.category, name: x.name, imageUrl: x.image_url, priceCoins: String(x.price_coins), durationDays: x.duration_days,
});

// Yükleme Merkezi paketleri
router.get('/coin-packages', async (_req, res) => {
  const r = await query(`SELECT id, coins, price_cents, currency FROM coin_packages WHERE is_active = TRUE ORDER BY sort_order, coins`);
  res.json({ packages: r.rows.map((x) => ({ id: x.id, coins: String(x.coins), priceCents: String(x.price_cents), currency: x.currency })) });
});

router.get('/items', async (req, res) => {
  const category = req.query.category ? String(req.query.category) : null;
  if (category && !STORE_CATEGORIES.includes(category)) throw fail('Geçersiz kategori.');
  const r = await query(
    `SELECT * FROM store_items WHERE is_active = TRUE AND for_sale = TRUE AND category <> 'badge' AND ($1::text IS NULL OR category = $1)
     ORDER BY sort_order, created_at DESC LIMIT 200`,
    [category],
  );
  res.json({ items: r.rows.map(view) });
});

// Satın al (kendin için) veya "Gönder" (başka bir kullanıcıya hediye). Süre: ürünün gün sayısı; aynı ürün tekrar alınırsa süre uzar.
router.post('/buy', userLimit('store_buy', 30, 3600e3), idempotent('store_buy'), async (req, res) => {
  const itemId = uuid(req.body?.itemId, 'Ürün');
  const toUserId = req.body?.toUserId ? uuid(req.body.toUserId, 'Alıcı') : req.user.id;
  const result = await tx(async (c) => {
    const item = (await c.query(`SELECT * FROM store_items WHERE id = $1 AND is_active = TRUE AND for_sale = TRUE AND category <> 'badge'`, [itemId])).rows[0];
    if (!item) throw fail('Ürün bulunamadı.', 404);
    if (toUserId !== req.user.id) {
      const u = (await c.query(`SELECT account_status FROM users WHERE id = $1`, [toUserId])).rows[0];
      if (!u || u.account_status !== 'active') throw fail('Alıcı bulunamadı.', 404);
      const b = await c.query(`SELECT 1 FROM user_blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`, [req.user.id, toUserId]);
      if (b.rowCount) throw fail('Bu kullanıcıya gönderemezsiniz.', 403);
    }
    const user = (await c.query(`SELECT coins FROM users WHERE id = $1 FOR UPDATE`, [req.user.id])).rows[0];
    const price = BigInt(item.price_coins);
    const before = BigInt(user.coins);
    if (before < price) throw fail('Yetersiz Coin.');
    const after = before - price;
    await c.query(`UPDATE users SET coins = $1, updated_at = NOW() WHERE id = $2`, [after.toString(), req.user.id]);

    // Çerçeve/giriş efektinde envanter anahtarı katalog kimliğidir (mevcut gösterim kodu bunu kullanır); diğerlerinde ürün kimliği + görsel.
    const linked = item.ref_id && (item.category === 'frame' || item.category === 'entrance_effect');
    const key = linked ? String(item.ref_id) : String(item.id);
    const existing = (await c.query(
      `SELECT id FROM inventory_items WHERE user_id = $1 AND item_type = $2 AND item_key = $3 AND is_active = TRUE AND expires_at IS NOT NULL AND expires_at > NOW() LIMIT 1`,
      [toUserId, item.category, key],
    )).rows[0];
    if (existing) {
      await c.query(`UPDATE inventory_items SET expires_at = expires_at + ($2::int * INTERVAL '1 day') WHERE id = $1`, [existing.id, item.duration_days]);
    } else {
      await c.query(
        `INSERT INTO inventory_items(user_id, item_type, item_key, item_name, expires_at, metadata)
         VALUES($1,$2,$3,$4, NOW() + ($5::int * INTERVAL '1 day'), $6)`,
        [toUserId, item.category, key, item.name, item.duration_days, JSON.stringify({ assetUrl: item.image_url, storeItemId: item.id, fromUserId: req.user.id })],
      );
    }
    await c.query(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, reference_id, description) VALUES($1,'store_purchase',$2,$3,$4)`,
      [req.user.id, (-price).toString(), item.id, `${toUserId === req.user.id ? 'Mağaza' : 'Mağaza hediyesi'}: ${item.name}`],
    );
    await c.query(
      `INSERT INTO financial_audit_logs(user_id, action, reference_type, reference_id, amount_coins, balance_before, balance_after, metadata)
       VALUES($1,'store_purchase','store_item',$2,$3,$4,$5,$6)`,
      [req.user.id, item.id, (-price).toString(), before.toString(), after.toString(), JSON.stringify({ toUserId, days: item.duration_days })],
    );
    return { balance: after.toString(), name: item.name };
  });
  if (toUserId !== req.user.id) hub.sendToUser(toUserId, { type: 'friend_update' });
  res.json({ ok: true, balance: result.balance, gifted: toUserId !== req.user.id });
});
