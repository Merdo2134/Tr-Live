// Hediye combo sayacı (Yoho): aynı kişi(ler)e aynı hediye birkaç saniye içinde tekrar gönderilirse
// sayaç artar (x2, x3 ...). Bellek içidir; tek sunucu örneği için yeterli (çoklu örnekte Redis gerekir).
export const COMBO_WINDOW_MS = 6000;
const combos = new Map(); // anahtar -> { n, at }

export function nextCombo(key, now = Date.now()) {
  const prev = combos.get(key);
  const n = prev && now - prev.at <= COMBO_WINDOW_MS ? prev.n + 1 : 1;
  combos.set(key, { n, at: now });
  if (combos.size > 5000) {
    for (const [k, v] of combos) if (now - v.at > COMBO_WINDOW_MS) combos.delete(k);
  }
  return n;
}
