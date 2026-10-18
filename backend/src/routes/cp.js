// İlişkiler (yakınlık): CP (tek), En İyi Arkadaş ('friend') ve Kanka. İki kişi arasındaki yakınlık puanı mesaj ve
// hediyelerle birikir (services/cp.js). İlişki daveti Coin ile gönderilir; karşı taraf 24 saat içinde kabul etmezse,
// reddederse ya da davet geri çekilirse Coin iade edilir. Kabul edilince Coin harcanmış olur.
import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, uuid, oneOf } from '../http.js';
import { hub } from '../realtime.js';
import { cpInfo, cpLevelFor } from '../levels.js';
import { pairOf, CP_MSG_EXP, CP_MSG_DAILY } from '../services/cp.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';
import { loadPublicRow } from '../services/users.js';
import { notifyUser } from '../services/notify.js';

export const router = Router();
router.use(requireAuth);

export const REL_KINDS = ['cp', 'friend', 'kanka'];
export const REL_COST = { cp: 2500n, friend: 1500n, kanka: 1000n };
const REQUEST_TTL_MS = 24 * 3600e3;
const REQUEST_TTL = `INTERVAL '24 hours'`;
const KIND_LABEL = { friend: 'En İyi Arkadaş', cp: 'CP', kanka: 'Kanka' };

async function pairRow(me, other, run = query) {
  const [a, b] = pairOf(me, other);
  return (await run(`SELECT * FROM cp_pairs WHERE user_a = $1 AND user_b = $2`, [a, b])).rows[0] ?? null;
}

function liveRequest(p) {
  if (!p?.request_kind || !p.request_at) return null;
  if (Date.now() - new Date(p.request_at).getTime() > REQUEST_TTL_MS) return null;
  return p;
}

const costs = () => Object.fromEntries(REL_KINDS.map((k) => [k, REL_COST[k].toString()]));

function statusJson(me, p) {
  const info = cpInfo(p?.exp ?? 0);
  const req = liveRequest(p);
  return {
    ...info,
    relation: p?.relation ?? 'none',
    relationSince: p?.relation_since ?? null,
    request: req ? { kind: req.request_kind, fromMe: req.request_from === me, at: req.request_at, cost: String(req.request_cost ?? 0) } : null,
    canChoose: true,
    costs: costs(),
    requestHours: 24,
    rules: { messageExp: CP_MSG_EXP, messagesPerDay: CP_MSG_DAILY, cpGiftMultiplier: 1.5 },
  };
}

async function ensureOther(me, other) {
  if (other === me) throw fail('Kendinizle ilişki kuramazsınız.');
  const u = (await query(`SELECT account_status FROM users WHERE id = $1`, [other])).rows[0];
  if (!u || u.account_status !== 'active') throw fail('Kullanıcı bulunamadı.', 404);
  const b = await query(`SELECT 1 FROM user_blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`, [me, other]);
  if (b.rowCount) throw fail('Bu kullanıcıyla işlem yapılamaz.', 403);
}

