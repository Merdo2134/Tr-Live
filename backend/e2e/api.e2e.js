// Uçtan uca testler: GERÇEK PostgreSQL + GERÇEK sunucu süreci.
// Çalıştırma:  TEST_DATABASE_URL=postgresql://user:pass@localhost:5432/trlive_test npm run test:e2e
// Veritabanı boş/atılabilir olmalıdır. Testler sırayla çalışır ve birbirinin durumunu kullanır.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const run = promisify(execFile);
const dir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DB = process.env.TEST_DATABASE_URL;
const PORT = Number(process.env.E2E_PORT || 3199);
const BASE = `http://127.0.0.1:${PORT}`;
const skip = !DB ? 'TEST_DATABASE_URL tanımlı değil' : false;

const env = {
  ...process.env, NODE_ENV: 'test', PORT: String(PORT), DATABASE_URL: DB, DATABASE_SSL: 'false',
  JWT_SECRET: 'e2e-secret-e2e-secret-e2e-secret-1234567890', FIREWALL_ENABLED: 'false', GLOBAL_GIFT_MIN_COINS: '100',
  UPLOAD_DIR: fs.mkdtempSync(path.join(os.tmpdir(), 'trlive-up-')),
};

let server; let pool;
const sql = (q, p = []) => pool.query(q, p);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const tag = Date.now().toString(36);

