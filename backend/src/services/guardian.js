// Koruyucu: bir kullanıcı Coin ile başka birinin koruyucusu olur. Koruyucunun o kişiye gönderdiği hediyeler
// (1 Coin = 1 puan) koruyucu puanını artırır. Her Pazartesi 00:00'da (İstanbul) bir önceki hafta hiç hediye
// göndermeyen koruyucuların puanı düşer: 250 ve üstü ise %20, altındaysa 50; sıfıra inince koruyuculuk biter.
// Koruyucu olunan ilk hafta (o hafta açılan koruyuculuk) düşüşten muaftır.
import { tx } from '../database.js';

export const GUARDIAN_COST = 3000n; // Koruyucu kartı (Coin)
export const GUARDIAN_LIST_LIMIT = 50;

const WEEK_START = `((date_trunc('week', NOW() AT TIME ZONE 'Europe/Istanbul')) AT TIME ZONE 'Europe/Istanbul')`;

/** Hediye: gönderen alıcının koruyucusuysa Coin kadar puan. [run] hediye işleminin içinden çağrılır. */
export async function addGuardianPoints(run, senderId, receiverId, coinAmount) {
  if (!senderId || !receiverId || senderId === receiverId) return;
  const amount = BigInt(coinAmount);
  if (amount <= 0n) return;
  await run(
    `UPDATE guardians SET points = points + $3, last_gift_at = NOW(), updated_at = NOW()
     WHERE owner_id = $1 AND guardian_id = $2`,
    [receiverId, senderId, amount.toString()],
  );
}

/** Bu haftanın düşüşü yapılmadıysa yapar (her hafta bir kez; birden çok sunucu aynı anda çalışsa da tek sefer). */
export async function runGuardianDecay() {
  return tx(async (c) => {
    const ins = await c.query(
      `INSERT INTO guardian_decay_runs(week_start) VALUES (${WEEK_START}) ON CONFLICT (week_start) DO NOTHING RETURNING week_start`,
    );
    if (!ins.rowCount) return 0;
    const week = ins.rows[0].week_start; // bu haftanın başı; değerlendirilen hafta bir önceki hafta
    // Hediye işlemleriyle kilitlenme olmasın: düşecek satırlar önce sabit sırayla kilitlenir.
    await c.query(
      `SELECT 1 FROM guardians WHERE created_at < $1::timestamptz - INTERVAL '7 days'
         AND (last_gift_at IS NULL OR last_gift_at < $1::timestamptz - INTERVAL '7 days')
       ORDER BY owner_id, guardian_id FOR UPDATE`,
      [week],
    );
    // Önceki hafta hediye göndermeyen, o haftadan önce koruyucu olmuş olanlar.
    const r = await c.query(
      `UPDATE guardians SET
         points = GREATEST(0, CASE WHEN points >= 250 THEN points - (points * 20) / 100 ELSE points - 50 END),
         updated_at = NOW()
       WHERE created_at < $1::timestamptz - INTERVAL '7 days'
         AND (last_gift_at IS NULL OR last_gift_at < $1::timestamptz - INTERVAL '7 days')
       RETURNING owner_id, guardian_id, points`,
      [week],
    );
    await c.query(`DELETE FROM guardians WHERE points <= 0 AND created_at < $1::timestamptz - INTERVAL '7 days'`, [week]);
    return r.rowCount;
  });
}

export function startGuardianTicker() {
  const run = () => runGuardianDecay().then((n) => { if (n) console.log(`[koruyucu] haftalık düşüş: ${n} kayıt`); })
    .catch((e) => console.error('[koruyucu] düşüş:', e.message));
  setTimeout(run, 30e3).unref();
  const t = setInterval(run, 10 * 60e3);
  t.unref();
  return t;
}