/** Bekleyen davetin Coin'ini gönderene iade eder ve daveti temizler. [c] işlem içinden; satır kilitli olmalı. */
async function refundRequest(c, p, reason = 'İlişki daveti iadesi') {
  const cost = BigInt(p.request_cost ?? 0);
  if (cost > 0n && p.request_from) {
    await c.query(`UPDATE users SET coins = coins + $2, updated_at = NOW() WHERE id = $1`, [p.request_from, cost.toString()]);
    await c.query(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, description) VALUES($1,'relation_refund',$2,$3)`,
      [p.request_from, cost.toString(), reason],
    );
  }
  await c.query(
    `UPDATE cp_pairs SET request_kind = NULL, request_from = NULL, request_at = NULL, request_cost = 0, updated_at = NOW()
     WHERE user_a = $1 AND user_b = $2`,
    [p.user_a, p.user_b],
  );
  return cost;
}

// Bana gelen bekleyen ilişki davetleri
router.get('/requests', async (req, res) => {
  const me = req.user.id;
  const r = await query(
    `SELECT ${USER_PUBLIC_COLUMNS}, p.request_kind, p.request_at, p.exp AS pair_exp
     FROM cp_pairs p JOIN users u ON u.id = p.request_from ${USER_PUBLIC_JOINS}
     WHERE (p.user_a = $1 OR p.user_b = $1) AND p.request_kind IS NOT NULL AND p.request_from <> $1
       AND p.request_at > NOW() - ${REQUEST_TTL} AND u.account_status = 'active'
     ORDER BY p.request_at DESC LIMIT 50`,
    [me],
  );
  res.json({
    requests: r.rows.map((x) => ({ user: publicUser(x, me), kind: x.request_kind, createdAt: x.request_at, level: cpLevelFor(x.pair_exp) })),
  });
});

// Bir kişiyle yakınlık durumu
router.get('/with/:userId', async (req, res) => {
  const other = uuid(req.params.userId, 'Kullanıcı');
  if (other === req.user.id) return res.json(statusJson(req.user.id, null));
  res.json(statusJson(req.user.id, await pairRow(req.user.id, other)));
});

// İlişki daveti (Coin ile). Karşı taraf aynı türde davet göndermişse doğrudan kabul edilir (bu durumda Coin alınmaz).
router.post('/with/:userId/request', userLimit('cpreq', 20, 3600e3), async (req, res) => {
  const me = req.user.id;
  const other = uuid(req.params.userId, 'Kullanıcı');
  const kind = oneOf(req.body?.kind, REL_KINDS, 'İlişki');
  await ensureOther(me, other);
  const cost = REL_COST[kind];
  const [a, b] = pairOf(me, other);
  const result = await tx(async (c) => {
    // Kilit sırası: önce kullanıcılar (id sırasıyla), sonra çift.
    const users = (await c.query(`SELECT id, coins, cp_partner_id FROM users WHERE id = ANY($1::uuid[]) ORDER BY id FOR UPDATE`, [[me, other]])).rows;
    await c.query(`INSERT INTO cp_pairs(user_a, user_b) VALUES($1,$2) ON CONFLICT DO NOTHING`, [a, b]);
    const p = (await c.query(`SELECT * FROM cp_pairs WHERE user_a = $1 AND user_b = $2 FOR UPDATE`, [a, b])).rows[0];
    if (p.relation === kind) throw fail(`Zaten ${KIND_LABEL[kind]}sınız.`);
    const pending = liveRequest(p);
    if (pending) {
      if (pending.request_from === other && pending.request_kind === kind) return { acceptNow: true };
      if (pending.request_from === other) throw fail('Bu kişinin sana bekleyen bir daveti var. Önce onu yanıtla.');
      throw fail('Bekleyen bir davetin var. Yeni davet için önce onu geri çek.');
    }
    // Süresi dolmuş eski davet varsa önce iade.
    if (p.request_kind) await refundRequest(c, p, 'Süresi dolan ilişki daveti iadesi');
    if (kind === 'cp') {
      if (users.find((x) => x.id === me)?.cp_partner_id) throw fail('Zaten bir CP\'n var. Önce mevcut CP ilişkini bitir.');
      if (users.find((x) => x.id === other)?.cp_partner_id) throw fail('Bu kişinin zaten bir CP\'si var.');
    }
    const mine = users.find((x) => x.id === me);
    if (BigInt(mine.coins) < cost) throw fail(`${KIND_LABEL[kind]} daveti için ${cost} Coin gerekir.`);
    await c.query(`UPDATE users SET coins = coins - $2, updated_at = NOW() WHERE id = $1`, [me, cost.toString()]);
    await c.query(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, description) VALUES($1,'relation_invite',$2,$3)`,
      [me, (-cost).toString(), `${KIND_LABEL[kind]} daveti`],
    );
    await c.query(
      `UPDATE cp_pairs SET request_kind = $3, request_from = $4, request_at = NOW(), request_cost = $5, updated_at = NOW()
       WHERE user_a = $1 AND user_b = $2`,
      [a, b, kind, me, cost.toString()],
    );
    return { acceptNow: false };
  });
  if (result.acceptNow) return res.json(await accept(me, other, kind));
  const fromRow = await loadPublicRow(me);
  const from = publicUser(fromRow);
  const p = await pairRow(me, other);
  hub.sendToUser(other, { type: 'cp_request', kind, from, level: cpLevelFor(p?.exp ?? 0) });
  const name = fromRow?.is_hidden ? 'Bir kullanıcı' : (fromRow?.display_name || fromRow?.username || 'Bir kullanıcı');
  notifyUser(other, 'relation_request', `💞 ${KIND_LABEL[kind]} daveti`, `${name} seni ${KIND_LABEL[kind]} olarak seçti. 24 saat içinde yanıtla!`, { userId: me });
  res.json(statusJson(me, p));
});

