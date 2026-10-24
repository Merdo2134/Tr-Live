import fs from 'node:fs';
import zlib from 'node:zlib';
import { query, tx } from './database.js';
import { ensureVapc } from './services/media.js';

// Hazır paket: siyah arka planlı videolardan şeffaf yapılmış çerçeveler (hareketli webp) ve hediyeler (şeffaf mp4 / VAP,
// renkler oynatıcının beklediği ön-çarpımlı biçimde). Dosyalar iki yoldan gelir:
//  1) Depodaki backend/src/samples/packN/ klasörleri (sunucu açılışında uygulanır),
//  2) Yönetim panelinden yüklenen TR-Live-paket-N.zip dosyaları (anında uygulanır, GitHub gerekmez).
// N = sürüm. Her öğenin kurulu sürümü asset_items tablosunda tutulur; daha yeni sürüm gelince yalnızca görüntü
// dosyaları yenilenir (ad, fiyat, sekme ve geçmiş kayıtlar korunur). Yöneticinin sildiği öğe yeniden eklenmez.
const SAMPLES = new URL('./samples/', import.meta.url);
const FRAME_PRICE = 5000;
const FRAME_DAYS = 30;
// Alıcının mikindeki dairede oynayanlar.
const SEAT_GIFTS = new Set(['g_egg', 'g_tomato']);
const FRAMES = [
  ['f_rainbow', 'Altın Gökkuşağı'],
  ['f_kiss', 'Öpücük'],
  ['f_ruby', 'Kızıl Yakut'],
  ['f_phoenix', 'Altın Anka'],
  ['f_shield', 'Altın Kalkan'],
  ['f_flame', 'Alev Kanatlar'],
  ['f_ice', 'Ateş ve Buz'],
  ['f_diamond', 'Elmas Taç'],
  ['f_silver', 'Gümüş Tüy'],
  ['f_violet', 'Mor Gül'],
  ['f_sapphire', 'Safir Kanat'],
  ['f_top1', 'Top 1 Yayıncı'],
];
// [dosya, ad, fiyat, sekme]
const GIFTS = [
  ['g_mic', 'Mikrofon', 99, 'popular'],
  ['g_peach', 'Şeftali', 99, 'popular'],
  ['g_fruit', 'Meyve Kupası', 129, 'popular'],
  ['g_icecream', 'Dondurma', 149, 'popular'],
  ['g_candy', 'Şeker', 199, 'popular'],
  ['g_blueheart', 'Mavi Kalp', 299, 'popular'],
  ['g_grill', 'Mangal', 699, 'popular'],
  ['g_rocket', 'Roket', 999, 'popular'],
  ['g_cake3', 'Doğum Günü Pastası', 999, 'popular'],
  ['g_cake1', 'Ayıcıklı Pasta', 1499, 'popular'],
  ['g_balloon', 'Elmas Balon', 1500, 'popular'],
  ['g_rose', 'Büyülü Gül', 1999, 'popular'],
  ['g_shoes', 'Külkedisi Ayakkabısı', 2000, 'popular'],
  ['g_cake2', 'Şeker Pastası', 2999, 'popular'],
  ['g_eagle', 'Kartal', 3000, 'popular'],
  ['g_crown', 'Kırmızı Taç', 3500, 'popular'],
  ['g_sword', 'Kılıç', 3999, 'popular'],
  ['g_flowergirl', 'Çiçek Kız', 4000, 'popular'],
  ['g_beauty', 'Güzel ve Kedi', 4999, 'popular'],
  ['g_crystal', 'Kristal Hediye', 6000, 'popular'],
  ['g_fountain', 'Dilek Çeşmesi', 7999, 'popular'],
  ['g_lantern', 'Ramazan Fenerleri', 1999, 'event'],
  ['g_ramadancar', 'Ramazan Arabası', 9999, 'event'],
  ['g_bluering', 'Mavi Yüzük', 2999, 'cp'],
  ['g_rings', 'Yüzükler', 4999, 'cp'],
  ['g_lovering', 'Aşk Yüzüğü', 5999, 'cp'],
  ['g_romance', 'Romantik An', 9999, 'cp'],
  ['g_wedding', 'Düğün', 19999, 'cp'],
  ['g_warrior', 'Altın Savaşçı', 5000, 'vip'],
  ['g_jets', 'Savaş Uçakları', 7000, 'vip'],
  ['g_unicorn', 'Tek Boynuzlu At', 8000, 'vip'],
  ['g_jewel', 'Mücevher', 9999, 'vip'],
  ['g_yacht', 'Yat', 10000, 'vip'],
  ['g_chest', 'Hazine Sandığı', 12000, 'vip'],
  ['g_princess', 'Prenses', 14999, 'vip'],
  ['g_phoenix', 'Anka Kuşu', 15000, 'vip'],
  ['g_dragon', 'Ateş Ejderi', 20000, 'vip'],
  ['g_jeep', 'Arazi Aracı', 19999, 'vip'],
  ['g_transformer', 'Robot Araba', 24999, 'vip'],
  ['g_lion', 'Ateş Aslanı', 25000, 'vip'],
  ['g_palace', 'Saray Arabası', 29999, 'vip'],
  ['g_angel', 'Melek', 30000, 'vip'],
  ['g_sheikh', 'Zengin Şeyh', 50000, 'vip'],
  ['g_lion3', 'Kral Aslan', 20000, 'vip'],
  ['g_phoenix3d', 'Ateş Kuşu', 9999, 'vip'],
  ['g_unicorn2d', 'Sevimli Unicorn', 1999, 'popular'],
  ['g_egypt', 'Mısır', 999, 'event'],
  ['g_racecars', 'Yarış Arabaları', 39999, 'vip'],
  ['g_volcano', 'Yanardağ', 14999, 'vip'],
  ['g_cabrio', 'Üstü Açık Araba', 29999, 'vip'],
  ['g_tiger', 'Kaplan', 4999, 'popular'],
  ['g_usa', 'Amerika', 999, 'event'],
  ['g_castleball', 'Sihirli Küre', 12999, 'vip'],
  ['g_icecastle', 'Buz Şatosu', 9999, 'vip'],
  ['g_neonroad', 'Neon Yol', 7999, 'vip'],
  ['g_orangecar', 'Turuncu Spor Araba', 34999, 'vip'],
  ['g_denmark', 'Danimarka', 999, 'event'],
  ['g_motor', 'Motosiklet', 8999, 'vip'],
  ['g_singer', 'Şarkıcı Kız', 3999, 'popular'],
  ['g_england', 'İngiltere', 999, 'event'],
  ['g_lionintro', 'Aslan Girişi', 5999, 'vip'],
  ['g_india', 'Hindistan', 999, 'event'],
  ['g_indonesia', 'Endonezya', 999, 'event'],
  ['g_neoncar', 'Neon Araba', 19999, 'vip'],
  ['g_yellowcar', 'Sarı Spor Araba', 34999, 'vip'],
  ['g_blackcar', 'Siyah Spor Araba', 39999, 'vip'],
  ['g_france', 'Fransa', 999, 'event'],
  ['g_wingsgirl', 'Kanatlı Kız', 6999, 'popular'],
  ['g_limo', 'Lüks Limuzin', 49999, 'vip'],
  ['g_goldjeep', 'Altın Cip', 44999, 'vip'],
  ['g_dress', 'Gelinlik', 9999, 'cp'],
  ['g_bluecar', 'Mavi Spor Araba', 44999, 'vip'],
  ['g_crown2', 'Altın Taç', 19999, 'vip'],
  ['g_china', 'Çin', 999, 'event'],
  ['g_spaceman', 'Astronot', 2999, 'popular'],
  ['g_purplecar', 'Mor Şimşek Araba', 9999, 'vip'],
  ['g_firelion', 'Alev Aslan', 6999, 'vip'],
  ['g_greenmotor', 'Yeşil Motosiklet', 7999, 'vip'],
  ['g_pakistan', 'Pakistan', 999, 'event'],
  ['g_dubai', 'Dubai', 999, 'event'],
  ['g_germany', 'Almanya', 999, 'event'],
  ['g_smallphoenix', 'Küçük Anka', 1999, 'popular'],
  ['g_newyear', 'Yeni Yıl', 2999, 'event'],
  ['g_bullcar', 'Altın Boğa Araba', 29999, 'vip'],
  ['g_ship', 'Büyük Gemi', 19999, 'vip'],
  ['g_whitecar', 'Beyaz Spor Araba', 24999, 'vip'],
  ['g_bluesport', 'Mavi Yarış Arabası', 19999, 'vip'],
  ['g_canada', 'Kanada', 999, 'event'],
  ['g_darkdragon', 'Gece Ejderi', 14999, 'vip'],
  ['g_australia', 'Avustralya', 999, 'event'],
  ['g_lovecity', 'Aşk Şehri', 4999, 'cp'],
  ['g_marryme', 'Evlen Benimle', 19999, 'cp'],
  ['g_devil', 'Şeytan', 24999, 'vip'],
  ['g_mermaidboat', 'Deniz Kızı Gemisi', 14999, 'vip'],
  ['g_flyinggirl', 'Uçan Kız', 2999, 'popular'],
  ['g_pinkcastle', 'Pembe Şato', 4999, 'popular'],
  ['g_love', 'Aşk', 499, 'popular'],
  ['g_flyingboat', 'Uçan Gül Gemisi', 9999, 'cp'],
  ['g_tomato', 'Domates', 19, 'popular'],
  ['g_redgate', 'Kızıl Saray Kapısı', 19999, 'vip'],
  ['g_egg', 'Yumurta', 19, 'popular'],
  ['g_drums', 'Davul', 299, 'popular'],
  ['g_balloonring', 'Balonlu Yüzük', 3999, 'cp'],
  ['g_skypalace', 'Uçan Saray', 14999, 'vip'],
  ['g_whitecouple', 'Beyaz Gelinlikli Çift', 7999, 'cp'],
  ['g_fireworks', 'Havai Fişekli Şato', 1999, 'popular'],
  ['g_dj', 'DJ', 999, 'popular'],
];

