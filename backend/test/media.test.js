import test from 'node:test';
import assert from 'node:assert/strict';
import zlib from 'node:zlib';
import { detectMedia, ensureVapc } from '../src/services/media.js';

const pad = (b) => Buffer.concat([b, Buffer.alloc(16)]);

test('png, webp, gif, jpg içerikten tanınır', () => {
  assert.equal(detectMedia(pad(Buffer.from([0x89, 0x50, 0x4e, 0x47]))).kind, 'png');
  assert.equal(detectMedia(pad(Buffer.from('RIFF\0\0\0\0WEBP'))).kind, 'webp');
  assert.equal(detectMedia(pad(Buffer.from('GIF89a'))).kind, 'gif');
  assert.equal(detectMedia(pad(Buffer.from([0xff, 0xd8, 0xff, 0xe0]))).kind, 'jpg');
});

test('svga 2.x zlib içeriğinden tanınır, rastgele zlib reddedilir', () => {
  const svga = zlib.deflateSync(Buffer.concat([Buffer.from([0x0a, 0x05]), Buffer.from('2.1.0'), Buffer.alloc(50)]));
  assert.equal(detectMedia(svga).kind, 'svga');
  assert.throws(() => detectMedia(zlib.deflateSync(Buffer.from('merhaba dünya, bu svga değil'.repeat(5)))));
});

test('Lottie json kabul edilir; dışarıdan görselli Lottie ve PAG reddedilir', () => {
  const ok = Buffer.from(JSON.stringify({ v: '5', fr: 25, ip: 0, op: 50, w: 100, h: 100, layers: [], assets: [] }));
  assert.equal(detectMedia(ok).kind, 'json');
  const ext = Buffer.from(JSON.stringify({ fr: 25, ip: 0, op: 50, w: 1, h: 1, layers: [], assets: [{ u: 'images/', p: 'a.png' }] }));
  assert.throws(() => detectMedia(ext), /ayrı klasör/);
  assert.throws(() => detectMedia(pad(Buffer.from('PAG\x01'))), /PAG/);
});

test('mp4 olmayan veya bozuk dosyada vapc eklenmez', () => {
  assert.throws(() => ensureVapc(pad(Buffer.from('\0\0\0\x08ftyp')), 'left'));
});

test('hareketli görsel tespiti: gif ve animasyonlu webp', async () => {
  const { isAnimatedImage } = await import('../src/services/media.js');
  assert.equal(isAnimatedImage(Buffer.from('GIF89a' + '\0'.repeat(20))), 'gif');
  const webp = Buffer.alloc(40); webp.write('RIFF', 0); webp.write('WEBP', 8); webp.write('VP8X', 12); webp[20] = 0x02;
  assert.equal(isAnimatedImage(webp), 'webp');
  webp[20] = 0;
  assert.equal(isAnimatedImage(webp), null);
});
