// Aile (Figma tasarımı): Demir → Elmas seviyeleri, başvuru ile katılım (yönetici onaylar), zenginlik seviyesi sınırı,
// haftalık katkı, haftalık Coins ödülü (aile başkanı alır) ve başkan indirimi. Katkı hesapları: services/family.js
import express from 'express';
import { cleanPublic } from '../safe_text.js';
import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, uuid, text, httpsUrl, oneOf } from '../http.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';
import {
  familyCapacity, familyAdminLimit, familyTier, familyNextPoints, FAMILY_LEVEL_STEPS, FAMILY_TIERS, FAMILY_CAPACITY, FAMILY_ADMINS,
  FAMILY_CASHBACK_BPS, FAMILY_WEEK_REWARDS, FAMILY_CASHBACK_MIN_SPEND,
} from '../levels.js';
import { WEEK_DATE } from '../services/family.js';
import { IMAGE_TYPES, saveUpload, removeUpload } from '../services/images.js';
import { hub } from '../realtime.js';
import { notifyUser } from '../services/notify.js';

export const router = Router();
router.use(requireAuth);

const RANK = { owner: 3, admin: 2, member: 1 };
const NAME_MAX = 12;
const NOTICE_MAX = 100;

const familyJson = (f, extra = {}) => ({
  id: f.id, publicId: f.public_id ?? null, name: f.name, logoUrl: f.logo_url, description: f.description ?? '', ownerId: f.owner_id,
  level: f.level, tier: familyTier(f.level), totalPoints: String(f.total_points), nextPoints: familyNextPoints(f.level).toString(),
  memberCount: f.member_count, capacity: familyCapacity(f.level), adminLimit: familyAdminLimit(f.level),
  joinMinLevel: f.join_min_level ?? 0, ...extra,
});

const FAMILY_SELECT = `SELECT f.*, (SELECT COUNT(*)::int FROM family_members fm WHERE fm.family_id = f.id) AS member_count FROM families f`;

async function activeFamily(id, run = query) {
  const f = (await run(`${FAMILY_SELECT} WHERE f.id = $1 AND f.is_active = TRUE`, [id])).rows[0];
  if (!f) throw fail('Aile bulunamadı.', 404);
  return f;
}

async function myRole(familyId, userId, run = query) {
  return (await run(`SELECT role FROM family_members WHERE family_id = $1 AND user_id = $2`, [familyId, userId])).rows[0]?.role ?? null;
}

async function requireRole(familyId, userId, min) {
  const role = await myRole(familyId, userId);
  if (!role || RANK[role] < RANK[min]) throw fail('Bu işlem için yetkiniz yok.', 403);
  return role;
}

async function newPublicId(run) {
  for (let i = 0; i < 20; i++) {
    const id = String(10000000 + Math.floor(Math.random() * 89999999));
    const used = await run(`SELECT 1 FROM families WHERE public_id = $1`, [id]);
    if (!used.rowCount) return id;
  }
  throw fail('Aile kimliği oluşturulamadı, tekrar deneyin.', 503);
}

// Kurallar ve seviye tablosu (Aile kuralları / seviye sayfaları)
router.get('/rules', (req, res) => {
  res.json({
    tiers: FAMILY_TIERS.map((name, i) => ({
      level: i + 1, name, capacity: FAMILY_CAPACITY[i], admins: FAMILY_ADMINS[i],
      minPoints: i === 0 ? '0' : FAMILY_LEVEL_STEPS[i - 1].toString(), cashbackBps: FAMILY_CASHBACK_BPS[i],
    })),
    tasks: [
      { key: 'login', name: 'Oturum Aç', value: 'Günlük kişi başına 20' },
      { key: 'topup', name: 'Yükleme yap', value: '1 Coin = 1' },
      { key: 'gift_sent', name: 'Hediye gönder', value: '1 Coin = 1' },
      { key: 'gift_received', name: 'Hediye yükle', value: '1 Elmas = 1' },
    ],
    weekRewards: FAMILY_WEEK_REWARDS.map(([need, coins], i) => ({ tier: i + 1, need: need.toString(), coins: coins.toString() })),
    cashbackMinSpend: FAMILY_CASHBACK_MIN_SPEND.toString(),
  });
});

