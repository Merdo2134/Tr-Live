// TR Live sunucu paneli (https://ALAN-ADI/panel). Telefondan tarayıcıyla açılır; şifre kurulumda verilen PANEL_PASSWORD.
// Yapabildikleri: durum, ayarlar (Google/Facebook anahtarları vb.), eski veritabanını aktarma, şimdi güncelle.
// Ek paket gerektirmez (Node + PostgreSQL araçları).
import http from 'node:http';
import fs from 'node:fs';
import crypto from 'node:crypto';
import { execFile } from 'node:child_process';

const PORT = 8090;
const ENV_DIR = '/data/env';
const STATE = '/data/state';
const PASSWORD = process.env.PANEL_PASSWORD || '';
const DB = process.env.DATABASE_URL;
const DOMAIN = () => readText(`${ENV_DIR}/domain`).trim() || process.env.DOMAIN || '';
const SSLIP = () => readText(`${ENV_DIR}/sslip`).trim();

// Panelden değiştirilebilen ayarlar (sunucuya ortam değişkeni olarak geçer).
const KEYS = [
  ['GOOGLE_CLIENT_ID', 'Google Client ID', false],
  ['GOOGLE_CLIENT_SECRET', 'Google Client secret', true],
  ['FACEBOOK_APP_ID', 'Facebook App ID', false],
  ['FACEBOOK_APP_SECRET', 'Facebook App Secret', true],
  ['ADMIN_USERNAMES', 'Yönetici kullanıcı adları (virgülle)', false],
  ['GLOBAL_GIFT_MIN_COINS', 'Global hediye şeridi alt sınırı (Coin)', false],
  ['BANNED_WORDS', 'Yasaklı kelimeler (virgülle)', false],
  ['FIREWALL_ALLOW_IPS', 'Asla engellenmeyecek IP adresleri (virgülle)', false],
];

function readText(f) {
  try { return fs.readFileSync(f, 'utf8'); } catch { return ''; }
}
function readEnv(f) {
  const out = {};
  for (const line of readText(f).split('\n')) {
    const i = line.indexOf('=');
    if (i <= 0) continue;
    let v = line.slice(i + 1);
    if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) v = v.slice(1, -1);
    out[line.slice(0, i).trim()] = v;
  }
  return out;
}
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const touch = (name) => fs.writeFileSync(`${STATE}/${name}`, new Date().toISOString());

function psql(url, sql) {
  return new Promise((resolve) => {
    execFile('psql', [url, '-At', '-c', sql], { timeout: 20000 }, (err, stdout, stderr) => resolve(err ? { error: (stderr || err.message).trim() } : { out: stdout.trim() }));
  });
}

// ---- Giriş (HTTP Basic) + kaba kuvvet koruması ----
const fails = new Map();
setInterval(() => { const now = Date.now(); for (const [k, v] of fails) if (now - v.t > 15 * 60e3) fails.delete(k); }, 60e3).unref();
function authorized(req) {
  const ip = String(req.headers['x-forwarded-for'] || req.socket.remoteAddress).split(',')[0].trim();
  const f = fails.get(ip);
  if (f && f.n >= 8 && Date.now() - f.t < 15 * 60e3) return false;
  const h = String(req.headers.authorization || '');
  const given = h.startsWith('Basic ') ? Buffer.from(h.slice(6), 'base64').toString().split(':').slice(1).join(':') : null;
  if (given !== null && PASSWORD.length >= 10) {
    const a = crypto.createHash('sha256').update(given).digest();
    const b = crypto.createHash('sha256').update(PASSWORD).digest();
    if (crypto.timingSafeEqual(a, b)) { fails.delete(ip); return true; }
  }
  if (given !== null) fails.set(ip, { n: (f && Date.now() - f.t < 15 * 60e3 ? f.n : 0) + 1, t: Date.now() });
  return false;
}

function body(req) {
  return new Promise((resolve) => {
    let s = '';
    req.on('data', (c) => { s += c; if (s.length > 20000) req.destroy(); });
    req.on('end', () => resolve(new URLSearchParams(s)));
    req.on('close', () => resolve(new URLSearchParams(s)));
    req.on('error', () => resolve(new URLSearchParams('')));
  });
}

