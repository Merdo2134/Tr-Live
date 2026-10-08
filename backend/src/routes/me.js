import { Router } from 'express';
import express from 'express';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { query, tx } from '../database.js';
import { requireAuth, checkPassword, hashPassword, passwordRules } from '../auth.js';
import { fail, text, oneOf, httpsUrl } from '../http.js';
import { loadProfile } from '../services/profile.js';
import { activeWip } from '../services/wip.js';
import { publicUser, USER_PUBLIC_COLUMNS, USER_PUBLIC_JOINS } from '../views.js';
import { config } from '../config.js';
import { cleanPublic } from '../safe_text.js';
import { hub } from '../realtime.js';
import { userLimit } from '../firewall.js';

export const router = Router();
router.use(requireAuth);

const LANG_RE = /^[a-z]{2}(-[A-Z]{2})?$/;
const IMAGE_TYPES = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' };

router.get('/', async (req, res) => {
  const profile = await loadProfile(req.user.id, req.user.id);
  const wip = await activeWip(req.user.id);
  res.json({ user: profile, wip });
});

router.patch('/', async (req, res) => {
  const b = req.body ?? {};
  const sets = [];
  const values = [];
  const set = (column, value) => { values.push(value); sets.push(`${column} = $${values.length}`); };

  if (b.displayName !== undefined) set('display_name', cleanPublic(text(b.displayName, 'Ad', { min: 1, max: 60, required: true }), 'Ad'));
  if (b.bio !== undefined) set('bio', cleanPublic(text(b.bio, 'Biyografi', { max: 300 }), 'Biyografi'));
  if (b.language !== undefined) {
    if (typeof b.language !== 'string' || !LANG_RE.test(b.language)) throw fail('Dil geçersiz.');
    set('language', b.language);
  }
  if (b.isHidden !== undefined) {
    if (typeof b.isHidden !== 'boolean') throw fail('Gizli kullanıcı değeri geçersiz.');
    set('is_hidden', b.isHidden);
  }
  if (b.whoCanDm !== undefined) set('who_can_dm', oneOf(b.whoCanDm, ['everyone', 'following', 'nobody'], 'Mesaj gizliliği'));
  if (b.gender !== undefined) set('gender', b.gender === null ? null : oneOf(b.gender, ['male', 'female', 'other'], 'Cinsiyet'));
  if (b.birthDate !== undefined) {
    if (b.birthDate === null) set('birth_date', null);
    else {
      const d = new Date(`${b.birthDate}T00:00:00Z`);
      const ok = /^\d{4}-\d{2}-\d{2}$/.test(String(b.birthDate)) && !Number.isNaN(d.getTime());
      const age = ok ? (Date.now() - d.getTime()) / (365.25 * 24 * 3600 * 1000) : 0;
      if (!ok || age < 13 || age > 110) throw fail('Doğum tarihi geçersiz (en az 13 yaşında olmalısınız).');
      set('birth_date', b.birthDate);
    }
  }
  if (b.country !== undefined) set('country', text(b.country, 'Ülke', { max: 60 }));
  if (b.city !== undefined) set('city', text(b.city, 'Şehir', { max: 60 }));
  if (b.avatarUrl !== undefined) set('avatar_url', b.avatarUrl === null ? null : httpsUrl(b.avatarUrl, 'Avatar adresi'));
  if (b.coverUrl !== undefined) set('cover_url', b.coverUrl === null ? null : httpsUrl(b.coverUrl, 'Kapak adresi'));

  if (sets.length) {
    values.push(req.user.id);
    await query(`UPDATE users SET ${sets.join(', ')}, updated_at = NOW() WHERE id = $${values.length}`, values);
  }
  res.json({ user: await loadProfile(req.user.id, req.user.id) });
});

