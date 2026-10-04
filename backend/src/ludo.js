// Ludo motoru: saf ve sunucu tarafından yönetilir (istemci yalnızca gösterir). Para/bahis YOKTUR.
//
// Konumlar (ilerleme, "progress"):  -1 = üs,  0 = kendi başlangıç karesi,  1..50 = ortak yol,
//                                   51..55 = ev sütunu,  56 = bitti.
// Ortak yol 52 karelidir; koltuk s için küresel kare = (s*13 + progress) % 52 (progress 0..50 iken).
export const SAFE_CELLS = new Set([0, 8, 13, 21, 26, 34, 39, 47]);
export const TURN_MS = 30000;
export const MAX_AUTO = 3;
export const COLORS = ['red', 'green', 'yellow', 'blue'];
export const FINISH = 56;

const clone = (o) => JSON.parse(JSON.stringify(o));

export const cellOf = (seat, progress) => (progress >= 0 && progress <= 50 ? (seat * 13 + progress) % 52 : null);

// 2 oyuncuda karşılıklı koltuklar (0,2); 3-4 oyuncuda sırayla.
export function seatsFor(count) {
  if (count === 2) return [0, 2];
  if (count === 3) return [0, 1, 2];
  if (count === 4) return [0, 1, 2, 3];
  throw new Error('Oyuncu sayısı 2-4 olmalı');
}

export function newGame(userIds, now = Date.now()) {
  if (userIds.length < 2 || userIds.length > 4) throw new Error('Oyuncu sayısı 2-4 olmalı');
  const seats = seatsFor(userIds.length);
  const players = userIds.map((userId, i) => ({ userId, seat: seats[i], auto: 0 }));
  const tokens = {};
  for (const p of players) tokens[p.seat] = [-1, -1, -1, -1];
  return {
    players, tokens, turn: players[0].seat, dice: null, sixes: 0,
    winnerSeat: null, deadline: now + TURN_MS, log: [], moves: 0,
  };
}

const playerOf = (st, seat) => st.players.find((p) => p.seat === seat);
export const seatOfUser = (st, userId) => st.players.find((p) => p.userId === userId)?.seat ?? null;

export function legalMoves(st, seat, dice) {
  if (dice == null) return [];
  const out = [];
  st.tokens[seat].forEach((p, i) => {
    if (p === FINISH) return;
    if (p === -1) { if (dice === 6) out.push(i); return; }
    if (p + dice <= FINISH) out.push(i);
  });
  return out;
}

function nextSeat(st, seat) {
  const order = st.players.map((p) => p.seat);
  return order[(order.indexOf(seat) + 1) % order.length];
}

function endTurn(st, now, keep = false) {
  st.dice = null;
  if (!keep) { st.turn = nextSeat(st, st.turn); st.sixes = 0; }
  st.deadline = now + TURN_MS;
}

export function roll(st0, seat, rng = Math.random, now = Date.now()) {
  const st = clone(st0);
  if (st.winnerSeat !== null) throw new Error('Oyun bitti');
  if (st.turn !== seat) throw new Error('Sıra sizde değil');
  if (st.dice !== null) throw new Error('Zar zaten atıldı');
  const dice = 1 + Math.floor(rng() * 6);
  st.dice = dice;
  st.moves += 1;
  st.sixes = dice === 6 ? st.sixes + 1 : 0;
  let skipped = false;
  if (st.sixes >= 3) {
    // Üst üste üç altı: hamle yok, sıra geçer.
    skipped = true;
    st.log.push({ seat, dice, event: 'three_sixes' });
    endTurn(st, now);
  } else if (!legalMoves(st, seat, dice).length) {
    skipped = true;
    st.log.push({ seat, dice, event: 'no_move' });
    endTurn(st, now);
  } else {
    st.deadline = now + TURN_MS;
  }
  st.log = st.log.slice(-20);
  return { state: st, dice, skipped, legal: skipped ? [] : legalMoves(st, seat, dice) };
}

