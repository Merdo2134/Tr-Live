import { query } from '../database.js';

export const BASE_FEATURES = Object.freeze({
  nameColor: null, badge: null, maxRooms: 1, viewVisitors: false, kickImmunity: false, profileEffect: false, customRoomTheme: false,
});

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
