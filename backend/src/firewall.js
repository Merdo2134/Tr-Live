import net from 'node:net';
import { query } from './database.js';
import { config } from './config.js';
import { fail } from './http.js';
import {
  SlidingWindowLimiter, LockoutTracker, BanList, ViolationTracker, inspectRequest, jsonShapeProblem, normalizeIp,
} from './firewall_core.js';

// Uygulama katmanı güvenlik duvarı (WAF-lite). Ağ katmanı koruması (ufw, nginx, Cloudflare) AYRICA gereklidir: bkz. deploy/.
const limiter = new SlidingWindowLimiter();
const bans = new BanList();
const violations = new ViolationTracker({ threshold: config.firewall.banThreshold });
const ipLockout = new LockoutTracker({ maxFailures: 5, windowMs: 15 * 60e3, lockMs: 15 * 60e3 });
const nameLockout = new LockoutTracker({ maxFailures: 20, windowMs: 60 * 60e3, lockMs: 30 * 60e3 });
const allow = new Set(config.firewall.allowIps);

export const clientIp = (req) => normalizeIp(req.ip || req.socket?.remoteAddress);

/** WebSocket el sıkışması için IP (tek güvenilir ters vekil varsayımıyla sağdaki X-Forwarded-For girdisi). */
export function wsClientIp(req) {
  const xff = req.headers['x-forwarded-for'];
  if (config.trustProxy && typeof xff === 'string' && xff) return normalizeIp(xff.split(',').pop());
  return normalizeIp(req.socket?.remoteAddress);
}

// Güvenlik günlüğü hiçbir koşulda isteği bozmamalı (veritabanı yoksa/çökmüşse sessizce geçilir).
function safeQuery(sql, params) {
  try { return Promise.resolve(query(sql, params)).catch(() => {}); } catch { return Promise.resolve(); }
}

let eventCount = 0;
export function logSecurityEvent(type, ip, userId = null, detail = {}) {
  // Günlük taşmasına karşı: dakikada en fazla 120 olay veritabanına yazılır.
  if (!limiter.hit('secevt', 120, 60e3).allowed) return;
  eventCount += 1;
  console.warn(JSON.stringify({ security: type, ip, userId, ...detail }));
  const validIp = ip && net.isIP(ip) ? ip : null;
  safeQuery(`INSERT INTO security_events(event_type, ip, user_id, detail) VALUES($1,$2,$3,$4)`, [type, validIp, userId, JSON.stringify(detail)]);
}

export function banIp(ip, ms, reason, createdBy = null) {
  if (allow.has(ip)) return false;
  bans.ban(ip, ms, reason);
  if (net.isIP(ip)) {
    const expires = ms == null ? null : new Date(Date.now() + ms).toISOString();
    safeQuery(
      `INSERT INTO firewall_blocks(ip, reason, expires_at, created_by) VALUES($1,$2,$3,$4)
       ON CONFLICT (ip) DO UPDATE SET reason = EXCLUDED.reason, expires_at = EXCLUDED.expires_at, created_by = EXCLUDED.created_by, created_at = NOW()`,
      [ip, reason, expires, createdBy],
    );
  }
  logSecurityEvent('ip_banned', ip, createdBy, { reason, ms });
  return true;
}

/** Yönetici işlemi: yasak veritabanına yazılana kadar bekler (yazılamazsa hata verir). */
export async function banIpPersist(ip, ms, reason, createdBy = null) {
  if (allow.has(ip)) return false;
  bans.ban(ip, ms, reason);
  const expires = ms == null ? null : new Date(Date.now() + ms).toISOString();
  await query(
    `INSERT INTO firewall_blocks(ip, reason, expires_at, created_by) VALUES($1,$2,$3,$4)
     ON CONFLICT (ip) DO UPDATE SET reason = EXCLUDED.reason, expires_at = EXCLUDED.expires_at, created_by = EXCLUDED.created_by, created_at = NOW()`,
    [ip, reason, expires, createdBy],
  );
  logSecurityEvent('ip_banned', ip, createdBy, { reason, ms });
  return true;
}

export async function unbanIp(ip) {
  bans.unban(ip);
  if (net.isIP(ip)) await query(`DELETE FROM firewall_blocks WHERE ip = $1`, [ip]);
}

export const isBanned = (ip) => !allow.has(ip) && bans.isBanned(ip);

/** İhlal puanı ekler; eşik aşılırsa IP'yi otomatik yasaklar. */
export function noteViolation(ip, type, { userId = null, weight = 1, detail = {} } = {}) {
  if (!config.firewall.enabled || allow.has(ip)) return;
  logSecurityEvent(`violation:${type}`.slice(0, 40), ip, userId, detail);
  const r = violations.record(ip, weight);
  if (r.ban) banIp(ip, r.durationMs, `Otomatik: ${type} (puan ${r.score})`);
}

