import crypto from 'node:crypto';
import { Router } from 'express';
import { query, tx } from '../database.js';
import { fail } from '../http.js';
import { ipLimit, logSecurityEvent, clientIp } from '../firewall.js';
import { publicTextProblem } from '../safe_text.js';
import { selfUser } from '../views.js';
import { tokensFor, createAccount, checkAccount } from './auth.js';

/**
 * Google ve Facebook ile giriş (SDK'sız, tarayıcı üzerinden):
 *  1. Uygulama rastgele bir "poll" sırrı üretir, /oauth/start ile giriş adresini alır ve tarayıcıda açar.
 *  2. Kullanıcı Google/Facebook'ta onay verir; sağlayıcı /oauth/:provider/callback adresine döner.
 *  3. Sunucu kodu sağlayıcıyla doğrular, hesabı bulur ya da açar ve girişi "tamamlandı" olarak işaretler.
 *  4. Uygulama /oauth/poll ile (state + poll sırrı) sonucu alır. Sırrı yalnızca uygulama bildiği için tarayıcı
 *     adresini gören biri oturumu alamaz.
 * Ayarlar (Render ortam değişkenleri): GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, FACEBOOK_APP_ID, FACEBOOK_APP_SECRET,
 * PUBLIC_BASE_URL (ör. https://tr-live-1.onrender.com). Biri eksikse o yöntem uygulamada görünmez.
 */
export const router = Router();

const env = process.env;
const FB_VERSION = env.FACEBOOK_API_VERSION || 'v23.0';
const ANDROID_PACKAGE = env.ANDROID_PACKAGE || 'com.trlive.tr_live';
const STATE_RE = /^[A-Za-z0-9_-]{32,64}$/;
const POLL_RE = /^[A-Za-z0-9_-]{32,128}$/;

const PROVIDERS = {
  google: {
    enabled: () => Boolean(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET),
    authUrl: (redirect, state) => `https://accounts.google.com/o/oauth2/v2/auth?${new URLSearchParams({
      client_id: env.GOOGLE_CLIENT_ID, redirect_uri: redirect, response_type: 'code', scope: 'openid email profile',
      state, prompt: 'select_account', access_type: 'online',
    })}`,
    async profile(code, redirect) {
      const r = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ code, client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET, redirect_uri: redirect, grant_type: 'authorization_code' }),
        signal: AbortSignal.timeout(15000),
      });
      const j = await r.json().catch(() => ({}));
      if (!r.ok || !j.id_token) throw new Error(`Google yanıtı: ${j.error_description || j.error || r.status}`);
      // Kimlik belgesi doğrudan Google'ın sunucusundan (TLS) alındı; alanları yine de denetlenir.
      const p = JSON.parse(Buffer.from(String(j.id_token).split('.')[1] || '', 'base64url').toString('utf8'));
      if (p.aud !== env.GOOGLE_CLIENT_ID || !['accounts.google.com', 'https://accounts.google.com'].includes(p.iss)) throw new Error('Google kimliği doğrulanamadı.');
      if (!p.sub) throw new Error('Google hesabı okunamadı.');
      return { subject: String(p.sub), email: p.email_verified ? p.email : null, name: p.name || p.given_name || null };
    },
  },
  facebook: {
    enabled: () => Boolean(env.FACEBOOK_APP_ID && env.FACEBOOK_APP_SECRET),
    authUrl: (redirect, state) => `https://www.facebook.com/${FB_VERSION}/dialog/oauth?${new URLSearchParams({
      client_id: env.FACEBOOK_APP_ID, redirect_uri: redirect, state, scope: 'public_profile,email', response_type: 'code',
    })}`,
    async profile(code, redirect) {
      const t = await fetch(`https://graph.facebook.com/${FB_VERSION}/oauth/access_token?${new URLSearchParams({
        client_id: env.FACEBOOK_APP_ID, client_secret: env.FACEBOOK_APP_SECRET, redirect_uri: redirect, code,
      })}`, { signal: AbortSignal.timeout(15000) });
      const tj = await t.json().catch(() => ({}));
      if (!t.ok || !tj.access_token) throw new Error(`Facebook yanıtı: ${tj.error?.message || t.status}`);
      const proof = crypto.createHmac('sha256', env.FACEBOOK_APP_SECRET).update(tj.access_token).digest('hex');
      const m = await fetch(`https://graph.facebook.com/${FB_VERSION}/me?${new URLSearchParams({
        fields: 'id,name,email', access_token: tj.access_token, appsecret_proof: proof,
      })}`, { signal: AbortSignal.timeout(15000) });
      const mj = await m.json().catch(() => ({}));
      if (!m.ok || !mj.id) throw new Error(`Facebook hesabı okunamadı: ${mj.error?.message || m.status}`);
      return { subject: String(mj.id), email: mj.email || null, name: mj.name || null };
    },
  },
};

