import { query } from '../database.js';
import { hub } from '../realtime.js';
import { publicUser } from '../views.js';
import { isGhost } from './presence.js';
import { loadPublicRow } from './users.js';

/** Hayalet modu şu an etkin mi (değişiklikten önce çağrılıp refreshGhost'a verilir). */
export const ghostNow = (userId) => isGhost(userId).catch(() => false);

/**
 * Hayalet durumu değişebilecek bir işlemden sonra (mod aç/kapa, SWIP alma, yönetici WIP verme/alma):
 * çevrimiçi görünürlüğü günceller; dinleyici olarak bulunduğu odalarda (mikrofonda değilken) görünür/görünmez yapar.
 */
export async function refreshGhost(userId, wasGhost) {
  try {
    const u = (await query(`SELECT show_presence, is_hidden, is_ghost(id) AS ghost FROM users WHERE id = $1`, [userId])).rows[0];
    if (!u) return;
    hub.setPresenceVisible(userId, u.show_presence !== false && !u.is_hidden && !u.ghost);
    if (wasGhost === null || wasGhost === undefined || wasGhost === u.ghost) return;
    const rooms = (await query(`SELECT room_id FROM room_members WHERE user_id = $1 AND microphone = FALSE`, [userId])).rows;
    if (!rooms.length) return;
    const user = u.ghost ? null : publicUser(await loadPublicRow(userId), null);
    for (const { room_id: roomId } of rooms) {
      if (u.ghost) hub.broadcastRoom(roomId, { type: 'room_member_left', roomId, userId, ghost: true });
      else hub.broadcastRoom(roomId, { type: 'room_member_joined', roomId, user, entranceEffect: null, silent: true });
    }
  } catch (e) {
    console.error('Hayalet durumu güncellenemedi:', e.message);
  }
}
