import pg from 'pg';
import { config } from './config.js';

const { Pool } = pg;
let pool;

function sslOption() {
  if (config.databaseSsl === 'false') return false;
  if (config.databaseSsl === 'true') return { rejectUnauthorized: true };
  return { rejectUnauthorized: false }; // 'no-verify'
}

export function db() {
  if (!pool) {
    if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL tanımlı değil');
    pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: sslOption(), max: 10 });
    pool.on('error', (error) => console.error('PostgreSQL havuz hatası:', error.message));
  }
  return pool;
}

export const query = (text, params = []) => db().query(text, params);

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
