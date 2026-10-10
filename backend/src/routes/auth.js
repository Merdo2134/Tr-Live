import { cleanPublic } from '../safe_text.js';
import { Router } from 'express';
import { query } from '../database.js';
import { hashPassword, checkPassword, signToken, passwordRules, liftBan, requireAuth, optionalAuth } from '../auth.js';
import { openSession, refreshSession, revokeByRefresh, revokeSession, cleanDevice } from '../services/sessions.js';
import { banExpired, banMessage } from '../staff_logic.js';
import { fail, text } from '../http.js';
import { selfUser } from '../views.js';
import { newPublicId } from '../services/ids.js';
import { ipLimit, loginGuard, clientIp } from '../firewall.js';
import { promoteBootstrapAdmins } from '../services/bootstrap.js';

export const router = Router();
const USERNAME_RE = /^[a-z0-9_.]{3,30}$/;
let dummyHash;

/**
 * Giriş yanıtı. Yeni uygulama "device" alanı gönderir ve cihaz oturumu (kısa erişim + yenileme token'ı) alır.
 * Cihaz bilgisi göndermeyen eski sürümler, yenileme bilmedikleri için eskisi gibi 30 günlük token alır.
 */
async function tokensFor(user, req) {
  if (!req.body?.device || typeof req.body.device !== 'object') return { token: signToken(user) };
  const s = await openSession(user, cleanDevice(req.body.device), clientIp(req));
  return { token: s.token, refreshToken: s.refreshToken, expiresIn: s.expiresIn };
}

router.post('/register', ipLimit('register', 5, 3600e3), async (req, res) => {
  const username = String(req.body?.username ?? '').trim().toLowerCase();
  if (!USERNAME_RE.test(username)) {
    throw fail('Kullanıcı adı 3-30 karakter olmalı; yalnızca harf, rakam, nokta ve alt çizgi kullanılabilir.');
  }
  const password = String(req.body?.password ?? '');
  passwordRules(password);
  const displayName = cleanPublic(text(req.body?.displayName || username, 'Ad', { min: 1, max: 60 }), 'Ad');cleanPublic(username, 'Kullanıcı adı');
  const passwordHash = await hashPassword(password);
  try {
    const publicId = await newPublicId();
    const r = await query(
      `INSERT INTO users(username, display_name, password_hash, public_id) VALUES($1,$2,$3,$4) RETURNING *`,
      [username, displayName, passwordHash, publicId],
    );
    const row = r.rows[0];
    if (await promoteBootstrapAdmins(row.username)) row.system_role = 'admin';
    res.status(201).json({ ...(await tokensFor(row, req)), user: selfUser(row) });
  } catch (error) {
    if (error.code === '23505') throw fail('Kullanıcı adı zaten kullanılıyor.', 409);
    throw error;
  }
});

router.post('/login', ipLimit('login', 30, 15 * 60e3), async (req, res) => {
  const username = String(req.body?.username ?? '').trim().toLowerCase().slice(0, 40);
  const password = String(req.body?.password ?? '').slice(0, 200);
  const guard = loginGuard(clientIp(req), username);
  guard.check(); // çok sayıda hatalı denemeden sonra geçici kilit
  const user = (await query(`SELECT * FROM users WHERE lower(username) = $1`, [username])).rows[0];
  // Kullanıcı yoksa da bcrypt çalıştırılır; böylece yanıt süresinden kullanıcı adı sızmaz.
  dummyHash ??= await hashPassword('dummy-password-for-timing');
  const ok = await checkPassword(password, user?.password_hash || dummyHash);
  if (!user || !user.password_hash || !ok) { guard.failed(); throw fail('Giriş bilgileri hatalı.', 401); }
  guard.succeeded();
  let acct = user;
  if (banExpired(acct)) acct = await liftBan(acct);
  if (acct.account_status === 'banned') throw fail(banMessage(acct), 403);
  if (acct.account_status !== 'active') throw fail('Hesap askıya alınmış veya silinmiş.', 403);
  res.json({ ...(await tokensFor(acct, req)), user: selfUser(acct) });
});

// Erişim token'ını yeniler. Yenileme token'ı her seferinde değişir; uygulama yenisini saklamalıdır.
router.post('/refresh', ipLimit('refresh', 600, 15 * 60e3), async (req, res) => {
  const device = cleanDevice(req.body?.device);
  res.json(await refreshSession(req.body?.refreshToken, clientIp(req), device));
});

// Eski (30 günlük) token ile giriş yapmış uygulama güncellenince cihaz oturumuna geçer; yeniden giriş gerekmez.
router.post('/session', requireAuth, ipLimit('session_upgrade', 30, 15 * 60e3), async (req, res) => {
  if (req.user.session_id) throw fail('Bu cihazda zaten oturum var.', 409);
  const legacy = (req.headers.authorization || '').slice(7);
  const s = await openSession(req.user, cleanDevice(req.body?.device), clientIp(req), legacy);
  res.json({ token: s.token, refreshToken: s.refreshToken, expiresIn: s.expiresIn });
});

// Çıkış: bu cihazın oturumu sunucuda da kapanır (erişim token'ının süresi dolmuş olsa bile yenileme token'ıyla).
router.post('/logout', ipLimit('logout', 60, 15 * 60e3), optionalAuth, async (req, res) => {
  let n = await revokeByRefresh(req.body?.refreshToken, 'logout');
  if (!n && req.user?.session_id) n = await revokeSession(req.user.id, req.user.session_id, 'logout');
  res.json({ ok: true, revoked: n });
});
