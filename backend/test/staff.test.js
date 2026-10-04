import test from 'node:test';
import assert from 'node:assert/strict';
import { supportMayCall, banEnd, banExpired, banMessage, mayActOnUser } from '../src/staff_logic.js';
import { canManage } from '../src/room_permissions.js';

test('yardımcı admin yalnızca dar yetkilere erişir', () => {
  assert.ok(supportMayCall('GET', '/users'));
  assert.ok(supportMayCall('POST', '/users/abc/ban'));
  assert.ok(supportMayCall('POST', '/users/abc/unban'));
  assert.ok(supportMayCall('POST', '/users/abc/display-name'));
  assert.ok(supportMayCall('POST', '/users/abc/avatar'));
  for (const [m, p] of [['POST', '/users/abc/coins'], ['POST', '/users/abc/wip'], ['POST', '/users/abc/staff-role'], ['GET', '/staff'],
    ['POST', '/gifts'], ['PUT', '/agency-config'], ['POST', '/payouts/close'], ['GET', '/finance/audit'], ['POST', '/security/blocks'],
    ['POST', '/users/abc/kyc'], ['POST', '/dealers']]) assert.equal(supportMayCall(m, p), false, `${m} ${p}`);
});

test('ban süresi', () => {
  const now = new Date('2026-10-04T10:00:00Z');
  assert.equal(banEnd(null, now), null);
  assert.equal(banEnd(0, now), null);
  assert.equal(banEnd(24, now).toISOString(), '2026-10-05T10:00:00.000Z');
  assert.equal(banEnd(-1, now), undefined);
  assert.equal(banEnd('abc', now), undefined);
  assert.equal(banEnd(24 * 400, now), undefined);
});

test('süresi dolan ban', () => {
  const now = new Date('2026-10-04T10:00:00Z');
  assert.equal(banExpired({ account_status: 'banned', banned_until: '2026-10-04T09:00:00Z' }, now), true);
  assert.equal(banExpired({ account_status: 'banned', banned_until: '2026-10-04T11:00:00Z' }, now), false);
  assert.equal(banExpired({ account_status: 'banned', banned_until: null }, now), false);
  assert.equal(banExpired({ account_status: 'active', banned_until: null }, now), false);
  assert.match(banMessage({ banned_until: '2026-10-04T11:00:00Z', ban_reason: 'spam' }), /14:00.*spam/);
});

test('yardımcı admin yöneticiyi ve diğer yardımcıyı yönetemez', () => {
  assert.equal(mayActOnUser('support', 'user'), true);
  assert.equal(mayActOnUser('support', 'support'), false);
  assert.equal(mayActOnUser('support', 'admin'), false);
  assert.equal(mayActOnUser('admin', 'support'), true);
  assert.equal(mayActOnUser('user', 'user'), false);
});

test('moderatör yetkileri oda sahibine dokunamaz, normal kullanıcıya uygulanır', () => {
  assert.equal(canManage('moderator', 'user', 'moderate'), true);
  assert.equal(canManage('moderator', 'moderator', 'moderate'), false);
  assert.equal(canManage('moderator', 'owner', 'moderate'), false);
  assert.equal(canManage('moderator', 'user', 'role', 'moderator'), false); // moderatör atayamaz
  assert.equal(canManage('owner', 'user', 'role', 'moderator'), true);
  assert.equal(canManage('user', 'user', 'moderate'), false);
});