const FRAME_META = new Map(FRAMES.map(([key, name]) => [key, { name }]));
const GIFT_META = new Map(GIFTS.map(([key, name, price, category]) => [key, { name, price, category }]));
export const PACK_GIFT_COUNT = GIFTS.length;
export const PACK_FRAME_COUNT = FRAMES.length;

const MEDIA_ID = /^\/media\/([0-9a-f-]{36})\.[a-z0-9]+$/i;

async function putMedia(c, kind, mime, ext, data, key) {
  const r = await c.query(
    `INSERT INTO media_files(kind, mime, ext, size_bytes, data, meta) VALUES($1,$2,$3,$4,$5,$6) RETURNING id`,
    [kind, mime, ext, data.length, data, JSON.stringify({ purpose: 'asset_pack', key })],
  );
  return `/media/${r.rows[0].id}.${ext}`;
}

async function dropAssetMedia(c, url) {
  const m = MEDIA_ID.exec(url ?? '');
  if (!m) return;
  // Başka bir hediye / çerçeve / ürün aynı dosyayı kullanıyorsa silinmez.
  await c.query(
    `DELETE FROM media_files WHERE id = $1 AND meta->>'purpose' = 'asset_pack'
       AND NOT EXISTS (SELECT 1 FROM gifts WHERE icon_url = $2 OR animation_url = $2)
       AND NOT EXISTS (SELECT 1 FROM frames WHERE image_url = $2)
       AND NOT EXISTS (SELECT 1 FROM store_items WHERE image_url = $2)`,
    [m[1], url],
  );
}

