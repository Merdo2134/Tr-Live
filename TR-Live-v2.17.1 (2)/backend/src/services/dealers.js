import { fail } from '../http.js';

// Bayi bakiyesinden kullanıcıya Coin satışı. Çağıran, bir transaction (client "c") içinde olmalıdır.
export async function dealerSell(c, { dealerId, userId, coins, actorId, description }) {
  const dealer = (await c.query(`SELECT * FROM dealer_accounts WHERE id = $1 AND is_active = TRUE FOR UPDATE`, [dealerId])).rows[0];
  if (!dealer) throw fail('Bayi bulunamadı.', 404);
  const user = (await c.query(`SELECT coins FROM users WHERE id = $1 AND account_status = 'active' FOR UPDATE`, [userId])).rows[0];
  if (!user) throw fail('Kullanıcı bulunamadı.', 404);
  const balance = BigInt(dealer.coin_balance);
  if (balance < coins) throw fail('Bayinin Coin bakiyesi yetersiz.');
  const before = BigInt(user.coins);
  const after = before + coins;
  await c.query(`UPDATE dealer_accounts SET coin_balance = coin_balance - $1 WHERE id = $2`, [coins.toString(), dealer.id]);
  await c.query(`UPDATE users SET coins = $1, updated_at = NOW() WHERE id = $2`, [after.toString(), userId]);
  await c.query(
    `INSERT INTO dealer_transactions(dealer_id, admin_id, user_id, type, coin_amount, description) VALUES($1,$2,$3,'sale',$4,$5)`,
    [dealer.id, actorId, userId, coins.toString(), description || 'Bayi kullanıcı Coin satışı'],
  );
  await c.query(
    `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, reference_id, description) VALUES($1,'dealer_credit',$2,$3,$4)`,
    [userId, coins.toString(), dealer.id, `Bayi Coin yüklemesi (${dealer.name})`],
  );
  await c.query(
    `INSERT INTO financial_audit_logs(admin_id, user_id, action, reference_type, reference_id, amount_coins, balance_before, balance_after, metadata)
     VALUES($1,$2,'dealer_sale','dealer',$3,$4,$5,$6,$7)`,
    [actorId, userId, dealer.id, coins.toString(), before.toString(), after.toString(), JSON.stringify({ dealerName: dealer.name })],
  );
  return { dealerBalance: (balance - coins).toString(), userBalance: after.toString() };
}