const baseUrl = (req) => (env.PUBLIC_BASE_URL || `https://${req.get('host')}`).replace(/\/+$/, '');
const redirectUri = (req, provider) => `${baseUrl(req)}/api/auth/oauth/${provider}/callback`;
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');

/** Uygulamada hangi giriş düğmeleri gösterilsin. */
router.get('/providers', (_req, res) => {
  res.json({ google: PROVIDERS.google.enabled(), facebook: PROVIDERS.facebook.enabled(), phone: true });
});

router.post('/oauth/start', ipLimit('oauth_start', 30, 15 * 60e3), async (req, res) => {
  const name = String(req.body?.provider ?? '');
  const p = Object.hasOwn(PROVIDERS, name) ? PROVIDERS[name] : null;
  if (!p) throw fail('Geçersiz giriş yöntemi.');
  if (!p.enabled()) throw fail('Bu giriş yöntemi henüz açılmadı.', 503);
  const poll = String(req.body?.poll ?? '');
  if (!POLL_RE.test(poll)) throw fail('Geçersiz istek.');
  const state = crypto.randomBytes(24).toString('base64url');
  await query(`INSERT INTO oauth_states(state, poll_hash, provider) VALUES($1,$2,$3)`, [state, sha(poll), name]);
  // Eski kayıtlar temizlenir (arka planda).
  query(`DELETE FROM oauth_states WHERE expires_at < NOW() - INTERVAL '1 hour'`).catch(() => {});
  res.json({ state, url: p.authUrl(redirectUri(req, name), state) });
});

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function page(res, ok, message, state = null, code = null) {
  // Uygulamaya dönüş bağlantısı (trlive://login/auth?state=…&code=…); uygulama yüklü değilse Android sayfada kalır.
  const q = new URLSearchParams({ ...(state ? { state } : {}), ...(code ? { code } : {}) }).toString();
  const open = `intent://login/auth${q ? `?${q}` : ''}#Intent;scheme=trlive;package=${ANDROID_PACKAGE};end`;
  res.set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'");
  res.type('html').send(`<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TR Live</title><style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0b1220;color:#fff;font-family:system-ui,sans-serif;text-align:center}
.c{padding:28px}.i{font-size:56px}h1{font-size:20px;margin:12px 0 8px}p{color:#9ca3af;font-size:15px;line-height:1.4}
a{display:inline-block;margin-top:18px;padding:13px 26px;border-radius:24px;background:${ok ? '#22d3ee' : '#f43f5e'};color:#06202a;font-weight:800;text-decoration:none}</style></head>
<body><div class="c"><div class="i">${ok ? '✅' : '⚠️'}</div><h1>${ok ? 'Giriş tamamlandı' : 'Giriş yapılamadı'}</h1><p>${esc(message)}</p>
<a href="${esc(open)}">TR Live'a dön</a></div>${ok ? `<script>setTimeout(function(){location.href=${JSON.stringify(open)}},400)</script>` : ''}</body></html>`);
}