/** Eski paket sistemiyle (asset_seeds) kurulmuş en yüksek sürüm; hiç kurulmadıysa 0. */
async function legacyVersion(c, key) {
  const r = await c.query(`SELECT key FROM asset_seeds WHERE key = ANY($1)`, [[1, 2, 3].map((n) => `pack${n}:${key}`)]);
  return Math.max(0, ...r.rows.map((x) => Number(x.key.slice(4, x.key.indexOf(':')))));
}

/** Eski paket sistemiyle eklenmiş hediyeyi bulur: önce dosya anahtarıyla, sonra paket dosyası kullanan aynı adla. */
async function legacyGift(c, key, name) {
  const pick = (where, params) => c.query(
    `SELECT g.id FROM gifts g JOIN media_files m ON g.animation_url = '/media/' || m.id || '.mp4'
      WHERE m.meta->>'purpose' = 'asset_pack' AND ${where}
        AND NOT EXISTS (SELECT 1 FROM asset_items a WHERE a.ref_id = g.id) ORDER BY g.is_active DESC LIMIT 1`, params,
  ).then((r) => r.rows[0]?.id ?? null);
  return (await pick(`m.meta->>'key' = $1`, [key])) ?? (await pick('g.name = $1', [name]));
}

async function legacyFrame(c, name) {
  const r = await c.query(
    `SELECT f.id FROM frames f JOIN media_files m ON f.image_url = '/media/' || m.id || '.webp'
      WHERE m.meta->>'purpose' = 'asset_pack' AND f.name = $1
        AND NOT EXISTS (SELECT 1 FROM asset_items a WHERE a.ref_id = f.id) LIMIT 1`, [name],
  );
  return r.rows[0]?.id ?? null;
}

