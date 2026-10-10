// Kullanıcıyı dışarıya nasıl göstereceğimizi tek yerde toplar.
// Diğer kullanıcılara ASLA bakiye (coin/diamond) verilmez.
export const HIDDEN_NAME = 'Gizli Kullanıcı';

// "u" takma adlı users tablosu ile kullanılır.
export const USER_PUBLIC_COLUMNS = `u.id, u.username, u.public_id, u.display_name, u.avatar_url, u.is_hidden,
  u.coin_level, u.gift_level, uw.level AS wip_level, wt.features AS wip_features,
  (SELECT COALESCE(fr.image_url, fi.metadata->>'assetUrl') FROM inventory_items fi
     LEFT JOIN frames fr ON fr.id::text = fi.item_key
    WHERE fi.user_id = u.id AND fi.item_type = 'frame' AND fi.is_active = TRUE
      AND (fi.expires_at IS NULL OR fi.expires_at > NOW()) AND COALESCE(fi.metadata->>'equipped' = 'true', FALSE)
    ORDER BY fi.created_at DESC LIMIT 1) AS frame_url`;
export const USER_PUBLIC_JOINS = `LEFT JOIN user_wip uw ON uw.user_id = u.id AND uw.is_active = TRUE AND uw.expires_at > NOW()
  LEFT JOIN wip_tiers wt ON wt.level = uw.level`;

export function publicUser(row, viewerId = null) {
  if (!row) return null;
  const hidden = Boolean(row.is_hidden) && row.id !== viewerId;
  if (hidden) {
    return {
      id: row.id, publicId: null, username: HIDDEN_NAME, displayName: HIDDEN_NAME, avatarUrl: null,
      coinLevel: row.coin_level, giftLevel: row.gift_level, wipLevel: null, nameColor: null, frameUrl: null, isHidden: true,
    };
  }
  return {
    id: row.id,
    publicId: row.public_id ?? null,
    username: row.username,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    coinLevel: row.coin_level,
    giftLevel: row.gift_level,
    wipLevel: row.wip_level ?? null,
    nameColor: row.wip_features?.nameColor ?? null,
    frameUrl: row.frame_url ?? null,
    isHidden: Boolean(row.is_hidden),
  };
}

export function selfUser(row) {
  return {
    id: row.id,
    publicId: row.public_id ?? null,
    username: row.username,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    coverUrl: row.cover_url ?? null,
    bio: row.bio,
    language: row.language,
    gender: row.gender ?? null,
    birthDate: row.birth_date ? String(row.birth_date).slice(0, 10) : null,
    country: row.country ?? null,
    city: row.city ?? null,
    coins: String(row.coins),
    diamonds: String(row.diamonds),
    totalSentCoins: String(row.total_sent_coins),
    totalReceivedDiamonds: String(row.total_received_diamonds),
    coinLevel: row.coin_level,
    giftLevel: row.gift_level,
    isHidden: Boolean(row.is_hidden),
    whoCanDm: row.who_can_dm ?? 'everyone',
    showPresence: row.show_presence !== false,
    ghostMode: row.ghost_mode === true,
    chatRestrictedUntil: row.chat_restricted_until && new Date(row.chat_restricted_until) > new Date() ? row.chat_restricted_until : null,
    systemRole: row.system_role,
    kycStatus: row.kyc_status ?? 'none',
    createdAt: row.created_at,
  };
}
