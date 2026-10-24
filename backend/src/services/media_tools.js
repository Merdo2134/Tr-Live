import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { vapcInfo } from './media.js';

// Yüklenen videolar için otomatik işlemler (sunucuda ffmpeg varsa):
//  - Yan yana şeffaf mp4 (VAP) mi, düz video mu anlaşılır; VAP ise şeffaflık yarısı (sol/sağ) bulunur.
//  - Siyah arka planlı düz video şeffaf mp4'e çevrilir (siyah → şeffaf, ışık/parıltı yarı saydam).
//    Kendi arka planı olan sahne videoları kenarları yumuşatılmış, opak tam ekran olarak çevrilir.
//  - Hediye ikonu: animasyonun ortalarındaki kareden şeffaf PNG (içeriğe göre kırpılmış, 256x256).
// ffmpeg yoksa hiçbiri yapılmaz; yükleme eskisi gibi çalışır.

// Tüm hediyeler aynı ölçüde: 540x960 (dikey ekran). Çerçeveler kare: 360x360.
const GIFT = [540, 960];
const FRAME = [360, 360];
const MAX_FPS = 20;

function run(cmd, args, { input = null, timeoutMs = 240000 } = {}) {
  return new Promise((resolve, reject) => {
    let p;
    try {
      p = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'pipe'] });
    } catch (e) {
      reject(e);
      return;
    }
    const out = [];
    let err = '';
    const timer = setTimeout(() => { p.kill('SIGKILL'); }, timeoutMs);
    p.stdout.on('data', (d) => out.push(d));
    p.stderr.on('data', (d) => { if (err.length < 4000) err += d; });
    p.on('error', (e) => { clearTimeout(timer); reject(e); });
    p.on('close', (code) => {
      clearTimeout(timer);
      if (code === 0) resolve(Buffer.concat(out));
      else reject(new Error(`${cmd} ${code}: ${err.slice(-400)}`));
    });
    p.stdin.on('error', () => {});
    if (input) p.stdin.end(input); else p.stdin.end();
  });
}

let available = null;
export async function ffmpegAvailable() {
  if (available !== null) return available;
  try {
    await run('ffmpeg', ['-hide_banner', '-version'], { timeoutMs: 10000 });
    await run('ffprobe', ['-hide_banner', '-version'], { timeoutMs: 10000 });
    available = true;
  } catch {
    available = false;
  }
  return available;
}

async function withTemp(buf, ext, fn) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'trmedia-'));
  const file = path.join(dir, `in.${ext}`);
  try {
    await fs.writeFile(file, buf);
    return await fn(file, dir);
  } finally {
    fs.rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}

async function probe(file) {
  const out = await run('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries',
    'stream=width,height,r_frame_rate:format=duration', '-of', 'json', file], { timeoutMs: 30000 });
  const j = JSON.parse(out.toString());
  const s = j.streams?.[0] ?? {};
  const [a, b] = String(s.r_frame_rate ?? '25/1').split('/').map(Number);
  const fps = b ? a / b : a || 25;
  return { w: s.width | 0, h: s.height | 0, fps: Number.isFinite(fps) && fps > 0 ? fps : 25, duration: Number(j.format?.duration) || 0 };
}

/** Videonun t. saniyesindeki kareyi (en fazla 320 genişlik) ham RGB olarak döndürür. */
async function grabRgb(file, t, w, h) {
  const sw = Math.min(320, w) & ~1;
  const sh = Math.max(2, Math.round((h * sw) / w) & ~1);
  const raw = await run('ffmpeg', ['-v', 'error', '-ss', String(Math.max(0, t)), '-i', file, '-frames:v', '1',
    '-vf', `scale=${sw}:${sh}`, '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], { timeoutMs: 60000 });
  if (raw.length !== sw * sh * 3) throw new Error('kare alınamadı');
  return { raw, w: sw, h: sh };
}

/** Bir karenin sol ve sağ yarısının ortalama doygunluğu ve parlaklık ilişkisi: VAP'ta bir yarı gri (maske) olur. */
function layoutOf({ raw, w, h }) {
  const half = w >> 1;
  let satL = 0; let satR = 0; let n = 0;
  let lumL = 0; let lumR = 0;
  for (let y = 0; y < h; y += 2) {
    for (let x = 0; x < half; x += 2) {
      const i = (y * w + x) * 3; const j = (y * w + x + half) * 3;
      const l = [raw[i], raw[i + 1], raw[i + 2]]; const r = [raw[j], raw[j + 1], raw[j + 2]];
      satL += Math.max(...l) - Math.min(...l); satR += Math.max(...r) - Math.min(...r);
      lumL += Math.max(...l); lumR += Math.max(...r);
      n++;
    }
  }
  satL /= n; satR /= n; lumL /= n; lumR /= n;
  // Gri yarı: neredeyse hiç renk yok; diğer yarıda renk var (ya da en azından içerik var).
  if (satL < 3 && satR > satL + 4 && lumL > 3) return 'left';
  if (satR < 3 && satL > satR + 4 && lumR > 3) return 'right';
  return 'plain';
}

/** Düz videonun arka planı siyah mı (şeffaf yapılabilir) yoksa kendine ait bir sahne mi. */
function isScene({ raw, w, h }) {
  const b = Math.max(2, Math.round(Math.min(w, h) * 0.06));
  const border = [];
  let black = 0; let total = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 3;
      const m = Math.max(raw[i], raw[i + 1], raw[i + 2]);
      if (m < 20) black++;
      total++;
      if (y < b || y >= h - b || x < b || x >= w - b) border.push(m);
    }
  }
  border.sort((p, q) => p - q);
  const med = border[border.length >> 1] ?? 0;
  return med > 30 || black / total < 0.25;
}

