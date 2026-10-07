// Girdi doğrulama yardımcıları (bağımlılık yok, test edilebilir).
export const MAX_AMOUNT = 1_000_000_000_000n;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function fail(message, status = 400) {
  return Object.assign(new Error(message), { status });
}

export const isUuid = (v) => typeof v === 'string' && UUID_RE.test(v);

export function uuid(value, field = 'Kimlik') {
  if (!isUuid(value)) throw fail(`${field} geçersiz.`);
  return value.toLowerCase();
}

export function uuidArray(value, field = 'Liste', max = 50) {
  if (!Array.isArray(value) || value.length > max) throw fail(`${field} geçersiz.`);
  return [...new Set(value.map((v) => uuid(v, field)))];
}

export function positiveInt(value, field, max = Number.MAX_SAFE_INTEGER) {
  const n = typeof value === 'string' && /^\d{1,15}$/.test(value.trim()) ? Number(value) : value;
  if (!Number.isSafeInteger(n) || n < 1) throw fail(`${field} geçersiz.`);
  if (n > max) throw fail(`${field} en fazla ${max} olabilir.`);
  return n;
}

// Para birimi miktarları BigInt olarak işlenir. Onaltılık/üstel/ondalıklı girdi reddedilir.
export function bigAmount(value, field = 'Miktar', { allowNegative = false, max = MAX_AMOUNT } = {}) {
  let n;
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) throw fail(`${field} geçersiz.`);
    n = BigInt(value);
  } else if (typeof value === 'string' && /^-?\d{1,15}$/.test(value.trim())) {
    n = BigInt(value.trim());
  } else {
    throw fail(`${field} geçersiz.`);
  }
  if (n === 0n) throw fail(`${field} sıfır olamaz.`);
  if (n < 0n && !allowNegative) throw fail(`${field} pozitif olmalı.`);
  if (n > max || n < -max) throw fail(`${field} çok büyük.`);
  return n;
}

export function text(value, field, { min = 0, max = 255, required = false } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required || min > 0) throw fail(`${field} gerekli.`);
    return null;
  }
  if (typeof value !== 'string') throw fail(`${field} geçersiz.`);
  const v = value.trim();
  if (v.length === 0 && (required || min > 0)) throw fail(`${field} gerekli.`);
  if (v.length < min) throw fail(`${field} en az ${min} karakter olmalı.`);
  if (v.length > max) throw fail(`${field} en fazla ${max} karakter olabilir.`);
  return v.length ? v : null;
}

export function httpsUrl(value, field = 'Adres') {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string' || value.length > 500) throw fail(`${field} geçersiz.`);
  let u;
  try { u = new URL(value); } catch { throw fail(`${field} geçersiz.`); }
  if (u.protocol !== 'https:') throw fail(`${field} https ile başlamalı.`);
  return u.toString();
}

export function oneOf(value, allowed, field) {
  if (!allowed.includes(value)) throw fail(`${field} geçersiz.`);
  return value;
}
