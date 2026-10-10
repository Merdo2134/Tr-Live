import fs from 'node:fs/promises';
import path from 'node:path';
import { config } from '../config.js';
import { fail } from '../http.js';
import { query } from '../database.js';

export const IMAGE_TYPES = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' };
// Kullanıcı yüklemeleri media_files'ta bu türle tutulur; yönetici varlıkları (hediye, çerçeve) ayrı türdedir
// ve kullanıcı işlemleriyle asla silinmez.
export const USER_UPLOAD_KIND = 'upload';
// Sunucunun yüklediği görsellerin adresi: /media/<uuid>.<uzantı> (veritabanı) veya eski /uploads/<uuid>.<uzantı> (disk).
export const OWN_IMAGE_RE = /^\/(?:media|uploads)\/[0-9a-f-]{36}\.(?:png|jpg|webp)$/;

export function detectImage(buf) {
  if (buf.length > 12 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) return 'image/png';
  if (buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length > 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  return null;
}

/**
 * Görseli veritabanına yazar ve "/media/<id>.<uzantı>" adresini döndürür.
 * Render gibi platformlarda disk her dağıtımda sıfırlandığı için görseller artık diske yazılmaz.
 */
export async function storeImage(buf, mime, ownerId, purpose) {
  const ext = IMAGE_TYPES[mime];
  if (!ext) throw fail('Görsel biçimi geçersiz.');
  const r = await query(
    `INSERT INTO media_files(kind, mime, ext, size_bytes, data, meta, created_by) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
    [USER_UPLOAD_KIND, mime, ext, buf.length, buf, JSON.stringify({ purpose }), ownerId ?? null],
  );
  return `/media/${r.rows[0].id}.${ext}`;
}

/** Ham bayt gövdesini doğrular, kalıcı olarak saklar ve adresini döndürür. */
export async function saveUpload(req, purpose = 'image') {
  const buf = req.body;
  if (!Buffer.isBuffer(buf) || !buf.length) throw fail('Görsel gönderilmedi (png, jpeg veya webp).');
  const kind = detectImage(buf);
  if (!kind || kind !== req.headers['content-type']?.split(';')[0]) throw fail('Görsel biçimi geçersiz.');
  const url = await storeImage(buf, kind, req.user?.id ?? null, purpose);
  // Sahiplik kaydı: gönderide yalnızca kendi yüklediğin görsel kullanılabilsin.
  await query(`INSERT INTO upload_owners(url, owner_id) VALUES($1,$2) ON CONFLICT (url) DO NOTHING`, [url, req.user?.id ?? null]);
  return url;
}

/**
 * Kullanıcı yüklemesini siler. ownerId verilirse yalnızca o kişinin yüklediği kayıt silinir
 * (başkasının dosyası ya da yönetici varlığı hiçbir koşulda silinmez).
 */
export async function removeUpload(url, ownerId = null) {
  if (!url || typeof url !== 'string') return;
  const m = /^\/media\/([0-9a-f-]{36})\./.exec(url);
  if (m) {
    try {
      await query(
        `DELETE FROM media_files WHERE id = $1 AND kind = $2 AND ($3::uuid IS NULL OR created_by = $3)`,
        [m[1], USER_UPLOAD_KIND, ownerId],
      );
      forgetMedia(m[1]);
    } catch (_) { /* yoksay */ }
    return;
  }
  if (url.startsWith('/uploads/')) {
    try { await fs.unlink(path.join(config.uploadDir, path.basename(url))); } catch (_) { /* yoksay */ }
  }
}

/**
 * Hareketli profil fotoğrafı kaydını siler. Yalnızca kullanıcının kendi yüklediği gif/webp silinir;
 * yönetici varlıkları (hediye, çerçeve) hiçbir koşulda silinmez.
 */
export async function removeAnimatedAvatar(url, userId) {
  const m = /^\/media\/([0-9a-f-]{36})\./.exec(typeof url === 'string' ? url : '');
  if (!m || !userId) return;
  try {
    await query(
      `DELETE FROM media_files WHERE id = $1 AND created_by = $2 AND kind IN ('gif','webp')
         AND (meta->>'purpose' = 'avatar_animated' OR (meta = '{}'::jsonb AND NOT EXISTS (SELECT 1 FROM users WHERE id = $2 AND system_role = 'admin')))`,
      [m[1], userId],
    );
    forgetMedia(m[1]);
  } catch (_) { /* yoksay */ }
}

// ---- /media/:id sunumu için küçük bellek önbelleği ----
// Profil fotoğrafları her ekranda tekrar istenir; her seferinde veritabanından okumamak için son kullanılanlar
// bellekte tutulur. Büyük dosyalar (hediye animasyonları) önbelleğe alınmaz.
const CACHE_MAX_BYTES = 48 * 1024 * 1024;
const CACHE_ITEM_MAX = 1024 * 1024;
const cache = new Map(); // id -> { mime, data }
let cacheBytes = 0;

export function cachedMedia(id) {
  const hit = cache.get(id);
  if (!hit) return null;
  cache.delete(id);
  cache.set(id, hit); // en son kullanılan sona
  return hit;
}

export function rememberMedia(id, mime, data) {
  if (!data || data.length > CACHE_ITEM_MAX) return;
  forgetMedia(id);
  cache.set(id, { mime, data });
  cacheBytes += data.length;
  for (const [k, v] of cache) {
    if (cacheBytes <= CACHE_MAX_BYTES) break;
    cache.delete(k);
    cacheBytes -= v.data.length;
  }
}

export function forgetMedia(id) {
  const hit = cache.get(id);
  if (!hit) return;
  cache.delete(id);
  cacheBytes -= hit.data.length;
}

export const mediaCacheStats = () => ({ items: cache.size, bytes: cacheBytes });
