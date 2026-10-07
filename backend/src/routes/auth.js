import { cleanPublic } from '../safe_text.js';
import { Router } from 'express';
import { query } from '../database.js';
import { hashPassword, checkPassword, signToken, passwordRules, liftBan } from '../auth.js';
import { banExpired, banMessage } from '../staff_logic.js';
import { fail, text } from '../http.js';
import { selfUser } from '../views.js';
import { ipLimit, loginGuard, clientIp } from '../firewall.js';

export const router = Router();
const USERNAME_RE = /^[a-z0-9_.]{3,30}$/;
let dummyHash;

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
    const r = await query(
      `INSERT INTO users(username, display_name, password_hash) VALUES($1,$2,$3) RETURNING *`,
      [username, displayName, passwordHash],
    );
    res.status(201).json({ token: signToken(r.rows[0]), user: selfUser(r.rows[0]) });
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
  res.json({ token: signToken(acct), user: selfUser(acct) });
});
