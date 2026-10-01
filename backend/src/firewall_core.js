// Güvenlik duvarının saf (bağımlılıksız, test edilebilir) çekirdeği.

/** Kayan pencere hız sınırlayıcı (bellek içi). */
export class SlidingWindowLimiter {
  constructor() { this.buckets = new Map(); }

  hit(key, limit, windowMs, now = Date.now()) {
    let b = this.buckets.get(key);
    if (!b) { b = { arr: [], windowMs }; this.buckets.set(key, b); }
    b.windowMs = windowMs;
    const cutoff = now - windowMs;
    while (b.arr.length && b.arr[0] <= cutoff) b.arr.shift();
    if (b.arr.length >= limit) return { allowed: false, retryAfterMs: Math.max(1, b.arr[0] + windowMs - now), count: b.arr.length };
    b.arr.push(now);
    return { allowed: true, remaining: limit - b.arr.length, count: b.arr.length };
  }

  prune(now = Date.now()) {
    for (const [k, b] of this.buckets) {
      if (!b.arr.length || b.arr[b.arr.length - 1] <= now - b.windowMs) this.buckets.delete(k);
    }
  }

  get size() { return this.buckets.size; }
}

/** Başarısız giriş sayacı + geçici kilit. */
export class LockoutTracker {
  constructor({ maxFailures = 5, windowMs = 15 * 60 * 1000, lockMs = 15 * 60 * 1000 } = {}) {
    Object.assign(this, { maxFailures, windowMs, lockMs });
    this.fails = new Map();   // key -> [timestamps]
    this.locks = new Map();   // key -> lockedUntil
  }

  lockedFor(key, now = Date.now()) {
    const until = this.locks.get(key);
    if (!until) return 0;
    if (until <= now) { this.locks.delete(key); return 0; }
    return until - now;
  }

  fail(key, now = Date.now()) {
    const arr = (this.fails.get(key) || []).filter((t) => t > now - this.windowMs);
    arr.push(now);
    this.fails.set(key, arr);
    if (arr.length >= this.maxFailures) {
      this.locks.set(key, now + this.lockMs);
      this.fails.delete(key);
      return { locked: true, retryAfterMs: this.lockMs };
    }
    return { locked: false, remaining: this.maxFailures - arr.length };
  }

  success(key) { this.fails.delete(key); this.locks.delete(key); }

  prune(now = Date.now()) {
    for (const [k, until] of this.locks) if (until <= now) this.locks.delete(k);
    for (const [k, arr] of this.fails) if (!arr.length || arr[arr.length - 1] <= now - this.windowMs) this.fails.delete(k);
  }
}

/** IP yasak listesi (bellek içi önbellek; kalıcılık firewall.js'te). */
export class BanList {
  constructor() { this.map = new Map(); } // ip -> { until|null, reason }

  ban(ip, ms, reason = '', now = Date.now()) {
    this.map.set(ip, { until: ms == null ? null : now + ms, reason });
  }

  unban(ip) { return this.map.delete(ip); }

  get(ip, now = Date.now()) {
    const b = this.map.get(ip);
    if (!b) return null;
    if (b.until !== null && b.until <= now) { this.map.delete(ip); return null; }
    return b;
  }

  isBanned(ip, now = Date.now()) { return this.get(ip, now) !== null; }
  list() { return [...this.map.entries()].map(([ip, b]) => ({ ip, ...b })); }
}

/** İhlal puanı; eşik aşılınca yasak. Tekrarlayan ihlalcilerde süre uzar. */
export class ViolationTracker {
  constructor({ windowMs = 10 * 60 * 1000, threshold = 30, escalationMs = [15 * 60e3, 60 * 60e3, 24 * 60 * 60e3], historyMs = 24 * 60 * 60e3 } = {}) {
    Object.assign(this, { windowMs, threshold, escalationMs, historyMs });
    this.events = new Map();   // ip -> [{t, w}]
    this.bans = new Map();     // ip -> [timestamps of previous bans]
  }