// ---- Eski veritabanını aktarma: istek dosyası yazılır, aktarmayı sunucu (import.sh) yapar ----
const importing = () => readText(`${STATE}/import.log`).trim() !== '' && !/Bitti\.\s*$/.test(readText(`${STATE}/import.log`));

// ---- Sayfa ----
async function page(msg = '') {
  const env = readEnv(`${ENV_DIR}/extra.env`);
  let health = 'kontrol edilemedi';
  try {
    const r = await fetch('http://backend:3000/health', { signal: AbortSignal.timeout(4000) });
    health = r.ok ? '✅ çalışıyor' : `⚠️ yanıt ${r.status}`;
  } catch { health = '❌ yanıt yok (yeni başlıyorsa 1-2 dk bekleyin)'; }
  const users = await psql(DB, 'SELECT COUNT(*) FROM users');
  const size = await psql(DB, 'SELECT pg_size_pretty(pg_database_size(current_database()))');
  const d = DOMAIN();
  const fields = KEYS.map(([k, label, secret]) => {
    const v = env[k] || '';
    return `<label>${esc(label)}<input name="${k}" ${secret ? 'type="password" placeholder="' + (v ? 'kayıtlı (değiştirmek için yazın)' : 'boş') + '"' : `value="${esc(v)}"`} autocomplete="off"></label>`;
  }).join('');
  const tail = (f, n) => esc(readText(`${STATE}/${f}`).split('\n').slice(-n).join('\n'));
  return `<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TR Live Sunucu</title><style>
body{margin:0;background:#0b1220;color:#e5e7eb;font-family:system-ui,sans-serif;font-size:15px}
main{max-width:640px;margin:0 auto;padding:16px}h1{font-size:22px}h2{font-size:17px;margin:0 0 10px}
section{background:#111a2e;border:1px solid #1f2a44;border-radius:14px;padding:14px;margin:14px 0}
label{display:block;margin:10px 0 4px;color:#9ca3af;font-size:13px}input{display:block;width:100%;box-sizing:border-box;margin-top:4px;padding:11px;border-radius:10px;border:1px solid #334155;background:#0b1220;color:#fff;font-size:15px}
button{margin-top:12px;width:100%;padding:13px;border:0;border-radius:12px;background:#22d3ee;color:#06202a;font-weight:800;font-size:15px}
button.red{background:#f43f5e;color:#fff}pre{white-space:pre-wrap;background:#0b1220;padding:10px;border-radius:10px;font-size:12px;max-height:260px;overflow:auto}
.ok{background:#14532d;padding:10px;border-radius:10px}code{background:#0b1220;padding:2px 6px;border-radius:6px;word-break:break-all}
</style></head><body><main>
<h1>TR Live Sunucu</h1>${msg ? `<p class="ok">${esc(msg)}</p>` : ''}
<section><h2>Durum</h2>
<p>Uygulama sunucusu: ${health}<br>Kullanıcı sayısı: ${esc(users.out ?? users.error)}<br>Veritabanı boyutu: ${esc(size.out ?? '-')}</p>
<p>Uygulama adresi (APK için): <code>https://${esc(d)}</code><br>LiveKit: <code>wss://lk.${esc(d)}</code></p>
<form method="post" action="/panel/update"><button>Şimdi güncelle (GitHub'daki son sürüm)</button></form>
<pre>${tail('update.log', 8) || 'Henüz güncelleme kaydı yok.'}</pre></section>

<section><h2>Ayarlar</h2><form method="post" action="/panel/env">${fields}
<label>Alan adı (değiştirmeyin; kendi alan adınızı aldıysanız yazın)<input name="DOMAIN" value="${esc(d)}"></label>
<button>Kaydet ve uygula</button></form></section>

<section><h2>Eski veritabanını aktar</h2>
<p>Render/Aiven'deki tüm veriler (kullanıcılar, odalar, bakiyeler, fotoğraflar) bu sunucuya kopyalanır (odaya yüklenen müzik dosyaları hariç). Aktarma sırasında uygulama birkaç dakika kapalı olur. <b>Bu sunucudaki mevcut veriler silinir.</b> Eski veritabanı değişmez.</p>
<form method="post" action="/panel/import">
<label>Eski veritabanı adresi (Render/Aiven'deki DATABASE_URL — dışarıdan erişilebilen "External" adres)<input name="old" type="password" autocomplete="off" placeholder="postgres://..."></label>
<label>Onay için AKTAR yazın<input name="confirm" autocomplete="off"></label>
<button class="red" ${importing() ? 'disabled' : ''}>${importing() ? 'Aktarılıyor…' : 'Verileri aktar'}</button></form>
<pre>${tail('import.log', 40) || 'Henüz aktarma yapılmadı.'}</pre></section>

<section><h2>Kurulum kaydı (son satırlar)</h2><pre>${tail('install.log', 25) || '-'}</pre></section>
</main></body></html>`;
}

