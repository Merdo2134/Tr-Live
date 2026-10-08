// Ödül ve çanta ayarları tek yerde: sayıları buradan değiştirin.
export const DAILY_TASKS = {
  join_room: { label: 'Bir odaya gir', target: 1 },
  mic: { label: 'Mikrofona otur', target: 1 },
  chat: { label: 'Sohbete 5 mesaj yaz', target: 5 },
  gift: { label: 'Bir hediye gönder', target: 1 },
};
export const XP_PER_TASK = 10; // her görev tamamlanınca
export const XP_PER_DAY = 50; // gün (tüm görevler) tamamlanınca: seri 1-6. günler
export const STREAK_DAYS = 7;
export const STREAK_COINS = 1000; // 7. gün tüm görevler tamamlanınca

// Şanslı çanta kademeleri.
// Normal: geri sayım yok, hemen açılır; açık kalma süresi yalnızca temizlik içindir (30 dk, sonra kalan iade edilir).
// Süper: `countdown` sn geri sayım (bu sırada not sohbete yazılır), sonra `window` sn boyunca açılır.
export const BAG_TIERS = {
  n3: { kind: 'normal', total: 3000, slots: 10, countdown: 0, window: 1800 },
  n6: { kind: 'normal', total: 6000, slots: 20, countdown: 0, window: 1800 },
  n9: { kind: 'normal', total: 9000, slots: 30, countdown: 0, window: 1800 },
  s30: { kind: 'super', total: 30000, slots: 50, countdown: 60, window: 120 },
  s60: { kind: 'super', total: 60000, slots: 50, countdown: 60, window: 120 },
  s90: { kind: 'super', total: 90000, slots: 50, countdown: 60, window: 120 },
};
