import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, uuid } from '../http.js';
import { activeWip, BASE_FEATURES } from '../services/wip.js';
import { idempotent } from '../idempotency.js';
import { ghostNow, refreshGhost } from '../services/ghost.js';

export const router = Router();
router.use(requireAuth);

// Kademeler ve satın alınabilir paketler.
router.get('/tiers', async (req, res) => {
  const tiers = (await query(`SELECT level, name, features FROM wip_tiers ORDER BY level`)).rows;
  const plans = (await query(`SELECT id, name, level, duration_days, price_coins FROM wip_plans WHERE is_active = TRUE ORDER BY level, duration_days`)).rows;
  res.json({
    base: BASE_FEATURES,
    tiers: tiers.map((t) => ({
      level: t.level, name: t.name, features: { ...BASE_FEATURES, ...t.features },
      plans: plans.filter((p) => p.level === t.level).map((p) => ({
        id: p.id, name: p.name, durationDays: p.duration_days, priceCoins: String(p.price_coins),
      })),
    })),
  });
});

router.get('/', async (req, res) => {
  res.json({ wip: await activeWip(req.user.id) });
});

// Satın alma kuralları: aynı seviye = süre uzatır, yüksek seviye = yükseltir (kalan süre yeni paketle değişir),
// düşük seviye aktifken satın alınamaz.
router.post('/purchase', userLimit('wip_buy', 10, 3600e3), idempotent('wip_purchase'), async (req, res) => {
  const planId = uuid(req.body?.planId, 'Paket');
  const wasGhost = await ghostNow(req.user.id);
  const result = await tx(async (c) => {
    const user = (await c.query(`SELECT coins FROM users WHERE id = $1 FOR UPDATE`, [req.user.id])).rows[0];
    const plan = (await c.query(`SELECT * FROM wip_plans WHERE id = $1 AND is_active = TRUE`, [planId])).rows[0];
    if (!plan) throw fail('WIP paketi bulunamadı.', 404);
    const current = (await c.query(`SELECT level FROM user_wip WHERE user_id = $1 AND is_active = TRUE AND expires_at > NOW()`, [req.user.id])).rows[0];
    if (current && current.level > plan.level) throw fail('Daha yüksek seviyeli WIP aktifken düşük seviye satın alınamaz.', 409);

    const price = BigInt(plan.price_coins);
    const before = BigInt(user.coins);
    if (before < price) throw fail('Yetersiz Coin.');
    const after = before - price;
    await c.query(`UPDATE users SET coins = $1, updated_at = NOW() WHERE id = $2`, [after.toString(), req.user.id]);

    const wip = (await c.query(
      `INSERT INTO user_wip(user_id, level, starts_at, expires_at, is_active)
       VALUES($1, $2, NOW(), NOW() + ($3::int * INTERVAL '1 day'), TRUE)
       ON CONFLICT (user_id) DO UPDATE SET
         starts_at  = CASE WHEN user_wip.is_active AND user_wip.expires_at > NOW() AND user_wip.level = EXCLUDED.level
                           THEN user_wip.starts_at ELSE EXCLUDED.starts_at END,
         expires_at = CASE WHEN user_wip.is_active AND user_wip.expires_at > NOW() AND user_wip.level = EXCLUDED.level
                           THEN user_wip.expires_at + ($3::int * INTERVAL '1 day') ELSE EXCLUDED.expires_at END,
         level = EXCLUDED.level, is_active = TRUE
       RETURNING level, starts_at, expires_at`,
      [req.user.id, plan.level, plan.duration_days],
    )).rows[0];

    await c.query(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, reference_id, description) VALUES($1,'wip_purchase',$2,$3,$4)`,
      [req.user.id, (-price).toString(), plan.id, `WIP satın alma: ${plan.name}`],
    );
    await c.query(
      `INSERT INTO financial_audit_logs(user_id, action, reference_type, reference_id, amount_coins, balance_before, balance_after, metadata)
       VALUES($1,'wip_purchase','wip_plan',$2,$3,$4,$5,$6)`,
      [req.user.id, plan.id, (-price).toString(), before.toString(), after.toString(), JSON.stringify({ level: plan.level, days: plan.duration_days })],
    );
    return { wip, balance: after.toString() };
  });
  await refreshGhost(req.user.id, wasGhost); // SWIP'e geçişte önceki hayalet tercihi yeniden etkinleşebilir
  res.json({ wip: await activeWip(req.user.id), balance: result.balance });
});