router.get('/', async (req, res) => {
  const q = String(req.query.q ?? '').trim().toLowerCase();
  const r = await query(
    `${FAMILY_SELECT} WHERE f.is_active = TRUE AND ($1 = '' OR lower(f.name) LIKE $2 ESCAPE '\\' OR f.public_id = $1)
     ORDER BY f.total_points DESC, f.created_at LIMIT 100`,
    [q, `%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`],
  );
  res.json({ families: r.rows.map((f) => familyJson(f)) });
});

router.get('/mine', async (req, res) => {
  const m = (await query(
    `SELECT fm.family_id, fm.role FROM family_members fm JOIN families f ON f.id = fm.family_id AND f.is_active = TRUE WHERE fm.user_id = $1`,
    [req.user.id],
  )).rows[0];
  if (!m) {
    const req0 = (await query(`SELECT family_id FROM family_join_requests WHERE user_id = $1`, [req.user.id])).rows.map((x) => x.family_id);
    return res.json({ family: null, requested: req0 });
  }
  res.json({ family: familyJson(await activeFamily(m.family_id), { myRole: m.role }) });
});

/** Aile sayfası: bilgiler, üye önizlemesi, aile odaları, bekleyen başvuru sayısı. */
router.get('/:familyId', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const me = req.user.id;
  const f = await activeFamily(id);
  const role = await myRole(id, me);
  const [members, rooms, pending, requested, admins] = await Promise.all([
    query(
      `SELECT fm.role, ${USER_PUBLIC_COLUMNS} FROM family_members fm JOIN users u ON u.id = fm.user_id ${USER_PUBLIC_JOINS}
       WHERE fm.family_id = $1 AND u.account_status = 'active'
       ORDER BY CASE fm.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END, fm.total_contrib DESC, fm.joined_at LIMIT 12`,
      [id],
    ),
    // Aile odaları: üyelerin açık (gizli olmayan) odaları, en kalabalık önce.
    query(
      `SELECT r.id, r.name, r.cover_url, r.tags, r.room_type, r.owner_id, u.avatar_url AS owner_avatar,
              (SELECT COUNT(*)::int FROM room_members rm WHERE rm.room_id = r.id) AS online
       FROM rooms r JOIN family_members fm ON fm.user_id = r.owner_id AND fm.family_id = $1 JOIN users u ON u.id = r.owner_id
       WHERE r.is_active = TRUE AND r.is_hidden = FALSE AND u.account_status = 'active'
       ORDER BY online DESC, r.created_at DESC LIMIT 10`,
      [id],
    ),
    role && RANK[role] >= RANK.admin
      ? query(`SELECT COUNT(*)::int AS n FROM family_join_requests WHERE family_id = $1`, [id]) : Promise.resolve({ rows: [{ n: 0 }] }),
    query(`SELECT 1 FROM family_join_requests WHERE family_id = $1 AND user_id = $2`, [id, me]),
    query(`SELECT COUNT(*)::int AS n FROM family_members WHERE family_id = $1 AND role = 'admin'`, [id]),
  ]);
  res.json({
    family: familyJson(f, {
      myRole: role,
      requested: requested.rowCount > 0,
      pendingRequests: pending.rows[0].n,
      adminCount: admins.rows[0].n,
      members: members.rows.map((m) => ({ role: m.role, user: publicUser(m, me) })),
      rooms: rooms.rows.map((r) => ({
        id: r.id, name: r.name, coverUrl: r.cover_url ?? r.owner_avatar ?? null, tag: (r.tags ?? [])[0] ?? null, roomType: r.room_type, online: r.online,
      })),
    }),
  });
});

