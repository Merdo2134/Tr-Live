import { query } from '../database.js';
import { USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS, publicUser } from '../views.js';
import { hub } from '../realtime.js';
import { isGhost } from './presence.js';

export async function loadPublicRow(id, run = query) {
  const r = await run(`SELECT ${USER_PUBLIC_COLUMNS} FROM users u ${USER_PUBLIC_JOINS} WHERE u.id = $1`, [id]);
  return r.rows[0] || null;
}

export async function loadPublicRows(ids, run = query) {
  if (!ids.length) return [];
  const r = await run(`SELECT ${USER_PUBLIC_COLUMNS} FROM users u ${USER_PUBLIC_JOINS} WHERE u.id = ANY($1::uuid[])`, [ids]);
  return r.rows;
}

/**
 * Odaya girişte oynayan efekt: mağazadan alınan **giriş aracı** (vehicle) ya da **özel giriş** (entrance_effect),
 * ayrıca verilmiş ya da WIP üyeliğinin verdiği **WIP aracı** (kodla çizilir: kind 'wip_vehicle').
 * Sıra: takılı öğe → WIP üyelik aracı (kullanıcı kapatmadıysa) → takılı olmayan mağaza öğesi. Hiçbiri yoksa null.
 */
export async function activeEntranceEffect(userId, run = query) {
  const r = await run(
    `SELECT i.item_type, i.item_key, i.item_name, COALESCE(e.animation_url, i.metadata->>'assetUrl') AS animation_url, e.duration_ms,
            (i.metadata->>'wipLevel')::int AS wip_level, COALESCE(i.metadata->>'equipped' = 'true', FALSE) AS equipped
     FROM inventory_items i
     LEFT JOIN entrance_effects e ON i.item_type = 'entrance_effect' AND e.id::text = i.item_key AND e.is_active = TRUE
     WHERE i.user_id = $1 AND i.item_type IN ('entrance_effect', 'vehicle') AND i.is_active = TRUE
       AND (i.item_key NOT LIKE 'wip:%' OR i.item_type = 'vehicle')
       AND (i.expires_at IS NULL OR i.expires_at > NOW())
     ORDER BY COALESCE(i.metadata->>'equipped' = 'true', FALSE) DESC, (i.item_type = 'vehicle') DESC, i.created_at DESC LIMIT 1`,
    [userId],
  );
  const row = r.rows[0];
  const fromRow = (x) => {
    if (x.item_key.startsWith('wip:')) {
      const level = x.wip_level ?? Number(x.item_key.slice(4));
      return { kind: 'wip_vehicle', level, itemKey: x.item_key, itemName: x.item_name, animationUrl: null, durationMs: 4600 };
    }
    const vehicle = x.item_type === 'vehicle';
    return {
      kind: vehicle ? 'vehicle' : 'effect', itemKey: x.item_key, itemName: x.item_name, animationUrl: x.animation_url ?? null,
      durationMs: x.duration_ms ?? (vehicle ? 5000 : 4000),
    };
  };
  // Takılı araç her şeyden önce gelir; takılı özel giriş efekti ise üyelik aracından sonra.
  if (row?.equipped && row.item_type === 'vehicle') return fromRow(row);
  // WIP üyeliğinin aracı (Görünüm'den kapatılmadıysa).
  const w = (await run(
    `SELECT uw.level, u.wip_hidden FROM users u
     JOIN user_wip uw ON uw.user_id = u.id AND uw.is_active = TRUE AND uw.expires_at > NOW() WHERE u.id = $1`,
    [userId],
  )).rows[0];
  if (w?.level && w.wip_hidden?.vehicle !== true) {
    return { kind: 'wip_vehicle', level: w.level, itemKey: `wip:${w.level}`, itemName: null, animationUrl: null, durationMs: 4600 };
  }
  return row ? fromRow(row) : null;
}

/**
 * Kullanıcının görünümü değişince (çerçeve, balon, mikrofon dalgası, fotoğraf…) bulunduğu odalara anında bildirir;
 * odadakiler çıkıp girmeden yeni görünümü görür. Hata olursa sessizce geçer (asıl işlemi bozmaz).
 */
export async function announceUserChange(userId) {
  try {
    if (await isGhost(userId)) return;
    const rooms = (await query(`SELECT room_id FROM room_members WHERE user_id = $1`, [userId])).rows;
    if (!rooms.length) return;
    const row = await loadPublicRow(userId);
    if (!row) return;
    const user = publicUser(row, null);
    for (const r of rooms) hub.broadcastRoom(r.room_id, { type: 'room_member_updated', roomId: r.room_id, user });
  } catch (error) {
    console.error('[görünüm] odalara bildirilemedi:', error.message);
  }
}

/** Yeni verilen/alınan öğe: o türden takılı bir öğe yoksa kendiliğinden takılır (kullanıcı ayrıca uğraşmasın). */
export async function equipIfNone(run, userId, itemType, itemId) {
  await run(
    `UPDATE inventory_items SET metadata = COALESCE(metadata, '{}'::jsonb) || '{"equipped": true}'::jsonb
     WHERE id = $1 AND NOT EXISTS (
       SELECT 1 FROM inventory_items o WHERE o.user_id = $2 AND o.item_type = $3 AND o.id <> $1 AND o.is_active = TRUE
         AND (o.expires_at IS NULL OR o.expires_at > NOW()) AND COALESCE(o.metadata->>'equipped' = 'true', FALSE))`,
    [itemId, userId, itemType],
  );
}