/** Düz videoyu 540x960 şeffaf mp4'e (sol yarı maske, sağ yarı renk) çevirir. */
async function convertPlain(file, info, scene, [W, H]) {
  const fps = Math.min(MAX_FPS, Math.round(info.fps) || MAX_FPS);
  const fit = `scale=${W}:${H}:force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2`;
  const pad = `pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:black`;
  const graph = scene
    // Sahne: içerik opak, kenarları yumuşak; boş kalan yer şeffaf.
    ? `[0:v]fps=${fps},${fit},split[s1][s2];[s1]${pad},format=yuv420p[c];`
      + `[s2]format=gray,lut=c0=255,${pad},boxblur=10:2,format=yuv420p[a];[a][c]hstack=inputs=2[v]`
    // Siyah arka plan: maske = en parlak renk kanalı (siyah → şeffaf, parlak → opak).
    : `[0:v]fps=${fps},${fit},${pad},format=gbrp,split[c0][m];[m]extractplanes=r+g+b[r][g][b];`
      + `[r][g]blend=all_mode=lighten[rg];[rg][b]blend=all_mode=lighten,lut=c0='clip((val-16)*1.07,0,255)',format=yuv420p[a];`
      + `[c0]format=yuv420p[c];[a][c]hstack=inputs=2[v]`;
  return withTemp(Buffer.alloc(0), 'tmp', async (_f, dir) => {
    const out = path.join(dir, 'out.mp4');
    await run('ffmpeg', ['-v', 'error', '-y', '-i', file, '-filter_complex', graph, '-map', '[v]', '-map', '0:a?',
      '-c:v', 'libx264', '-preset', 'veryfast', '-threads', '2', '-crf', '24', '-maxrate', '1100k', '-bufsize', '2200k', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-b:a', '96k', '-shortest', '-movflags', '+faststart', out], { timeoutMs: 200000 });
    return fs.readFile(out);
  });
}

/** VAP videodan ortalardaki kareyi şeffaf PNG ikon yapar. rgb / mask: [x, y, w, h] (renk ve maske bölgeleri). */
async function iconFromRects(file, info, rgb, mask) {
  const t = info.duration > 0 ? info.duration * 0.55 : 1;
  const sw = Math.min(360, rgb[2]) & ~1;
  const sh = Math.max(2, Math.round((rgb[3] * sw) / rgb[2]) & ~1);
  const raw = await run('ffmpeg', ['-v', 'error', '-ss', String(t), '-i', file, '-frames:v', '1', '-filter_complex',
    `[0:v]split[x][y];[x]crop=${rgb[2]}:${rgb[3]}:${rgb[0]}:${rgb[1]},scale=${sw}:${sh},format=rgb24[c];`
    + `[y]crop=${mask[2]}:${mask[3]}:${mask[0]}:${mask[1]},scale=${sw}:${sh},format=gray[a];[c][a]alphamerge,format=rgba[o]`,
    '-map', '[o]', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-'], { timeoutMs: 60000 });
  if (raw.length !== sw * sh * 4) return null;
  // içeriğin kutusu
  let x0 = sw; let y0 = sh; let x1 = -1; let y1 = -1;
  for (let y = 0; y < sh; y++) {
    for (let x = 0; x < sw; x++) {
      if (raw[(y * sw + x) * 4 + 3] > 20) {
        if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return null; // tamamen boş kare
  const cw = (x1 - x0 + 1); const ch = (y1 - y0 + 1);
  return run('ffmpeg', ['-v', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', `${sw}x${sh}`, '-i', '-',
    '-vf', `crop=${cw}:${ch}:${x0}:${y0},scale=256:256:force_original_aspect_ratio=decrease,pad=256:256:(ow-iw)/2:(oh-ih)/2:color=black@0`,
    '-frames:v', '1', '-f', 'image2', '-c:v', 'png', '-'], { input: raw, timeoutMs: 60000 });
}

/** Şeffaflığı olmayan videodan ortalardaki kareyi PNG ikon yapar (dönüştürmeden). */
async function iconFromPlain(file, info) {
  const t = info.duration > 0 ? info.duration * 0.55 : 1;
  return run('ffmpeg', ['-v', 'error', '-ss', String(t), '-i', file, '-frames:v', '1',
    '-vf', 'scale=256:256:force_original_aspect_ratio=decrease,pad=256:256:(ow-iw)/2:(oh-ih)/2:color=black@0,format=rgba',
    '-f', 'image2', '-c:v', 'png', '-'], { timeoutMs: 60000 });
}

/**
 * Yüklenen mp4'ü hazırlar. alpha: 'auto' | 'left' | 'right'. frame: çerçeve (kare tuval).
 * Döner: { buf (VAP mp4, vapc eklenmemiş), alpha ('left'|'right'), converted (bool), scene (bool), icon (PNG Buffer|null) }
 * ffmpeg yoksa null döner (çağıran eski yolu kullanır).
 */
// Aynı anda tek video işlenir (sunucuda ses sunucusu da çalışıyor; işlemciyi boğmasın).
let chain = Promise.resolve();
export function prepareMp4(buf, alpha = 'auto', opts = {}) {
  const p = chain.then(() => prepare(buf, alpha, opts));
  chain = p.catch(() => {});
  return p;
}

async function prepare(buf, alpha, { frame = false, iconOnly = false } = {}) {
  if (!(await ffmpegAvailable())) return null;
  return withTemp(buf, 'mp4', async (file) => {
    const info = await probe(file);
    if (!info.w || !info.h) return null;
    // Zaten VAP ayarı olan dosyaya dokunulmaz (maske ve renk bölgeleri dosyanın içinde yazılı).
    const vapc = vapcInfo(buf);
    if (vapc && Array.isArray(vapc.aFrame) && Array.isArray(vapc.rgbFrame)) {
      let icon = null;
      try { icon = await iconFromRects(file, info, vapc.rgbFrame, vapc.aFrame); } catch { icon = null; }
      return { buf, alpha: vapc.aFrame[0] > vapc.rgbFrame[0] ? 'right' : 'left', converted: false, scene: false, icon };
    }
    let side = alpha;
    let out = buf; let converted = false; let scene = false;
    const d = info.duration > 0 ? info.duration : 0;
    if (side === 'auto') {
      const mid = await grabRgb(file, d * 0.5, info.w, info.h);
      side = layoutOf(mid);
      if (side === 'plain') {
        // Sahne mi: üç karenin çoğunda kenarlar aydınlık / siyah az ise (tek bir parlama sahne sayılmaz).
        const stills = [mid];
        for (const k of [0.25, 0.75]) {
          try { stills.push(await grabRgb(file, d * k, info.w, info.h)); } catch { /* atla */ }
        }
        scene = stills.filter(isScene).length * 2 > stills.length;
        if (iconOnly) {
          let icon = null;
          try { icon = await iconFromPlain(file, info); } catch { icon = null; }
          return { buf, alpha: 'left', converted: false, scene, icon };
        }
        out = await convertPlain(file, info, scene, frame ? FRAME : GIFT);
        converted = true;
        side = 'left';
      }
    }
    let icon = null;
    try {
      if (converted) {
        icon = await withTemp(out, 'mp4', async (f2) => {
          const i2 = await probe(f2);
          const half = i2.w >> 1;
          return iconFromRects(f2, i2, [half, 0, half, i2.h], [0, 0, half, i2.h]);
        });
      } else {
        const half = info.w >> 1;
        const left = [0, 0, half, info.h]; const right = [half, 0, half, info.h];
        icon = await iconFromRects(file, info, side === 'right' ? left : right, side === 'right' ? right : left);
      }
    } catch { icon = null; }
    return { buf: out, alpha: side, converted, scene, icon };
  });
}
