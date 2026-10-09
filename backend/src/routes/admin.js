import { Router } from 'express';
import express from 'express';
import { query, tx } from '../database.js';
import { requireAuth, requireStaff, requireSuperAdmin } from '../auth.js';
import { supportMayCall, banEnd, mayActOnUser } from '../staff_logic.js';
import { fail, uuid, bigAmount, positiveInt, text, oneOf, httpsUrl, assetUrl } from '../http.js';
import { validateAgencyConfig } from '../agency_config.js';
import { loadConfig, configJson, closePeriod, hostStatementJson, agencyStatementJson } from '../services/payouts.js';
import { parsePeriodKey, previousPeriod } from '../settlement.js';
import { ensureAgencyCode } from './agencies.js';
import { WIP_MIN_LEVEL, WIP_MAX_LEVEL } from '../levels.js';
import { dealerSell } from '../services/dealers.js';
import { hub } from '../realtime.js';
import { banIpPersist, unbanIp, listBans, securityStats } from '../firewall.js';
import net from 'node:net';
import { saveUpload, removeUpload, IMAGE_TYPES } from '../services/images.js';
import { detectMedia, ensureVapc, mimeFor, MEDIA_MAX_BYTES } from '../services/media.js';

export const router = Router();
router.use(requireAuth, requireStaff);
// Yardımcı admin ('support') yalnızca dar yetkilere sahiptir (nick, profil fotoğrafı, ban). Diğer her şey yöneticiye aittir.
router.use((req, res, next) => {
  if (req.user.system_role === 'admin') return next();
  if (supportMayCall(req.method, req.path)) return next();
  next(fail('Bu işlem yalnızca yöneticiye aittir.', 403));
});

router.get('/me/permissions', (req, res) => {
  const admin = req.user.system_role === 'admin';
  res.json({ role: req.user.system_role, full: admin, can: admin ? ['all'] : ['search_users', 'ban', 'unban', 'change_display_name', 'change_avatar'] });
});

const INVENTORY_TYPES = ['frame', 'entrance_effect', 'badge', 'profile_effect'];
const wipLevel = (v) => {
  const n = positiveInt(v, 'WIP seviyesi');
  if (n < WIP_MIN_LEVEL || n > WIP_MAX_LEVEL) throw fail(`WIP seviyesi ${WIP_MIN_LEVEL}-${WIP_MAX_LEVEL} arasında olmalı.`);
  return n;
};

async function assertUser(id, run = query) {
  const u = (await run(`SELECT id, username, system_role, account_status FROM users WHERE id = $1`, [id])).rows[0];
  if (!u) throw fail('Kullanıcı bulunamadı.', 404);
  return u;
}

// ---------------- Kullanıcı arama ve durum ----------------
router.get('/users', async (req, res) => {
  const q = String(req.query.q ?? '').trim().toLowerCase();
  if (q.length < 2) throw fail('Arama için en az 2 karakter girin.');
  const r = await query(
    `SELECT id, username, display_name, avatar_url, coins, diamonds, system_role, account_status, banned_until, ban_reason
     FROM users WHERE lower(username) LIKE $1 ESCAPE '\\' OR lower(display_name) LIKE $1 ESCAPE '\\' OR id::text = $2
     ORDER BY username LIMIT 20`,
    [`%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`, q],
  );
  res.json({
    users: r.rows.map((u) => ({
      id: u.id, username: u.username, displayName: u.display_name, coins: String(u.coins), diamonds: String(u.diamonds),
      systemRole: u.system_role, accountStatus: u.account_status, avatarUrl: u.avatar_url, bannedUntil: u.banned_until, banReason: u.ban_reason,
      ...(req.user.system_role === 'admin' ? {} : { coins: undefined, diamonds: undefined }),
    })),
  });
});

async function auditStaff(c, adminId, userId, action, meta) {
  await c.query(
    `INSERT INTO financial_audit_logs(admin_id, user_id, action, reference_type, metadata) VALUES($1,$2,$3,'user',$4)`,
    [adminId, userId, action, JSON.stringify(meta)],
  );
}

// Süreli veya süresiz ban. hours yoksa/0 ise süresiz.
router.post('/users/:userId/ban', async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  if (userId === req.user.id) throw fail('Kendinizi banlayamazsınız.');
  const target = await assertUser(userId);
  if (target.account_status === 'deleted') throw fail('Silinmiş hesap değiştirilemez.', 409);
  if (!mayActOnUser(req.user.system_role, target.system_role)) throw fail('Bu hesap üzerinde işlem yetkiniz yok.', 403);
  const until = banEnd(req.body?.hours);
  if (until === undefined) throw fail('Süre 1 saat ile 1 yıl arasında olmalı (süresiz için boş bırakın).');
  const reason = text(req.body?.reason, 'Neden', { max: 300 });
  await tx(async (c) => {
    await c.query(
      `UPDATE users SET account_status = 'banned', banned_until = $2, ban_reason = $3, banned_by = $4, token_version = token_version + 1, updated_at = NOW() WHERE id = $1`,
      [userId, until, reason, req.user.id],
    );
    await auditStaff(c, req.user.id, userId, 'account_ban', { until, reason, by: req.user.system_role });
  });
  hub.disconnectUser(userId, 'banned');
  res.json({ ok: true, status: 'banned', bannedUntil: until });
});

router.post('/users/:userId/unban', async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  const target = await assertUser(userId);
  if (!mayActOnUser(req.user.system_role, target.system_role)) throw fail('Bu hesap üzerinde işlem yetkiniz yok.', 403);
  if (target.account_status !== 'banned') throw fail('Hesap banlı değil.', 409);
  await tx(async (c) => {
    await c.query(`UPDATE users SET account_status = 'active', banned_until = NULL, ban_reason = NULL, banned_by = NULL, updated_at = NOW() WHERE id = $1`, [userId]);
    await auditStaff(c, req.user.id, userId, 'account_unban', { by: req.user.system_role });
  });
  res.json({ ok: true, status: 'active' });
});

