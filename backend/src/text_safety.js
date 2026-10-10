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

// ---- Link / reklam / iletişim bilgisi tespiti ----
// Boşluksuz "kelime.uzantı" kalıbında yalnızca Türkçede kelime olarak geçmeyen uzantılar aranır
// ("tamam.biz", "evet.de", "hadi.top" gibi noktadan sonra boşluk unutulan cümleler link sayılmasın).
// "tv", "me", "co", "az", "cam" gibi Türkçe cümlede noktadan sonra gelebilen kısa sözcükler burada YOK
// ("Geldim.Az sonra", "aksamlar.Tv izliyorum"); bunlar yalnızca http/www veya gizleme kalıplarıyla yakalanır.
const STRONG_TLDS = 'com|net|org|io|xyz|app|ly|site|online|shop|store|club|info|gg|ru|vip|bet|dev|page|link|click|icu|buzz|cloud|space|website|tk|ml|ga|cf|gq|pw|sh|ws|cc|live|chat|social|asia|eu|uk|nl|tr|bio|lol|wtf|xxx|porn|sex|tips|casino|games|stream';
const DOMAIN_RE = new RegExp(`(?:^|[^\\p{L}\\p{N}_-])[a-z0-9][a-z0-9-]{1,62}\\s?\\.\\s?(?:${STRONG_TLDS})(?![\\p{L}\\p{N}])`, 'iu');
// "site nokta com", "site (dot) com", "site[.]com" gibi gizleme denemeleri.
const OBFUSCATED_RE = new RegExp(`(?:^|[^a-z0-9-])[a-z0-9-]{2,63}\\s*(?:\\(\\s*(?:\\.|dot|nokta)\\s*\\)|\\[\\s*(?:\\.|dot|nokta)\\s*\\]|\\s(?:dot|nokta)\\s)\\s*(?:${STRONG_TLDS}|tv|me|co|az|cam|biz|top|art|fun|pro|win)(?![\\p{L}\\p{N}])`, 'iu');
const LINK_RES = [
  /\bh\s*t\s*t\s*p\s*s?\s*:\s*\/\s*\//i,
  /\bwww\s*\.\s*[a-z0-9-]{2,}/i,
  /\b(?:t\.me|wa\.me|youtu\.be|discord\.gg|bit\.ly|linktr\.ee|tinyurl\.com|goo\.gl)\b/i,
  DOMAIN_RE,
  OBFUSCATED_RE,
];
const HANDLE_RE = /\b(?:telegram|tg|insta(?:gram)?|ig|snap(?:chat)?|whats?app|wp|discord|tiktok|onlyfans)\s*(?:[:=]\s*@?|\s@)[a-z0-9_.]{3,}/i;

/** Metinde link, alan adı veya başka uygulamaya yönlendiren kullanıcı adı varsa true. */
export function findLink(text) {
  if (typeof text !== 'string' || !text) return false;
  const t = text.normalize('NFKC');
  return LINK_RES.some((re) => re.test(t)) || HANDLE_RE.test(t);
}

// Türkiye cep (5xx operatör önekleri) veya + ile başlayan uluslararası numara. Coin miktarı gibi uzun sayılar
// (5.000.000.000) operatör önekine uymadığı için numara sayılmaz.
const TR_MOBILE = /^(?:90|0)?5(?:0[1-7]|[345]\d|6[1-9])\d{7}$/;
export function findPhone(text) {
  if (typeof text !== 'string' || !text) return false;
  const t = text.normalize('NFKC');
  for (const m of t.matchAll(/(\+?)(\d[\d\s.\-()]{8,22}\d)/g)) {
    const digits = m[2].replace(/\D/g, '');
    if (TR_MOBILE.test(digits)) return true;
    if (m[1] === '+' && digits.length >= 10 && digits.length <= 15) return true;
  }
  return false;
}
