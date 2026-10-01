import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { fail, uuid, text, httpsUrl } from '../http.js';
import { currentPeriod, isPeriod, periodRange } from '../periods.js';
import { USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS, publicUser } from '../views.js';

export const router = Router();
router.use(requireAuth);

const agencyJson = (a) => ({
  id: a.id, name: a.name, logoUrl: a.logo_url, description: a.description, status: a.status,
  commissionBps: a.commission_bps, ownerId: a.owner_id, createdAt: a.created_at,
  broadcasterCount: a.broadcaster_count ?? undefined,
});
const AGENCY_SELECT = `SELECT a.*, (SELECT COUNT(*)::int FROM broadcasters b WHERE b.agency_id = a.id AND b.status = 'approved') AS broadcaster_count FROM agencies a`;

// Yönetim ekranlarında (ajans sahibi/yönetici) gerçek kimlik gösterilir; "gizli kullanıcı" maskesi uygulanmaz.
const memberJson = (x) => ({ id: x.id, username: x.username, displayName: x.display_name, avatarUrl: x.avatar_url });

const SEC_EXPR = `COALESCE((SELECT SUM(EXTRACT(EPOCH FROM (LEAST(COALESCE(s.ended_at, NOW()), $3::timestamptz) - GREATEST(s.started_at, $2::timestamptz))))
  FROM broadcast_sessions s WHERE s.user_id = b.user_id AND s.started_at < $3::timestamptz AND COALESCE(s.ended_at, NOW()) > $2::timestamptz), 0)::bigint`;
const DIA_EXPR = `COALESCE((SELECT SUM(gt.coin_amount) FROM gift_transactions gt WHERE gt.receiver_id = b.user_id AND gt.sender_id <> b.user_id
  AND gt.created_at >= $2::timestamptz AND gt.created_at < $3::timestamptz), 0)`;

async function ownedAgency(userId) {
  return (await query(`SELECT * FROM agencies WHERE owner_id = $1 AND status <> 'rejected'`, [userId])).rows[0] || null;
}

async function assertAgencyOwner(agencyId, user) {
  const a = (await query(`SELECT * FROM agencies WHERE id = $1`, [agencyId])).rows[0];
  if (!a) throw fail('Ajans bulunamadı.', 404);
  if (a.owner_id !== user.id && !['admin', 'support'].includes(user.system_role)) throw fail('Bu ajansı yönetme yetkiniz yok.', 403);
  return a;
}

function periodFrom(req) {
  const p = req.query.period ? String(req.query.period) : currentPeriod();
  if (!isPeriod(p)) throw fail('Dönem YYYY-AA biçiminde olmalı.');
  return { period: p, ...periodRange(p) };
}

// ---------------- Ajans ----------------
router.get('/agencies', async (req, res) => {
  const q = String(req.query.q ?? '').trim().toLowerCase();
  const r = await query(
    `${AGENCY_SELECT} WHERE a.status = 'active' AND ($1 = '' OR lower(a.name) LIKE $2 ESCAPE '\\') ORDER BY a.name LIMIT 100`,
    [q, `%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`],
  );
  res.json({ agencies: r.rows.map(agencyJson) });
});

router.post('/agencies', async (req, res) => {
  const name = text(req.body?.name, 'Ajans adı', { min: 3, max: 60, required: true });
  const description = text(req.body?.description, 'Açıklama', { max: 500 });
  const logoUrl = httpsUrl(req.body?.logoUrl, 'Logo adresi');
  try {
    const agency = await tx(async (c) => {
      await c.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [req.user.id]);
      const b = (await c.query(`SELECT status FROM broadcasters WHERE user_id = $1`, [req.user.id])).rows[0];
      if (b && b.status !== 'rejected') throw fail('Yayıncılar ajans kuramaz.', 409);
      if ((await c.query(`SELECT 1 FROM agencies WHERE owner_id = $1 AND status <> 'rejected'`, [req.user.id])).rowCount) {
        throw fail('Zaten bir ajansınız var.', 409);
      }
      return (await c.query(
        `INSERT INTO agencies(name, owner_id, logo_url, description) VALUES($1,$2,$3,$4) RETURNING *`,
        [name, req.user.id, logoUrl, description],
      )).rows[0];
    });
    res.status(201).json({ agency: agencyJson(agency), message: 'Ajans başvurunuz alındı; yönetici onayı bekleniyor.' });
  } catch (error) {
    if (error.code === '23505') throw fail('Bu ajans adı kullanılıyor veya zaten bir ajansınız var.', 409);
    throw error;
  }
});