// Kullanıcının görünen adını (nick) değiştirir. Yasaklı kelime denetimi uygulanmaz (yetkili işlemi) ama uzunluk denetlenir.
router.post('/users/:userId/display-name', async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  const name = text(req.body?.displayName, 'Görünen ad', { min: 2, max: 40, required: true });
  const target = await assertUser(userId);
  if (target.account_status === 'deleted') throw fail('Silinmiş hesap değiştirilemez.', 409);
  if (!mayActOnUser(req.user.system_role, target.system_role)) throw fail('Bu hesap üzerinde işlem yetkiniz yok.', 403);
  await tx(async (c) => {
    const before = (await c.query(`SELECT display_name FROM users WHERE id = $1`, [userId])).rows[0]?.display_name;
    await c.query(`UPDATE users SET display_name = $2, updated_at = NOW() WHERE id = $1`, [userId, name]);
    await auditStaff(c, req.user.id, userId, 'profile_display_name', { before, after: name, by: req.user.system_role });
  });
  res.json({ ok: true, displayName: name });
});

// Profil fotoğrafını kaldırır (avatarUrl boş) veya https adresiyle değiştirir.
router.post('/users/:userId/avatar', async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  const url = httpsUrl(req.body?.avatarUrl, 'Fotoğraf adresi');
  const target = await assertUser(userId);
  if (target.account_status === 'deleted') throw fail('Silinmiş hesap değiştirilemez.', 409);
  if (!mayActOnUser(req.user.system_role, target.system_role)) throw fail('Bu hesap üzerinde işlem yetkiniz yok.', 403);
  await tx(async (c) => {
    await c.query(`UPDATE users SET avatar_url = $2, updated_at = NOW() WHERE id = $1`, [userId, url]);
    await auditStaff(c, req.user.id, userId, 'profile_avatar', { removed: !url, by: req.user.system_role });
  });
  res.json({ ok: true, avatarUrl: url });
});

// Yardımcı admin atama/alma: yalnızca yönetici, admin panelinden.
router.post('/users/:userId/staff-role', requireSuperAdmin, async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  const role = oneOf(req.body?.role, ['user', 'support'], 'Rol');
  if (userId === req.user.id) throw fail('Kendi rolünüzü değiştiremezsiniz.');
  const target = await assertUser(userId);
  if (target.system_role === 'admin') throw fail('Yönetici rolü buradan değiştirilemez.', 403);
  if (target.account_status !== 'active') throw fail('Yalnızca aktif hesaplara yetki verilebilir.', 409);
  await tx(async (c) => {
    await c.query(`UPDATE users SET system_role = $2, updated_at = NOW() WHERE id = $1`, [userId, role]);
    await auditStaff(c, req.user.id, userId, 'staff_role', { role });
  });
  res.json({ ok: true, role });
});

router.get('/staff', requireSuperAdmin, async (req, res) => {
  const r = await query(`SELECT id, username, display_name, system_role FROM users WHERE system_role IN ('support','admin') ORDER BY system_role, username`);
  res.json({ staff: r.rows.map((u) => ({ id: u.id, username: u.username, displayName: u.display_name, systemRole: u.system_role })) });
});

