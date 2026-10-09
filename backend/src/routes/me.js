import { Router } from 'express';
import express from 'express';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { query, tx } from '../database.js';
import { requireAuth, checkPassword, hashPassword, passwordRules } from '../auth.js';
import { fail, text, oneOf, httpsUrl } from '../http.js';
import { levelInfo } from '../levels.js';
import { loadProfile } from '../services/profile.js';
import { activeWip, featuresFor } from '../services/wip.js';
import { isAnimatedImage, mimeFor } from '../services/media.js';
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
  if (b.avatarUrl !== undefined) { set('avatar_url', b.avatarUrl === null ? null : httpsUrl(b.avatarUrl, 'Avatar adresi')); set('avatar_animated', false); set('static_avatar_url', null); }
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

function imageUpload(column, allowAnimated = false) {
  const types = allowAnimated ? [...Object.keys(IMAGE_TYPES), 'image/gif'] : Object.keys(IMAGE_TYPES);
  const parser = express.raw({ type: types, limit: allowAnimated ? '6mb' : '3mb' });
  return [parser, async (req, res) => {
    const buf = req.body;
    if (!Buffer.isBuffer(buf) || !buf.length) throw fail('Görsel gönderilmedi (png, jpeg veya webp).');
    const animated = allowAnimated ? isAnimatedImage(buf) : null;
    let url;
    if (animated) {
      // Hareketli profil fotoğrafı: WIP 5 özelliği; veritabanında saklanır (sunucu yenilense de kaybolmaz).
      if (!(await featuresFor(req.user.id)).animatedAvatar) throw fail('Hareketli profil fotoğrafı WIP 5 özelliğidir.', 403);
      if (buf.length > 5 * 1024 * 1024) throw fail('Hareketli fotoğraf 5 MB’tan küçük olmalı.');
      const r = await query(
        `INSERT INTO media_files(kind, mime, ext, size_bytes, data, created_by) VALUES($1,$2,$3,$4,$5,$6) RETURNING id`,
        [animated, mimeFor(animated), animated, buf.length, buf, req.user.id],
      );
      url = `/media/${r.rows[0].id}.${animated}`;
      // Önceki sabit fotoğraf yedeklenir; WIP 5 bitince ona dönülür.
      await query(
        `UPDATE users SET static_avatar_url = CASE WHEN avatar_animated THEN static_avatar_url ELSE avatar_url END, avatar_animated = TRUE, avatar_url = $1, updated_at = NOW() WHERE id = $2`,
        [url, req.user.id],
      );
      return res.json({ url, animated: true });
    } else {
      const kind = detectImage(buf);
      if (!kind || kind !== req.headers['content-type']?.split(';')[0]) throw fail('Görsel biçimi geçersiz.');
      if (buf.length > 3 * 1024 * 1024) throw fail('Görsel 3 MB’tan küçük olmalı.');
      await fs.mkdir(config.uploadDir, { recursive: true });
      const name = `${crypto.randomUUID()}.${IMAGE_TYPES[kind]}`;
      await fs.writeFile(path.join(config.uploadDir, name), buf);
      url = `/uploads/${name}`;
    }
    const old = (await query(`SELECT ${column} AS url, static_avatar_url FROM users WHERE id = $1`, [req.user.id])).rows[0];
    if (column === 'avatar_url') {
      await query(`UPDATE users SET avatar_url = $1, avatar_animated = FALSE, static_avatar_url = NULL, updated_at = NOW() WHERE id = $2`, [url, req.user.id]);
      await removeOldUpload(old?.static_avatar_url);
    } else {
      await query(`UPDATE users SET ${column} = $1, updated_at = NOW() WHERE id = $2`, [url, req.user.id]);
    }
    await removeOldUpload(old?.url);
    res.json({ url, animated: false });
  }];
}
router.put('/avatar', ...imageUpload('avatar_url', true));
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

// ---- Gelir Merkezi: yayın özeti (Europe/Istanbul gün/ay sınırları) ----
const TZ = 'Europe/Istanbul';
function monthParam(v) {
  const m = /^(\d{4})-(0[1-9]|1[0-2])$/.exec(String(v ?? ''));
  if (m) return `${m[1]}-${m[2]}`;
  return new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit' }).format(new Date()).slice(0, 7);
}
async function earningsBlock(userId, from, to) {
  // from/to: Istanbul yerel zaman damgası (metin) — yarı açık aralık
  const gifts = await query(
    `SELECT COALESCE(r.room_type, 'audio') AS t, COALESCE(SUM(g.coin_amount), 0)::text AS d
     FROM gift_transactions g LEFT JOIN rooms r ON r.id = g.room_id
     WHERE g.receiver_id = $1 AND g.sender_id <> g.receiver_id
       AND g.created_at >= ($2::timestamp AT TIME ZONE '${TZ}') AND g.created_at < ($3::timestamp AT TIME ZONE '${TZ}')
     GROUP BY 1`,
    [userId, from, to],
  );
  const by = Object.fromEntries(gifts.rows.map((x) => [x.t, BigInt(x.d)]));
  const video = by.video ?? 0n;
  const audio = Object.entries(by).filter(([k]) => k !== 'video').reduce((a, [, v]) => a + v, 0n);
  const mic = (await query(
    `SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (LEAST(COALESCE(ended_at, NOW()), ($3::timestamp AT TIME ZONE '${TZ}')) - GREATEST(started_at, ($2::timestamp AT TIME ZONE '${TZ}'))))), 0)::bigint AS secs,
            COUNT(DISTINCT (GREATEST(started_at, ($2::timestamp AT TIME ZONE '${TZ}')) AT TIME ZONE '${TZ}')::date)::int AS days
     FROM mic_sessions WHERE user_id = $1 AND started_at < ($3::timestamp AT TIME ZONE '${TZ}') AND COALESCE(ended_at, NOW()) > ($2::timestamp AT TIME ZONE '${TZ}')`,
    [userId, from, to],
  )).rows[0];
  return {
    totalDiamonds: String(video + audio), videoDiamonds: String(video), audioDiamonds: String(audio),
    activeDays: mic.days, activeMinutes: Math.floor(Number(mic.secs) / 60),
  };
}