  /** Puan ekler. Eşik aşıldıysa { ban: true, durationMs } döner. */
  record(ip, weight = 1, now = Date.now()) {
    const arr = (this.events.get(ip) || []).filter((e) => e.t > now - this.windowMs);
    arr.push({ t: now, w: weight });
    const score = arr.reduce((s, e) => s + e.w, 0);
    if (score < this.threshold) { this.events.set(ip, arr); return { ban: false, score }; }
    this.events.delete(ip);
    const past = (this.bans.get(ip) || []).filter((t) => t > now - this.historyMs);
    const durationMs = this.escalationMs[Math.min(past.length, this.escalationMs.length - 1)];
    past.push(now);
    this.bans.set(ip, past);
    return { ban: true, durationMs, score };
  }

  prune(now = Date.now()) {
    for (const [k, arr] of this.events) if (!arr.length || arr[arr.length - 1].t <= now - this.windowMs) this.events.delete(k);
    for (const [k, arr] of this.bans) { const f = arr.filter((t) => t > now - this.historyMs); if (f.length) this.bans.set(k, f); else this.bans.delete(k); }
  }
}

// ---- İstek denetimi (yalnızca URL ve User-Agent; gövde alanları parametreli sorgularla korunur) ----
const URL_RULES = [
  { id: 'path_traversal', re: /(\.\.[\\/]|%2e%2e(%2f|%5c|[\\/])|%252e%252e)/i },
  { id: 'null_byte', re: /%00|\u0000/ },
  { id: 'sql_injection', re: /(\bunion\b[\s\S]{0,20}\bselect\b|information_schema|;\s*drop\s+table|\bor\b\s+1\s*=\s*1|pg_sleep\s*\(|\bsleep\s*\(\s*\d)/i },
  { id: 'xss', re: /(<\s*script|javascript:|onerror\s*=|onload\s*=)/i },
  { id: 'cmd_injection', re: /(\$\(|%24%28|\|\s*(nc|bash|sh|curl|wget)\b)/i },
];
const BAD_UA = /(sqlmap|nikto|masscan|nmap|acunetix|nessus|havij|dirbuster|wpscan|zgrab)/i;

export function inspectRequest(url, userAgent = '') {
  if (typeof url !== 'string') return 'bad_url';
  if (url.length > 2048) return 'url_too_long';
  let decoded = url;
  try { decoded = decodeURIComponent(url); } catch { /* bozuk kodlama kendi başına şüphelidir */ return 'bad_encoding'; }
  for (const rule of URL_RULES) {
    if (rule.re.test(url) || rule.re.test(decoded)) return rule.id;
  }
  if (BAD_UA.test(userAgent || '')) return 'scanner_user_agent';
  return null;
}

// ---- JSON gövde şekli: aşırı derin/geniş yapıları ve prototype pollution anahtarlarını reddeder ----
const DANGEROUS_KEYS = new Set(['__proto__', 'constructor', 'prototype']);

export function jsonShapeProblem(value, { maxDepth = 8, maxNodes = 2000 } = {}) {
  let nodes = 0;
  const walk = (v, depth) => {
    if (depth > maxDepth) return 'too_deep';
    if (v && typeof v === 'object') {
      if (++nodes > maxNodes) return 'too_large';
      const keys = Array.isArray(v) ? null : Object.keys(v);
      if (keys) for (const k of keys) { if (DANGEROUS_KEYS.has(k)) return 'dangerous_key'; const p = walk(v[k], depth + 1); if (p) return p; }
      else for (const item of v) { const p = walk(item, depth + 1); if (p) return p; }
    }
    return null;
  };
  return walk(value, 0);
}

export function normalizeIp(ip) {
  if (!ip) return 'unknown';
  return String(ip).replace(/^::ffff:/i, '').trim();
}