// ---------------- Coin (yalnızca yönetici) ----------------
router.post('/users/:userId/coins', requireSuperAdmin, async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  const delta = bigAmount(req.body?.amount, 'Coin miktarı', { allowNegative: true });
  const reason = text(req.body?.reason, 'Neden', { max: 300 }) || 'Admin Coin düzenlemesi';
  const result = await tx(async (c) => {
    const user = (await c.query(`SELECT coins FROM users WHERE id = $1 AND account_status = 'active' FOR UPDATE`, [userId])).rows[0];
    if (!user) throw fail('Kullanıcı bulunamadı.', 404);
    const before = BigInt(user.coins);
    const after = before + delta;
    if (after < 0n) throw fail('Bakiye negatife düşemez.');
    await c.query(`UPDATE users SET coins = $1, updated_at = NOW() WHERE id = $2`, [after.toString(), userId]);
    await c.query(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, description) VALUES($1,'admin_adjustment',$2,$3)`,
      [userId, delta.toString(), reason],
    );
    await c.query(
      `INSERT INTO financial_audit_logs(admin_id, user_id, action, reference_type, amount_coins, balance_before, balance_after, metadata)
       VALUES($1,$2,'admin_coin_adjustment','user',$3,$4,$5,$6)`,
      [req.user.id, userId, delta.toString(), before.toString(), after.toString(), JSON.stringify({ reason })],
    );
    return { before: before.toString(), after: after.toString() };
  });
  res.json(result);
});

// ---------------- WIP ----------------
router.post('/users/:userId/wip', async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  const level = wipLevel(req.body?.level);
  const days = positiveInt(req.body?.days, 'WIP süresi', 3650);
  await assertUser(userId);
  const r = await query(
    `INSERT INTO user_wip(user_id, level, starts_at, expires_at, is_active)
     VALUES($1,$2,NOW(),NOW() + ($3::int * INTERVAL '1 day'),TRUE)
     ON CONFLICT (user_id) DO UPDATE SET level = EXCLUDED.level, starts_at = EXCLUDED.starts_at, expires_at = EXCLUDED.expires_at, is_active = TRUE
     RETURNING level, starts_at, expires_at`,
    [userId, level, days],
  );
  await query(
    `INSERT INTO financial_audit_logs(admin_id, user_id, action, reference_type, metadata) VALUES($1,$2,'admin_wip_grant','wip',$3)`,
    [req.user.id, userId, JSON.stringify({ level, days })],
  );
  res.json({ wip: r.rows[0] });
});

router.delete('/users/:userId/wip', async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  await query(`UPDATE user_wip SET is_active = FALSE WHERE user_id = $1`, [userId]);
  await query(`INSERT INTO financial_audit_logs(admin_id, user_id, action, reference_type) VALUES($1,$2,'admin_wip_revoke','wip')`, [req.user.id, userId]);
  res.json({ ok: true });
});

const FEATURE_TYPES = { nameColor: 'color', badge: 'string', maxRooms: 'int', viewVisitors: 'bool', kickImmunity: 'bool', profileEffect: 'bool', customRoomTheme: 'bool' };
function cleanFeatures(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw fail('Özellikler nesne olmalı.');
  const out = {};
  for (const [key, value] of Object.entries(input)) {
    const type = FEATURE_TYPES[key];
    if (!type) throw fail(`Bilinmeyen özellik: ${key}`);
    if (type === 'bool' && typeof value !== 'boolean') throw fail(`${key} true/false olmalı.`);
    if (type === 'int' && (!Number.isInteger(value) || value < 1 || value > 50)) throw fail(`${key} 1-50 arasında tam sayı olmalı.`);
    if (type === 'color' && value !== null && !/^#[0-9a-fA-F]{6}$/.test(String(value))) throw fail(`${key} #RRGGBB olmalı.`);
    if (type === 'string' && value !== null && (typeof value !== 'string' || value.length > 40)) throw fail(`${key} geçersiz.`);
    out[key] = value;
  }
  return out;
}

router.patch('/wip/tiers/:level', requireSuperAdmin, async (req, res) => {
  const level = wipLevel(Number(req.params.level));
  const name = req.body?.name !== undefined ? text(req.body.name, 'Ad', { min: 2, max: 60, required: true }) : null;
  const features = req.body?.features !== undefined ? cleanFeatures(req.body.features) : null;
  if (name === null && features === null) throw fail('Değiştirilecek alan yok.');
  const r = await query(
    `UPDATE wip_tiers SET name = COALESCE($2, name), features = features || COALESCE($3::jsonb, '{}'::jsonb) WHERE level = $1 RETURNING level, name, features`,
    [level, name, features ? JSON.stringify(features) : null],
  );
  res.json({ tier: r.rows[0] });
});

router.post('/wip/plans', requireSuperAdmin, async (req, res) => {
  const r = await query(
    `INSERT INTO wip_plans(name, level, duration_days, price_coins) VALUES($1,$2,$3,$4) RETURNING id, name, level, duration_days, price_coins`,
    [text(req.body?.name, 'Ad', { min: 2, max: 100, required: true }), wipLevel(req.body?.level),
      positiveInt(req.body?.durationDays, 'Süre', 3650), bigAmount(req.body?.priceCoins, 'Fiyat').toString()],
  );
  res.status(201).json({ plan: r.rows[0] });
});

// ---------------- Envanter ----------------
router.post('/users/:userId/inventory', async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  const itemType = oneOf(req.body?.itemType, INVENTORY_TYPES, 'Öğe tipi');
  const itemKey = text(req.body?.itemKey, 'Öğe anahtarı', { max: 100, required: true });
  const itemName = text(req.body?.itemName, 'Öğe adı', { max: 120, required: true });
  await assertUser(userId);
  if (itemType === 'frame' || itemType === 'entrance_effect') {
    const table = itemType === 'frame' ? 'frames' : 'entrance_effects';
    const exists = await query(`SELECT 1 FROM ${table} WHERE id::text = $1 AND is_active = TRUE`, [itemKey]);
    if (!exists.rowCount) throw fail('Bu anahtara sahip aktif bir katalog öğesi yok.', 404);
  }
  let expiresAt = null;
  if (req.body?.expiresAt) {
    const d = new Date(req.body.expiresAt);
    if (Number.isNaN(d.getTime()) || d.getTime() < Date.now()) throw fail('Bitiş tarihi geçersiz veya geçmişte.');
    expiresAt = d.toISOString();
  }
  const metadata = req.body?.metadata && typeof req.body.metadata === 'object' && !Array.isArray(req.body.metadata) ? req.body.metadata : {};
  const r = await query(
    `INSERT INTO inventory_items(user_id, item_type, item_key, item_name, expires_at, metadata) VALUES($1,$2,$3,$4,$5,$6) RETURNING id`,
    [userId, itemType, itemKey, itemName, expiresAt, JSON.stringify(metadata)],
  );
  await query(
    `INSERT INTO financial_audit_logs(admin_id, user_id, action, reference_type, reference_id, metadata) VALUES($1,$2,'admin_inventory_grant','inventory',$3,$4)`,
    [req.user.id, userId, r.rows[0].id, JSON.stringify({ itemType, itemKey })],
  );
  res.status(201).json({ id: r.rows[0].id });
});

