import { WebSocketServer } from 'ws';

let wss = null;
const OPEN = 1;

// ---- Çevrimiçi durumu ----
// userId -> açık (kimliği doğrulanmış) bağlantı sayısı. Son bağlantı kapanınca kullanıcı hemen "çevrimdışı"
// sayılmaz: mobil ağ geçişlerinde (Wi-Fi → 4G) bağlantı birkaç saniye kopar; 20 sn içinde dönerse durum değişmez.
const OFFLINE_GRACE_MS = 20000;
const MAX_WATCH = 100;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const onlineCount = new Map();
const offlineTimers = new Map();
const presenceVisible = new Map(); // userId -> bool (gizli kullanıcı / "durumumu gizle" seçenekleri)
let presenceHook = () => {};

function emitPresence(userId, online) {
  if (presenceVisible.get(userId) === false) return;
  const payload = { type: 'presence', userId, online, lastSeenAt: online ? null : new Date().toISOString() };
  for (const ws of clients()) if (ws.watch?.has(userId)) safeSend(ws, payload);
}

function markOnline(userId, visible) {
  presenceVisible.set(userId, visible);
  const pending = offlineTimers.get(userId);
  if (pending) { clearTimeout(pending); offlineTimers.delete(userId); }
  const n = (onlineCount.get(userId) ?? 0) + 1;
  onlineCount.set(userId, n);
  if (n === 1 && !pending) {
    emitPresence(userId, true);
    presenceHook(userId, true);
  }
}

function markClosed(userId) {
  const n = (onlineCount.get(userId) ?? 1) - 1;
  if (n > 0) { onlineCount.set(userId, n); return; }
  onlineCount.delete(userId);
  if (offlineTimers.has(userId)) return;
  const t = setTimeout(() => {
    offlineTimers.delete(userId);
    if (onlineCount.has(userId)) return;
    emitPresence(userId, false);
    presenceVisible.delete(userId);
    presenceHook(userId, false);
  }, OFFLINE_GRACE_MS);
  t.unref?.();
  offlineTimers.set(userId, t);
}

function safeSend(ws, payload) {
  if (ws.readyState !== OPEN) return;
  try { ws.send(JSON.stringify(payload)); } catch (_) { /* yoksay */ }
}

const clients = () => (wss ? wss.clients : []);

