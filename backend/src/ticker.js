// Zamanlayıcı işleri üst üste binmesin: önceki tur bitmeden yenisi başlamaz
// (yavaş bir veritabanı turunda bağlantı havuzunun tükenmesini önler).
export function nonOverlapping(fn) {
  let busy = false;
  return async () => {
    if (busy) return;
    busy = true;
    try {
      await fn();
    } finally {
      busy = false;
    }
  };
}