// ---------------- Katalog (yalnızca yönetici) ----------------
function guessFormat(url) {
  const m = /\.([a-z0-9]{2,5})(\?|$)/i.exec(String(url ?? ''));
  const e = (m?.[1] ?? '').toLowerCase();
  return { mp4: 'mp4', svga: 'svga', json: 'lottie', webp: 'webp', gif: 'gif', png: 'png' }[e] ?? 'lottie';
}
router.post('/media', requireSuperAdmin, express.raw({ type: () => true, limit: MEDIA_MAX_BYTES }), async (req, res) => {
  const buf = req.body;
  if (!Buffer.isBuffer(buf) || !buf.length) throw fail('Dosya gönderilmedi.');
  const d = detectMedia(buf);
  const alpha = req.query.alpha === 'right' ? 'right' : 'left';
  let data = buf; let note = null;
  if (d.kind === 'mp4') {
    const r = ensureVapc(buf, alpha);
    data = r.buf;
    note = r.injected ? 'Şeffaflık ayarı eklendi.' : 'Dosyada şeffaflık ayarı zaten vardı.';
  }
  const ins = await query(
    `INSERT INTO media_files(kind, mime, ext, size_bytes, data, meta, created_by) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
    [d.kind, mimeFor(d.ext), d.ext, data.length, data, JSON.stringify(d.meta ?? {}), req.user.id],
  );
  const format = { mp4: 'mp4', svga: 'svga', json: 'lottie', webp: 'webp', gif: 'gif', png: 'png', jpg: 'png' }[d.kind];
  res.status(201).json({ url: `/media/${ins.rows[0].id}.${d.ext}`, kind: d.kind, format, size: data.length, note });
});
router.post('/gifts', requireSuperAdmin, async (req, res) => {
  const r = await query(
    `INSERT INTO gifts(name, coin_price, icon_url, animation_url, animation_format, has_alpha, category) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
    [text(req.body?.name, 'Ad', { min: 2, max: 80, required: true }), bigAmount(req.body?.coinPrice, 'Fiyat').toString(),
      assetUrl(req.body?.iconUrl, 'İkon adresi'), assetUrl(req.body?.animationUrl, 'Animasyon adresi'),
      oneOf(req.body?.animationFormat ?? guessFormat(req.body?.animationUrl), ['lottie', 'svga', 'mp4', 'webp', 'gif', 'png'], 'Animasyon biçimi'), req.body?.hasAlpha !== false,
      oneOf(req.body?.category ?? 'popular', ['event', 'popular', 'private', 'vip'], 'Hediye sekmesi')],
  );
  res.status(201).json({ id: r.rows[0].id });
});
router.post('/frames', requireSuperAdmin, async (req, res) => {
  const r = await query(`INSERT INTO frames(name, image_url) VALUES($1,$2) RETURNING id`, [
    text(req.body?.name, 'Ad', { min: 2, max: 100, required: true }), assetUrl(req.body?.imageUrl, 'Görsel adresi') ?? (() => { throw fail('Görsel adresi gerekli.'); })()]);
  res.status(201).json({ id: r.rows[0].id });
});
router.post('/entrance-effects', requireSuperAdmin, async (req, res) => {
  const r = await query(`INSERT INTO entrance_effects(name, animation_url, duration_ms) VALUES($1,$2,$3) RETURNING id`, [
    text(req.body?.name, 'Ad', { min: 2, max: 100, required: true }),
    assetUrl(req.body?.animationUrl, 'Animasyon adresi') ?? (() => { throw fail('Animasyon adresi gerekli.'); })(),
    req.body?.durationMs === undefined ? 4000 : positiveInt(req.body.durationMs, 'Süre', 20000)]);
  res.status(201).json({ id: r.rows[0].id });
});
router.get('/catalog', requireSuperAdmin, async (_req, res) => {
  const g = await query(`SELECT id, name, coin_price, icon_url, animation_url, animation_format, category, is_active FROM gifts ORDER BY is_active DESC, coin_price DESC, name`);
  const f = await query(`SELECT id, name, image_url, is_active FROM frames ORDER BY is_active DESC, name`);
  res.json({
    gifts: g.rows.map((r) => ({ id: r.id, name: r.name, coinPrice: String(r.coin_price), iconUrl: r.icon_url, animationUrl: r.animation_url, animationFormat: r.animation_format, category: r.category, isActive: r.is_active })),
    frames: f.rows.map((r) => ({ id: r.id, name: r.name, imageUrl: r.image_url, isActive: r.is_active })),
  });
});
const TOGGLE_TABLES = { gifts: 'gifts', frames: 'frames', 'entrance-effects': 'entrance_effects', music: 'music_tracks' };
router.post('/catalog/:kind/:id/active', requireSuperAdmin, async (req, res) => {
  const table = TOGGLE_TABLES[req.params.kind];
  if (!table) throw fail('Geçersiz katalog türü.', 404);
  if (typeof req.body?.isActive !== 'boolean') throw fail('isActive true/false olmalı.');
  const r = await query(`UPDATE ${table} SET is_active = $2 WHERE id = $1 RETURNING id`, [uuid(req.params.id, 'Kimlik'), req.body.isActive]);
  if (!r.rowCount) throw fail('Öğe bulunamadı.', 404);
  res.json({ ok: true });
});

// ---------------- Bayi (yalnızca yönetici) ----------------
router.get('/dealers', requireSuperAdmin, async (req, res) => {
  const r = await query(
    `SELECT d.*, u.username AS owner_username FROM dealer_accounts d LEFT JOIN users u ON u.id = d.owner_user_id ORDER BY d.created_at DESC LIMIT 200`,
  );
  res.json({ dealers: r.rows.map((d) => ({
    id: d.id, name: d.name, ownerUserId: d.owner_user_id, ownerUsername: d.owner_username,
    coinBalance: String(d.coin_balance), commissionBps: d.commission_bps, isActive: d.is_active,
  })) });
});

router.post('/dealers', requireSuperAdmin, async (req, res) => {
  const bps = req.body?.commissionBps === undefined ? 0 : Number(req.body.commissionBps);
  if (!Number.isInteger(bps) || bps < 0 || bps > 10000) throw fail('Komisyon 0-10000 (baz puan) arasında olmalı.');
  const ownerId = req.body?.ownerUserId ? uuid(req.body.ownerUserId, 'Sahip') : null;
  if (ownerId) await assertUser(ownerId);
  const r = await query(
    `INSERT INTO dealer_accounts(name, owner_user_id, commission_bps) VALUES($1,$2,$3) RETURNING id, name`,
    [text(req.body?.name, 'Bayi adı', { min: 2, max: 100, required: true }), ownerId, bps],
  );
  res.status(201).json({ dealer: r.rows[0] });
});

router.post('/dealers/:dealerId/coins', requireSuperAdmin, async (req, res) => {
  const dealerId = uuid(req.params.dealerId, 'Bayi');
  const amount = bigAmount(req.body?.amount, 'Bayi Coin miktarı');
  const result = await tx(async (c) => {
    const dealer = (await c.query(`SELECT * FROM dealer_accounts WHERE id = $1 FOR UPDATE`, [dealerId])).rows[0];
    if (!dealer) throw fail('Bayi bulunamadı.', 404);
    const before = BigInt(dealer.coin_balance);
    const balance = before + amount;
    await c.query(`UPDATE dealer_accounts SET coin_balance = $1 WHERE id = $2`, [balance.toString(), dealer.id]);
    await c.query(
      `INSERT INTO dealer_transactions(dealer_id, admin_id, type, coin_amount, description) VALUES($1,$2,'credit',$3,$4)`,
      [dealer.id, req.user.id, amount.toString(), text(req.body?.description, 'Açıklama', { max: 200 }) || 'Admin bayi Coin yükleme'],
    );
    await c.query(
      `INSERT INTO financial_audit_logs(admin_id, action, reference_type, reference_id, amount_coins, balance_before, balance_after)
       VALUES($1,'dealer_credit','dealer',$2,$3,$4,$5)`,
      [req.user.id, dealer.id, amount.toString(), before.toString(), balance.toString()],
    );
    return { balance: balance.toString() };
  });
  res.json(result);
});

router.post('/dealers/:dealerId/sell', requireSuperAdmin, async (req, res) => {
  const result = await tx((c) => dealerSell(c, {
    dealerId: uuid(req.params.dealerId, 'Bayi'), userId: uuid(req.body?.userId, 'Kullanıcı'),
    coins: bigAmount(req.body?.amount, 'Satış Coin miktarı'), actorId: req.user.id, description: text(req.body?.description, 'Açıklama', { max: 200 }),
  }));
  res.json(result);
});