async function accept(me, other, kind) {
  const [a, b] = pairOf(me, other);
  // Kabul CP ise ikisine bekleyen diğer CP davetleri iade edilecek: o davetleri gönderenler de kilit sırasına
  // (kullanıcılar id sırasıyla, sonra çiftler) baştan eklenir; kilitlenme (deadlock) olmasın.
  const extra = (await query(
    `SELECT DISTINCT request_from FROM cp_pairs WHERE request_kind = 'cp' AND request_from IS NOT NULL
       AND (user_a = ANY($1::uuid[]) OR user_b = ANY($1::uuid[]))`,
    [[me, other]],
  )).rows.map((x) => x.request_from);
  const lockIds = [...new Set([me, other, ...extra])];
  await tx(async (c) => {
    const locked = (await c.query(`SELECT id, cp_partner_id FROM users WHERE id = ANY($1::uuid[]) ORDER BY id FOR UPDATE`, [lockIds])).rows;
    const users = locked.filter((u) => u.id === me || u.id === other);
    const lockedSet = new Set(locked.map((u) => u.id));
    const p = (await c.query(`SELECT * FROM cp_pairs WHERE user_a = $1 AND user_b = $2 FOR UPDATE`, [a, b])).rows[0];
    const req = liveRequest(p);
    if (!req || req.request_from !== other || (kind && req.request_kind !== kind)) throw fail('Bekleyen davet bulunamadı.', 404);
    const k = req.request_kind;
    if (k === 'cp') {
      if (users.some((u) => u.cp_partner_id && u.cp_partner_id !== (u.id === me ? other : me))) {
        throw fail('Taraflardan birinin zaten başka bir CP\'si var.');
      }
      await c.query(`UPDATE users SET cp_partner_id = $2 WHERE id = $1`, [me, other]);
      await c.query(`UPDATE users SET cp_partner_id = $2 WHERE id = $1`, [other, me]);
      // İkisine gelen/gönderilen diğer CP davetleri artık geçersiz: Coin'leri iade edilir.
      const others = (await c.query(
        `SELECT * FROM cp_pairs WHERE request_kind = 'cp' AND (user_a = ANY($1::uuid[]) OR user_b = ANY($1::uuid[]))
           AND NOT (user_a = $2 AND user_b = $3) ORDER BY user_a, user_b FOR UPDATE`,
        [[me, other], a, b],
      )).rows;
      // Arada yeni gelen (kilitlenmemiş kişiden) davet varsa dokunulmaz; süresi dolunca ayrıca iade edilir.
      for (const o of others) if (lockedSet.has(o.request_from)) await refundRequest(c, o, 'Geçersiz kalan CP daveti iadesi');
    } else if (p.relation === 'cp') {
      // CP'den başka bir ilişkiye geçiş: CP bağı kalkar.
      await c.query(`UPDATE users SET cp_partner_id = NULL WHERE id = ANY($1::uuid[]) AND cp_partner_id = ANY($1::uuid[])`, [[me, other]]);
    }
    await c.query(
      `UPDATE cp_pairs SET relation = $3, relation_since = NOW(), request_kind = NULL, request_from = NULL, request_at = NULL,
         request_cost = 0, updated_at = NOW()
       WHERE user_a = $1 AND user_b = $2`,
      [a, b, k],
    );
  });
  hub.sendToUser(other, { type: 'cp_update', userId: me });
  return statusJson(me, await pairRow(me, other));
}

