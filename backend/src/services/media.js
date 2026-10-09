import zlib from 'node:zlib';
import { fail } from '../http.js';

export const MEDIA_MAX_BYTES = 40 * 1024 * 1024;
const MIME = { png: 'image/png', jpg: 'image/jpeg', webp: 'image/webp', gif: 'image/gif', mp4: 'video/mp4', json: 'application/json', svga: 'application/octet-stream' };

/** Dosyanın uzantısına değil gerçek içeriğine bakarak türünü bulur. */
export function detectMedia(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 12) throw fail('Dosya boş veya çok küçük.');
  const b = buf;
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) {
    if (b.subarray(0, Math.min(b.length, 4096)).includes(Buffer.from('acTL'))) throw fail('Hareketli PNG (APNG) uygulamada oynamaz. Aynı animasyonun webp, gif veya svga sürümünü yükleyin.');
    return { kind: 'png', ext: 'png' };
  }
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { kind: 'jpg', ext: 'jpg' };
  if (b.toString('ascii', 0, 4) === 'RIFF' && b.toString('ascii', 8, 12) === 'WEBP') return { kind: 'webp', ext: 'webp' };
  if (b.toString('ascii', 0, 4) === 'GIF8') return { kind: 'gif', ext: 'gif' };
  if (b.toString('ascii', 4, 8) === 'ftyp') return { kind: 'mp4', ext: 'mp4' };
  if (b.toString('ascii', 0, 3) === 'PAG') throw fail('PAG dosyaları henüz desteklenmiyor. Aynı animasyonun svga, mp4 veya Lottie sürümünü yükleyin.');
  if (b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3) throw fail('WebM desteklenmiyor. Şeffaf MP4 (VAP) veya svga kullanın.');
  if (b[0] === 0x50 && b[1] === 0x4b) {
    if (b.includes(Buffer.from('movie.spec'))) throw fail('Eski svga 1.x biçimi desteklenmiyor; svga 2.x yükleyin.');
    throw fail('Zip dosyası yüklenemez; zip içindeki dosyayı tek tek yükleyin.');
  }
  if (b[0] === 0x78) {
    try {
      const head = zlib.inflateSync(b.subarray(0, Math.min(b.length, 8192)), { finishFlush: zlib.constants.Z_SYNC_FLUSH });
      if (head.length > 8 && head[0] === 0x0a && head.toString('latin1', 2, 3) === '2') return { kind: 'svga', ext: 'svga' };
    } catch (_) { /* svga değil */ }
  }
  if (b[0] === 0x7b || (b[0] === 0xef && b[3] === 0x7b)) {
    let j;
    try { j = JSON.parse(b.toString('utf8').replace(/^﻿/, '')); } catch { throw fail('JSON dosyası okunamadı.'); }
    if (!(Array.isArray(j.layers) && j.fr && j.w && j.h)) throw fail('Bu JSON bir Lottie animasyonu değil.');
    const external = (j.assets ?? []).some((a) => a && a.p && a.u && !String(a.p).startsWith('data:'));
    if (external) throw fail('Bu Lottie görselleri ayrı klasörde tutuyor. Görselleri içine gömen "birleşik JSON" sürümünü yükleyin.');
    return { kind: 'json', ext: 'json', meta: { w: j.w, h: j.h, frames: Math.round(j.op - j.ip), fps: j.fr } };
  }
  throw fail('Dosya biçimi tanınmadı. Desteklenenler: mp4, svga, Lottie json, webp, gif, png, jpg.');
}

export function mimeFor(ext) { return MIME[ext] ?? 'application/octet-stream'; }

function boxes(buf, start, end) {
  const out = [];
  let o = start;
  while (o + 8 <= end) {
    let size = buf.readUInt32BE(o);
    const type = buf.toString('latin1', o + 4, o + 8);
    let hdr = 8;
    if (size === 1) { size = Number(buf.readBigUInt64BE(o + 8)); hdr = 16; }
    if (size === 0) size = end - o;
    if (size < hdr || o + size > end) break;
    out.push({ type, start: o, size, hdr });
    o += size;
  }
  return out;
}

