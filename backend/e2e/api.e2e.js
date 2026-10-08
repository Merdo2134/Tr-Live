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
  // kalıcı oda: aynı türde ikinci "oda aç" yeni oda açmaz, mevcut odayı döndürür; ad ve etiketler profildeki gibi kalır
  const second = await api('POST', '/api/rooms', { token: U.a.token, body: { name: 'İkinci', tags: ['başka'] } });
  status(second, 200, 'aynı odaya girer');
  assert.equal(second.body.room.id, roomId);
  assert.equal(second.body.room.name, 'E2E Oda');
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

test('hediye: çoklu alıcı (her birine tam adet), Tüm Koltuk / Tüm Oda, sekmeler', { skip, timeout: 60000 }, async () => {
  const list = await api('GET', '/api/gifts', { token: U.a.token });
  ok(list);
  assert.ok(list.body.globalMinCoins);
  assert.ok(list.body.gifts.every((g) => ['event', 'popular', 'private', 'vip'].includes(g.category)));
  const a0 = await coins(U.a);
  const each = await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: rose.id, quantity: 2, distribution: 'each', recipientIds: [U.b.id, U.c.id] } });
  ok(each, 'each');
  assert.equal(each.body.totalCoins, '40', 'adet × kişi');
  assert.equal(await coins(U.a), a0 - 40n);
  status(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: rose.id, quantity: 1, distribution: 'each', recipientIds: [] } }), 400, 'boş alıcı listesi');
  status(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: rose.id, quantity: 1, distribution: 'each', recipientIds: ['00000000-0000-4000-8000-000000000000'] } }), 400, 'odada olmayan alıcı');
  const mic = await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: rose.id, quantity: 1, distribution: 'all_mic' } });
  ok(mic, 'all_mic');
  assert.ok(mic.body.transactions.every((t) => t.receiverId !== U.a.id), 'kendine gitmez');
  const all = await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: rose.id, quantity: 1, distribution: 'all_room' } });
  ok(all, 'all_room');
  assert.ok(all.body.transactions.length >= 2);
  assert.ok(all.body.transactions.every((t) => t.receiverId !== U.a.id));
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
  const r = await api('POST', '/api/rooms', { token: U.e.token, body: { name: 'Gizli Oda' } });
  ok(r);
  assert.equal(r.body.room.locked, false, 'oda kurulurken şifre istenmez');
  const id = r.body.room.id;
  ok(await api('PATCH', `/api/rooms/${id}`, { token: U.e.token, body: { password: '1234' } }), 'şifre oda içinden konur');
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
  const r2 = await api('POST', '/api/rooms', { token: U.h.token, body: { name: 'H2', roomType: 'video' } });
  ok(r2, 'sesli ve görüntülü için birer oda');
  const again = await api('POST', '/api/rooms', { token: U.h.token, body: { name: 'H3' } });
  status(again, 200, 'aynı türde yeni oda açılmaz');
  assert.equal(again.body.room.id, r1.body.room.id);
  await api('POST', `/api/rooms/${r1.body.room.id}/close`, { token: U.h.token });
  await api('POST', `/api/rooms/${r2.body.room.id}/close`, { token: U.h.token });
  await sql(`UPDATE users SET coins = 10 WHERE id = $1`, [U.x.id]);
  status(await api('POST', '/api/wip/purchase', { token: U.x.token, body: { planId: plan(1).id } }), 400, 'yetersiz coin');
});

