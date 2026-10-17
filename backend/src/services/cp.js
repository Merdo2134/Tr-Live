import { query } from '../database.js';

// İki kişi arasındaki yakınlık (CP) puanı. Çift her zaman (küçük id, büyük id) sırasıyla saklanır.
export const pairOf = (x, y) => (x < y ? [x, y] : [y, x]);

export const CP_MSG_EXP = 10; // özel mesaj başına
export const CP_MSG_DAILY = 10; // günde en fazla bu kadar mesaj sayılır (100 exp)
export const CP_GIFT_MULTIPLIER_BPS = 15000; // CP hediyesi 1,5 kat
const TODAY = `(NOW() AT TIME ZONE 'Europe/Istanbul')::date`;

/** Hediye: Coin değeri kadar exp (CP hediyesinde 1,5 kat). Kendine hediye sayılmaz. [run] işlem içinden çağrılabilir. */
export async function addGiftExp(run, senderId, receiverId, coinAmount, cpGift) {
  if (!senderId || !receiverId || senderId === receiverId) return;
  let exp = BigInt(coinAmount);
  if (cpGift) exp = (exp * BigInt(CP_GIFT_MULTIPLIER_BPS)) / 10000n;
  if (exp <= 0n) return;
  const [a, b] = pairOf(senderId, receiverId);
  await run(
    `INSERT INTO cp_pairs(user_a, user_b, exp) VALUES($1,$2,$3)
     ON CONFLICT (user_a, user_b) DO UPDATE SET exp = cp_pairs.exp + EXCLUDED.exp, updated_at = NOW()`,
    [a, b, exp.toString()],
  );
}

/** Özel mesaj: çift başına günde ilk 10 mesaj 10'ar exp (iki yönün toplamı). */
export async function addMessageExp(senderId, receiverId, run = query) {
  if (!senderId || !receiverId || senderId === receiverId) return;
  const [a, b] = pairOf(senderId, receiverId);
  await run(
    `INSERT INTO cp_pairs(user_a, user_b, exp, msg_day, msg_count) VALUES($1,$2,$3,${TODAY},1)
     ON CONFLICT (user_a, user_b) DO UPDATE SET
       exp = cp_pairs.exp + CASE WHEN cp_pairs.msg_day IS DISTINCT FROM ${TODAY} OR cp_pairs.msg_count < $4 THEN $3 ELSE 0 END,
       msg_count = CASE WHEN cp_pairs.msg_day IS DISTINCT FROM ${TODAY} THEN 1 ELSE LEAST(cp_pairs.msg_count + 1, $4) END,
       msg_day = ${TODAY}, updated_at = NOW()`,
    [a, b, CP_MSG_EXP, CP_MSG_DAILY],
  );
}