// ---------------- Ajans ve yayıncı ----------------
router.get('/agencies', async (req, res) => {
  const status = req.query.status ? oneOf(String(req.query.status), ['pending', 'active', 'suspended', 'rejected'], 'Durum') : null;
  const r = await query(
    `SELECT a.*, u.username AS owner_username, (SELECT COUNT(*)::int FROM broadcasters b WHERE b.agency_id = a.id) AS broadcaster_count
     FROM agencies a JOIN users u ON u.id = a.owner_id WHERE ($1::text IS NULL OR a.status = $1) ORDER BY a.created_at DESC LIMIT 200`,
    [status],
  );
  res.json({ agencies: r.rows.map((a) => ({
    id: a.id, name: a.name, ownerId: a.owner_id, ownerUsername: a.owner_username, status: a.status,
    commissionBps: a.commission_bps, overrideBps: a.commission_override_bps, agencyCode: a.agency_code, broadcasterCount: a.broadcaster_count, createdAt: a.created_at,
  })) });
});

// Komisyon para etkisi taşıdığı için yalnızca yönetici.
router.post('/agencies/:agencyId/status', requireSuperAdmin, async (req, res) => {
  const agencyId = uuid(req.params.agencyId, 'Ajans');
  const status = oneOf(req.body?.status, ['active', 'suspended', 'rejected'], 'Durum');
  let bps = null;
  if (req.body?.commissionBps !== undefined) {
    bps = Number(req.body.commissionBps);
    if (!Number.isInteger(bps) || bps < 0 || bps > 10000) throw fail('Komisyon 0-10000 (baz puan) arasında olmalı.');
  }
  const r = await query(
    `UPDATE agencies SET status = $2::text, commission_bps = COALESCE($3, commission_bps),
       approved_by = CASE WHEN $2::text = 'active' THEN $4::uuid ELSE approved_by END,
       approved_at = CASE WHEN $2::text = 'active' THEN NOW() ELSE approved_at END
     WHERE id = $1 RETURNING id, status, commission_bps`,
    [agencyId, status, bps, req.user.id],
  );
  if (!r.rowCount) throw fail('Ajans bulunamadı.', 404);
  if (status === 'active') await ensureAgencyCode(agencyId);
  await query(
    `INSERT INTO financial_audit_logs(admin_id, action, reference_type, reference_id, metadata) VALUES($1,'agency_status','agency',$2,$3)`,
    [req.user.id, agencyId, JSON.stringify({ status, commissionBps: r.rows[0].commission_bps })],
  );
  res.json({ agency: r.rows[0] });
});

router.get('/broadcasters', async (req, res) => {
  const status = req.query.status ? oneOf(String(req.query.status), ['pending', 'approved', 'rejected', 'suspended'], 'Durum') : null;
  const r = await query(
    `SELECT b.user_id, b.status, b.applied_at, b.agency_id, u.username, u.display_name, a.name AS agency_name
     FROM broadcasters b JOIN users u ON u.id = b.user_id LEFT JOIN agencies a ON a.id = b.agency_id
     WHERE ($1::text IS NULL OR b.status = $1) ORDER BY b.applied_at DESC LIMIT 200`,
    [status],
  );
  res.json({ broadcasters: r.rows.map((b) => ({
    userId: b.user_id, username: b.username, displayName: b.display_name, status: b.status, appliedAt: b.applied_at,
    agencyId: b.agency_id, agencyName: b.agency_name,
  })) });
});

router.post('/broadcasters/:userId/status', async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  const status = oneOf(req.body?.status, ['approved', 'rejected', 'suspended'], 'Durum');
  const r = await query(
    `UPDATE broadcasters SET status = $2::text,
       approved_by = CASE WHEN $2::text = 'approved' THEN $3::uuid ELSE approved_by END,
       approved_at = CASE WHEN $2::text = 'approved' THEN NOW() ELSE approved_at END,
       agency_id = CASE WHEN $2::text IN ('rejected','suspended') THEN NULL ELSE agency_id END
     WHERE user_id = $1 RETURNING user_id, status`,
    [userId, status, req.user.id],
  );
  if (!r.rowCount) throw fail('Yayıncı başvurusu bulunamadı.', 404);
  await query(
    `INSERT INTO financial_audit_logs(admin_id, user_id, action, reference_type, metadata) VALUES($1,$2,'broadcaster_status','broadcaster',$3)`,
    [req.user.id, userId, JSON.stringify({ status })],
  );
  res.json({ broadcaster: r.rows[0] });
});

// ---------------- Ajans ayarları, etkinlikler, dönem kapatma, KYC ----------------
router.get('/agency-config', async (req, res) => {
  res.json({ config: configJson(await loadConfig()) });
});

router.put('/agency-config', requireSuperAdmin, async (req, res) => {
  const v = validateAgencyConfig(req.body);
  await tx(async (c) => {
    if (v.settings) {
      const m = { cycle: 'cycle', penaltyBps: 'penalty_bps', requireOfficialEvents: 'require_official_events', minEventCount: 'min_event_count', currency: 'currency' };
      for (const [k, col] of Object.entries(m)) {
        if (v.settings[k] !== undefined) await c.query(`UPDATE agency_settings SET ${col} = $1, updated_at = NOW() WHERE id = 1`, [v.settings[k]]);
      }
    }
    if (v.salaryTiers) {
      await c.query(`DELETE FROM host_salary_tiers`);
      for (const t of v.salaryTiers) {
        await c.query(`INSERT INTO host_salary_tiers(level, required_hours, required_diamonds, salary_cents) VALUES($1,$2,$3,$4)`, [t.level, t.hours, t.diamonds.toString(), t.salaryCents.toString()]);
      }
    }
    if (v.commissionTiers) {
      await c.query(`DELETE FROM agency_commission_tiers`);
      for (const t of v.commissionTiers) {
        await c.query(`INSERT INTO agency_commission_tiers(level, min_team_diamonds, commission_bps) VALUES($1,$2,$3)`, [t.level, t.minDiamonds.toString(), t.bps]);
      }
    }
    await c.query(`INSERT INTO financial_audit_logs(admin_id, action, reference_type, metadata) VALUES($1,'agency_config_update','agency_config',$2)`, [req.user.id, JSON.stringify(Object.keys(v))]);
  });
  res.json({ config: configJson(await loadConfig()) });
});

