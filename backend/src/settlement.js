// Ajans / yayıncı maaş hesapları (saf fonksiyonlar, veritabanı yok). Türkiye saati UTC+3 esas alınır.
const OFFSET_MS = 3 * 3600 * 1000;
const DAY_MS = 86400000;
const pad = (n) => String(n).padStart(2, '0');

export const CYCLES = ['weekly', 'monthly'];

function trParts(date) {
  const s = new Date(date.getTime() + OFFSET_MS);
  return { y: s.getUTCFullYear(), m: s.getUTCMonth(), d: s.getUTCDate(), dow: s.getUTCDay() };
}
const trMidnightUtc = (y, m, d) => new Date(Date.UTC(y, m, d) - OFFSET_MS);

export function periodBounds(cycle, date = new Date()) {
  const { y, m, d, dow } = trParts(date);
  if (cycle === 'monthly') {
    const start = trMidnightUtc(y, m, 1);
    const end = trMidnightUtc(y, m + 1, 1);
    return { cycle, key: `${y}-${pad(m + 1)}`, start, end };
  }
  if (cycle === 'weekly') {
    const back = (dow + 6) % 7; // pazartesi = 0
    const start = trMidnightUtc(y, m, d - back);
    const end = new Date(start.getTime() + 7 * DAY_MS);
    const s = trParts(start);
    return { cycle, key: `W${s.y}-${pad(s.m + 1)}-${pad(s.d)}`, start, end };
  }
  throw new Error('Geçersiz dönem türü');
}

export function previousPeriod(cycle, date = new Date()) {
  return periodBounds(cycle, new Date(periodBounds(cycle, date).start.getTime() - 1));
}

// '2026-09' (aylık) veya 'W2026-09-28' (haftalık, pazartesi) → sınırlar.
export function parsePeriodKey(key) {
  if (typeof key !== 'string') throw new Error('Geçersiz dönem');
  let m = /^(\d{4})-(0[1-9]|1[0-2])$/.exec(key);
  if (m) return periodBounds('monthly', new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, 15)));
  m = /^W(\d{4})-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/.exec(key);
  if (m) {
    const start = trMidnightUtc(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
    const b = periodBounds('weekly', new Date(start.getTime() + 12 * 3600 * 1000));
    if (b.key !== key) throw new Error('Haftalık dönem pazartesi ile başlamalı');
    return b;
  }
  throw new Error('Geçersiz dönem');
}

const tierSort = (tiers) => [...tiers].sort((a, b) => a.level - b.level);

// Bir kademe, hem saat hem Diamond hedefi sağlandığında "tam" ulaşılmış sayılır.
export function achievedTier(tiers, seconds, diamonds) {
  let best = null;
  for (const t of tierSort(tiers)) {
    if (seconds >= t.hours * 3600 && BigInt(diamonds) >= BigInt(t.diamonds)) best = t;
  }
  return best;
}

// Maaş kuralı:
//  - Diamond hedefine göre kademe bulunur (kazanç esas).
//  - Saat hedefi o kademe için tutmadıysa veya zorunlu resmi etkinlik koşulu sağlanmadıysa maaş ceza oranı kadar kesilir (tek sefer).
//  - Hiçbir kademenin Diamond hedefi tutmadıysa maaş 0.
export function evaluateHost({ tiers, seconds, diamonds, penaltyBps = 5000, eventsRequired = false, eventsOk = true }) {
  const d = BigInt(diamonds);
  let tier = null;
  for (const t of tierSort(tiers)) if (d >= BigInt(t.diamonds)) tier = t;
  if (!tier) return { tier: null, baseCents: 0n, salaryCents: 0n, penalty: false, hoursMet: false, eventsMet: !eventsRequired || eventsOk };
  const hoursMet = seconds >= tier.hours * 3600;
  const eventsMet = !eventsRequired || eventsOk;
  const base = BigInt(tier.salaryCents);
  const penalty = !hoursMet || !eventsMet;
  const salary = penalty ? (base * BigInt(10000 - penaltyBps)) / 10000n : base;
  return { tier, baseCents: base, salaryCents: salary, penalty, hoursMet, eventsMet };
}

export function commissionFor(tiers, teamDiamonds, overrideBps = null) {
  const team = BigInt(teamDiamonds);
  let bps = 0; let level = null;
  if (overrideBps !== null && overrideBps !== undefined) {
    bps = Number(overrideBps);
  } else {
    for (const t of tierSort(tiers)) {
      if (team >= BigInt(t.minDiamonds)) { bps = t.bps; level = t.level; }
    }
  }
  return { bps, level, amount: (team * BigInt(bps)) / 10000n };
}

export function nextCommissionTier(tiers, teamDiamonds) {
  const team = BigInt(teamDiamonds);
  for (const t of tierSort(tiers)) {
    if (BigInt(t.minDiamonds) > team) return { level: t.level, minDiamonds: BigInt(t.minDiamonds), bps: t.bps, remaining: BigInt(t.minDiamonds) - team };
  }
  return null;
}
