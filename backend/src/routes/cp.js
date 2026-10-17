import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, uuid, oneOf } from '../http.js';
import { hub } from '../realtime.js';
import { cpInfo, cpLevelFor, CP_CHOOSE_LEVEL } from '../levels.js';
import { pairOf, CP_MSG_EXP, CP_MSG_DAILY } from '../services/cp.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';
import { loadPublicRow } from '../services/users.js';

export const router = Router();
router.use(requireAuth);

const REQUEST_TTL = `INTERVAL '7 days'`;
const KIND_LABEL = { friend: 'Arkadaş', cp: 'CP' };

async function pairRow(me, other, run = query) {
  const [a, b] = pairOf(me, other);
  return (await run(`SELECT * FROM cp_pairs WHERE user_a = $1 AND user_b = $2`, [a, b])).rows[0] ?? null;
}

function liveRequest(p) {
  if (!p?.request_kind || !p.request_at) return null;
  if (Date.now() - new Date(p.request_at).getTime() > 7 * 24 * 3600e3) return null;
  return p;
}

function statusJson(me, p) {
  const info = cpInfo(p?.exp ?? 0);
  const req = liveRequest(p);
  return {
    ...info,
    relation: p?.relation ?? 'none',
    relationSince: p?.relation_since ?? null,
    request: req ? { kind: req.request_kind, fromMe: req.request_from === me, at: req.request_at } : null,
    canChoose: info.level >= CP_CHOOSE_LEVEL,
    chooseLevel: CP_CHOOSE_LEVEL,
    rules: { messageExp: CP_MSG_EXP, messagesPerDay: CP_MSG_DAILY, cpGiftMultiplier: 1.5 },
  };
}

async function ensureOther(me, other) {
  if (other === me) throw fail('Kendinizle CP olamazsınız.');
  const u = (await query(`SELECT account_status FROM users WHERE id = $1`, [other])).rows[0];
  if (!u || u.account_status !== 'active') throw fail('Kullanıcı bulunamadı.', 404);
  const b = await query(`SELECT 1 FROM user_blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`, [me, other]);
  if (b.rowCount) throw fail('Bu kullanıcıyla işlem yapılamaz.', 403);
}

// Bana gelen bekleyen ilişki istekleri (Arkadaş / CP)
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

// İlişki isteği: 3. kademeden itibaren Arkadaş ya da CP. Karşı taraf aynı isteği göndermişse doğrudan kabul edilir.
router.post('/with/:userId/request', userLimit('cpreq', 20, 3600e3), async (req, res) => {
  const me = req.user.id;
  const other = uuid(req.params.userId, 'Kullanıcı');
  const kind = oneOf(req.body?.kind, ['friend', 'cp'], 'İlişki');
  await ensureOther(me, other);
  const p = await pairRow(me, other);
  const level = cpLevelFor(p?.exp ?? 0);
  if (level < CP_CHOOSE_LEVEL) throw fail(`İlişki seçmek için yakınlık seviyesi ${CP_CHOOSE_LEVEL} olmalı.`);
  if (p.relation === kind) throw fail(`Zaten ${KIND_LABEL[kind]}sınız.`);
  const pending = liveRequest(p);
  if (pending && pending.request_from === other && pending.request_kind === kind) {
    const out = await accept(me, other, kind);
    return res.json(out);
  }
  if (kind === 'cp') {
    const taken = (await query(`SELECT id, cp_partner_id FROM users WHERE id = ANY($1::uuid[])`, [[me, other]])).rows;
    if (taken.find((x) => x.id === me)?.cp_partner_id) throw fail('Zaten bir CP\'n var. Önce mevcut CP ilişkini bitir.');
    if (taken.find((x) => x.id === other)?.cp_partner_id) throw fail('Bu kişinin zaten bir CP\'si var.');
  }
  const [a, b] = pairOf(me, other);
  await query(
    `UPDATE cp_pairs SET request_kind = $3, request_from = $4, request_at = NOW(), updated_at = NOW() WHERE user_a = $1 AND user_b = $2`,
    [a, b, kind, me],
  );
  const from = publicUser(await loadPublicRow(me));
  hub.sendToUser(other, { type: 'cp_request', kind, from, level });
  res.json(statusJson(me, await pairRow(me, other)));
});

async function accept(me, other, kind) {
  const [a, b] = pairOf(me, other);
  await tx(async (c) => {
    // Kilit sırası hediye gönderimiyle aynı: önce kullanıcılar (id sırasıyla), sonra çift (kilitlenme olmasın).
    const users = (await c.query(`SELECT id, cp_partner_id FROM users WHERE id = ANY($1::uuid[]) ORDER BY id FOR UPDATE`, [[me, other]])).rows;
    const p = (await c.query(`SELECT * FROM cp_pairs WHERE user_a = $1 AND user_b = $2 FOR UPDATE`, [a, b])).rows[0];
    const req = liveRequest(p);
    if (!req || req.request_from !== other || (kind && req.request_kind !== kind)) throw fail('Bekleyen istek bulunamadı.', 404);
    const k = req.request_kind;
    if (k === 'cp') {
      if (users.some((u) => u.cp_partner_id && u.cp_partner_id !== (u.id === me ? other : me))) {
        throw fail('Taraflardan birinin zaten başka bir CP\'si var.');
      }
      await c.query(`UPDATE users SET cp_partner_id = $2 WHERE id = $1`, [me, other]);
      await c.query(`UPDATE users SET cp_partner_id = $2 WHERE id = $1`, [other, me]);
      // İkisine gelen/gönderilen diğer CP istekleri artık geçersiz.
      await c.query(
        `UPDATE cp_pairs SET request_kind = NULL, request_from = NULL, request_at = NULL
         WHERE request_kind = 'cp' AND (user_a = ANY($1::uuid[]) OR user_b = ANY($1::uuid[])) AND NOT (user_a = $2 AND user_b = $3)`,
        [[me, other], a, b],
      );
    } else if (p.relation === 'cp') {
      // CP'den arkadaşlığa geçiş: CP bağı kalkar.
      await c.query(`UPDATE users SET cp_partner_id = NULL WHERE id = ANY($1::uuid[]) AND cp_partner_id = ANY($1::uuid[])`, [[me, other]]);
    }
    await c.query(
      `UPDATE cp_pairs SET relation = $3, relation_since = NOW(), request_kind = NULL, request_from = NULL, request_at = NULL, updated_at = NOW()
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

// Gelen isteği reddet ya da gönderdiğim isteği geri çek
router.post('/with/:userId/decline', async (req, res) => {
  const me = req.user.id;
  const other = uuid(req.params.userId, 'Kullanıcı');
  const [a, b] = pairOf(me, other);
  await query(
    `UPDATE cp_pairs SET request_kind = NULL, request_from = NULL, request_at = NULL, updated_at = NOW() WHERE user_a = $1 AND user_b = $2`,
    [a, b],
  );
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
      `UPDATE cp_pairs SET relation = 'none', relation_since = NULL, request_kind = NULL, request_from = NULL, request_at = NULL, updated_at = NOW()
       WHERE user_a = $1 AND user_b = $2`,
      [a, b],
    );
  });
  hub.sendToUser(other, { type: 'cp_update', userId: me });
  res.json(statusJson(me, await pairRow(me, other)));
});
