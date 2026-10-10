import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import { query, tx } from '../database.js';
import { jwtSecret } from '../config.js';
import { fail } from '../http.js';
import { hub } from '../realtime.js';
import { banExpired, banMessage } from '../staff_logic.js';

// Erişim token'ı kısa ömürlüdür; uygulama süresi dolmadan yenileme token'ıyla yenisini alır.
export const ACCESS_TTL_SEC = 60 * 60;
// Yenileme token'ı her kullanımda süresini uzatır; 60 gün hiç açılmayan cihazın oturumu düşer.
export const REFRESH_TTL_DAYS = 60;
// Yanıtı ağda kaybolan yenileme isteği tekrar gelirse (aynı eski token ile) bu süre içinde kabul edilir.
// Uzun tutulur: telefon ağdan düşüp dakikalar sonra dönerse kullanıcı haksız yere oturumdan atılmasın.
export const REUSE_GRACE_MS = 15 * 60 * 1000;
export const MAX_SESSIONS_PER_USER = 10;

const sha = (t) => crypto.createHash('sha256').update(t).digest('hex');
const newRefresh = () => `rt_${crypto.randomBytes(32).toString('base64url')}`;
export const REFRESH_RE = /^rt_[A-Za-z0-9_-]{43}$/;
const EXPIRED = 'Oturum süresi doldu. Lütfen yeniden giriş yapın.';

export function signAccess(user, sid) {
  return jwt.sign({ sub: user.id, tv: user.token_version ?? 0, sid }, jwtSecret(), { expiresIn: ACCESS_TTL_SEC, algorithm: 'HS256' });
}

/** İstemcinin gönderdiği cihaz bilgisini temizler. Hiçbir alan zorunlu değildir. */
export function cleanDevice(raw) {
  const d = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  const str = (v, max) => (typeof v === 'string' ? v.replace(/[\u0000-\u001f\u007f​-‏‪-‮]/g, '').trim().slice(0, max) || null : null);
  const id = str(d.id, 64);
  const version = str(d.appVersion, 20);
  return {
    id: id && /^[A-Za-z0-9_-]{8,64}$/.test(id) ? id : null,
    name: str(d.name, 80),
    platform: ['android', 'ios'].includes(d.platform) ? d.platform : null,
    appVersion: version && /^\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(version) ? version : null,
    emulator: d.emulator === true,
  };
}

/** IP'nin yalnızca ilk yarısı gösterilir (kişisel veri). */
export function maskIp(ip) {
  if (!ip) return null;
  const v4 = /^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$/.exec(ip);
  if (v4) return `${v4[1]}.${v4[2]}.x.x`;
  const parts = ip.split(':').filter(Boolean);
  return parts.length >= 2 ? `${parts[0]}:${parts[1]}:…` : null;
}

async function revokeWhere(sql, params, reason) {
  const r = await query(`UPDATE user_sessions SET revoked_at = NOW(), revoke_reason = $${params.length + 1} WHERE revoked_at IS NULL AND ${sql} RETURNING id`, [...params, reason]);
  for (const row of r.rows) hub.disconnectSession(row.id);
  return r.rowCount;
}

/**
 * Yeni cihaz oturumu açar (giriş/kayıt/eski token yükseltme). Kayıt yalnızca kullanıcının token sürümü hâlâ
 * okunduğu andaki gibiyse yazılır: giriş sürerken şifre değişir veya ban gelirse oturum açılmaz (yarış koşulu).
 * legacyToken: eski tip 30 günlük token'dan yükseltmede, aynı token'ın ikinci kez yükseltilmesini önler.
 */
export async function openSession(user, device, ip, legacyToken = null) {
  const refresh = newRefresh();
  const r = await query(
    `INSERT INTO user_sessions(user_id, refresh_hash, device_id, device_name, platform, app_version, emulator, ip, expires_at, legacy_hash)
     SELECT $1,$2,$3,$4,$5,$6,$7,$8, NOW() + make_interval(days => $9::int), $11
     WHERE EXISTS (SELECT 1 FROM users WHERE id = $1 AND token_version = $10 AND account_status = 'active')
     ON CONFLICT DO NOTHING
     RETURNING id`,
    [user.id, sha(refresh), device.id, device.name, device.platform, device.appVersion, device.emulator, ip ?? null, REFRESH_TTL_DAYS,
      user.token_version ?? 0, legacyToken ? sha(legacyToken) : null],
  );
  if (!r.rowCount) throw fail(legacyToken ? 'Bu oturum zaten yükseltilmiş. Lütfen yeniden giriş yapın.' : EXPIRED, legacyToken ? 409 : 401);
  const sid = r.rows[0].id;
  // Aynı cihazdan yeniden giriş: o cihazın daha ÖNCE açılmış oturumu kapanır (liste şişmesin).
  if (device.id) {
    await revokeWhere(
      `user_id = $1 AND device_id = $2 AND id <> $3 AND created_at <= (SELECT created_at FROM user_sessions WHERE id = $3)`,
      [user.id, device.id, sid], 'replaced',
    );
  }
  // Kullanıcı başına en fazla 10 açık oturum; en uzun süredir kullanılmayanlar kapanır.
  await revokeWhere(
    `id IN (SELECT id FROM user_sessions WHERE user_id = $1 AND revoked_at IS NULL ORDER BY last_used_at DESC OFFSET $2)`,
    [user.id, MAX_SESSIONS_PER_USER], 'limit',
  );
  return { token: signAccess(user, sid), refreshToken: refresh, expiresIn: ACCESS_TTL_SEC, sessionId: sid };
}

