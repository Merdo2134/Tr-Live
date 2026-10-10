import { Router } from 'express';
import crypto from 'node:crypto';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { fail, uuid } from '../http.js';
import { userLimit } from '../firewall.js';
import { hub } from '../realtime.js';
import { cleanLine } from '../text_safety.js';
import { screenText } from '../services/moderation.js';
import { loadPublicRow } from '../services/users.js';
import { publicUser } from '../views.js';
import { BAG_TIERS } from '../services/rewards_config.js';
import { noteTask, dailyState } from '../services/daily.js';
import { idempotent } from '../idempotency.js';

export const router = Router();
router.use(requireAuth);

/** Toplamı rastgele paylara böler; her pay en az toplamın (ortalamanın %20'si) kadardır. */
export function splitBag(total, slots) {
  const min = Math.max(1, Math.floor((total / slots) * 0.2));
  const rest = total - min * slots;
  const w = Array.from({ length: slots }, () => crypto.randomInt(1, 1000));
  const sum = w.reduce((a, b) => a + b, 0);
  const out = w.map((x) => min + Math.floor((rest * x) / sum));
  out[0] += total - out.reduce((a, b) => a + b, 0);
  return out;
}

async function bagJson(b, viewerId, c = { query }) {
  const sender = await loadPublicRow(b.sender_id);
  const mine = (await c.query(`SELECT amount FROM lucky_bag_claims WHERE bag_id = $1 AND user_id = $2`, [b.id, viewerId])).rows[0];
  return {
    id: b.id, roomId: b.room_id, kind: b.kind, tier: b.tier, totalCoins: String(b.total_coins), slots: b.slots, claimed: b.claimed_count,
    status: b.status, note: b.kind === 'super' ? b.note : null, expiresAt: b.expires_at, opensAt: b.opens_at ?? b.created_at, sender: publicUser(sender, null),
    mine: mine ? String(mine.amount) : null,
  };
}

router.get('/lucky-bags/config', (req, res) => {
  res.json({ tiers: Object.entries(BAG_TIERS).map(([id, t]) => ({ id, kind: t.kind, totalCoins: t.total, slots: t.slots, countdown: t.countdown, window: t.window })) });
});

router.get('/rooms/:roomId/lucky-bags', async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const m = await query(`SELECT 1 FROM room_members WHERE room_id = $1 AND user_id = $2`, [roomId, req.user.id]);
  if (!m.rowCount) throw fail('Önce odaya girin.', 403);
  const r = await query(`SELECT * FROM lucky_bags WHERE room_id = $1 AND status = 'open' AND expires_at > NOW() ORDER BY created_at`, [roomId]);
  const bags = [];
  for (const b of r.rows) bags.push(await bagJson(b, req.user.id));
  res.json({ bags });
});

