// Haftalık etkinlikler: sıralama, ödül tanımları ve hafta sonunda otomatik ödül dağıtımı.
// Hafta Pazartesi 00:00 (Türkiye saati) başlar; biten haftanın ilk 3'ü bir kez ödüllendirilir.
import { query, tx } from '../database.js';
import { hub } from '../realtime.js';
import { publicUser } from '../views.js';
import { loadPublicRows, equipIfNone, announceUserChange } from './users.js';
import { wipLabel } from './wip.js';
import { nonOverlapping } from '../ticker.js';

export const EVENT_KINDS = ['couple', 'king', 'queen', 'star1', 'star2', 'star3', 'star4'];
export const isStar = (kind) => kind.startsWith('star');

export const EVENT_TITLES = {
  couple: 'Haftalık Çift', king: 'Haftanın Kralı', queen: 'Haftanın Kraliçesi',
  star1: 'Haftalık Yıldız', star2: 'Haftalık Yıldız', star3: 'Haftalık Yıldız', star4: 'Haftalık Yıldız',
};

const DEFAULT_RULES = {
  couple: [
    'Yalnızca onaylı CP çiftleri yarışır.',
    'Çiftin birbirine gönderdiği CP hediyelerinin Coin değeri toplanır (iki yön birlikte).',
    'Hafta Pazartesi 00:00\'da başlar, Pazar 23:59\'da biter (Türkiye saati).',
    'Hafta bitince ilk 3 çiftin iki kişisine de ödüller otomatik verilir.',
    'Eşitlikte sıralama sistem tarafından belirlenir. Hileli işlemlerde ödül geri alınır.',
  ].join('\n'),
  king: [
    'Profilinde cinsiyeti "Erkek" olan kullanıcılar yarışır.',
    'Hafta boyunca aldığın hediyelerin Coin değeri toplanır (kendine gönderdiğin sayılmaz).',
    'Hafta Pazartesi 00:00\'da başlar, Pazar 23:59\'da biter (Türkiye saati).',
    'Hafta bitince ilk 3\'e ödüller otomatik verilir.',
  ].join('\n'),
  queen: [
    'Profilinde cinsiyeti "Kadın" olan kullanıcılar yarışır.',
    'Hafta boyunca aldığın hediyelerin Coin değeri toplanır (kendine gönderdiğin sayılmaz).',
    'Hafta Pazartesi 00:00\'da başlar, Pazar 23:59\'da biter (Türkiye saati).',
    'Hafta bitince ilk 3\'e ödüller otomatik verilir.',
  ].join('\n'),
  star: [
    'Her hafta 4 yıldız hediyesi seçilir; her hediye ayrı bir yarıştır.',
    'O hediyeden hafta boyunca en çok gönderen (adet) kazanır. Kendine gönderilen sayılmaz.',
    'Hafta Pazartesi 00:00\'da başlar, Pazar 23:59\'da biter (Türkiye saati).',
    'Hafta bitince her hediyenin ilk 3\'üne kendi ödülleri otomatik verilir.',
  ].join('\n'),
};
export const defaultRules = (kind) => DEFAULT_RULES[isStar(kind) ? 'star' : kind];

// ---------------------------------------------------------------- hafta sınırları
/** offset 0: bu hafta, -1: geçen hafta. Dönüş: { start, end } (Date). */
export async function weekBounds(offset = 0, run = query) {
  const r = await run(
    `SELECT (date_trunc('week', NOW() AT TIME ZONE 'Europe/Istanbul') + ($1::int * INTERVAL '7 days')) AT TIME ZONE 'Europe/Istanbul' AS start`,
    [offset],
  );
  const start = new Date(r.rows[0].start);
  return { start, end: new Date(start.getTime() + 7 * 86400e3) };
}