async function api(method, p, { body, token, headers = {}, raw } = {}) {
  const res = await fetch(BASE + p, {
    method,
    headers: { ...(raw ? {} : { 'Content-Type': 'application/json' }), ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
  });
  let json = null;
  try { json = await res.json(); } catch { /* gövde yok */ }
  return { status: res.status, body: json };
}
const ok = (r, msg = '') => assert.ok(r.status >= 200 && r.status < 300, `${msg} → HTTP ${r.status} ${JSON.stringify(r.body)}`);
const status = (r, code, msg = '') => assert.equal(r.status, code, `${msg} → HTTP ${r.status} ${JSON.stringify(r.body)}`);

async function register(name) {
  const r = await api('POST', '/api/auth/register', { body: { username: `e2e_${tag}_${name}`, password: 'sifre123', displayName: `Kişi ${name}` } });
  ok(r, `kayıt ${name}`);
  return { id: r.body.user.id, token: r.body.token, username: `e2e_${tag}_${name}` };
}
const coins = async (u) => BigInt((await sql('SELECT coins FROM users WHERE id=$1', [u.id])).rows[0].coins);
const diamonds = async (u) => BigInt((await sql('SELECT diamonds FROM users WHERE id=$1', [u.id])).rows[0].diamonds);

const U = {}; let roomId; let rose; let heart;

before(async () => {
  if (skip) return;
  pool = new pg.Pool({ connectionString: DB });
  await run(process.execPath, ['src/migration_runner.js'], { cwd: dir, env });
  server = spawn(process.execPath, ['src/server.js'], { cwd: dir, env, stdio: ['ignore', 'inherit', 'inherit'] });
  for (let i = 0; i < 60; i++) {
    try { if ((await fetch(`${BASE}/health`)).ok) return; } catch { /* henüz kalkmadı */ }
    await sleep(500);
  }
  throw new Error('Sunucu 30 sn içinde açılmadı');
});

after(async () => {
  if (server) { server.kill('SIGTERM'); await sleep(300); }
  if (pool) await pool.end();
});

test('sağlık ve kayıt/giriş', { skip, timeout: 60000 }, async () => {
  const h = await api('GET', '/health');
  ok(h);
  for (const n of ['a', 'b', 'c', 'd', 'f', 'g', 'h', 'e', 'x']) U[n] = await register(n);
  const dup = await api('POST', '/api/auth/register', { body: { username: U.a.username.toUpperCase(), password: 'sifre123' } });
  status(dup, 409, 'büyük/küçük harf duyarsız tekrar');
  status(await api('POST', '/api/auth/register', { body: { username: 'x', password: 'sifre123' } }), 400, 'kısa kullanıcı adı');
  status(await api('POST', '/api/auth/register', { body: { username: `okay_${tag}`, password: '123' } }), 400, 'kısa şifre');
  const login = await api('POST', '/api/auth/login', { body: { username: U.a.username, password: 'sifre123' } });
  ok(login, 'giriş');
  status(await api('POST', '/api/auth/login', { body: { username: U.a.username, password: 'yanlis' } }), 401, 'yanlış şifre');
  const me = await api('GET', '/api/me', { token: U.a.token });
  ok(me);
  assert.equal(me.body.user.id, U.a.id);
  status(await api('GET', '/api/me'), 401, 'token yok');
  status(await api('GET', '/api/rooms/abc/members', { token: U.a.token }), 400, 'geçersiz UUID 500 değil 400 olmalı');
  await sql(`UPDATE users SET coins = 100000 WHERE id = ANY($1::uuid[])`, [Object.values(U).map((u) => u.id)]);
  await sql(`UPDATE users SET system_role = 'admin' WHERE id = $1`, [U.d.id]);
  const gifts = await api('GET', '/api/gifts', { token: U.a.token });
  ok(gifts);
  rose = gifts.body.gifts.find((g) => g.name === 'Rose');
  heart = gifts.body.gifts.find((g) => g.name === 'Heart');
  assert.ok(rose && heart, 'tohum hediyeleri (Rose, Heart) bulunmalı');
});

test('giriş kilidi: 5 hatalı denemeden sonra doğru şifre bile 429', { skip, timeout: 60000 }, async () => {
  for (let i = 0; i < 5; i++) status(await api('POST', '/api/auth/login', { body: { username: U.x.username, password: 'yanlis' } }), 401);
  status(await api('POST', '/api/auth/login', { body: { username: U.x.username, password: 'sifre123' } }), 429, 'kilitli');
});

test('profil: düzenleme, arama, takip, gizli mod, avatar yükleme, engelleme etkisi', { skip, timeout: 60000 }, async () => {
  ok(await api('PATCH', '/api/me', { token: U.b.token, body: { bio: 'merhaba', city: 'İstanbul', gender: 'other', whoCanDm: 'everyone' } }));
  status(await api('PATCH', '/api/me', { token: U.b.token, body: { gender: 'zzz' } }), 400);
  status(await api('PATCH', '/api/me', { token: U.b.token, body: { avatarUrl: 'http://x/y.png' } }), 400, 'https zorunlu');
  const s = await api('GET', `/api/users/search?q=${encodeURIComponent(`e2e_${tag}_b`)}`, { token: U.a.token });
  ok(s);
  assert.ok(s.body.users.some((u) => u.id === U.b.id));
  ok(await api('POST', `/api/users/${U.b.id}/follow`, { token: U.a.token }));
  const prof = await api('GET', `/api/users/${U.b.id}`, { token: U.a.token });
  ok(prof);
  assert.equal(prof.body.profile.isFollowing, true);
  assert.equal(prof.body.profile.followers, 1);
  assert.equal(prof.body.profile.coins, undefined, 'başkasının bakiyesi görünmemeli');
  // gizli mod
  ok(await api('PATCH', '/api/me', { token: U.c.token, body: { isHidden: true } }));
  const hidden = await api('GET', `/api/users/${U.c.id}`, { token: U.a.token });
  assert.equal(hidden.body.profile.displayName, 'Gizli Kullanıcı');
  const s2 = await api('GET', `/api/users/search?q=${encodeURIComponent(`e2e_${tag}_c`)}`, { token: U.a.token });
  assert.ok(!s2.body.users.some((u) => u.id === U.c.id), 'gizli kullanıcı aramada çıkmamalı');
  ok(await api('PATCH', '/api/me', { token: U.c.token, body: { isHidden: false } }));
  // avatar (1x1 png)
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
  const up = await api('PUT', '/api/me/avatar', { token: U.b.token, raw: png, headers: { 'Content-Type': 'image/png' } });
  ok(up, 'avatar');
  const img = await fetch(BASE + up.body.url);
  assert.equal(img.status, 200);
  const bad = await api('PUT', '/api/me/avatar', { token: U.b.token, raw: Buffer.from('not an image at all'), headers: { 'Content-Type': 'image/png' } });
  status(bad, 400, 'sahte görsel reddedilmeli');
});

test('oda: oluşturma, etiket, katılma, mikrofon, üyeler', { skip, timeout: 60000 }, async () => {
  const r = await api('POST', '/api/rooms', { token: U.a.token, body: { name: 'E2E Oda', seatCount: 8, tags: ['müzik', 'sohbet'] } });
  ok(r, 'oda');
  roomId = r.body.room.id;
  const second = await api('POST', '/api/rooms', { token: U.a.token, body: { name: 'İkinci' } });
  status(second, 409, 'WIP yokken en fazla 1 oda');
  const list = await api('GET', `/api/rooms?tag=${encodeURIComponent('müzik')}`);
  ok(list);
  const row = list.body.rooms.find((x) => x.id === roomId);
  assert.ok(row, 'oda listede');
  assert.equal(row.id, roomId, 'oda kimliği sahip kimliğiyle karışmamalı');
  assert.equal(row.ownerId, U.a.id);
  for (const n of ['b', 'c', 'f']) ok(await api('POST', `/api/rooms/${roomId}/join`, { token: U[n].token }), `${n} katıl`);
  const take = await api('POST', `/api/rooms/${roomId}/mic/take`, { token: U.b.token, body: {} });
  ok(take);
  assert.equal(take.body.seatIndex, 1);
  status(await api('POST', `/api/rooms/${roomId}/mic/take`, { token: U.c.token, body: { seatIndex: 1 } }), 409, 'dolu koltuk');
  status(await api('POST', `/api/rooms/${roomId}/mic/take`, { token: U.c.token, body: { seatIndex: 0 } }), 403, '0. koltuk sahibine ait');
  const m = await api('GET', `/api/rooms/${roomId}/members`, { token: U.a.token });
  ok(m);
  const byId = Object.fromEntries(m.body.members.map((x) => [x.userId, x]));
  assert.equal(byId[U.a.id].seatIndex, 0);
  assert.equal(byId[U.b.id].seatIndex, 1);
  assert.equal(byId[U.b.id].user.coins, undefined, 'üye listesinde bakiye olmamalı');
});

test('hediye: tekli, KENDİNE hediye, eşit dağıtım, bakiye/muhasebe doğruluğu', { skip, timeout: 60000 }, async () => {
  const a0 = await coins(U.a); const b0 = await diamonds(U.b); const a0d = await diamonds(U.a);
  const single = await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: rose.id, quantity: 3, distribution: 'single', recipientId: U.b.id } });
  ok(single, 'tekli');
  assert.equal(single.body.totalCoins, '30');
  assert.equal(await coins(U.a), a0 - 30n);
  assert.equal(await diamonds(U.b), b0 + 30n);

  const self = await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: rose.id, quantity: 2, distribution: 'single', recipientId: U.a.id } });
  ok(self, 'kendine hediye');
  assert.equal(await diamonds(U.a), a0d + 20n, 'kendine hediyede Diamond artar');
  assert.equal(await coins(U.a), a0 - 50n, 'Coin düşer');

  const equal = await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: rose.id, quantity: 4, distribution: 'equal' } });
  ok(equal, 'eşit');
  assert.equal(equal.body.transactions.length, 2, 'mikrofondaki iki kişiye (A ve B)');
  const wt = await sql(`SELECT COUNT(*)::int AS n FROM wallet_transactions WHERE user_id = $1 AND transaction_type = 'gift_sent'`, [U.a.id]);
  assert.ok(wt.rows[0].n >= 4);

  const random = await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: rose.id, quantity: 10, distribution: 'random' } });
  ok(random, 'rastgele');
  assert.equal(random.body.transactions.reduce((s, t) => s + t.quantity, 0), 10);

  status(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.d.token, body: { giftId: rose.id, quantity: 1, distribution: 'single', recipientId: U.b.id } }), 403, 'odada olmayan gönderemez');
  await sql(`UPDATE users SET coins = 5 WHERE id = $1`, [U.c.id]);
  status(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.c.token, body: { giftId: rose.id, quantity: 1, distribution: 'single', recipientId: U.b.id } }), 400, 'yetersiz coin');
  await sql(`UPDATE users SET coins = 100000 WHERE id = $1`, [U.c.id]);
  status(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: rose.id, quantity: 1, distribution: 'single', recipientId: U.d.id } }), 400, 'alıcı odada değil');
  status(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: 'zzz', quantity: 1, distribution: 'single', recipientId: U.b.id } }), 400);
  // eşzamanlı karşılıklı hediyeler kilitlenme (deadlock) üretmemeli
  const results = await Promise.all(Array.from({ length: 12 }, (_, i) => api('POST', `/api/rooms/${roomId}/gifts/send`, {
    token: i % 2 ? U.a.token : U.b.token, body: { giftId: rose.id, quantity: 1, distribution: 'single', recipientId: i % 2 ? U.b.id : U.a.id } })));
  for (const r of results) status(r, 200, 'eşzamanlı hediye');
  const neg = await sql(`SELECT COUNT(*)::int AS n FROM users WHERE coins < 0 OR diamonds < 0`);
  assert.equal(neg.rows[0].n, 0);
  const ge = await sql(`SELECT COUNT(*)::int AS n FROM global_gift_events`);
  assert.ok(ge.rows[0].n >= 0);
  const wip = await api('GET', '/api/gifts/global/recent', { token: U.a.token });
  ok(wip);
});

