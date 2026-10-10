import { AccessToken, RoomServiceClient } from 'livekit-server-sdk';

const configured = () => Boolean(process.env.LIVEKIT_API_KEY && process.env.LIVEKIT_API_SECRET && process.env.LIVEKIT_URL);
const httpUrl = () => (process.env.LIVEKIT_URL || '').replace(/^wss:/, 'https:').replace(/^ws:/, 'http:');
const client = () => new RoomServiceClient(httpUrl(), process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET);

export async function token({ identity, name, room, canPublish = true, metadata = '' }) {
  if (!configured()) throw Object.assign(new Error('LiveKit yapılandırılmamış.'), { status: 503 });
  const t = new AccessToken(process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET, { identity, name, metadata, ttl: '2h' });
  t.addGrant({ roomJoin: true, room, canPublish, canSubscribe: true, canPublishData: true });
  return t.toJwt();
}

// Aşağıdaki çağrılar "en iyi çaba"dır: LiveKit'e ulaşılamasa da oda işlemleri bozulmaz.
export async function setCanPublish(room, identity, canPublish) {
  if (!configured()) return;
  try {
    await client().updateParticipant(room, identity, undefined, { canPublish, canSubscribe: true, canPublishData: true });
  } catch (_) { /* katılımcı henüz bağlı olmayabilir */ }
}

export async function removeParticipant(room, identity) {
  if (!configured()) return;
  try { await client().removeParticipant(room, identity); } catch (_) { /* yoksay */ }
}

export async function deleteRoom(room) {
  if (!configured()) return;
  try { await client().deleteRoom(room); } catch (_) { /* yoksay */ }
}

/** Yönetim paneli için: LiveKit'e ulaşılabiliyor mu, kaç oda/katılımcı var. 4 sn'de yanıt yoksa "ulaşılamıyor". */
export async function livekitHealth() {
  if (!configured()) return { configured: false, ok: false };
  const started = Date.now();
  try {
    const rooms = await Promise.race([
      client().listRooms(),
      new Promise((_, reject) => { setTimeout(() => reject(new Error('zaman aşımı')), 4000).unref?.(); }),
    ]);
    return {
      configured: true, ok: true, latencyMs: Date.now() - started,
      rooms: rooms.length, participants: rooms.reduce((s, r) => s + Number(r.numParticipants ?? 0), 0),
    };
  } catch (e) {
    return { configured: true, ok: false, latencyMs: Date.now() - started, error: String(e?.message ?? e).slice(0, 120) };
  }
}
