import { cleanPublic } from '../safe_text.js';
import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { fail, uuid, text, httpsUrl } from '../http.js';
import crypto from 'node:crypto';
import { periodBounds, parsePeriodKey, commissionFor, nextCommissionTier, evaluateHost } from '../settlement.js';
import { loadConfig, configJson, hostMetrics, teamDiamonds, eventsOk, hostProgress, hostStatementJson, agencyStatementJson } from '../services/payouts.js';

export const router = Router();
router.use(requireAuth);

const agencyJson = (a) => ({
  id: a.id, name: a.name, logoUrl: a.logo_url, description: a.description, status: a.status,
  commissionBps: a.commission_bps, ownerId: a.owner_id, createdAt: a.created_at,
  broadcasterCount: a.broadcaster_count ?? undefined, agencyCode: a.agency_code ?? undefined,
});
const AGENCY_SELECT = `SELECT a.*, (SELECT COUNT(*)::int FROM broadcasters b WHERE b.agency_id = a.id AND b.status = 'approved') AS broadcaster_count FROM agencies a`;

const publicAgencyJson = (a) => { const j = agencyJson(a); delete j.agencyCode; return j; };

// Yönetim ekranlarında (ajans sahibi/yönetici) gerçek kimlik gösterilir; "gizli kullanıcı" maskesi uygulanmaz.
const memberJson = (x) => ({ id: x.id, username: x.username, displayName: x.display_name, avatarUrl: x.avatar_url });

// 8 haneli ajans kodu (ilk hane 0 olmaz).
export async function ensureAgencyCode(agencyId, run = query) {
  const cur = (await run(`SELECT agency_code FROM agencies WHERE id = $1`, [agencyId])).rows[0];
  if (!cur) return null;
  if (cur.agency_code) return cur.agency_code;
  for (let i = 0; i < 10; i += 1) {
    const code = String(10000000 + crypto.randomInt(0, 90000000));
    try {
      const r = await run(`UPDATE agencies SET agency_code = $2 WHERE id = $1 AND agency_code IS NULL RETURNING agency_code`, [agencyId, code]);
      return r.rows[0]?.agency_code ?? (await run(`SELECT agency_code FROM agencies WHERE id = $1`, [agencyId])).rows[0].agency_code;
    } catch (error) {
      if (error.code !== '23505') throw error;
    }
  }
  throw fail('Ajans kodu üretilemedi.', 503);
}

async function ownedAgency(userId) {
  return (await query(`SELECT * FROM agencies WHERE owner_id = $1 AND status <> 'rejected'`, [userId])).rows[0] || null;
}

async function assertAgencyOwner(agencyId, user) {
  const a = (await query(`SELECT * FROM agencies WHERE id = $1`, [agencyId])).rows[0];
  if (!a) throw fail('Ajans bulunamadı.', 404);
  if (a.owner_id !== user.id && !['admin', 'support'].includes(user.system_role)) throw fail('Bu ajansı yönetme yetkiniz yok.', 403);
  return a;
}

function boundsFrom(req, cycle) {
  try { return req.query.period ? parsePeriodKey(String(req.query.period)) : periodBounds(cycle); }
  catch { throw fail('Dönem anahtarı geçersiz (örn. 2026-10 veya W2026-09-28).'); }
}

// ---------------- Ajans ----------------
router.get('/agencies', async (req, res) => {
  const q = String(req.query.q ?? '').trim().toLowerCase();
  const r = await query(
    `${AGENCY_SELECT} WHERE a.status = 'active' AND ($1 = '' OR lower(a.name) LIKE $2 ESCAPE '\\') ORDER BY a.name LIMIT 100`,
    [q, `%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`],
  );
  res.json({ agencies: r.rows.map(publicAgencyJson) });
});

router.post('/agencies', async (req, res) => {
  const name = cleanPublic(text(req.body?.name, 'Ajans adı', { min: 3, max: 60, required: true }), 'Ajans adı');
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
    res.status(201).json({ agency: publicAgencyJson(agency), message: 'Ajans başvurunuz alındı; yönetici onayı bekleniyor.' });
  } catch (error) {
    if (error.code === '23505') throw fail('Bu ajans adı kullanılıyor veya zaten bir ajansınız var.', 409);
    throw error;
  }
});

