import { query, tx } from '../database.js';
import { hub } from '../realtime.js';
import * as ludo from '../ludo.js';
import { loadPublicRows } from './users.js';
import { publicUser } from '../views.js';
import { fail } from '../http.js';

export async function gameView(gameId, run = query) {
  const g = (await run(`SELECT * FROM room_games WHERE id = $1`, [gameId])).rows[0];
  if (!g) return null;
  const waiting = (await run(`SELECT user_id, seat FROM room_game_players WHERE game_id = $1 ORDER BY seat`, [gameId])).rows;
  const st = g.state && g.state.players ? g.state : null;
  const ids = st ? st.players.map((p) => p.userId) : waiting.map((p) => p.user_id);
  const users = new Map((await loadPublicRows(ids, run)).map((u) => [u.id, u]));
  const players = st
    ? st.players.map((p) => ({ user: publicUser(users.get(p.userId)), seat: p.seat, color: ludo.COLORS[p.seat], auto: p.auto }))
    : waiting.map((p) => ({ user: publicUser(users.get(p.user_id)), seat: p.seat, color: ludo.COLORS[p.seat], auto: 0 }));
  const turnSeat = st && g.status === 'playing' ? st.turn : null;
  return {
    id: g.id, roomId: g.room_id, type: g.game_type, status: g.status, createdBy: g.created_by, winnerId: g.winner_id,
    players,
    turnSeat,
    turnUserId: st && turnSeat !== null ? st.players.find((p) => p.seat === turnSeat)?.userId ?? null : null,
    dice: st ? st.dice : null,
    legal: st && g.status === 'playing' && st.dice !== null ? ludo.legalMoves(st, st.turn, st.dice) : [],
    tokens: st ? st.tokens : null,
    deadlineMs: st?.deadline ?? null,
    secondsLeft: st?.deadline ? Math.max(0, Math.ceil((st.deadline - Date.now()) / 1000)) : null,
    log: st ? st.log.slice(-5) : [],
  };
}

export async function broadcastGame(gameId) {
  const view = await gameView(gameId);
  if (view) hub.broadcastRoom(view.roomId, { type: 'room_game_state', game: view });
  return view;
}

export async function openGameOfRoom(roomId, run = query) {
  return (await run(`SELECT * FROM room_games WHERE room_id = $1 AND status IN ('waiting','playing')`, [roomId])).rows[0] || null;
}

// Kilitli satır üzerinde saf motoru çalıştırıp durumu yazar. fn(state, game) → { state, extra }.
export async function mutateGame(gameId, fn) {
  const out = await tx(async (c) => {
    const g = (await c.query(`SELECT * FROM room_games WHERE id = $1 FOR UPDATE`, [gameId])).rows[0];
    if (!g) throw fail('Oyun bulunamadı.', 404);
    if (g.status !== 'playing') throw fail('Oyun şu an oynanmıyor.', 409);
    const res = fn(g.state, g);
    const st = res.state;
    if (st.winnerSeat !== null) {
      const winner = st.players.find((p) => p.seat === st.winnerSeat);
      await c.query(`UPDATE room_games SET state = $2, status = 'finished', finished_at = NOW(), winner_id = $3 WHERE id = $1`, [gameId, JSON.stringify(st), winner?.userId ?? null]);
    } else {
      await c.query(`UPDATE room_games SET state = $2 WHERE id = $1`, [gameId, JSON.stringify(st)]);
    }
    return res;
  });
  await broadcastGame(gameId);
  return out;
}

export async function startGame(gameId, requesterId) {
  const out = await tx(async (c) => {
    const g = (await c.query(`SELECT * FROM room_games WHERE id = $1 FOR UPDATE`, [gameId])).rows[0];
    if (!g || g.status !== 'waiting') throw fail('Oyun başlatılamaz.', 409);
    if (g.created_by !== requesterId) throw fail('Oyunu yalnızca kuran başlatabilir.', 403);
    const ps = (await c.query(`SELECT user_id FROM room_game_players WHERE game_id = $1 ORDER BY seat`, [gameId])).rows;
    if (ps.length < 2) throw fail('En az 2 oyuncu gerekir.', 409);
    const st = ludo.newGame(ps.map((p) => p.user_id));
    await c.query(`UPDATE room_games SET status = 'playing', state = $2, started_at = NOW() WHERE id = $1`, [gameId, JSON.stringify(st)]);
    return st;
  });
  await broadcastGame(gameId);
  return out;
}

// Oyuncu odadan çıkınca: bekleyen oyunda listeden silinir, oynanan oyunda oyundan elenir.
export async function forfeitUserInRoom(userId, roomId) {
  const g = await openGameOfRoom(roomId);
  if (!g) return;
  if (g.status === 'waiting') {
    if (g.created_by === userId) { await cancelRoomGame(roomId); return; }
    await query(`DELETE FROM room_game_players WHERE game_id = $1 AND user_id = $2`, [g.id, userId]);
    await broadcastGame(g.id);
    return;
  }
  if (!g.state?.players?.some((p) => p.userId === userId)) return;
  try {
    await mutateGame(g.id, (state) => ({ state: ludo.forfeit(state, userId) }));
  } catch (error) {
    if (error.status !== 409) throw error;
  }
}

export async function cancelRoomGame(roomId) {
  const r = await query(
    `UPDATE room_games SET status = 'cancelled', finished_at = NOW() WHERE room_id = $1 AND status IN ('waiting','playing') RETURNING id`, [roomId],
  );
  for (const g of r.rows) await broadcastGame(g.id);
}

// Süresi dolan sıralar için otomatik oyun (AFK koruması).
export function startGameTicker() {
  const timer = setInterval(async () => {
    try {
      const due = await query(
        `SELECT id FROM room_games WHERE status = 'playing' AND (state->>'deadline')::bigint <= $1`, [Date.now()],
      );
      for (const g of due.rows) {
        try { await mutateGame(g.id, (state) => ludo.autoPlay(state)); } catch (e) { if (e.status !== 409) console.error('Oyun otomatik hamle hatası:', e.message); }
      }
    } catch (error) {
      console.error('Oyun zamanlayıcı hatası:', error.message);
    }
  }, 2000);
  timer.unref();
  return timer;
}