test('moderasyon: yetki, mikrofon kapatma, atma, engelleme, rol, WIP dokunulmazlığı', { skip, timeout: 60000 }, async () => {
  status(await api('POST', `/api/rooms/${roomId}/members/${U.a.id}/kick`, { token: U.b.token }), 403, 'üye sahibi atamaz');
  ok(await api('POST', `/api/rooms/${roomId}/members/${U.b.id}/mic-off`, { token: U.a.token }), 'mic-off');
  let m = (await api('GET', `/api/rooms/${roomId}/members`, { token: U.a.token })).body.members;
  assert.equal(m.find((x) => x.userId === U.b.id).microphone, false);
  ok(await api('POST', `/api/rooms/${roomId}/members/${U.c.id}/kick`, { token: U.a.token }), 'kick');
  m = (await api('GET', `/api/rooms/${roomId}/members`, { token: U.a.token })).body.members;
  assert.ok(!m.some((x) => x.userId === U.c.id));
  ok(await api('POST', `/api/rooms/${roomId}/join`, { token: U.c.token }), 'atılan yeniden girebilir');
  ok(await api('POST', `/api/rooms/${roomId}/members/${U.c.id}/block`, { token: U.a.token }), 'block');
  status(await api('POST', `/api/rooms/${roomId}/join`, { token: U.c.token }), 403, 'engelli giremez');
  ok(await api('DELETE', `/api/rooms/${roomId}/blocks/${U.c.id}`, { token: U.a.token }));
  ok(await api('POST', `/api/rooms/${roomId}/join`, { token: U.c.token }));
  ok(await api('POST', `/api/rooms/${roomId}/members/${U.b.id}/role`, { token: U.a.token, body: { role: 'moderator' } }));
  status(await api('POST', `/api/rooms/${roomId}/members/${U.a.id}/kick`, { token: U.b.token }), 403, 'moderatör sahibi atamaz');
  status(await api('POST', `/api/rooms/${roomId}/members/${U.c.id}/role`, { token: U.b.token, body: { role: 'cohost' } }), 403, 'moderatör rol veremez');
  // WIP 3+ olan kullanıcı moderatör tarafından atılamaz; oda sahibi atabilir
  await sql(`INSERT INTO user_wip(user_id, level, starts_at, expires_at, is_active) VALUES($1,3,NOW(),NOW()+INTERVAL '1 day',TRUE)
             ON CONFLICT (user_id) DO UPDATE SET level=3, expires_at=NOW()+INTERVAL '1 day', is_active=TRUE`, [U.f.id]);
  status(await api('POST', `/api/rooms/${roomId}/members/${U.f.id}/kick`, { token: U.b.token }), 403, 'WIP dokunulmazlığı');
  await sql(`UPDATE user_wip SET is_active = FALSE WHERE user_id = $1`, [U.f.id]);
  ok(await api('POST', `/api/rooms/${roomId}/members/${U.b.id}/role`, { token: U.a.token, body: { role: 'user' } }));
  ok(await api('POST', `/api/rooms/${roomId}/mic/take`, { token: U.b.token, body: {} }));
});

