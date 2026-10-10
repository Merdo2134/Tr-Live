import { query } from '../database.js';

// İlk kurulum / veritabanı taşıma kolaylığı: ADMIN_USERNAMES ortam değişkenindeki kullanıcı adları (virgülle ayrılmış)
// yönetici yapılır. Yalnızca sunucu sahibi (Render ortam değişkenleri) ayarlayabilir; listeden çıkarmak yetkiyi geri almaz.
const names = () => String(process.env.ADMIN_USERNAMES || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);

/** username verilirse yalnızca o kişi (listedeyse), verilmezse listedeki herkes. Yönetici yapılan varsa true. */
export async function promoteBootstrapAdmins(username) {
  const list = names();
  if (!list.length) return false;
  const target = username === undefined ? list : list.filter((n) => n === String(username).toLowerCase());
  if (!target.length) return false;
  const r = await query(
    `UPDATE users SET system_role = 'admin', updated_at = NOW()
     WHERE lower(username) = ANY($1::text[]) AND system_role <> 'admin' AND account_status = 'active' RETURNING username`,
    [target],
  );
  for (const u of r.rows) console.log(`Yönetici yapıldı (ADMIN_USERNAMES): ${u.username}`);
  return r.rowCount > 0;
}