// ---------------------------------------------------------------- sıralama
/** Sınırsız sıralama sorgusu: (user_id, partner_id, score). $1 başlangıç, $2 bitiş, $3 hediye/cinsiyet. */
function rankingSql(kind) {
  if (kind === 'couple') {
    return `SELECT LEAST(g.sender_id, g.receiver_id) AS user_id, GREATEST(g.sender_id, g.receiver_id) AS partner_id,
              SUM(g.coin_amount)::bigint AS score
            FROM gift_transactions g
            JOIN gifts gf ON gf.id = g.gift_id AND gf.category = 'cp'
            JOIN cp_pairs p ON p.user_a = LEAST(g.sender_id, g.receiver_id) AND p.user_b = GREATEST(g.sender_id, g.receiver_id) AND p.relation = 'cp'
            JOIN users ua ON ua.id = p.user_a AND ua.account_status = 'active'
            JOIN users ub ON ub.id = p.user_b AND ub.account_status = 'active'
            WHERE g.created_at >= $1 AND g.created_at < $2 AND g.sender_id <> g.receiver_id AND $3::text IS NULL
            GROUP BY 1, 2`;
  }
  if (kind === 'king' || kind === 'queen') {
    return `SELECT g.receiver_id AS user_id, NULL::uuid AS partner_id, SUM(g.coin_amount)::bigint AS score
            FROM gift_transactions g JOIN users u ON u.id = g.receiver_id
            WHERE g.created_at >= $1 AND g.created_at < $2 AND g.sender_id <> g.receiver_id
              AND u.gender = $3::text AND u.account_status = 'active'
            GROUP BY g.receiver_id`;
  }
  return `SELECT g.sender_id AS user_id, NULL::uuid AS partner_id, SUM(g.quantity)::bigint AS score
          FROM gift_transactions g JOIN users u ON u.id = g.sender_id
          WHERE g.created_at >= $1 AND g.created_at < $2 AND g.sender_id <> g.receiver_id
            AND g.gift_id = $3::uuid AND u.account_status = 'active'
          GROUP BY g.sender_id`;
}

function rankingArg(kind, giftId) {
  if (kind === 'king') return 'male';
  if (kind === 'queen') return 'female';
  if (isStar(kind)) return giftId;
  return null;
}

export async function ranking(kind, start, end, { limit = 50, giftId = null, run = query } = {}) {
  if (isStar(kind) && !giftId) return [];
  const r = await run(
    `SELECT * FROM (${rankingSql(kind)}) t ORDER BY score DESC, user_id LIMIT $4`,
    [start, end, rankingArg(kind, giftId), limit],
  );
  return r.rows;
}

/** Kullanıcının sırası ve puanı (çiftte iki taraftan biri olması yeter). Listede yoksa null. */
export async function myRank(kind, start, end, userId, giftId = null) {
  if (isStar(kind) && !giftId) return null;
  const r = await query(
    `SELECT rank, score::text, user_id, partner_id FROM (
       SELECT t.*, ROW_NUMBER() OVER (ORDER BY score DESC, user_id) AS rank FROM (${rankingSql(kind)}) t
     ) x WHERE x.user_id = $4 OR x.partner_id = $4 LIMIT 1`,
    [start, end, rankingArg(kind, giftId), userId],
  );
  return r.rows[0] ? { rank: Number(r.rows[0].rank), score: r.rows[0].score } : null;
}

/** Sıralama satırlarını kullanıcı bilgileriyle doldurur. */
export async function decorate(rows, viewerId) {
  const ids = [...new Set(rows.flatMap((x) => [x.user_id, x.partner_id]).filter(Boolean))];
  const users = new Map((await loadPublicRows(ids)).map((u) => [u.id, u]));
  return rows.map((x, i) => ({
    rank: x.rank ?? i + 1,
    score: String(x.score),
    user: publicUser(users.get(x.user_id), viewerId),
    partner: x.partner_id ? publicUser(users.get(x.partner_id), viewerId) : null,
  }));
}

// ---------------------------------------------------------------- ödüller
const ITEM_KIND = {
  frame: 'Çerçeve', badge: 'Rozet', chat_bubble: 'Sohbet balonu', entrance_effect: 'Giriş efekti',
  mini_card: 'Profil kartı', mic_wave: 'Mikrofon dalgası', vehicle: 'Araç', room_card: 'Oda kartı',
};
const WIP_ITEM_KIND = { frame: 'çerçevesi', chat_bubble: 'sohbet balonu', badge: 'rozeti', entrance_effect: 'giriş efekti', vehicle: 'aracı' };
export const REWARD_ITEM_CATEGORIES = Object.keys(ITEM_KIND);
const MAX_REWARDS_PER_RANK = 5;

const bad = (msg) => Object.assign(new Error(msg), { status: 400 });
const intIn = (v, lo, hi, name) => {
  const n = Number(v);
  if (!Number.isInteger(n) || n < lo || n > hi) throw bad(`${name} ${lo}-${hi} arasında olmalı.`);
  return n;
};

