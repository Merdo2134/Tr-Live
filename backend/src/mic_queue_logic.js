// Mikrofon sırası: saf mantık.
// queue: [{user_id}] (en eski önce). eligible: Set<user_id> (odada ve koltukta olmayanlar).
export function pickNext(queue, eligible) {
  const drop = [];
  let next = null;
  for (const q of queue) {
    if (!eligible.has(q.user_id)) { drop.push(q.user_id); continue; }
    if (next === null) next = q.user_id;
  }
  return { next, drop };
}

// Serbest, kilitli olmayan koltuk var mı? (0. koltuk sahibe ayrılmış)
export function hasFreeSeat(seatCount, lockedSeats, takenSeats) {
  const locked = new Set(lockedSeats ?? []);
  const taken = new Set(takenSeats);
  for (let i = 1; i < seatCount; i += 1) if (!locked.has(i) && !taken.has(i)) return true;
  return false;
}
