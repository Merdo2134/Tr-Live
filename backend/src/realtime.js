import { WebSocketServer } from 'ws';

let wss = null;
const OPEN = 1;

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
};

const MAX_SOCKETS_PER_IP = 30;
const MAX_SOCKETS_PER_USER = 5;
const MSG_LIMIT = { count: 40, windowMs: 10000 };

export function attachRealtime(server, { authenticate, isRoomMember, ipOf = () => 'unknown', isBanned = () => false, onViolation = () => {} }) {
  wss = new WebSocketServer({ server, path: '/ws', maxPayload: 8 * 1024 });

  async function handleMessage(ws, raw) {
    let data;
    try { data = JSON.parse(String(raw)); } catch { return; }
    if (data.type === 'ping') return safeSend(ws, { type: 'pong' });
    if (data.type === 'room_unsubscribe') { ws.roomId = null; return; }
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
        ws.userId = user.id;
        initialRoom = url.searchParams.get('roomId');
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