/** Yönetimden gelen ödül listesini doğrular; öğelerin adı ve görseli kaydedilir (dağıtımda tekrar aranmaz). */
export async function validateRewards(input, run = query) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw bad('Ödüller geçersiz.');
  const out = {};
  for (const rank of ['1', '2', '3']) {
    const list = input[rank] ?? [];
    if (!Array.isArray(list)) throw bad(`${rank}. sıra ödülleri liste olmalı.`);
    if (list.length > MAX_REWARDS_PER_RANK) throw bad(`Her sıraya en fazla ${MAX_REWARDS_PER_RANK} ödül eklenebilir.`);
    out[rank] = [];
    for (const r of list) {
      if (r?.type === 'coins') {
        out[rank].push({ type: 'coins', amount: intIn(r.amount, 1, 100_000_000, 'Coin miktarı') });
      } else if (r?.type === 'wip') {
        out[rank].push({ type: 'wip', level: intIn(r.level, 1, 10, 'WIP kademesi'), days: intIn(r.days, 1, 365, 'Gün') });
      } else if (r?.type === 'item') {
        const category = String(r.category ?? '');
        if (!ITEM_KIND[category]) throw bad('Öğe türü geçersiz.');
        const key = String(r.itemKey ?? '').slice(0, 80);
        const days = intIn(r.days, 1, 3650, 'Gün');
        const wip = /^wip:(\d{1,2})$/.exec(key);
        let name; let assetUrl = null; let wipLevel = null;
        if (wip) {
          wipLevel = Number(wip[1]);
          if (!WIP_ITEM_KIND[category] || wipLevel < 1 || wipLevel > 11) throw bad('Geçersiz WIP öğesi.');
          name = `${wipLabel(wipLevel)} ${WIP_ITEM_KIND[category]}`;
        } else if (category === 'frame') {
          const f = (await run(`SELECT name, image_url FROM frames WHERE id::text = $1`, [key])).rows[0];
          if (!f) throw bad('Çerçeve bulunamadı.');
          name = f.name; assetUrl = f.image_url;
        } else if (category === 'entrance_effect') {
          const f = (await run(`SELECT name, animation_url FROM entrance_effects WHERE id::text = $1`, [key])).rows[0];
          if (!f) throw bad('Giriş efekti bulunamadı.');
          name = f.name; assetUrl = f.animation_url;
        } else {
          const f = (await run(`SELECT name, image_url FROM store_items WHERE id::text = $1 AND category = $2`, [key, category])).rows[0];
          if (!f) throw bad('Ürün bulunamadı.');
          name = f.name; assetUrl = f.image_url;
        }
        out[rank].push({ type: 'item', category, itemKey: key, name, assetUrl, wipLevel, days });
      } else {
        throw bad('Ödül türü geçersiz (coins, wip, item).');
      }
    }
  }
  return out;
}

/** Uygulamada gösterilecek hâli. */
export function rewardView(r) {
  if (r.type === 'coins') return { type: 'coins', amount: r.amount, label: `${Number(r.amount).toLocaleString('tr-TR')} Coin` };
  if (r.type === 'wip') return { type: 'wip', level: r.level, days: r.days, label: `${wipLabel(r.level)} üyeliği · ${r.days} gün` };
  return {
    type: 'item', category: r.category, itemKey: r.itemKey, imageUrl: r.assetUrl ?? null, wipLevel: r.wipLevel ?? null, days: r.days,
    label: `${r.name} · ${r.days} gün`, kindLabel: ITEM_KIND[r.category],
  };
}

export const rewardsView = (rewards) => Object.fromEntries(['1', '2', '3'].map((k) => [k, (rewards?.[k] ?? []).map(rewardView)]));

/** Tek ödülü verir (işlem içinde). */
async function grantReward(run, userId, r, reason) {
  if (r.type === 'coins') {
    await run(`UPDATE users SET coins = coins + $1, updated_at = NOW() WHERE id = $2`, [String(r.amount), userId]);
    await run(
      `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, description) VALUES($1,'event_reward',$2,$3)`,
      [userId, String(r.amount), reason],
    );
  } else if (r.type === 'wip') {
    // Daha yüksek ya da aynı kademe varsa süresi uzar; düşük kademe varsa ödül kademesine yükselir.
    await run(
      `INSERT INTO user_wip(user_id, level, starts_at, expires_at, is_active) VALUES($1,$2,NOW(),NOW() + ($3::int * INTERVAL '1 day'),TRUE)
       ON CONFLICT (user_id) DO UPDATE SET
         level = CASE WHEN user_wip.is_active AND user_wip.expires_at > NOW() AND user_wip.level > EXCLUDED.level THEN user_wip.level ELSE EXCLUDED.level END,
         starts_at = CASE WHEN user_wip.is_active AND user_wip.expires_at > NOW() AND user_wip.level >= EXCLUDED.level THEN user_wip.starts_at ELSE NOW() END,
         expires_at = CASE WHEN user_wip.is_active AND user_wip.expires_at > NOW() AND user_wip.level >= EXCLUDED.level
                           THEN user_wip.expires_at + ($3::int * INTERVAL '1 day') ELSE EXCLUDED.expires_at END,
         is_active = TRUE`,
      [userId, r.level, r.days],
    );
  } else if (r.type === 'item') {
    const meta = { assetUrl: r.assetUrl ?? null, eventReward: reason, ...(r.wipLevel ? { wipLevel: r.wipLevel } : {}) };
    const ins = await run(
      `INSERT INTO inventory_items(user_id, item_type, item_key, item_name, expires_at, metadata)
       VALUES($1,$2,$3,$4, NOW() + ($5::int * INTERVAL '1 day'), $6) RETURNING id`,
      [userId, r.category, r.itemKey, r.name, r.days, JSON.stringify(meta)],
    );
    await equipIfNone(run, userId, r.category, ins.rows[0].id);
  }
}

