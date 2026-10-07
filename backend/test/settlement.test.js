import test from 'node:test';
import assert from 'node:assert/strict';
import { periodBounds, previousPeriod, parsePeriodKey, achievedTier, evaluateHost, commissionFor, nextCommissionTier } from '../src/settlement.js';
import { validateAgencyConfig } from '../src/agency_config.js';
import { decideWinner, validDuration, remainingSeconds } from '../src/pk_logic.js';

const SAL = [
  { level: 1, hours: 20, diamonds: 10000n, salaryCents: 5000n },
  { level: 2, hours: 40, diamonds: 80000n, salaryCents: 40000n },
  { level: 3, hours: 80, diamonds: 500000n, salaryCents: 250000n },
];
const COM = [
  { level: 1, minDiamonds: 0n, bps: 2000 },
  { level: 2, minDiamonds: 500000n, bps: 3000 },
  { level: 3, minDiamonds: 2000000n, bps: 4000 },
];
const H = 3600;

test('aylık dönem sınırları Türkiye saatine göredir', () => {
  const b = periodBounds('monthly', new Date('2026-09-30T22:00:00Z')); // TR: 1 Ekim 01:00
  assert.equal(b.key, '2026-10');
  assert.equal(b.start.toISOString(), '2026-09-30T21:00:00.000Z');
  assert.equal(b.end.toISOString(), '2026-10-31T21:00:00.000Z');
  assert.equal(previousPeriod('monthly', new Date('2026-01-10T12:00:00Z')).key, '2025-12');
});

test('haftalık dönem pazartesi başlar', () => {
  const b = periodBounds('weekly', new Date('2026-10-03T12:00:00Z')); // cumartesi
  assert.equal(b.key, 'W2026-09-28');
  assert.equal(b.end.getTime() - b.start.getTime(), 7 * 86400000);
  assert.equal(periodBounds('weekly', new Date('2026-09-27T20:59:00Z')).key, 'W2026-09-21'); // pazar 23:59 TR
  assert.equal(periodBounds('weekly', new Date('2026-09-27T21:00:00Z')).key, 'W2026-09-28'); // pazartesi 00:00 TR
});

test('parsePeriodKey', () => {
  assert.equal(parsePeriodKey('2026-02').end.toISOString(), '2026-02-28T21:00:00.000Z');
  assert.equal(parsePeriodKey('W2026-09-28').key, 'W2026-09-28');
  assert.throws(() => parsePeriodKey('W2026-09-29'));
  assert.throws(() => parsePeriodKey('2026-13'));
  assert.throws(() => parsePeriodKey(5));
});

test('achievedTier hem saat hem Diamond ister', () => {
  assert.equal(achievedTier(SAL, 45 * H, 90000n).level, 2);
  assert.equal(achievedTier(SAL, 25 * H, 90000n).level, 1);
  assert.equal(achievedTier(SAL, 5 * H, 90000n), null);
});

test('maaş: tam, ceza ve sıfır durumları', () => {
  const full = evaluateHost({ tiers: SAL, seconds: 41 * H, diamonds: 85000n });
  assert.equal(full.salaryCents, 40000n); assert.equal(full.penalty, false);
  const short = evaluateHost({ tiers: SAL, seconds: 30 * H, diamonds: 85000n });
  assert.equal(short.baseCents, 40000n); assert.equal(short.salaryCents, 20000n); assert.equal(short.penalty, true);
  const none = evaluateHost({ tiers: SAL, seconds: 100 * H, diamonds: 100n });
  assert.equal(none.salaryCents, 0n); assert.equal(none.tier, null);
  const ev = evaluateHost({ tiers: SAL, seconds: 41 * H, diamonds: 85000n, eventsRequired: true, eventsOk: false });
  assert.equal(ev.penalty, true); assert.equal(ev.salaryCents, 20000n);
  const both = evaluateHost({ tiers: SAL, seconds: 1 * H, diamonds: 85000n, eventsRequired: true, eventsOk: false });
  assert.equal(both.salaryCents, 20000n, 'ceza tek sefer uygulanır');
});

test('komisyon kademeleri ve ajansa özel oran', () => {
  assert.deepEqual(commissionFor(COM, 100n), { bps: 2000, level: 1, amount: 20n });
  assert.equal(commissionFor(COM, 2_000_000n).bps, 4000);
  assert.equal(commissionFor(COM, 2_000_000n).amount, 800000n);
  assert.equal(commissionFor(COM, 1_000_000n, 2500).bps, 2500);
  assert.equal(commissionFor(COM, 1_000_000n, 0).amount, 0n);
  const next = nextCommissionTier(COM, 400000n);
  assert.equal(next.remaining, 100000n); assert.equal(next.bps, 3000);
  assert.equal(nextCommissionTier(COM, 9_000_000n), null);
});

test('ajans ayarı doğrulaması', () => {
  const ok = validateAgencyConfig({
    settings: { cycle: 'weekly', penaltyBps: 5000, requireOfficialEvents: true, minEventCount: 2, currency: 'USD' },
    salaryTiers: [{ hours: 10, diamonds: 1000, salaryCents: 500 }, { hours: 20, diamonds: '5000', salaryCents: 2000 }],
    commissionTiers: [{ minDiamonds: 0, bps: 2000 }, { minDiamonds: 100000, bps: 3000 }],
  });
  assert.equal(ok.salaryTiers[1].diamonds, 5000n);
  assert.equal(ok.commissionTiers.length, 2);
  assert.throws(() => validateAgencyConfig({ salaryTiers: [{ hours: 20, diamonds: 1, salaryCents: 1 }, { hours: 10, diamonds: 2, salaryCents: 2 }] }), /artan/);
  assert.throws(() => validateAgencyConfig({ commissionTiers: [{ minDiamonds: 5, bps: 100 }] }), /0 Diamond/);
  assert.throws(() => validateAgencyConfig({ commissionTiers: [{ minDiamonds: 0, bps: 20000 }] }), /baz puan/);
  assert.throws(() => validateAgencyConfig({ settings: { cycle: 'daily' } }));
  assert.throws(() => validateAgencyConfig({ settings: { currency: 'usd' } }));
  assert.throws(() => validateAgencyConfig({ salaryTiers: [] }));
  assert.throws(() => validateAgencyConfig({ salaryTiers: [{ hours: 1, diamonds: '1e5', salaryCents: 1 }] }));
});

test('PK mantığı', () => {
  assert.equal(decideWinner(5n, 3n), 'a');
  assert.equal(decideWinner('3', '9'), 'b');
  assert.equal(decideWinner(4, 4), 'draw');
  assert.ok(validDuration(60) && validDuration(1800));
  assert.ok(!validDuration(59) && !validDuration(1801) && !validDuration(90.5) && !validDuration('x'));
  const now = new Date('2026-01-01T00:00:00Z');
  assert.equal(remainingSeconds(new Date(now.getTime() + 20500), now), 21);
  assert.equal(remainingSeconds(new Date(now.getTime() - 1000), now), 0);
  assert.equal(remainingSeconds(null, now), 0);
});
