import { query } from '../database.js';
import { USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';

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
 * Odaya girişte oynayan efekt: mağazadan alınan **giriş aracı** (vehicle) ya da **özel giriş** (entrance_effect).
 * Takılı olan öne geçer; hiçbiri takılı değilse araç önceliklidir. Hiçbiri yoksa null (WIP şeridi ayrıca gösterilir).
 */
export async function activeEntranceEffect(userId, run = query) {
  const r = await run(
    `SELECT i.item_type, i.item_key, i.item_name, COALESCE(e.animation_url, i.metadata->>'assetUrl') AS animation_url, e.duration_ms
     FROM inventory_items i
     LEFT JOIN entrance_effects e ON i.item_type = 'entrance_effect' AND e.id::text = i.item_key AND e.is_active = TRUE
     WHERE i.user_id = $1 AND i.item_type IN ('entrance_effect', 'vehicle') AND i.is_active = TRUE
       AND (i.expires_at IS NULL OR i.expires_at > NOW())
     ORDER BY COALESCE(i.metadata->>'equipped' = 'true', FALSE) DESC, (i.item_type = 'vehicle') DESC, i.created_at DESC LIMIT 1`,
    [userId],
  );
  const row = r.rows[0];
  if (!row) return null;
  const vehicle = row.item_type === 'vehicle';
  return {
    kind: vehicle ? 'vehicle' : 'effect', itemKey: row.item_key, itemName: row.item_name, animationUrl: row.animation_url ?? null,
    durationMs: row.duration_ms ?? (vehicle ? 5000 : 4000),
  };
}
