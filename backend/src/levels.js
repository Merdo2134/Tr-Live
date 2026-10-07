// Seviye ve komisyon hesapları (saf fonksiyonlar).
export const COIN_LEVEL_STEPS = [1000n, 10000n, 50000n, 200000n, 1000000n, 5000000n, 20000000n, 100000000n];
export const GIFT_LEVEL_STEPS = COIN_LEVEL_STEPS;
export const FAMILY_LEVEL_STEPS = [100000n, 500000n, 2000000n, 10000000n];
export const FAMILY_CAPACITY = [30, 50, 80, 120, 200];
export const WIP_MIN_LEVEL = 1;
export const WIP_MAX_LEVEL = 5;

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
