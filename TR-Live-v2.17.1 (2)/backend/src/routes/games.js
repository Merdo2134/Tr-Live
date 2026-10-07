import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { userLimit } from '../firewall.js';
import { fail, uuid } from '../http.js';
import * as ludo from '../ludo.js';
import { gameView, broadcastGame, openGameOfRoom, mutateGame, startGame } from '../services/games.js';

export const router = Router();
router.use(requireAuth);

async function assertMember(roomId, userId) {
  const m = (await query(`SELECT role FROM room_members WHERE room_id = $1 AND user_id = $2`, [roomId, userId])).rows[0];
  if (!m) throw fail('Önce odaya girin.', 403);
  return m;
}

router.get('/rooms/:roomId/game', async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  await assertMember(roomId, req.user.id);
  const g = await openGameOfRoom(roomId);
  res.json({ game: g ? await gameView(g.id) : null });
});

// Oyun kurma: oda sahibi / yardımcı sahip / moderatör. Ücretsizdir, Coin bahsi yoktur.
router.post('/rooms/:roomId/games', userLimit('game_create', 10, 60e3), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const m = await assertMember(roomId, req.user.id);
  if (!['owner', 'cohost', 'moderator'].includes(m.role)) throw fail('Oyunu yalnızca oda yetkilileri kurabilir.', 403);
  if ((req.body?.type ?? 'ludo') !== 'ludo') throw fail('Bu oyun henüz desteklenmiyor.');
  const id = await tx(async (c) => {
    await c.query(`SELECT id FROM rooms WHERE id = $1 AND is_active = TRUE FOR UPDATE`, [roomId]);
    if (await openGameOfRoom(roomId, (t, p) => c.query(t, p))) throw fail('Odada zaten açık bir oyun var.', 409);
    const g = (await c.query(`INSERT INTO room_games(room_id, created_by) VALUES($1,$2) RETURNING id`, [roomId, req.user.id])).rows[0];
    await c.query(`INSERT INTO room_game_players(game_id, user_id, seat) VALUES($1,$2,0)`, [g.id, req.user.id]);
    return g.id;
  });
  res.status(201).json({ game: await broadcastGame(id) });
});

async function gameInRoom(gameId, userId) {
  const g = (await query(`SELECT * FROM room_games WHERE id = $1`, [gameId])).rows[0];
  if (!g) throw fail('Oyun bulunamadı.', 404);
  await assertMember(g.room_id, userId);
  return g;
}

router.post('/games/:id/join', userLimit('game', 60, 60e3), async (req, res) => {
  const id = uuid(req.params.id, 'Oyun');
  const g = await gameInRoom(id, req.user.id);
  await tx(async (c) => {
    const row = (await c.query(`SELECT status FROM room_games WHERE id = $1 FOR UPDATE`, [id])).rows[0];
    if (row.status !== 'waiting') throw fail('Oyuna artık katılınamaz.', 409);
    const taken = (await c.query(`SELECT user_id, seat FROM room_game_players WHERE game_id = $1`, [id])).rows;
    if (taken.some((p) => p.user_id === req.user.id)) return;
    if (taken.length >= 4) throw fail('Oyun dolu.', 409);
    const free = [0, 1, 2, 3].find((s) => !taken.some((p) => p.seat === s));
    await c.query(`INSERT INTO room_game_players(game_id, user_id, seat) VALUES($1,$2,$3)`, [id, req.user.id, free]);
  });
  res.json({ game: await broadcastGame(g.id) });
});

router.post('/games/:id/leave', async (req, res) => {
  const id = uuid(req.params.id, 'Oyun');
  const g = await gameInRoom(id, req.user.id);
  if (g.status === 'waiting') {
    if (g.created_by === req.user.id) throw fail('Kurucu ayrılamaz; oyunu iptal edin.', 409);
    await query(`DELETE FROM room_game_players WHERE game_id = $1 AND user_id = $2`, [id, req.user.id]);
  } else if (g.status === 'playing') {
    await mutateGame(id, (state) => ({ state: ludo.forfeit(state, req.user.id) }));
  } else throw fail('Oyun zaten bitti.', 409);
  res.json({ game: await broadcastGame(id) });
});

router.post('/games/:id/start', async (req, res) => {
  const id = uuid(req.params.id, 'Oyun');
  await gameInRoom(id, req.user.id);
  await startGame(id, req.user.id);
  res.json({ game: await gameView(id) });
});

router.post('/games/:id/cancel', async (req, res) => {
  const id = uuid(req.params.id, 'Oyun');
  const g = await gameInRoom(id, req.user.id);
  const m = await assertMember(g.room_id, req.user.id);
  if (g.created_by !== req.user.id && !['owner', 'cohost'].includes(m.role)) throw fail('Bu işlem için yetkiniz yok.', 403);
  if (!['waiting', 'playing'].includes(g.status)) throw fail('Oyun zaten bitti.', 409);
  await query(`UPDATE room_games SET status = 'cancelled', finished_at = NOW() WHERE id = $1`, [id]);
  res.json({ game: await broadcastGame(id) });
});

router.post('/games/:id/roll', userLimit('game_move', 120, 60e3), async (req, res) => {
  const id = uuid(req.params.id, 'Oyun');
  await gameInRoom(id, req.user.id);
  const out = await mutateGame(id, (state) => {
    const seat = ludo.seatOfUser(state, req.user.id);
    if (seat === null) throw fail('Bu oyunda değilsiniz.', 403);
    try { return ludo.roll(ludo.markActive(state, seat), seat); } catch (e) { throw fail(e.message, 409); }
  });
  res.json({ dice: out.dice, skipped: out.skipped, legal: out.legal, game: await gameView(id) });
});

router.post('/games/:id/move', userLimit('game_move', 120, 60e3), async (req, res) => {
  const id = uuid(req.params.id, 'Oyun');
  await gameInRoom(id, req.user.id);
  const token = Number(req.body?.token);
  const out = await mutateGame(id, (state) => {
    const seat = ludo.seatOfUser(state, req.user.id);
    if (seat === null) throw fail('Bu oyunda değilsiniz.', 403);
    try { return ludo.move(ludo.markActive(state, seat), seat, token); } catch (e) { throw fail(e.message, 409); }
  });
  res.json({ captured: out.captured, extraTurn: out.extraTurn, won: out.won, game: await gameView(id) });
});