// Tek sunucu örneği için bellek içi hub. Birden fazla örnek çalıştırılacaksa Redis pub/sub gerekir.
export const hub = {
  broadcastRoom(roomId, payload) {
    for (const ws of clients()) if (ws.userId && ws.roomId === roomId) safeSend(ws, payload);
  },
  broadcastGlobal(payload) {
    for (const ws of clients()) if (ws.userId) safeSend(ws, payload);
  },
  sendToUser(userId, payload) {
    for (const ws of clients()) if (ws.userId === userId) safeSend(ws, payload);
  },
  detachUserFromRoom(userId, roomId, payload = null) {
    for (const ws of clients()) {
      if (ws.userId === userId && ws.roomId === roomId) {
        ws.roomId = null;
        if (payload) safeSend(ws, payload);
      }
    }
  },
  clearRoom(roomId) {
    for (const ws of clients()) if (ws.roomId === roomId) ws.roomId = null;
  },
  isUserInRoom(userId, roomId) {
    for (const ws of clients()) if (ws.userId === userId && ws.roomId === roomId && ws.readyState === OPEN) return true;
    return false;
  },
  disconnectUser(userId, reason = 'closed') {
    for (const ws of clients()) if (ws.userId === userId) ws.close(4001, reason);
  },
  /** Tek bir cihaz oturumunun bağlantılarını kapatır (uzaktan çıkış). */
  disconnectSession(sessionId, reason = 'session_revoked') {
    if (!sessionId) return;
    for (const ws of clients()) if (ws.sessionId === sessionId) ws.close(4001, reason);
  },
  /** Kullanıcının, verilen oturum dışındaki tüm bağlantılarını kapatır (keepSessionId null ise hepsini). */
  disconnectUserExcept(userId, keepSessionId, reason = 'closed') {
    for (const ws of clients()) if (ws.userId === userId && (!keepSessionId || ws.sessionId !== keepSessionId)) ws.close(4001, reason);
  },
  /** Engelleme sonrası iki kişi birbirinin çevrimiçi durumunu artık almaz (izleme listelerinden çıkarılır). */
  unwatchPair(a, b) {
    for (const ws of clients()) {
      if (!ws.watch) continue;
      if (ws.userId === a) ws.watch.delete(b);
      else if (ws.userId === b) ws.watch.delete(a);
    }
  },
  /** Bağlantısı açık (ya da kısa kopma payı içinde) kullanıcı. */
  isOnline(userId) {
    return onlineCount.has(userId) || offlineTimers.has(userId);
  },
  onlineUserCount() {
    return new Set([...onlineCount.keys(), ...offlineTimers.keys()]).size;
  },
  /** Kullanıcı "çevrimiçi durumumu gizle" seçeneğini değiştirince izleyenlere bildirilir. */
  setPresenceVisible(userId, visible) {
    if (!hub.isOnline(userId)) return;
    if (visible) { presenceVisible.set(userId, true); emitPresence(userId, true); return; }
    // Gizlenince izleyenler kişiyi çevrimdışı görür (son görülme bilgisi de verilmez).
    const payload = { type: 'presence', userId, online: false, lastSeenAt: null };
    for (const ws of clients()) if (ws.watch?.has(userId)) safeSend(ws, payload);
    presenceVisible.set(userId, false);
  },
  stats() {
    let sockets = 0; let inRooms = 0;
    for (const ws of clients()) { if (!ws.userId) continue; sockets += 1; if (ws.roomId) inRooms += 1; }
    return { sockets, onlineUsers: hub.onlineUserCount(), inRooms };
  },
};

const MAX_SOCKETS_PER_IP = 30;
const MAX_SOCKETS_PER_USER = 5;
const MSG_LIMIT = { count: 40, windowMs: 10000 };