test('yazılı sohbet: gönder, listele, sustur, sil, spam', { skip, timeout: 60000 }, async () => {
  const a = await api('POST', `/api/rooms/${roomId}/messages`, { token: U.a.token, body: { text: 'Merhaba\u202E herkese' } });
  status(a, 201);
  assert.equal(a.body.message.text, 'Merhaba herkese', 'yön değiştirme karakteri temizlenmeli');
  const b = await api('POST', `/api/rooms/${roomId}/messages`, { token: U.b.token, body: { text: 'selam' } });
  status(b, 201);
  let list = await api('GET', `/api/rooms/${roomId}/messages`, { token: U.c.token });
  ok(list);
  assert.equal(list.body.messages.length, 2);
  assert.equal(list.body.messages[0].text, 'Merhaba herkese', 'eskiden yeniye sıralı');
  status(await api('POST', `/api/rooms/${roomId}/messages`, { token: U.b.token, body: { text: 'aaaaaaaaaaaaaaaaaaaa' } }), 422, 'flood');
  status(await api('POST', `/api/rooms/${roomId}/messages`, { token: U.b.token, body: { text: '   ' } }), 400);
  ok(await api('POST', `/api/rooms/${roomId}/members/${U.c.id}/chat-mute`, { token: U.a.token, body: { minutes: 5 } }));
  status(await api('POST', `/api/rooms/${roomId}/messages`, { token: U.c.token, body: { text: 'ben' } }), 403, 'susturulmuş');
  ok(await api('POST', `/api/rooms/${roomId}/members/${U.c.id}/chat-mute`, { token: U.a.token, body: { minutes: 0 } }));
  status(await api('POST', `/api/rooms/${roomId}/messages`, { token: U.c.token, body: { text: 'ben geldim' } }), 201);
  ok(await api('DELETE', `/api/rooms/${roomId}/messages/${b.body.message.id}`, { token: U.a.token }));
  list = await api('GET', `/api/rooms/${roomId}/messages`, { token: U.a.token });
  assert.ok(!list.body.messages.some((x) => x.id === b.body.message.id), 'silinen mesaj görünmemeli');
  ok(await api('PATCH', `/api/rooms/${roomId}`, { token: U.a.token, body: { chatEnabled: false } }));
  status(await api('POST', `/api/rooms/${roomId}/messages`, { token: U.c.token, body: { text: 'kapalıyken' } }), 403, 'sohbet kapalı');
  ok(await api('POST', `/api/rooms/${roomId}/messages`, { token: U.a.token, body: { text: 'yetkili yazabilir' } }));
  ok(await api('PATCH', `/api/rooms/${roomId}`, { token: U.a.token, body: { chatEnabled: true } }));
});

