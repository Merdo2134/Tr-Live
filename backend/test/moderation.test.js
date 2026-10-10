import test from 'node:test';
import assert from 'node:assert/strict';
import { findLink, findPhone } from '../src/text_safety.js';
import { publicTextProblem } from '../src/safe_text.js';
import { classifyText } from '../src/services/moderation.js';
import { compareVersions, validateConfigPatch } from '../src/services/app_config.js';
import { cleanDevice, maskIp, REFRESH_RE } from '../src/services/sessions.js';

test('link tespiti: açık ve gizlenmiş adresler yakalanır', () => {
  for (const s of [
    'www.site.com', 'gir: https://x.co', 'ali.com', 'trlive . com', 't.me/kanal', 'instagram.com/abc', 'insta: @ahmet_12',
    'telegram @kanal1', 'discord.gg/abc', 'site nokta com', 'ali(dot)net', 'bit.ly/x', 'ahmet@gmail.com', 'youtu.be/xx', 'h t t p s : / / x',
    'kanal nokta tv', 'site[.]co',
  ]) assert.equal(findLink(s), true, s);
});

test('link tespiti: noktadan sonra boşluk unutulan Türkçe cümleler link sayılmaz', () => {
  for (const s of [
    'tamam.biz geliyoruz', 'evet.de', 'saat 10.30 da', '5.000.000 coin', 'hadi.top oynayalım', 'merhaba nasılsın',
    'a.b.c', 'wp den yaz', '3.5 puan', 'ben.sen.o', 'İyi akşamlar.Tv izliyorum', 'Sınav 2.5 saat sürdü',
    'aksamlar.Tv izliyorum', 'Geldim.Az sonra', 'ali.tv izledin mi', 'Ahmet.Co ile', 'Bu nokta de önemli',
  ]) assert.equal(findLink(s), false, s);
});

test('telefon tespiti: Türkiye cep ve uluslararası numaralar; büyük sayılar numara sayılmaz', () => {
  for (const s of ['0532 123 45 67', '+90 532 123 4567', '5321234567', '0(532)-123-45-67', '+44 7911 123456']) assert.equal(findPhone(s), true, s);
  for (const s of ['5.000.000.000 coin', '1000000000', '2026 yılında 15 bin', '100 200 300 400', '0500 000 00 00', 'ID: 10023456']) assert.equal(findPhone(s), false, s);
});

test('moderasyon sınıflandırması: bağlam ve personel istisnası', () => {
  assert.equal(classifyText('aaaaaaaaaaaaaaaaaaaa', { context: 'room_chat' }), 'flood');
  assert.equal(classifyText('www.site.com gel', { context: 'room_chat' }), 'link');
  assert.equal(classifyText('www.site.com gel', { context: 'room_chat', staff: true }), null, 'yönetici link paylaşabilir');
  assert.equal(classifyText('www.site.com gel', { context: 'room_chat', blockLinks: false }), null, 'ayardan kapatılabilir');
  assert.equal(classifyText('numaram 0532 123 45 67', { context: 'room_chat' }), 'phone');
  assert.equal(classifyText('numaram 0532 123 45 67', { context: 'dm' }), null, 'arkadaşa özel mesajda numara serbest');
  assert.equal(classifyText('merhaba', { context: 'dm' }), null);
});

test('herkese açık metin: link ve telefon reddedilir', () => {
  assert.match(publicTextProblem('instagram.com/benim'), /link/);
  assert.match(publicTextProblem('Ara 0532 123 45 67'), /telefon/);
  assert.equal(publicTextProblem('Mehmet Ali'), null);
  assert.equal(publicTextProblem(''), null);
});

test('sürüm karşılaştırma ve uzaktan ayar doğrulaması', () => {
  assert.equal(compareVersions('2.36.0', '2.36.0'), 0);
  assert.equal(compareVersions('2.9.0', '2.36.0'), -1, 'sayısal karşılaştırma (metin değil)');
  assert.equal(compareVersions('3.0.0', '2.99.99'), 1);
  assert.equal(compareVersions(undefined, '0.0.1'), -1, 'sürüm göndermeyen eski uygulama 0.0.0 sayılır');
  assert.equal(compareVersions('abc', '0.0.0'), 0);
  assert.deepEqual(validateConfigPatch({ minAppVersion: '2.36.0', blockLinks: false, strikeLimit: 5 }), { minAppVersion: '2.36.0', blockLinks: false, strikeLimit: 5 });
  assert.throws(() => validateConfigPatch({ minAppVersion: '2.36' }), /Sürüm/);
  assert.throws(() => validateConfigPatch({ hacker: true }), /Bilinmeyen/);
  assert.throws(() => validateConfigPatch({ strikeLimit: 0 }), /arasında/);
  assert.throws(() => validateConfigPatch({ updateUrl: 'http://x.com/a.apk' }), /https/);
  assert.throws(() => validateConfigPatch({ blockLinks: 'evet' }), /true\/false/);
});

test('cihaz bilgisi temizlenir, IP maskelenir', () => {
  const d = cleanDevice({ id: 'abcDEF12_-', name: ' Samsung‮ SM-A515F ', platform: 'android', appVersion: '2.36.0', emulator: true, extra: 'x' });
  assert.deepEqual(d, { id: 'abcDEF12_-', name: 'Samsung SM-A515F', platform: 'android', appVersion: '2.36.0', emulator: true });
  assert.deepEqual(cleanDevice({ id: 'kısa', platform: 'windows', appVersion: '2.36' }), { id: null, name: null, platform: null, appVersion: null, emulator: false });
  assert.deepEqual(cleanDevice(null), { id: null, name: null, platform: null, appVersion: null, emulator: false });
  assert.equal(maskIp('85.105.12.34'), '85.105.x.x');
  assert.equal(maskIp('2a02:e0:1:2::5'), '2a02:e0:…');
  assert.equal(maskIp(null), null);
  assert.ok(REFRESH_RE.test(`rt_${'A'.repeat(43)}`));
  assert.ok(!REFRESH_RE.test('rt_kısa'));
});

test('link tespiti uzun girdide yavaşlamaz', () => {
  const t = Date.now();
  findLink('a'.repeat(100000));
  findLink('ab-'.repeat(5000));
  findLink('x nokta '.repeat(2000));
  findPhone('1 '.repeat(20000));
  assert.ok(Date.now() - t < 1000);
});

test('hediye combo sayacı: pencere içinde artar, süre geçince sıfırlanır', async () => {
  const { nextCombo, COMBO_WINDOW_MS } = await import('../src/combo.js');
  assert.equal(nextCombo('k', 1000), 1);
  assert.equal(nextCombo('k', 2000), 2);
  assert.equal(nextCombo('k', 2000 + COMBO_WINDOW_MS), 3, 'pencere sınırında hâlâ combo');
  assert.equal(nextCombo('k', 2000 + COMBO_WINDOW_MS * 3), 1, 'uzun aradan sonra yeniden başlar');
  assert.equal(nextCombo('baska', 2000), 1, 'farklı hediye/alıcı ayrı sayılır');
});