router.post('/', userLimit('family_create', 5, 3600e3), async (req, res) => {
  const name = cleanPublic(text(req.body?.name, 'Aile adı', { min: 2, max: NAME_MAX, required: true }), 'Aile adı');
  const description = text(req.body?.description, 'Aile bildirimi', { max: NOTICE_MAX });
  const logoUrl = httpsUrl(req.body?.logoUrl, 'Logo adresi');
  try {
    const family = await tx(async (c) => {
      await c.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [req.user.id]);
      const existing = await c.query(`SELECT 1 FROM family_members WHERE user_id = $1`, [req.user.id]);
      if (existing.rowCount) throw fail('Zaten bir ailedesiniz. Önce ayrılmalısınız.', 409);
      const pid = await newPublicId((t, p) => c.query(t, p));
      const f = (await c.query(
        `INSERT INTO families(name, logo_url, description, owner_id, public_id) VALUES($1,$2,$3,$4,$5) RETURNING *`,
        [name, logoUrl, description, req.user.id, pid],
      )).rows[0];
      await c.query(`INSERT INTO family_members(family_id, user_id, role) VALUES($1,$2,'owner')`, [f.id, req.user.id]);
      await c.query(`DELETE FROM family_join_requests WHERE user_id = $1`, [req.user.id]);
      return { ...f, member_count: 1 };
    });
    res.status(201).json({ family: familyJson(family, { myRole: 'owner' }) });
  } catch (error) {
    if (error.code === '23505') throw fail('Bu aile adı zaten kullanılıyor.', 409);
    throw error;
  }
});

// Bilgileri Düzenle: aile adı (en fazla 12) ve aile bildirimi (en fazla 100)
router.patch('/:familyId', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const role = await requireRole(id, req.user.id, 'admin');
  const sets = []; const values = [];
  if (req.body?.description !== undefined) { values.push(cleanPublic(text(req.body.description, 'Aile bildirimi', { max: NOTICE_MAX }) ?? '', 'Aile bildirimi')); sets.push(`description = $${values.length}`); }
  if (req.body?.logoUrl !== undefined) { values.push(httpsUrl(req.body.logoUrl, 'Logo adresi')); sets.push(`logo_url = $${values.length}`); }
  if (req.body?.name !== undefined) {
    if (role !== 'owner') throw fail('Aile adını yalnızca sahibi değiştirebilir.', 403);
    values.push(cleanPublic(text(req.body.name, 'Aile adı', { min: 2, max: NAME_MAX, required: true }), 'Aile adı')); sets.push(`name = $${values.length}`);
  }
  if (!sets.length) throw fail('Değiştirilecek alan yok.');
  values.push(id);
  try {
    await query(`UPDATE families SET ${sets.join(', ')} WHERE id = $${values.length} AND is_active = TRUE`, values);
  } catch (error) {
    if (error.code === '23505') throw fail('Bu aile adı zaten kullanılıyor.', 409);
    throw error;
  }
  res.json({ family: familyJson(await activeFamily(id), { myRole: role }) });
});

// Kapak resmi (aile logosu) yükleme: ham bayt (png, jpeg, webp), en fazla 3 MB
router.put(
  '/:familyId/logo',
  userLimit('family_logo', 15, 3600e3),
  express.raw({ type: Object.keys(IMAGE_TYPES), limit: '3mb' }),
  async (req, res) => {
    const id = uuid(req.params.familyId, 'Aile');
    await requireRole(id, req.user.id, 'admin');
    const old = (await query(`SELECT logo_url FROM families WHERE id = $1`, [id])).rows[0];
    const url = await saveUpload(req, 'family_logo');
    await query(`UPDATE families SET logo_url = $2 WHERE id = $1 AND is_active = TRUE`, [id, url]);
    // /media/ logosu yalnızca bu uçtan gelebilir: kim yüklediyse silinir.
    if (old?.logo_url !== url) await removeUpload(old?.logo_url);
    res.json({ url });
  },
);

// İstek Ayarları: başvuranın en düşük zenginlik (gönderme) seviyesi
router.put('/:familyId/settings', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  await requireRole(id, req.user.id, 'admin');
  const v = Number(req.body?.joinMinLevel);
  if (!Number.isInteger(v) || v < 0 || v > 200) throw fail('Seviye 0 ile 200 arasında olmalı.');
  await query(`UPDATE families SET join_min_level = $2 WHERE id = $1`, [id, v]);
  res.json({ joinMinLevel: v });
});

