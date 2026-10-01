import { query } from '../database.js';
import { HIDDEN_NAME, selfUser } from '../views.js';
import { BASE_FEATURES } from './wip.js';

export async function equippedItems(userId, run = query) {
  const r = await run(
    `SELECT i.id, i.item_type, i.item_key, i.item_name, i.expires_at, i.metadata,
            COALESCE(f.image_url, e.animation_url, i.metadata->>'assetUrl') AS asset_url
     FROM inventory_items i
     LEFT JOIN frames f ON i.item_type = 'frame' AND f.id::text = i.item_key
     LEFT JOIN entrance_effects e ON i.item_type = 'entrance_effect' AND e.id::text = i.item_key
     WHERE i.user_id = $1 AND i.is_active = TRUE AND (i.expires_at IS NULL OR i.expires_at > NOW())
       AND COALESCE(i.metadata->>'equipped' = 'true', FALSE)`,
    [userId],
  );
  return r.rows.map((x) => ({
    id: x.id, itemType: x.item_type, itemKey: x.item_key, itemName: x.item_name,
    expiresAt: x.expires_at, assetUrl: x.asset_url,
  }));
}

// Profil sayfası. Gizli kullanıcılar başkalarına yalnızca minimal bilgiyle görünür.
export async function loadProfile(viewerId, targetId) {
  const r = await query(
    `SELECT u.*, uw.level AS wip_level, uw.expires_at AS wip_expires_at, wt.name AS wip_name, wt.features AS wip_features,
            CASE WHEN u.birth_date IS NULL THEN NULL ELSE DATE_PART('year', AGE(u.birth_date))::int END AS age
     FROM users u
     LEFT JOIN user_wip uw ON uw.user_id = u.id AND uw.is_active = TRUE AND uw.expires_at > NOW()
     LEFT JOIN wip_tiers wt ON wt.level = uw.level
     WHERE u.id = $1`,
    [targetId],
  );
  const u = r.rows[0];
  if (!u || u.account_status === 'deleted') return null;
  const isSelf = viewerId === targetId;

  if (u.is_hidden && !isSelf) {
    return {
      id: u.id, isHidden: true, username: HIDDEN_NAME, displayName: HIDDEN_NAME, avatarUrl: null,
      coinLevel: u.coin_level, giftLevel: u.gift_level,
    };
  }

  const [counts, following, items, family, broadcaster, ownedAgency] = await Promise.all([
    query(
      `SELECT (SELECT COUNT(*)::int FROM follows WHERE followed_id = $1) AS followers,
              (SELECT COUNT(*)::int FROM follows WHERE follower_id = $1) AS following,
              (SELECT COUNT(*)::int FROM profile_visitors WHERE profile_user_id = $1) AS visitors`,
      [targetId],
    ),
    isSelf ? Promise.resolve({ rowCount: 0 }) : query(`SELECT 1 FROM follows WHERE follower_id = $1 AND followed_id = $2`, [viewerId, targetId]),
    equippedItems(targetId),
    query(
      `SELECT f.id, f.name, f.logo_url, f.level, fm.role FROM family_members fm
       JOIN families f ON f.id = fm.family_id AND f.is_active = TRUE WHERE fm.user_id = $1`,
      [targetId],
    ),
    query(
      `SELECT b.status, a.id AS agency_id, a.name AS agency_name, a.logo_url AS agency_logo
       FROM broadcasters b LEFT JOIN agencies a ON a.id = b.agency_id AND a.status = 'active' WHERE b.user_id = $1`,
      [targetId],
    ),
    isSelf ? query(`SELECT id, name, status FROM agencies WHERE owner_id = $1 AND status <> 'rejected'`, [targetId]) : Promise.resolve({ rows: [] }),
  ]);

  const f = family.rows[0];
  const b = broadcaster.rows[0];
  const profile = {
    id: u.id,
    username: u.username,
    displayName: u.display_name,
    avatarUrl: u.avatar_url,
    coverUrl: u.cover_url,
    bio: u.bio,
    gender: u.gender,
    age: u.age,
    country: u.country,
    city: u.city,
    coinLevel: u.coin_level,
    giftLevel: u.gift_level,
    createdAt: u.created_at,
    isHidden: Boolean(u.is_hidden),
    followers: counts.rows[0].followers,
    following: counts.rows[0].following,
    isFollowing: following.rowCount > 0,
    wip: u.wip_level ? {
      level: u.wip_level, name: u.wip_name, expiresAt: u.wip_expires_at,
      features: { ...BASE_FEATURES, ...u.wip_features },
    } : null,
    equipped: items,
    family: f ? { id: f.id, name: f.name, logoUrl: f.logo_url, level: f.level, role: f.role } : null,
    broadcaster: b && b.status === 'approved'
      ? { status: b.status, agency: b.agency_id ? { id: b.agency_id, name: b.agency_name, logoUrl: b.agency_logo } : null }
      : null,
  };

  if (isSelf) {
    Object.assign(profile, selfUser(u), {
      followers: profile.followers, following: profile.following, visitorCount: counts.rows[0].visitors,
      broadcasterStatus: b?.status ?? null,
      agencyOwned: ownedAgency.rows[0] ? { id: ownedAgency.rows[0].id, name: ownedAgency.rows[0].name, status: ownedAgency.rows[0].status } : null,
      wip: profile.wip, equipped: items, family: profile.family, broadcaster: profile.broadcaster,
    });
  }
  return profile;
}