async function remember(c, key, kind, refId, version) {
  await c.query(
    `INSERT INTO asset_items(key, kind, ref_id, version) VALUES($1,$2,$3,$4)
     ON CONFLICT (key) DO UPDATE SET ref_id = EXCLUDED.ref_id, version = EXCLUDED.version, updated_at = NOW()`,
    [key, kind, refId, version],
  );
  // Eski sürüme dönülürse eski kod bu öğeyi yeniden eklemesin.
  await c.query(`INSERT INTO asset_seeds(key) VALUES($1) ON CONFLICT DO NOTHING`, [`pack${Math.min(version, 3)}:${key}`]);
}

/**
 * Bir hediyeyi kurar ya da yeni sürümüyle yeniler. Döner: 'added' | 'updated' | 'same' | 'deleted' | 'unknown'.
 * mp4 / icon: Buffer ya da () => Buffer (dosya yalnızca gerekirse okunur).
 */
async function applyGift(key, version, mp4, icon) {
  const meta = GIFT_META.get(key);
  if (!meta) return 'unknown';
  return tx(async (c) => {
    await c.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`asset:${key}`]);
    const cur = (await c.query(`SELECT ref_id, version FROM asset_items WHERE key = $1`, [key])).rows[0];
    if (cur && cur.version >= version) return 'same';
    let giftId = cur ? cur.ref_id : await legacyGift(c, key, meta.name);
    const old = giftId ? (await c.query(`SELECT id, icon_url, animation_url FROM gifts WHERE id = $1`, [giftId])).rows[0] : null;
    const legacy = cur ? 0 : await legacyVersion(c, key);
    const seat = SEAT_GIFTS.has(key);
    if (!old && (cur || legacy > 0)) {
      // Yönetici silmiş: yeniden eklenmez.
      await remember(c, key, 'gift', null, version);
      return 'deleted';
    }
    if (old && !cur && legacy >= version) {
      // Eski sistemle aynı ya da daha yeni sürüm kurulmuş: dosyalar yeniden yazılmaz, yalnızca kaydı tutulur.
      if (seat) await c.query(`UPDATE gifts SET play_mode = 'seat' WHERE id = $1`, [old.id]);
      await remember(c, key, 'gift', old.id, legacy);
      return 'same';
    }
    const iconUrl = await putMedia(c, 'png', 'image/png', 'png', typeof icon === 'function' ? icon() : icon, key);
    const raw = typeof mp4 === 'function' ? mp4() : mp4;
    const animUrl = await putMedia(c, 'mp4', 'video/mp4', 'mp4', ensureVapc(raw, 'left').buf, key);
    if (old) {
      await c.query(
        `UPDATE gifts SET icon_url = $2, animation_url = $3, animation_format = 'mp4', has_alpha = TRUE,
           play_mode = CASE WHEN $4 THEN 'seat' ELSE play_mode END WHERE id = $1`,
        [old.id, iconUrl, animUrl, seat],
      );
      await dropAssetMedia(c, old.icon_url);
      await dropAssetMedia(c, old.animation_url);
      giftId = old.id;
    } else {
      giftId = (await c.query(
        `INSERT INTO gifts(name, coin_price, icon_url, animation_url, animation_format, has_alpha, category, play_mode)
         VALUES($1,$2,$3,$4,'mp4',TRUE,$5,$6) RETURNING id`,
        [meta.name, meta.price, iconUrl, animUrl, meta.category, seat ? 'seat' : 'full'],
      )).rows[0].id;
    }
    await remember(c, key, 'gift', giftId, version);
    return old ? 'updated' : 'added';
  });
}

