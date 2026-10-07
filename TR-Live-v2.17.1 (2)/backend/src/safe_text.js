import { config } from './config.js';
import { containsBanned } from './text_safety.js';
import { fail } from './http.js';

const banned = config.bannedWords.map((w) => w.toLocaleLowerCase('tr'));

// Herkese görünen metinler (ad, oda adı, biyografi, aile/ajans adı) için yasaklı kelime denetimi.
export function cleanPublic(value, field = 'Metin') {
  if (typeof value === 'string' && containsBanned(value, banned)) {
    throw fail(`${field} topluluk kurallarına aykırı ifadeler içeriyor.`, 422);
  }
  return value;
}
