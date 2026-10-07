export const ROLE_LEVEL = { user: 1, moderator: 2, cohost: 3, owner: 4 };
const level = (role) => ROLE_LEVEL[role] || 0;

// action:
//  'moderate' -> at / engelle / mikrofon kapat (yetkili, hedeften yüksek rolde olmalı)
//  'role'     -> newRole ile rol değiştir
export function canManage(actorRole, targetRole, action, newRole = null) {
  if (targetRole === 'owner') return false;
  const a = level(actorRole);
  const t = level(targetRole);
  if (action === 'moderate') return a >= ROLE_LEVEL.moderator && a > t;
  if (action === 'role') {
    if (!['user', 'moderator', 'cohost'].includes(newRole)) return false;
    if (actorRole === 'owner') return true;
    if (actorRole === 'cohost') return newRole !== 'cohost' && t < ROLE_LEVEL.cohost;
    return false;
  }
  return false;
}
