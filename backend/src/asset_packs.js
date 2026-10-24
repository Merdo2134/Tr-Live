import fs from 'node:fs';
import { tx } from './database.js';
import { ensureVapc } from './services/media.js';

// Hazır paket: siyah arka planlı videolardan şeffaf yapılmış çerçeveler (pack1: 300x300 hareketli webp) ve hediyeler
// (pack2: yüksek kalite, hepsi aynı ölçüde 720x1280, şeffaf mp4 / VAP).
// Sunucu açılışında eklenmemiş olanlar bir kez eklenir; ad ve fiyat yönetim panelinden düzenlenebilir.
// pack1'in ilk (düşük kaliteli) hediyeleri eklenmişse pack2 gelince aynı hediyenin dosyaları yenisiyle değiştirilir
// (ad, fiyat, sekme ve geçmiş kayıtlar korunur).
const DIR = new URL('./samples/pack1/', import.meta.url);
const DIR2 = new URL('./samples/pack2/', import.meta.url);
const FRAME_PRICE = 5000;
const FRAME_DAYS = 30;
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

function read(file, dir = DIR) {
  return fs.readFileSync(new URL(file, dir));
}

async function putMedia(c, kind, mime, ext, data, key = null) {
  const r = await c.query(
    `INSERT INTO media_files(kind, mime, ext, size_bytes, data, meta) VALUES($1,$2,$3,$4,$5,$6) RETURNING id`,
    [kind, mime, ext, data.length, data, JSON.stringify({ purpose: 'asset_pack', key })],
  );
  return `/media/${r.rows[0].id}.${ext}`;
}

function has(dir, ...files) {
  return files.every((f) => fs.existsSync(new URL(f, dir)));
}

const MEDIA_ID = /^\/media\/([0-9a-f-]{36})\.[a-z0-9]+$/i;

/** Bu öğe daha önce eklenmediyse ekler (aynı işlemde kaydedilir; yarıda kalırsa bir sonraki açılışta tekrar denenir).
 * Bir öğenin hatası diğerlerini durdurmaz. Eklendiyse true döner. */
async function once(key, fn) {
  try {
    return await tx(async (c) => {
      const claim = await c.query(`INSERT INTO asset_seeds(key) VALUES($1) ON CONFLICT DO NOTHING RETURNING key`, [key]);
      if (!claim.rowCount) return false;
      await fn(c);
      return true;
    });
  } catch (e) {
    console.error(`Hazır paket öğesi eklenemedi (${key}):`, e.message);
    return false;
  }
}

export async function seedAssetPacks() {
  let added = 0;
  for (const [file, name] of FRAMES) {
    if (!has(DIR, `${file}.webp`)) continue;
    if (await once(`pack1:${file}`, async (c) => {
      const url = await putMedia(c, 'webp', 'image/webp', 'webp', read(`${file}.webp`));
      const ref = (await c.query(`INSERT INTO frames(name, image_url) VALUES($1,$2) RETURNING id`, [name, url])).rows[0].id;
      await c.query(
        `INSERT INTO store_items(category, name, image_url, ref_id, price_coins, duration_days, for_sale) VALUES('frame',$1,$2,$3,$4,$5,TRUE)`,
        [name, url, ref, FRAME_PRICE, FRAME_DAYS],
      );
    })) added++;
  }
  for (const [file, name, price, category] of GIFTS) {
    if (!has(DIR2, `${file}.mp4`, `${file}_icon.png`)) continue;
    if (await once(`pack2:${file}`, async (c) => {
      const old = (await c.query(`SELECT 1 FROM asset_seeds WHERE key = $1`, [`pack1:${file}`])).rowCount > 0;
      const icon = await putMedia(c, 'png', 'image/png', 'png', read(`${file}_icon.png`, DIR2), file);
      const anim = await putMedia(c, 'mp4', 'video/mp4', 'mp4', ensureVapc(read(`${file}.mp4`, DIR2), 'left').buf, file);
      if (!old) {
        await c.query(`INSERT INTO asset_seeds(key) VALUES($1) ON CONFLICT DO NOTHING`, [`pack1:${file}`]);
        await c.query(
          `INSERT INTO gifts(name, coin_price, icon_url, animation_url, animation_format, has_alpha, category) VALUES($1,$2,$3,$4,'mp4',TRUE,$5)`,
          [name, price, icon, anim, category],
        );
        return;
      }
      // Eski (pack1) sürüm eklenmişti: aynı hediyeyi bul (paketle gelen dosyayı kullanan ve aynı adlı), dosyalarını değiştir.
      const g = (await c.query(
        `SELECT g.id, g.icon_url, g.animation_url FROM gifts g
          JOIN media_files m ON g.animation_url = '/media/' || m.id || '.mp4'
         WHERE g.name = $1 AND m.meta->>'purpose' = 'asset_pack' ORDER BY g.is_active DESC LIMIT 1`,
        [name],
      )).rows[0];
      // Ad değiştirildiyse: eski paket dosyasının boyutuyla eşleştir (eski dosya sunucuda duruyorsa).
      let g2 = g;
      if (!g2 && has(DIR, `${file}.mp4`)) {
        const size = ensureVapc(read(`${file}.mp4`), 'left').buf.length;
        g2 = (await c.query(
          `SELECT g.id, g.icon_url, g.animation_url FROM gifts g
            JOIN media_files m ON g.animation_url = '/media/' || m.id || '.mp4'
           WHERE m.meta->>'purpose' = 'asset_pack' AND m.size_bytes = $1 ORDER BY g.is_active DESC LIMIT 1`,
          [size],
        )).rows[0];
      }
      if (!g2) {
        // Silinmiş: yeni dosyalar kullanılmaz (yer kaplamasın).
        for (const u of [icon, anim]) await c.query(`DELETE FROM media_files WHERE id = $1`, [MEDIA_ID.exec(u)[1]]);
        return;
      }
      await c.query(`UPDATE gifts SET icon_url = $2, animation_url = $3 WHERE id = $1`, [g2.id, icon, anim]);
      for (const u of [g2.icon_url, g2.animation_url]) {
        const m = MEDIA_ID.exec(u ?? '');
        if (m) await c.query(`DELETE FROM media_files WHERE id = $1 AND meta->>'purpose' = 'asset_pack'`, [m[1]]);
      }
    })) added++;
  }
  return added;
}
