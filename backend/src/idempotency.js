import { query } from './database.js';
import { fail } from './http.js';

const KEY_RE = /^[A-Za-z0-9_-]{16,64}$/;

/**
 * Para işlemleri için tekrar koruması. İstemci "Idempotency-Key" başlığı gönderirse:
 *  - Anahtar ilk kez geliyorsa işlem yapılır, başarılı yanıt saklanır.
 *  - Aynı anahtar tekrar gelirse işlem YAPILMAZ, saklanan yanıt döner (Idempotent-Replay: true).
 *  - İlk istek hâlâ sürüyorsa 409.
 *  - İşlem hata verirse anahtar silinir; aynı anahtarla tekrar denenebilir.
 * Başlık yoksa davranış eskisi gibidir (eski uygulama sürümleri).
 * requireAuth'tan SONRA kullanılır.
 */
export function idempotent(endpoint) {
  return async (req, res, next) => {
    const key = req.get('Idempotency-Key');
    if (!key) return next();
    if (!KEY_RE.test(key)) throw fail('Geçersiz işlem anahtarı.');
    const userId = req.user.id;
    const ins = await query(
      `INSERT INTO idempotency_keys(user_id, key, endpoint) VALUES($1,$2,$3) ON CONFLICT DO NOTHING RETURNING key`,
      [userId, key, endpoint],
    );
    if (!ins.rowCount) {
      const row = (await query(`SELECT endpoint, status_code, response FROM idempotency_keys WHERE user_id = $1 AND key = $2`, [userId, key])).rows[0];
      if (!row) throw fail('İşlem şu an tamamlanıyor. Lütfen tekrar deneyin.', 409);
      if (row.endpoint !== endpoint) throw fail('İşlem anahtarı başka bir işlemde kullanılmış.', 422);
      if (row.status_code == null) throw fail('Bu işlem hâlâ sürüyor veya sonucu alınamadı. Tekrar denemeden önce bakiyenizi kontrol edin.', 409);
      res.set('Idempotent-Replay', 'true');
      return res.status(row.status_code).json(row.response);
    }
    // Yanıt gönderilmeden önce saklanır: hemen ardından gelen tekrar isteği "sürüyor" yerine aynı sonucu alsın.
    const send = res.json.bind(res);
    res.json = (body) => {
      const code = res.statusCode;
      const ok = code >= 200 && code < 300;
      const store = ok
        ? query(`UPDATE idempotency_keys SET status_code = $3, response = $4 WHERE user_id = $1 AND key = $2`, [userId, key, code, JSON.stringify(body ?? null)])
        : query(`DELETE FROM idempotency_keys WHERE user_id = $1 AND key = $2`, [userId, key]);
      store.catch((e) => console.error('İşlem anahtarı kaydedilemedi:', e.message)).finally(() => send(body));
      return res;
    };
    next();
  };
}

/** Bir günden eski anahtarlar silinir (zamanlayıcıdan çağrılır). */
export async function pruneIdempotencyKeys() {
  const r = await query(`DELETE FROM idempotency_keys WHERE created_at < NOW() - INTERVAL '24 hours'`);
  return r.rowCount;
}