export function attachRealtime(server, {
  authenticate, isRoomMember, ipOf = () => 'unknown', isBanned = () => false, onViolation = () => {},
  onPresence = () => {}, presenceSnapshot = async () => [], canTyping = async () => false,
  isPresenceVisible = async (u) => u.show_presence !== false && !u.is_hidden,
}) {
  wss = new WebSocketServer({ server, path: '/ws', maxPayload: 8 * 1024 });
  presenceHook = (userId, online) => { Promise.resolve().then(() => onPresence(userId, online)).catch(() => {}); };

  async function handleMessage(ws, raw) {
    let data;
    try { data = JSON.parse(String(raw)); } catch { return; }
    if (data.type === 'ping') return safeSend(ws, { type: 'pong' });
    if (data.type === 'room_unsubscribe') { ws.roomId = null; return; }
    // Ekranda görünen kişilerin çevrimiçi durumunu izleme (sohbet listesi, DM, profil). Liste her seferinde yenilenir.
    if (data.type === 'presence_watch' && Array.isArray(data.userIds)) {
      const ids = [...new Set(data.userIds.filter((x) => typeof x === 'string' && UUID_RE.test(x)))].slice(0, MAX_WATCH);
      if (!ids.length) { ws.watch = null; return; }
      try {
        // Gizli/engelli kişiler anlık görüntüden ve izleme listesinden çıkarılır.
        const users = await presenceSnapshot(ws.userId, ids);
        ws.watch = new Set(users.map((u) => u.userId));
        safeSend(ws, { type: 'presence_state', users });
      } catch (_) { /* anlık görüntü alınamazsa durum gösterilmez */ }
      return;
    }
    // "Yazıyor..." (özel mesaj): aynı kişiye en fazla 2 sn'de bir iletilir.
    if (data.type === 'typing' && typeof data.to === 'string' && UUID_RE.test(data.to) && data.to !== ws.userId) {
      const now = Date.now();
      ws.typingAt ??= new Map();
      if (now - (ws.typingAt.get(data.to) ?? 0) < 2000) return;
      if (ws.typingAt.size > 50) ws.typingAt.clear();
      ws.typingAt.set(data.to, now);
      try {
        if (await canTyping(ws.userId, data.to)) hub.sendToUser(data.to, { type: 'typing', userId: ws.userId });
      } catch (_) { /* yoksay */ }
      return;
    }
    if (data.type === 'room_subscribe' && typeof data.roomId === 'string') {
      try {
        if (await isRoomMember(ws.userId, data.roomId)) {
          ws.roomId = data.roomId;
          safeSend(ws, { type: 'room_subscribed', roomId: data.roomId });
        } else {
          safeSend(ws, { type: 'error', code: 'not_member', roomId: data.roomId });
        }
      } catch (_) { safeSend(ws, { type: 'error', code: 'server' }); }
    }
  }

  wss.on('connection', (ws, req) => {
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });
    ws.on('error', () => {});
    ws.on('close', () => {
      if (ws.counted) { ws.counted = false; markClosed(ws.userId); }
    });

    const ip = ipOf(req);
    ws.ip = ip;
    if (isBanned(ip)) { ws.close(1008, 'banned'); return; }
    let sameIp = 0;
    for (const c of wss.clients) if (c.ip === ip) sameIp += 1;
    if (sameIp > MAX_SOCKETS_PER_IP) {
      onViolation(ip, 'ws_ip_flood', { weight: 2 });
      ws.close(1013, 'too_many_connections');
      return;
    }

    let ready = false;
    const queue = [];
    const times = [];
    ws.on('message', (raw) => {
      // Mesaj seli koruması: 10 sn içinde en fazla 40 mesaj.
      const now = Date.now();
      while (times.length && times[0] <= now - MSG_LIMIT.windowMs) times.shift();
      if (times.length >= MSG_LIMIT.count) {
        onViolation(ip, 'ws_message_flood', { weight: 3, userId: ws.userId ?? null });
        ws.close(1008, 'flood');
        return;
      }
      times.push(now);
      if (!ready) { if (queue.length < 5) queue.push(raw); return; }
      handleMessage(ws, raw);
    });

    (async () => {
      let initialRoom = null;
      try {
        const url = new URL(req.url, 'http://localhost');
        const user = await authenticate(url.searchParams.get('token'));
        if (ws.readyState !== OPEN) return; // doğrulama sürerken istemci gitti
        ws.userId = user.id;
        ws.sessionId = user.session_id ?? null;
        initialRoom = url.searchParams.get('roomId');
        const visible = await isPresenceVisible(user).catch(() => false);
        if (ws.readyState !== OPEN) return;
        ws.counted = true;
        markOnline(user.id, visible);
      } catch (_) {
        ws.close(1008, 'auth');
        return;
      }
      // Kullanıcı başına en fazla 5 eşzamanlı bağlantı; en eskiler kapatılır.
      const mine = [...wss.clients].filter((c) => c !== ws && c.userId === ws.userId);
      while (mine.length >= MAX_SOCKETS_PER_USER) mine.shift().close(1013, 'replaced');
      ready = true;
      safeSend(ws, { type: 'connected', userId: ws.userId });
      if (initialRoom) await handleMessage(ws, JSON.stringify({ type: 'room_subscribe', roomId: initialRoom }));
      for (const raw of queue.splice(0)) await handleMessage(ws, raw);
    })();
  });

  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.isAlive) { ws.terminate(); continue; }
      ws.isAlive = false;
      try { ws.ping(); } catch (_) { /* yoksay */ }
    }
  }, 30000);
  heartbeat.unref();
  wss.on('close', () => clearInterval(heartbeat));
  return wss;
}
