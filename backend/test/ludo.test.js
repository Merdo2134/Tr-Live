import test from 'node:test';
import assert from 'node:assert/strict';
import {
  newGame, roll, move, legalMoves, cellOf, SAFE_CELLS, forfeit, autoPlay, pickAuto, FINISH, TURN_MS, MAX_AUTO, seatOfUser, markActive,
} from '../src/ludo.js';

const seq = (...vals) => { let i = 0; return () => (vals[i++ % vals.length] - 1) / 6 + 0.001; }; // zar = verilen değer
const U = ['a', 'b', 'c', 'd'];

test('2 oyuncuda koltuklar karşılıklıdır, 4 oyuncuda sıralıdır', () => {
  assert.deepEqual(newGame(['a', 'b'], 0).players.map((p) => p.seat), [0, 2]);
  assert.deepEqual(newGame(U, 0).players.map((p) => p.seat), [0, 1, 2, 3]);
  assert.throws(() => newGame(['a'], 0));
});

test('üsten çıkmak için 6 gerekir', () => {
  let st = newGame(['a', 'b'], 0);
  const r = roll(st, 0, seq(3), 0);
  assert.equal(r.skipped, true);
  assert.equal(r.state.turn, 2);
  st = newGame(['a', 'b'], 0);
  const r6 = roll(st, 0, seq(6), 0);
  assert.deepEqual(r6.legal, [0, 1, 2, 3]);
  const m = move(r6.state, 0, 0, 0);
  assert.equal(m.state.tokens[0][0], 0);
  assert.equal(m.extraTurn, true);
  assert.equal(m.state.turn, 0);
});

test('sıra kontrolü ve çift zar engeli', () => {
  const st = newGame(['a', 'b'], 0);
  assert.throws(() => roll(st, 2, seq(6), 0), /Sıra/);
  const r = roll(st, 0, seq(6), 0).state;
  assert.throws(() => roll(r, 0, seq(6), 0), /zaten/);
  assert.throws(() => move(newGame(['a', 'b'], 0), 0, 0, 0), /zar/);
  assert.throws(() => move(r, 0, 9, 0), /Geçersiz/);
});

test('üst üste üç altı sırayı geçirir', () => {
  let st = newGame(['a', 'b'], 0);
  st = move(roll(st, 0, seq(6), 0).state, 0, 0, 0).state; // 1. altı
  st = move(roll(st, 0, seq(6), 0).state, 0, 0, 0).state; // 2. altı (0 → 6)
  const r = roll(st, 0, seq(6), 0); // 3. altı
  assert.equal(r.skipped, true);
  assert.equal(r.state.turn, 2);
});

test('rakip taşı yakalanır, güvenli karede yakalanmaz', () => {
  const st = newGame(['a', 'b'], 0);
  // Koltuk 0 taşı ilerleme 5 → küresel 5. Koltuk 2 taşı ilerleme 31 → (26+31)%52 = 5.
  st.tokens[0] = [4, -1, -1, -1];
  st.tokens[2] = [31, -1, -1, -1];
  st.dice = 1;
  const m = move(st, 0, 0, 0);
  assert.equal(m.captured.length, 1);
  assert.equal(m.state.tokens[2][0], -1);
  assert.equal(m.extraTurn, true);
  // Güvenli kare (küresel 8): ilerleme 8, rakip 34
  const s2 = newGame(['a', 'b'], 0);
  s2.tokens[0] = [7, -1, -1, -1]; s2.tokens[2] = [34, -1, -1, -1]; s2.dice = 1;
  assert.ok(SAFE_CELLS.has(cellOf(0, 8)));
  const m2 = move(s2, 0, 0, 0);
  assert.equal(m2.captured.length, 0);
  assert.equal(m2.state.tokens[2][0], 34);
});

test('bitişe tam sayı gerekir; bitirince ekstra tur', () => {
  const st = newGame(['a', 'b'], 0);
  st.tokens[0] = [54, 56, 56, 56]; st.dice = 3;
  assert.deepEqual(legalMoves(st, 0, 3), []);
  assert.deepEqual(legalMoves(st, 0, 2), [0]);
  st.dice = 2;
  const m = move(st, 0, 0, 0);
  assert.equal(m.won, true);
  assert.equal(m.state.winnerSeat, 0);
});

test('hamle yoksa sıra otomatik geçer', () => {
  const st = newGame(['a', 'b'], 0);
  st.tokens[0] = [55, 56, 56, 56];
  const r = roll(st, 0, seq(4), 0);
  assert.equal(r.skipped, true);
  assert.equal(r.state.turn, 2);
});

test('AFK: otomatik oynar, MAX_AUTO sonrası elenir', () => {
  let st = newGame(['a', 'b', 'c'], 0);
  let guard = 0;
  while (st.players.some((p) => p.userId === 'a') && guard++ < 200) {
    if (st.turn === 0) {
      const before = st.players.find((p) => p.userId === 'a').auto;
      const r = autoPlay(st, seq(6, 2, 6, 3), 1000);
      st = r.state;
      if (r.forfeited) { assert.equal(r.forfeited, 'a'); assert.equal(before, MAX_AUTO); break; }
    } else {
      st.turn = 0; st.dice = null;
    }
  }
  assert.ok(!st.players.some((p) => p.userId === 'a'));
  assert.equal(st.players.length, 2);
});

test('markActive AFK sayacını sıfırlar', () => {
  let st = newGame(['a', 'b'], 0);
  st.players[0].auto = 2;
  st = markActive(st, 0);
  assert.equal(st.players[0].auto, 0);
});

test('forfeit: iki kişiden biri çıkarsa diğeri kazanır', () => {
  const st = forfeit(newGame(['a', 'b'], 0), 'a', 0);
  assert.equal(st.winnerSeat, 2);
  const s3 = forfeit(newGame(['a', 'b', 'c'], 0), 'a', 5);
  assert.equal(s3.winnerSeat, null);
  assert.equal(s3.turn, 1);
  assert.equal(s3.deadline, 5 + TURN_MS);
});

test('pickAuto bitirmeyi yakalamaya, yakalamayı çıkışa tercih eder', () => {
  const st = newGame(['a', 'b'], 0);
  st.tokens[0] = [52, 10, -1, -1]; st.dice = 4;
  assert.equal(pickAuto(st, 0), 0);
  const s2 = newGame(['a', 'b'], 0);
  s2.tokens[0] = [4, -1, -1, -1]; s2.tokens[2] = [31, -1, -1, -1]; s2.dice = 1;
  assert.equal(pickAuto(s2, 0), 0);
});

test('seatOfUser', () => {
  const st = newGame(['a', 'b'], 0);
  assert.equal(seatOfUser(st, 'b'), 2);
  assert.equal(seatOfUser(st, 'x'), null);
});

test('4 oyunculu tam oyun simülasyonu bir kazanan ile biter', () => {
  let seed = 12345;
  const rng = () => { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; };
  let st = newGame(U, 0);
  let steps = 0;
  while (st.winnerSeat === null && steps++ < 20000) {
    const seat = st.turn;
    const r = roll(st, seat, rng, steps);
    st = r.state;
    if (!r.skipped) {
      const pick = pickAuto(st, seat);
      st = move(st, seat, pick, steps).state;
    }
    for (const sSeat of Object.keys(st.tokens)) for (const p of st.tokens[sSeat]) assert.ok(p >= -1 && p <= FINISH);
  }
  assert.notEqual(st.winnerSeat, null, 'oyun bitmeli');
  assert.ok(st.tokens[st.winnerSeat].every((p) => p === FINISH));
});