const server = http.createServer((req, res) => {
  handle(req, res).catch((e) => {
    console.error('panel:', e);
    try { res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' }); res.end('Hata: ' + e.message); } catch { /* yanıt zaten gitti */ }
  });
});

async function handle(req, res) {
  const send = (code, html, headers = {}) => { res.writeHead(code, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Frame-Options': 'DENY', ...headers }); res.end(html); };
  if (!authorized(req)) return send(401, 'Şifre gerekli.', { 'WWW-Authenticate': 'Basic realm="TR Live Panel", charset="UTF-8"' });
  const url = new URL(req.url, 'http://x');
  if (req.method === 'GET' && (url.pathname === '/panel' || url.pathname === '/panel/')) return send(200, await page(url.searchParams.get('m') || ''));
  if (req.method !== 'POST') return send(404, 'Bulunamadı');
  // Başka siteden form gönderimini engelle.
  const origin = String(req.headers.origin || '');
  if (origin && origin !== `https://${DOMAIN()}` && origin !== `https://${SSLIP()}`) return send(403, 'Geçersiz istek.');
  const f = await body(req);
  const back = (m) => send(303, '', { Location: `/panel?m=${encodeURIComponent(m)}` });

  if (url.pathname === '/panel/update') {
    touch('update');
    return back('Güncelleme başlatıldı. 2-3 dakika içinde tamamlanır.');
  }
  if (url.pathname === '/panel/env') {
    const env = readEnv(`${ENV_DIR}/extra.env`);
    for (const [k, , secret] of KEYS) {
      const v = String(f.get(k) ?? '').replace(/[\r\n]/g, '').trim();
      if (secret && !v) continue; // gizli alan boş bırakıldıysa eski değer kalır
      if (v) env[k] = v; else delete env[k];
    }
    // Tek tırnak içinde: docker compose $ ve # işaretlerini yorumlamasın.
    fs.writeFileSync(`${ENV_DIR}/extra.env`, Object.entries(env).map(([k, v]) => `${k}='${String(v).replace(/'/g, '')}'`).join('\n') + '\n', { mode: 0o600 });
    const dom = String(f.get('DOMAIN') ?? '').trim().toLowerCase();
    if (/^[a-z0-9.-]{4,120}$/.test(dom) && dom !== DOMAIN()) fs.writeFileSync(`${ENV_DIR}/domain`, `${dom}\n`);
    touch('apply');
    return back('Kaydedildi. Sunucu 1-2 dakika içinde yeni ayarlarla açılır.');
  }
  if (url.pathname === '/panel/import') {
    const old = String(f.get('old') ?? '').trim();
    if (importing()) return back('Aktarma zaten sürüyor.');
    if (String(f.get('confirm') ?? '').trim().toLocaleUpperCase('tr-TR') !== 'AKTAR') return back('Onay için AKTAR yazmalısınız.');
    if (!/^postgres(ql)?:\/\/\S+$/.test(old)) return back('Adres postgres:// ile başlamalı.');
    const t = await psql(old, 'SELECT COUNT(*) FROM users');
    if (t.error) return back(`Eski veritabanına bağlanılamadı: ${t.error.slice(0, 200)}`);
    fs.writeFileSync(`${STATE}/import.log`, `[${new Date().toLocaleTimeString('tr-TR')}] İstek alındı (${t.out} kullanıcı), başlıyor…\n`);
    fs.writeFileSync(`${STATE}/import-request`, old, { mode: 0o600 });
    return back(`Aktarma başladı (${t.out} kullanıcı). Birkaç dakika sonra sayfayı yenileyin.`);
  }
  return send(404, 'Bulunamadı');
}
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => process.exit(0));
server.listen(PORT, '0.0.0.0', () => console.log(`Panel ${PORT} portunda`));