router.post('/agencies/:agencyId/commission-override', requireSuperAdmin, async (req, res) => {
  const agencyId = uuid(req.params.agencyId, 'Ajans');
  let bps = req.body?.bps;
  if (bps !== null) {
    if (!Number.isInteger(bps) || bps < 0 || bps > 10000) throw fail('Oran 0-10000 (baz puan) olmalı veya null.');
  }
  const r = await query(`UPDATE agencies SET commission_override_bps = $2 WHERE id = $1 RETURNING id, commission_override_bps`, [agencyId, bps]);
  if (!r.rowCount) throw fail('Ajans bulunamadı.', 404);
  await query(`INSERT INTO financial_audit_logs(admin_id, action, reference_type, reference_id, metadata) VALUES($1,'agency_commission_override','agency',$2,$3)`, [req.user.id, agencyId, JSON.stringify({ bps })]);
  res.json({ ok: true, overrideBps: r.rows[0].commission_override_bps });
});

router.post('/broadcasters/:userId/contract', requireSuperAdmin, async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  const tier = req.body?.tier === null ? null : positiveInt(req.body?.tier, 'Kademe', 10);
  const r = await query(`UPDATE broadcasters SET contract_tier = $2 WHERE user_id = $1 RETURNING user_id`, [userId, tier]);
  if (!r.rowCount) throw fail('Yayıncı bulunamadı.', 404);
  res.json({ ok: true, tier });
});

router.post('/events', async (req, res) => {
  const title = text(req.body?.title, 'Başlık', { min: 3, max: 120, required: true });
  const startsAt = new Date(req.body?.startsAt);
  if (Number.isNaN(startsAt.getTime())) throw fail('Başlangıç zamanı geçersiz.');
  const r = await query(`INSERT INTO official_events(title, starts_at, created_by) VALUES($1,$2,$3) RETURNING id, title, starts_at`, [title, startsAt.toISOString(), req.user.id]);
  res.status(201).json({ event: r.rows[0] });
});

router.get('/events', async (req, res) => {
  const r = await query(
    `SELECT e.id, e.title, e.starts_at, (SELECT COUNT(*)::int FROM official_event_attendance a WHERE a.event_id = e.id) AS attendees
     FROM official_events e ORDER BY e.starts_at DESC LIMIT 100`,
  );
  res.json({ events: r.rows.map((e) => ({ id: e.id, title: e.title, startsAt: e.starts_at, attendees: e.attendees })) });
});

router.post('/events/:id/attendance', async (req, res) => {
  const eventId = uuid(req.params.id, 'Etkinlik');
  const userIds = (Array.isArray(req.body?.userIds) ? req.body.userIds : []).slice(0, 200).map((x) => uuid(x, 'Kullanıcı'));
  if (!userIds.length) throw fail('En az bir kullanıcı gerekli.');
  if (!(await query(`SELECT 1 FROM official_events WHERE id = $1`, [eventId])).rowCount) throw fail('Etkinlik bulunamadı.', 404);
  const r = await query(
    `INSERT INTO official_event_attendance(event_id, user_id, marked_by)
     SELECT $1, b.user_id, $3 FROM broadcasters b WHERE b.user_id = ANY($2::uuid[]) ON CONFLICT DO NOTHING`, [eventId, userIds, req.user.id],
  );
  res.json({ ok: true, added: r.rowCount });
});

// Dönemi kapat (hesap özetleri üretir). period boş ise bir önceki dönem.
router.post('/payouts/close', requireSuperAdmin, async (req, res) => {
  const cfg = await loadConfig();
  let key = req.body?.period;
  if (!key) key = previousPeriod(cfg.settings.cycle).key;
  try { parsePeriodKey(key); } catch (e) { throw fail(e.message); }
  const out = await closePeriod({ adminId: req.user.id, periodKey: key, force: req.body?.force === true });
  res.status(201).json(out);
});

router.get('/payouts', async (req, res) => {
  const r = await query(
    `SELECT p.id, p.period_key, p.cycle, p.starts_at, p.ends_at, p.closed_at,
       (SELECT COUNT(*)::int FROM host_statements h WHERE h.period_id = p.id) AS hosts,
       (SELECT COUNT(*)::int FROM host_statements h WHERE h.period_id = p.id AND h.status = 'pending') AS pending_hosts,
       (SELECT COALESCE(SUM(salary_cents),0) FROM host_statements h WHERE h.period_id = p.id) AS total_salary_cents,
       (SELECT COUNT(*)::int FROM agency_statements a WHERE a.period_id = p.id) AS agencies,
       (SELECT COUNT(*)::int FROM agency_statements a WHERE a.period_id = p.id AND a.status = 'pending') AS pending_agencies
     FROM payout_periods p ORDER BY p.starts_at DESC LIMIT 52`,
  );
  res.json({ periods: r.rows.map((p) => ({
    id: p.id, periodKey: p.period_key, cycle: p.cycle, startsAt: p.starts_at, endsAt: p.ends_at, closedAt: p.closed_at,
    hosts: p.hosts, pendingHosts: p.pending_hosts, totalSalaryCents: String(p.total_salary_cents), agencies: p.agencies, pendingAgencies: p.pending_agencies,
  })) });
});

router.get('/payouts/:id', async (req, res) => {
  const id = uuid(req.params.id, 'Dönem');
  const p = (await query(`SELECT * FROM payout_periods WHERE id = $1`, [id])).rows[0];
  if (!p) throw fail('Dönem bulunamadı.', 404);
  const hosts = (await query(
    `SELECT h.*, $2::text AS period_key, $3::timestamptz AS starts_at, $4::timestamptz AS ends_at, u.username, u.kyc_status
     FROM host_statements h JOIN users u ON u.id = h.user_id WHERE h.period_id = $1 ORDER BY h.salary_cents DESC`,
    [id, p.period_key, p.starts_at, p.ends_at],
  )).rows;
  const agencies = (await query(
    `SELECT s.*, $2::text AS period_key, $3::timestamptz AS starts_at, $4::timestamptz AS ends_at, a.name AS agency_name
     FROM agency_statements s JOIN agencies a ON a.id = s.agency_id WHERE s.period_id = $1 ORDER BY s.commission_diamonds DESC`,
    [id, p.period_key, p.starts_at, p.ends_at],
  )).rows;
  res.json({
    period: { id: p.id, periodKey: p.period_key, cycle: p.cycle, startsAt: p.starts_at, endsAt: p.ends_at, closedAt: p.closed_at },
    hostStatements: hosts.map((h) => ({ ...hostStatementJson(h), kycStatus: h.kyc_status })),
    agencyStatements: agencies.map(agencyStatementJson),
  });
});

