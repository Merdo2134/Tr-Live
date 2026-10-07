// Sohbet/mesaj metni temizliği (saf fonksiyonlar).

// Bidi geçersiz kılma, sıfır genişlikli ve kontrol karakterleri: kimlik taklidi ve görsel sahtekârlık için kullanılır.
const INVISIBLE = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]/g;

export function cleanLine(input, maxLen = 300) {
  if (typeof input !== 'string') return '';
  return input.replace(INVISIBLE, '').replace(/\s+/g, ' ').trim().slice(0, maxLen);
}

export function cleanMultiline(input, maxLen = 1000) {
  if (typeof input !== 'string') return '';
  return input.replace(INVISIBLE, '').replace(/\r\n?/g, '\n').replace(/\n{3,}/g, '\n\n').trim().slice(0, maxLen);
}

// Yasaklı kelime listesi (BANNED_WORDS env: virgülle ayrılmış). Varsayılan boştur; sizin politikanıza göre doldurulur.
export function parseBannedWords(raw = '') {
  return raw.split(',').map((w) => w.trim().toLocaleLowerCase('tr')).filter(Boolean);
}

export function containsBanned(text, words) {
  if (!words.length) return false;
  const t = text.toLocaleLowerCase('tr');
  return words.some((w) => t.includes(w));
}

// Aynı karakterin/kelimenin tekrarıyla yapılan flood (ör. "aaaaaaaaaa", "hello hello hello hello")
export function looksLikeFlood(text) {
  if (/(.)\1{11,}/u.test(text)) return true;
  const words = text.toLocaleLowerCase('tr').split(' ').filter(Boolean);
  return words.length >= 8 && new Set(words).size <= 2;
}

// Oda etiketleri: en fazla 3, her biri 2-20 karakter (harf, rakam, boşluk, _ ve -).
export function cleanTags(input) {
  if (input === undefined || input === null) return [];
  if (!Array.isArray(input) || input.length > 3) throw Object.assign(new Error('En fazla 3 etiket girebilirsiniz.'), { status: 400 });
  const out = [];
  for (const raw of input) {
    const t = cleanLine(String(raw), 20).toLocaleLowerCase('tr');
    if (!/^[\p{L}\p{N} _-]{2,20}$/u.test(t)) throw Object.assign(new Error('Etiketler 2-20 karakter olmalı; yalnızca harf, rakam, boşluk, _ ve - içerebilir.'), { status: 400 });
    if (!out.includes(t)) out.push(t);
  }
  return out;
}
