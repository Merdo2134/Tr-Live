import http from 'node:http';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import { config, validateConfig } from './config.js';
import { query, closeDb } from './database.js';
import { authenticateToken } from './auth.js';
import { attachRealtime } from './realtime.js';
import { isRoomMember, startRoomSweeper } from './services/rooms.js';
import { router as authRouter } from './routes/auth.js';
import { router as meRouter } from './routes/me.js';
import { router as usersRouter } from './routes/users.js';
import { router as inventoryRouter } from './routes/inventory.js';
import { router as roomsRouter } from './routes/rooms.js';
import { router as familiesRouter } from './routes/families.js';
import { router as wipRouter } from './routes/wip.js';
import { router as dealersRouter } from './routes/dealers.js';
import { router as adminRouter } from './routes/admin.js';
import { router as giftsRouter } from './routes/gifts.js';
import { router as agenciesRouter } from './routes/agencies.js';
import { router as musicRouter } from './routes/music.js';
import { router as chatRouter } from './routes/chat.js';
import { router as messagesRouter } from './routes/messages.js';
import { router as safetyRouter } from './routes/safety.js';
import { router as leaderboardsRouter } from './routes/leaderboards.js';
import { router as pkRouter } from './routes/pk.js';
import { router as gamesRouter } from './routes/games.js';
import { router as feedRouter } from './routes/feed.js';
import { startMusicTicker } from './services/music.js';
import { startPkTicker } from './services/pk.js';
import { startGameTicker } from './services/games.js';
import { closeStaleMicSessions } from './services/mic.js';
import { firewall, bodyGuard, ipLimit, loadBans, startFirewallJanitor, wsClientIp, isBanned, noteViolation } from './firewall.js';

validateConfig();

export const app = express();
app.disable('x-powered-by');
if (config.trustProxy) app.set('trust proxy', config.trustProxy);
app.use(helmet({
  crossOriginResourcePolicy: { policy: 'cross-origin' },
  hsts: { maxAge: 31536000, includeSubDomains: true },
}));
app.use(firewall()); // IP yasağı, WAF kuralları, IP başına hız sınırı (CORS ve gövde okumadan önce)
app.use(cors({
  origin: config.corsOrigin.includes('*') ? true : config.corsOrigin,
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
app.use(express.json({ limit: '100kb' }));
app.use(bodyGuard()); // derin/dev JSON ve prototype pollution anahtarlarını reddeder
app.use('/api', (req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });

app.get(['/health', '/api/health'], async (req, res) => {
  try {
    await query('SELECT 1');
    res.json({ ok: true, service: 'tr-live-backend', time: new Date().toISOString() });
  } catch {
    res.status(503).json({ ok: false });
  }
});

app.use('/uploads', express.static(config.uploadDir, {
  maxAge: '7d', index: false, dotfiles: 'deny',
  setHeaders: (res) => res.setHeader('X-Content-Type-Options', 'nosniff'),
}));

app.use('/api/auth', ipLimit('auth', 60, 15 * 60e3), authRouter);
app.use('/api/me', meRouter);
app.use('/api/users', usersRouter);
app.use('/api/inventory', inventoryRouter);
app.use('/api/rooms', roomsRouter);
app.use('/api/rooms', chatRouter);
app.use('/api/messages', messagesRouter);
app.use('/api/leaderboards', leaderboardsRouter);
app.use('/api/families', familiesRouter);
app.use('/api/wip', wipRouter);
app.use('/api/dealer', dealersRouter);
app.use('/api/admin', adminRouter);
// Aşağıdakiler '/api' altında birden çok yol tanımladığı için en sona konur.
app.use('/api', feedRouter);
app.use('/api', giftsRouter);
app.use('/api', agenciesRouter);
app.use('/api', musicRouter);
app.use('/api', pkRouter);
app.use('/api', gamesRouter);
app.use('/api', safetyRouter);

app.use('/api', (req, res) => res.status(404).json({ message: 'Adres bulunamadı.' }));

const PG_ERRORS = {
  '22P02': [400, 'Geçersiz değer gönderildi.'],
  '22001': [400, 'Bir alan izin verilen uzunluğu aşıyor.'],
  '22003': [400, 'Sayısal değer izin verilen aralığın dışında.'],
  '23505': [409, 'Bu kayıt zaten mevcut.'],
  '23503': [400, 'İlişkili kayıt bulunamadı.'],
  '23514': [400, 'Değer kurallara uymuyor.'],
  '40P01': [409, 'İşlem çakıştı, lütfen tekrar deneyin.'],
  '40001': [409, 'İşlem çakıştı, lütfen tekrar deneyin.'],
};

// eslint-disable-next-line no-unused-vars
app.use((error, req, res, next) => {
  if (error.type === 'entity.parse.failed') return res.status(400).json({ message: 'Geçersiz JSON.' });
  if (error.type === 'entity.too.large') return res.status(413).json({ message: 'İstek çok büyük.' });
  if (error.status && error.status >= 400 && error.status < 500) return res.status(error.status).json({ message: error.message });
  if (error.status === 503) return res.status(503).json({ message: error.message });
  const pg = PG_ERRORS[error.code];
  if (pg) return res.status(pg[0]).json({ message: pg[1] });
  console.error(`[hata] ${req.method} ${req.originalUrl}:`, error);
  res.status(500).json({ message: 'Sunucu hatası.' });
});

const server = http.createServer(app);
attachRealtime(server, {
  authenticate: authenticateToken,
  isRoomMember,
  ipOf: wsClientIp,
  isBanned,
  onViolation: (ip, type, opts) => noteViolation(ip, type, opts),
});
const sweeper = startRoomSweeper();
const musicTicker = startMusicTicker();
const pkTicker = startPkTicker();
const gameTicker = startGameTicker();
closeStaleMicSessions().catch((e) => console.error('Mikrofon oturumları temizlenemedi:', e.message));
const janitor = startFirewallJanitor();
loadBans().then((n) => n && console.log(`${n} aktif IP yasağı yüklendi.`)).catch((e) => console.error('IP yasakları yüklenemedi:', e.message));

server.listen(config.port, () => console.log(`TR Live backend ${config.port} portunda çalışıyor.`));

let closing = false;
async function shutdown(signal) {
  if (closing) return;
  closing = true;
  console.log(`${signal} alındı, kapatılıyor...`);
  clearInterval(sweeper);
  clearInterval(musicTicker);
  clearInterval(pkTicker);
  clearInterval(gameTicker);
  clearInterval(janitor);
  const force = setTimeout(() => process.exit(1), 10000);
  force.unref();
  server.close(async () => { await closeDb(); process.exit(0); });
  server.closeAllConnections?.();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('unhandledRejection', (reason) => console.error('İşlenmeyen söz reddi:', reason));
process.on('uncaughtException', (error) => { console.error('Beklenmeyen hata:', error); shutdown('uncaughtException'); });
