import crypto from 'node:crypto';
import { query } from '../database.js';

const digits = (n) => String(crypto.randomInt(10 ** (n - 1), 10 ** n));

/** 8 haneli benzersiz kullanıcı kimliği. */
export async function newPublicId(run = query) {
  for (let i = 0; i < 30; i += 1) {
    const id = digits(8);
    if (!(await run(`SELECT 1 FROM users WHERE public_id = $1`, [id])).rowCount) return id;
  }
  throw new Error('Kimlik üretilemedi.');
}

/** 7 haneli benzersiz kalıcı oda numarası. */
export async function newRoomNumber(run = query) {
  for (let i = 0; i < 30; i += 1) {
    const n = digits(7);
    const used = (await run(`SELECT 1 FROM room_profiles WHERE room_number = $1 UNION ALL SELECT 1 FROM rooms WHERE room_number = $1`, [n])).rowCount;
    if (!used) return n;
  }
  throw new Error('Oda numarası üretilemedi.');
}