// ---------------------------------------------------------------- haftalık dağıtım
/** Biten haftayı (bir kez) kapatır: ilk 3'ü kaydeder ve ödülleri verir. Dönüş: kazananlar ya da null (zaten kapalıysa). */
export async function settleWeek(start, end) {
  const winners = await tx(async (c) => {
    const run = (q, p) => c.query(q, p);
    const ins = await run(`INSERT INTO weekly_event_settlements(week_start) VALUES($1) ON CONFLICT (week_start) DO NOTHING RETURNING week_start`, [start]);
    if (!ins.rowCount) return null;
    const cfgs = (await run(`SELECT * FROM weekly_event_config ORDER BY kind`)).rows;
    const out = [];
    for (const cfg of cfgs) {
      if (!cfg.enabled || (isStar(cfg.kind) && !cfg.gift_id)) continue;
      const top = await ranking(cfg.kind, start, end, { limit: 3, giftId: cfg.gift_id, run });
      const giftName = isStar(cfg.kind) ? (await run(`SELECT name FROM gifts WHERE id = $1`, [cfg.gift_id])).rows[0]?.name : null;
      for (let i = 0; i < top.length; i += 1) {
        const rank = i + 1;
        const row = top[i];
        const rewards = cfg.rewards?.[String(rank)] ?? [];
        await run(
          `INSERT INTO weekly_event_results(week_start, kind, rank, user_id, partner_id, score, gift_id, rewards) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,
          [start, cfg.kind, rank, row.user_id, row.partner_id, String(row.score), isStar(cfg.kind) ? cfg.gift_id : null, JSON.stringify(rewards)],
        );
        const title = `${EVENT_TITLES[cfg.kind]}${giftName ? ` (${giftName})` : ''} ${rank}.`;
        for (const uid of [row.user_id, row.partner_id].filter(Boolean)) {
          let granted = 0;
          for (const r of rewards) {
            // Bir ödül sorun çıkarırsa (ör. silinmiş katalog) diğerleri yine verilir.
            await run('SAVEPOINT event_reward');
            try {
              await grantReward(run, uid, r, `Etkinlik ödülü: ${title}`);
              await run('RELEASE SAVEPOINT event_reward');
              granted += 1;
            } catch (error) {
              await run('ROLLBACK TO SAVEPOINT event_reward');
              console.error('[etkinlik] ödül verilemedi:', cfg.kind, rank, error.message);
            }
          }
          out.push({ userId: uid, kind: cfg.kind, rank, title, granted });
        }
      }
    }
    return out;
  });
  if (!winners) return null;
  for (const w of winners) {
    hub.sendToUser(w.userId, { type: 'event_reward', kind: w.kind, rank: w.rank, title: w.title, rewarded: w.granted > 0 });
    announceUserChange(w.userId);
  }
  if (winners.length) {
    const users = new Map((await loadPublicRows([...new Set(winners.map((w) => w.userId))])).map((u) => [u.id, u]));
    const lines = winners.map((w) => `${w.title} ${publicUser(users.get(w.userId), null)?.displayName ?? ''}`);
    const body = `Geçen haftanın kazananları:\n${lines.join('\n')}`.slice(0, 2000);
    await query(`INSERT INTO announcements(kind, title, body) VALUES('event', 'Haftalık etkinlik sonuçları', $1)`, [body]).catch((e) => console.error('[etkinlik] duyuru:', e.message));
  }
  return winners;
}

/** Geçen hafta kapatılmadıysa kapatır. Sunucu açılışında ve 5 dakikada bir çalışır. */
export async function settleDueWeeks() {
  const { start, end } = await weekBounds(-1);
  return settleWeek(start, end);
}

export function startWeeklyEventsTicker() {
  const run = nonOverlapping(() => settleDueWeeks().then((w) => {
    if (w) console.log(`[etkinlik] hafta kapatıldı, ${w.length} ödül sahibi.`);
  }).catch((e) => console.error('[etkinlik] haftalık dağıtım hatası:', e.message)));
  setTimeout(run, 30e3).unref();
  const t = setInterval(run, 5 * 60e3);
  t.unref();
  return t;
}
