import pg from 'pg';
import { config } from './config.js';

const { Pool } = pg;
let pool;
// Küçük/ücretsiz veritabanı planlarında bağlantı sınırı düşüktür (Aiven Free: toplam 20, bir kısmını Aiven kendisi kullanır;
// Render yeni sürümü açarken eski sürüm de birkaç dakika açık kalır). Havuz bu yüzden 5 ile sınırlı; DATABASE_POOL_MAX ile değişir.
const POOL_MAX = Math.min(Math.max(Number(process.env.DATABASE_POOL_MAX) || 5, 1), 50);

function sslOption() {
  // Sağlayıcının CA sertifikası verilirse (ör. Aiven "CA certificate") sertifika tam doğrulanır.
  if (process.env.DATABASE_CA) return { ca: process.env.DATABASE_CA.replace(/\\n/g, '\n'), rejectUnauthorized: true };
  if (config.databaseSsl === 'false') return false;
  if (config.databaseSsl === 'true') return { rejectUnauthorized: true };
  return { rejectUnauthorized: false }; // 'no-verify'
}

/**
 * Bağlantı adresindeki SSL parametreleri (Aiven/Supabase/Neon adreslerinin sonundaki ?sslmode=require gibi) pg'de
 * aşağıdaki ssl ayarını ezer ve sağlayıcının kendi sertifika zinciriyle "self-signed certificate" hatası verir.
 * Bu yüzden adresten çıkarılır; SSL davranışı DATABASE_SSL (ve isteğe bağlı DATABASE_CA) ile belirlenir.
 */
export function dbTarget(raw) {
  try {
    const u = new URL(raw);
    const mode = (u.searchParams.get('sslmode') || '').toLowerCase();
    for (const k of ['sslmode', 'ssl', 'sslrootcert', 'sslcert', 'sslkey', 'sslcrl', 'uselibpqcompat']) u.searchParams.delete(k);
    return { connectionString: u.toString(), sslDisabled: mode === 'disable' };
  } catch {
    return { connectionString: raw, sslDisabled: false };
  }
}

export function db() {
  if (!pool) {
    if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL tanımlı değil');
    const t = dbTarget(process.env.DATABASE_URL);
    pool = new Pool({
      connectionString: t.connectionString,
      ssl: t.sslDisabled ? false : sslOption(),
      max: POOL_MAX,
      idleTimeoutMillis: 10000,
      // Bağlantı alınamazsa istek sonsuza dek beklemesin: 15 sn sonra anlaşılır hata döner.
      connectionTimeoutMillis: 15000,
    });
    pool.on('error', (error) => console.error('PostgreSQL havuz hatası:', error.message));
  }
  return pool;
}

export const query = (text, params = []) => db().query(text, params);

/** Bağlantı havuzu durumu (yönetim paneli). */
export function poolStats() {
  if (!pool) return { total: 0, idle: 0, waiting: 0, max: POOL_MAX };
  return { total: pool.totalCount, idle: pool.idleCount, waiting: pool.waitingCount, max: POOL_MAX };
}

export async function tx(fn) {
  const client = await db().connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) { /* bağlantı zaten kopmuş olabilir */ }
    throw error;
  } finally {
    client.release();
  }
}

export async function closeDb() {
  if (pool) { await pool.end(); pool = undefined; }
}