router.get('/agencies/mine', async (req, res) => {
  const owned = await ownedAgency(req.user.id);
  const membership = (await query(
    `SELECT b.status, b.joined_agency_at, a.id, a.name, a.logo_url, a.description, a.status AS agency_status
     FROM broadcasters b LEFT JOIN agencies a ON a.id = b.agency_id WHERE b.user_id = $1`,
    [req.user.id],
  )).rows[0];
  res.json({
    owned: owned ? agencyJson(owned) : null,
    membership: membership ? {
      broadcasterStatus: membership.status,
      agency: membership.id ? { id: membership.id, name: membership.name, logoUrl: membership.logo_url, description: membership.description, status: membership.agency_status } : null,
      joinedAt: membership.joined_agency_at,
    } : null,
  });
});

router.patch('/agencies/:agencyId', async (req, res) => {
  const a = await assertAgencyOwner(uuid(req.params.agencyId, 'Ajans'), req.user);
  const sets = []; const values = [];
  if (req.body?.description !== undefined) { values.push(text(req.body.description, 'Açıklama', { max: 500 })); sets.push(`description = $${values.length}`); }
  if (req.body?.logoUrl !== undefined) { values.push(httpsUrl(req.body.logoUrl, 'Logo adresi')); sets.push(`logo_url = $${values.length}`); }
  if (!sets.length) throw fail('Değiştirilecek alan yok.');
  values.push(a.id);
  await query(`UPDATE agencies SET ${sets.join(', ')} WHERE id = $${values.length}`, values);
  res.json({ ok: true });
});

// Ajans paneli: yayıncılar, aylık Diamond ve yayın süresi, komisyon özeti.
router.get('/agencies/:agencyId/dashboard', async (req, res) => {
  const a = await assertAgencyOwner(uuid(req.params.agencyId, 'Ajans'), req.user);
  const { period, start, end } = periodFrom(req);
  const rows = (await query(
    `SELECT u.id, u.username, u.display_name, u.avatar_url, b.status, b.joined_agency_at,
            ${DIA_EXPR} AS diamonds, ${SEC_EXPR} AS seconds
     FROM broadcasters b JOIN users u ON u.id = b.user_id
     WHERE b.agency_id = $1 ORDER BY diamonds DESC, u.username`,
    [a.id, start, end],
  )).rows;
  const commissions = (await query(
    `SELECT status, COALESCE(SUM(diamond_amount), 0) AS total FROM agency_commissions WHERE agency_id = $1 AND period = $2 GROUP BY status`,
    [a.id, period],
  )).rows;
  const unpaid = (await query(
    `SELECT COALESCE(SUM(diamond_amount), 0) AS total FROM agency_commissions WHERE agency_id = $1 AND status = 'accrued'`, [a.id],
  )).rows[0].total;
  const sum = (status) => String(commissions.find((x) => x.status === status)?.total ?? 0);
  res.json({
    agency: agencyJson(a), period,
    broadcasters: rows.map((x) => ({ ...memberJson(x), status: x.status, joinedAt: x.joined_agency_at, diamonds: String(x.diamonds), seconds: Number(x.seconds) })),
    totals: {
      diamonds: rows.reduce((s, x) => s + BigInt(x.diamonds), 0n).toString(),
      seconds: rows.reduce((s, x) => s + Number(x.seconds), 0),
      commissionAccrued: sum('accrued'), commissionPaid: sum('paid'), commissionUnpaidAllTime: String(unpaid),
    },
  });
});

router.get('/agencies/:agencyId/requests', async (req, res) => {
  const a = await assertAgencyOwner(uuid(req.params.agencyId, 'Ajans'), req.user);
  const r = await query(
    `SELECT q.id AS request_id, q.direction, q.created_at AS request_created_at, u.id, u.username, u.display_name, u.avatar_url
     FROM agency_requests q JOIN users u ON u.id = q.user_id WHERE q.agency_id = $1 AND q.status = 'pending' ORDER BY q.created_at DESC`,
    [a.id],
  );
  res.json({ requests: r.rows.map((x) => ({ id: x.request_id, direction: x.direction, createdAt: x.request_created_at, user: memberJson(x) })) });
});

