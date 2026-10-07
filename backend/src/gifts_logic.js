import { fail } from './http.js';

// Mikrofondaki kullanıcılara hediye dağıtımı. Gönderen mikrofondaysa kendisi de hedef olabilir (kendine hediye).
export function distributeGift(members, quantity, mode, selectedUserIds = [], rng = Math.random) {
  if (mode === 'single') throw fail('Tekli dağıtım için alıcı belirtilmelidir.');
  const onMic = members.filter((m) => m.microphone === true);
  if (!onMic.length) throw fail('Mikrofonda kullanıcı yok.');

  let targets = onMic;
  if (mode === 'selected') {
    const selected = new Set(selectedUserIds.map(String));
    targets = onMic.filter((m) => selected.has(String(m.user_id)));
    if (!targets.length) throw fail('Seçilen kullanıcılar mikrofonda değil.');
  }

  const result = targets.map((m) => ({ userId: m.user_id, quantity: 0 }));
  if (mode === 'random') {
    for (let i = 0; i < quantity; i += 1) result[Math.floor(rng() * result.length)].quantity += 1;
  } else {
    const base = Math.floor(quantity / result.length);
    let extra = quantity % result.length;
    // Artan adetler her seferinde aynı kişiye gitmesin diye rastgele başlangıç noktası.
    const offset = Math.floor(rng() * result.length);
    result.forEach((_, i) => {
      const item = result[(i + offset) % result.length];
      item.quantity = base + (extra > 0 ? 1 : 0);
      if (extra > 0) extra -= 1;
    });
  }
  return result.filter((x) => x.quantity > 0);
}
