import { query, tx } from '../database.js';
import { hub } from '../realtime.js';
import { decideWinner, remainingSeconds, PK_INVITE_TTL_SECONDS } from '../pk_logic.js';
import { loadPublicRows } from './users.js';
import { publicUser } from '../views.js';
import { nonOverlapping } from '../ticker.js';

const OPEN = `('pending','active')`;

export async function pkView(battleId, run = query) {
  const b = (await run(`SELECT * FROM pk_battles WHERE id = $1`, [battleId])).rows[0];
  if (!b) return null;
  const rooms = (await run(`SELECT id, name FROM rooms WHERE id = ANY($1::uuid[])`, [[b.room_a, b.room_b]])).rows;
  const nameOf = (id) => rooms.find((r) => r.id === id)?.name ?? '';
  const users = new Map((await loadPublicRows([b.host_a, b.host_b], run)).map((u) => [u.id, u]));
  const sup = (await run(
    `SELECT room_id, user_id, coins FROM pk_supporters WHERE battle_id = $1 ORDER BY coins DESC LIMIT 20`, [battleId],
  )).rows;
  const top = async (roomId) => {
    const rows = sup.filter((x) => x.room_id === roomId).slice(0, 3);
    const u = new Map((await loadPublicRows(rows.map((x) => x.user_id), run)).map((x) => [x.id, x]));
    return rows.map((x) => ({ user: publicUser(u.get(x.user_id)), coins: String(x.coins) }));
  };
  return {
    id: b.id, status: b.status, durationSeconds: b.duration_seconds,
    remainingSeconds: b.status === 'active' ? remainingSeconds(b.ends_at) : 0,
    startedAt: b.started_at, endsAt: b.ends_at,
    a: { roomId: b.room_a, roomName: nameOf(b.room_a), host: publicUser(users.get(b.host_a)), score: String(b.score_a), top: await top(b.room_a) },
    b: { roomId: b.room_b, roomName: nameOf(b.room_b), host: publicUser(users.get(b.host_b)), score: String(b.score_b), top: await top(b.room_b) },
    winnerRoomId: b.winner_room,
    result: b.status === 'finished' ? (b.winner_room === null ? 'draw' : b.winner_room === b.room_a ? 'a' : 'b') : null,
  };
}

export async function broadcastPk(battleId) {
  const view = await pkView(battleId);
  if (!view) return null;
  const payload = { type: 'pk_state', pk: view };
  hub.broadcastRoom(view.a.roomId, payload);
  hub.broadcastRoom(view.b.roomId, payload);
  return view;
}

export async function activePkOfRoom(roomId, run = query) {
  const r = await run(`SELECT id FROM pk_battles WHERE (room_a = $1 OR room_b = $1) AND status IN ${OPEN} ORDER BY created_at DESC LIMIT 1`, [roomId]);
  return r.rows[0]?.id ?? null;
}

// Süresi dolan karşılaşmayı bitirir; kazananı belirler.
export async function finishPk(battleId) {
  const done = await tx(async (c) => {
    const b = (await c.query(`SELECT * FROM pk_battles WHERE id = $1 AND status = 'active' FOR UPDATE`, [battleId])).rows[0];
    if (!b) return false;
    const w = decideWinner(b.score_a, b.score_b);
    await c.query(
      `UPDATE pk_battles SET status = 'finished', finished_at = NOW(), winner_room = $2 WHERE id = $1`,
      [battleId, w === 'a' ? b.room_a : w === 'b' ? b.room_b : null],
    );
    return true;
  });
  if (done) await broadcastPk(battleId);
  return done;
}

// Oda kapanırken: bekleyen davet iptal, süren karşılaşma o anki skorla biter.
export async function endPkForRoom(roomId) {
  const r = await query(`SELECT id, status FROM pk_battles WHERE (room_a = $1 OR room_b = $1) AND status IN ${OPEN}`, [roomId]);
  for (const b of r.rows) {
    if (b.status === 'active') await finishPk(b.id);
    else {
      await query(`UPDATE pk_battles SET status = 'cancelled', finished_at = NOW() WHERE id = $1 AND status = 'pending'`, [b.id]);
      await broadcastPk(b.id);
    }
  }
}

// Hediye işlemi içinde çağrılır (aynı transaction). Kendine hediye puan getirmez; yalnızca oda sahibine (ev sahibi) gelen hediyeler sayılır.
export async function scorePk(c, roomId, receiverId, senderId, coinAmount) {
  if (receiverId === senderId) return null;
  const b = (await c.query(
    `SELECT id, room_a, room_b, host_a, host_b FROM pk_battles
     WHERE status = 'active' AND ends_at > NOW() AND (room_a = $1 OR room_b = $1) FOR UPDATE`, [roomId],
  )).rows[0];
  if (!b) return null;
  const side = b.room_a === roomId ? 'a' : 'b';
  const host = side === 'a' ? b.host_a : b.host_b;
  if (host !== receiverId) return null;
  await c.query(`UPDATE pk_battles SET score_${side} = score_${side} + $2 WHERE id = $1`, [b.id, coinAmount.toString()]);
  await c.query(
    `INSERT INTO pk_supporters(battle_id, room_id, user_id, coins) VALUES($1,$2,$3,$4)
     ON CONFLICT (battle_id, user_id) DO UPDATE SET coins = pk_supporters.coins + EXCLUDED.coins`,
    [b.id, roomId, senderId, coinAmount.toString()],
  );
  return b.id;
}

export function startPkTicker() {
  const timer = setInterval(nonOverlapping(async () => {
    try {
      const due = await query(`SELECT id FROM pk_battles WHERE status = 'active' AND ends_at <= NOW()`);
      for (const b of due.rows) await finishPk(b.id);
      const stale = await query(
        `UPDATE pk_battles SET status = 'cancelled', finished_at = NOW()
         WHERE status = 'pending' AND created_at < NOW() - ($1::int * INTERVAL '1 second') RETURNING id`, [PK_INVITE_TTL_SECONDS],
      );
      for (const b of stale.rows) await broadcastPk(b.id);
      // Canlı karşılaşmalarda süre göstergesini senkron tutmak için hafif bir yayın.
      const live = await query(`SELECT id FROM pk_battles WHERE status = 'active'`);
      for (const b of live.rows) {
        const v = await pkView(b.id);
        if (v) {
          const msg = { type: 'pk_tick', pkId: v.id, remainingSeconds: v.remainingSeconds, scoreA: v.a.score, scoreB: v.b.score };
          hub.broadcastRoom(v.a.roomId, msg); hub.broadcastRoom(v.b.roomId, msg);
        }
      }
    } catch (error) {
      console.error('PK zamanlayıcı hatası:', error.message);
    }
  }), 2000);
  timer.unref();
  return timer;
}