// Aileye katıl: başvuru (yönetici onaylar). Seviye şartı ve kontenjan kontrol edilir.
router.post('/:familyId/join', userLimit('family_join', 20, 3600e3), async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const me = req.user.id;
  await tx(async (c) => {
    const u = (await c.query(`SELECT id, coin_level FROM users WHERE id = $1 FOR UPDATE`, [me])).rows[0];
    const f = (await c.query(`SELECT id, level, join_min_level FROM families WHERE id = $1 AND is_active = TRUE`, [id])).rows[0];
    if (!f) throw fail('Aile bulunamadı.', 404);
    const existing = (await c.query(`SELECT family_id FROM family_members WHERE user_id = $1`, [me])).rows[0];
    if (existing) throw fail(existing.family_id === id ? 'Zaten bu ailedesiniz.' : 'Zaten başka bir ailedesiniz. Önce ayrılmalısınız.', 409);
    if ((u.coin_level ?? 1) < (f.join_min_level ?? 0)) throw fail(`Bu aileye başvurmak için zenginlik seviyeniz en az ${f.join_min_level} olmalı.`);
    const count = (await c.query(`SELECT COUNT(*)::int AS n FROM family_members WHERE family_id = $1`, [id])).rows[0].n;
    if (count >= familyCapacity(f.level)) throw fail('Aile dolu.', 409);
    await c.query(`INSERT INTO family_join_requests(family_id, user_id) VALUES($1,$2) ON CONFLICT DO NOTHING`, [id, me]);
  });
  // Yöneticilere haber ver
  const admins = (await query(`SELECT user_id FROM family_members WHERE family_id = $1 AND role IN ('owner','admin')`, [id])).rows;
  for (const a of admins) hub.sendToUser(a.user_id, { type: 'family_request', familyId: id });
  res.json({ ok: true, requested: true, family: familyJson(await activeFamily(id), { myRole: null, requested: true }) });
});

// Başvuruyu geri çek
router.post('/:familyId/join/cancel', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  await query(`DELETE FROM family_join_requests WHERE family_id = $1 AND user_id = $2`, [id, req.user.id]);
  res.json({ ok: true });
});

// İstekler (yönetici)
router.get('/:familyId/requests', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  await requireRole(id, req.user.id, 'admin');
  const r = await query(
    `SELECT jr.created_at AS requested_at, ${USER_PUBLIC_COLUMNS}
     FROM family_join_requests jr JOIN users u ON u.id = jr.user_id ${USER_PUBLIC_JOINS}
     WHERE jr.family_id = $1 AND u.account_status = 'active' ORDER BY jr.created_at`,
    [id],
  );
  res.json({ requests: r.rows.map((x) => ({ user: publicUser(x, req.user.id), createdAt: x.requested_at })) });
});

router.post('/:familyId/requests/:userId/:action', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const target = uuid(req.params.userId, 'Kullanıcı');
  const action = oneOf(req.params.action, ['accept', 'reject'], 'İşlem');
  await requireRole(id, req.user.id, 'admin');
  let joined = false;
  await tx(async (c) => {
    const tu = (await c.query(`SELECT id, account_status FROM users WHERE id = $1 FOR UPDATE`, [target])).rows[0];
    const f = (await c.query(`SELECT id, level, name FROM families WHERE id = $1 AND is_active = TRUE FOR UPDATE`, [id])).rows[0];
    if (!f) throw fail('Aile bulunamadı.', 404);
    const r = await c.query(`DELETE FROM family_join_requests WHERE family_id = $1 AND user_id = $2 RETURNING user_id`, [id, target]);
    if (!r.rowCount) throw fail('Başvuru bulunamadı.', 404);
    if (action === 'reject') return;
    if (tu?.account_status !== 'active') throw fail('Bu hesap artık aktif değil.', 409);
    const existing = (await c.query(`SELECT family_id FROM family_members WHERE user_id = $1`, [target])).rows[0];
    if (existing) throw fail('Bu kişi artık başka bir ailede.', 409);
    const count = (await c.query(`SELECT COUNT(*)::int AS n FROM family_members WHERE family_id = $1`, [id])).rows[0].n;
    if (count >= familyCapacity(f.level)) throw fail('Aile dolu.', 409);
    await c.query(`INSERT INTO family_members(family_id, user_id, role) VALUES($1,$2,'member')`, [id, target]);
    // Kişinin diğer ailelere başvuruları geçersiz
    await c.query(`DELETE FROM family_join_requests WHERE user_id = $1`, [target]);
    joined = true;
  });
  if (joined) {
    const f = await activeFamily(id);
    notifyUser(target, 'family_join', '👪 Aileye katıldın', `"${f.name}" ailesine başvurun kabul edildi.`, { familyId: id });
  }
  res.json({ ok: true });
});