test('müzik çalar: kütüphane, sıra, yetki, duraklat/devam/ara/sonraki, otomatik geçiş', { skip, timeout: 90000 }, async () => {
  const t1 = (await sql(`INSERT INTO music_tracks(title, artist, url, duration_ms, license_note) VALUES('Parça 1','Sanatçı','https://example.com/1.mp3',120000,'e2e test lisansı') RETURNING id`)).rows[0].id;
  const t2 = (await sql(`INSERT INTO music_tracks(title, artist, url, duration_ms, license_note) VALUES('Parça 2','Sanatçı','https://example.com/2.mp3',120000,'e2e test lisansı') RETURNING id`)).rows[0].id;
  const short = (await sql(`INSERT INTO music_tracks(title, artist, url, duration_ms, license_note) VALUES('Kısa','Sanatçı','https://example.com/3.mp3',2000,'e2e test lisansı') RETURNING id`)).rows[0].id;
  const lib = await api('GET', '/api/music/tracks?q=par', { token: U.f.token });
  ok(lib);
  assert.ok(lib.body.tracks.length >= 2);
  // F üye mikrofonda değil → sıraya ekleyemez; mikrofona çıkınca ekler ama kontrol edemez
  status(await api('POST', `/api/rooms/${roomId}/music/queue`, { token: U.f.token, body: { trackId: t1 } }), 403, 'mikrofonsuz ekleyemez');
  ok(await api('POST', `/api/rooms/${roomId}/mic/take`, { token: U.f.token, body: {} }));
  const q1 = await api('POST', `/api/rooms/${roomId}/music/queue`, { token: U.f.token, body: { trackId: t1 } });
  status(q1, 201);
  assert.equal(q1.body.state.status, 'playing', 'boşken ilk eklenen hemen çalar');
  assert.equal(q1.body.state.track.id, t1);
  status(await api('POST', `/api/rooms/${roomId}/music/pause`, { token: U.f.token }), 403, 'yetkisiz kontrol');
  ok(await api('POST', `/api/rooms/${roomId}/music/queue`, { token: U.a.token, body: { trackId: t2 } }));
  let st = (await api('GET', `/api/rooms/${roomId}/music`, { token: U.c.token })).body.state;
  assert.equal(st.queue.length, 1);
  await sleep(1200);
  const p = await api('POST', `/api/rooms/${roomId}/music/pause`, { token: U.a.token });
  ok(p);
  assert.equal(p.body.state.status, 'paused');
  assert.ok(p.body.state.positionMs >= 1000, `konum ilerlemiş olmalı: ${p.body.state.positionMs}`);
  const frozen = p.body.state.positionMs;
  await sleep(800);
  st = (await api('GET', `/api/rooms/${roomId}/music`, { token: U.a.token })).body.state;
  assert.equal(st.positionMs, frozen, 'duraklatılmışken konum sabit');
  ok(await api('POST', `/api/rooms/${roomId}/music/play`, { token: U.a.token }));
  const sk = await api('POST', `/api/rooms/${roomId}/music/seek`, { token: U.a.token, body: { positionMs: 60000 } });
  ok(sk);
  assert.ok(sk.body.state.positionMs >= 60000 && sk.body.state.positionMs < 62000);
  status(await api('POST', `/api/rooms/${roomId}/music/seek`, { token: U.a.token, body: { positionMs: -5 } }), 400);
  const nx = await api('POST', `/api/rooms/${roomId}/music/next`, { token: U.a.token });
  ok(nx);
  assert.equal(nx.body.state.track.id, t2);
  // otomatik geçiş: kısa şarkı bitince sıradaki/dur
  ok(await api('POST', `/api/rooms/${roomId}/music/play`, { token: U.a.token, body: { trackId: short } }));
  ok(await api('POST', `/api/rooms/${roomId}/music/queue`, { token: U.a.token, body: { trackId: t2 } }));
  await sleep(6500);
  st = (await api('GET', `/api/rooms/${roomId}/music`, { token: U.a.token })).body.state;
  assert.equal(st.track?.id, t2, 'kısa şarkı bitince sıradaki otomatik başlamalı');
  assert.equal(st.status, 'playing');
  const stop = await api('POST', `/api/rooms/${roomId}/music/stop`, { token: U.a.token });
  ok(stop);
  assert.equal(stop.body.state.status, 'stopped');
  status(await api('POST', `/api/rooms/${roomId}/music/play`, { token: U.a.token, body: { trackId: '00000000-0000-4000-8000-000000000000' } }), 404);
});

test('şifreli oda', { skip, timeout: 60000 }, async () => {
  const r = await api('POST', '/api/rooms', { token: U.e.token, body: { name: 'Gizli Oda', password: '1234' } });
  ok(r);
  const id = r.body.room.id;
  assert.equal(r.body.room.locked, true);
  status(await api('POST', `/api/rooms/${id}/join`, { token: U.f.token }), 403, 'şifresiz');
  status(await api('POST', `/api/rooms/${id}/join`, { token: U.f.token, body: { password: 'yanlis' } }), 403, 'yanlış şifre');
  ok(await api('POST', `/api/rooms/${id}/join`, { token: U.f.token, body: { password: '1234' } }), 'doğru şifre');
  ok(await api('POST', `/api/rooms/${id}/join`, { token: U.f.token }), 'zaten üye olan şifresiz yeniden bağlanabilir');
  ok(await api('POST', `/api/rooms/${id}/close`, { token: U.e.token }));
});

test('aile: kurma, katılma, çifte üyelik engeli, devir, dağıtma', { skip, timeout: 60000 }, async () => {
  const f = await api('POST', '/api/families', { token: U.a.token, body: { name: `Aile ${tag}`, description: 'test' } });
  ok(f);
  const id = f.body.family.id;
  status(await api('POST', '/api/families', { token: U.a.token, body: { name: `Başka ${tag}` } }), 409, 'zaten ailede');
  ok(await api('POST', `/api/families/${id}/join`, { token: U.b.token }));
  status(await api('POST', `/api/families/${id}/join`, { token: U.b.token }), 409, 'tekrar katılım');
  const g = await api('POST', '/api/families', { token: U.g.token, body: { name: `Diğer ${tag}` } });
  ok(g);
  status(await api('POST', `/api/families/${g.body.family.id}/join`, { token: U.b.token }), 409, 'başka aileye sessiz başarı OLMAMALI');
  status(await api('POST', `/api/families/${id}/leave`, { token: U.a.token }), 409, 'sahip ayrılamaz');
  const mem = await api('GET', `/api/families/${id}/members`, { token: U.a.token });
  assert.equal(mem.body.members[0].role, 'owner', 'sahip en üstte');
  // aile puanı: A'nın aileden biri olan B'ye hediyesi aile puanını artırır
  const before = BigInt((await sql('SELECT total_points FROM families WHERE id=$1', [id])).rows[0].total_points);
  ok(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: rose.id, quantity: 5, distribution: 'single', recipientId: U.b.id } }));
  const after = BigInt((await sql('SELECT total_points FROM families WHERE id=$1', [id])).rows[0].total_points);
  assert.equal(after - before, 50n);
  ok(await api('POST', `/api/families/${id}/transfer`, { token: U.a.token, body: { userId: U.b.id } }));
  status(await api('DELETE', `/api/families/${id}`, { token: U.a.token }), 403, 'artık sahip değil');
  ok(await api('DELETE', `/api/families/${id}`, { token: U.b.token }));
  const mine = await api('GET', '/api/families/mine', { token: U.a.token });
  assert.equal(mine.body.family, null);
  ok(await api('DELETE', `/api/families/${g.body.family.id}`, { token: U.g.token }));
});

