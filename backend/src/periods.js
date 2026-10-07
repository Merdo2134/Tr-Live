// Aylık dönem yardımcıları. Türkiye saati (UTC+3, yaz saati uygulaması yok) esas alınır.
const PERIOD_RE = /^\d{4}-(0[1-9]|1[0-2])$/;

export function currentPeriod(date = new Date()) {
  const shifted = new Date(date.getTime() + 3 * 3600 * 1000);
  return shifted.toISOString().slice(0, 7);
}

export function isPeriod(value) {
  return typeof value === 'string' && PERIOD_RE.test(value);
}

// [başlangıç, bitiş) aralığı, ISO string olarak döner.
export function periodRange(period) {
  if (!isPeriod(period)) throw new Error('Geçersiz dönem');
  const [y, m] = period.split('-').map(Number);
  const start = new Date(`${period}-01T00:00:00+03:00`);
  const ny = m === 12 ? y + 1 : y;
  const nm = m === 12 ? 1 : m + 1;
  const end = new Date(`${ny}-${String(nm).padStart(2, '0')}-01T00:00:00+03:00`);
  return { start: start.toISOString(), end: end.toISOString() };
}

// Liderlik tabloları için dönem başlangıcı (Türkiye saati, UTC+3). 'all' → null.
export function periodStartIso(kind, now = new Date()) {
  if (kind === 'all') return null;
  const shifted = new Date(now.getTime() + 3 * 3600 * 1000);
  const y = shifted.getUTCFullYear();
  const m = shifted.getUTCMonth();
  const d = shifted.getUTCDate();
  const offset = 3 * 3600 * 1000;
  let startUtc;
  if (kind === 'daily') startUtc = Date.UTC(y, m, d) - offset;
  else if (kind === 'weekly') startUtc = Date.UTC(y, m, d) - offset - ((shifted.getUTCDay() + 6) % 7) * 86400000;
  else if (kind === 'monthly') startUtc = Date.UTC(y, m, 1) - offset;
  else throw new Error('Geçersiz dönem');
  return new Date(startUtc).toISOString();
}