/** Yan yana alfa-renk düzenli mp4'e Tencent VAP ayar kutusunu (vapc) ekler. alpha: 'left' | 'right' */
export function ensureVapc(buf, alpha = 'left') {
  const top = boxes(buf, 0, buf.length);
  if (top.some((x) => x.type === 'vapc')) return { buf, injected: false };
  const moov = top.find((x) => x.type === 'moov');
  if (!moov) throw fail('MP4 dosyası geçersiz (moov yok).');
  const mdat = top.find((x) => x.type === 'mdat');
  let width = 0; let height = 0; let frames = 0; let fps = 25;
  for (const trak of boxes(buf, moov.start + 8, moov.start + moov.size).filter((x) => x.type === 'trak')) {
    const kids = boxes(buf, trak.start + 8, trak.start + trak.size);
    const tkhd = kids.find((x) => x.type === 'tkhd');
    const w = tkhd ? buf.readUInt32BE(tkhd.start + tkhd.size - 8) >>> 16 : 0;
    const h = tkhd ? buf.readUInt32BE(tkhd.start + tkhd.size - 4) >>> 16 : 0;
    if (!w || !h) continue;
    width = w; height = h;
    const mdia = kids.find((x) => x.type === 'mdia');
    const mk = boxes(buf, mdia.start + 8, mdia.start + mdia.size);
    const mdhd = mk.find((x) => x.type === 'mdhd');
    const minf = mk.find((x) => x.type === 'minf');
    const stbl = boxes(buf, minf.start + 8, minf.start + minf.size).find((x) => x.type === 'stbl');
    const stsz = boxes(buf, stbl.start + 8, stbl.start + stbl.size).find((x) => x.type === 'stsz');
    frames = buf.readUInt32BE(stsz.start + 16);
    const ver = buf[mdhd.start + 8];
    const scale = buf.readUInt32BE(mdhd.start + (ver === 1 ? 28 : 20));
    const dur = ver === 1 ? Number(buf.readBigUInt64BE(mdhd.start + 32)) : buf.readUInt32BE(mdhd.start + 24);
    if (dur > 0 && scale > 0) fps = Math.max(1, Math.round(frames / (dur / scale)));
    break;
  }
  if (!width || !height || !frames) throw fail('MP4 video bilgisi okunamadı.');
  if (width % 2) throw fail('Yan yana düzen için video genişliği çift olmalı.');
  const half = width / 2;
  const [aX, rX] = alpha === 'right' ? [half, 0] : [0, half];
  const json = Buffer.from(JSON.stringify({ info: { v: 2, f: frames, w: half, h: height, fps, videoW: width, videoH: height, aFrame: [aX, 0, half, height], rgbFrame: [rX, 0, half, height], isVapx: 0, orien: 0 } }));
  const box = Buffer.alloc(8 + json.length);
  box.writeUInt32BE(box.length, 0);
  box.write('vapc', 4, 'latin1');
  json.copy(box, 8);
  const at = moov.start + moov.size;
  const out = Buffer.concat([buf.subarray(0, at), box, buf.subarray(at)]);
  if (mdat && mdat.start > moov.start) shiftOffsets(out, moov.start, moov.size, box.length);
  return { buf: out, injected: true, info: { frames, fps, width, height } };
}

function shiftOffsets(buf, moovStart, moovSize, delta) {
  const walk = (s, e) => {
    for (const x of boxes(buf, s, e)) {
      if (['trak', 'mdia', 'minf', 'stbl'].includes(x.type)) walk(x.start + 8, x.start + x.size);
      else if (x.type === 'stco') {
        const n = buf.readUInt32BE(x.start + 12);
        for (let i = 0; i < n; i++) { const p = x.start + 16 + i * 4; buf.writeUInt32BE(buf.readUInt32BE(p) + delta, p); }
      } else if (x.type === 'co64') {
        const n = buf.readUInt32BE(x.start + 12);
        for (let i = 0; i < n; i++) { const p = x.start + 16 + i * 8; buf.writeBigUInt64BE(buf.readBigUInt64BE(p) + BigInt(delta), p); }
      }
    }
  };
  walk(moovStart + 8, moovStart + moovSize);
}
