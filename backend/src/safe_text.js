import { config } from './config.js';
import { containsBanned, findLink, findPhone } from './text_safety.js';
import { fail } from './http.js';

const banned = config.bannedWords.map((w) => w.toLocaleLowerCase('tr'));

/** Herkese açık kısa metindeki sorun (yoksa null). Küfür, link/site adresi ve telefon numarası kabul edilmez. */
export function publicTextProblem(value) {
  if (typeof value !== 'string' || !value) return null;
  if (containsBanned(value, banned)) return 'topluluk kurallarına aykırı ifadeler içeriyor';
  if (findLink(value)) return 'link, site adresi veya başka uygulamaya yönlendirme içeremez';
  if (findPhone(value)) return 'telefon numarası içeremez';
  return null;
}

// Herkese görünen metinler (ad, oda adı/duyurusu, biyografi, aile/ajans adı) için denetim.
export function cleanPublic(value, field = 'Metin') {
  const problem = publicTextProblem(value);
  if (problem) throw fail(`${field} ${problem}.`, 422);
  return value;
}
