import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { config } from '../config.js';
import { fail } from '../http.js';

export const IMAGE_TYPES = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' };

export function detectImage(buf) {
  if (buf.length > 12 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) return 'image/png';
  if (buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length > 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  return null;
}

/** Ham bayt gövdesini doğrular, uploads dizinine yazar ve "/uploads/..." adresini döndürür. */
export async function saveUpload(req) {
  const buf = req.body;
  if (!Buffer.isBuffer(buf) || !buf.length) throw fail('Görsel gönderilmedi (png, jpeg veya webp).');
  const kind = detectImage(buf);
  if (!kind || kind !== req.headers['content-type']?.split(';')[0]) throw fail('Görsel biçimi geçersiz.');
  await fs.mkdir(config.uploadDir, { recursive: true });
  const name = `${crypto.randomUUID()}.${IMAGE_TYPES[kind]}`;
  await fs.writeFile(path.join(config.uploadDir, name), buf);
  return `/uploads/${name}`;
}

export async function removeUpload(url) {
  if (!url || !url.startsWith('/uploads/')) return;
  try { await fs.unlink(path.join(config.uploadDir, path.basename(url))); } catch (_) { /* yoksay */ }
}