router.post('/:familyId/leave', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const role = await myRole(id, req.user.id);
  if (!role) throw fail('Bu ailenin üyesi değilsiniz.', 404);
  if (role === 'owner') throw fail('Aile sahibi ayrılamaz. Sahipliği devredin veya aileyi dağıtın.', 409);
  await query(`DELETE FROM family_members WHERE family_id = $1 AND user_id = $2`, [id, req.user.id]);
  res.json({ ok: true });
});

// Aile üyeleri: rol ve bu haftaki katkı
router.get('/:familyId/members', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  await activeFamily(id);
  const r = await query(
    `SELECT fm.role, fm.joined_at, fm.total_contrib, COALESCE(w.points, 0) AS week_points, ${USER_PUBLIC_COLUMNS}
     FROM family_members fm JOIN users u ON u.id = fm.user_id ${USER_PUBLIC_JOINS}
     LEFT JOIN family_contrib_weekly w ON w.family_id = fm.family_id AND w.user_id = fm.user_id AND w.week_start = ${WEEK_DATE}
     WHERE fm.family_id = $1
     ORDER BY CASE fm.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END, COALESCE(w.points, 0) DESC, fm.joined_at`,
    [id],
  );
  res.json({
    members: r.rows.map((m) => ({
      userId: m.id, role: m.role, joinedAt: m.joined_at, weekPoints: String(m.week_points), totalContrib: String(m.total_contrib), user: publicUser(m, req.user.id),
    })),
  });
});

router.post('/:familyId/members/:userId/kick', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  if (targetId === req.user.id) throw fail('Kendinizi atamazsınız; ayrılmayı kullanın.');
  const actorRole = await myRole(id, req.user.id);
  const targetRole = await myRole(id, targetId);
  if (!actorRole || !targetRole) throw fail('Üye bulunamadı.', 404);
  if (RANK[actorRole] < RANK.admin || RANK[actorRole] <= RANK[targetRole]) throw fail('Bu işlem için yetkiniz yok.', 403);
  await query(`DELETE FROM family_members WHERE family_id = $1 AND user_id = $2`, [id, targetId]);
  res.json({ ok: true });
});

router.post('/:familyId/members/:userId/role', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const targetId = uuid(req.params.userId, 'Kullanıcı');
  const role = oneOf(req.body?.role, ['admin', 'member'], 'Rol');
  if (await myRole(id, req.user.id) !== 'owner') throw fail('Rolleri yalnızca aile sahibi değiştirebilir.', 403);
  if (targetId === req.user.id) throw fail('Kendi rolünüzü değiştiremezsiniz.');
  await tx(async (c) => {
    const f = (await c.query(`SELECT level FROM families WHERE id = $1 AND is_active = TRUE FOR UPDATE`, [id])).rows[0];
    if (!f) throw fail('Aile bulunamadı.', 404);
    if (role === 'admin') {
      const n = (await c.query(`SELECT COUNT(*)::int AS n FROM family_members WHERE family_id = $1 AND role = 'admin'`, [id])).rows[0].n;
      if (n >= familyAdminLimit(f.level)) throw fail(`Bu seviyede en fazla ${familyAdminLimit(f.level)} yönetici olabilir.`);
    }
    const r = await c.query(`UPDATE family_members SET role = $3 WHERE family_id = $1 AND user_id = $2 AND role <> 'owner' RETURNING user_id`, [id, targetId, role]);
    if (!r.rowCount) throw fail('Üye bulunamadı.', 404);
  });
  res.json({ ok: true, role });
});