let agencyId; let agencyCode;
test('ajans/yayıncı: başvuru, kod, onay, katılma, hedef/maaş, komisyon kademesi, dönem kapatma, KYC, ödeme', { skip, timeout: 90000 }, async () => {
  status(await api('POST', '/api/broadcaster/apply', { token: U.f.token }), 201);
  status(await api('POST', '/api/broadcaster/apply', { token: U.f.token }), 409, 'tekrar başvuru');
  ok(await api('POST', `/api/admin/broadcasters/${U.f.id}/status`, { token: U.d.token, body: { status: 'approved' } }));
  status(await api('POST', `/api/admin/broadcasters/${U.f.id}/status`, { token: U.a.token, body: { status: 'approved' } }), 403, 'yetkisiz');
  const ag = await api('POST', '/api/agencies', { token: U.e.token, body: { name: `Ajans ${tag}`, description: 'test ajansı' } });
  status(ag, 201);
  agencyId = ag.body.agency.id;
  status(await api('POST', `/api/agencies/${agencyId}/apply`, { token: U.f.token }), 404, 'onaysız ajansa başvurulamaz');
  ok(await api('POST', `/api/admin/agencies/${agencyId}/status`, { token: U.d.token, body: { status: 'active' } }));
  status(await api('POST', `/api/admin/agencies/${agencyId}/status`, { token: U.a.token, body: { status: 'active' } }), 403);

  const mine = await api('GET', '/api/agencies/mine', { token: U.e.token });
  agencyCode = mine.body.owned.agencyCode;
  assert.match(agencyCode, /^\d{8}$/, '8 haneli ajans kodu');
  status(await api('GET', '/api/agencies/by-code/123', { token: U.f.token }), 400);
  status(await api('GET', '/api/agencies/by-code/00000000', { token: U.f.token }), 404);
  ok(await api('GET', `/api/agencies/by-code/${agencyCode}`, { token: U.f.token }));
  const ap = await api('POST', '/api/agencies/apply-by-code', { token: U.f.token, body: { code: agencyCode } });
  status(ap, 201);
  status(await api('POST', `/api/agency-requests/${ap.body.requestId}/respond`, { token: U.f.token, body: { accept: true } }), 403, 'başvuruyu başvuran onaylayamaz');
  ok(await api('POST', `/api/agency-requests/${ap.body.requestId}/respond`, { token: U.e.token, body: { accept: true } }));

  // Ayarlar: yalnızca yönetici; geçersiz kademeler reddedilir.
  status(await api('PUT', '/api/admin/agency-config', { token: U.a.token, body: { settings: { cycle: 'monthly' } } }), 403);
  status(await api('PUT', '/api/admin/agency-config', { token: U.d.token, body: { salaryTiers: [{ hours: 9, diamonds: 100, salaryCents: 5 }, { hours: 1, diamonds: 200, salaryCents: 9 }] } }), 400, 'azalan kademe');
  ok(await api('PUT', '/api/admin/agency-config', { token: U.d.token, body: {
    settings: { cycle: 'monthly', penaltyBps: 5000, requireOfficialEvents: false, minEventCount: 0, currency: 'USD' },
    salaryTiers: [{ hours: 1, diamonds: 100, salaryCents: 1000 }, { hours: 10, diamonds: 1000, salaryCents: 5000 }],
    commissionTiers: [{ minDiamonds: 0, bps: 2000 }, { minDiamonds: 150, bps: 3000 }],
  } }));

  // Yalnızca yayıncı onayından SONRAKİ süre ve hediyeler sayılır: önceki hediyeler (Tüm Oda testi) onaydan önceye, onay 4 saat öncesine alınır.
  await sql(`UPDATE gift_transactions SET created_at = NOW() - INTERVAL '5 hours' WHERE receiver_id = $1`, [U.f.id]);
  await sql(`UPDATE broadcasters SET approved_at = NOW() - INTERVAL '4 hours' WHERE user_id = $1`, [U.f.id]);
  // A (oda sahibi) F'ye hediye: 200 Diamond. F kendine hediye: sayılmaz.
  ok(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: heart.id, quantity: 4, distribution: 'single', recipientId: U.f.id } }));
  ok(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.f.token, body: { giftId: heart.id, quantity: 4, distribution: 'single', recipientId: U.f.id } }));
  const tagged = await sql(`SELECT COUNT(*)::int AS n FROM gift_transactions WHERE receiver_id=$1 AND receiver_agency_id=$2`, [U.f.id, agencyId]);
  assert.equal(tagged.rows[0].n, 2, 'hediyeler ajansla etiketlenir');
  // F'nin 2 saatlik mikrofon oturumu
  await sql(`INSERT INTO mic_sessions(user_id, room_id, started_at, ended_at) VALUES($1,$2,NOW() - INTERVAL '3 hours', NOW() - INTERVAL '1 hour')`, [U.f.id, roomId]);

  const dash = await api('GET', `/api/agencies/${agencyId}/dashboard`, { token: U.e.token });
  ok(dash);
  assert.equal(dash.body.broadcasters.length, 1);
  assert.equal(dash.body.broadcasters[0].diamonds, '200', 'kazanca kendine hediye dahil değil');
  assert.ok(dash.body.broadcasters[0].seconds >= 7200);
  assert.equal(dash.body.totals.teamDiamonds, '200');
  assert.equal(dash.body.totals.commissionBps, 3000, '200 ≥ 150 → ikinci kademe');
  assert.equal(dash.body.totals.estimatedCommissionDiamonds, '60');
  assert.equal(dash.body.broadcasters[0].tier, 1);
  assert.equal(dash.body.broadcasters[0].estimatedCents, '1000');
  status(await api('GET', `/api/agencies/${agencyId}/dashboard`, { token: U.g.token }), 403, 'başkası paneli göremez');
  const me = await api('GET', '/api/broadcaster/me', { token: U.f.token });
  ok(me);
  assert.equal(me.body.broadcaster.progress.diamonds, '200');
  assert.equal(me.body.broadcaster.progress.tier, 1);
  assert.equal(me.body.broadcaster.progress.next.level, 2);

  // Dönem kapatma: bitmeyen dönem force olmadan kapanmaz.
  const period = new Date(Date.now() + 3 * 3600e3).toISOString().slice(0, 7);
  status(await api('POST', '/api/admin/payouts/close', { token: U.d.token, body: { period } }), 409, 'dönem bitmedi');
  status(await api('POST', '/api/admin/payouts/close', { token: U.a.token, body: { period, force: true } }), 403);
  const closed = await api('POST', '/api/admin/payouts/close', { token: U.d.token, body: { period, force: true } });
  status(closed, 201);
  assert.equal(closed.body.hostStatements, 1);
  assert.equal(closed.body.agencyStatements, 1);
  status(await api('POST', '/api/admin/payouts/close', { token: U.d.token, body: { period, force: true } }), 409, 'aynı dönem iki kez kapanmaz');

  const list = await api('GET', '/api/admin/payouts', { token: U.d.token });
  const pid = list.body.periods[0].id;
  const detail = await api('GET', `/api/admin/payouts/${pid}`, { token: U.d.token });
  ok(detail);
  const hs = detail.body.hostStatements[0]; const as = detail.body.agencyStatements[0];
  assert.equal(hs.salaryCents, '1000'); assert.equal(hs.penaltyApplied, false);
  assert.equal(as.commissionDiamonds, '60');

  // KYC onayı olmadan yayıncı maaşı ödenemez
  status(await api('POST', `/api/admin/statements/host/${hs.id}/pay`, { token: U.d.token }), 409, 'KYC yok');
  ok(await api('POST', '/api/me/kyc/request', { token: U.f.token }));
  status(await api('POST', '/api/me/kyc/request', { token: U.f.token }), 409);
  ok(await api('POST', `/api/admin/users/${U.f.id}/kyc`, { token: U.d.token, body: { status: 'approved' } }));
  ok(await api('POST', `/api/admin/statements/host/${hs.id}/pay`, { token: U.d.token }));
  status(await api('POST', `/api/admin/statements/host/${hs.id}/pay`, { token: U.d.token }), 409, 'iki kez ödenemez');
  ok(await api('POST', `/api/admin/statements/agency/${as.id}/pay`, { token: U.d.token }));
  const stm = await api('GET', '/api/broadcaster/statements', { token: U.f.token });
  assert.equal(stm.body.statements[0].status, 'paid');
  const astm = await api('GET', `/api/agencies/${agencyId}/statements`, { token: U.e.token });
  assert.equal(astm.body.agencyStatements[0].status, 'paid');
});