// ---- Görsel yükleme: ham bayt (image/png|jpeg|webp), en fazla 3 MB ----
function detectImage(buf) {
  if (buf.length > 12 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) return 'image/png';
  if (buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length > 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  return null;
}

async function removeOldUpload(url) {
  if (!url || !url.startsWith('/uploads/')) return;
  const file = path.basename(url);
  try { await fs.unlink(path.join(config.uploadDir, file)); } catch (_) { /* yoksay */ }
}

function imageUpload(column) {
  const parser = express.raw({ type: Object.keys(IMAGE_TYPES), limit: '3mb' });
  return [parser, async (req, res) => {
    const buf = req.body;
    if (!Buffer.isBuffer(buf) || !buf.length) throw fail('Görsel gönderilmedi (png, jpeg veya webp).');
    const kind = detectImage(buf);
    if (!kind || kind !== req.headers['content-type']?.split(';')[0]) throw fail('Görsel biçimi geçersiz.');
    await fs.mkdir(config.uploadDir, { recursive: true });
    const name = `${crypto.randomUUID()}.${IMAGE_TYPES[kind]}`;
    await fs.writeFile(path.join(config.uploadDir, name), buf);
    const url = `/uploads/${name}`;
    const old = (await query(`SELECT ${column} AS url FROM users WHERE id = $1`, [req.user.id])).rows[0]?.url;
    await query(`UPDATE users SET ${column} = $1, updated_at = NOW() WHERE id = $2`, [url, req.user.id]);
    await removeOldUpload(old);
    res.json({ url });
  }];
}
router.put('/avatar', ...imageUpload('avatar_url'));
router.put('/cover', ...imageUpload('cover_url'));

router.post('/password', async (req, res) => {
  const current = String(req.body?.currentPassword ?? '');
  const next = String(req.body?.newPassword ?? '');
  passwordRules(next);
  if (!req.user.password_hash || !(await checkPassword(current, req.user.password_hash))) throw fail('Mevcut şifre hatalı.', 403);
  const hash = await hashPassword(next);
  // token_version artınca eski oturumlar geçersiz olur.
  await query(`UPDATE users SET password_hash = $1, token_version = token_version + 1, updated_at = NOW() WHERE id = $2`, [hash, req.user.id]);
  hub.disconnectUser(req.user.id, 'password_changed');
  res.json({ ok: true, message: 'Şifre değişti. Lütfen yeniden giriş yapın.' });
});

// Mağaza kuralları gereği uygulama içinden hesap silme.
router.delete('/', async (req, res) => {
  const password = String(req.body?.password ?? '');
  if (!req.user.password_hash || !(await checkPassword(password, req.user.password_hash))) throw fail('Şifre hatalı.', 403);
  const owned = await query(`SELECT 1 FROM families WHERE owner_id = $1 AND is_active = TRUE`, [req.user.id]);
  if (owned.rowCount) throw fail('Önce ailenizin sahipliğini devredin veya aileyi dağıtın.', 409);
  const agency = await query(`SELECT 1 FROM agencies WHERE owner_id = $1 AND status IN ('pending','active','suspended')`, [req.user.id]);
  if (agency.rowCount) throw fail('Önce ajans sahipliği için destek ile iletişime geçin.', 409);
  await tx(async (c) => {
    await c.query(
      `UPDATE users SET account_status = 'deleted', username = 'silinmis_' || substr(id::text, 1, 8), display_name = 'Silinmiş Kullanıcı',
         password_hash = NULL, avatar_url = NULL, cover_url = NULL, bio = NULL, birth_date = NULL, country = NULL, city = NULL,
         is_hidden = FALSE, token_version = token_version + 1, updated_at = NOW() WHERE id = $1`,
      [req.user.id],
    );
    await c.query(`DELETE FROM room_members WHERE user_id = $1`, [req.user.id]);
    await c.query(`DELETE FROM family_members WHERE user_id = $1`, [req.user.id]);
    await c.query(`DELETE FROM follows WHERE follower_id = $1 OR followed_id = $1`, [req.user.id]);
    await c.query(`UPDATE broadcasters SET agency_id = NULL, status = 'suspended' WHERE user_id = $1`, [req.user.id]);
  });
  hub.disconnectUser(req.user.id, 'deleted');
  res.json({ ok: true });
});

router.post('/kyc/request', async (req, res) => {
  const r = await query(`UPDATE users SET kyc_status = 'pending' WHERE id = $1 AND kyc_status IN ('none','rejected') RETURNING kyc_status`, [req.user.id]);
  if (!r.rowCount) throw fail('Kimlik doğrulama başvurunuz zaten var veya onaylı.', 409);
  res.json({ ok: true, kycStatus: 'pending' });
});

// Elmas bozdurma: 5 Elmas = 1 Coin. Onaylı yayıncılar maaş sistemiyle ödendiği için bozduramaz.
export const DIAMONDS_PER_COIN = 5n;
router.post('/diamonds/exchange', userLimit('diamond_exchange', 20, 10 * 60e3), async (req, res) => {
  const raw = req.body?.diamonds;
  if (!/^\d{1,12}$/.test(String(raw ?? ''))) throw fail('Geçerli bir elmas miktarı girin.');
  const diamonds = BigInt(raw);
  if (diamonds < DIAMONDS_PER_COIN || diamonds % DIAMONDS_PER_COIN !== 0n) throw fail('Miktar 5 ve katları olmalı (5 Elmas = 1 Coin).');
  const coins = diamonds / DIAMONDS_PER_COIN;
  const out = await tx(async (c) => {
    const u = (await c.query(`SELECT coins, diamonds FROM users WHERE id = $1 FOR UPDATE`, [req.user.id])).rows[0];
    const b = (await c.query(`SELECT 1 FROM broadcasters WHERE user_id = $1 AND status = 'approved'`, [req.user.id])).rowCount;
    if (b) throw fail('Onaylı yayıncılar elmasları maaş sistemiyle alır; bozdurma yapılamaz.', 403);
    if (BigInt(u.diamonds) < diamonds) throw fail('Yeterli elmasınız yok.', 409);
    const n = (await c.query(`UPDATE users SET diamonds = diamonds - $2, coins = coins + $3, updated_at = NOW() WHERE id = $1 RETURNING coins, diamonds`, [req.user.id, diamonds.toString(), coins.toString()])).rows[0];
    await c.query(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, diamond_amount, description) VALUES($1,'diamond_exchange',$2,$3,$4)`,
      [req.user.id, coins.toString(), (-diamonds).toString(), `${diamonds} Elmas → ${coins} Coin`],
    );
    return n;
  });
  res.json({ ok: true, coins: String(out.coins), diamonds: String(out.diamonds), exchangedCoins: coins.toString() });
});

router.get('/wallet', async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 50, 100);
  const r = await query(
    `SELECT id, transaction_type, coin_amount, diamond_amount, description, created_at
     FROM wallet_transactions WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2`,
    [req.user.id, limit],
  );
  res.json({
    transactions: r.rows.map((x) => ({
      id: x.id, type: x.transaction_type, coinAmount: String(x.coin_amount ?? 0),
      diamondAmount: String(x.diamond_amount ?? 0), description: x.description, createdAt: x.created_at,
    })),
  });
});

// Profil ziyaretçileri: sayı herkese açık, liste WIP kademesine bağlı (viewVisitors).
router.get('/visitors', async (req, res) => {
  const wip = await activeWip(req.user.id);
  if (!wip?.features.viewVisitors) throw fail('Ziyaretçi listesi WIP 2 ve üzeri için açıktır.', 403);
  const r = await query(
    `SELECT ${USER_PUBLIC_COLUMNS}, pv.visit_count, pv.last_visited_at
     FROM profile_visitors pv JOIN users u ON u.id = pv.visitor_id ${USER_PUBLIC_JOINS}
     WHERE pv.profile_user_id = $1 ORDER BY pv.last_visited_at DESC LIMIT 50`,
    [req.user.id],
  );
  res.json({
    visitors: r.rows.map((x) => ({ user: publicUser(x, req.user.id), visitCount: x.visit_count, lastVisitedAt: x.last_visited_at })),
  });
});
