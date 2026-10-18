import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { fail, uuid } from '../http.js';
import { announceUserChange } from '../services/users.js';
import { wipLabel } from '../services/wip.js';

// WIP üyeliğinin verdiği görünüm öğeleri: Görünüm sayfasında ayrı ayrı takılıp çıkarılabilir.
const WIP_KINDS = { vehicle: 'aracı', frame: 'çerçevesi', chat_bubble: 'sohbet balonu', entrance_effect: 'giriş efekti', badge: 'rozeti' };
const WIP_ITEM_RE = /^wip-(vehicle|frame|chat_bubble|entrance_effect|badge)$/;

export const router = Router();
router.use(requireAuth);

const ITEM_SELECT = `SELECT i.id, i.item_type, i.item_key, i.item_name, i.quantity, i.expires_at, i.created_at,
    COALESCE(i.metadata->>'equipped' = 'true', FALSE) AS equipped, (i.metadata->>'wipLevel')::int AS wip_level,
    COALESCE(f.image_url, e.animation_url, i.metadata->>'assetUrl') AS asset_url
  FROM inventory_items i
  LEFT JOIN frames f ON i.item_type = 'frame' AND f.id::text = i.item_key
  LEFT JOIN entrance_effects e ON i.item_type = 'entrance_effect' AND e.id::text = i.item_key`;

const view = (x) => ({
  id: x.id, itemType: x.item_type, itemKey: x.item_key, itemName: x.item_name, quantity: x.quantity,
  expiresAt: x.expires_at, equipped: x.equipped, assetUrl: x.asset_url,
  wipLevel: x.wip_level ?? (String(x.item_key).startsWith('wip:') ? Number(String(x.item_key).slice(4)) || null : null),
});

router.get('/', async (req, res) => {
  const r = await query(
    `${ITEM_SELECT} WHERE i.user_id = $1 AND i.is_active = TRUE AND (i.expires_at IS NULL OR i.expires_at > NOW())
     ORDER BY i.created_at DESC`,
    [req.user.id],
  );
  const items = r.rows.map(view);
  // WIP üyeliği varsa her öğesi (araç, çerçeve, balon, giriş efekti, rozet) ayrı bir satır olarak eklenir.
  // Takılı sayılır: kullanıcı kapatmadıysa ve aynı türden başka takılı öğe yoksa.
  const w = (await query(
    `SELECT uw.level, uw.expires_at, u.wip_hidden FROM users u
     JOIN user_wip uw ON uw.user_id = u.id AND uw.is_active = TRUE AND uw.expires_at > NOW() WHERE u.id = $1`,
    [req.user.id],
  )).rows[0];
  if (w?.level) {
    for (const [type, kind] of Object.entries(WIP_KINDS)) {
      items.unshift({
        id: `wip-${type}`, itemType: type, itemKey: `wip:${w.level}`, itemName: `${wipLabel(w.level)} ${kind}`, quantity: 1,
        expiresAt: w.expires_at, assetUrl: null, wipLevel: w.level, membership: true,
        equipped: w.wip_hidden?.[type] !== true && !items.some((i) => i.itemType === type && i.equipped),
      });
    }
  }
  res.json({ items });
});

/** WIP üyelik öğesi: takınca aynı türdeki diğer öğeler çıkarılır; çıkarınca kullanıcıda kapalı olarak işaretlenir. */
async function setWipEquipped(userId, type, equipped) {
  await tx(async (c) => {
    await c.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [userId]);
    if (equipped) {
      const w = await c.query(`SELECT 1 FROM user_wip WHERE user_id = $1 AND is_active = TRUE AND expires_at > NOW()`, [userId]);
      if (!w.rowCount) throw fail('WIP üyeliğiniz yok veya süresi dolmuş.', 404);
      await c.query(
        `UPDATE inventory_items SET metadata = COALESCE(metadata, '{}'::jsonb) || '{"equipped": false}'::jsonb WHERE user_id = $1 AND item_type = $2`,
        [userId, type],
      );
      await c.query(`UPDATE users SET wip_hidden = wip_hidden - $2::text WHERE id = $1`, [userId, type]);
    } else {
      await c.query(`UPDATE users SET wip_hidden = wip_hidden || jsonb_build_object($2::text, true) WHERE id = $1`, [userId, type]);
    }
  });
}

/** İstekteki öğe: WIP üyelik öğesi ("wip-frame" gibi) ya da envanter kimliği. */
async function toggle(req, equipped) {
  const raw = String(req.body?.itemId ?? '');
  const m = WIP_ITEM_RE.exec(raw);
  if (m) await setWipEquipped(req.user.id, m[1], equipped);
  else await setEquipped(req.user.id, uuid(raw, 'Öğe'), equipped);
}

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
  await toggle(req, true);
  res.json({ ok: true });
  announceUserChange(req.user.id);
});

router.post('/unequip', async (req, res) => {
  await toggle(req, false);
  res.json({ ok: true });
  announceUserChange(req.user.id);
});

router.get('/catalog/frames', async (req, res) => {
  const r = await query(`SELECT id, name, image_url FROM frames WHERE is_active = TRUE ORDER BY name`);
  res.json({ frames: r.rows.map((x) => ({ id: x.id, name: x.name, imageUrl: x.image_url })) });
});

router.get('/catalog/entrance-effects', async (req, res) => {
  const r = await query(`SELECT id, name, animation_url, duration_ms FROM entrance_effects WHERE is_active = TRUE ORDER BY name`);
  res.json({ effects: r.rows.map((x) => ({ id: x.id, name: x.name, animationUrl: x.animation_url, durationMs: x.duration_ms })) });
});
