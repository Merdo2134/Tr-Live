// Yönetici panelinden gelen ajans ayarlarının doğrulaması (saf fonksiyon).
const fail = (m) => Object.assign(new Error(m), { status: 400 });

function big(v, field) {
  if (typeof v === 'number' && Number.isSafeInteger(v) && v >= 0) return BigInt(v);
  if (typeof v === 'string' && /^\d{1,15}$/.test(v.trim())) return BigInt(v.trim());
  throw fail(`${field} geçersiz.`);
}

export function validateAgencyConfig(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw fail('Ayarlar nesne olmalı.');
  const out = {};

  if (input.settings !== undefined) {
    const s = input.settings;
    if (!s || typeof s !== 'object') throw fail('Genel ayarlar geçersiz.');
    out.settings = {};
    if (s.cycle !== undefined) { if (!['weekly', 'monthly'].includes(s.cycle)) throw fail('Dönem türü weekly veya monthly olmalı.'); out.settings.cycle = s.cycle; }
    if (s.penaltyBps !== undefined) {
      if (!Number.isInteger(s.penaltyBps) || s.penaltyBps < 0 || s.penaltyBps > 10000) throw fail('Ceza oranı 0-10000 olmalı.');
      out.settings.penaltyBps = s.penaltyBps;
    }
    if (s.requireOfficialEvents !== undefined) {
      if (typeof s.requireOfficialEvents !== 'boolean') throw fail('requireOfficialEvents true/false olmalı.');
      out.settings.requireOfficialEvents = s.requireOfficialEvents;
    }
    if (s.minEventCount !== undefined) {
      if (!Number.isInteger(s.minEventCount) || s.minEventCount < 0 || s.minEventCount > 50) throw fail('Etkinlik sayısı 0-50 olmalı.');
      out.settings.minEventCount = s.minEventCount;
    }
    if (s.currency !== undefined) {
      if (typeof s.currency !== 'string' || !/^[A-Z]{3}$/.test(s.currency)) throw fail('Para birimi 3 büyük harf olmalı (örn. USD).');
      out.settings.currency = s.currency;
    }
  }

  if (input.salaryTiers !== undefined) {
    const t = input.salaryTiers;
    if (!Array.isArray(t) || t.length < 1 || t.length > 10) throw fail('Maaş kademesi sayısı 1-10 olmalı.');
    let prevH = -1; let prevD = -1n; let prevS = -1n;
    out.salaryTiers = t.map((x, i) => {
      const hours = x?.hours; const diamonds = big(x?.diamonds, 'Diamond hedefi'); const salaryCents = big(x?.salaryCents, 'Maaş');
      if (!Number.isInteger(hours) || hours < 0 || hours > 744) throw fail('Saat hedefi 0-744 arasında tam sayı olmalı.');
      if (hours < prevH || diamonds < prevD || salaryCents < prevS) throw fail('Kademeler artan sırada olmalı (saat, Diamond ve maaş düşemez).');
      if (diamonds === prevD && hours === prevH) throw fail('Kademeler birbirinin aynısı olamaz.');
      prevH = hours; prevD = diamonds; prevS = salaryCents;
      return { level: i + 1, hours, diamonds, salaryCents };
    });
  }

  if (input.commissionTiers !== undefined) {
    const t = input.commissionTiers;
    if (!Array.isArray(t) || t.length < 1 || t.length > 10) throw fail('Komisyon kademesi sayısı 1-10 olmalı.');
    let prevD = -1n; let prevB = -1;
    out.commissionTiers = t.map((x, i) => {
      const minDiamonds = big(x?.minDiamonds, 'Ekip Diamond eşiği');
      const bps = x?.bps;
      if (!Number.isInteger(bps) || bps < 0 || bps > 10000) throw fail('Komisyon oranı 0-10000 (baz puan) olmalı.');
      if (i === 0 && minDiamonds !== 0n) throw fail('İlk komisyon kademesi 0 Diamond ile başlamalı.');
      if (minDiamonds <= prevD) throw fail('Komisyon eşikleri kesin artan olmalı.');
      if (bps < prevB) throw fail('Komisyon oranı kademeyle birlikte düşemez.');
      prevD = minDiamonds; prevB = bps;
      return { level: i + 1, minDiamonds, bps };
    });
  }
  return out;
}