router.post('/agencies/:agencyId/invite', async (req, res) => {
  const a = await assertAgencyOwner(uuid(req.params.agencyId, 'Ajans'), req.user);
  if (a.owner_id !== req.user.id) throw fail('Davet yalnızca ajans sahibi tarafından gönderilir.', 403);
  if (a.status !== 'active') throw fail('Ajans henüz aktif değil.', 409);
  const userId = uuid(req.body?.userId, 'Kullanıcı');
  const b = (await query(`SELECT status, agency_id FROM broadcasters WHERE user_id = $1`, [userId])).rows[0];
  if (!b || b.status === 'rejected' || b.status === 'suspended') throw fail('Kullanıcı onaylı veya bekleyen bir yayıncı değil.', 409);
  if (b.agency_id) throw fail('Yayıncı zaten bir ajansa bağlı.', 409);
  try {
    const r = await query(`INSERT INTO agency_requests(agency_id, user_id, direction) VALUES($1,$2,'invite') RETURNING id`, [a.id, userId]);
    res.status(201).json({ ok: true, requestId: r.rows[0].id });
  } catch (error) {
    if (error.code === '23505') throw fail('Bu kullanıcı için bekleyen bir istek zaten var.', 409);
    throw error;
  }
});

router.post('/agencies/:agencyId/apply', async (req, res) => {
  const agencyId = uuid(req.params.agencyId, 'Ajans');
  const a = (await query(`SELECT * FROM agencies WHERE id = $1 AND status = 'active'`, [agencyId])).rows[0];
  if (!a) throw fail('Ajans bulunamadı.', 404);
  const b = (await query(`SELECT status, agency_id FROM broadcasters WHERE user_id = $1`, [req.user.id])).rows[0];
  if (!b || b.status === 'rejected' || b.status === 'suspended') throw fail('Ajansa başvurmak için önce yayıncı başvurusu yapmalısınız.', 409);
  if (b.agency_id) throw fail('Zaten bir ajansa bağlısınız.', 409);
  try {
    const r = await query(`INSERT INTO agency_requests(agency_id, user_id, direction) VALUES($1,$2,'apply') RETURNING id`, [agencyId, req.user.id]);
    res.status(201).json({ ok: true, requestId: r.rows[0].id });
  } catch (error) {
    if (error.code === '23505') throw fail('Bu ajansa zaten bekleyen bir isteğiniz var.', 409);
    throw error;
  }
});

// Davet eden değil, karşı taraf yanıtlar: davete kullanıcı, başvuruya ajans sahibi.
router.post('/agency-requests/:requestId/respond', async (req, res) => {
  const requestId = uuid(req.params.requestId, 'İstek');
  const accept = req.body?.accept === true;
  await tx(async (c) => {
    const q = (await c.query(`SELECT * FROM agency_requests WHERE id = $1 AND status = 'pending' FOR UPDATE`, [requestId])).rows[0];
    if (!q) throw fail('İstek bulunamadı veya yanıtlanmış.', 404);
    const agency = (await c.query(`SELECT * FROM agencies WHERE id = $1`, [q.agency_id])).rows[0];
    const allowed = q.direction === 'apply' ? agency.owner_id === req.user.id : q.user_id === req.user.id;
    if (!allowed) throw fail('Bu isteği yanıtlama yetkiniz yok.', 403);
    if (accept) {
      if (agency.status !== 'active') throw fail('Ajans aktif değil.', 409);
      const b = (await c.query(`SELECT status, agency_id FROM broadcasters WHERE user_id = $1 FOR UPDATE`, [q.user_id])).rows[0];
      if (!b || b.status === 'rejected' || b.status === 'suspended') throw fail('Kullanıcı yayıncı olarak uygun değil.', 409);
      if (b.agency_id) throw fail('Yayıncı zaten bir ajansa bağlı.', 409);
      await c.query(`UPDATE broadcasters SET agency_id = $1, joined_agency_at = NOW() WHERE user_id = $2`, [agency.id, q.user_id]);
      await c.query(`UPDATE agency_requests SET status = 'cancelled', responded_at = NOW() WHERE user_id = $1 AND status = 'pending' AND id <> $2`, [q.user_id, q.id]);
    }
    await c.query(`UPDATE agency_requests SET status = $2, responded_at = NOW() WHERE id = $1`, [q.id, accept ? 'accepted' : 'rejected']);
  });
  res.json({ ok: true, accepted: accept });
});

