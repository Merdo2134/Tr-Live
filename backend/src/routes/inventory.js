import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { fail, uuid } from '../http.js';

export const router = Router();
router.use(requireAuth);

const ITEM_SELECT = `SELECT i.id, i.item_type, i.item_key, i.item_name, i.quantity, i.expires_at, i.created_at,
    COALESCE(i.metadata->>'equipped' = 'true', FALSE) AS equipped,
    COALESCE(f.image_url, e.animation_url, i.metadata->>'assetUrl') AS asset_url
  FROM inventory_items i
  LEFT JOIN frames f ON i.item_type = 'frame' AND f.id::text = i.item_key
  LEFT JOIN entrance_effects e ON i.item_type = 'entrance_effect' AND e.id::text = i.item_key`;

const view = (x) => ({
  id: x.id, itemType: x.item_type, itemKey: x.item_key, itemName: x.item_name, quantity: x.quantity,
  expiresAt: x.expires_at, equipped: x.equipped, assetUrl: x.asset_url,
});

router.get('/', async (req, res) => {
  const r = await query(
    `${ITEM_SELECT} WHERE i.user_id = $1 AND i.is_active = TRUE AND (i.expires_at IS NULL OR i.expires_at > NOW())
     ORDER BY i.created_at DESC`,
    [req.user.id],
  );
  res.json({ items: r.rows.map(view) });
});

async function setEquipped(userId, itemId, equipped) {
  await tx(async (c) => {
    await c.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [userId]); // aynı kullanıcının eşzamanlı işlemlerini sıraya sokar
    const item = (await c.query(
      `SELECT id, item_type FROM inventory_items WHERE id = $1 AND user_id = $2 AND is_active = TRUE
         AND (expires_at IS NULL OR expires_at > NOW())`,
      [itemId, userId],
    )).rows[0];
    if (!item) throw fail('Envanter öğesi bulunamadı.', 404);
    if (equipped) {
      await c.query(
        `UPDATE inventory_items SET metadata = COALESCE(metadata, '{}'::jsonb) || '{"equipped": false}'::jsonb
         WHERE user_id = $1 AND item_type = $2`,
        [userId, item.item_type],
      );
    }
    await c.query(
      `UPDATE inventory_items SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('equipped', $2::boolean) WHERE id = $1`,
      [item.id, equipped],
    );
  });
}

router.post('/equip', async (req, res) => {
  await setEquipped(req.user.id, uuid(req.body?.itemId, 'Öğe'), true);
  res.json({ ok: true });
});

router.post('/unequip', async (req, res) => {
  await setEquipped(req.user.id, uuid(req.body?.itemId, 'Öğe'), false);
  res.json({ ok: true });
});

router.get('/catalog/frames', async (req, res) => {
  const r = await query(`SELECT id, name, image_url FROM frames WHERE is_active = TRUE ORDER BY name`);
  res.json({ frames: r.rows.map((x) => ({ id: x.id, name: x.name, imageUrl: x.image_url })) });
});

router.get('/catalog/entrance-effects', async (req, res) => {
  const r = await query(`SELECT id, name, animation_url, duration_ms FROM entrance_effects WHERE is_active = TRUE ORDER BY name`);
  res.json({ effects: r.rows.map((x) => ({ id: x.id, name: x.name, animationUrl: x.animation_url, durationMs: x.duration_ms })) });
});