router.post('/with/:userId/accept', async (req, res) => {
  const other = uuid(req.params.userId, 'Kullanıcı');
  await ensureOther(req.user.id, other);
  res.json(await accept(req.user.id, other, null));
});

// Gelen daveti reddet ya da gönderdiğim daveti geri çek: Coin gönderene iade edilir.
router.post('/with/:userId/decline', async (req, res) => {
  const me = req.user.id;
  const other = uuid(req.params.userId, 'Kullanıcı');
  const [a, b] = pairOf(me, other);
  await tx(async (c) => {
    await c.query(`SELECT id FROM users WHERE id = ANY($1::uuid[]) ORDER BY id FOR UPDATE`, [[me, other]]);
    const p = (await c.query(`SELECT * FROM cp_pairs WHERE user_a = $1 AND user_b = $2 FOR UPDATE`, [a, b])).rows[0];
    if (p?.request_kind) await refundRequest(c, p, p.request_from === me ? 'Geri çekilen ilişki daveti iadesi' : 'Reddedilen ilişki daveti iadesi');
  });
  hub.sendToUser(other, { type: 'cp_update', userId: me });
  res.json(statusJson(me, await pairRow(me, other)));
});

// İlişkiyi bitir (yakınlık puanı korunur)
router.post('/with/:userId/end', async (req, res) => {
  const me = req.user.id;
  const other = uuid(req.params.userId, 'Kullanıcı');
  const [a, b] = pairOf(me, other);
  await tx(async (c) => {
    await c.query(`SELECT id FROM users WHERE id = ANY($1::uuid[]) ORDER BY id FOR UPDATE`, [[me, other]]);
    const p = (await c.query(`SELECT relation FROM cp_pairs WHERE user_a = $1 AND user_b = $2 FOR UPDATE`, [a, b])).rows[0];
    if (!p || p.relation === 'none') throw fail('Aranızda bir ilişki yok.');
    if (p.relation === 'cp') {
      await c.query(`UPDATE users SET cp_partner_id = NULL WHERE (id = $1 AND cp_partner_id = $2) OR (id = $2 AND cp_partner_id = $1)`, [me, other]);
    }
    await c.query(
      `UPDATE cp_pairs SET relation = 'none', relation_since = NULL, updated_at = NOW() WHERE user_a = $1 AND user_b = $2`,
      [a, b],
    );
  });
  hub.sendToUser(other, { type: 'cp_update', userId: me });
  res.json(statusJson(me, await pairRow(me, other)));
});

// ---------- İlişki Duvarı ----------
async function relationList(userId, viewerId, kind, limit) {
  const r = await query(
    `SELECT ${USER_PUBLIC_COLUMNS}, p.exp AS pair_exp, p.relation_since
     FROM cp_pairs p JOIN users u ON u.id = CASE WHEN p.user_a = $1 THEN p.user_b ELSE p.user_a END ${USER_PUBLIC_JOINS}
     WHERE (p.user_a = $1 OR p.user_b = $1) AND p.relation = $2 AND u.account_status = 'active'
     ORDER BY p.exp DESC, p.relation_since ASC LIMIT $3`,
    [userId, kind, limit],
  );
  return r.rows.map((x) => ({
    user: publicUser(x, viewerId),
    level: cpLevelFor(x.pair_exp),
    exp: String(x.pair_exp),
    since: x.relation_since,
    days: x.relation_since ? Math.max(1, Math.ceil((Date.now() - new Date(x.relation_since).getTime()) / 86400e3)) : 0,
  }));
}

