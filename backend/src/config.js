import 'dotenv/config';
import path from 'node:path';

const env = process.env;
export const isProd = env.NODE_ENV === 'production';

let warned = false;
export function jwtSecret() {
  if (env.JWT_SECRET) return env.JWT_SECRET;
  if (isProd) throw new Error('JWT_SECRET tanımlı değil.');
  if (!warned) {
    warned = true;
    console.warn('[uyarı] JWT_SECRET tanımlı değil; yalnızca geliştirme için varsayılan anahtar kullanılıyor.');
  }
  return 'dev-only-change-me';
}

export function validateConfig() {
  if (!env.DATABASE_URL) throw new Error('DATABASE_URL tanımlı değil.');
  if (isProd) {
    const secret = env.JWT_SECRET || '';
    if (secret.length < 32 || /CHANGE_ME/i.test(secret)) {
      throw new Error('Üretimde JWT_SECRET en az 32 karakterlik rastgele bir değer olmalıdır.');
    }
    if (!env.LIVEKIT_API_KEY || !env.LIVEKIT_API_SECRET || !env.LIVEKIT_URL) {
      console.warn('[uyarı] LiveKit ayarları eksik; sesli/görüntülü bağlantı çalışmaz.');
    }
  }
}

export const config = {
  port: Number(env.PORT || 3000),
  corsOrigin: (env.CORS_ORIGIN || '*').split(',').map((s) => s.trim()).filter(Boolean),
  trustProxy: env.TRUST_PROXY === undefined ? false : (/^\d+$/.test(env.TRUST_PROXY) ? Number(env.TRUST_PROXY) : env.TRUST_PROXY === 'true'),
  uploadDir: env.UPLOAD_DIR || path.join(process.cwd(), 'uploads'),
  // Bu değerin (Coin) üstündeki hediyeler tüm kullanıcılara global şerit olarak gider.
  globalGiftMinCoins: BigInt(env.GLOBAL_GIFT_MIN_COINS || 1000),
  databaseSsl: env.DATABASE_SSL ?? (isProd ? 'no-verify' : 'false'),
  bannedWords: (env.BANNED_WORDS || '').split(',').map((w) => w.trim()).filter(Boolean),
  firewall: {
    enabled: env.FIREWALL_ENABLED !== 'false',
    // Asla yasaklanmayacak IP'ler (yerel geliştirme + kendi ofis/izleme IP'leriniz)
    allowIps: ['127.0.0.1', '::1', ...(env.FIREWALL_ALLOW_IPS || '').split(',').map((s) => s.trim()).filter(Boolean)],
    ipPerMinute: Number(env.FIREWALL_IP_PER_MINUTE || 300),
    banThreshold: Number(env.FIREWALL_BAN_THRESHOLD || 30),
  },
};
