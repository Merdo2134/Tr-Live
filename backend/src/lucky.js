import crypto from 'node:crypto';

// Şanslı hediye (Yoho "çan"): gönderen her hediye adedi için şans çekilişine girer; çıkan çarpan × hediye fiyatı
// kadar Coin kazanır. Temel tablo %70 geri ödeme (RTP) içindir; yönetim panelindeki RTP oranına göre olasılıklar ölçeklenir.
export const LUCKY_BASE = Object.freeze([
  [500, 0.0001],
  [100, 0.0008],
  [50, 0.002],
  [10, 0.015],
  [5, 0.03],
  [2, 0.085],
]);
const BASE_RTP = LUCKY_BASE.reduce((s, [m, p]) => s + m * p, 0); // 0.70

/** RTP (baz puan, 7000 = %70) için olasılık tablosu. */
export function luckyTable(rtpBps) {
  const k = Math.max(0, rtpBps) / 10000 / BASE_RTP;
  return LUCKY_BASE.map(([m, p]) => [m, p * k]);
}

/** Hızlı, kriptografik tohumlu sözde rastgele üretici (yüz binlerce çekiliş için crypto tek tek yavaş kalır). */
export function seededRandom(seed = crypto.randomBytes(16)) {
  let a = seed.readUInt32LE(0) || 1; let b = seed.readUInt32LE(4) || 2; let c = seed.readUInt32LE(8) || 3; let d = seed.readUInt32LE(12) || 4;
  return () => {
    // xoshiro128** (32 bit)
    const r = Math.imul(Math.imul(b, 5) << 7 | Math.imul(b, 5) >>> 25, 9) >>> 0;
    const t = b << 9;
    c ^= a; d ^= b; b ^= c; a ^= d; c ^= t;
    d = d << 11 | d >>> 21;
    return r / 4294967296;
  };
}

/**
 * units adet için çekiliş. Dönüş: { multiplier: toplam çarpan, best: en yüksek tek çarpan, hits: {çarpan: adet} }.
 * rng testte sabitlenebilir.
 */
export function drawLucky(units, rtpBps, rng = seededRandom()) {
  const table = luckyTable(rtpBps);
  const hits = {};
  let multiplier = 0;
  let best = 0;
  for (let i = 0; i < units; i += 1) {
    let x = rng();
    for (const [m, p] of table) {
      if (x < p) {
        hits[m] = (hits[m] ?? 0) + 1;
        multiplier += m;
        if (m > best) best = m;
        break;
      }
      x -= p;
    }
  }
  return { multiplier, best, hits };
}
