import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SlidingWindowLimiter, LockoutTracker, BanList, ViolationTracker, inspectRequest, jsonShapeProblem, normalizeIp,
} from '../src/firewall_core.js';
import { cleanLine, cleanMultiline, containsBanned, looksLikeFlood, parseBannedWords, cleanTags } from '../src/text_safety.js';

test('kayan pencere sınırlayıcı: sınırı aşınca reddeder, pencere geçince açar', () => {
  const l = new SlidingWindowLimiter();
  for (let i = 0; i < 3; i++) assert.equal(l.hit('a', 3, 1000, 1000 + i).allowed, true);
  const blocked = l.hit('a', 3, 1000, 1500);
  assert.equal(blocked.allowed, false);
  assert.ok(blocked.retryAfterMs > 0 && blocked.retryAfterMs <= 1000);
  assert.equal(l.hit('b', 3, 1000, 1500).allowed, true, 'farklı anahtar etkilenmez');
  assert.equal(l.hit('a', 3, 1000, 2200).allowed, true, 'pencere geçince yeniden açılır');
  l.prune(1e9);
  assert.equal(l.size, 0);
});

test('giriş kilidi: 5 hatadan sonra kilitler, başarı sıfırlar, süre dolunca açar', () => {
  const t = new LockoutTracker({ maxFailures: 5, windowMs: 60000, lockMs: 60000 });
  for (let i = 0; i < 4; i++) assert.equal(t.fail('k', 1000 + i).locked, false);
  assert.equal(t.fail('k', 1010).locked, true);
  assert.ok(t.lockedFor('k', 2000) > 0);
  assert.equal(t.lockedFor('k', 1010 + 60001), 0);
  t.fail('x', 1); t.success('x');
  for (let i = 0; i < 4; i++) t.fail('x', 10 + i);
  assert.equal(t.lockedFor('x', 20), 0, 'başarıdan sonra sayaç sıfırlanmış olmalı');
});

test('yasak listesi: süreli ve süresiz', () => {
  const b = new BanList();
  b.ban('1.1.1.1', 1000, 'test', 0);
  b.ban('2.2.2.2', null, 'kalıcı', 0);
  assert.equal(b.isBanned('1.1.1.1', 500), true);
  assert.equal(b.isBanned('1.1.1.1', 1500), false);
  assert.equal(b.isBanned('2.2.2.2', 9e12), true);
  assert.equal(b.unban('2.2.2.2'), true);
  assert.equal(b.isBanned('2.2.2.2', 0), false);
});

test('ihlal takibi: eşik aşılınca yasak, tekrarlayanda süre uzar', () => {
  const v = new ViolationTracker({ windowMs: 600000, threshold: 10, escalationMs: [100, 200, 300], historyMs: 1e9 });
  for (let i = 0; i < 9; i++) assert.equal(v.record('ip', 1, i).ban, false);
  const first = v.record('ip', 1, 10);
  assert.equal(first.ban, true);
  assert.equal(first.durationMs, 100);
  let second;
  for (let i = 0; i < 10; i++) second = v.record('ip', 1, 1000 + i);
  assert.equal(second.ban, true);
  assert.equal(second.durationMs, 200);
  assert.equal(v.record('baska', 5, 0).ban, false);
  assert.equal(v.record('baska', 5, 1).ban, true, 'ağır ihlal puanı daha hızlı yasaklar');
});

test('WAF: saldırı imzaları yakalanır, normal istekler geçer', () => {
  const bad = [
    '/api/users/../../etc/passwd', '/api/x?f=%2e%2e%2fsecret', '/api/a%00b', "/api/users/search?q=1' UNION SELECT password FROM users",
    '/api/x?q=<script>alert(1)</script>', '/api/x?q=1;DROP TABLE users', '/api/x?q=1 or 1=1', '/api/x?c=$(whoami)',
    '/api/x?q=%E0%A4%A', '/' + 'a'.repeat(3000),
  ];
  for (const u of bad) assert.ok(inspectRequest(u), `yakalanmalı: ${u.slice(0, 60)}`);
  const good = [
    '/api/rooms?type=audio', '/api/users/search?q=ali', '/api/users/search?q=%C5%9Fule', '/api/rooms/11111111-1111-4111-8111-111111111111/join',
    '/api/leaderboards?type=senders&period=weekly', '/api/agencies?q=select', '/health',
  ];
  for (const u of good) assert.equal(inspectRequest(u, 'Dart/3.8 (dart:io)'), null, `geçmeli: ${u}`);
  assert.equal(inspectRequest('/api/rooms', 'sqlmap/1.7'), 'scanner_user_agent');
});

test('JSON gövde şekli: prototype pollution ve aşırı derinlik reddedilir', () => {
  assert.equal(jsonShapeProblem({ a: 1, b: { c: [1, 2, { d: 3 }] } }), null);
  assert.equal(jsonShapeProblem(JSON.parse('{"__proto__":{"admin":true}}')), 'dangerous_key');
  assert.equal(jsonShapeProblem({ constructor: 1 }), 'dangerous_key');
  let deep = {}; let cur = deep;
  for (let i = 0; i < 20; i++) { cur.x = {}; cur = cur.x; }
  assert.equal(jsonShapeProblem(deep), 'too_deep');
  assert.equal(jsonShapeProblem(Array.from({ length: 3000 }, () => ({}))), 'too_large');
});

test('IP normalizasyonu', () => {
  assert.equal(normalizeIp('::ffff:10.0.0.5'), '10.0.0.5');
  assert.equal(normalizeIp(undefined), 'unknown');
});

test('metin temizliği: görünmez/yönlendirme karakterleri, flood, yasaklı kelime, etiketler', () => {
  assert.equal(cleanLine('  merhaba\u202E   dünya\u200B  '), 'merhaba dünya');
  assert.equal(cleanLine(123), '');
  assert.equal(cleanLine('x'.repeat(500)).length, 300);
  assert.equal(cleanMultiline('a\r\n\n\n\nb'), 'a\n\nb');
  assert.equal(looksLikeFlood('aaaaaaaaaaaaaaaa'), true);
  assert.equal(looksLikeFlood('al al al al al al al al'), true);
  assert.equal(looksLikeFlood('merhaba nasılsınız bugün'), false);
  const words = parseBannedWords(' Kötü , ÇIRKIN ,');
  assert.deepEqual(words, ['kötü', 'çırkın']);
  assert.equal(containsBanned('Bu çok KÖTÜ bir söz', words), true);
  assert.equal(containsBanned('güzel bir gün', words), false);
  assert.equal(containsBanned('herhangi', []), false);
  assert.deepEqual(cleanTags(['Müzik', 'sohbet', 'müzik']), ['müzik', 'sohbet']);
  assert.throws(() => cleanTags(['a']));
  assert.throws(() => cleanTags(['bir', 'iki', 'üç', 'dört']));
  assert.throws(() => cleanTags(['<script>']));
  assert.deepEqual(cleanTags(undefined), []);
});