test('WIP: kademeler, satın alma, uzatma, düşük seviye engeli, oda sınırı artışı', { skip, timeout: 60000 }, async () => {
  const t = await api('GET', '/api/wip/tiers', { token: U.h.token });
  ok(t);
  assert.equal(t.body.tiers.length, 5);
  const plan = (lvl) => t.body.tiers.find((x) => x.level === lvl).plans[0];
  const c0 = await coins(U.h);
  ok(await api('POST', '/api/wip/purchase', { token: U.h.token, body: { planId: plan(2).id } }));
  assert.equal(await coins(U.h), c0 - BigInt(plan(2).priceCoins));
  let w = (await api('GET', '/api/wip', { token: U.h.token })).body.wip;
  assert.equal(w.level, 2);
  const exp1 = new Date(w.expiresAt).getTime();
  ok(await api('POST', '/api/wip/purchase', { token: U.h.token, body: { planId: plan(2).id } }));
  w = (await api('GET', '/api/wip', { token: U.h.token })).body.wip;
  assert.ok(new Date(w.expiresAt).getTime() - exp1 > 29 * 86400000, 'aynı seviye süreyi uzatır');
  status(await api('POST', '/api/wip/purchase', { token: U.h.token, body: { planId: plan(1).id } }), 409, 'düşük seviye');
  ok(await api('GET', '/api/me/visitors', { token: U.h.token }), 'WIP2 ziyaretçi listesi');
  status(await api('GET', '/api/me/visitors', { token: U.g.token }), 403, 'WIP yok');
  const r1 = await api('POST', '/api/rooms', { token: U.h.token, body: { name: 'H1' } });
  ok(r1);
  const r2 = await api('POST', '/api/rooms', { token: U.h.token, body: { name: 'H2' } });
  ok(r2, 'WIP 2 ile 2 oda');
  status(await api('POST', '/api/rooms', { token: U.h.token, body: { name: 'H3' } }), 409);
  await api('POST', `/api/rooms/${r1.body.room.id}/close`, { token: U.h.token });
  await api('POST', `/api/rooms/${r2.body.room.id}/close`, { token: U.h.token });
  await sql(`UPDATE users SET coins = 10 WHERE id = $1`, [U.x.id]);
  status(await api('POST', '/api/wip/purchase', { token: U.x.token, body: { planId: plan(1).id } }), 400, 'yetersiz coin');
});

let agencyId;
test('ajans/yayıncı: başvuru, onay, katılma, komisyon (kendine hediye hariç), panel, ödeme', { skip, timeout: 60000 }, async () => {
  status(await api('POST', '/api/broadcaster/apply', { token: U.f.token }), 201);
  status(await api('POST', '/api/broadcaster/apply', { token: U.f.token }), 409, 'tekrar başvuru');
  ok(await api('POST', `/api/admin/broadcasters/${U.f.id}/status`, { token: U.d.token, body: { status: 'approved' } }));
  status(await api('POST', `/api/admin/broadcasters/${U.f.id}/status`, { token: U.a.token, body: { status: 'approved' } }), 403, 'yetkisiz');
  const ag = await api('POST', '/api/agencies', { token: U.e.token, body: { name: `Ajans ${tag}`, description: 'test ajansı' } });
  status(ag, 201);
  agencyId = ag.body.agency.id;
  status(await api('POST', `/api/agencies/${agencyId}/apply`, { token: U.f.token }), 404, 'onaysız ajansa başvurulamaz');
  ok(await api('POST', `/api/admin/agencies/${agencyId}/status`, { token: U.d.token, body: { status: 'active', commissionBps: 1000 } }));
  status(await api('POST', `/api/admin/agencies/${agencyId}/status`, { token: U.a.token, body: { status: 'active' } }), 403);
  const ap = await api('POST', `/api/agencies/${agencyId}/apply`, { token: U.f.token });
  status(ap, 201);
  status(await api('POST', `/api/agency-requests/${ap.body.requestId}/respond`, { token: U.f.token, body: { accept: true } }), 403, 'başvuruyu başvuran onaylayamaz');
  ok(await api('POST', `/api/agency-requests/${ap.body.requestId}/respond`, { token: U.e.token, body: { accept: true } }));

  // F, A'nın odasında; A hediye gönderir → komisyon %10
  const c0 = BigInt((await sql(`SELECT COALESCE(SUM(diamond_amount),0) AS s FROM agency_commissions WHERE agency_id=$1`, [agencyId])).rows[0].s);
  ok(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: heart.id, quantity: 4, distribution: 'single', recipientId: U.f.id } }));
  const c1 = BigInt((await sql(`SELECT COALESCE(SUM(diamond_amount),0) AS s FROM agency_commissions WHERE agency_id=$1`, [agencyId])).rows[0].s);
  assert.equal(c1 - c0, 20n, '200 coin × %10 = 20');
  // F kendine hediye: komisyon OLUŞMAMALI
  ok(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.f.token, body: { giftId: heart.id, quantity: 4, distribution: 'single', recipientId: U.f.id } }));
  const c2 = BigInt((await sql(`SELECT COALESCE(SUM(diamond_amount),0) AS s FROM agency_commissions WHERE agency_id=$1`, [agencyId])).rows[0].s);
  assert.equal(c2, c1, 'kendine hediyede ajans komisyonu olmamalı');

  const dash = await api('GET', `/api/agencies/${agencyId}/dashboard`, { token: U.e.token });
  ok(dash);
  assert.equal(dash.body.broadcasters.length, 1);
  assert.equal(dash.body.broadcasters[0].diamonds, '200', 'yayıncı kazancına kendine hediye dahil değil');
  assert.equal(dash.body.totals.commissionAccrued, '20');
  status(await api('GET', `/api/agencies/${agencyId}/dashboard`, { token: U.g.token }), 403, 'başkası paneli göremez');
  const me = await api('GET', '/api/broadcaster/me', { token: U.f.token });
  assert.equal(me.body.broadcaster.periodDiamonds, '200');

  const period = new Date(Date.now() + 3 * 3600e3).toISOString().slice(0, 7);
  const st = await api('POST', `/api/admin/agencies/${agencyId}/settle`, { token: U.d.token, body: { period } });
  ok(st);
  assert.equal(st.body.paidDiamonds, '20');
  status(await api('POST', `/api/admin/agencies/${agencyId}/settle`, { token: U.d.token, body: { period } }), 404, 'iki kez ödenemez');
});

