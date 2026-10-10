import { query, tx } from '../database.js';
import { fail } from '../http.js';

// Uzaktan ayarlar: APK yayınlamadan yönetim panelinden değiştirilir. Okumalar 30 sn önbelleklenir.
export const CONFIG_DEFAULTS = Object.freeze({
  // Bu sürümün altındaki uygulamalar "Güncelleme gerekli" ekranı görür. 0.0.0 = kapalı.
  minAppVersion: '0.0.0',
  // Güncel sürüm (bilgi amaçlı: "yeni sürüm var" uyarısı) ve indirme bağlantısı.
  latestAppVersion: '0.0.0',
  updateUrl: '',
  updateMessage: 'Uygulamanın yeni bir sürümü var. Devam etmek için lütfen güncelleyin.',
  // Otomatik moderasyon
  blockLinks: true,
  blockPhones: true,
  strikeLimit: 3, // pencere içinde bu kadar ihlal → otomatik kısıtlama
  strikeWindowMin: 10,
  muteMinutes: 15, // ilk kısıtlama; 24 saat içinde tekrarlarsa ikiye katlanır
  maxMuteMinutes: 1440,
  // Şanslı hediye: gönderene ortalama geri dönüş (RTP, baz puan: 7000 = %70), alıcıya geçen Elmas payı (1000 = %10),
  // tek gönderimde en fazla kazanç ve tüm kullanıcılara duyurulan en düşük çarpan.
  luckyEnabled: true,
  luckyRtpBps: 7000,
  luckyReceiverBps: 1000,
  luckyMaxWin: 5000000,
  luckyAnnounceMultiplier: 100,
});

const VERSION_RE = /^\d{1,3}\.\d{1,3}\.\d{1,3}$/;
const TTL_MS = 30e3;
let cache = null;
let cacheAt = 0;

export async function getConfig() {
  if (cache && Date.now() - cacheAt < TTL_MS) return cache;
  try {
    const r = await query(`SELECT key, value FROM app_config`);
    const next = { ...CONFIG_DEFAULTS };
    for (const row of r.rows) if (row.key in CONFIG_DEFAULTS) next[row.key] = row.value;
    cache = next;
    cacheAt = Date.now();
  } catch (_) {
    // Veritabanı geçici olarak erişilemezse son bilinen (yoksa varsayılan) ayarlarla devam edilir.
    cache ??= { ...CONFIG_DEFAULTS };
  }
  return cache;
}

export function clearConfigCache() { cache = null; }

/** Yönetici panelinden gelen değişiklikleri doğrular. Bilinmeyen anahtar reddedilir. */
export function validateConfigPatch(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw fail('Ayarlar nesne olmalı.');
  const out = {};
  for (const [k, v] of Object.entries(body)) {
    if (!(k in CONFIG_DEFAULTS)) throw fail(`Bilinmeyen ayar: ${k}`);
    const def = CONFIG_DEFAULTS[k];
    if (k === 'minAppVersion' || k === 'latestAppVersion') {
      if (typeof v !== 'string' || !VERSION_RE.test(v)) throw fail('Sürüm 1.2.3 biçiminde olmalı.');
    } else if (k === 'updateUrl') {
      if (typeof v !== 'string' || (v && !/^https:\/\/[^\s]{4,300}$/.test(v))) throw fail('İndirme bağlantısı https ile başlamalı.');
    } else if (k === 'updateMessage') {
      if (typeof v !== 'string' || v.length > 300) throw fail('Mesaj en fazla 300 karakter olmalı.');
    } else if (typeof def === 'boolean') {
      if (typeof v !== 'boolean') throw fail(`${k} true/false olmalı.`);
    } else if (typeof def === 'number') {
      const limits = {
        strikeLimit: [1, 20], strikeWindowMin: [1, 1440], muteMinutes: [1, 1440], maxMuteMinutes: [1, 10080],
        luckyRtpBps: [0, 9000], luckyReceiverBps: [0, 5000], luckyMaxWin: [1, 1000000000], luckyAnnounceMultiplier: [10, 500],
      }[k];
      if (!Number.isInteger(v) || v < limits[0] || v > limits[1]) throw fail(`${k} ${limits[0]}-${limits[1]} arasında tam sayı olmalı.`);
    }
    out[k] = v;
  }
  return out;
}

export async function saveConfig(patch, adminId) {
  // Tek işlem: birbirine bağlı ayarlar (ör. şanslı hediye oranları) yarım kaydedilmesin.
  await tx(async (c) => {
    for (const [k, v] of Object.entries(patch)) {
      await c.query(
      `INSERT INTO app_config(key, value, updated_by, updated_at) VALUES($1, $2::jsonb, $3, NOW())
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
        [k, JSON.stringify(v), adminId],
      );
    }
  });
  clearConfigCache();
  return getConfig();
}

/** "2.36.0" < "2.40.1" karşılaştırması. Geçersiz sürüm 0.0.0 sayılır. */
export function compareVersions(a, b) {
  const pa = VERSION_RE.test(a ?? '') ? a.split('.').map(Number) : [0, 0, 0];
  const pb = VERSION_RE.test(b ?? '') ? b.split('.').map(Number) : [0, 0, 0];
  for (let i = 0; i < 3; i++) if (pa[i] !== pb[i]) return pa[i] < pb[i] ? -1 : 1;
  return 0;
}