async function relationCount(userId, kind) {
  const r = await query(
    `SELECT COUNT(*)::int AS n FROM cp_pairs p
     JOIN users u ON u.id = CASE WHEN p.user_a = $1 THEN p.user_b ELSE p.user_a END AND u.account_status = 'active'
     WHERE (p.user_a = $1 OR p.user_b = $1) AND p.relation = $2`,
    [userId, kind],
  );
  return r.rows[0].n;
}

router.get('/wall/:userId', async (req, res) => {
  const owner = uuid(req.params.userId, 'Kullanıcı');
  const me = req.user.id;
  const ownerRow = await loadPublicRow(owner);
  if (!ownerRow) throw fail('Kullanıcı bulunamadı.', 404);
  // Gizli kullanıcının ilişkileri başkalarına gösterilmez.
  if (ownerRow.is_hidden && owner !== me) {
    return res.json({ owner: publicUser(ownerRow, me), cp: null, friend: { count: 0, items: [] }, kanka: { count: 0, items: [] }, costs: costs() });
  }
  const [cp, friend, kanka, nf, nk] = await Promise.all([
    relationList(owner, me, 'cp', 1),
    relationList(owner, me, 'friend', 3),
    relationList(owner, me, 'kanka', 3),
    relationCount(owner, 'friend'),
    relationCount(owner, 'kanka'),
  ]);
  res.json({
    owner: publicUser(ownerRow, me),
    cp: cp[0] ?? null,
    friend: { count: nf, items: friend },
    kanka: { count: nk, items: kanka },
    costs: costs(),
  });
});

router.get('/wall/:userId/:kind', async (req, res) => {
  const owner = uuid(req.params.userId, 'Kullanıcı');
  const kind = oneOf(req.params.kind, REL_KINDS, 'İlişki');
  if (owner !== req.user.id) {
    const h = (await query(`SELECT is_hidden FROM users WHERE id = $1`, [owner])).rows[0];
    if (!h || h.is_hidden) return res.json({ items: [] });
  }
  res.json({ items: await relationList(owner, req.user.id, kind, 200) });
});

// ---------- Süresi dolan davetler: Coin iadesi ----------
export async function refundExpiredRequests() {
  const rows = (await query(
    `SELECT user_a, user_b FROM cp_pairs WHERE request_kind IS NOT NULL AND request_at <= NOW() - ${REQUEST_TTL} LIMIT 200`,
  )).rows;
  let n = 0;
  for (const r of rows) {
    await tx(async (c) => {
      await c.query(`SELECT id FROM users WHERE id = ANY($1::uuid[]) ORDER BY id FOR UPDATE`, [[r.user_a, r.user_b]]);
      const p = (await c.query(
        `SELECT * FROM cp_pairs WHERE user_a = $1 AND user_b = $2 AND request_kind IS NOT NULL AND request_at <= NOW() - ${REQUEST_TTL} FOR UPDATE`,
        [r.user_a, r.user_b],
      )).rows[0];
      if (!p) return;
      const cost = await refundRequest(c, p, 'Süresi dolan ilişki daveti iadesi');
      if (cost > 0n) n += 1;
    }).catch((e) => console.error('[ilişki] iade:', e.message));
  }
  return n;
}

export function startRelationRefundTicker() {
  const run = () => refundExpiredRequests().then((n) => { if (n) console.log(`[ilişki] ${n} davet iade edildi`); })
    .catch((e) => console.error('[ilişki] iade:', e.message));
  setTimeout(run, 20e3).unref();
  const t = setInterval(run, 5 * 60e3);
  t.unref();
  return t;
}
