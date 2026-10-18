import { cpLevelFor } from './levels.js';

// Kullanıcıyı dışarıya nasıl göstereceğimizi tek yerde toplar.
// Diğer kullanıcılara ASLA bakiye (coin/diamond) verilmez.
export const HIDDEN_NAME = 'Gizli Kullanıcı';

// "u" takma adlı users tablosu ile kullanılır.
export const USER_PUBLIC_COLUMNS = `u.id, u.username, u.public_id, u.display_name, u.avatar_url, u.is_hidden, u.wip_hidden,
  u.coin_level, u.gift_level, u.created_at AS u_created_at, u.kyc_status AS u_kyc_status, uw.level AS wip_level, wt.features AS wip_features,
  (SELECT COALESCE(fr.image_url, fi.metadata->>'assetUrl') FROM inventory_items fi
     LEFT JOIN frames fr ON fr.id::text = fi.item_key
    WHERE fi.user_id = u.id AND fi.item_type = 'frame' AND fi.is_active = TRUE
      AND (fi.expires_at IS NULL OR fi.expires_at > NOW()) AND COALESCE(fi.metadata->>'equipped' = 'true', FALSE)
    ORDER BY fi.created_at DESC LIMIT 1) AS frame_url,
  u.cp_partner_id,
  (SELECT jsonb_object_agg(c.item_type, c.url) FROM (
     SELECT DISTINCT ON (ci.item_type) ci.item_type, ci.metadata->>'assetUrl' AS url FROM inventory_items ci
      WHERE ci.user_id = u.id AND ci.item_type IN ('chat_bubble', 'mic_wave', 'mini_card', 'room_card')
        AND ci.item_key NOT LIKE 'wip:%' AND ci.is_active = TRUE AND (ci.expires_at IS NULL OR ci.expires_at > NOW())
        AND COALESCE(ci.metadata->>'equipped' = 'true', FALSE) AND ci.metadata->>'assetUrl' IS NOT NULL
      ORDER BY ci.item_type, ci.created_at DESC) c) AS cosmetics,
  (SELECT jsonb_object_agg(wi.item_type, (wi.metadata->>'wipLevel')::int) FROM inventory_items wi
    WHERE wi.user_id = u.id AND wi.item_key LIKE 'wip:%' AND wi.is_active = TRUE
      AND (wi.expires_at IS NULL OR wi.expires_at > NOW()) AND COALESCE(wi.metadata->>'equipped' = 'true', FALSE)) AS wip_items,
  CASE WHEN u.cp_partner_id IS NULL THEN NULL ELSE (SELECT cp.exp FROM cp_pairs cp
    WHERE cp.user_a = LEAST(u.id, u.cp_partner_id) AND cp.user_b = GREATEST(u.id, u.cp_partner_id) AND cp.relation = 'cp') END AS cp_exp`;
export const USER_PUBLIC_JOINS = `LEFT JOIN user_wip uw ON uw.user_id = u.id AND uw.is_active = TRUE AND uw.expires_at > NOW()
  LEFT JOIN wip_tiers wt ON wt.level = uw.level`;

/** Takılı (ayrıca verilmiş) WIP öğesi; yoksa üyelik öğesi kapatıldıysa 0, değilse null (uygulama üyelik kademesini kullanır). */
const wipItem = (row, type) => row.wip_items?.[type] ?? (row.wip_hidden?.[type] === true ? 0 : null);

export function publicUser(row, viewerId = null) {
  if (!row) return null;
  // Gizli kullanıcı herkese — kendisine de — "Gizli Kullanıcı" görünür (odada, sohbette, listelerde tutarlı olsun;
  // kişi gizli modda olduğunu kendi koltuğundan da görür). Profil düzenleme kendi profil sayfasından yapılır.
  void viewerId;
  const hidden = Boolean(row.is_hidden);
  if (hidden) {
    return {
      id: row.id, publicId: null, username: HIDDEN_NAME, displayName: HIDDEN_NAME, avatarUrl: null,
      coinLevel: row.coin_level, giftLevel: row.gift_level, wipLevel: null, nameColor: null, frameUrl: null, isHidden: true,
      chatBubbleUrl: null, micWaveUrl: null, profileCardUrl: null, roomCardUrl: null,
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
    // Mağazadan alınıp takılan görünüm öğeleri: sohbet balonu, mikrofon dalgası, profil kartı, oda kartı.
    chatBubbleUrl: row.cosmetics?.chat_bubble ?? null,
    micWaveUrl: row.cosmetics?.mic_wave ?? null,
    profileCardUrl: row.cosmetics?.mini_card ?? null,
    roomCardUrl: row.cosmetics?.room_card ?? null,
    isHidden: Boolean(row.is_hidden),
    // Yönetimden ayrı verilen ve takılı WIP öğeleri (WIP üyeliğinden bağımsız): çerçeve, sohbet balonu, rozet, giriş efekti.
    // Kullanıcı üyeliğin verdiği öğeyi Görünüm'den çıkardıysa 0 gelir (uygulama 0'ı "yok" sayar, üyelik
    // kademesine geri düşmez).
    wipFrame: wipItem(row, 'frame'),
    wipBubble: wipItem(row, 'chat_bubble'),
    wipBadge: wipItem(row, 'badge'),
    wipEntrance: wipItem(row, 'entrance_effect'),
    // CP: odada yan yana oturunca kalp efekti için (yalnızca onaylı CP ilişkisi).
    cpPartnerId: row.cp_exp != null ? row.cp_partner_id : null,
    cpLevel: row.cp_exp != null ? cpLevelFor(row.cp_exp) : null,
    // Sohbette "yakın zamanda kayıt oldu" kartı (son 3 gün) ve "Doğrulanmış" rozeti.
    isNew: row.u_created_at ? Date.now() - new Date(row.u_created_at).getTime() < 3 * 86400e3 : false,
    verified: row.u_kyc_status === 'approved',
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
    phone: row.phone ?? null,
    // Google/Facebook ile açılan hesapların şifresi yoktur (silme onayı ve şifre belirleme buna göre).
    hasPassword: Boolean(row.password_hash),
    createdAt: row.created_at,
  };
}