test('özel mesaj, gizlilik, engelleme', { skip, timeout: 60000 }, async () => {
  const send = await api('POST', `/api/messages/with/${U.c.id}`, { token: U.b.token, body: { text: 'selam C' } });
  status(send, 201);
  assert.equal((await api('GET', '/api/messages/unread-count', { token: U.c.token })).body.unread, 1);
  const conv = await api('GET', '/api/messages/conversations', { token: U.c.token });
  ok(conv);
  assert.equal(conv.body.conversations[0].unread, 1);
  assert.equal(conv.body.conversations[0].peer.id, U.b.id);
  const th = await api('GET', `/api/messages/with/${U.b.id}`, { token: U.c.token });
  assert.equal(th.body.messages.length, 1);
  assert.equal((await api('GET', '/api/messages/unread-count', { token: U.c.token })).body.unread, 0, 'okundu işaretlendi');
  status(await api('POST', `/api/messages/with/${U.c.id}`, { token: U.c.token, body: { text: 'x' } }), 400, 'kendine mesaj');
  ok(await api('PATCH', '/api/me', { token: U.c.token, body: { whoCanDm: 'nobody' } }));
  status(await api('POST', `/api/messages/with/${U.c.id}`, { token: U.b.token, body: { text: 'tekrar' } }), 403, 'kimse');
  ok(await api('PATCH', '/api/me', { token: U.c.token, body: { whoCanDm: 'following' } }));
  status(await api('POST', `/api/messages/with/${U.c.id}`, { token: U.b.token, body: { text: 'tekrar' } }), 403, 'C, B yi takip etmiyor');
  ok(await api('POST', `/api/users/${U.b.id}/follow`, { token: U.c.token }));
  status(await api('POST', `/api/messages/with/${U.c.id}`, { token: U.b.token, body: { text: 'artık olur' } }), 201);
  ok(await api('PATCH', '/api/me', { token: U.c.token, body: { whoCanDm: 'everyone' } }));
  // engelleme: takip kalkar, mesaj/arama kapanır
  ok(await api('POST', `/api/blocks/${U.b.id}`, { token: U.c.token }));
  status(await api('POST', `/api/messages/with/${U.c.id}`, { token: U.b.token, body: { text: 'engelli' } }), 403);
  status(await api('POST', `/api/messages/with/${U.b.id}`, { token: U.c.token, body: { text: 'ben engelledim' } }), 403);
  const prof = await api('GET', `/api/users/${U.b.id}`, { token: U.a.token });
  assert.equal(prof.body.profile.following !== undefined, true);
  const s = await api('GET', `/api/users/search?q=${encodeURIComponent(`e2e_${tag}_c`)}`, { token: U.b.token });
  assert.ok(!s.body.users.some((u) => u.id === U.c.id), 'engelleyen kullanıcı aramada görünmemeli');
  status(await api('POST', `/api/users/${U.c.id}/follow`, { token: U.b.token }), 403);
  const bl = await api('GET', '/api/blocks', { token: U.c.token });
  assert.ok(bl.body.users.some((u) => u.id === U.b.id));
  ok(await api('DELETE', `/api/blocks/${U.b.id}`, { token: U.c.token }));
});