router.post('/:familyId/transfer', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const targetId = uuid(req.body?.userId, 'Kullanıcı');
  await tx(async (c) => {
    // Önce aile satırı (hediye işlemiyle aynı sıra: families, sonra family_members).
    const fam = (await c.query(`SELECT owner_id FROM families WHERE id = $1 AND is_active = TRUE FOR UPDATE`, [id])).rows[0];
    if (!fam) throw fail('Aile bulunamadı.', 404);
    if (fam.owner_id !== req.user.id || await myRole(id, req.user.id, (t, p) => c.query(t, p)) !== 'owner') {
      throw fail('Sahipliği yalnızca aile sahibi devredebilir.', 403);
    }
    if (targetId === req.user.id) throw fail('Sahipliği kendinize devredemezsiniz.');
    const targetRole = await myRole(id, targetId, (t, p) => c.query(t, p));
    if (!targetRole) throw fail('Hedef kullanıcı bu ailenin üyesi değil.', 404);
    await c.query(`UPDATE family_members SET role = 'admin' WHERE family_id = $1 AND user_id = $2`, [id, req.user.id]);
    await c.query(`UPDATE family_members SET role = 'owner' WHERE family_id = $1 AND user_id = $2`, [id, targetId]);
    // Başkan indirimi kişiseldir: devredilince sıfırlanır.
    await c.query(`UPDATE families SET owner_id = $2, leader_cashback = 0, leader_spent = 0 WHERE id = $1`, [id, targetId]);
  });
  res.json({ ok: true });
});

router.delete('/:familyId', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  await tx(async (c) => {
    if (await myRole(id, req.user.id, (t, p) => c.query(t, p)) !== 'owner') throw fail('Aileyi yalnızca sahibi dağıtabilir.', 403);
    await c.query(`UPDATE families SET is_active = FALSE WHERE id = $1`, [id]);
    await c.query(`DELETE FROM family_members WHERE family_id = $1`, [id]);
    await c.query(`DELETE FROM family_join_requests WHERE family_id = $1`, [id]);
  });
  res.json({ ok: true });
});

// ---------- Coins ödülü (haftalık katkı) ve başkan indirimi ----------
router.get('/:familyId/rewards', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const f = await activeFamily(id);
  const role = await myRole(id, req.user.id);
  const [week, claimed, range] = await Promise.all([
    query(`SELECT COALESCE(SUM(points), 0)::bigint AS total FROM family_contrib_weekly WHERE family_id = $1 AND week_start = ${WEEK_DATE}`, [id]),
    query(`SELECT tier FROM family_week_rewards WHERE family_id = $1 AND week_start = ${WEEK_DATE}`, [id]),
    query(`SELECT (${WEEK_DATE})::timestamp AT TIME ZONE 'Europe/Istanbul' AS start_at`),
  ]);
  const total = BigInt(week.rows[0].total);
  const got = new Set(claimed.rows.map((x) => x.tier));
  const start = new Date(range.rows[0].start_at);
  const lvIdx = Math.min(Math.max(f.level, 1), FAMILY_CASHBACK_BPS.length) - 1;
  res.json({
    weekTotal: total.toString(),
    weekStart: start.toISOString(),
    weekEnd: new Date(start.getTime() + 7 * 86400e3 - 1000).toISOString(),
    canClaim: role === 'owner',
    tiers: FAMILY_WEEK_REWARDS.map(([need, coins], i) => ({
      tier: i + 1, need: need.toString(), coins: coins.toString(), reached: total >= need, claimed: got.has(i + 1),
    })),
    cashback: {
      // Başkanın kişisel harcaması yalnızca başkana gösterilir.
      amount: role === 'owner' ? (BigInt(f.leader_cashback ?? 0) / 10000n).toString() : '0',
      spent: role === 'owner' ? String(f.leader_spent ?? 0) : '0', minSpend: FAMILY_CASHBACK_MIN_SPEND.toString(),
      bps: FAMILY_CASHBACK_BPS[lvIdx], tiers: FAMILY_TIERS.map((name, i) => ({ name, bps: FAMILY_CASHBACK_BPS[i] })),
    },
  });
});