router.get('/oauth/:provider/callback', ipLimit('oauth_cb', 60, 15 * 60e3), async (req, res) => {
  const name = String(req.params.provider);
  const p = Object.hasOwn(PROVIDERS, name) ? PROVIDERS[name] : null;
  const state = String(req.query.state ?? '');
  if (!p || !STATE_RE.test(state)) return page(res, false, 'Geçersiz bağlantı. Uygulamaya dönüp tekrar deneyin.');
  const st = (await query(`SELECT * FROM oauth_states WHERE state = $1 AND provider = $2`, [state, name])).rows[0];
  if (!st || st.status !== 'pending' || new Date(st.expires_at) < new Date()) {
    return page(res, false, 'Bu giriş isteğinin süresi doldu. Uygulamaya dönüp tekrar deneyin.');
  }
  const failState = async (msg) => {
    await query(`UPDATE oauth_states SET status = 'error', error = $2 WHERE state = $1 AND status = 'pending'`, [state, msg]);
    return page(res, false, msg, state);
  };
  if (req.query.error || !req.query.code) return failState('Giriş iptal edildi.');
  let prof;
  try {
    prof = await p.profile(String(req.query.code), redirectUri(req, name));
  } catch (e) {
    console.error(`[oauth] ${name}:`, e.message);
    return failState('Hesap doğrulanamadı. Lütfen tekrar deneyin.');
  }
  try {
    const user = await tx(async (c) => {
      const run = (sql, params) => c.query(sql, params);
      const found = (await c.query(
        `SELECT u.* FROM user_identities i JOIN users u ON u.id = i.user_id WHERE i.provider = $1 AND i.subject = $2`,
        [name, prof.subject],
      )).rows[0];
      if (found) return found;
      // İlk giriş: yeni hesap. Ad uygunsuzsa (küfür vb.) varsayılan ad verilir; profilden değiştirilebilir.
      let displayName = String(prof.name ?? '').trim().slice(0, 60);
      if (!displayName || publicTextProblem(displayName)) displayName = 'TR Live Kullanıcısı';
      const row = await createAccount({ displayName, prefix: name === 'google' ? 'g' : 'f' }, run, true);
      await c.query(`INSERT INTO user_identities(provider, subject, user_id, email) VALUES($1,$2,$3,$4)`, [name, prof.subject, row.id, prof.email]);
      return row;
    });
    // Tek kullanımlık kod yalnızca bu tarayıcıdaki "uygulamaya dön" bağlantısıyla telefondaki uygulamaya gider.
    // Oturum, kodu ve girişi başlatan uygulamanın sırrını birlikte gösterene verilir: başkasına giriş bağlantısı
    // gönderip onun hesabını ele geçirme (oltalama) böylece işe yaramaz.
    const code = crypto.randomBytes(24).toString('base64url');
    const upd = await query(
      `UPDATE oauth_states SET status = 'done', user_id = $2, code_hash = $3 WHERE state = $1 AND status = 'pending'`,
      [state, user.id, sha(code)],
    );
    if (!upd.rowCount) return page(res, false, 'Bu giriş isteği zaten kullanıldı. Uygulamaya dönüp tekrar deneyin.');
    return page(res, true, 'Uygulama açılmazsa aşağıdaki "TR Live\'a dön" düğmesine dokunun.', state, code);
  } catch (e) {
    console.error(`[oauth] ${name} hesap:`, e.message);
    return failState('Hesap açılamadı. Lütfen tekrar deneyin.');
  }
});

// Uygulama sonucu birkaç saniyede bir sorar. Tamamlandıysa oturum bir kez verilir ve istek silinir.
router.post('/oauth/poll', ipLimit('oauth_poll', 400, 15 * 60e3), async (req, res) => {
  const state = String(req.body?.state ?? '');
  const poll = String(req.body?.poll ?? '');
  if (!STATE_RE.test(state) || !POLL_RE.test(poll)) throw fail('Geçersiz istek.');
  const st = (await query(`SELECT * FROM oauth_states WHERE state = $1 AND poll_hash = $2`, [state, sha(poll)])).rows[0];
  if (!st || new Date(st.expires_at) < new Date()) return res.json({ status: 'expired' });
  if (st.status === 'pending') return res.json({ status: 'pending' });
  if (st.status === 'error') {
    await query(`DELETE FROM oauth_states WHERE state = $1`, [state]);
    return res.json({ status: 'error', message: st.error || 'Giriş yapılamadı.' });
  }
  // Tamamlandı: oturum yalnızca tarayıcıdan uygulamaya gelen tek kullanımlık kodla verilir.
  const code = String(req.body?.code ?? '');
  if (!code) return res.json({ status: 'waiting_app' });
  if (!POLL_RE.test(code) || sha(code) !== st.code_hash) throw fail('Geçersiz giriş kodu.', 403);
  const user = (await query(`SELECT * FROM users WHERE id = $1`, [st.user_id])).rows[0];
  let acct;
  try {
    acct = user ? await checkAccount(user) : null;
  } catch (e) {
    await query(`DELETE FROM oauth_states WHERE state = $1`, [state]);
    return res.json({ status: 'error', message: e.message });
  }
  // Tek kullanımlık: aynı sonuç ikinci kez alınamaz.
  const del = await query(`DELETE FROM oauth_states WHERE state = $1 AND status = 'done'`, [state]);
  if (!del.rowCount || !acct) return res.json({ status: 'expired' });
  logSecurityEvent('oauth_login', clientIp(req), acct.id, { provider: st.provider });
  res.json({ status: 'done', ...(await tokensFor(acct, req)), user: selfUser(acct) });
});