router.get('/earnings/summary', async (req, res) => {
  const month = monthParam(req.query.month);
  const [y, m] = month.split('-').map(Number);
  const next = m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, '0')}`;
  const monthly = await earningsBlock(req.user.id, `${month}-01 00:00:00`, `${next}-01 00:00:00`);
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date());
  const tomorrow = new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date(Date.now() + 86400e3));
  const daily = await earningsBlock(req.user.id, `${today} 00:00:00`, `${tomorrow} 00:00:00`);
  res.json({ month, today, monthly, daily });
});

// Canlı yayın geçmişi (video/sesli): mikrofonda geçirilen oturumlar ve o oturumda alınan elmas.
router.get('/earnings/history', async (req, res) => {
  const type = req.query.type === 'video' ? 'video' : 'audio';
  const offset = Math.max(Number(req.query.offset) || 0, 0);
  const r = await query(
    `SELECT s.started_at, s.ended_at,
            EXTRACT(EPOCH FROM (COALESCE(s.ended_at, NOW()) - s.started_at))::bigint AS secs,
            (SELECT COALESCE(SUM(g.coin_amount), 0)::text FROM gift_transactions g
              WHERE g.receiver_id = s.user_id AND g.sender_id <> g.receiver_id AND g.room_id = s.room_id
                AND g.created_at >= s.started_at AND g.created_at < COALESCE(s.ended_at, NOW())) AS diamonds
     FROM mic_sessions s JOIN rooms rm ON rm.id = s.room_id
     WHERE s.user_id = $1 AND (CASE WHEN rm.room_type = 'video' THEN 'video' ELSE 'audio' END) = $2
     ORDER BY s.started_at DESC LIMIT 10 OFFSET $3`,
    [req.user.id, type, offset],
  );
  const totals = (await query(
    `SELECT COUNT(DISTINCT (s.started_at AT TIME ZONE '${TZ}')::date)::int AS days,
            COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(s.ended_at, NOW()) - s.started_at))), 0)::bigint AS secs
     FROM mic_sessions s JOIN rooms rm ON rm.id = s.room_id
     WHERE s.user_id = $1 AND (CASE WHEN rm.room_type = 'video' THEN 'video' ELSE 'audio' END) = $2`,
    [req.user.id, type],
  )).rows[0];
  const dia = (await query(
    `SELECT COALESCE(SUM(g.coin_amount), 0)::text AS d FROM gift_transactions g LEFT JOIN rooms rm ON rm.id = g.room_id
     WHERE g.receiver_id = $1 AND g.sender_id <> g.receiver_id AND (CASE WHEN rm.room_type = 'video' THEN 'video' ELSE 'audio' END) = $2`,
    [req.user.id, type],
  )).rows[0].d;
  res.json({
    type, offset, hasMore: r.rows.length === 10,
    totals: { activeDays: totals.days, minutes: Math.floor(Number(totals.secs) / 60), diamonds: dia },
    sessions: r.rows.map((x) => ({ startedAt: x.started_at, endedAt: x.ended_at, seconds: Number(x.secs), diamonds: x.diamonds })),
  });
});

// Seviye Merkezi: kullanıcı seviyesi (gönderilen coin) ve yayıncı seviyesi (alınan elmas), 160 kademe.
router.get('/levels', async (req, res) => {
  const u = (await query(`SELECT total_sent_coins, total_received_diamonds FROM users WHERE id = $1`, [req.user.id])).rows[0];
  const user = levelInfo(u.total_sent_coins);
  const broadcaster = levelInfo(u.total_received_diamonds);
  // Eski kayıtlarla uyuşmazlık varsa kendini düzelt.
  await query(`UPDATE users SET coin_level = $2, gift_level = $3 WHERE id = $1 AND (coin_level <> $2 OR gift_level <> $3)`, [req.user.id, user.level, broadcaster.level]);
  res.json({ user, broadcaster });
});

// Kırmızı rozetler (yeni ziyaretçi, yeni takipçi, bekleyen arkadaş isteği).
router.get('/badges', async (req, res) => {
  const r = await query(
    `SELECT (SELECT COUNT(*)::int FROM profile_visitors WHERE profile_user_id = $1 AND last_visited_at > u.visitors_seen_at) AS visitors,
            (SELECT COUNT(*)::int FROM follows WHERE followed_id = $1 AND created_at > u.followers_seen_at) AS followers,
            (SELECT COUNT(*)::int FROM friend_requests WHERE target_id = $1 AND status = 'pending') AS friends
     FROM users u WHERE u.id = $1`,
    [req.user.id],
  );
  const x = r.rows[0] ?? { visitors: 0, followers: 0, friends: 0 };
  res.json({ visitors: x.visitors, followers: x.followers, friends: x.friends, total: x.visitors + x.followers + x.friends });
});

// Liste açılınca rozet sıfırlanır.
router.post('/seen', async (req, res) => {
  const kind = oneOf(req.body?.kind, ['visitors', 'followers'], 'Tür');
  await query(`UPDATE users SET ${kind}_seen_at = NOW() WHERE id = $1`, [req.user.id]);
  res.json({ ok: true });
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
