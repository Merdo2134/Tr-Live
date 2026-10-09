import { query } from '../database.js';

/** WIP 5 (hareketli avatar özelliği) bitenlerin hareketli fotoğrafını önceki sabit fotoğrafa döndürür. */
export async function revertExpiredAnimatedAvatars() {
  const r = await query(
    `UPDATE users u SET avatar_url = u.static_avatar_url, avatar_animated = FALSE, updated_at = NOW()
     WHERE u.avatar_animated = TRUE
       AND NOT EXISTS (
         SELECT 1 FROM user_wip uw JOIN wip_tiers wt ON wt.level = uw.level
         WHERE uw.user_id = u.id AND uw.is_active = TRUE AND uw.expires_at > NOW()
           AND COALESCE((wt.features->>'animatedAvatar')::boolean, FALSE) = TRUE)
     RETURNING u.id`,
  );
  return r.rowCount;
}

export function startAvatarSweeper() {
  const run = () => revertExpiredAnimatedAvatars().catch((e) => console.error('Hareketli avatar temizliği başarısız:', e.message));
  run();
  const t = setInterval(run, 60e3);
  t.unref?.();
  return t;
}