export function move(st0, seat, token, now = Date.now()) {
  const st = clone(st0);
  if (st.winnerSeat !== null) throw new Error('Oyun bitti');
  if (st.turn !== seat) throw new Error('Sıra sizde değil');
  if (st.dice === null) throw new Error('Önce zar atın');
  if (!Number.isInteger(token) || !legalMoves(st, seat, st.dice).includes(token)) throw new Error('Geçersiz hamle');

  const dice = st.dice;
  const from = st.tokens[seat][token];
  const to = from === -1 ? 0 : from + dice;
  st.tokens[seat][token] = to;

  const captured = [];
  const cell = cellOf(seat, to);
  if (cell !== null && !SAFE_CELLS.has(cell)) {
    for (const p of st.players) {
      if (p.seat === seat) continue;
      st.tokens[p.seat].forEach((q, i) => {
        if (q >= 0 && q <= 50 && cellOf(p.seat, q) === cell) { st.tokens[p.seat][i] = -1; captured.push({ seat: p.seat, token: i }); }
      });
    }
  }
  const finishedToken = to === FINISH;
  st.moves += 1;
  st.log.push({ seat, dice, event: captured.length ? 'capture' : finishedToken ? 'finish' : 'move', token });
  st.log = st.log.slice(-20);

  if (st.tokens[seat].every((p) => p === FINISH)) {
    st.winnerSeat = seat;
    st.dice = null;
    st.deadline = null;
    return { state: st, captured, finished: true, extraTurn: false, won: true };
  }
  const extra = dice === 6 || captured.length > 0 || finishedToken;
  endTurn(st, now, extra);
  return { state: st, captured, finished: finishedToken, extraTurn: extra, won: false };
}

// Zaman aşımı / AFK: sıradaki oyuncu için otomatik oynar. MAX_AUTO kez üst üste otomatik oynarsa oyundan atılır.
export function pickAuto(st, seat) {
  const legal = legalMoves(st, seat, st.dice);
  if (!legal.length) return null;
  let best = legal[0]; let bestScore = -1;
  for (const i of legal) {
    const from = st.tokens[seat][i];
    const to = from === -1 ? 0 : from + st.dice;
    let score = to;
    if (to === FINISH) score += 1000;
    const cell = cellOf(seat, to);
    if (cell !== null && !SAFE_CELLS.has(cell)) {
      for (const p of st.players) if (p.seat !== seat) for (const q of st.tokens[p.seat]) if (q >= 0 && q <= 50 && cellOf(p.seat, q) === cell) score += 500;
    }
    if (from === -1) score += 100;
    if (score > bestScore) { best = i; bestScore = score; }
  }
  return best;
}

export function autoPlay(st0, rng = Math.random, now = Date.now()) {
  let st = clone(st0);
  const seat = st.turn;
  const pl = playerOf(st, seat);
  pl.auto += 1;
  if (pl.auto > MAX_AUTO) return { state: forfeit(st, pl.userId, now), forfeited: pl.userId };
  if (st.dice === null) {
    const r = roll(st, seat, rng, now);
    st = r.state;
    if (r.skipped || st.turn !== seat) return { state: st, forfeited: null };
  }
  const pick = pickAuto(st, seat);
  if (pick === null) { endTurn(st, now); return { state: st, forfeited: null }; }
  return { state: move(st, seat, pick, now).state, forfeited: null };
}

// Oyuncu hamle yaptığında AFK sayacı sıfırlanır.
export function markActive(st0, seat) {
  const st = clone(st0);
  const p = playerOf(st, seat);
  if (p) p.auto = 0;
  return st;
}

export function forfeit(st0, userId, now = Date.now()) {
  const st = clone(st0);
  const p = st.players.find((x) => x.userId === userId);
  if (!p) return st;
  const wasTurn = st.turn === p.seat;
  const next = wasTurn ? nextSeat(st, p.seat) : st.turn;
  st.players = st.players.filter((x) => x.userId !== userId);
  delete st.tokens[p.seat];
  st.log.push({ seat: p.seat, event: 'forfeit' });
  if (st.players.length === 1) {
    st.winnerSeat = st.players[0].seat;
    st.dice = null;
    st.deadline = null;
    return st;
  }
  if (wasTurn) { st.turn = next; st.dice = null; st.sixes = 0; st.deadline = now + TURN_MS; }
  return st;
}
