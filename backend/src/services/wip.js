import { query } from '../database.js';

export const BASE_FEATURES = Object.freeze({
  nameColor: null, badge: null, maxRooms: 1, viewVisitors: false, vipGifts: false, muteImmunity: false, kickImmunity: false,
  profileEffect: false, customRoomTheme: false, invisibleVisit: false, animatedAvatar: false, ghostMode: false,
});

/** Bir ayrıcalığın açıldığı en düşük kademe (hata mesajlarında "WIP 6 ve üzeri" demek için; panelden değişebilir). */
export async function minLevelFor(feature, run = query) {
  const r = await run(`SELECT MIN(level) AS level FROM wip_tiers WHERE COALESCE((features->>$1)::boolean, FALSE)`, [feature]);
  return r.rows[0]?.level ?? null;
}

export const wipLabel = (level) => (level >= 11 ? 'SWIP' : `WIP ${level}`);

/** Ayrıcalık yoksa açıklayıcı hata (hangi kademede açıldığını söyler). */
export async function requireFeature(userId, feature, what) {
  if ((await featuresFor(userId))[feature]) return;
  const lvl = await minLevelFor(feature);
  const err = new Error(lvl ? `${what} ${wipLabel(lvl)} ve üzeri üyeliğe özeldir.` : `${what} şu an hiçbir WIP kademesinde açık değil.`);
  err.status = 403;
  throw err;
}

// run: (text, params) => Promise<{rows}>  (transaction içinde client.query kullanılabilir)
export async function activeWip(userId, run = query) {
  const r = await run(
    `SELECT uw.level, uw.starts_at, uw.expires_at, wt.name, wt.features
     FROM user_wip uw JOIN wip_tiers wt ON wt.level = uw.level
     WHERE uw.user_id = $1 AND uw.is_active = TRUE AND uw.expires_at > NOW()`,
    [userId],
  );
  const row = r.rows[0];
  if (!row) return null;
  return {
    level: row.level, name: row.name, startsAt: row.starts_at, expiresAt: row.expires_at,
    features: { ...BASE_FEATURES, ...row.features },
  };
}

export async function featuresFor(userId, run = query) {
  return (await activeWip(userId, run))?.features ?? { ...BASE_FEATURES };
}
