import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { fail, uuid, text, httpsUrl, oneOf } from '../http.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';
import { familyCapacity } from '../levels.js';

export const router = Router();
router.use(requireAuth);

const RANK = { owner: 3, admin: 2, member: 1 };
const familyJson = (f, extra = {}) => ({
  id: f.id, name: f.name, logoUrl: f.logo_url, description: f.description, ownerId: f.owner_id,
  level: f.level, totalPoints: String(f.total_points), memberCount: f.member_count, capacity: familyCapacity(f.level), ...extra,
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

router.get('/', async (req, res) => {
  const q = String(req.query.q ?? '').trim().toLowerCase();
  const r = await query(
    `${FAMILY_SELECT} WHERE f.is_active = TRUE AND ($1 = '' OR lower(f.name) LIKE $2 ESCAPE '\\')
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
  if (!m) return res.json({ family: null });
  res.json({ family: familyJson(await activeFamily(m.family_id), { myRole: m.role }) });
});

router.get('/:familyId', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const f = await activeFamily(id);
  res.json({ family: familyJson(f, { myRole: await myRole(id, req.user.id) }) });
});

router.post('/', async (req, res) => {
  const name = text(req.body?.name, 'Aile adı', { min: 2, max: 40, required: true });
  const description = text(req.body?.description, 'Açıklama', { max: 300 });
  const logoUrl = httpsUrl(req.body?.logoUrl, 'Logo adresi');
  try {
    const family = await tx(async (c) => {
      await c.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [req.user.id]);
      const existing = await c.query(`SELECT 1 FROM family_members WHERE user_id = $1`, [req.user.id]);
      if (existing.rowCount) throw fail('Zaten bir ailedesiniz. Önce ayrılmalısınız.', 409);
      const f = (await c.query(
        `INSERT INTO families(name, logo_url, description, owner_id) VALUES($1,$2,$3,$4) RETURNING *`,
        [name, logoUrl, description, req.user.id],
      )).rows[0];
      await c.query(`INSERT INTO family_members(family_id, user_id, role) VALUES($1,$2,'owner')`, [f.id, req.user.id]);
      return { ...f, member_count: 1 };
    });
    res.status(201).json({ family: familyJson(family, { myRole: 'owner' }) });
  } catch (error) {
    if (error.code === '23505') throw fail('Bu aile adı zaten kullanılıyor.', 409);
    throw error;
  }
});

router.patch('/:familyId', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const role = await myRole(id, req.user.id);
  if (!role || RANK[role] < RANK.admin) throw fail('Bu işlem için yetkiniz yok.', 403);
  const sets = []; const values = [];
  if (req.body?.description !== undefined) { values.push(text(req.body.description, 'Açıklama', { max: 300 })); sets.push(`description = $${values.length}`); }
  if (req.body?.logoUrl !== undefined) { values.push(httpsUrl(req.body.logoUrl, 'Logo adresi')); sets.push(`logo_url = $${values.length}`); }
  if (req.body?.name !== undefined) {
    if (role !== 'owner') throw fail('Aile adını yalnızca sahibi değiştirebilir.', 403);
    values.push(text(req.body.name, 'Aile adı', { min: 2, max: 40, required: true })); sets.push(`name = $${values.length}`);
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

router.post('/:familyId/join', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  await tx(async (c) => {
    await c.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [req.user.id]);
    const f = (await c.query(`SELECT id, level FROM families WHERE id = $1 AND is_active = TRUE FOR UPDATE`, [id])).rows[0];
    if (!f) throw fail('Aile bulunamadı.', 404);
    const existing = (await c.query(`SELECT family_id FROM family_members WHERE user_id = $1`, [req.user.id])).rows[0];
    if (existing) throw fail(existing.family_id === id ? 'Zaten bu ailedesiniz.' : 'Zaten başka bir ailedesiniz. Önce ayrılmalısınız.', 409);
    const count = (await c.query(`SELECT COUNT(*)::int AS n FROM family_members WHERE family_id = $1`, [id])).rows[0].n;
    if (count >= familyCapacity(f.level)) throw fail('Aile dolu.', 409);
    await c.query(`INSERT INTO family_members(family_id, user_id, role) VALUES($1,$2,'member')`, [id, req.user.id]);
  });
  res.json({ family: familyJson(await activeFamily(id), { myRole: 'member' }) });
});

router.post('/:familyId/leave', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const role = await myRole(id, req.user.id);
  if (!role) throw fail('Bu ailenin üyesi değilsiniz.', 404);
  if (role === 'owner') throw fail('Aile sahibi ayrılamaz. Sahipliği devredin veya aileyi dağıtın.', 409);
  await query(`DELETE FROM family_members WHERE family_id = $1 AND user_id = $2`, [id, req.user.id]);
  res.json({ ok: true });
});

router.get('/:familyId/members', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  await activeFamily(id);
  const r = await query(
    `SELECT fm.role, fm.joined_at, ${USER_PUBLIC_COLUMNS}
     FROM family_members fm JOIN users u ON u.id = fm.user_id ${USER_PUBLIC_JOINS}
     WHERE fm.family_id = $1
     ORDER BY CASE fm.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END, fm.joined_at`,
    [id],
  );
  res.json({ members: r.rows.map((m) => ({ userId: m.id, role: m.role, joinedAt: m.joined_at, user: publicUser(m, req.user.id) })) });
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
  const r = await query(`UPDATE family_members SET role = $3 WHERE family_id = $1 AND user_id = $2 RETURNING user_id`, [id, targetId, role]);
  if (!r.rowCount) throw fail('Üye bulunamadı.', 404);
  res.json({ ok: true, role });
});

router.post('/:familyId/transfer', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  const targetId = uuid(req.body?.userId, 'Kullanıcı');
  await tx(async (c) => {
    if (await myRole(id, req.user.id, (t, p) => c.query(t, p)) !== 'owner') throw fail('Sahipliği yalnızca aile sahibi devredebilir.', 403);
    if (targetId === req.user.id) throw fail('Sahipliği kendinize devredemezsiniz.');
    const targetRole = await myRole(id, targetId, (t, p) => c.query(t, p));
    if (!targetRole) throw fail('Hedef kullanıcı bu ailenin üyesi değil.', 404);
    await c.query(`UPDATE family_members SET role = 'admin' WHERE family_id = $1 AND user_id = $2`, [id, req.user.id]);
    await c.query(`UPDATE family_members SET role = 'owner' WHERE family_id = $1 AND user_id = $2`, [id, targetId]);
    await c.query(`UPDATE families SET owner_id = $2 WHERE id = $1`, [id, targetId]);
  });
  res.json({ ok: true });
});

router.delete('/:familyId', async (req, res) => {
  const id = uuid(req.params.familyId, 'Aile');
  await tx(async (c) => {
    if (await myRole(id, req.user.id, (t, p) => c.query(t, p)) !== 'owner') throw fail('Aileyi yalnızca sahibi dağıtabilir.', 403);
    await c.query(`UPDATE families SET is_active = FALSE WHERE id = $1`, [id]);
    await c.query(`DELETE FROM family_members WHERE family_id = $1`, [id]);
  });
  res.json({ ok: true });
});
