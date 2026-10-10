import { query, tx } from '../database.js';
import { fail } from '../http.js';
import { periodBounds, parsePeriodKey, evaluateHost, commissionFor, nextCommissionTier } from '../settlement.js';

export async function loadConfig(run = query) {
  const s = (await run(`SELECT * FROM agency_settings WHERE id = 1`)).rows[0];
  const sal = (await run(`SELECT * FROM host_salary_tiers ORDER BY level`)).rows;
  const com = (await run(`SELECT * FROM agency_commission_tiers ORDER BY level`)).rows;
  return {
    settings: {
      cycle: s.cycle, penaltyBps: s.penalty_bps, requireOfficialEvents: s.require_official_events,
      minEventCount: s.min_event_count, currency: s.currency,
    },
    salaryTiers: sal.map((t) => ({ level: t.level, hours: t.required_hours, diamonds: BigInt(t.required_diamonds), salaryCents: BigInt(t.salary_cents) })),
    commissionTiers: com.map((t) => ({ level: t.level, minDiamonds: BigInt(t.min_team_diamonds), bps: t.commission_bps })),
  };
}

export const configJson = (cfg) => ({
  settings: cfg.settings,
  salaryTiers: cfg.salaryTiers.map((t) => ({ level: t.level, hours: t.hours, diamonds: String(t.diamonds), salaryCents: String(t.salaryCents) })),
  commissionTiers: cfg.commissionTiers.map((t) => ({ level: t.level, minDiamonds: String(t.minDiamonds), bps: t.bps })),
});

// Yayıncının dönem içindeki yayın süresi (sn) ve aldığı Diamond (kendine gönderilenler hariç).
// Yalnızca ONAYLI yayıncılar için ve yayıncı onayından SONRAKİ süre/hediyeler sayılır; yayıncı olmayan kullanıcı maaş hedefi biriktiremez
// (Diamond'larını yalnızca bozdurabilir). Ajansa katılma tarihi etkilemez.
export async function hostMetrics(userId, start, end, run = query) {
  const b = (await run(`SELECT approved_at FROM broadcasters WHERE user_id = $1 AND status = 'approved'`, [userId])).rows[0];
  if (!b) return { seconds: 0, diamonds: 0n };
  // approved_at boşsa (eski kayıt) dönem başı kullanılır.
  const from = b.approved_at && new Date(b.approved_at) > new Date(start) ? new Date(b.approved_at).toISOString() : start;
  const sec = (await run(
    `SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (LEAST(COALESCE(ended_at, NOW()), $3::timestamptz) - GREATEST(started_at, $2::timestamptz)))), 0)::bigint AS s
     FROM mic_sessions WHERE user_id = $1 AND started_at < $3::timestamptz AND COALESCE(ended_at, NOW()) > $2::timestamptz`,
    [userId, from, end],
  )).rows[0].s;
  const dia = (await run(
    `SELECT COALESCE(SUM(COALESCE(diamond_amount, coin_amount)), 0) AS d FROM gift_transactions
     WHERE receiver_id = $1 AND sender_id <> $1 AND created_at >= $2::timestamptz AND created_at < $3::timestamptz`,
    [userId, from, end],
  )).rows[0].d;
  return { seconds: Number(sec), diamonds: BigInt(dia) };
}

export async function teamDiamonds(agencyId, start, end, run = query) {
  const r = (await run(
    `SELECT COALESCE(SUM(COALESCE(diamond_amount, coin_amount)), 0) AS d FROM gift_transactions
     WHERE receiver_agency_id = $1 AND sender_id <> receiver_id AND created_at >= $2::timestamptz AND created_at < $3::timestamptz`,
    [agencyId, start, end],
  )).rows[0].d;
  return BigInt(r);
}

export async function eventCount(userId, start, end, run = query) {
  const r = await run(
    `SELECT COUNT(*)::int AS n FROM official_event_attendance a JOIN official_events e ON e.id = a.event_id
     WHERE a.user_id = $1 AND e.starts_at >= $2::timestamptz AND e.starts_at < $3::timestamptz`,
    [userId, start, end],
  );
  return r.rows[0].n;
}

export async function eventsOk(userId, cfg, start, end, run = query) {
  if (!cfg.settings.requireOfficialEvents) return true;
  return (await eventCount(userId, start, end, run)) >= cfg.settings.minEventCount;
}

// Yayıncının güncel dönem ilerlemesi (uygulamadaki "hedef" ekranı).
export async function hostProgress(userId, cfg, date = new Date(), run = query) {
  const b = periodBounds(cfg.settings.cycle, date);
  const m = await hostMetrics(userId, b.start, b.end, run);
  const evOk = await eventsOk(userId, cfg, b.start, b.end, run);
  const ev = await eventCount(userId, b.start, b.end, run);
  const r = evaluateHost({ tiers: cfg.salaryTiers, seconds: m.seconds, diamonds: m.diamonds, penaltyBps: cfg.settings.penaltyBps, eventsRequired: cfg.settings.requireOfficialEvents, eventsOk: evOk });
  const next = cfg.salaryTiers.find((t) => !r.tier || t.level > r.tier.level) ?? null;
  return {
    periodKey: b.key, cycle: b.cycle, startsAt: b.start, endsAt: b.end,
    seconds: m.seconds, diamonds: String(m.diamonds),
    tier: r.tier ? r.tier.level : null,
    estimatedCents: String(r.salaryCents), baseCents: String(r.baseCents), atRisk: r.penalty,
    hoursMet: r.hoursMet, eventsMet: r.eventsMet, eventCount: ev,
    requireOfficialEvents: cfg.settings.requireOfficialEvents, minEventCount: cfg.settings.minEventCount,
    next: next ? { level: next.level, hours: next.hours, diamonds: String(next.diamonds), salaryCents: String(next.salaryCents) } : null,
    currency: cfg.settings.currency,
  };
}

