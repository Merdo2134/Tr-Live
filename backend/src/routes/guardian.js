// Koruyucu uç noktaları. Kurallar ve haftalık düşüş: services/guardian.js
import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, uuid } from '../http.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';
import { loadPublicRow } from '../services/users.js';
import { notifyUser } from '../services/notify.js';
import { GUARDIAN_COST, GUARDIAN_LIST_LIMIT } from '../services/guardian.js';

export const router = Router();
router.use(requireAuth);

const RULES = {
  cost: GUARDIAN_COST.toString(),
  pointPerCoin: 1,
  decayHighThreshold: 250,
  decayHighPercent: 20,
  decayLowPoints: 50,
};

async function guardiansOf(ownerId, viewerId, limit = GUARDIAN_LIST_LIMIT) {
  const r = await query(
    `SELECT ${USER_PUBLIC_COLUMNS}, g.points, g.created_at AS since
     FROM guardians g JOIN users u ON u.id = g.guardian_id ${USER_PUBLIC_JOINS}
     WHERE g.owner_id = $1 AND u.account_status = 'active'
     ORDER BY g.points DESC, g.created_at ASC LIMIT $2`,
    [ownerId, limit],
  );
  return r.rows.map((x, i) => ({ rank: i + 1, user: publicUser(x, viewerId), points: String(x.points), since: x.since }));
}

async function guardingOf(guardianId, viewerId) {
  const r = await query(
    `SELECT ${USER_PUBLIC_COLUMNS}, g.points, g.created_at AS since
     FROM guardians g JOIN users u ON u.id = g.owner_id ${USER_PUBLIC_JOINS}
     WHERE g.guardian_id = $1 AND u.account_status = 'active'
     ORDER BY g.points DESC LIMIT $2`,
    [guardianId, GUARDIAN_LIST_LIMIT],
  );
  return r.rows.map((x) => ({ user: publicUser(x, viewerId), points: String(x.points), since: x.since }));
}

/** Profilde gösterilen koruyucu: sahibin seçtiği (hâlâ koruyucuysa), yoksa en yüksek puanlı. */
function shownOf(list, shownId) {
  return list.find((g) => g.user.id === shownId) ?? list[0] ?? null;
}

// Bir kişinin koruyucuları (sıralama) ve benim durumum
router.get('/of/:userId', async (req, res) => {
  const owner = uuid(req.params.userId, 'Kullanıcı');
  const me = req.user.id;
  const ownerRow = await loadPublicRow(owner);
  if (!ownerRow) throw fail('Kullanıcı bulunamadı.', 404);
  const st = (await query(`SELECT guardian_enabled, guardian_shown_id FROM users WHERE id = $1`, [owner])).rows[0];
  // Gizli kullanıcının koruyucuları başkalarına gösterilmez ve kimse koruyucusu olamaz.
  const hiddenForMe = Boolean(ownerRow.is_hidden) && owner !== me;
  const enabled = st?.guardian_enabled !== false && !hiddenForMe;
  // Koruyucu kapalıysa sıralama başkalarına gösterilmez (kişi kendisi görür).
  const list = (enabled || owner === me) && !hiddenForMe ? await guardiansOf(owner, me) : [];
  const mine = (await query(`SELECT points FROM guardians WHERE owner_id = $1 AND guardian_id = $2`, [owner, me])).rows[0];
  res.json({
    owner: publicUser(ownerRow, me),
    enabled,
    isSelf: owner === me,
    top: shownOf(list, st?.guardian_shown_id),
    guardians: list,
    myPoints: mine ? String(mine.points) : null,
    rules: RULES,
  });
});

