import { Router } from 'express';
import { query } from '../database.js';
import { optionalAuth } from '../auth.js';
import { ipLimit } from '../firewall.js';
import { getConfig } from '../services/app_config.js';

export const router = Router();

// Uygulama açılışında okunur: zorunlu/isteğe bağlı güncelleme bilgisi. Giriş gerektirmez.
router.get('/app/config', async (_req, res) => {
  const c = await getConfig();
  res.json({
    minAppVersion: c.minAppVersion, latestAppVersion: c.latestAppVersion, updateUrl: c.updateUrl || null, updateMessage: c.updateMessage,
    roomNotice: c.roomNotice || '', flyTextCoins: c.flyTextCoins,
  });
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

// Google / Facebook giriş ayarlarında istenen herkese açık sayfalar: gizlilik politikası ve veri silme.
function legalPage(res, title, body) {
  res.set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'");
  res.type('html').send(`<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TR Live – ${title}</title><style>body{max-width:760px;margin:0 auto;padding:24px 18px;font-family:system-ui,sans-serif;line-height:1.55;color:#111}
h1{font-size:24px}h2{font-size:18px;margin-top:22px}</style></head><body><h1>TR Live – ${title}</h1>${body}</body></html>`);
}

router.get('/legal/privacy', (_req, res) => legalPage(res, 'Gizlilik Politikası', `
<p>TR Live, sesli/görüntülü sohbet odaları sunan bir mobil uygulamadır. Bu sayfa hangi verileri neden işlediğimizi açıklar.</p>
<h2>Topladığımız bilgiler</h2>
<ul>
<li><b>Hesap bilgileri:</b> görünen ad, profil fotoğrafı ve isteğe bağlı profil alanları. Telefonla kayıtta telefon numaranız.
Google veya Facebook ile girişte yalnızca hesap kimliğiniz, adınız ve (varsa) e-posta adresiniz alınır; şifreniz bize gelmez.</li>
<li><b>Kullanım bilgileri:</b> odalara giriş-çıkış, gönderdiğiniz mesajlar ve hediyeler, cihaz modeli ve uygulama sürümü
(güvenlik ve hata ayıklama için).</li>
<li>Sesli/görüntülü sohbet anlık iletilir; kaydedilmez.</li>
</ul>
<h2>Kullanım amacı</h2>
<p>Hesabınızı oluşturmak ve korumak, uygulama özelliklerini sunmak, kötüye kullanımı (dolandırıcılık, taciz, spam) önlemek ve
yasal yükümlülükleri yerine getirmek. Verileriniz satılmaz ve reklam amacıyla paylaşılmaz.</p>
<h2>Saklama ve silme</h2>
<p>Hesabınızı uygulamadan dilediğiniz zaman silebilirsiniz (Profil → Ayarlar → Hesabı sil). Silindiğinde kişisel bilgileriniz,
gönderileriniz, fotoğraflarınız ve Google/Facebook bağlantınız kaldırılır; yasal zorunluluk gereği tutulması gereken işlem
kayıtları (ör. ödeme kayıtları) süresi boyunca saklanır.</p>
<h2>İletişim</h2>
<p>Sorularınız ve KVKK kapsamındaki talepleriniz için uygulama içindeki Destek bölümünü kullanabilirsiniz.</p>`));

router.get('/legal/data-deletion', (_req, res) => legalPage(res, 'Veri Silme', `
<p>TR Live hesabınızı ve kişisel verilerinizi şu şekilde silebilirsiniz:</p>
<ol>
<li>TR Live uygulamasını açın ve giriş yapın.</li>
<li><b>Profil → Ayarlar → Hesabı sil</b> adımlarını izleyin.</li>
<li>Şifreniz varsa şifrenizi, Google/Facebook ile açılan hesaplarda onay için <b>SİL</b> yazın.</li>
</ol>
<p>Hesap silindiğinde profiliniz, gönderileriniz, yüklediğiniz fotoğraflar ve Facebook/Google bağlantınız kaldırılır.
Uygulamaya erişemiyorsanız, uygulama içi Destek bölümünden ya da bu uygulamayı yayınlayan hesap üzerinden bize ulaşın.</p>`));
