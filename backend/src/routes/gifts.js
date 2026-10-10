import { Router } from 'express';
import { query, tx } from '../database.js';
import { requireAuth } from '../auth.js';
import { noteTask } from '../services/daily.js';
import { userLimit } from '../firewall.js';
import { fail, uuid, uuidArray, positiveInt, oneOf } from '../http.js';
import { publicUser } from '../views.js';
import { hub } from '../realtime.js';
import { config } from '../config.js';
import { distributeGift } from '../gifts_logic.js';
import { levelFromExp, familyLevelFor, giftDisplayLevel } from '../levels.js';
import { scorePk, pkView } from '../services/pk.js';
import { scoreboardOf } from '../services/scoreboard.js';
import { loadPublicRows } from '../services/users.js';
import { idempotent } from '../idempotency.js';
import { nextCombo } from '../combo.js';
import { drawLucky, LUCKY_BASE } from '../lucky.js';
import { getConfig } from '../services/app_config.js';
import { featuresFor, minLevelFor, wipLabel } from '../services/wip.js';

export const router = Router();
router.use(requireAuth);

// single: tek kişi · equal/random/selected: adet kişiler arasında bölünür · each: seçilen HER kişiye tam adet
// all_mic: mikrofondaki herkese (kendin hariç) tam adet · all_room: odadaki herkese (kendin hariç) tam adet
const DISTRIBUTIONS = ['single', 'equal', 'random', 'selected', 'each', 'all_mic', 'all_room'];
const MAX_BULK_RECIPIENTS = 50;
const giftJson = (g) => ({
  id: g.id, name: g.name, coinPrice: String(g.coin_price), iconUrl: g.icon_url, animationUrl: g.animation_url,
  animationFormat: g.animation_format, hasAlpha: g.has_alpha, category: g.category ?? 'popular',
});

router.get('/gifts', async (req, res) => {
  const r = await query(`SELECT * FROM gifts WHERE is_active = TRUE ORDER BY coin_price`);
  const cfg = await getConfig();
  // Şanslı hediyeler kapalıyken sekme hiç görünmez.
  const rows = cfg.luckyEnabled ? r.rows : r.rows.filter((g) => g.category !== 'lucky');
  res.json({
    gifts: rows.map(giftJson), globalMinCoins: String(config.globalGiftMinCoins),
    lucky: { enabled: cfg.luckyEnabled, receiverBps: cfg.luckyReceiverBps, multipliers: LUCKY_BASE.map(([m]) => m) },
  });
});

// Uygulama açılışında şeridi doldurmak için son global hediyeler.
router.get('/gifts/global/recent', async (req, res) => {
  const r = await query(
    `SELECT e.id, e.coin_amount, e.display_level, e.created_at, e.sender_id, e.receiver_id, e.room_id,
            g.name AS gift_name, g.icon_url, g.animation_url, g.animation_format, gt.quantity
     FROM global_gift_events e
     JOIN gift_transactions gt ON gt.id = e.gift_transaction_id
     JOIN gifts g ON g.id = gt.gift_id
     WHERE e.created_at > NOW() - INTERVAL '10 minutes' ORDER BY e.created_at DESC LIMIT 20`,
  );
  const ids = [...new Set(r.rows.flatMap((x) => [x.sender_id, x.receiver_id]))];
  const users = new Map((await loadPublicRows(ids)).map((u) => [u.id, u]));
  res.json({
    events: r.rows.map((x) => ({
      id: x.id, roomId: x.room_id, coinAmount: String(x.coin_amount), displayLevel: x.display_level, quantity: x.quantity, createdAt: x.created_at,
      gift: { name: x.gift_name, iconUrl: x.icon_url, animationUrl: x.animation_url, animationFormat: x.animation_format },
      sender: publicUser(users.get(x.sender_id)), receiver: publicUser(users.get(x.receiver_id)),
    })),
  });
});