test('oda: gizli oda + davet kodu, tema, WIP özel tema, sayı tahtası, sohbet temizleme', { skip, timeout: 60000 }, async () => {
  const hr = await api('POST', '/api/rooms', { token: U.g.token, body: { name: 'Gizli Oda', hidden: true, theme: 'neon' } });
  status(hr, 201);
  const hid = hr.body.room.id; const code = hr.body.room.joinCode;
  assert.match(code, /^[A-HJ-NP-Z2-9]{6}$/);
  assert.equal(hr.body.room.theme, 'neon');
  const pub = await api('GET', '/api/rooms', { token: U.x.token });
  assert.ok(!pub.body.rooms.some((r) => r.id === hid), 'gizli oda listede yok');
  status(await api('GET', `/api/rooms/${hid}`, { token: U.x.token }), 404, 'gizli oda ayrıntısı gizli');
  status(await api('POST', `/api/rooms/${hid}/join`, { token: U.x.token, body: {} }), 403, 'kodsuz girilemez');
  status(await api('POST', `/api/rooms/${hid}/join`, { token: U.x.token, body: { code: 'AAAAAA' } }), 403, 'yanlış kod');
  status(await api('POST', '/api/rooms/by-code', { token: U.x.token, body: { code: 'ZZZZZZ' } }), 404);
  const bc = await api('POST', '/api/rooms/by-code', { token: U.x.token, body: { code } });
  ok(bc);
  assert.equal(bc.body.roomId, hid);
  const j = await api('POST', `/api/rooms/${hid}/join`, { token: U.x.token, body: { code } });
  ok(j);
  assert.equal(j.body.room.joinCode, undefined, 'kodu yalnızca sahibi görür');
  const own = await api('GET', `/api/rooms/${hid}`, { token: U.g.token });
  assert.equal(own.body.room.joinCode, code);
  // kod yenileme / sabit kalma
  const same = await api('PATCH', `/api/rooms/${hid}`, { token: U.g.token, body: { hidden: true } });
  assert.equal(same.body.room.joinCode, code, 'tekrar gizleme kodu değiştirmez');
  const regen = await api('PATCH', `/api/rooms/${hid}`, { token: U.g.token, body: { regenerateCode: true } });
  assert.notEqual(regen.body.room.joinCode, code);
  // tema
  status(await api('PATCH', `/api/rooms/${hid}`, { token: U.g.token, body: { theme: 'yok' } }), 400);
  ok(await api('PATCH', `/api/rooms/${hid}`, { token: U.g.token, body: { theme: 'galaxy' } }));
  status(await api('PATCH', `/api/rooms/${hid}`, { token: U.g.token, body: { themeImageUrl: 'https://example.com/a.png' } }), 403, 'WIP 4 gerekir');
  ok(await api('POST', `/api/admin/users/${U.g.id}/wip`, { token: U.d.token, body: { level: 4, days: 30 } }));
  ok(await api('PATCH', `/api/rooms/${hid}`, { token: U.g.token, body: { themeImageUrl: 'https://example.com/a.png' } }));
  // sayı tahtası: x mikrofona çıkar, g ona hediye gönderir
  const c = await sql(`UPDATE users SET coins = coins + 10000 WHERE id = $1 RETURNING id`, [U.g.id]);
  assert.equal(c.rowCount, 1);
  ok(await api('POST', `/api/rooms/${hid}/mic/take`, { token: U.x.token, body: {} }));
  ok(await api('POST', `/api/rooms/${hid}/gifts/send`, { token: U.g.token, body: { giftId: heart.id, quantity: 3, distribution: 'single', recipientId: U.x.id } }));
  const sb = await api('GET', `/api/rooms/${hid}/scoreboard`, { token: U.x.token });
  ok(sb);
  const row = sb.body.scoreboard.find((r) => r.userId === U.x.id);
  assert.equal(row.coins, '150'); assert.equal(row.count, '3'); assert.equal(row.seatIndex, 1);
  status(await api('POST', `/api/rooms/${hid}/scoreboard/reset`, { token: U.x.token }), 403);
  ok(await api('POST', `/api/rooms/${hid}/scoreboard/reset`, { token: U.g.token }));
  assert.equal((await api('GET', `/api/rooms/${hid}/scoreboard`, { token: U.x.token })).body.scoreboard.length, 0);
  // sohbet temizleme
  ok(await api('POST', `/api/rooms/${hid}/messages`, { token: U.x.token, body: { text: 'merhaba' } }));
  status(await api('DELETE', `/api/rooms/${hid}/messages`, { token: U.x.token }), 403, 'sıradan üye temizleyemez');
  ok(await api('POST', `/api/rooms/${hid}/members/${U.x.id}/role`, { token: U.g.token, body: { role: 'moderator' } }));
  const cl = await api('DELETE', `/api/rooms/${hid}/messages`, { token: U.x.token });
  ok(cl);
  assert.equal((await api('GET', `/api/rooms/${hid}/messages`, { token: U.x.token })).body.messages.length, 0);
  // mikrofon oturumu açıldı mı
  const ms = await sql(`SELECT COUNT(*)::int AS n FROM mic_sessions WHERE room_id = $1 AND ended_at IS NULL`, [hid]);
  assert.equal(ms.rows[0].n, 2, 'sahip + mikrofondaki kullanıcı');
  ok(await api('POST', `/api/rooms/${hid}/close`, { token: U.g.token }));
  const ms2 = await sql(`SELECT COUNT(*)::int AS n FROM mic_sessions WHERE room_id = $1 AND ended_at IS NULL`, [hid]);
  assert.equal(ms2.rows[0].n, 0, 'oda kapanınca oturumlar kapanır');
});