test('şikâyet ve yönetim', { skip, timeout: 60000 }, async () => {
  status(await api('POST', '/api/reports', { token: U.b.token, body: { kind: 'user', targetUserId: U.c.id, reason: 'spam', details: 'test' } }), 201);
  const dup = await api('POST', '/api/reports', { token: U.b.token, body: { kind: 'user', targetUserId: U.c.id, reason: 'spam' } });
  ok(dup);
  assert.equal(dup.body.duplicate, true);
  status(await api('POST', '/api/reports', { token: U.b.token, body: { kind: 'user', reason: 'spam' } }), 400, 'hedef gerekli');
  status(await api('POST', '/api/reports', { token: U.b.token, body: { kind: 'user', targetUserId: U.c.id, reason: 'uydurma' } }), 400);
  status(await api('GET', '/api/admin/reports', { token: U.b.token }), 403, 'yetkisiz');
  const rep = await api('GET', '/api/admin/reports', { token: U.d.token });
  ok(rep);
  assert.equal(rep.body.reports.length, 1);
  ok(await api('POST', `/api/admin/reports/${rep.body.reports[0].id}/resolve`, { token: U.d.token, body: { status: 'resolved', note: 'ok' } }));
  // yasaklama oturumu anında geçersiz kılar
  ok(await api('POST', `/api/admin/users/${U.g.id}/status`, { token: U.d.token, body: { status: 'banned' } }));
  status(await api('GET', '/api/me', { token: U.g.token }), 401, 'yasaklı token geçersiz');
  // coin düzenleme yalnızca admin; negatif bakiye olmaz
  const c0 = await coins(U.b);
  ok(await api('POST', `/api/admin/users/${U.b.id}/coins`, { token: U.d.token, body: { amount: 500, reason: 'test' } }));
  assert.equal(await coins(U.b), c0 + 500n);
  status(await api('POST', `/api/admin/users/${U.b.id}/coins`, { token: U.d.token, body: { amount: '0x10' } }), 400, 'onaltılık reddedilir');
  status(await api('POST', `/api/admin/users/${U.b.id}/coins`, { token: U.d.token, body: { amount: -99999999999 } }), 400, 'bakiye negatife düşemez');
  // güvenlik uç noktaları
  ok(await api('GET', '/api/admin/security/events', { token: U.d.token }));
  status(await api('POST', '/api/admin/security/blocks', { token: U.d.token, body: { ip: '203.0.113.9', minutes: 5, reason: 'e2e' } }), 201);
  const bl = await api('GET', '/api/admin/security/blocks', { token: U.d.token });
  assert.ok(bl.body.blocks.some((b) => b.ip === '203.0.113.9'));
  ok(await api('DELETE', '/api/admin/security/blocks/203.0.113.9', { token: U.d.token }));
  status(await api('POST', '/api/admin/security/blocks', { token: U.d.token, body: { ip: 'abc' } }), 400);
  const row = await sql(`SELECT 1 FROM firewall_blocks WHERE ip = '203.0.113.9'`);
  assert.equal(row.rowCount, 0, 'kalıcı yasak kaydı silinmeli');
});

test('liderlik tablosu, cüzdan geçmişi ve hesap silme', { skip, timeout: 60000 }, async () => {
  const lb = await api('GET', '/api/leaderboards?type=senders&period=weekly', { token: U.b.token });
  ok(lb);
  assert.ok(lb.body.entries.some((e) => e.user.id === U.a.id), 'A en çok gönderenler arasında');
  const rc = await api('GET', '/api/leaderboards?type=receivers&period=all', { token: U.b.token });
  ok(rc);
  ok(await api('GET', '/api/leaderboards?type=families&period=daily', { token: U.b.token }));
  status(await api('GET', '/api/leaderboards?type=zzz', { token: U.b.token }), 400);
  const w = await api('GET', '/api/me/wallet', { token: U.a.token });
  ok(w);
  assert.ok(w.body.transactions.length > 5);
  status(await api('DELETE', '/api/me', { token: U.x.token, body: { password: 'yanlis' } }), 403);
  const y = await register('y');
  ok(await api('DELETE', '/api/me', { token: y.token, body: { password: 'sifre123' } }));
  status(await api('GET', '/api/me', { token: y.token }), 401, 'silinen hesabın tokeni geçersiz');
  status(await api('POST', '/api/auth/login', { body: { username: y.username, password: 'sifre123' } }), 401, 'eski kullanıcı adı artık yok');
});

test('oda sahibi çıkınca oda kapanır', { skip, timeout: 60000 }, async () => {
  ok(await api('POST', `/api/rooms/${roomId}/leave`, { token: U.a.token }));
  const r = await api('GET', `/api/rooms/${roomId}`, { token: U.b.token });
  status(r, 404, 'kapanan oda bulunamaz');
  const left = await sql(`SELECT COUNT(*)::int AS n FROM room_members WHERE room_id = $1`, [roomId]);
  assert.equal(left.rows[0].n, 0);
  const sess = await sql(`SELECT COUNT(*)::int AS n FROM broadcast_sessions WHERE ended_at IS NULL AND room_id = $1`, [roomId]);
  assert.equal(sess.rows[0].n, 0);
  const ms = await sql(`SELECT COUNT(*)::int AS n FROM room_music WHERE room_id = $1`, [roomId]);
  assert.equal(ms.rows[0].n, 0, 'oda kapanınca müzik durumu temizlenir');
});