// Hediye gönderimi: tek PostgreSQL işlemi. Kendine hediye serbesttir (gönderen alıcı olabilir):
//  - Coin düşer, Diamond artar (muhasebe kaydı tutulur).
//  - Kendine hediye; ajans/maaş hesabına, PK puanına ve liderlik tablolarına SAYILMAZ (suistimali önlemek için).
router.post('/rooms/:roomId/gifts/send', userLimit('gift', 60, 60e3), idempotent('gift_send'), async (req, res) => {
  const roomId = uuid(req.params.roomId, 'Oda');
  const giftId = uuid(req.body?.giftId, 'Hediye');
  const quantity = positiveInt(req.body?.quantity ?? 1, 'Hediye adedi', 10000);
  const distribution = oneOf(req.body?.distribution ?? 'single', DISTRIBUTIONS, 'Dağıtım tipi');
  const recipientId = distribution === 'single' ? uuid(req.body?.recipientId, 'Alıcı') : null;
  const selectedUserIds = distribution === 'selected' ? uuidArray(req.body?.selectedUserIds, 'Seçilen kullanıcılar', 20) : [];
  const eachIds = distribution === 'each' ? uuidArray(req.body?.recipientIds, 'Alıcılar', MAX_BULK_RECIPIENTS) : [];
  if (distribution === 'each' && !eachIds.length) throw fail('En az bir alıcı seçin.');
  const senderId = req.user.id;
  // Ayarlar işlem dışında okunur (önbellek süresi dolduysa havuzdan bağlantı ister; işlem içinde beklemek kilitlenmeye yol açar).
  const cfg = await getConfig();
  // Şanslı hediye değerleri çekiliş anında da sınırlanır (panel denetimini aşan/bozuk değerlere karşı): RTP + alıcı payı ≤ %95.
  const luckyRecvBps = Math.min(Math.max(Math.trunc(Number(cfg.luckyReceiverBps)) || 0, 0), 5000);
  const luckyRtpBps = Math.min(Math.max(Math.trunc(Number(cfg.luckyRtpBps)) || 0, 0), 9500 - luckyRecvBps);
  const luckyMaxWin = BigInt(Math.max(Math.trunc(Number(cfg.luckyMaxWin)) || 1, 1));

  const result = await tx(async (c) => {
    const room = (await c.query(`SELECT id, is_hidden FROM rooms WHERE id = $1 AND is_active = TRUE`, [roomId])).rows[0];
    if (!room) throw fail('Oda bulunamadı.', 404);
    const gift = (await c.query(`SELECT * FROM gifts WHERE id = $1 AND is_active = TRUE`, [giftId])).rows[0];
    if (!gift) throw fail('Hediye bulunamadı.', 404);
    // Vip sekmesindeki hediyeler WIP ayrıcalığıdır.
    if (gift.category === 'vip' && !(await featuresFor(senderId, (t, p) => c.query(t, p))).vipGifts) {
      const lvl = await minLevelFor('vipGifts', (t, p) => c.query(t, p));
      throw fail(`Vip hediyeleri ${lvl ? `${wipLabel(lvl)} ve üzeri` : 'WIP'} üyelere özeldir.`, 403);
    }
    const lucky = gift.category === 'lucky';
    if (lucky && cfg.luckyEnabled === false) throw fail('Şanslı hediyeler şu an kapalı.', 403);
    // Şanslı hediyede alıcıya hediye değerinin bir payı Elmas olarak geçer (geri kalanı gönderenin şans havuzudur).
    const creditOf = (coinAmount) => (lucky ? (coinAmount * BigInt(luckyRecvBps)) / 10000n : coinAmount);

    // Hayalet (SWIP) dinleyiciler toplu hediyelerde alıcı olmaz (mikrofondaysa olur).
    const members = (await c.query(
      `SELECT rm.user_id, rm.microphone FROM room_members rm
       JOIN users u ON u.id = rm.user_id AND u.account_status = 'active'
       WHERE rm.room_id = $1 AND (rm.microphone OR rm.user_id = $2 OR NOT is_ghost(rm.user_id))`,
      [roomId, senderId],
    )).rows;
    if (!members.some((m) => m.user_id === senderId)) throw fail('Hediye göndermek için odada olmalısınız.', 403);

    let allocation;
    if (distribution === 'single') {
      if (!members.some((m) => m.user_id === recipientId)) throw fail('Alıcı odada değil.');
      allocation = [{ userId: recipientId, quantity }];
    } else if (distribution === 'each') {
      const inRoom = new Set(members.map((m) => m.user_id));
      if (!eachIds.every((id) => inRoom.has(id))) throw fail('Seçilen alıcılardan biri odada değil.');
      allocation = eachIds.map((userId) => ({ userId, quantity }));
    } else if (distribution === 'all_mic' || distribution === 'all_room') {
      const targets = members.filter((m) => m.user_id !== senderId && (distribution === 'all_room' || m.microphone === true));
      if (!targets.length) throw fail(distribution === 'all_mic' ? 'Mikrofonda başka kimse yok.' : 'Odada başka kimse yok.');
      if (targets.length > MAX_BULK_RECIPIENTS) throw fail(`Toplu hediye en fazla ${MAX_BULK_RECIPIENTS} kişiye gönderilebilir.`);
      allocation = targets.map((m) => ({ userId: m.user_id, quantity }));
    } else {
      allocation = distributeGift(members, quantity, distribution, selectedUserIds);
    }

    // Toplam tutar, dağıtılan toplam adede göre hesaplanır (bölünen modlarda = adet, "herkese" modlarında = adet × kişi).
    const totalUnits = allocation.reduce((s, a) => s + BigInt(a.quantity), 0n);
    const totalCoins = BigInt(gift.coin_price) * totalUnits;
    // Kilitlenmeyi (deadlock) önlemek için ilgili tüm kullanıcı satırları TEK sorguda, sıralı kilitlenir.
    const lockIds = [...new Set([senderId, ...allocation.map((a) => a.userId)])];
    const locked = (await c.query(`SELECT id, coins FROM users WHERE id = ANY($1::uuid[]) ORDER BY id FOR UPDATE`, [lockIds])).rows;
    const senderRow = locked.find((u) => u.id === senderId);
    if (!senderRow || BigInt(senderRow.coins) < totalCoins) throw fail('Yetersiz Coin.');

    const sent = (await c.query(
      `UPDATE users SET coins = coins - $1, total_sent_coins = total_sent_coins + $1, updated_at = NOW()
       WHERE id = $2 RETURNING coins, total_sent_coins`,
      [totalCoins.toString(), senderId],
    )).rows[0];
    await c.query(`UPDATE users SET coin_level = $1 WHERE id = $2`, [levelFromExp(sent.total_sent_coins), senderId]);

    const pkIds = new Set();
    const transactions = [];
    const qualifying = [];
    for (const item of allocation) {
      const coinAmount = BigInt(gift.coin_price) * BigInt(item.quantity);
      const credit = creditOf(coinAmount); // alıcıya geçen Elmas (normal hediyede = coinAmount)
      const recv = (await c.query(
        `UPDATE users SET diamonds = diamonds + $1, total_received_diamonds = total_received_diamonds + $1, updated_at = NOW()
         WHERE id = $2 RETURNING total_received_diamonds`,
        [credit.toString(), item.userId],
      )).rows[0];
      await c.query(`UPDATE users SET gift_level = $1 WHERE id = $2`, [levelFromExp(recv.total_received_diamonds), item.userId]);

      const gt = (await c.query(
        `INSERT INTO gift_transactions(room_id, sender_id, receiver_id, gift_id, quantity, coin_amount, diamond_amount, receiver_agency_id)
         VALUES($1,$2,$3,$4,$5,$6,$7,(SELECT b.agency_id FROM broadcasters b JOIN agencies a ON a.id = b.agency_id
                                   WHERE b.user_id = $3 AND b.status = 'approved' AND a.status = 'active')) RETURNING id`,
        [roomId, senderId, item.userId, gift.id, item.quantity, coinAmount.toString(), lucky ? credit.toString() : null],
      )).rows[0];
      // Oda içi sayı tahtası (mikrofon koltuğu başına toplam). Kendine hediye de tahtada görünür.
      await c.query(
        `INSERT INTO room_gift_totals(room_id, user_id, total_coins, total_count) VALUES($1,$2,$3,$4)
         ON CONFLICT (room_id, user_id) DO UPDATE SET total_coins = room_gift_totals.total_coins + EXCLUDED.total_coins,
           total_count = room_gift_totals.total_count + EXCLUDED.total_count, updated_at = NOW()`,
        [roomId, item.userId, credit.toString(), item.quantity],
      );
      const pkId = await scorePk(c, roomId, item.userId, senderId, credit, coinAmount);
      if (pkId) pkIds.add(pkId);
      await c.query(
        `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, reference_id, description) VALUES($1,'gift_sent',$2,$3,$4)`,
        [senderId, (-coinAmount).toString(), gt.id, `Hediye: ${gift.name} x${item.quantity}`],
      );
      if (credit > 0n) {
        await c.query(
          `INSERT INTO wallet_transactions(user_id, transaction_type, diamond_amount, reference_id, description) VALUES($1,'gift_received',$2,$3,$4)`,
          [item.userId, credit.toString(), gt.id, `Hediye: ${gift.name} x${item.quantity}`],
        );
      }

      // Aile puanı: alıcının ailesine.
      const fam = (await c.query(
        `UPDATE families SET total_points = total_points + $1
         WHERE is_active = TRUE AND id = (SELECT family_id FROM family_members WHERE user_id = $2) RETURNING id, total_points`,
        [credit.toString(), item.userId],
      )).rows[0];
      if (fam) await c.query(`UPDATE families SET level = $1 WHERE id = $2`, [familyLevelFor(fam.total_points), fam.id]);

      // Gizli odanın kimliği tüm kullanıcılara yayılmasın: global şerit/kayıt yalnızca açık odalarda.
      if (coinAmount >= config.globalGiftMinCoins && !room.is_hidden) {
        await c.query(
          `INSERT INTO global_gift_events(gift_transaction_id, room_id, sender_id, receiver_id, coin_amount, display_level)
           VALUES($1,$2,$3,$4,$5,$6)`,
          [gt.id, roomId, senderId, item.userId, coinAmount.toString(), giftDisplayLevel(coinAmount)],
        );
        qualifying.push({ userId: item.userId, coinAmount, quantity: item.quantity });
      }
      transactions.push({
        id: gt.id, receiverId: item.userId, quantity: item.quantity, coinAmount: coinAmount.toString(), diamondAmount: credit.toString(),
      });
    }

    // Şanslı hediye çekilişi: her adet ayrı çekiliş; kazanç = toplam çarpan × hediye fiyatı (tek gönderimde üst sınırlı).
    let luckyResult = null;
    let balance = sent.coins;
    if (lucky) {
      const draw = drawLucky(Number(totalUnits), luckyRtpBps);
      let win = BigInt(draw.multiplier) * BigInt(gift.coin_price);
      if (win > luckyMaxWin) win = luckyMaxWin;
      if (win > 0n) {
        balance = (await c.query(
          `UPDATE users SET coins = coins + $1, updated_at = NOW() WHERE id = $2 RETURNING coins`,
          [win.toString(), senderId],
        )).rows[0].coins;
        await c.query(
          `INSERT INTO wallet_transactions(user_id, transaction_type, coin_amount, reference_id, description) VALUES($1,'lucky_gift_win',$2,$3,$4)`,
          [senderId, win.toString(), transactions[0].id, `Şanslı hediye kazancı: ${gift.name} (en yüksek x${draw.best})`],
        );
      }
      luckyResult = { win: win.toString(), best: draw.best, hits: draw.hits };
    }
    return {
      gift, quantity, totalCoins, balance, transactions, qualifying, allocation, pkIds: [...pkIds], lucky: luckyResult,
      // Duyuru: hem çarpan yüksek hem tek isabetin değeri global hediye eşiğinin üstünde olmalı (10 Coin'lik çanla toplu
      // gönderimde her seferinde x100 çıkıp tüm uygulamaya şerit düşmesin).
      announce: lucky && !room.is_hidden && luckyResult.best >= cfg.luckyAnnounceMultiplier
        && BigInt(luckyResult.best) * BigInt(gift.coin_price) >= BigInt(config.globalGiftMinCoins),
    };
  });

  // ---- Olaylar (işlem başarıyla bittikten sonra) ----
  // Para hareketi tamamlandı: buradan sonraki bir veritabanı hatası 500 döndürmesin (istemci tekrar dener ve iki kez öder).
  let userRows = [];
  try {
    userRows = await loadPublicRows([...new Set([senderId, ...result.allocation.map((a) => a.userId)])]);
  } catch (e) {
    console.error('Hediye sonrası kullanıcı bilgisi alınamadı:', e.message);
  }
  const byId = new Map(userRows.map((u) => [u.id, u]));
  const giftInfo = {
    id: result.gift.id, name: result.gift.name, iconUrl: result.gift.icon_url, animationUrl: result.gift.animation_url,
    animationFormat: result.gift.animation_format, category: result.gift.category,
  };
  const sender = publicUser(byId.get(senderId));
  const receivers = result.transactions.map((t) => ({
    user: publicUser(byId.get(t.receiverId)), quantity: t.quantity, coinAmount: t.coinAmount,
  }));

  // Combo (Yoho): aynı kişiye aynı hediye birkaç saniye içinde tekrar gönderilirse sayaç artar (x2, x3 ...).
  const combo = nextCombo(`${roomId}|${senderId}|${giftId}|${distribution}|${result.allocation.map((a) => a.userId).sort().join(',')}`);
  hub.broadcastRoom(roomId, {
    type: 'room_gift', roomId, gift: giftInfo, quantity: result.quantity, totalCoins: result.totalCoins.toString(), sender, receivers, combo,
    lucky: result.lucky,
  });
  // Büyük şanslı kazanç tüm uygulamaya duyurulur (Yoho "çan" şeridi).
  if (result.announce) {
    hub.broadcastGlobal({
      type: 'lucky_gift_win', roomId, gift: giftInfo, sender, multiplier: result.lucky.best, win: result.lucky.win,
    });
  }

  scoreboardOf(roomId).then((scoreboard) => hub.broadcastRoom(roomId, { type: 'room_scoreboard', roomId, scoreboard })).catch(() => {});
  for (const id of result.pkIds) {
    pkView(id).then((pk) => {
      if (!pk) return;
      hub.broadcastRoom(pk.a.roomId, { type: 'pk_state', pk });
      hub.broadcastRoom(pk.b.roomId, { type: 'pk_state', pk });
    }).catch(() => {});
  }

  let ribbon = null;
  if (result.qualifying.length) {
    const q = result.qualifying;
    ribbon = {
      type: 'global_gift_ribbon', roomId, gift: giftInfo,
      quantity: q.reduce((s, x) => s + x.quantity, 0),
      totalCoins: q.reduce((s, x) => s + x.coinAmount, 0n).toString(),
      sender,
      receivers: q.map((x) => publicUser(byId.get(x.userId))),
    };
    hub.broadcastGlobal(ribbon);
  }

  noteTask(senderId, 'gift');
  res.json({
    gift: giftJson(result.gift), quantity: result.quantity, totalCoins: result.totalCoins.toString(),
    balance: String(result.balance), transactions: result.transactions, ribbon, combo, lucky: result.lucky,
  });
});
