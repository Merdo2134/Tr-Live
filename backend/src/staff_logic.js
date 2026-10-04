// Yardımcı admin ("support") yetkileri ve süreli ban hesapları (saf mantık, test edilebilir).
// Yardımcı admin YALNIZCA: kullanıcı arama, nick değiştirme, profil fotoğrafı değiştirme/kaldırma, süreli/süresiz ban ve ban kaldırma.
const SUPPORT_ROUTES = [
  ['GET', /^\/users$/],
  ['POST', /^\/users\/[^/]+\/ban$/],
  ['POST', /^\/users\/[^/]+\/unban$/],
  ['POST', /^\/users\/[^/]+\/display-name$/],
  ['POST', /^\/users\/[^/]+\/avatar$/],
  ['GET', /^\/me\/permissions$/],
];

export function supportMayCall(method, path) {
  const p = path.replace(/\/+$/, '') || '/';
  return SUPPORT_ROUTES.some(([m, re]) => m === method.toUpperCase() && re.test(p));
}

export const MAX_BAN_HOURS = 24 * 365;

// hours: sayı (saat) veya null/0 = süresiz. Dönüş: bitiş zamanı (Date) veya null (süresiz).
export function banEnd(hours, now = new Date()) {
  if (hours === null || hours === undefined || hours === 0 || hours === '0') return null;
  const h = Number(hours);
  if (!Number.isFinite(h) || h <= 0 || h > MAX_BAN_HOURS) return undefined; // geçersiz
  return new Date(now.getTime() + Math.round(h * 3600e3));
}

export const banExpired = (user, now = new Date()) =>
  user.account_status === 'banned' && user.banned_until != null && new Date(user.banned_until) <= now;

export function banMessage(user) {
  if (user.banned_until) {
    const d = new Date(user.banned_until);
    const tr = new Date(d.getTime() + 3 * 3600e3).toISOString().replace('T', ' ').slice(0, 16);
    return `Hesabınız ${tr} (TSİ) tarihine kadar askıya alındı.${user.ban_reason ? ` Neden: ${user.ban_reason}` : ''}`;
  }
  return `Hesabınız askıya alındı.${user.ban_reason ? ` Neden: ${user.ban_reason}` : ''}`;
}

// Hedef üzerinde işlem yetkisi: admin herkesi yönetir (kendi hariç), yardımcı admin yalnızca normal kullanıcıları.
export function mayActOnUser(actorRole, targetRole) {
  if (actorRole === 'admin') return true;
  if (actorRole === 'support') return targetRole === 'user';
  return false;
}
