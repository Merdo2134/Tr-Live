// Seviye ve komisyon hesapları (saf fonksiyonlar).
export const COIN_LEVEL_STEPS = [1000n, 10000n, 50000n, 200000n, 1000000n, 5000000n, 20000000n, 100000000n];
export const GIFT_LEVEL_STEPS = COIN_LEVEL_STEPS;
export const FAMILY_LEVEL_STEPS = [100000n, 500000n, 2000000n, 10000000n];
export const FAMILY_CAPACITY = [30, 50, 80, 120, 200];
export const WIP_MIN_LEVEL = 1;
// WIP 1–10 ve SWIP (11): hayalet mod dahil tüm ayrıcalıklar.
export const WIP_MAX_LEVEL = 11;
export const SWIP_LEVEL = 11;

export function levelFor(total, steps) {
  const t = BigInt(total);
  let level = 1;
  for (const step of steps) {
    if (t >= step) level += 1; else break;
  }
  return level;
}

export const familyLevelFor = (points) => levelFor(points, FAMILY_LEVEL_STEPS);
export const familyCapacity = (level) => FAMILY_CAPACITY[Math.min(Math.max(level, 1), FAMILY_CAPACITY.length) - 1];

// Ajans komisyonu: baz puan (bps) üzerinden aşağı yuvarlanır.
export function commissionOf(coinAmount, bps) {
  return (BigInt(coinAmount) * BigInt(bps)) / 10000n;
}

export function giftDisplayLevel(coinAmount) {
  const n = BigInt(coinAmount);
  return n >= 10000n ? 3 : n >= 1000n ? 2 : 1;
}

// ---- 160 kademeli seviye sistemi (Seviye Merkezi) ----
// Kullanıcı seviyesi: gönderilen toplam coin; yayıncı seviyesi: alınan toplam elmas. L. seviyeye ulaşmak için gereken toplam exp: 2000 * (L-1)^2.5
export const MAX_LEVEL = 160;
export const EXP_BASE = 2000;
export function expForLevel(level) {
  const l = Math.min(Math.max(Math.floor(level), 1), MAX_LEVEL);
  return l <= 1 ? 0n : BigInt(Math.round(EXP_BASE * Math.pow(l - 1, 2.5)));
}
export function levelFromExp(total) {
  const t = BigInt(total ?? 0);
  let lo = 1; let hi = MAX_LEVEL;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (expForLevel(mid) <= t) lo = mid; else hi = mid - 1;
  }
  return lo;
}
export function levelInfo(total) {
  const exp = BigInt(total ?? 0);
  const level = levelFromExp(exp);
  const maxed = level >= MAX_LEVEL;
  return { level, exp: exp.toString(), levelStartExp: expForLevel(level).toString(), nextLevelExp: (maxed ? expForLevel(level) : expForLevel(level + 1)).toString(), maxed };
}

// CP (yakınlık) kademeleri: toplam exp eşikleri. 0 = henüz kademe yok, 1–5.
export const CP_LEVEL_STEPS = [10000n, 50000n, 200000n, 600000n, 1500000n];
export const CP_MAX_LEVEL = CP_LEVEL_STEPS.length;
export const CP_CHOOSE_LEVEL = 3; // ilişki (Arkadaş / CP) seçimi
export const CP_EFFECT_LEVEL = 5; // odada yan yana kalp efekti
export function cpLevelFor(exp) {
  const t = BigInt(exp ?? 0);
  let level = 0;
  for (const s of CP_LEVEL_STEPS) if (t >= s) level += 1; else break;
  return level;
}
export function cpInfo(exp) {
  const level = cpLevelFor(exp);
  const maxed = level >= CP_MAX_LEVEL;
  return {
    exp: String(exp ?? 0), level, maxed,
    levelStartExp: level === 0 ? '0' : CP_LEVEL_STEPS[level - 1].toString(),
    nextLevelExp: (maxed ? CP_LEVEL_STEPS[CP_MAX_LEVEL - 1] : CP_LEVEL_STEPS[level]).toString(),
    steps: CP_LEVEL_STEPS.map(String),
  };
}
