import test from 'node:test';
import assert from 'node:assert/strict';
import { positionAt, clampPosition, hasEnded, queueDecision, MAX_QUEUE, MAX_PER_USER } from '../src/music_logic.js';
import { periodStartIso } from '../src/periods.js';

test('müzik konumu: oynarken ilerler, duraklatılmışken sabit, süreyi aşmaz', () => {
  assert.equal(positionAt('playing', 1000, 2500), 3500);
  assert.equal(positionAt('paused', 1000, 99999), 1000);
  assert.equal(positionAt('stopped', 0, 5000), 0);
  assert.equal(positionAt('playing', 1000, 999999, 60000), 60000);
  assert.equal(positionAt('playing', 1000, -50), 1000, 'negatif geçen süre yok sayılır');
  assert.equal(positionAt('playing', null, undefined), 0);
});

test('seek sınırlandırma ve şarkı bitişi', () => {
  assert.equal(clampPosition(-5, 1000), 0);
  assert.equal(clampPosition(5000, 1000), 999);
  assert.equal(clampPosition('abc', 1000), 0);
  assert.equal(clampPosition(499.9, 1000), 499);
  assert.equal(hasEnded('playing', 1000, 9000, 10000), true);
  assert.equal(hasEnded('playing', 1000, 8000, 10000), false);
  assert.equal(hasEnded('paused', 9999, 9999, 10000), false);
  assert.equal(hasEnded('playing', 0, 5, null), false);
});

test('sıra sınırları', () => {
  assert.equal(queueDecision({ queueLength: 0, userCount: 0 }).ok, true);
  assert.equal(queueDecision({ queueLength: MAX_QUEUE, userCount: 0 }).ok, false);
  assert.equal(queueDecision({ queueLength: 5, userCount: MAX_PER_USER }).ok, false);
});

test('liderlik dönem başlangıcı (Türkiye saati)', () => {
  const now = new Date('2026-10-01T10:00:00Z'); // Perşembe 13:00 TRT
  assert.equal(periodStartIso('daily', now), '2026-09-30T21:00:00.000Z');
  assert.equal(periodStartIso('weekly', now), '2026-09-27T21:00:00.000Z'); // Pazartesi 28 Eylül 00:00 TRT
  assert.equal(periodStartIso('monthly', now), '2026-09-30T21:00:00.000Z'); // 1 Ekim 00:00 TRT
  assert.equal(periodStartIso('all', now), null);
  assert.throws(() => periodStartIso('yearly', now));
  // TRT gece yarısından hemen sonra yeni gün
  assert.equal(periodStartIso('daily', new Date('2026-09-30T21:30:00Z')), '2026-09-30T21:00:00.000Z');
});
