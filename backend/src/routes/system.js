import { Router } from 'express';
import { query } from '../database.js';
import { optionalAuth } from '../auth.js';
import { ipLimit } from '../firewall.js';
import { getConfig } from '../services/app_config.js';

export const router = Router();

// Uygulama açılışında okunur: zorunlu/isteğe bağlı güncelleme bilgisi. Giriş gerektirmez.
router.get('/app/config', async (_req, res) => {
  const c = await getConfig();
  res.json({ minAppVersion: c.minAppVersion, latestAppVersion: c.latestAppVersion, updateUrl: c.updateUrl || null, updateMessage: c.updateMessage });
});

// Telefon bildirimleri (yönetimden herkese): uygulama açılınca / öne gelince buradan kaçırdıklarını sorar.
// Herkese açık duyuru olduğu için giriş gerektirmez. [after]: telefonda gösterilen son bildirimin numarası.
router.get('/push/latest', ipLimit('push_poll', 2000, 3600e3), async (req, res) => {
  const after = Number.parseInt(String(req.query.after ?? '0'), 10);
  const r = await query(
    `SELECT id, title, body, created_at FROM push_messages
     WHERE id > $1 AND created_at > NOW() - INTERVAL '3 days' ORDER BY id DESC LIMIT 5`,
    [Number.isFinite(after) && after > 0 ? after : 0],
  );
  const last = (await query(`SELECT COALESCE(MAX(id), 0)::bigint AS id FROM push_messages`)).rows[0].id;
  res.json({ lastId: String(last), messages: r.rows.reverse().map((x) => ({ id: String(x.id), title: x.title, body: x.body, createdAt: x.created_at })) });
});

const clip = (v, max) => (typeof v === 'string' ? v.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '').slice(0, max) : null);
let inserts = 0;

// Telefonda yakalanan hatalar (çökme yerine yakalanan istisnalar) yönetim paneline düşer.
// Giriş ekranındaki hatalar da gönderilebilsin diye oturum zorunlu değildir; IP başına sınırlıdır.
router.post('/client-errors', ipLimit('client_errors', 30, 3600e3), optionalAuth, async (req, res) => {
  const list = Array.isArray(req.body?.errors) ? req.body.errors.slice(0, 20) : [];
  const appVersion = clip(req.body?.appVersion, 20);
  const device = clip(req.body?.device, 80);
  let n = 0;
  for (const e of list) {
    const source = clip(e?.source, 80);
    const message = clip(e?.message, 1000);
    if (!source || !message) continue;
    // Telefon saati bozuk olabilir: makul aralık dışındaki tarih yok sayılır (veritabanı hatası yerine).
    const ms = typeof e?.at === 'string' ? Date.parse(e.at) : NaN;
    const at = Number.isFinite(ms) && ms > Date.UTC(2020, 0, 1) && ms < Date.now() + 86400e3 ? new Date(ms) : null;
    await query(
      `INSERT INTO client_errors(user_id, app_version, device, source, message, stack, occurred_at) VALUES($1,$2,$3,$4,$5,$6,$7)`,
      [req.user?.id ?? null, appVersion, device, source, message, clip(e?.stack, 2000), at],
    );
    n += 1;
  }
  // Tablo sınırsız büyümesin: ara sıra 30 günden eski kayıtlar ve son 5000 dışındakiler silinir.
  inserts += n;
  if (inserts >= 200) {
    inserts = 0;
    query(
      `DELETE FROM client_errors WHERE created_at < NOW() - INTERVAL '30 days'
         OR id < (SELECT COALESCE(MIN(id), 0) FROM (SELECT id FROM client_errors ORDER BY id DESC LIMIT 5000) t)`,
    ).catch(() => {});
  }
  res.json({ ok: true, saved: n });
});