async function applyFrame(key, version, webp) {
  const meta = FRAME_META.get(key);
  if (!meta) return 'unknown';
  return tx(async (c) => {
    await c.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`asset:${key}`]);
    const cur = (await c.query(`SELECT ref_id, version FROM asset_items WHERE key = $1`, [key])).rows[0];
    if (cur && cur.version >= version) return 'same';
    let frameId = cur ? cur.ref_id : await legacyFrame(c, meta.name);
    const old = frameId ? (await c.query(`SELECT id, image_url FROM frames WHERE id = $1`, [frameId])).rows[0] : null;
    const legacy = cur ? 0 : await legacyVersion(c, key);
    if (!old && (cur || legacy > 0)) {
      await remember(c, key, 'frame', null, version);
      return 'deleted';
    }
    if (old && !cur && legacy >= version) {
      // Eski sistemle aynı sürüm kurulmuş: yalnızca kaydı tutulur.
      await remember(c, key, 'frame', old.id, legacy);
      return 'same';
    }
    const url = await putMedia(c, 'webp', 'image/webp', 'webp', typeof webp === 'function' ? webp() : webp, key);
    if (old) {
      await c.query(`UPDATE frames SET image_url = $2 WHERE id = $1`, [old.id, url]);
      await c.query(`UPDATE store_items SET image_url = $2 WHERE category = 'frame' AND ref_id = $1`, [old.id, url]);
      await dropAssetMedia(c, old.image_url);
      frameId = old.id;
    } else {
      frameId = (await c.query(`INSERT INTO frames(name, image_url) VALUES($1,$2) RETURNING id`, [meta.name, url])).rows[0].id;
      await c.query(
        `INSERT INTO store_items(category, name, image_url, ref_id, price_coins, duration_days, for_sale) VALUES('frame',$1,$2,$3,$4,$5,TRUE)`,
        [meta.name, url, frameId, FRAME_PRICE, FRAME_DAYS],
      );
    }
    await remember(c, key, 'frame', frameId, version);
    return old ? 'updated' : 'added';
  });
}

const FILE_RE = /(?:^|\/)pack(\d{1,3})\/((?:g|f)_[a-z0-9]+)(\.mp4|_icon\.png|\.webp)$/;

/** Dosya listesinden (ad → okuyucu) her öğenin en yüksek sürümünü seçip uygular. */
async function applyFiles(entries) {
  const items = new Map(); // key → { version, files: { '.mp4': fn, ... } }
  for (const [name, read] of entries) {
    const m = FILE_RE.exec(name);
    if (!m) continue;
    const version = Number(m[1]); const key = m[2]; const part = m[3];
    let it = items.get(key);
    if (!it || it.version < version) { it = { version, files: {} }; items.set(key, it); }
    if (it.version === version) it.files[part] = read;
  }
  const results = [];
  for (const [key, it] of items) {
    let status;
    try {
      if (key.startsWith('g_')) {
        status = it.files['.mp4'] && it.files['_icon.png'] ? await applyGift(key, it.version, it.files['.mp4'], it.files['_icon.png']) : 'incomplete';
      } else {
        status = it.files['.webp'] ? await applyFrame(key, it.version, it.files['.webp']) : 'incomplete';
      }
    } catch (e) {
      console.error(`Hazır paket öğesi uygulanamadı (${key}):`, e.message);
      status = 'error';
    }
    const name = (GIFT_META.get(key) ?? FRAME_META.get(key))?.name ?? key;
    results.push({ key, name, version: it.version, status });
  }
  return results;
}