export const hostStatementJson = (x) => ({
  id: x.id, periodKey: x.period_key, startsAt: x.starts_at, endsAt: x.ends_at,
  userId: x.user_id, username: x.username, agencyId: x.agency_id,
  seconds: Number(x.seconds), diamonds: String(x.diamonds), tier: x.tier_level,
  baseSalaryCents: String(x.base_salary_cents), penaltyApplied: x.penalty_applied, salaryCents: String(x.salary_cents),
  eventsOk: x.events_ok, status: x.status, paidAt: x.paid_at,
});
export const agencyStatementJson = (x) => ({
  id: x.id, periodKey: x.period_key, startsAt: x.starts_at, endsAt: x.ends_at, agencyId: x.agency_id, agencyName: x.agency_name,
  teamDiamonds: String(x.team_diamonds), hostCount: x.host_count, commissionBps: x.commission_bps,
  commissionDiamonds: String(x.commission_diamonds), status: x.status, paidAt: x.paid_at,
});

// Dönemi kapatır: her aktif ajans ve onaylı yayıncı için hesap özeti oluşturur. Bitmemiş dönem force olmadan kapanmaz.
export async function closePeriod({ adminId, periodKey, force = false }) {
  const b = parsePeriodKey(periodKey);
  if (b.end > new Date() && !force) throw fail('Bu dönem henüz bitmedi.', 409);
  return tx(async (c) => {
    const run = (t, p) => c.query(t, p);
    await c.query(`SELECT pg_advisory_xact_lock(hashtext('payout_close'))`);
    if ((await c.query(`SELECT 1 FROM payout_periods WHERE period_key = $1`, [b.key])).rowCount) throw fail('Bu dönem zaten kapatılmış.', 409);
    // Aylık ve haftalık dönemler karışırsa aynı hediyeler/mikrofon süresi iki kez ödenmesin: zaman aralığı çakışması reddedilir.
    const overlap = (await c.query(
      `SELECT period_key FROM payout_periods WHERE starts_at < $2 AND ends_at > $1 LIMIT 1`, [b.start, b.end],
    )).rows[0];
    if (overlap) throw fail(`Bu dönem, kapatılmış ${overlap.period_key} dönemiyle çakışıyor; aynı kazanç iki kez ödenemez.`, 409);
    const cfg = await loadConfig(run);
    const p = (await c.query(
      `INSERT INTO payout_periods(period_key, cycle, starts_at, ends_at, closed_by, config) VALUES($1,$2,$3,$4,$5,$6) RETURNING id`,
      [b.key, b.cycle, b.start, b.end, adminId, JSON.stringify(configJson(cfg))],
    )).rows[0];

    const hosts = (await c.query(
      `SELECT b.user_id, b.agency_id FROM broadcasters b WHERE b.status = 'approved' AND b.agency_id IS NOT NULL`,
    )).rows;
    let totalSalary = 0n;
    for (const h of hosts) {
      const m = await hostMetrics(h.user_id, b.start, b.end, run);
      if (m.seconds === 0 && m.diamonds === 0n) continue;
      const evOk = await eventsOk(h.user_id, cfg, b.start, b.end, run);
      const r = evaluateHost({ tiers: cfg.salaryTiers, seconds: m.seconds, diamonds: m.diamonds, penaltyBps: cfg.settings.penaltyBps, eventsRequired: cfg.settings.requireOfficialEvents, eventsOk: evOk });
      totalSalary += r.salaryCents;
      await c.query(
        `INSERT INTO host_statements(period_id, user_id, agency_id, seconds, diamonds, tier_level, base_salary_cents, penalty_applied, salary_cents, events_ok)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
        [p.id, h.user_id, h.agency_id, m.seconds, m.diamonds.toString(), r.tier?.level ?? null, r.baseCents.toString(), r.penalty, r.salaryCents.toString(), evOk],
      );
    }
    const agencies = (await c.query(`SELECT id, commission_override_bps FROM agencies WHERE status = 'active'`)).rows;
    let agencyCount = 0;
    for (const a of agencies) {
      const team = await teamDiamonds(a.id, b.start, b.end, run);
      if (team === 0n) continue;
      const com = commissionFor(cfg.commissionTiers, team, a.commission_override_bps);
      const hc = (await c.query(`SELECT COUNT(*)::int AS n FROM host_statements WHERE period_id = $1 AND agency_id = $2`, [p.id, a.id])).rows[0].n;
      await c.query(
        `INSERT INTO agency_statements(period_id, agency_id, team_diamonds, host_count, commission_bps, commission_diamonds) VALUES($1,$2,$3,$4,$5,$6)`,
        [p.id, a.id, team.toString(), hc, com.bps, com.amount.toString()],
      );
      agencyCount += 1;
    }
    await c.query(
      `INSERT INTO financial_audit_logs(admin_id, action, reference_type, reference_id, metadata) VALUES($1,'payout_period_close','payout_period',$2,$3)`,
      [adminId, p.id, JSON.stringify({ periodKey: b.key, hosts: hosts.length, agencies: agencyCount, totalSalaryCents: totalSalary.toString() })],
    );
    return { periodId: p.id, periodKey: b.key, hostStatements: hosts.length, agencyStatements: agencyCount, totalSalaryCents: totalSalary.toString() };
  });
}

export { commissionFor, nextCommissionTier };
