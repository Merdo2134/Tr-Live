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

// Kullanıcının aktif giriş efekti: önce seçili (equipped) olan, yoksa en yenisi.
export async function activeEntranceEffect(userId, run = query) {
  const r = await run(
    `SELECT i.item_key, i.item_name, e.animation_url, e.duration_ms
     FROM inventory_items i
     LEFT JOIN entrance_effects e ON e.id::text = i.item_key AND e.is_active = TRUE
     WHERE i.user_id = $1 AND i.item_type = 'entrance_effect' AND i.is_active = TRUE
       AND (i.expires_at IS NULL OR i.expires_at > NOW())
     ORDER BY COALESCE(i.metadata->>'equipped' = 'true', FALSE) DESC, i.created_at DESC LIMIT 1`,
    [userId],
  );
  const row = r.rows[0];
  if (!row) return null;
  return { itemKey: row.item_key, itemName: row.item_name, animationUrl: row.animation_url, durationMs: row.duration_ms ?? 4000 };
}