/** Sunucu açılışında: depodaki samples/packN klasörlerini uygular. */
export async function seedAssetPacks() {
  const entries = [];
  let dirs = [];
  try { dirs = fs.readdirSync(SAMPLES).filter((d) => /^pack\d+$/.test(d)); } catch { return 0; }
  for (const d of dirs) {
    let files = [];
    try { files = fs.readdirSync(new URL(`${d}/`, SAMPLES)); } catch { continue; }
    for (const f of files) {
      const url = new URL(`${d}/${f}`, SAMPLES);
      entries.push([`${d}/${f}`, () => fs.readFileSync(url)]);
    }
  }
  const res = await applyFiles(entries);
  return res.filter((r) => r.status === 'added' || r.status === 'updated').length;
}

// ---------- Yönetimden zip ile yükleme ----------

/** Zip dosyasının içindekileri listeler (sıkıştırmasız ya da deflate). Döner: [ad, () => Buffer][] */
export function readZip(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 22) throw new Error('Zip dosyası geçersiz.');
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('Zip dosyası geçersiz (son kayıt bulunamadı).');
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const out = [];
  for (let n = 0; n < count; n++) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== 0x02014b50) throw new Error('Zip dizini bozuk.');
    if (buf.readUInt16LE(p + 8) & 1) throw new Error('Şifreli zip desteklenmiyor.');
    const method = buf.readUInt16LE(p + 10);
    const csize = buf.readUInt32LE(p + 20);
    const usize = buf.readUInt32LE(p + 24);
    const nlen = buf.readUInt16LE(p + 28); const xlen = buf.readUInt16LE(p + 30); const clen = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.toString('utf8', p + 46, p + 46 + nlen);
    p += 46 + nlen + xlen + clen;
    if (name.endsWith('/')) continue;
    if (local + 30 > buf.length || buf.readUInt32LE(local) !== 0x04034b50) throw new Error('Zip kaydı bozuk.');
    const start = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
    if (start + csize > buf.length) throw new Error('Zip kaydı eksik.');
    out.push([name, () => {
      const data = buf.subarray(start, start + csize);
      if (method === 0) return Buffer.from(data);
      if (method === 8) return zlib.inflateRawSync(data, { maxOutputLength: Math.max(usize, 1) + 1024 });
      throw new Error('Desteklenmeyen zip sıkıştırması.');
    }]);
  }
  return out;
}

/** Yönetimden yüklenen paket zip'ini uygular. */
export async function applyPackZip(buf) {
  return applyFiles(readZip(buf));
}

/** Paket durumu: kaç öğe kurulu, hangi sürümde, hangileri eksik. */
export async function packStatus() {
  const rows = (await query(`SELECT key, kind, version, ref_id FROM asset_items`)).rows;
  const byKey = new Map(rows.map((r) => [r.key, r]));
  const versions = {};
  for (const r of rows) if (r.ref_id) versions[r.version] = (versions[r.version] ?? 0) + 1;
  const missing = [...GIFTS.map(([k, n]) => [k, n]), ...FRAMES.map(([k, n]) => [k, n])]
    .filter(([k]) => !byKey.get(k)).map(([k, n]) => ({ key: k, name: n }));
  const deleted = rows.filter((r) => !r.ref_id).map((r) => ({ key: r.key, name: (GIFT_META.get(r.key) ?? FRAME_META.get(r.key))?.name ?? r.key }));
  return { gifts: GIFTS.length, frames: FRAMES.length, installed: rows.filter((r) => r.ref_id).length, versions, missing, deleted };
}
