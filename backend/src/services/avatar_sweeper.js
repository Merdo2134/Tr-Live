import { query } from '../database.js';
import { removeAnimatedAvatar } from './images.js';

/** WIP 5 (hareketli avatar özelliği) bitenlerin hareketli fotoğrafını önceki sabit fotoğrafa döndürür. */
export async function revertExpiredAnimatedAvatars() {
  // Eski (hareketli) adres CTE ile alınır; dönüşten sonra o kayıt veritabanında yer kaplamasın diye silinir.
  const r = await query(
    `WITH t AS (
       SELECT u.id, u.avatar_url AS old_url FROM users u
       WHERE u.avatar_animated = TRUE
         AND NOT EXISTS (
           SELECT 1 FROM user_wip uw JOIN wip_tiers wt ON wt.level = uw.level
           WHERE uw.user_id = u.id AND uw.is_active = TRUE AND uw.expires_at > NOW()
             AND COALESCE((wt.features->>'animatedAvatar')::boolean, FALSE) = TRUE)
       FOR UPDATE OF u SKIP LOCKED)
     UPDATE users u SET avatar_url = u.static_avatar_url, static_avatar_url = NULL, avatar_animated = FALSE, updated_at = NOW()
     FROM t WHERE u.id = t.id
     RETURNING u.id, t.old_url`,
  );
  for (const row of r.rows) await removeAnimatedAvatar(row.old_url, row.id);
  return r.rowCount;
}

export function startAvatarSweeper() {
  const run = () => revertExpiredAnimatedAvatars().catch((e) => console.error('Hareketli avatar temizliği başarısız:', e.message));
  run();
  const t = setInterval(run, 60e3);
  t.unref?.();
  return t;
}
