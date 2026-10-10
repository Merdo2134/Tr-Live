import pg from 'pg';
import { config } from './config.js';

const { Pool } = pg;
let pool;

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
    pool = new Pool({ connectionString: t.connectionString, ssl: t.sslDisabled ? false : sslOption(), max: 10 });
    pool.on('error', (error) => console.error('PostgreSQL havuz hatası:', error.message));
  }
  return pool;
}

export const query = (text, params = []) => db().query(text, params);

/** Bağlantı havuzu durumu (yönetim paneli). */
export function poolStats() {
  if (!pool) return { total: 0, idle: 0, waiting: 0, max: 10 };
  return { total: pool.totalCount, idle: pool.idleCount, waiting: pool.waitingCount, max: 10 };
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