// Koruyucu ol (Coin ile)
router.post('/of/:userId/join', userLimit('guardjoin', 20, 3600e3), async (req, res) => {
  const owner = uuid(req.params.userId, 'Kullanıcı');
  const me = req.user.id;
  if (owner === me) throw fail('Kendinizin koruyucusu olamazsınız.');
  const blocked = await query(
    `SELECT 1 FROM user_blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`,
    [me, owner],
  );
  if (blocked.rowCount) throw fail('Bu kullanıcıyla işlem yapılamaz.', 403);
  const coins = await tx(async (c) => {
    const users = (await c.query(
      `SELECT id, coins, account_status, guardian_enabled, is_hidden FROM users WHERE id = ANY($1::uuid[]) ORDER BY id FOR UPDATE`,
      [[me, owner]],
    )).rows;
    const o = users.find((u) => u.id === owner);
    const m = users.find((u) => u.id === me);
    if (!o || o.account_status !== 'active') throw fail('Kullanıcı bulunamadı.', 404);
    if (o.guardian_enabled === false || o.is_hidden) throw fail('Bu kullanıcı koruyucu kabul etmiyor.');
    const exists = await c.query(`SELECT 1 FROM guardians WHERE owner_id = $1 AND guardian_id = $2`, [owner, me]);
    if (exists.rowCount) throw fail('Zaten bu kişinin koruyucususunuz.');
    if (BigInt(m.coins) < GUARDIAN_COST) throw fail(`Koruyucu olmak için ${GUARDIAN_COST} Coin gerekir.`);
    const left = (await c.query(
      `UPDATE users SET coins = coins - $2, updated_at = NOW() WHERE id = $1 RETURNING coins`,
      [me, GUARDIAN_COST.toString()],
    )).rows[0].coins;
    await c.query(`INSERT INTO guardians(owner_id, guardian_id) VALUES($1,$2)`, [owner, me]);
    await c.query(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, description) VALUES($1,'guardian_card',$2,'Koruyucu kartı')`,
      [me, (-GUARDIAN_COST).toString()],
    );
    return String(left);
  });
  const meRow = await loadPublicRow(me);
  const name = meRow?.is_hidden ? 'Bir kullanıcı' : (meRow?.display_name || meRow?.username || 'Bir kullanıcı');
  notifyUser(owner, 'guardian', '🛡️ Yeni koruyucu', `${name} artık senin koruyucun!`, { userId: me });
  res.json({ ok: true, coins });
});

// Koruyuculuğumu bitir
router.post('/of/:userId/leave', async (req, res) => {
  const owner = uuid(req.params.userId, 'Kullanıcı');
  const r = await query(`DELETE FROM guardians WHERE owner_id = $1 AND guardian_id = $2`, [owner, req.user.id]);
  if (!r.rowCount) throw fail('Bu kişinin koruyucusu değilsiniz.', 404);
  res.json({ ok: true });
});

// Profil sahibi bir koruyucusunu çıkarır
router.post('/remove/:guardianId', async (req, res) => {
  const g = uuid(req.params.guardianId, 'Koruyucu');
  const r = await query(`DELETE FROM guardians WHERE owner_id = $1 AND guardian_id = $2`, [req.user.id, g]);
  if (!r.rowCount) throw fail('Bu kişi koruyucunuz değil.', 404);
  res.json({ ok: true });
});

// Koruyuculuğum: koruyucularım ve koruduklarım
router.get('/mine', async (req, res) => {
  const me = req.user.id;
  const [guardians, guarding, s] = await Promise.all([
    guardiansOf(me, me),
    guardingOf(me, me),
    query(`SELECT guardian_enabled, guardian_shown_id FROM users WHERE id = $1`, [me]),
  ]);
  const shown = shownOf(guardians, s.rows[0]?.guardian_shown_id);
  res.json({ guardians, guarding, shownId: shown?.user.id ?? null, top: shown, enabled: s.rows[0]?.guardian_enabled !== false, rules: RULES });
});

// Profilde gösterilecek koruyucuyu seç (profil sahibi)
router.post('/show/:guardianId', async (req, res) => {
  const g = uuid(req.params.guardianId, 'Koruyucu');
  const r = await query(`SELECT 1 FROM guardians WHERE owner_id = $1 AND guardian_id = $2`, [req.user.id, g]);
  if (!r.rowCount) throw fail('Bu kişi koruyucunuz değil.', 404);
  await query(`UPDATE users SET guardian_shown_id = $2, updated_at = NOW() WHERE id = $1`, [req.user.id, g]);
  res.json({ ok: true, shownId: g });
});

// Koruyucu açık / kapalı
router.put('/settings', async (req, res) => {
  if (typeof req.body?.enabled !== 'boolean') throw fail('Ayar geçersiz.');
  await query(`UPDATE users SET guardian_enabled = $2, updated_at = NOW() WHERE id = $1`, [req.user.id, req.body.enabled]);
  res.json({ enabled: req.body.enabled });
});