// Ödeme platform dışında yapılır; burada yalnızca "ödendi" işaretlenir. Yayıncı için KYC onayı şarttır.
router.post('/statements/:kind/:id/pay', requireSuperAdmin, async (req, res) => {
  const kind = oneOf(req.params.kind, ['host', 'agency'], 'Tür');
  const id = uuid(req.params.id, 'Özet');
  await tx(async (c) => {
    if (kind === 'host') {
      const h = (await c.query(`SELECT h.*, u.kyc_status FROM host_statements h JOIN users u ON u.id = h.user_id WHERE h.id = $1 FOR UPDATE OF h`, [id])).rows[0];
      if (!h) throw fail('Özet bulunamadı.', 404);
      if (h.status !== 'pending') throw fail('Bu özet zaten işlenmiş.', 409);
      if (BigInt(h.salary_cents) > 0n && h.kyc_status !== 'approved') throw fail('Yayıncının kimlik doğrulaması (KYC) onaylı değil.', 409);
      await c.query(`UPDATE host_statements SET status = 'paid', paid_at = NOW(), paid_by = $2 WHERE id = $1`, [id, req.user.id]);
      await c.query(`INSERT INTO financial_audit_logs(admin_id, user_id, action, reference_type, reference_id, metadata) VALUES($1,$2,'host_salary_paid','host_statement',$3,$4)`,
        [req.user.id, h.user_id, id, JSON.stringify({ salaryCents: String(h.salary_cents) })]);
    } else {
      const a = (await c.query(`SELECT * FROM agency_statements WHERE id = $1 FOR UPDATE`, [id])).rows[0];
      if (!a) throw fail('Özet bulunamadı.', 404);
      if (a.status !== 'pending') throw fail('Bu özet zaten işlenmiş.', 409);
      await c.query(`UPDATE agency_statements SET status = 'paid', paid_at = NOW(), paid_by = $2 WHERE id = $1`, [id, req.user.id]);
      await c.query(`INSERT INTO financial_audit_logs(admin_id, action, reference_type, reference_id, amount_diamonds, metadata) VALUES($1,'agency_commission_paid','agency_statement',$2,$3,$4)`,
        [req.user.id, id, a.commission_diamonds, JSON.stringify({ agencyId: a.agency_id })]);
    }
  });
  res.json({ ok: true });
});

router.get('/kyc', async (req, res) => {
  const status = oneOf(String(req.query.status ?? 'pending'), ['pending', 'approved', 'rejected'], 'Durum');
  const r = await query(`SELECT id, username, display_name, kyc_status FROM users WHERE kyc_status = $1 ORDER BY username LIMIT 200`, [status]);
  res.json({ users: r.rows.map((u) => ({ id: u.id, username: u.username, displayName: u.display_name, kycStatus: u.kyc_status })) });
});

router.post('/users/:userId/kyc', requireSuperAdmin, async (req, res) => {
  const userId = uuid(req.params.userId, 'Kullanıcı');
  const status = oneOf(req.body?.status, ['approved', 'rejected', 'none'], 'Durum');
  const r = await query(`UPDATE users SET kyc_status = $2 WHERE id = $1 RETURNING id`, [userId, status]);
  if (!r.rowCount) throw fail('Kullanıcı bulunamadı.', 404);
  await query(`INSERT INTO financial_audit_logs(admin_id, user_id, action, reference_type, metadata) VALUES($1,$2,'kyc_status','user',$3)`, [req.user.id, userId, JSON.stringify({ status })]);
  res.json({ ok: true, status });
});

router.get('/finance/audit', requireSuperAdmin, async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 100, 500);
  const userId = req.query.userId ? uuid(String(req.query.userId), 'Kullanıcı') : null;
  const r = await query(
    `SELECT * FROM financial_audit_logs WHERE ($1::uuid IS NULL OR user_id = $1) ORDER BY created_at DESC LIMIT $2`,
    [userId, limit],
  );
  res.json({ logs: r.rows });
});

