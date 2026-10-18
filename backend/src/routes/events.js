// Haftalık etkinlik sayfaları: banner özeti, sıralama, ödüller, kurallar, geçen haftanın kazananları.
import { Router } from 'express';
import { query } from '../database.js';
import { requireAuth } from '../auth.js';
import { fail } from '../http.js';
import {
  EVENT_KINDS, EVENT_TITLES, isStar, weekBounds, ranking, myRank, decorate, rewardsView, defaultRules,
} from '../services/weekly_events.js';

export const router = Router();
router.use(requireAuth);

const giftJson = (g) => (g ? { id: g.id, name: g.name, iconUrl: g.icon_url, coinPrice: String(g.coin_price) } : null);

async function configs() {
  const r = await query(
    `SELECT c.*, g.name AS g_name, g.icon_url AS g_icon, g.coin_price AS g_price
     FROM weekly_event_config c LEFT JOIN gifts g ON g.id = c.gift_id ORDER BY c.kind`,
  );
  return new Map(r.rows.map((c) => [c.kind, {
    ...c, gift: c.gift_id ? giftJson({ id: c.gift_id, name: c.g_name, icon_url: c.g_icon, coin_price: c.g_price }) : null,
  }]));
}

// Banner'lar ve sayfa başlığı için özet: hangi etkinlik açık, her birinin şimdiki lideri.
router.get('/', async (req, res) => {
  const { start, end } = await weekBounds(0);
  const cfg = await configs();
  const events = [];
  for (const kind of EVENT_KINDS) {
    const c = cfg.get(kind);
    if (!c?.enabled || (isStar(kind) && !c.gift_id)) continue;
    const top = await decorate(await ranking(kind, start, end, { limit: 1, giftId: c.gift_id }), req.user.id);
    events.push({ kind, title: EVENT_TITLES[kind], gift: c.gift, leader: top[0] ?? null });
  }
  res.json({ weekStart: start, weekEnd: end, events });
});

router.get('/:kind', async (req, res) => {
  const kind = String(req.params.kind);
  if (!EVENT_KINDS.includes(kind)) throw fail('Etkinlik bulunamadı.', 404);
  const c = (await configs()).get(kind);
  if (!c) throw fail('Etkinlik bulunamadı.', 404);
  const { start, end } = await weekBounds(0);
  const rows = c.enabled ? await ranking(kind, start, end, { limit: 50, giftId: c.gift_id }) : [];
  const me = c.enabled ? await myRank(kind, start, end, req.user.id, c.gift_id) : null;
  // Geçen haftanın kazananları (dağıtılmışsa).
  const prev = await weekBounds(-1);
  const last = (await query(
    `SELECT rank, user_id, partner_id, score FROM weekly_event_results WHERE week_start = $1 AND kind = $2 ORDER BY rank`,
    [prev.start, kind],
  )).rows;
  res.json({
    kind, title: EVENT_TITLES[kind], enabled: c.enabled, weekStart: start, weekEnd: end, gift: c.gift,
    // Yıldız: puan hediye adedi; diğerleri Coin değeri.
    scoreUnit: isStar(kind) ? 'adet' : 'Coin',
    leaderboard: await decorate(rows, req.user.id),
    me,
    rewards: rewardsView(c.rewards),
    rules: (c.rules ?? '').trim() || defaultRules(kind),
    lastWinners: await decorate(last, req.user.id),
  });
});