test('PK: davet, kabul, skor (kendine hediye sayılmaz), bitiş', { skip, timeout: 60000 }, async () => {
  const r2 = await api('POST', '/api/rooms', { token: U.h.token, body: { name: 'PK Rakip' } });
  status(r2, 201);
  const room2 = r2.body.room.id;
  ok(await api('POST', `/api/rooms/${room2}/join`, { token: U.c.token }));
  status(await api('POST', '/api/pk/challenge', { token: U.b.token, body: { roomId, targetRoomId: room2, durationSeconds: 60 } }), 403, 'sahip değil');
  status(await api('POST', '/api/pk/challenge', { token: U.a.token, body: { roomId, targetRoomId: room2, durationSeconds: 10 } }), 400, 'kısa süre');
  const ch = await api('POST', '/api/pk/challenge', { token: U.a.token, body: { roomId, targetRoomId: room2, durationSeconds: 60 } });
  status(ch, 201);
  const pkId = ch.body.pk.id;
  status(await api('POST', '/api/pk/challenge', { token: U.a.token, body: { roomId, targetRoomId: room2, durationSeconds: 60 } }), 409, 'ikinci PK');
  status(await api('POST', `/api/pk/${pkId}/respond`, { token: U.a.token, body: { accept: true } }), 403, 'davet eden kabul edemez');
  ok(await api('POST', `/api/pk/${pkId}/respond`, { token: U.h.token, body: { accept: true } }));
  // A'ya (oda sahibi) B hediye: 50 puan. A kendine: sayılmaz. C, H'ye 100.
  await sql(`UPDATE users SET coins = coins + 10000 WHERE id = ANY($1::uuid[])`, [[U.a.id, U.b.id, U.c.id]]);
  ok(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.b.token, body: { giftId: heart.id, quantity: 1, distribution: 'single', recipientId: U.a.id } }));
  ok(await api('POST', `/api/rooms/${roomId}/gifts/send`, { token: U.a.token, body: { giftId: heart.id, quantity: 2, distribution: 'single', recipientId: U.a.id } }));
  ok(await api('POST', `/api/rooms/${room2}/gifts/send`, { token: U.c.token, body: { giftId: heart.id, quantity: 2, distribution: 'single', recipientId: U.h.id } }));
  const st = await api('GET', `/api/rooms/${roomId}/pk`, { token: U.b.token });
  assert.equal(st.body.pk.a.score, '50');
  assert.equal(st.body.pk.b.score, '100');
  assert.equal(st.body.pk.status, 'active');
  ok(await api('POST', `/api/pk/${pkId}/cancel`, { token: U.a.token }));
  const fin = await sql(`SELECT status, winner_room FROM pk_battles WHERE id = $1`, [pkId]);
  assert.equal(fin.rows[0].status, 'finished');
  assert.equal(fin.rows[0].winner_room, room2, 'yüksek skor kazanır');
  ok(await api('POST', `/api/rooms/${room2}/close`, { token: U.h.token }));
});

