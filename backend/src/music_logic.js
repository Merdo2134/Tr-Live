// Müzik senkronizasyon mantığı (saf fonksiyonlar).
// Konum her zaman VERİTABANININ saatiyle hesaplanan "elapsedMs" ile bulunur; uygulama/veritabanı saat farkı etkilemez.
export const MAX_QUEUE = 50;
export const MAX_PER_USER = 3;
export const MUSIC_MANAGERS = ['owner', 'cohost', 'moderator'];

export function positionAt(status, positionMs, elapsedMs, durationMs = Infinity) {
  const base = Number(positionMs) || 0;
  const pos = status === 'playing' ? base + Math.max(0, Number(elapsedMs) || 0) : base;
  return Math.max(0, Math.min(pos, durationMs));
}

export function clampPosition(positionMs, durationMs) {
  const n = Math.floor(Number(positionMs));
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(n, Math.max(0, durationMs - 1)));
}

export function hasEnded(status, positionMs, elapsedMs, durationMs) {
  return status === 'playing' && durationMs > 0 && Number(positionMs) + Math.max(0, Number(elapsedMs)) >= durationMs;
}

export const MAX_PER_MANAGER = 40; // oda yetkilileri çalma listesi oluşturabilir

export function queueDecision({ queueLength, userCount, manager = false }) {
  const perUser = manager ? MAX_PER_MANAGER : MAX_PER_USER;
  if (queueLength >= MAX_QUEUE) return { ok: false, message: `Sıra dolu (en fazla ${MAX_QUEUE} şarkı).` };
  if (userCount >= perUser) return { ok: false, message: `Sıraya en fazla ${perUser} şarkı ekleyebilirsiniz.` };
  return { ok: true };
}
