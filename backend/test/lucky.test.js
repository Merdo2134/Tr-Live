import test from 'node:test';
import assert from 'node:assert/strict';
import { LUCKY_BASE, luckyTable, seededRandom, drawLucky } from '../src/lucky.js';

const rtpOf = (table) => table.reduce((s, [m, p]) => s + m * p, 0);

test('şanslı hediye: temel tablo %70 geri dönüş', () => {
  assert.ok(Math.abs(rtpOf(LUCKY_BASE) - 0.7) < 1e-9);
  assert.ok(Math.abs(rtpOf(luckyTable(9000)) - 0.9) < 1e-9);
  assert.equal(rtpOf(luckyTable(0)), 0);
  // Olasılıklar toplamı 1'i geçmez (en yüksek ayarda bile)
  assert.ok(luckyTable(9000).reduce((s, [, p]) => s + p, 0) < 1);
});

test('şanslı hediye: tohumlu üretici tekrarlanabilir ve [0,1) aralığında', () => {
  const seed = Buffer.from('00112233445566778899aabbccddeeff', 'hex');
  const a = seededRandom(seed); const b = seededRandom(seed);
  for (let i = 0; i < 1000; i += 1) {
    const x = a();
    assert.equal(x, b());
    assert.ok(x >= 0 && x < 1);
  }
});

test('şanslı hediye: uzun vadede ayarlanan RTP tutturulur', () => {
  const seed = Buffer.from('0f1e2d3c4b5a69788796a5b4c3d2e1f0', 'hex');
  for (const bps of [5000, 7000, 9000]) {
    const n = 400000;
    const r = drawLucky(n, bps, seededRandom(seed));
    const rtp = r.multiplier / n;
    assert.ok(Math.abs(rtp - bps / 10000) < 0.03, `RTP ${bps}: ${rtp}`);
    assert.equal(Object.entries(r.hits).reduce((s, [m, c]) => s + Number(m) * c, 0), r.multiplier);
    assert.ok(r.best <= 500);
  }
  assert.deepEqual(drawLucky(1000, 0, seededRandom(seed)), { multiplier: 0, best: 0, hits: {} }, 'RTP 0 → hiç kazanç yok');
  assert.deepEqual(drawLucky(0, 7000), { multiplier: 0, best: 0, hits: {} });
});