router.get('/agencies/mine', async (req, res) => {
  let owned = await ownedAgency(req.user.id);
  if (owned && owned.status === 'active' && !owned.agency_code) { await ensureAgencyCode(owned.id); owned = await ownedAgency(req.user.id); }
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

// Ajans paneli: canlı dönem verileri, komisyon kademesi, bir sonraki kademeye kalan, yayıncı bazında ilerleme.
router.get('/agencies/:agencyId/dashboard', async (req, res) => {
  const a = await assertAgencyOwner(uuid(req.params.agencyId, 'Ajans'), req.user);
  const cfg = await loadConfig();
  const b = boundsFrom(req, cfg.settings.cycle);
  const hosts = (await query(
    `SELECT u.id, u.username, u.display_name, u.avatar_url, br.status, br.joined_agency_at
     FROM broadcasters br JOIN users u ON u.id = br.user_id WHERE br.agency_id = $1 ORDER BY u.username`, [a.id],
  )).rows;
  const rows = [];
  for (const h of hosts) {
    const m = await hostMetrics(h.id, b.start, b.end);
    const ok = await eventsOk(h.id, cfg, b.start, b.end);
    const ev = evaluateHost({ tiers: cfg.salaryTiers, seconds: m.seconds, diamonds: m.diamonds, penaltyBps: cfg.settings.penaltyBps, eventsRequired: cfg.settings.requireOfficialEvents, eventsOk: ok });
    rows.push({
      ...memberJson(h), status: h.status, joinedAt: h.joined_agency_at, seconds: m.seconds, diamonds: String(m.diamonds),
      tier: ev.tier?.level ?? null, estimatedCents: String(ev.salaryCents), atRisk: ev.penalty && ev.tier !== null, eventsOk: ok,
    });
  }
  rows.sort((x, y) => (BigInt(y.diamonds) > BigInt(x.diamonds) ? 1 : BigInt(y.diamonds) < BigInt(x.diamonds) ? -1 : 0));
  const team = await teamDiamonds(a.id, b.start, b.end);
  const com = commissionFor(cfg.commissionTiers, team, a.commission_override_bps);
  const next = a.commission_override_bps === null ? nextCommissionTier(cfg.commissionTiers, team) : null;
  res.json({
    agency: agencyJson(a), periodKey: b.key, cycle: b.cycle, startsAt: b.start, endsAt: b.end, currency: cfg.settings.currency,
    broadcasters: rows,
    totals: {
      teamDiamonds: String(team), seconds: rows.reduce((t, x) => t + x.seconds, 0),
      commissionBps: com.bps, commissionTier: com.level, estimatedCommissionDiamonds: String(com.amount),
      overrideBps: a.commission_override_bps,
      estimatedSalaryCents: String(rows.reduce((t, x) => t + BigInt(x.estimatedCents), 0n)),
      next: next ? { level: next.level, minDiamonds: String(next.minDiamonds), bps: next.bps, remaining: String(next.remaining) } : null,
    },
    config: configJson(cfg),
  });
});

router.get('/agencies/:agencyId/statements', async (req, res) => {
  const a = await assertAgencyOwner(uuid(req.params.agencyId, 'Ajans'), req.user);
  const mine = (await query(
    `SELECT s.*, p.period_key, p.starts_at, p.ends_at, $2::text AS agency_name FROM agency_statements s JOIN payout_periods p ON p.id = s.period_id
     WHERE s.agency_id = $1 ORDER BY p.starts_at DESC LIMIT 24`, [a.id, a.name],
  )).rows;
  const hosts = (await query(
    `SELECT h.*, p.period_key, p.starts_at, p.ends_at, u.username FROM host_statements h
     JOIN payout_periods p ON p.id = h.period_id JOIN users u ON u.id = h.user_id
     WHERE h.agency_id = $1 ORDER BY p.starts_at DESC, h.salary_cents DESC LIMIT 200`, [a.id],
  )).rows;
  res.json({ agencyStatements: mine.map(agencyStatementJson), hostStatements: hosts.map(hostStatementJson) });
});

// Ajans koduyla ajans bilgisi ve başvuru.
router.get('/agencies/by-code/:code', async (req, res) => {
  const code = String(req.params.code ?? '');
  if (!/^\d{8}$/.test(code)) throw fail('Ajans kodu 8 haneli olmalı.');
  const a = (await query(`${AGENCY_SELECT} WHERE a.agency_code = $1 AND a.status = 'active'`, [code])).rows[0];
  if (!a) throw fail('Bu koda ait ajans bulunamadı.', 404);
  res.json({ agency: publicAgencyJson(a) });
});

router.post('/agencies/apply-by-code', async (req, res) => {
  const code = String(req.body?.code ?? '').trim();
  if (!/^\d{8}$/.test(code)) throw fail('Ajans kodu 8 haneli olmalı.');
  const a = (await query(`SELECT id FROM agencies WHERE agency_code = $1 AND status = 'active'`, [code])).rows[0];
  if (!a) throw fail('Bu koda ait ajans bulunamadı.', 404);
  const b = (await query(`SELECT status, agency_id FROM broadcasters WHERE user_id = $1`, [req.user.id])).rows[0];
  if (!b || b.status === 'rejected' || b.status === 'suspended') throw fail('Önce yayıncı başvurusu yapmalısınız.', 409);
  if (b.agency_id) throw fail('Zaten bir ajansa bağlısınız.', 409);
  try {
    const r = await query(`INSERT INTO agency_requests(agency_id, user_id, direction) VALUES($1,$2,'apply') RETURNING id`, [a.id, req.user.id]);
    res.status(201).json({ ok: true, requestId: r.rows[0].id });
  } catch (error) {
    if (error.code === '23505') throw fail('Bu ajansa zaten bekleyen bir isteğiniz var.', 409);
    throw error;
  }
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
  const cfg = await loadConfig();
  const progress = await hostProgress(req.user.id, cfg);
  const total = (await query(
    `SELECT COALESCE(SUM(coin_amount), 0) AS diamonds FROM gift_transactions WHERE receiver_id = $1 AND sender_id <> $1`, [req.user.id],
  )).rows[0];
  const kyc = (await query(`SELECT kyc_status FROM users WHERE id = $1`, [req.user.id])).rows[0].kyc_status;
  res.json({
    broadcaster: {
      status: b.status,
      agency: b.agency_id ? { id: b.agency_id, name: b.agency_name, logoUrl: b.agency_logo } : null,
      joinedAgencyAt: b.joined_agency_at, totalDiamonds: String(total.diamonds), kycStatus: kyc,
      progress, config: configJson(cfg),
    },
  });
});

router.get('/broadcaster/statements', async (req, res) => {
  const r = await query(
    `SELECT h.*, p.period_key, p.starts_at, p.ends_at, u.username FROM host_statements h
     JOIN payout_periods p ON p.id = h.period_id JOIN users u ON u.id = h.user_id
     WHERE h.user_id = $1 ORDER BY p.starts_at DESC LIMIT 24`, [req.user.id],
  );
  res.json({ statements: r.rows.map(hostStatementJson) });
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
