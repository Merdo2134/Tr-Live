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

// Yerleşik küfür/hakaret kökleri (Türkçe). Yazım hileleri (s1k, a.m.k, siiiik, @ $ 0 3) temizlenerek aranır.
// Kısa kökler yalnızca tam kelime, uzun kökler kelime başı olarak eşleşir ("sıkıntı" gibi masum sözler takılmaz).
const EXACT_ROOTS = new Set(['sik', 'amk', 'aq', 'oc', 'amq', 'yrk', 'pic', 'dick']);
const PREFIX_ROOTS = ['siktir', 'sikik', 'sikeyim', 'sikis', 'sikim', 'sikerim', 'amina', 'aminakoy', 'amcik', 'amcuk', 'orospu', 'orspu', 'yarrak', 'yarak', 'gotveren', 'gotlek', 'gotoc', 'ibne', 'pezevenk', 'gavat', 'kahpe', 'puşt', 'pust', 'oropsu', 'serefsiz', 'şerefsiz', 'haysiyetsiz', 'dallama', 'sürtük', 'surtuk', 'fahise', 'fuck', 'bitch', 'shit', 'pussy', 'whore', 'nigg'];
const LEET = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', '$': 's', '!': 'i' };

function foldForFilter(text) {
  let t = text.toLocaleLowerCase('tr');
  t = t.replace(/[0134577@$!]/g, (c) => LEET[c] ?? c);
  t = t.replace(/ı/g, 'i').replace(/ç/g, 'c').replace(/ş/g, 's').replace(/ğ/g, 'g').replace(/ö/g, 'o').replace(/ü/g, 'u').replace(/î/g, 'i').replace(/â/g, 'a');
  return t;
}

const FOLDED_PREFIXES = PREFIX_ROOTS.map(foldForFilter); // her mesajda yeniden hesaplanmasın (performans)

function builtinHit(text) {
  const folded = foldForFilter(text);
  // Harfler arasına konan ayırıcılar ("s.i.k", "a m k") birleştirilmiş sürümde de aranır.
  const joined = folded.replace(/(?<=\p{L})[.\-_*+,\s]+(?=\p{L}\b)/gu, '');
  for (const variant of [folded, joined]) {
    const squeezed = variant.replace(/(\p{L})\1{2,}/gu, '$1$1'); // "siiiik" → "siik"
    for (const v of [variant, squeezed, squeezed.replace(/(\p{L})\1/gu, '$1')]) {
      for (const tok of v.split(/[^\p{L}]+/u)) {
        if (!tok) continue;
        if (EXACT_ROOTS.has(tok)) return true;
        if (tok.length >= 4 && FOLDED_PREFIXES.some((r) => tok.startsWith(r))) return true;
      }
    }
  }
  return false;
}

export function containsBanned(text, words) {
  if (typeof text !== 'string') return false;
  if (builtinHit(text)) return true;
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