router.post('/rooms/:roomId/lucky-bags', userLimit('lucky_send', 6, 10 * 60e3), idempotent('lucky_bag_send'), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const tierKey = String(req.body?.tier ?? '');
  const tier = Object.hasOwn(BAG_TIERS, tierKey) ? BAG_TIERS[tierKey] : null;
  if (!tier) throw fail('Geçersiz çanta türü.');
  let note = null;
  if (tier.kind === 'super') {
    note = cleanLine(req.body?.note, 100);
    if (!note || note.length < 2) throw fail('Süper çanta için bir not yazın (en az 2 karakter).');
    await screenText(req.user, note, 'bag_note');
  }
  const userId = req.user.id;
  const out = await tx(async (c) => {
    const room = (await c.query(`SELECT id, name, is_hidden FROM rooms WHERE id = $1 AND is_active = TRUE`, [roomId])).rows[0];
    if (!room) throw fail('Oda bulunamadı.', 404);
    if (!(await c.query(`SELECT 1 FROM room_members WHERE room_id = $1 AND user_id = $2`, [roomId, userId])).rowCount) throw fail('Önce odaya girin.', 403);
    const u = (await c.query(`SELECT coins FROM users WHERE id = $1 FOR UPDATE`, [userId])).rows[0];
    if (BigInt(u.coins) < BigInt(tier.total)) throw fail('Yeterli Coin yok.', 409);
    const open = (await c.query(`SELECT 1 FROM lucky_bags WHERE sender_id = $1 AND status = 'open' AND expires_at > NOW()`, [userId])).rowCount;
    if (open) throw fail('Açık bir çantanız zaten var; süresi dolunca yenisini gönderebilirsiniz.', 409);
    await c.query(`UPDATE users SET coins = coins - $2, updated_at = NOW() WHERE id = $1`, [userId, String(tier.total)]);
    const bag = (await c.query(
      `INSERT INTO lucky_bags(room_id, sender_id, kind, tier, total_coins, slots, amounts, note, opens_at, expires_at)
       VALUES($1,$2,$3,$4,$5,$6,$7,$8, NOW() + make_interval(secs => $9::int), NOW() + make_interval(secs => $10::int)) RETURNING *`,
      [roomId, userId, tier.kind, req.body.tier, String(tier.total), tier.slots, splitBag(tier.total, tier.slots).map(String), note, tier.countdown, tier.countdown + tier.window],
    )).rows[0];
    await c.query(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, reference_id, description) VALUES($1,'lucky_bag_sent',$2,$3,$4)`,
      [userId, String(-tier.total), bag.id, `${tier.kind === 'super' ? 'Süper ' : ''}Şanslı çanta (${tier.slots} kişilik)`],
    );
    return { bag, roomName: room.name, hidden: room.is_hidden === true };
  });
  const json = await bagJson(out.bag, userId);
  hub.broadcastRoom(roomId, { type: 'lucky_bag_new', roomId, bag: { ...json, mine: null } });
  if (out.bag.kind === 'super' && !out.hidden) {
    hub.broadcastGlobal({ type: 'lucky_bag_global', roomId, roomName: out.roomName, sender: json.sender, totalCoins: json.totalCoins, slots: json.slots, bagId: json.id });
  }
  res.status(201).json({ bag: json });
});

router.post('/lucky-bags/:id/claim', userLimit('lucky_claim', 30, 60e3), async (req, res) => {
  const id = uuid(req.params.id, 'Çanta');
  const userId = req.user.id;
  const result = await tx(async (c) => {
    const b = (await c.query(`SELECT * FROM lucky_bags WHERE id = $1 FOR UPDATE`, [id])).rows[0];
    if (!b) throw fail('Çanta bulunamadı.', 404);
    if (b.status !== 'open' || new Date(b.expires_at) <= new Date()) throw fail('Bu çantanın süresi doldu.', 410);
    if (b.claimed_count >= b.slots) throw fail('Çanta tükendi.', 410);
    if (b.sender_id === userId) throw fail('Kendi çantanızı açamazsınız.', 403);
    if (b.opens_at && new Date(b.opens_at) > new Date()) throw fail('Geri sayım bitince açılır.', 425);
    if (!(await c.query(`SELECT 1 FROM room_members WHERE room_id = $1 AND user_id = $2`, [b.room_id, userId])).rowCount) throw fail('Çantayı açmak için odada olmalısınız.', 403);
    if ((await c.query(`SELECT 1 FROM lucky_bag_claims WHERE bag_id = $1 AND user_id = $2`, [id, userId])).rowCount) throw fail('Bu çantayı zaten açtınız.', 409);
    if (b.kind === 'super') {
      const said = await c.query(
        `SELECT 1 FROM room_messages WHERE room_id = $1 AND user_id = $2 AND body = $3 AND deleted = FALSE AND created_at >= $4 LIMIT 1`,
        [b.room_id, userId, b.note, b.created_at],
      );
      if (!said.rowCount) throw fail(`Önce sohbete şu notu yazın: "${b.note}"`, 403);
    }
    const amount = BigInt(b.amounts[b.claimed_count]);
    const claimed = b.claimed_count + 1;
    await c.query(`INSERT INTO lucky_bag_claims(bag_id, user_id, amount) VALUES($1,$2,$3)`, [id, userId, amount.toString()]);
    await c.query(`UPDATE lucky_bags SET claimed_count = $2, status = $3 WHERE id = $1`, [id, claimed, claimed >= b.slots ? 'done' : 'open']);
    await c.query(`UPDATE users SET coins = coins + $2, updated_at = NOW() WHERE id = $1`, [userId, amount.toString()]);
    await c.query(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, reference_id, description) VALUES($1,'lucky_bag_received',$2,$3,'Şanslı çanta')`,
      [userId, amount.toString(), id],
    );
    return { amount, claimed, slots: b.slots, roomId: b.room_id, done: claimed >= b.slots };
  });
  hub.broadcastRoom(result.roomId, { type: 'lucky_bag_claimed', roomId: result.roomId, bagId: id, claimed: result.claimed, slots: result.slots, done: result.done });
  res.json({ ok: true, amount: result.amount.toString(), claimed: result.claimed, slots: result.slots });
});

/** Süresi dolan çantalarda dağıtılmayan Coin gönderene iade edilir. */
export async function expireBags() {
  const due = (await query(`SELECT id FROM lucky_bags WHERE status = 'open' AND expires_at <= NOW() LIMIT 50`)).rows;
  for (const { id } of due) {
    try {
      const info = await tx(async (c) => {
        const b = (await c.query(`SELECT * FROM lucky_bags WHERE id = $1 AND status = 'open' FOR UPDATE SKIP LOCKED`, [id])).rows[0];
        if (!b) return null;
        const left = b.amounts.slice(b.claimed_count).reduce((a, x) => a + BigInt(x), 0n);
        await c.query(`UPDATE lucky_bags SET status = 'expired' WHERE id = $1`, [id]);
        if (left > 0n) {
          await c.query(`UPDATE users SET coins = coins + $2, updated_at = NOW() WHERE id = $1`, [b.sender_id, left.toString()]);
          await c.query(
            `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, reference_id, description) VALUES($1,'lucky_bag_refund',$2,$3,'Şanslı çanta iadesi')`,
            [b.sender_id, left.toString(), id],
          );
        }
        return { roomId: b.room_id };
      });
      if (info) hub.broadcastRoom(info.roomId, { type: 'lucky_bag_ended', roomId: info.roomId, bagId: id });
    } catch (error) {
      console.error('Çanta iadesi hatası:', error.message);
    }
  }
}

export function startBagTicker() {
  const t = setInterval(() => expireBags().catch((e) => console.error('Çanta zamanlayıcı:', e.message)), 10000);
  t.unref();
  return t;
}

// Günlük görevler
router.get('/me/daily', async (req, res) => {
  res.json(await dailyState(req.user.id));
});

export { noteTask };
