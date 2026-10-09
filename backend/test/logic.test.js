import test from 'node:test';
import assert from 'node:assert/strict';
import { bigAmount, uuid, positiveInt, text, httpsUrl, isUuid } from '../src/http.js';
import { levelFromExp, expForLevel, levelInfo, levelFor, COIN_LEVEL_STEPS, familyLevelFor, familyCapacity, commissionOf, giftDisplayLevel } from '../src/levels.js';
import { distributeGift } from '../src/gifts_logic.js';
import { canManage } from '../src/room_permissions.js';
import { currentPeriod, periodRange, isPeriod } from '../src/periods.js';
import { publicUser, selfUser } from '../src/views.js';

const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
const C = '33333333-3333-4333-8333-333333333333';

test('bigAmount: geçerli ve geçersiz girdiler', () => {
  assert.equal(bigAmount('100'), 100n);
  assert.equal(bigAmount(5), 5n);
  assert.equal(bigAmount('-7', 'x', { allowNegative: true }), -7n);
  for (const bad of ['0x10', '1e3', '1.5', ' ', '', null, undefined, 1.5, 0, '0', '-5', '9999999999999999', NaN, {}]) {
    assert.throws(() => bigAmount(bad), undefined, `reddedilmeli: ${String(bad)}`);
  }
});

test('uuid / positiveInt / text / httpsUrl doğrulamaları', () => {
  assert.ok(isUuid(A));
  assert.throws(() => uuid('abc'));
  assert.throws(() => uuid(undefined));
  assert.equal(positiveInt('12', 'x'), 12);
  assert.throws(() => positiveInt(0, 'x'));
  assert.throws(() => positiveInt(10001, 'x', 10000));
  assert.throws(() => positiveInt(1.2, 'x'));
  assert.equal(text('  merhaba ', 'x', { max: 20 }), 'merhaba');
  assert.equal(text('', 'x', { max: 20 }), null);
  assert.throws(() => text('a', 'x', { min: 2 }));
  assert.throws(() => text('x'.repeat(21), 'x', { max: 20 }));
  assert.throws(() => text('   ', 'x', { required: true }));
  assert.equal(httpsUrl(null), null);
  assert.throws(() => httpsUrl('http://a.com/x.png'));
  assert.throws(() => httpsUrl('javascript:alert(1)'));
  assert.ok(httpsUrl('https://a.com/x.png').startsWith('https://'));
});

test('seviye hesapları', () => {
  assert.equal(levelFor(0, COIN_LEVEL_STEPS), 1);
  assert.equal(levelFor('999', COIN_LEVEL_STEPS), 1);
  assert.equal(levelFor('1000', COIN_LEVEL_STEPS), 2);
  assert.equal(levelFor('100000000', COIN_LEVEL_STEPS), 9);
  assert.equal(levelFor('999999999999', COIN_LEVEL_STEPS), 9);
  assert.equal(familyLevelFor(0), 1);
  assert.equal(familyLevelFor('10000000'), 5);
  assert.equal(familyCapacity(1), 30);
  assert.equal(familyCapacity(99), 200);
  assert.equal(giftDisplayLevel(999), 1);
  assert.equal(giftDisplayLevel(1000), 2);
  assert.equal(giftDisplayLevel(10000), 3);
});

test('komisyon: baz puan üzerinden aşağı yuvarlanır', () => {
  assert.equal(commissionOf(1000n, 1000), 100n);
  assert.equal(commissionOf(999n, 1000), 99n);
  assert.equal(commissionOf(1n, 1), 0n);
  assert.equal(commissionOf('5000', 10000), 5000n);
});

const members = [
  { user_id: A, microphone: true }, { user_id: B, microphone: true }, { user_id: C, microphone: false },
];

test('hediye dağıtımı: eşit dağıtım toplamı korur ve yalnızca mikrofondakilere gider', () => {
  for (const qty of [1, 2, 3, 7, 100]) {
    const r = distributeGift(members, qty, 'equal');
    assert.equal(r.reduce((s, x) => s + x.quantity, 0), qty);
    assert.ok(r.every((x) => x.userId !== C));
  }
  const two = distributeGift(members, 4, 'equal');
  assert.deepEqual(two.map((x) => x.quantity).sort(), [2, 2]);
});

