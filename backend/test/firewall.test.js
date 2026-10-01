import test from 'node:test';
import assert from 'node:assert/strict';

// Yapılandırma modül yüklenmeden önce ayarlanmalı.
process.env.FIREWALL_IP_PER_MINUTE = '6';
process.env.FIREWALL_BAN_THRESHOLD = '20';
process.env.FIREWALL_ALLOW_IPS = '8.8.8.8';
delete process.env.DATABASE_URL;
const fw = await import('../src/firewall.js');

const makeReq = (ip, url = '/api/rooms', extra = {}) => ({ ip, originalUrl: url, headers: { 'user-agent': 'Dart/3.8' }, socket: { remoteAddress: ip }, ...extra });
function run(mw, req) {
  return new Promise((resolve) => {
    const res = {
      code: 200, headers: {},
      set(k, v) { this.headers[k] = v; return this; },
      status(c) { this.code = c; return this; },
      json(b) { resolve({ status: this.code, body: b, headers: this.headers }); return this; },
    };
    mw(req, res, (err) => resolve({ status: err ? (err.status ?? 500) : 'next', err }));
  });
}

test('normal istek geçer, IP başına sınır aşılınca 429 + Retry-After', async () => {
  const mw = fw.firewall();
  for (let i = 0; i < 6; i++) assert.equal((await run(mw, makeReq('9.9.9.1'))).status, 'next');
  const r = await run(mw, makeReq('9.9.9.1'));
  assert.equal(r.status, 429);
  assert.ok(Number(r.headers['Retry-After']) >= 1);
  assert.equal((await run(mw, makeReq('9.9.9.2'))).status, 'next', 'başka IP etkilenmez');
});

test('WAF saldırıyı reddeder; tekrarlayan saldırgan otomatik yasaklanır; sonra masum istek de reddedilir', async () => {
  const mw = fw.firewall();
  const ip = '9.9.9.3';
  const attack = '/api/users/search?q=1 UNION SELECT password FROM users';
  for (let i = 0; i < 4; i++) assert.equal((await run(mw, makeReq(ip, attack))).status, 403);
  assert.equal(fw.isBanned(ip), true, '4 x 5 puan = eşik (20) → yasak');
  const after = await run(mw, makeReq(ip, '/api/rooms'));
  assert.equal(after.status, 403);
  assert.match(after.body.message, /engellendi/);
  await fw.unbanIp(ip).catch(() => {}); // bellekten kalkar; veritabanı yoksa hata yukarı taşınır (beklenen)
  assert.equal(fw.isBanned(ip), false);
});

test('izin listesindeki IP asla yasaklanmaz', async () => {
  const mw = fw.firewall();
  for (let i = 0; i < 10; i++) await run(mw, makeReq('8.8.8.8', '/api/x?q=../../etc/passwd'));
  assert.equal(fw.isBanned('8.8.8.8'), false);
  assert.equal(fw.banIp('8.8.8.8', 1000, 'deneme'), false);
  assert.equal((await run(mw, makeReq('8.8.8.8'))).status, 'next');
});

test('yönetici elle yasaklayabilir ve kaldırabilir', async () => {
  const mw = fw.firewall();
  assert.equal(fw.banIp('9.9.9.4', 60000, 'elle'), true);
  assert.equal((await run(mw, makeReq('9.9.9.4'))).status, 403);
  assert.ok(fw.listBans().some((b) => b.ip === '9.9.9.4'));
  await fw.unbanIp("9.9.9.4").catch(() => {});
  assert.equal((await run(mw, makeReq('9.9.9.4'))).status, 'next');
});

test('giriş kilidi: 5 hatalı denemeden sonra 429', async () => {
  const g = fw.loginGuard('9.9.9.5', 'ali');
  for (let i = 0; i < 5; i++) { g.check(); g.failed(); }
  assert.throws(() => g.check(), (e) => e.status === 429);
  // başka kullanıcı adı / başka IP etkilenmez
  assert.doesNotThrow(() => fw.loginGuard('9.9.9.5', 'veli').check());
  assert.doesNotThrow(() => fw.loginGuard('9.9.9.6', 'ali').check());
  // başarılı giriş sayacı sıfırlar
  const g2 = fw.loginGuard('9.9.9.7', 'ayse');
  for (let i = 0; i < 4; i++) g2.failed();
  g2.succeeded();
  for (let i = 0; i < 4; i++) g2.failed();
  assert.doesNotThrow(() => g2.check());
});

test('kullanıcı başına sınır: aşınca hata (429) döner', async () => {
  const mw = fw.userLimit('deneme', 3, 60000);
  const req = makeReq('9.9.9.8', '/api/x', { user: { id: 'u-1' } });
  for (let i = 0; i < 3; i++) assert.equal((await run(mw, req)).status, 'next');
  assert.equal((await run(mw, req)).status, 429);
  assert.equal((await run(mw, makeReq('9.9.9.8', '/api/x', { user: { id: 'u-2' } }))).status, 'next', 'başka kullanıcı etkilenmez');
});

test('gövde koruması: prototype pollution reddedilir', async () => {
  const mw = fw.bodyGuard();
  assert.equal((await run(mw, makeReq('9.9.9.9', '/api/x', { body: { a: 1 } }))).status, 'next');
  const evil = JSON.parse('{"__proto__":{"isAdmin":true}}');
  assert.equal((await run(mw, makeReq('9.9.9.10', '/api/x', { body: evil }))).status, 400);
});

test('oda şifresi deneme sınırı (hitLimit)', () => {
  for (let i = 0; i < 5; i++) assert.equal(fw.hitLimit('roompw:r1:u1', 5, 60000).allowed, true);
  assert.equal(fw.hitLimit('roompw:r1:u1', 5, 60000).allowed, false);
});
