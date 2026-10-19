// Aile katkı değeri (🔥) ve seviyeler. Katkı: günlük giriş (kişi başı 20), yükleme (1 Coin = 1),
// gönderilen hediye (1 Coin = 1) ve alınan hediye (1 Elmas = 1). Katkı ailenin toplamına, üyenin toplamına ve
// üyenin haftalık katkısına yazılır. Aile seviyesi düşmez (yalnızca yükselir).
import { query } from '../database.js';
import { familyLevelFor, FAMILY_CASHBACK_BPS } from '../levels.js';

export const FAMILY_LOGIN_POINTS = 20n;
const TODAY = `(NOW() AT TIME ZONE 'Europe/Istanbul')::date`;
export const WEEK_DATE = `(date_trunc('week', NOW() AT TIME ZONE 'Europe/Istanbul'))::date`;

/** Kullanıcının ailesine katkı ekler. [run] bir işlem içinden çağrılabilir. Ailesi yoksa bir şey yapmaz. */
export async function addFamilyContrib(run, userId, points) {
  const p = BigInt(points ?? 0);
  if (!userId || p <= 0n) return null;
  const fam = (await run(
    `UPDATE families f SET total_points = f.total_points + $2
     FROM family_members fm WHERE fm.user_id = $1 AND fm.family_id = f.id AND f.is_active = TRUE
     RETURNING f.id, f.total_points, f.level`,
    [userId, p.toString()],
  )).rows[0];
  if (!fam) return null;
  await run(`UPDATE family_members SET total_contrib = total_contrib + $3 WHERE family_id = $1 AND user_id = $2`, [fam.id, userId, p.toString()]);
  await run(
    `INSERT INTO family_contrib_weekly(family_id, user_id, week_start, points) VALUES($1,$2,${WEEK_DATE},$3)
     ON CONFLICT (family_id, user_id, week_start) DO UPDATE SET points = family_contrib_weekly.points + EXCLUDED.points`,
    [fam.id, userId, p.toString()],
  );
  const lv = familyLevelFor(fam.total_points);
  if (lv > fam.level) await run(`UPDATE families SET level = $2 WHERE id = $1 AND level < $2`, [fam.id, lv]);
  return fam.id;
}

/**
 * Birden çok kişinin katkısı tek seferde (hediye işlemi): aile satırları id sırasıyla güncellenir ki aynı anda
 * yapılan hediyeler birbirini kilitlemesin. [entries]: [{ userId, points }]
 */
export async function addFamilyContribBatch(run, entries, leaderSpend = null) {
  const byUser = new Map();
  for (const e of entries) {
    const p = BigInt(e.points ?? 0);
    if (e.userId && p > 0n) byUser.set(e.userId, (byUser.get(e.userId) ?? 0n) + p);
  }
  // Başkan indirimi (gönderen bir aile başkanıysa harcamasının yüzdesi): aynı sıralı güncellemeye katılır.
  const spend = leaderSpend && BigInt(leaderSpend.coins ?? 0) > 0n
    ? (await run(`SELECT id, level FROM families WHERE owner_id = $1 AND is_active = TRUE`, [leaderSpend.userId])).rows[0] : null;
  if (!byUser.size && !spend) return;
  const mem = !byUser.size ? [] : (await run(
    `SELECT fm.user_id, fm.family_id FROM family_members fm JOIN families f ON f.id = fm.family_id AND f.is_active = TRUE
     WHERE fm.user_id = ANY($1::uuid[])`,
    [[...byUser.keys()]],
  )).rows;
  const byFamily = new Map();
  for (const m of mem) byFamily.set(m.family_id, (byFamily.get(m.family_id) ?? 0n) + byUser.get(m.user_id));
  if (spend && !byFamily.has(spend.id)) byFamily.set(spend.id, 0n);
  for (const famId of [...byFamily.keys()].sort()) {
    let spent = 0n; let cash = 0n;
    if (spend && spend.id === famId) {
      spent = BigInt(leaderSpend.coins);
      // leader_cashback 1/10000 Coin biriminde tutulur (küçük harcamalarda yuvarlanıp kaybolmasın).
      cash = spent * BigInt(FAMILY_CASHBACK_BPS[Math.min(Math.max(spend.level, 1), FAMILY_CASHBACK_BPS.length) - 1] ?? 0);
    }
    const f = (await run(
      `UPDATE families SET total_points = total_points + $2, leader_spent = leader_spent + $3, leader_cashback = leader_cashback + $4
       WHERE id = $1 RETURNING total_points, level`,
      [famId, byFamily.get(famId).toString(), spent.toString(), cash.toString()],
    )).rows[0];
    const lv = familyLevelFor(f.total_points);
    if (lv > f.level) await run(`UPDATE families SET level = $2 WHERE id = $1 AND level < $2`, [famId, lv]);
  }
  for (const m of [...mem].sort((a, b) => (a.user_id < b.user_id ? -1 : 1))) {
    const pts = byUser.get(m.user_id).toString();
    await run(`UPDATE family_members SET total_contrib = total_contrib + $3 WHERE family_id = $1 AND user_id = $2`, [m.family_id, m.user_id, pts]);
    await run(
      `INSERT INTO family_contrib_weekly(family_id, user_id, week_start, points) VALUES($1,$2,${WEEK_DATE},$3)
       ON CONFLICT (family_id, user_id, week_start) DO UPDATE SET points = family_contrib_weekly.points + EXCLUDED.points`,
      [m.family_id, m.user_id, pts],
    );
  }
}

/** Aile başkanının kişisel Coin harcaması: seviyeye göre yüzdesi indirim olarak birikir (1/10000 Coin biriminde). */
export async function addLeaderSpend(run, userId, coins) {
  const c = BigInt(coins ?? 0);
  if (!userId || c <= 0n) return;
  const f = (await run(`SELECT id, level FROM families WHERE owner_id = $1 AND is_active = TRUE`, [userId])).rows[0];
  if (!f) return;
  const bps = BigInt(FAMILY_CASHBACK_BPS[Math.min(Math.max(f.level, 1), FAMILY_CASHBACK_BPS.length) - 1] ?? 0);
  await run(
    `UPDATE families SET leader_spent = leader_spent + $2, leader_cashback = leader_cashback + $3 WHERE id = $1`,
    [f.id, c.toString(), (c * bps).toString()],
  );
}

/** Günlük giriş katkısı (uygulama açılınca, kişi başı günde bir kez). Hata asıl işlemi bozmaz. */
export async function familyDailyLogin(userId) {
  try {
    // Yalnızca ailesi varken günü işaretle (aynı gün sonradan aileye giren de puanını alsın).
    const r = await query(
      `INSERT INTO family_daily_login(user_id, day)
       SELECT $1, ${TODAY} WHERE EXISTS (
         SELECT 1 FROM family_members fm JOIN families f ON f.id = fm.family_id AND f.is_active = TRUE WHERE fm.user_id = $1)
       ON CONFLICT DO NOTHING RETURNING day`,
      [userId],
    );
    if (r.rowCount) await addFamilyContrib(query, userId, FAMILY_LOGIN_POINTS);
  } catch (error) {
    console.error('[aile] giriş katkısı:', error.message);
  }
}

export function startFamilyJanitor() {
  const run = () => query(`DELETE FROM family_daily_login WHERE day < (NOW() AT TIME ZONE 'Europe/Istanbul')::date - 3`).catch(() => {});
  setTimeout(run, 90e3).unref();
  const t = setInterval(run, 24 * 3600e3);
  t.unref();
  return t;
}