test('hediye dağıtımı: rastgele toplamı korur; seçili yalnızca seçilenlere; kendine hediye mikrofonda mümkün', () => {
  const r = distributeGift(members, 50, 'random');
  assert.equal(r.reduce((s, x) => s + x.quantity, 0), 50);
  const sel = distributeGift(members, 3, 'selected', [A]);
  assert.deepEqual(sel, [{ userId: A, quantity: 3 }]); // A gönderen olsa bile kendisi alıcı olabilir
  assert.throws(() => distributeGift(members, 3, 'selected', [C]));
  assert.throws(() => distributeGift([{ user_id: C, microphone: false }], 1, 'equal'));
  assert.throws(() => distributeGift(members, 1, 'single'));
});

test('oda yetkileri', () => {
  assert.equal(canManage('owner', 'user', 'moderate'), true);
  assert.equal(canManage('moderator', 'user', 'moderate'), true);
  assert.equal(canManage('moderator', 'moderator', 'moderate'), false);
  assert.equal(canManage('moderator', 'cohost', 'moderate'), false);
  assert.equal(canManage('user', 'user', 'moderate'), false);
  assert.equal(canManage('cohost', 'owner', 'moderate'), false);
  assert.equal(canManage('owner', 'user', 'role', 'cohost'), true);
  assert.equal(canManage('owner', 'user', 'role', 'owner'), false);
  assert.equal(canManage('cohost', 'user', 'role', 'moderator'), true);
  assert.equal(canManage('cohost', 'user', 'role', 'cohost'), false);
  assert.equal(canManage('cohost', 'cohost', 'role', 'user'), false);
  assert.equal(canManage('moderator', 'user', 'role', 'moderator'), false);
});

test('dönemler (Türkiye saati)', () => {
  assert.equal(currentPeriod(new Date('2026-09-30T20:59:00Z')), '2026-09');
  assert.equal(currentPeriod(new Date('2026-09-30T21:00:00Z')), '2026-10'); // 00:00 TRT
  assert.ok(isPeriod('2026-09'));
  assert.ok(!isPeriod('2026-13'));
  assert.ok(!isPeriod('2026-9'));
  const r = periodRange('2026-12');
  assert.equal(r.start, '2026-11-30T21:00:00.000Z');
  assert.equal(r.end, '2026-12-31T21:00:00.000Z');
});

test('publicUser: bakiye sızdırmaz, gizli kullanıcıyı maskeler', () => {
  const row = {
    id: A, username: 'ali', display_name: 'Ali', avatar_url: 'https://x/a.png', is_hidden: false, coin_level: 3, gift_level: 2,
    coins: '999', diamonds: '888', wip_level: 4, wip_features: { nameColor: '#E5E4E2' },
  };
  const pub = publicUser(row, B);
  assert.equal(pub.coins, undefined);
  assert.equal(pub.diamonds, undefined);
  assert.equal(pub.displayName, 'Ali');
  assert.equal(pub.wipLevel, 4);
  assert.equal(pub.nameColor, '#E5E4E2');
  const hidden = publicUser({ ...row, is_hidden: true }, B);
  assert.equal(hidden.displayName, 'Gizli Kullanıcı');
  assert.equal(hidden.avatarUrl, null);
  assert.equal(hidden.wipLevel, null);
  assert.equal(publicUser({ ...row, is_hidden: true }, A).displayName, 'Ali'); // kendini görür
  assert.equal(selfUser({ ...row, total_sent_coins: '1', total_received_diamonds: '2' }).coins, '999');
});

test('160 kademeli seviye eğrisi', () => {
  assert.equal(levelFromExp(0), 1);
  assert.equal(levelFromExp(expForLevel(2) - 1n), 1);
  assert.equal(levelFromExp(expForLevel(2)), 2);
  assert.equal(levelFromExp(expForLevel(57)), 57);
  assert.equal(levelFromExp(expForLevel(160)), 160);
  assert.equal(levelFromExp('99999999999999999'), 160);
  const i = levelInfo(expForLevel(10) + 5n);
  assert.equal(i.level, 10);
  assert.equal(i.nextLevelExp, expForLevel(11).toString());
  assert.equal(levelInfo(expForLevel(160)).maxed, true);
});

test('yerleşik küfür filtresi hileleri yakalar, masum sözleri geçirir', async () => {
  const { containsBanned } = await import('../src/text_safety.js');
  for (const t of ['s1ktir git', 'a.m.k', 'siiiiktir', 'amına koyayım', 'orospu']) assert.equal(containsBanned(t, []), true, t);
  for (const t of ['selam nasılsın', 'sıkıntı var', 'pişmanlık', 'bitcoin', 'dickens', 'I got it', 'kitap']) assert.equal(containsBanned(t, []), false, t);
});