// ---------------- Müzik kütüphanesi (yalnızca yönetici) ----------------
// Telif: yalnızca kullanım hakkına sahip olduğunuz parçaları ekleyin; lisans notu zorunludur.
router.post('/music/tracks', requireSuperAdmin, async (req, res) => {
  const url = httpsUrl(req.body?.url, 'Şarkı adresi');
  if (!url) throw fail('Şarkı adresi gerekli.');
  const r = await query(
    `INSERT INTO music_tracks(title, artist, url, cover_url, duration_ms, license_note, created_by) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
    [text(req.body?.title, 'Başlık', { min: 1, max: 120, required: true }), text(req.body?.artist, 'Sanatçı', { max: 120 }), url,
      httpsUrl(req.body?.coverUrl, 'Kapak adresi'), positiveInt(req.body?.durationMs, 'Süre (ms)', 7200000),
      text(req.body?.licenseNote, 'Lisans notu', { min: 3, max: 300, required: true }), req.user.id],
  );
  res.status(201).json({ id: r.rows[0].id });
});

router.get('/music/tracks', requireSuperAdmin, async (req, res) => {
  const r = await query(`SELECT id, title, artist, duration_ms, is_active, license_note FROM music_tracks ORDER BY created_at DESC LIMIT 200`);
  res.json({ tracks: r.rows.map((t) => ({ id: t.id, title: t.title, artist: t.artist, durationMs: t.duration_ms, isActive: t.is_active, licenseNote: t.license_note })) });
});

// ---------------- Şikâyetler (admin + support) ----------------
router.get('/reports', async (req, res) => {
  const status = oneOf(String(req.query.status ?? 'open'), ['open', 'resolved', 'dismissed'], 'Durum');
  const r = await query(
    `SELECT r.*, ru.username AS reporter_username, tu.username AS target_username FROM reports r
     JOIN users ru ON ru.id = r.reporter_id LEFT JOIN users tu ON tu.id = r.target_user_id
     WHERE r.status = $1 ORDER BY r.created_at DESC LIMIT 100`,
    [status],
  );
  res.json({ reports: r.rows.map((x) => ({
    id: x.id, kind: x.kind, reason: x.reason, details: x.details, status: x.status, createdAt: x.created_at,
    reporter: x.reporter_username, targetUserId: x.target_user_id, target: x.target_username, roomId: x.room_id, messageId: x.message_id,
  })) });
});

router.post('/reports/:id/resolve', async (req, res) => {
  const status = oneOf(req.body?.status, ['resolved', 'dismissed'], 'Durum');
  const r = await query(
    `UPDATE reports SET status = $2, resolved_by = $3, resolved_note = $4, resolved_at = NOW() WHERE id = $1 AND status = 'open' RETURNING id`,
    [uuid(req.params.id, 'Şikâyet'), status, req.user.id, text(req.body?.note, 'Not', { max: 300 })],
  );
  if (!r.rowCount) throw fail('Açık şikâyet bulunamadı.', 404);
  res.json({ ok: true });
});

// ---------------- Güvenlik duvarı (yalnızca yönetici) ----------------
router.get('/security/events', requireSuperAdmin, async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 100, 500);
  const type = req.query.type ? String(req.query.type).slice(0, 40) : null;
  const r = await query(
    `SELECT id, event_type, host(ip) AS ip, user_id, detail, created_at FROM security_events
     WHERE ($1::text IS NULL OR event_type = $1) ORDER BY created_at DESC LIMIT $2`,
    [type, limit],
  );
  res.json({ events: r.rows, stats: securityStats() });
});

router.get('/security/blocks', requireSuperAdmin, async (req, res) => {
  res.json({ blocks: listBans().map((b) => ({ ip: b.ip, reason: b.reason, until: b.until ? new Date(b.until).toISOString() : null })) });
});

router.post('/security/blocks', requireSuperAdmin, async (req, res) => {
  const ip = String(req.body?.ip ?? '').trim();
  if (!net.isIP(ip)) throw fail('Geçerli bir IP adresi girin.');
  const minutes = req.body?.minutes === undefined || req.body.minutes === null ? null : positiveInt(req.body.minutes, 'Süre (dk)', 525600);
  if (!(await banIpPersist(ip, minutes === null ? null : minutes * 60000, text(req.body?.reason, 'Neden', { max: 200 }) || 'Yönetici kararı', req.user.id))) {
    throw fail('Bu IP izin listesinde olduğu için engellenemez.', 409);
  }
  res.status(201).json({ ok: true });
});

router.delete('/security/blocks/:ip', requireSuperAdmin, async (req, res) => {
  const ip = String(req.params.ip);
  if (!net.isIP(ip)) throw fail('Geçerli bir IP adresi girin.');
  await unbanIp(ip);
  res.json({ ok: true });
});

// ---------- Banner ve duyuru yönetimi (yalnızca yönetici) ----------
router.get('/banners', async (_req, res) => {
  const r = await query(`SELECT id, image_url, title, link_url, sort_order, is_active FROM banners ORDER BY sort_order, created_at DESC LIMIT 50`);
  res.json({ banners: r.rows.map((b) => ({ id: b.id, imageUrl: b.image_url, title: b.title, linkUrl: b.link_url, sortOrder: b.sort_order, active: b.is_active })) });
});

router.put('/banners/image', express.raw({ type: Object.keys(IMAGE_TYPES), limit: '3mb' }), async (req, res) => {
  res.json({ url: await saveUpload(req) });
});

router.post('/banners', async (req, res) => {
  const imageUrl = String(req.body?.imageUrl ?? '');
  if (!/^\/uploads\/[0-9a-f-]{36}\.(png|jpg|webp)$/.test(imageUrl)) throw fail('Önce bir görsel yükleyin.');
  const title = text(req.body?.title, 'Başlık', { max: 80 }) || null;
  const linkUrl = req.body?.linkUrl ? httpsUrl(req.body.linkUrl, 'Bağlantı') : null;
  const sortOrder = Number.isInteger(req.body?.sortOrder) ? req.body.sortOrder : 0;
  const r = await query(`INSERT INTO banners(image_url, title, link_url, sort_order) VALUES($1,$2,$3,$4) RETURNING id`, [imageUrl, title, linkUrl, sortOrder]);
  await auditStaff({ query }, req.user.id, null, 'banner_add', { id: r.rows[0].id });
  res.status(201).json({ id: r.rows[0].id });
});

router.patch('/banners/:id', async (req, res) => {
  const id = uuid(req.params.id);
  if (typeof req.body?.active !== 'boolean') throw fail('active alanı true/false olmalı.');
  const r = await query(`UPDATE banners SET is_active = $2 WHERE id = $1`, [id, req.body.active]);
  if (!r.rowCount) throw fail('Banner bulunamadı.', 404);
  res.json({ ok: true });
});

router.delete('/banners/:id', async (req, res) => {
  const id = uuid(req.params.id);
  const r = await query(`DELETE FROM banners WHERE id = $1 RETURNING image_url`, [id]);
  if (!r.rowCount) throw fail('Banner bulunamadı.', 404);
  await removeUpload(r.rows[0].image_url);
  await auditStaff({ query }, req.user.id, null, 'banner_delete', { id });
  res.json({ ok: true });
});

router.post('/announcements', async (req, res) => {
  const kind = oneOf(req.body?.kind, ['team', 'event', 'reward'], 'Tür');
  const title = text(req.body?.title, 'Başlık', { min: 2, max: 80, required: true });
  const body = text(req.body?.text, 'Metin', { min: 1, max: 2000, required: true });
  const r = await query(`INSERT INTO announcements(kind, title, body, created_by) VALUES($1,$2,$3,$4) RETURNING id`, [kind, title, body, req.user.id]);
  await auditStaff({ query }, req.user.id, null, 'announcement_add', { id: r.rows[0].id, kind });
  res.status(201).json({ id: r.rows[0].id });
});

router.delete('/announcements/:id', async (req, res) => {
  const id = uuid(req.params.id);
  const r = await query(`DELETE FROM announcements WHERE id = $1`, [id]);
  if (!r.rowCount) throw fail('Duyuru bulunamadı.', 404);
  res.json({ ok: true });
});