router.post('/agencies/:agencyId/broadcasters/:userId/remove', async (req, res) => {
  const a = await assertAgencyOwner(uuid(req.params.agencyId, 'Ajans'), req.user);
  const userId = uuid(req.params.userId, 'Kullanıcı');
  const r = await query(`UPDATE broadcasters SET agency_id = NULL, joined_agency_at = NULL WHERE user_id = $1 AND agency_id = $2 RETURNING user_id`, [userId, a.id]);
  if (!r.rowCount) throw fail('Yayıncı bu ajansta değil.', 404);
  res.json({ ok: true });
});

// ---------------- Yayıncı ----------------
router.post('/broadcaster/apply', async (req, res) => {
  if (await ownedAgency(req.user.id)) throw fail('Ajans sahipleri yayıncı olamaz.', 409);
  const b = (await query(`SELECT status FROM broadcasters WHERE user_id = $1`, [req.user.id])).rows[0];
  if (b?.status === 'pending') throw fail('Başvurunuz zaten inceleniyor.', 409);
  if (b?.status === 'approved') throw fail('Zaten onaylı bir yayıncısınız.', 409);
  if (b?.status === 'suspended') throw fail('Yayıncı hesabınız askıya alınmış. Destek ile iletişime geçin.', 403);
  await query(
    `INSERT INTO broadcasters(user_id, status) VALUES($1,'pending')
     ON CONFLICT (user_id) DO UPDATE SET status = 'pending', applied_at = NOW()`,
    [req.user.id],
  );
  res.status(201).json({ ok: true, status: 'pending' });
});

router.get('/broadcaster/me', async (req, res) => {
  const b = (await query(
    `SELECT b.status, b.joined_agency_at, a.id AS agency_id, a.name AS agency_name, a.logo_url AS agency_logo
     FROM broadcasters b LEFT JOIN agencies a ON a.id = b.agency_id WHERE b.user_id = $1`,
    [req.user.id],
  )).rows[0];
  if (!b) return res.json({ broadcaster: null });
  const { period, start, end } = periodFrom(req);
  // $1 = kullanıcı; DIA_EXPR/SEC_EXPR "b.user_id" kullandığı için broadcasters tablosundan sorgulanır.
  const stats = (await query(
    `SELECT ${DIA_EXPR} AS diamonds, ${SEC_EXPR} AS seconds FROM broadcasters b WHERE b.user_id = $1`,
    [req.user.id, start, end],
  )).rows[0];
  const total = (await query(
    `SELECT COALESCE(SUM(coin_amount), 0) AS diamonds FROM gift_transactions WHERE receiver_id = $1 AND sender_id <> $1`, [req.user.id],
  )).rows[0];
  res.json({
    broadcaster: {
      status: b.status,
      agency: b.agency_id ? { id: b.agency_id, name: b.agency_name, logoUrl: b.agency_logo } : null,
      joinedAgencyAt: b.joined_agency_at,
      period, periodDiamonds: String(stats.diamonds), periodSeconds: Number(stats.seconds), totalDiamonds: String(total.diamonds),
    },
  });
});

router.get('/broadcaster/requests', async (req, res) => {
  const r = await query(
    `SELECT q.id, q.direction, q.created_at, a.id AS agency_id, a.name AS agency_name, a.logo_url AS agency_logo
     FROM agency_requests q JOIN agencies a ON a.id = q.agency_id WHERE q.user_id = $1 AND q.status = 'pending' ORDER BY q.created_at DESC`,
    [req.user.id],
  );
  res.json({
    requests: r.rows.map((x) => ({
      id: x.id, direction: x.direction, createdAt: x.created_at, agency: { id: x.agency_id, name: x.agency_name, logoUrl: x.agency_logo },
    })),
  });
});

router.post('/broadcaster/leave-agency', async (req, res) => {
  const r = await query(`UPDATE broadcasters SET agency_id = NULL, joined_agency_at = NULL WHERE user_id = $1 AND agency_id IS NOT NULL RETURNING user_id`, [req.user.id]);
  if (!r.rowCount) throw fail('Bir ajansa bağlı değilsiniz.', 404);
  res.json({ ok: true });
});
