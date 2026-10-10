import { query } from '../database.js';
import { config } from '../config.js';
import { fail } from '../http.js';
import { containsBanned, looksLikeFlood, findLink, findPhone } from '../text_safety.js';
import { getConfig } from './app_config.js';
import { hub } from '../realtime.js';

const banned = config.bannedWords.map((w) => w.toLocaleLowerCase('tr'));
// Telefon numarası yalnızca herkese açık yerlerde engellenir; arkadaşlar arası özel mesajda serbesttir.
const PUBLIC_CONTEXTS = new Set(['room_chat', 'post', 'comment', 'bag_note']);
const STAFF = new Set(['admin', 'support']);

const MESSAGES = {
  flood: 'Mesaj spam olarak algılandı.',
  profanity: 'Mesajınız topluluk kurallarına aykırı ifadeler içeriyor.',
  link: 'Link, site adresi veya başka uygulamaya yönlendirme paylaşılamaz.',
  phone: 'Telefon numarası herkese açık alanlarda paylaşılamaz.',
};

// TSİ: aynı gün içindeyse "saat 14:30", daha uzunsa "12.10 14:30" (yönetici kısıtı 7 güne kadar olabilir).
function fmtUntil(d) {
  const t = new Date(new Date(d).getTime() + 3 * 3600e3).toISOString();
  const sameDay = new Date(d).getTime() - Date.now() < 20 * 3600e3;
  return sameDay ? `saat ${t.slice(11, 16)}` : `${t.slice(8, 10)}.${t.slice(5, 7)} ${t.slice(11, 16)}`;
}

/** Otomatik sohbet kısıtı sürüyorsa hata fırlatır. user: req.user (users satırı). */
export function assertCanChat(user) {
  const until = user?.chat_restricted_until;
  if (until && new Date(until) > new Date()) {
    throw fail(`Kural ihlali nedeniyle ${fmtUntil(until)} tarihine kadar mesaj gönderemezsiniz.`, 403);
  }
}

/** Saf sınıflandırma (test edilebilir): ihlal türü veya null. */
export function classifyText(text, { context, staff = false, blockLinks = true, blockPhones = true } = {}) {
  if (!text) return null;
  if (looksLikeFlood(text)) return 'flood';
  if (containsBanned(text, banned)) return 'profanity';
  if (!staff && blockLinks && findLink(text)) return 'link';
  if (!staff && blockPhones && PUBLIC_CONTEXTS.has(context) && findPhone(text)) return 'phone';
  return null;
}

/**
 * Kullanıcı metnini denetler. İhlalde mesaj reddedilir ve ihlal kaydı tutulur; kısa sürede tekrarlanırsa
 * kullanıcı tüm sohbetlerde (oda, DM, gönderi, yorum) süreli kısıtlanır. Kısıt süresi 24 saat içinde
 * her tekrarda ikiye katlanır (en fazla ayardaki üst sınır).
 * context: 'room_chat' | 'dm' | 'post' | 'comment' | 'bag_note'
 */
export async function screenText(user, text, context) {
  assertCanChat(user);
  if (!text) return text;
  const cfg = await getConfig();
  const kind = classifyText(text, { context, staff: STAFF.has(user.system_role), blockLinks: cfg.blockLinks, blockPhones: cfg.blockPhones });
  if (!kind) return text;
  // Spam (aynı harf/kelime tekrarı) yalnızca reddedilir; ihlal sayılmaz (emoji tekrarı gibi masum durumlar kısıt doğurmasın).
  if (kind === 'flood') throw fail(MESSAGES.flood, 422);
  const minutes = await addStrike(user.id, kind, context, text, cfg);
  const extra = minutes ? ` Kuralları tekrar ihlal ettiğiniz için ${minutes} dakika boyunca mesaj gönderemezsiniz.` : '';
  throw fail(MESSAGES[kind] + extra, 422);
}

async function addStrike(userId, kind, context, text, cfg) {
  await query(`INSERT INTO moderation_strikes(user_id, kind, context, sample) VALUES($1,$2,$3,$4)`, [userId, kind, context, text.slice(0, 300)]);
  // Son otomatik kısıttan sonraki ihlaller sayılır (kısıt bitince eski ihlaller yeniden kısıt doğurmasın).
  const r = await query(
    `WITH last_mute AS (SELECT MAX(created_at) AS at FROM moderation_strikes WHERE user_id = $1 AND kind = 'auto_mute')
     SELECT
       (SELECT COUNT(*)::int FROM moderation_strikes s, last_mute lm
         WHERE s.user_id = $1 AND s.kind <> 'auto_mute' AND s.created_at > NOW() - make_interval(mins => $2::int)
           AND (lm.at IS NULL OR s.created_at > lm.at)) AS recent,
       (SELECT COUNT(*)::int FROM moderation_strikes WHERE user_id = $1 AND kind = 'auto_mute' AND created_at > NOW() - INTERVAL '24 hours') AS mutes`,
    [userId, cfg.strikeWindowMin],
  );
  const { recent, mutes } = r.rows[0];
  if (recent < cfg.strikeLimit) return 0;
  const minutes = Math.min(cfg.muteMinutes * 2 ** Math.min(mutes, 10), cfg.maxMuteMinutes);
  await query(
    `UPDATE users SET chat_restricted_until = GREATEST(COALESCE(chat_restricted_until, NOW()), NOW() + make_interval(mins => $2::int)) WHERE id = $1`,
    [userId, minutes],
  );
  await query(`INSERT INTO moderation_strikes(user_id, kind, context, sample) VALUES($1,'auto_mute',$2,$3)`, [userId, context, `${minutes} dk`]);
  hub.sendToUser(userId, { type: 'chat_restricted', minutes });
  return minutes;
}
