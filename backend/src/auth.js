import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { query } from './database.js';
import { jwtSecret } from './config.js';
import { fail } from './http.js';

export const hashPassword = (p) => bcrypt.hash(p, 12);
export const checkPassword = (p, h) => bcrypt.compare(p, h);

export function passwordRules(password) {
  if (typeof password !== 'string' || password.length < 6) throw fail('Şifre en az 6 karakter olmalı.');
  if (Buffer.byteLength(password, 'utf8') > 72) throw fail('Şifre en fazla 72 bayt olabilir.');
}

export const signToken = (u) => jwt.sign({ sub: u.id, tv: u.token_version ?? 0 }, jwtSecret(), { expiresIn: '30d', algorithm: 'HS256' });

export async function loadUser(id) {
  const r = await query('SELECT * FROM users WHERE id = $1', [id]);
  return r.rows[0] || null;
}

// Token'ı doğrular; hesabın aktif ve token sürümünün güncel olduğunu denetler.
export async function authenticateToken(token) {
  if (!token) throw fail('Yetkisiz erişim.', 401);
  let payload;
  try { payload = jwt.verify(token, jwtSecret(), { algorithms: ['HS256'] }); } catch { throw fail('Yetkisiz erişim.', 401); }
  const user = await loadUser(payload.sub);
  if (!user || user.account_status !== 'active' || (user.token_version ?? 0) !== (payload.tv ?? 0)) {
    throw fail('Hesap aktif değil veya oturum sona erdi.', 401);
  }
  return user;
}

const bearer = (req) => {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7) : '';
};

export async function requireAuth(req, res, next) {
  try {
    req.user = await authenticateToken(bearer(req));
    req.auth = { sub: req.user.id };
    next();
  } catch (error) { next(error); }
}

export async function optionalAuth(req, res, next) {
  try {
    const t = bearer(req);
    if (t) { req.user = await authenticateToken(t); req.auth = { sub: req.user.id }; }
  } catch (_) { /* misafir olarak devam */ }
  next();
}

// requireAuth'tan SONRA kullanılır.
export const requireRole = (...roles) => (req, res, next) => {
  if (!req.user || !roles.includes(req.user.system_role)) return next(fail('Bu işlem için yetkiniz yok.', 403));
  next();
};
export const requireAdmin = requireRole('admin', 'support');
export const requireSuperAdmin = requireRole('admin');