export async function loadBans() {
  const r = await query(`SELECT ip, reason, expires_at FROM firewall_blocks WHERE expires_at IS NULL OR expires_at > NOW()`);
  for (const b of r.rows) bans.ban(normalizeIp(b.ip), b.expires_at ? new Date(b.expires_at).getTime() - Date.now() : null, b.reason || '');
  return r.rowCount;
}

export function startFirewallJanitor() {
  const t = setInterval(() => { limiter.prune(); ipLockout.prune(); nameLockout.prune(); violations.prune(); }, 5 * 60e3);
  t.unref();
  return t;
}

// ---------------- Express ara katmanları ----------------
export function firewall() {
  return (req, res, next) => {
    if (!config.firewall.enabled) return next();
    const ip = clientIp(req);
    if (allow.has(ip)) return next();
    if (bans.isBanned(ip)) return res.status(403).json({ message: 'Erişiminiz geçici olarak engellendi.' });

    const rule = inspectRequest(req.originalUrl, req.headers['user-agent']);
    if (rule) {
      noteViolation(ip, rule, { weight: 5, detail: { path: String(req.originalUrl).slice(0, 120) } });
      return res.status(403).json({ message: 'İstek reddedildi.' });
    }
    const r = limiter.hit(`ip:${ip}`, config.firewall.ipPerMinute, 60e3);
    if (!r.allowed) {
      noteViolation(ip, 'rate_limit');
      res.set('Retry-After', String(Math.ceil(r.retryAfterMs / 1000)));
      return res.status(429).json({ message: 'Çok fazla istek gönderildi. Lütfen biraz bekleyin.' });
    }
    next();
  };
}

/** JSON gövde şeklini denetler (derinlik, boyut, prototype pollution). express.json'dan sonra kullanılır. */
export function bodyGuard() {
  return (req, res, next) => {
    if (req.body && typeof req.body === 'object') {
      const problem = jsonShapeProblem(req.body);
      if (problem) {
        noteViolation(clientIp(req), `body_${problem}`, { weight: 3 });
        return res.status(400).json({ message: 'Geçersiz istek gövdesi.' });
      }
    }
    next();
  };
}

function limiterMiddleware(name, limit, windowMs, byUser) {
  return (req, res, next) => {
    if (!config.firewall.enabled) return next();
    const ip = clientIp(req);
    const who = byUser && req.user ? `u:${req.user.id}` : `ip:${ip}`;
    const r = limiter.hit(`${name}:${who}`, limit, windowMs);
    if (r.allowed) return next();
    noteViolation(ip, `limit_${name}`, { userId: req.user?.id ?? null });
    res.set('Retry-After', String(Math.ceil(r.retryAfterMs / 1000)));
    next(fail('Çok hızlı işlem yapıyorsunuz. Lütfen biraz bekleyin.', 429));
  };
}
/** Giriş yapmış kullanıcı başına sınır (requireAuth'tan sonra). */
export const userLimit = (name, limit, windowMs) => limiterMiddleware(name, limit, windowMs, true);
/** IP başına sınır (giriş gerektirmeyen uçlar için). */
export const ipLimit = (name, limit, windowMs) => limiterMiddleware(name, limit, windowMs, false);

// ---------------- Giriş kilidi (kaba kuvvet koruması) ----------------
export function loginGuard(ip, username) {
  const ipKey = `${ip}|${username}`;
  const nameKey = `n|${username}`;
  return {
    check() {
      const ms = Math.max(ipLockout.lockedFor(ipKey), nameLockout.lockedFor(nameKey));
      if (ms > 0) {
        noteViolation(ip, 'login_locked', { weight: 1 });
        throw fail(`Çok fazla hatalı deneme. ${Math.ceil(ms / 60000)} dakika sonra tekrar deneyin.`, 429);
      }
    },
    failed() {
      const a = ipLockout.fail(ipKey);
      nameLockout.fail(nameKey);
      noteViolation(ip, 'login_failed', { weight: 1 });
      if (a.locked) logSecurityEvent('login_lockout', ip, null, { username });
    },
    succeeded() { ipLockout.success(ipKey); nameLockout.success(nameKey); },
  };
}

/** Serbest anahtarlı sınır (ör. oda şifresi denemesi). */
export const hitLimit = (key, limit, windowMs) => limiter.hit(key, limit, windowMs);

export const securityStats = () => ({ bans: bans.list().length, eventsLogged: eventCount, limiterKeys: limiter.size });
export const listBans = () => bans.list();