// Haftalık ödülü al (aile başkanı; Coin başkana geçer)
router.post('/:familyId/rewards/:tier/claim', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const tier = Number(req.params.tier);
  const def = FAMILY_WEEK_REWARDS[tier - 1];
  if (!Number.isInteger(tier) || !def) throw fail('Ödül bulunamadı.', 404);
  const me = req.user.id;
  const coins = await tx(async (c) => {
    await c.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [me]);
    const f = (await c.query(`SELECT owner_id FROM families WHERE id = $1 AND is_active = TRUE FOR UPDATE`, [id])).rows[0];
    if (!f) throw fail('Aile bulunamadı.', 404);
    if (f.owner_id !== me) throw fail('Haftalık ödülü yalnızca aile başkanı alabilir.', 403);
    const total = BigInt((await c.query(
      `SELECT COALESCE(SUM(points), 0)::bigint AS t FROM family_contrib_weekly WHERE family_id = $1 AND week_start = ${WEEK_DATE}`, [id],
    )).rows[0].t);
    if (total < def[0]) throw fail('Bu hafta için katkı henüz yeterli değil.');
    const ins = await c.query(
      `INSERT INTO family_week_rewards(family_id, week_start, tier, claimed_by, coins) VALUES($1, ${WEEK_DATE}, $2, $3, $4)
       ON CONFLICT DO NOTHING RETURNING tier`,
      [id, tier, me, def[1].toString()],
    );
    if (!ins.rowCount) throw fail('Bu ödül bu hafta zaten alındı.', 409);
    const left = (await c.query(`UPDATE users SET coins = coins + $2, updated_at = NOW() WHERE id = $1 RETURNING coins`, [me, def[1].toString()])).rows[0].coins;
    await c.query(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, description) VALUES($1,'family_reward',$2,'Aile haftalık Coins ödülü')`,
      [me, def[1].toString()],
    );
    return String(left);
  });
  res.json({ ok: true, coins });
});

// Başkan indirimini al (kişisel harcama en az 10K olmalı)
router.post('/:familyId/cashback/claim', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const me = req.user.id;
  const result = await tx(async (c) => {
    await c.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [me]);
    const f = (await c.query(`SELECT owner_id, leader_cashback, leader_spent FROM families WHERE id = $1 AND is_active = TRUE FOR UPDATE`, [id])).rows[0];
    if (!f) throw fail('Aile bulunamadı.', 404);
    if (f.owner_id !== me) throw fail('İndirimi yalnızca aile başkanı alabilir.', 403);
    const units = BigInt(f.leader_cashback);
    const amount = units / 10000n;
    if (BigInt(f.leader_spent) < FAMILY_CASHBACK_MIN_SPEND) throw fail(`İndirim için toplam harcama en az ${FAMILY_CASHBACK_MIN_SPEND} Coin olmalı.`);
    if (amount <= 0n) throw fail('Alınacak indirim yok.');
    await c.query(`UPDATE families SET leader_cashback = $2, leader_spent = 0 WHERE id = $1`, [id, (units % 10000n).toString()]);
    const left = (await c.query(`UPDATE users SET coins = coins + $2, updated_at = NOW() WHERE id = $1 RETURNING coins`, [me, amount.toString()])).rows[0].coins;
    await c.query(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, description) VALUES($1,'family_cashback',$2,'Aile başkanı indirimi')`,
      [me, amount.toString()],
    );
    return { amount: amount.toString(), coins: String(left) };
  });
  res.json({ ok: true, ...result });
});
