// Koddan doküman üretir: veritabanı şeması, API uçları, gerçek zamanlı (WebSocket) olaylar.
// Çalıştır: cd backend && node scripts/gen_docs.mjs   →  docs/generated/*.md
// Dokümanlar elle yazılmaz; kod değişince bu komut yeniden çalıştırılır, böylece her zaman kodla aynıdır.
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const backend = join(here, '..');
const src = join(backend, 'src');
const out = join(backend, '..', 'docs', 'generated');
mkdirSync(out, { recursive: true });
const read = (p) => readFileSync(p, 'utf8');
const stamp = `> Otomatik üretildi: \`node backend/scripts/gen_docs.mjs\`. Elle düzenlemeyin.\n`;

// ---------------------------------------------------------------- Veritabanı
function splitTopLevel(body) {
  const parts = [];
  let depth = 0, cur = '', q = false;
  for (const ch of body) {
    if (ch === "'") q = !q;
    if (!q && ch === '(') depth++;
    if (!q && ch === ')') depth--;
    if (!q && ch === ',' && depth === 0) { parts.push(cur.trim()); cur = ''; continue; }
    cur += ch;
  }
  if (cur.trim()) parts.push(cur.trim());
  return parts;
}
function matchParen(s, open) {
  let depth = 0, q = false;
  for (let i = open; i < s.length; i++) {
    const ch = s[i];
    if (ch === "'") q = !q;
    if (q) continue;
    if (ch === '(') depth++;
    else if (ch === ')') { depth--; if (depth === 0) return i; }
  }
  return -1;
}
const stripComments = (sql) => sql.replace(/--[^\n]*/g, '');
const migDir = join(src, 'migrations');
const migFiles = readdirSync(migDir).filter((f) => f.endsWith('.sql')).sort();
const tables = new Map(); // ad -> { columns: Map(col -> {type, file}), constraints: [], indexes: [], created }
const getT = (n) => {
  if (!tables.has(n)) tables.set(n, { columns: new Map(), constraints: [], indexes: [], created: null });
  return tables.get(n);
};
for (const f of migFiles) {
  const sql = stripComments(read(join(migDir, f)));
  for (const m of sql.matchAll(/CREATE TABLE IF NOT EXISTS\s+([a-z_]+)\s*\(/gi)) {
    const t = getT(m[1].toLowerCase());
    t.created ??= f;
    const open = m.index + m[0].length - 1;
    const close = matchParen(sql, open);
    for (const part of splitTopLevel(sql.slice(open + 1, close))) {
      const p = part.replace(/\s+/g, ' ').trim();
      if (/^(PRIMARY KEY|UNIQUE|CHECK|FOREIGN KEY|CONSTRAINT)\b/i.test(p)) { t.constraints.push(p); continue; }
      const [col, ...rest] = p.split(' ');
      if (!t.columns.has(col)) t.columns.set(col, { type: rest.join(' '), file: f });
    }
  }
  for (const m of sql.matchAll(/ALTER TABLE\s+(?:IF EXISTS\s+)?([a-z_]+)\s+([^;]+);/gi)) {
    const t = getT(m[1].toLowerCase());
    for (const piece of splitTopLevel(m[2])) {
      const a = /^ADD COLUMN(?: IF NOT EXISTS)?\s+([a-z_]+)\s+(.+)$/is.exec(piece.replace(/\s+/g, ' ').trim());
      if (a && !t.columns.has(a[1])) t.columns.set(a[1], { type: a[2], file: f });
    }
  }
  for (const m of sql.matchAll(/CREATE (UNIQUE )?INDEX(?: IF NOT EXISTS)?\s+([a-z_0-9]+)\s+ON\s+([a-z_]+)\s*([^;]+);/gi)) {
    getT(m[3].toLowerCase()).indexes.push(`${m[1] ? 'UNIQUE ' : ''}${m[2]} ${m[4].replace(/\s+/g, ' ').trim()}`);
  }
}
const real = [...tables.entries()].filter(([, t]) => t.created).sort(([a], [b]) => a.localeCompare(b));
let db = `# Veritabanı şeması\n\n${stamp}\n**${real.length} tablo**, ${migFiles.length} migration dosyası (PostgreSQL 16).\n\n`;
db += real.map(([n]) => `[${n}](#${n})`).join(' · ') + '\n\n';
for (const [n, t] of real) {
  db += `## ${n}\n\nOluşturan: \`${t.created}\`\n\n| Sütun | Tür / kural | Ekleyen |\n|---|---|---|\n`;
  for (const [c, v] of t.columns) db += `| ${c} | \`${v.type.replace(/\|/g, '\\|')}\` | ${v.file.split('_')[0]} |\n`;
  if (t.constraints.length) db += `\nKısıtlar: ${t.constraints.map((x) => `\`${x}\``).join(', ')}\n`;
  if (t.indexes.length) db += `\nİndeksler:\n${t.indexes.map((x) => `- \`${x}\``).join('\n')}\n`;
  db += '\n';
}
writeFileSync(join(out, 'database.md'), db);

// ---------------------------------------------------------------- API
const server = read(join(src, 'server.js'));
const importOf = new Map([...server.matchAll(/import \{ router as (\w+)[^}]*\} from '\.\/routes\/([a-z_]+)\.js'/g)].map((m) => [m[1], m[2]]));
const mounts = server.split('\n').map((l) => /^app\.use\('([^']+)',.*?(\w+Router)\);/.exec(l.trim())).filter(Boolean).map((m) => ({ prefix: m[1], file: importOf.get(m[2]) })).filter((x) => x.file);
let api = `# API uçları\n\n${stamp}\nKimlik: **🔒** giriş gerekli · **👑** yalnızca yönetici · **🛠** yönetici + yardımcı admin (destek) · **⏱** hız sınırı adı\n\n`;
let total = 0;
const sections = [];
for (const { prefix, file } of mounts) {
  const code = read(join(src, 'routes', `${file}.js`));
  const globalAuth = /router\.use\(requireAuth\)/.test(code);
  const staffAll = /router\.use\(requireStaff\)/.test(code) || file === 'admin';
  const rows = [];
  for (const m of code.matchAll(/router\.(get|post|put|patch|delete)\(\s*'([^']+)'([^\n]*)/g)) {
    const [, method, path, tail] = m;
    const auth = /requireSuperAdmin/.test(tail) ? '👑' : (staffAll ? '🛠' : (globalAuth || /requireAuth/.test(tail) ? '🔒' : (/optionalAuth/.test(tail) ? '(isteğe bağlı)' : 'açık')));
    const limits = [...tail.matchAll(/(?:userLimit|ipLimit)\('([a-z_0-9]+)'/g)].map((x) => x[1]);
    // Uçtan hemen önceki yorum satırı açıklama olarak alınır.
    const before = code.slice(0, m.index).split('\n');
    let note = '';
    for (let i = before.length - 2; i >= 0 && i >= before.length - 4; i--) {
      const l = before[i].trim();
      if (l.startsWith('//')) { note = l.replace(/^\/\/\s*/, ''); break; }
      if (l && !l.startsWith('*') && !l.startsWith('/**')) break;
    }
    rows.push(`| ${method.toUpperCase()} | \`${(prefix + (path === '/' ? '' : path)).replace(/\/\//g, '/')}\` | ${auth} | ${limits.join(', ')} | ${note.replace(/\|/g, '/')} |`);
  }
  total += rows.length;
  sections.push(`## ${file}.js  (\`${prefix}\`)\n\n| Yöntem | Yol | Kimlik | ⏱ | Not |\n|---|---|---|---|---|\n${rows.join('\n')}\n`);
}
api += `**Toplam ${total} uç.**\n\n${sections.join('\n')}`;
writeFileSync(join(out, 'api.md'), api);

// ---------------------------------------------------------------- Gerçek zamanlı olaylar
const files = [];
const walk = (d) => { for (const n of readdirSync(d, { withFileTypes: true })) { const p = join(d, n.name); if (n.isDirectory()) { if (n.name !== 'migrations') walk(p); } else if (n.name.endsWith('.js')) files.push(p); } };
walk(src);
const events = new Map(); // tür -> {how:Set, where:Set}
for (const p of files) {
  const code = read(p);
  const rel = p.slice(src.length + 1);
  for (const m of code.matchAll(/hub\.(broadcastRoom|broadcastGlobal|sendToUser)\(([^;]*?)type:\s*'([a-z_]+)'/gs)) {
    const e = events.get(m[3]) ?? { how: new Set(), where: new Set() };
    e.how.add({ broadcastRoom: 'odaya', broadcastGlobal: 'herkese', sendToUser: 'kişiye' }[m[1]]);
    e.where.add(rel);
    events.set(m[3], e);
  }
  for (const m of code.matchAll(/safeSend\(ws,\s*\{\s*type:\s*'([a-z_]+)'/g)) {
    const e = events.get(m[1]) ?? { how: new Set(), where: new Set() };
    e.how.add('bağlantıya'); e.where.add(rel); events.set(m[1], e);
  }
  // Çevrimiçi durumu: realtime.js içinde izleyen bağlantılara giden olay nesneleri.
  if (rel === 'realtime.js') {
    for (const m of code.matchAll(/const payload = \{ type: '([a-z_]+)'/g)) {
      const e = events.get(m[1]) ?? { how: new Set(), where: new Set() };
      e.how.add('izleyenlere'); e.where.add(rel); events.set(m[1], e);
    }
  }
}
const realtime = read(join(src, 'realtime.js'));
const inbound = [...new Set([...realtime.matchAll(/data\.type === '([a-z_]+)'/g)].map((m) => m[1]))];
let ev = `# Gerçek zamanlı olaylar (WebSocket \`/ws\`)\n\n${stamp}\nBağlantı: \`wss://SUNUCU/ws?token=JWT\`. Mesajlar JSON, her mesajda \`type\` alanı var.\n\n`;
ev += `## İstemciden sunucuya\n\n${inbound.map((t) => `- \`${t}\``).join('\n')}\n\n`;
ev += `## Sunucudan istemciye (${events.size} tür)\n\n| Tür | Kime | Gönderen dosya |\n|---|---|---|\n`;
for (const [t, e] of [...events.entries()].sort(([a], [b]) => a.localeCompare(b))) ev += `| \`${t}\` | ${[...e.how].join(', ')} | ${[...e.where].join(', ')} |\n`;
writeFileSync(join(out, 'realtime.md'), ev);

console.log(`database.md: ${real.length} tablo · api.md: ${total} uç · realtime.md: ${events.size} olay`);