/**
 * Yenileme token'ıyla yeni erişim + yenileme token'ı verir (rotasyon).
 * Eski bir token kabul süresinden sonra tekrar kullanılırsa token çalınmış sayılır ve oturum kapatılır.
 */
export async function refreshSession(token, ip, device) {
  if (typeof token !== 'string' || !REFRESH_RE.test(token)) throw fail(EXPIRED, 401);
  const h = sha(token);
  const result = await tx(async (c) => {
    let s = (await c.query(`SELECT * FROM user_sessions WHERE refresh_hash = $1 FOR UPDATE`, [h])).rows[0];
    let viaPrev = false;
    if (!s) {
      s = (await c.query(`SELECT * FROM user_sessions WHERE prev_hash = $1 FOR UPDATE`, [h])).rows[0];
      viaPrev = Boolean(s);
    }
    if (!s || s.revoked_at || new Date(s.expires_at) <= new Date()) return { error: EXPIRED };
    if (viaPrev && (!s.rotated_at || Date.now() - new Date(s.rotated_at).getTime() > REUSE_GRACE_MS)) {
      await c.query(`UPDATE user_sessions SET revoked_at = NOW(), revoke_reason = 'reuse' WHERE id = $1`, [s.id]);
      return { error: 'Oturumunuz güvenlik nedeniyle kapatıldı. Lütfen yeniden giriş yapın.', revoked: s.id };
    }
    const user = (await c.query(`SELECT * FROM users WHERE id = $1`, [s.user_id])).rows[0];
    if (!user) return { error: EXPIRED };
    if (user.account_status === 'banned' && !banExpired(user)) return { error: banMessage(user), status: 403 };
    if (user.account_status === 'deleted') return { error: EXPIRED };
    const next = newRefresh();
    await c.query(
      `UPDATE user_sessions SET refresh_hash = $2, prev_hash = $3, rotated_at = NOW(), last_used_at = NOW(),
         ip = COALESCE($4, ip), app_version = COALESCE($5, app_version), expires_at = NOW() + make_interval(days => $6::int)
       WHERE id = $1`,
      [s.id, sha(next), s.refresh_hash, ip ?? null, device?.appVersion ?? null, REFRESH_TTL_DAYS],
    );
    return { user, sid: s.id, refreshToken: next };
  });
  if (result.error) {
    if (result.revoked) hub.disconnectSession(result.revoked);
    throw fail(result.error, result.status ?? 401);
  }
  // Süresi dolmuş ban: hesap yeniden aktif edilir (authenticateToken ile aynı davranış).
  if (result.user.account_status === 'banned') {
    await query(`UPDATE users SET account_status = 'active', banned_until = NULL, ban_reason = NULL, banned_by = NULL, updated_at = NOW() WHERE id = $1 AND account_status = 'banned'`, [result.user.id]);
  }
  return { token: signAccess(result.user, result.sid), refreshToken: result.refreshToken, expiresIn: ACCESS_TTL_SEC, sessionId: result.sid };
}

/** Çıkış: yenileme token'ıyla (erişim token'ının süresi dolmuş olsa bile) oturumu kapatır. */
export async function revokeByRefresh(token, reason = 'logout') {
  if (typeof token !== 'string' || !REFRESH_RE.test(token)) return 0;
  const h = sha(token);
  return revokeWhere('(refresh_hash = $1 OR prev_hash = $1)', [h], reason);
}

export const revokeSession = (userId, sid, reason) => revokeWhere('user_id = $1 AND id = $2', [userId, sid], reason);
export const revokeAllSessions = (userId, reason) => revokeWhere('user_id = $1', [userId], reason);
export const revokeOtherSessions = (userId, keepSid, reason) => revokeWhere('user_id = $1 AND id <> $2', [userId, keepSid], reason);

// Oturumun "son kullanım" zamanı her istekte değil, en fazla 5 dakikada bir yazılır.
const touched = new Map();
export function touchSession(sid) {
  if (!sid) return;
  const now = Date.now();
  if (now - (touched.get(sid) ?? 0) < 5 * 60e3) return;
  if (touched.size > 20000) touched.clear();
  touched.set(sid, now);
  query(`UPDATE user_sessions SET last_used_at = NOW() WHERE id = $1`, [sid]).catch(() => {});
}

export async function listSessions(userId, currentSid) {
  const r = await query(
    `SELECT id, device_name, platform, app_version, emulator, ip, created_at, last_used_at FROM user_sessions
     WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > NOW() ORDER BY last_used_at DESC LIMIT 20`,
    [userId],
  );
  return r.rows.map((x) => ({
    id: x.id, deviceName: x.device_name, platform: x.platform, appVersion: x.app_version, emulator: x.emulator,
    ip: maskIp(x.ip), createdAt: x.created_at, lastUsedAt: x.last_used_at, current: x.id === currentSid,
  }));
}
