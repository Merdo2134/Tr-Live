import { query } from '../database.js';
import { HIDDEN_NAME, selfUser } from '../views.js';
import { BASE_FEATURES } from './wip.js';
import { presenceView } from './presence.js';

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
    `SELECT u.*, uw.level AS wip_level, uw.expires_at AS wip_expires_at, wt.name AS wip_name, wt.features AS wip_features, is_ghost(u.id) AS ghost,
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

  const [counts, following, friendRel, items, family, broadcaster, ownedAgency, blocked] = await Promise.all([
    query(
      `SELECT (SELECT COUNT(*)::int FROM follows WHERE followed_id = $1) AS followers,
              (SELECT COUNT(*)::int FROM follows WHERE follower_id = $1) AS following,
              (SELECT COUNT(*)::int FROM profile_visitors WHERE profile_user_id = $1) AS visitors,
              (SELECT COUNT(*)::int FROM friend_requests WHERE status = 'accepted' AND (requester_id = $1 OR target_id = $1)) AS friends`,
      [targetId],
    ),
    isSelf ? Promise.resolve({ rowCount: 0 }) : query(`SELECT 1 FROM follows WHERE follower_id = $1 AND followed_id = $2`, [viewerId, targetId]),
    isSelf ? Promise.resolve({ rows: [] }) : query(
      `SELECT requester_id, status FROM friend_requests
       WHERE (requester_id = $1 AND target_id = $2) OR (requester_id = $2 AND target_id = $1)`,
      [viewerId, targetId],
    ),
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
    // Engelleme ilişkisi varsa çevrimiçi durumu gösterilmez.
    isSelf ? Promise.resolve({ rowCount: 0 }) : query(
      `SELECT 1 FROM user_blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`,
      [viewerId, targetId],
    ),
  ]);

  const f = family.rows[0];
  const b = broadcaster.rows[0];
  const profile = {
    id: u.id,
    publicId: u.public_id ?? null,
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
    friends: counts.rows[0].friends,
    friendStatus: isSelf ? null : (() => {
      const rel = friendRel.rows[0];
      if (!rel) return 'none';
      if (rel.status === 'accepted') return 'friends';
      return rel.requester_id === viewerId ? 'requested' : 'incoming';
    })(),
    wip: u.wip_level ? {
      level: u.wip_level, name: u.wip_name, expiresAt: u.wip_expires_at,
      features: { ...BASE_FEATURES, ...u.wip_features },
    } : null,
    equipped: items,
    // Çevrimiçi / son görülme (kişi gizlemediyse). Kendi profilinde gösterilmez.
    presence: isSelf || blocked.rowCount ? null : presenceView(u),
    family: f ? { id: f.id, name: f.name, logoUrl: f.logo_url, level: f.level, role: f.role } : null,
    broadcaster: b && b.status === 'approved'
      ? { status: b.status, agency: b.agency_id ? { id: b.agency_id, name: b.agency_name, logoUrl: b.agency_logo } : null }
      : null,
  };

  if (isSelf) {
    const badge = await query(
      `SELECT (SELECT COUNT(*)::int FROM profile_visitors WHERE profile_user_id = $1 AND last_visited_at > $2) AS new_visitors,
              (SELECT COUNT(*)::int FROM follows WHERE followed_id = $1 AND created_at > $3) AS new_followers,
              (SELECT COUNT(*)::int FROM friend_requests WHERE target_id = $1 AND status = 'pending') AS friend_requests`,
      [targetId, u.visitors_seen_at, u.followers_seen_at],
    );
    Object.assign(profile, selfUser(u), {
      newVisitors: badge.rows[0].new_visitors, newFollowers: badge.rows[0].new_followers, friendRequests: badge.rows[0].friend_requests,
      followers: profile.followers, following: profile.following, visitorCount: counts.rows[0].visitors,
      broadcasterStatus: b?.status ?? null,
      agencyOwned: ownedAgency.rows[0] ? { id: ownedAgency.rows[0].id, name: ownedAgency.rows[0].name, status: ownedAgency.rows[0].status } : null,
      wip: profile.wip, equipped: items, family: profile.family, broadcaster: profile.broadcaster,
    });
  }
  return profile;
}
