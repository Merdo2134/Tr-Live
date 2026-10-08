import { query, tx } from '../database.js';
import { DAILY_TASKS, XP_PER_TASK, XP_PER_DAY, STREAK_DAYS, STREAK_COINS } from './rewards_config.js';

const TODAY = `(NOW() AT TIME ZONE 'Europe/Istanbul')::date`;

/** Görev ilerletir. Hata verirse ana işlemi bozmaz. */
export async function noteTask(userId, key, n = 1) {
  const def = DAILY_TASKS[key];
  if (!def || !userId) return;
  try {
    await tx(async (c) => {
      await c.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [userId]);
      const day = (await c.query(`SELECT ${TODAY} AS d`)).rows[0].d;
      const cur = (await c.query(`SELECT count, done FROM daily_progress WHERE user_id = $1 AND day = $2 AND task_key = $3`, [userId, day, key])).rows[0];
      if (cur?.done) return;
      const count = Math.min(def.target, (cur?.count ?? 0) + n);
      const done = count >= def.target;
      await c.query(
        `INSERT INTO daily_progress(user_id, day, task_key, count, done) VALUES($1,$2,$3,$4,$5)
         ON CONFLICT (user_id, day, task_key) DO UPDATE SET count = EXCLUDED.count, done = EXCLUDED.done`,
        [userId, day, key, count, done],
      );
      if (!done) return;
      let xp = XP_PER_TASK;
      const doneCount = (await c.query(`SELECT COUNT(*)::int AS n FROM daily_progress WHERE user_id = $1 AND day = $2 AND done`, [userId, day])).rows[0].n;
      if (doneCount >= Object.keys(DAILY_TASKS).length) {
        const s = (await c.query(`SELECT streak, last_day, ($2::date - last_day) AS gap FROM daily_streak WHERE user_id = $1`, [userId, day])).rows[0];
        const streak = s && s.gap === 1 ? s.streak + 1 : 1;
        if (streak >= STREAK_DAYS) {
          await c.query(`UPDATE users SET coins = coins + $2 WHERE id = $1`, [userId, String(STREAK_COINS)]);
          await c.query(
            `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, description) VALUES($1,'daily_bonus',$2,$3)`,
            [userId, String(STREAK_COINS), `${STREAK_DAYS} gün üst üste görev ödülü`],
          );
        } else xp += XP_PER_DAY;
        await c.query(
          `INSERT INTO daily_streak(user_id, streak, last_day) VALUES($1,$2,$3)
           ON CONFLICT (user_id) DO UPDATE SET streak = EXCLUDED.streak, last_day = EXCLUDED.last_day`,
          [userId, streak >= STREAK_DAYS ? 0 : streak, day],
        );
      }
      await c.query(`UPDATE users SET xp = xp + $2 WHERE id = $1`, [userId, xp]);
    });
  } catch (error) {
    console.error('Günlük görev hatası:', error.message);
  }
}

export async function dailyState(userId) {
  const day = (await query(`SELECT ${TODAY} AS d`)).rows[0].d;
  const prog = (await query(`SELECT task_key, count, done FROM daily_progress WHERE user_id = $1 AND day = $2`, [userId, day])).rows;
  const s = (await query(`SELECT streak, ($2::date - last_day) AS gap FROM daily_streak WHERE user_id = $1`, [userId, day])).rows[0];
  const xp = (await query(`SELECT xp FROM users WHERE id = $1`, [userId])).rows[0]?.xp ?? 0;
  // Dün tamamlandıysa seri sürer; bugün tamamlandıysa bugünü de içerir; daha eskiyse sıfırlanır.
  const streak = s && s.gap <= 1 ? s.streak : 0;
  return {
    xp: String(xp),
    streak,
    streakTarget: STREAK_DAYS,
    todayComplete: Boolean(s && s.gap === 0),
    streakCoins: STREAK_COINS,
    tasks: Object.entries(DAILY_TASKS).map(([key, d]) => {
      const p = prog.find((x) => x.task_key === key);
      return { key, label: d.label, target: d.target, count: p?.count ?? 0, done: Boolean(p?.done) };
    }),
  };
}