test('Ludo: kurma, katılma, başlatma, zar/hamle yetkisi, ayrılma', { skip, timeout: 60000 }, async () => {
  status(await api('POST', `/api/rooms/${roomId}/games`, { token: U.b.token, body: {} }), 403, 'sıradan üye kuramaz');
  const g = await api('POST', `/api/rooms/${roomId}/games`, { token: U.a.token, body: { type: 'ludo' } });
  status(g, 201);
  const gid = g.body.game.id;
  status(await api('POST', `/api/rooms/${roomId}/games`, { token: U.a.token, body: {} }), 409, 'tek açık oyun');
  status(await api('POST', `/api/games/${gid}/start`, { token: U.a.token }), 409, 'tek kişiyle başlamaz');
  ok(await api('POST', `/api/games/${gid}/join`, { token: U.b.token }));
  status(await api('POST', `/api/games/${gid}/join`, { token: U.x.token }), 403, 'odada olmayan katılamaz');
  status(await api('POST', `/api/games/${gid}/start`, { token: U.b.token }), 403, 'yalnızca kurucu başlatır');
  ok(await api('POST', `/api/games/${gid}/start`, { token: U.a.token }));
  const view = await api('GET', `/api/rooms/${roomId}/game`, { token: U.b.token });
  assert.equal(view.body.game.status, 'playing');
  const turnUser = view.body.game.turnUserId;
  const other = turnUser === U.a.id ? U.b : U.a; const cur = turnUser === U.a.id ? U.a : U.b;
  status(await api('POST', `/api/games/${gid}/roll`, { token: other.token }), 409, 'sıra sizde değil');
  const roll = await api('POST', `/api/games/${gid}/roll`, { token: cur.token });
  ok(roll);
  assert.ok(roll.body.dice >= 1 && roll.body.dice <= 6);
  if (!roll.body.skipped) {
    status(await api('POST', `/api/games/${gid}/move`, { token: cur.token, body: { token: 9 } }), 409, 'geçersiz taş');
    ok(await api('POST', `/api/games/${gid}/move`, { token: cur.token, body: { token: roll.body.legal[0] } }));
  }
  // B ayrılırsa A kazanır
  ok(await api('POST', `/api/games/${gid}/leave`, { token: U.b.token }));
  const done = await sql(`SELECT status, winner_id FROM room_games WHERE id = $1`, [gid]);
  assert.equal(done.rows[0].status, 'finished');
  assert.equal(done.rows[0].winner_id, U.a.id);
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
  ok(await api('POST', `/api/admin/users/${U.g.id}/ban`, { token: U.d.token, body: { reason: 'e2e' } }));
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

test('roller: yardımcı admin (dar yetki, süreli ban) ve oda moderatörü', { skip, timeout: 90000 }, async () => {
  const sup = await register('sup'); const v = await register('victim'); const v2 = await register('victim2');
  // yardımcı admini yalnızca yönetici atar
  status(await api('POST', `/api/admin/users/${sup.id}/staff-role`, { token: U.a.token, body: { role: 'support' } }), 403, 'normal kullanıcı atayamaz');
  ok(await api('POST', `/api/admin/users/${sup.id}/staff-role`, { token: U.d.token, body: { role: 'support' } }));
  // dar yetki: nick, fotoğraf, ban serbest
  ok(await api('GET', `/api/admin/users?q=${v.username}`, { token: sup.token }), 'arama');
  ok(await api('POST', `/api/admin/users/${v.id}/display-name`, { token: sup.token, body: { displayName: 'Yeni Nick' } }));
  assert.equal((await sql('SELECT display_name FROM users WHERE id=$1', [v.id])).rows[0].display_name, 'Yeni Nick');
  await sql(`UPDATE users SET avatar_url = 'https://x.test/a.png' WHERE id = $1`, [v.id]);
  ok(await api('POST', `/api/admin/users/${v.id}/avatar`, { token: sup.token, body: { avatarUrl: null } }));
  assert.equal((await sql('SELECT avatar_url FROM users WHERE id=$1', [v.id])).rows[0].avatar_url, null);
  // yasak alanlar
  status(await api('POST', `/api/admin/users/${v.id}/coins`, { token: sup.token, body: { amount: 100 } }), 403, 'coin');
  status(await api('POST', `/api/admin/users/${v.id}/wip`, { token: sup.token, body: { level: 1, days: 1 } }), 403, 'wip');
  status(await api('POST', `/api/admin/users/${v.id}/staff-role`, { token: sup.token, body: { role: 'support' } }), 403, 'yetki dağıtamaz');
  status(await api('GET', '/api/admin/staff', { token: sup.token }), 403);
  status(await api('GET', '/api/admin/reports', { token: sup.token }), 403);
  status(await api('POST', `/api/admin/users/${U.d.id}/ban`, { token: sup.token, body: {} }), 403, 'yöneticiyi banlayamaz');
  // süreli ban: giriş reddedilir, süre dolunca otomatik açılır
  ok(await api('POST', `/api/admin/users/${v.id}/ban`, { token: sup.token, body: { hours: 2, reason: 'spam' } }));
  const lg = await api('POST', '/api/auth/login', { body: { username: v.username, password: 'sifre123' } });
  status(lg, 403, 'banlı giriş');
  assert.match(lg.body.error || lg.body.message || '', /spam/);
  status(await api('GET', '/api/me', { token: v.token }), 401, 'banlı token');
  await sql(`UPDATE users SET banned_until = NOW() - INTERVAL '1 minute' WHERE id = $1`, [v.id]);
  const lg2 = await api('POST', '/api/auth/login', { body: { username: v.username, password: 'sifre123' } });
  ok(lg2, 'süre dolunca giriş açılır');
  assert.equal((await sql('SELECT account_status FROM users WHERE id=$1', [v.id])).rows[0].account_status, 'active');
  // süresiz ban + kaldırma
  ok(await api('POST', `/api/admin/users/${v2.id}/ban`, { token: sup.token, body: {} }));
  assert.equal((await sql('SELECT banned_until FROM users WHERE id=$1', [v2.id])).rows[0].banned_until, null);
  ok(await api('POST', `/api/admin/users/${v2.id}/unban`, { token: sup.token, body: {} }));
  status(await api('POST', `/api/admin/users/${v2.id}/ban`, { token: sup.token, body: { hours: -5 } }), 400);
  // yetkiyi geri alınca panel kapanır
  ok(await api('POST', `/api/admin/users/${sup.id}/staff-role`, { token: U.d.token, body: { role: 'user' } }));
  status(await api('GET', `/api/admin/users?q=${v.username}`, { token: sup.token }), 403);

  // ---- Oda moderatörü ----
  const own = await register('own'); const mod = await register('mod'); const u1 = await register('u1'); const u2 = await register('u2');
  const room = (await api('POST', '/api/rooms', { token: own.token, body: { name: 'Rol Odası', seatCount: 8 } })).body.room;
  for (const x of [mod, u1, u2]) ok(await api('POST', `/api/rooms/${room.id}/join`, { token: x.token, body: {} }));
  status(await api('POST', `/api/rooms/${room.id}/members/${mod.id}/role`, { token: u1.token, body: { role: 'moderator' } }), 403, 'normal üye moderatör atayamaz');
  ok(await api('POST', `/api/rooms/${room.id}/members/${mod.id}/role`, { token: own.token, body: { role: 'moderator' } }));
  status(await api('POST', `/api/rooms/${room.id}/members/${u1.id}/role`, { token: mod.token, body: { role: 'moderator' } }), 403, 'moderatör yetki dağıtamaz');
  // koltuk kilidi
  status(await api('POST', `/api/rooms/${room.id}/seats/3/lock`, { token: u1.token, body: { locked: true } }), 403, 'normal üye kilitleyemez');
  ok(await api('POST', `/api/rooms/${room.id}/seats/3/lock`, { token: mod.token, body: { locked: true } }));
  status(await api('POST', `/api/rooms/${room.id}/mic/take`, { token: u1.token, body: { seatIndex: 3 } }), 403, 'kilitli koltuk');
  status(await api('POST', `/api/rooms/${room.id}/seats/0/lock`, { token: mod.token, body: { locked: true } }), 400, 'sahip koltuğu kilitlenmez');
  ok(await api('POST', `/api/rooms/${room.id}/seats/3/lock`, { token: mod.token, body: { locked: false } }));
  // davet, indirme, susturma, atma
  status(await api('POST', `/api/rooms/${room.id}/members/${u1.id}/mic-invite`, { token: u2.token, body: {} }), 403, 'üye davet edemez');
  ok(await api('POST', `/api/rooms/${room.id}/members/${u1.id}/mic-invite`, { token: mod.token, body: { seatIndex: 2 } }));
  ok(await api('POST', `/api/rooms/${room.id}/mic/take`, { token: u1.token, body: { seatIndex: 2 } }));
  status(await api('POST', `/api/rooms/${room.id}/members/${u1.id}/mic-invite`, { token: mod.token, body: {} }), 409, 'zaten mikrofonda');
  ok(await api('POST', `/api/rooms/${room.id}/members/${u1.id}/mic-off`, { token: mod.token }), 'koltuktan kaldır');
  ok(await api('POST', `/api/rooms/${room.id}/members/${u2.id}/chat-mute`, { token: mod.token, body: { minutes: 5 } }), 'sustur');
  ok(await api('DELETE', `/api/rooms/${room.id}/messages`, { token: mod.token }), 'sohbet temizle');
  status(await api('POST', `/api/rooms/${room.id}/members/${own.id}/kick`, { token: mod.token }), 403, 'sahibi atamaz');
  ok(await api('POST', `/api/rooms/${room.id}/members/${u2.id}/kick`, { token: mod.token }), 'normal üyeyi at');
  status(await api('POST', `/api/rooms/${room.id}/leave`, { token: u1.token }), 200);
  ok(await api('POST', `/api/rooms/${room.id}/leave`, { token: own.token }));
});

test('favori yayıncı, son girilen odalar, oda arama, mikrofon sırası', { skip, timeout: 90000 }, async () => {
  const host = await register('fh'); const fan = await register('fan'); const w1 = await register('w1'); const w2 = await register('w2');
  const room = (await api('POST', '/api/rooms', { token: host.token, body: { name: 'Karaoke Gecesi', seatCount: 2, tags: ['karaoke'] } })).body.room;
  // arama: ad, etiket, yayıncı adı; LIKE joker karakteri etkisiz
  for (const q of ['karaoke', 'GECESI', 'Kişi fh']) {
    const r = await api('GET', `/api/rooms?q=${encodeURIComponent(q)}`, { token: fan.token });
    ok(r, q);
    assert.ok(r.body.rooms.some((x) => x.id === room.id), `arama bulmalı: ${q}`);
  }
  const wild = await api('GET', `/api/rooms?q=${encodeURIComponent('%')}`, { token: fan.token });
  assert.ok(!wild.body.rooms.some((x) => x.id === room.id), '% joker değil');
  assert.ok(!(await api('GET', '/api/rooms?q=yokboylebiroda', { token: fan.token })).body.rooms.length);
  // favori
  status(await api('POST', `/api/rooms/hosts/${fan.id}/favorite`, { token: fan.token }), 400, 'kendini ekleyemez');
  ok(await api('POST', `/api/rooms/hosts/${host.id}/favorite`, { token: fan.token }));
  ok(await api('POST', `/api/rooms/hosts/${host.id}/favorite`, { token: fan.token }), 'tekrar ekleme zararsız');
  assert.equal((await api('GET', `/api/rooms/hosts/${host.id}/favorite`, { token: fan.token })).body.favorite, true);
  const fav = await api('GET', '/api/rooms/favorites', { token: fan.token });
  ok(fav);
  assert.equal(fav.body.hosts.length, 1);
  assert.equal(fav.body.hosts[0].room.id, room.id, 'yayıncı açıkken oda görünür');
  // son girilen
  ok(await api('POST', `/api/rooms/${room.id}/join`, { token: fan.token, body: {} }));
  const rec = await api('GET', '/api/rooms/recent', { token: fan.token });
  assert.equal(rec.body.recent[0].user.id, host.id);
  // mikrofon sırası: 2 koltuklu odada 0. koltuk sahibin, tek boş koltuk 1
  for (const x of [w1, w2]) ok(await api('POST', `/api/rooms/${room.id}/join`, { token: x.token, body: {} }));
  ok(await api('POST', `/api/rooms/${room.id}/mic/take`, { token: fan.token, body: {} }));
  status(await api('POST', `/api/rooms/${room.id}/mic/take`, { token: w1.token, body: {} }), 409, 'koltuk dolu');
  ok(await api('POST', `/api/rooms/${room.id}/mic/queue`, { token: w1.token }));
  const qr = await api('POST', `/api/rooms/${room.id}/mic/queue`, { token: w2.token });
  assert.deepEqual(qr.body.queue, [w1.id, w2.id], 'sıra eskiden yeniye');
  ok(await api('POST', `/api/rooms/${room.id}/mic/queue`, { token: w1.token }), 'çift kayıt olmaz');
  assert.equal((await api('GET', `/api/rooms/${room.id}/mic/queue`, { token: w1.token })).body.queue.length, 2);
  // koltuk boşalınca ilk kişi sıradan düşer (davet gider), diğeri kalır
  ok(await api('POST', `/api/rooms/${room.id}/mic/leave`, { token: fan.token }));
  assert.deepEqual((await api('GET', `/api/rooms/${room.id}/mic/queue`, { token: w2.token })).body.queue, [w2.id]);
  ok(await api('POST', `/api/rooms/${room.id}/mic/take`, { token: w1.token, body: {} }));
  ok(await api('DELETE', `/api/rooms/${room.id}/mic/queue`, { token: w2.token }));
  assert.equal((await api('GET', `/api/rooms/${room.id}/mic/queue`, { token: w2.token })).body.queue.length, 0);
  ok(await api('DELETE', `/api/rooms/hosts/${host.id}/favorite`, { token: fan.token }));
  assert.equal((await api('GET', '/api/rooms/favorites', { token: fan.token })).body.hosts.length, 0);
  ok(await api('POST', `/api/rooms/${room.id}/leave`, { token: host.token }));
});

test('Keşfet akışı, banner ve duyurular', { skip, timeout: 90000 }, async () => {
  const a = await register('fa'); const b = await register('fb');
  // gönderi: boş olamaz, yazı ile açılır, beğeni tekrar sayılmaz, yorum sayacı artar
  status(await api('POST', '/api/posts', { token: a.token, body: { text: '   ' } }), 400, 'boş gönderi');
  const post = (await api('POST', '/api/posts', { token: a.token, body: { text: 'Merhaba dünya' } })).body.post;
  assert.equal(post.mine, true);
  ok(await api('POST', `/api/posts/${post.id}/like`, { token: b.token }));
  const again = await api('POST', `/api/posts/${post.id}/like`, { token: b.token });
  assert.equal(again.body.likeCount, 1, 'çifte beğeni sayılmaz');
  ok(await api('POST', `/api/posts/${post.id}/comments`, { token: b.token, body: { text: 'Güzel!' } }));
  assert.equal((await api('GET', `/api/posts/${post.id}/comments`, { token: b.token })).body.comments.length, 1);
  // akış: genel herkese, takip yalnızca takip edilenlere
  const all = await api('GET', '/api/posts?scope=all', { token: b.token });
  const row = all.body.posts.find((x) => x.id === post.id);
  assert.ok(row && row.liked === true && row.commentCount === 1);
  assert.ok(!(await api('GET', '/api/posts?scope=following', { token: b.token })).body.posts.some((x) => x.id === post.id));
  ok(await api('POST', `/api/users/${a.id}/follow`, { token: b.token }));
  assert.ok((await api('GET', '/api/posts?scope=following', { token: b.token })).body.posts.some((x) => x.id === post.id));
  // silme: başkası silemez, sahibi siler
  status(await api('DELETE', `/api/posts/${post.id}`, { token: b.token }), 403, 'başkası silemez');
  ok(await api('DELETE', `/api/posts/${post.id}`, { token: a.token }));
  assert.ok(!(await api('GET', '/api/posts?scope=all', { token: b.token })).body.posts.some((x) => x.id === post.id));
  // görsel adresi yalnızca yüklenen dosya biçiminde olabilir
  status(await api('POST', '/api/posts', { token: a.token, body: { text: 'x', imageUrl: 'https://evil.test/a.png' } }), 400, 'dış adres');
  // banner ve duyuru yalnızca yönetici
  status(await api('POST', '/api/admin/announcements', { token: a.token, body: { kind: 'event', title: 'Test', text: 'Merhaba' } }), 403);
  ok(await api('POST', '/api/admin/announcements', { token: U.d.token, body: { kind: 'event', title: 'Etkinlik', text: 'Hafta sonu yarışma' } }));
  const ann = await api('GET', '/api/announcements?kind=event', { token: a.token });
  assert.equal(ann.body.announcements[0].title, 'Etkinlik');
  const sum = await api('GET', '/api/inbox-summary', { token: a.token });
  assert.ok(sum.body.event >= 0);
  assert.deepEqual((await api('GET', '/api/banners')).body.banners, []);
  // oda bölgesi / şehir filtresi ve yeni koltuk düzeni
  const fc = await register('fc');
  status(await api('POST', '/api/rooms', { token: fc.token, body: { name: 'Yedi', seatCount: 7 } }), 400, 'desteklenmeyen düzen');
  const six = await api('POST', '/api/rooms', { token: fc.token, body: { name: 'Altı koltuk', seatCount: 6 } });
  status(six, 201);
  assert.equal(six.body.room.seatCount, 6);
  status(await api('GET', '/api/rooms?region=near'), 401, 'yakındakiler giriş ister');
});

test('kalıcı oda: bir kez kur, tek adımda aç, ad/etiket sabit, yöneticiler korunur', { skip, timeout: 90000 }, async () => {
  const own = await register('po'); const mod = await register('pm');
  assert.deepEqual((await api('GET', '/api/rooms/mine', { token: own.token })).body.rooms, { audio: null, video: null });
  status(await api('POST', '/api/rooms', { token: own.token, body: {} }), 400, 'ilk kurulumda ad zorunlu');
  const first = await api('POST', '/api/rooms', { token: own.token, body: { name: 'Benim Odam', tags: ['sohbet', 'müzik'], seatCount: 9 } });
  status(first, 201);
  const roomId1 = first.body.room.id;
  // yönetici ata
  ok(await api('POST', `/api/rooms/${roomId1}/join`, { token: mod.token }));
  ok(await api('POST', `/api/rooms/${roomId1}/members/${mod.id}/role`, { token: own.token, body: { role: 'moderator' } }));
  const mgr = (await api('GET', `/api/rooms/${roomId1}/managers`, { token: mod.token })).body.managers;
  assert.equal(mgr[0].role, 'owner');
  assert.ok(mgr.some((m) => m.user.id === mod.id && m.role === 'moderator'));
  // oda içinden ad/etiket değişir ve kalıcı olur
  ok(await api('PATCH', `/api/rooms/${roomId1}`, { token: own.token, body: { name: 'Yeni Ad', tags: ['karaoke'] } }));
  status(await api('PATCH', `/api/rooms/${roomId1}`, { token: mod.token, body: { name: 'Hack' } }), 403, 'moderatör adı değiştiremez');
  // mikrofon modu: koltuk sayısı değişir, taşan koltuktakiler iner, oda sahibi 0. koltuğa geri dönebilir
  ok(await api('PATCH', `/api/rooms/${roomId1}`, { token: own.token, body: { seatCount: 12 } }));
  ok(await api('POST', `/api/rooms/${roomId1}/mic/take`, { token: mod.token, body: { seatIndex: 10 } }));
  ok(await api('POST', `/api/rooms/${roomId1}/mic/take`, { token: own.token, body: { seatIndex: 3 } }));
  ok(await api('POST', `/api/rooms/${roomId1}/mic/take`, { token: own.token, body: { seatIndex: 0 } }));
  ok(await api('PATCH', `/api/rooms/${roomId1}`, { token: own.token, body: { seatCount: 5 } }));
  const after = (await api('GET', `/api/rooms/${roomId1}/members`, { token: own.token })).body.members;
  assert.equal(after.find((x) => x.userId === mod.id).seatIndex, null, 'taşan koltuk boşalır');
  assert.equal(after.find((x) => x.userId === own.id).seatIndex, 0);
  status(await api('PATCH', `/api/rooms/${roomId1}`, { token: own.token, body: { seatCount: 7 } }), 400, 'desteklenmeyen koltuk sayısı');
  status(await api('PATCH', `/api/rooms/${roomId1}`, { token: mod.token, body: { seatCount: 8 } }), 403, 'moderatör modu değiştiremez');
  ok(await api('PATCH', `/api/rooms/${roomId1}`, { token: own.token, body: { seatCount: 9 } }));
  // kapat ve tek adımda yeniden aç
  ok(await api('POST', `/api/rooms/${roomId1}/close`, { token: own.token }));
  const mine = (await api('GET', '/api/rooms/mine', { token: own.token })).body.rooms.audio;
  assert.equal(mine.name, 'Yeni Ad'); assert.deepEqual(mine.tags, ['karaoke']); assert.equal(mine.seatCount, 9); assert.equal(mine.activeRoomId, null);
  const reopen = await api('POST', '/api/rooms', { token: own.token, body: { name: 'Yok Sayılır' } });
  status(reopen, 201);
  assert.equal(reopen.body.room.name, 'Yeni Ad'); assert.equal(reopen.body.room.seatCount, 9);
  // heartbeat: üye canlı tutulur, üye olmayan 403, kapalı oda 404
  ok(await api('POST', `/api/rooms/${reopen.body.room.id}/heartbeat`, { token: own.token }));
  status(await api('POST', `/api/rooms/${reopen.body.room.id}/heartbeat`, { token: mod.token }), 403, 'üye olmayan');
  // yönetici yeni oturumda rolünü geri alır
  const j = await api('POST', `/api/rooms/${reopen.body.room.id}/join`, { token: mod.token });
  assert.equal(j.body.me.role, 'moderator');
  // görüntülü oda ayrı kurulur
  const video = await api('POST', '/api/rooms', { token: own.token, body: { name: 'Kamera', roomType: 'video', seatCount: 4 } });
  status(video, 201);
  assert.equal(video.body.room.roomType, 'video');
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

test('kimlik: kullanıcı ID, oda numarası, elmas bozdurma 5/1', { skip, timeout: 60000 }, async () => {
  const me = await api('GET', '/api/me', { token: U.a.token });
  ok(me, 'me');
  assert.match(String(me.body.user?.publicId ?? me.body.publicId), /^\d{8}$/);
  const rm = await api('POST', '/api/rooms', { token: U.a.token, body: { name: 'Kimlik Oda', seatCount: 8 } });
  assert.match(String(rm.body.room.roomNumber), /^\d{7}$/);
  const ex = await register(`ex${Date.now() % 100000}`);
  await sql('UPDATE users SET diamonds = 23 WHERE id=$1', [ex.id]);
  status(await api('POST', '/api/me/diamonds/exchange', { token: ex.token, body: { diamonds: 7 } }), 400, '5 katı değil');
  status(await api('POST', '/api/me/diamonds/exchange', { token: ex.token, body: { diamonds: 25 } }), 409, 'yetersiz');
  const r = await api('POST', '/api/me/diamonds/exchange', { token: ex.token, body: { diamonds: 20 } });
  ok(r, 'bozdur');
  assert.equal(await diamonds(ex), 3n);
  assert.equal(r.body.exchangedCoins, '4');
  const c0 = await coins(ex);
  assert.ok(c0 >= 4n);
});
