import crypto from 'node:crypto';
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
export async function tokensFor(user, req) {
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

/**
 * Telefon numarasını tek biçime çevirir (+905xxxxxxxxx). Türkiye numaraları 0 / 90 / 5 ile yazılabilir;
 * yabancı numara + ile ve ülke koduyla yazılır. Geçersizse null.
 */
export function normalizePhone(input) {
  let s = String(input ?? '').replace(/[\s\-().]/g, '');
  if (!s) return null;
  if (s.startsWith('00')) s = `+${s.slice(2)}`;
  if (/^0?5\d{9}$/.test(s)) s = `+90${s.replace(/^0/, '')}`;
  else if (/^905\d{9}$/.test(s)) s = `+${s}`;
  if (!/^\+[1-9]\d{7,14}$/.test(s)) return null;
  if (s.startsWith('+90') && !/^\+905\d{9}$/.test(s)) return null; // Türkiye: yalnızca cep numarası
  return s;
}
const looksLikePhone = (v) => /^[+\d][\d\s\-()]{8,}$/.test(v);

// Telefon numarasıyla kayıt (SMS kodu yok): numara + şifre + görünen ad. Numara benzersizdir.
router.post('/register-phone', ipLimit('register', 5, 3600e3), async (req, res) => {
  const phone = normalizePhone(req.body?.phone);
  if (!phone) throw fail('Geçerli bir cep telefonu numarası girin (ör. 0555 123 45 67).');
  const password = String(req.body?.password ?? '');
  passwordRules(password);
  const displayName = cleanPublic(text(req.body?.displayName, 'Ad', { min: 1, max: 60 }), 'Ad');
  if ((await query(`SELECT 1 FROM users WHERE phone = $1`, [phone])).rowCount) throw fail('Bu telefon numarasıyla zaten bir hesap var. Giriş yapın.', 409);
  const passwordHash = await hashPassword(password);
  const row = await createAccount({ displayName, passwordHash, phone, prefix: 't' });
  res.status(201).json({ ...(await tokensFor(row, req)), user: selfUser(row) });
});

/** Yeni hesap: kullanıcı adı otomatik (ör. g_48392011), görünen ad verilen. Telefon / şifre isteğe bağlı. */
export async function createAccount({ displayName, passwordHash = null, phone = null, prefix = 'u' }, run = query, inTx = false) {
  for (let i = 0; i < 10; i += 1) {
    const username = `${prefix}_${crypto.randomInt(10_000_000, 99_999_999)}`;
    // İşlem (transaction) içindeyken çakışma tüm işlemi bozmasın: her deneme bir kayıt noktasında.
    let sp = inTx;
    if (sp) await run('SAVEPOINT create_account');
    try {
      const publicId = await newPublicId(run);
      const row = (await run(
        `INSERT INTO users(username, display_name, password_hash, public_id, phone) VALUES($1,$2,$3,$4,$5) RETURNING *`,
        [username, displayName, passwordHash, publicId, phone],
      )).rows[0];
      if (sp) {
        await run('RELEASE SAVEPOINT create_account');
        sp = false;
      }
      if (await promoteBootstrapAdmins(row.username)) row.system_role = 'admin';
      return row;
    } catch (error) {
      if (sp) await run('ROLLBACK TO SAVEPOINT create_account');
      if (error.code !== '23505') throw error;
      if (phone && /phone/.test(String(error.constraint ?? error.detail ?? ''))) throw fail('Bu telefon numarasıyla zaten bir hesap var. Giriş yapın.', 409);
    }
  }
  throw new Error('Hesap oluşturulamadı.');
}

/** Giriş öncesi hesap durumu: süresi dolan yasak kaldırılır; yasaklı / askıdaki hesap reddedilir. */
export async function checkAccount(user) {
  let acct = user;
  if (banExpired(acct)) acct = await liftBan(acct);
  if (acct.account_status === 'banned') throw fail(banMessage(acct), 403);
  if (acct.account_status !== 'active') throw fail('Hesap askıya alınmış veya silinmiş.', 403);
  return acct;
}

router.post('/login', ipLimit('login', 30, 15 * 60e3), async (req, res) => {
  const raw = String(req.body?.username ?? '').trim();
  // Kullanıcı adı ya da telefon numarası ile giriş.
  const phone = looksLikePhone(raw) ? normalizePhone(raw) : null;
  const username = phone ?? raw.toLowerCase().slice(0, 40);
  const password = String(req.body?.password ?? '').slice(0, 200);
  const guard = loginGuard(clientIp(req), username);
  guard.check(); // çok sayıda hatalı denemeden sonra geçici kilit
  let user = phone ? (await query(`SELECT * FROM users WHERE phone = $1`, [phone])).rows[0] : null;
  // Rakamlardan oluşan eski kullanıcı adları telefon gibi görünebilir: bulunamazsa kullanıcı adı olarak da bakılır.
  user ??= (await query(`SELECT * FROM users WHERE lower(username) = $1`, [raw.toLowerCase().slice(0, 40)])).rows[0];
  // Kullanıcı yoksa da bcrypt çalıştırılır; böylece yanıt süresinden kullanıcı adı sızmaz.
  dummyHash ??= await hashPassword('dummy-password-for-timing');
  const ok = await checkPassword(password, user?.password_hash || dummyHash);
  if (!user || !user.password_hash || !ok) { guard.failed(); throw fail('Giriş bilgileri hatalı.', 401); }
  guard.succeeded();
  const acct = await checkAccount(user);
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
