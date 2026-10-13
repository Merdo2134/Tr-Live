import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// İnternetten gelen görseller için telefon önbelleği.
/// Sunucudaki görsel adresleri değişmez (yeni yükleme = yeni adres), bu yüzden bir kez inen dosya tekrar indirilmez:
/// uygulama her açıldığında avatarlar, oda kapakları ve bannerlar yeniden indirilmez (sunucu ve internet yükü azalır).
class ImageDiskCache {
  ImageDiskCache._();
  static Directory? _dir;
  static final Map<String, Future<Uint8List>> _inflight = {};
  static final http.Client _client = http.Client();
  static const int maxBytes = 200 * 1024 * 1024;
  static DateTime? _lastTrim;

  static Future<Directory> _root() async {
    final d = _dir ?? Directory('${Directory.systemTemp.path}/trlive_img');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  static String _name(String url) {
    final last = url.split('?').first.split('/').last;
    final safe = last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final h = url.hashCode.toUnsigned(32).toRadixString(16);
    return '${h}_${safe.length > 60 ? safe.substring(safe.length - 60) : safe}';
  }

  /// Görsel baytları: telefonda varsa oradan, yoksa indirip kaydederek.
  static Future<Uint8List> load(String url) {
    return _inflight.putIfAbsent(url, () async {
      try {
        // Önbellek klasörü açılamazsa görsel yine de indirilip gösterilir (yalnızca saklanmaz).
        Directory? dir;
        try {
          dir = await _root();
        } catch (_) {
          dir = null;
        }
        final f = dir == null ? null : File('${dir.path}/${_name(url)}');
        if (f != null) {
          try {
            final b = await f.readAsBytes();
            if (b.isNotEmpty) return b;
          } catch (_) {/* yok: indirilecek */}
        }
        final uri = Uri.parse(url);
        final r = await _client.get(uri).timeout(const Duration(seconds: 45));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw NetworkImageLoadException(statusCode: r.statusCode, uri: uri);
        final bytes = r.bodyBytes;
        if (dir != null && f != null) unawaited(_store(dir, f, bytes));
        return bytes;
      } finally {
        _inflight.remove(url);
      }
    });
  }

  /// Saklanan dosya bozuksa (görsel değilse) silinir; sonraki açılışta yeniden indirilir.
  static Future<void> forget(String url) async {
    try {
      final dir = await _root();
      final f = File('${dir.path}/${_name(url)}');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<void> _store(Directory dir, File f, Uint8List bytes) async {
    try {
      final tmp = File('${f.path}.part');
      await tmp.writeAsBytes(bytes, flush: false);
      await tmp.rename(f.path);
      // Boyut denetimi en fazla 10 dakikada bir (her indirmede klasörü taramak gereksiz iş).
      final now = DateTime.now();
      if (_lastTrim == null || now.difference(_lastTrim!) > const Duration(minutes: 10)) {
        _lastTrim = now;
        await _trim(dir);
      }
    } catch (_) {/* kaydedilemese de görsel gösterilir */}
  }

  static Future<void> _trim(Directory dir) async {
    final files = <(File, int, DateTime)>[];
    var total = 0;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      if (e.path.endsWith('.part')) continue;
      final st = await e.stat();
      files.add((e, st.size, st.modified));
      total += st.size;
    }
    if (total <= maxBytes) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (f, size, _) in files) {
      if (total <= maxBytes * 0.7) break;
      try {
        await f.delete();
        total -= size;
      } catch (_) {}
    }
  }
}

/// Önbellekli ve ekrandaki boyutunda çözülen ağ görseli.
/// [targetW]/[targetH]: görselin çizileceği alan (cihaz pikseli). Görsel bu alandan büyükse çözülürken küçültülür
/// (4000 px'lik bir fotoğrafı 100 px'lik kutu için tam çözmek belleği ve işlemciyi boşuna yorar). Büyütme yapılmaz.
/// [cover]: alanı tamamen örtecek kadar (BoxFit.cover), değilse alana sığacak kadar (contain) küçültülür.
@immutable
class NetImage extends ImageProvider<NetImage> {
  final String url;
  final int? targetW;
  final int? targetH;
  final bool cover;
  const NetImage(this.url, {this.targetW, this.targetH, this.cover = true});

  /// Mantıksal boyuttan hedef piksel: 32'nin katına yuvarlanır (yakın boyutlar aynı önbellek kaydını kullanır).
  static int? px(double? logical, double dpr) {
    if (logical == null || !logical.isFinite || logical <= 0) return null;
    return ((logical * dpr) / 32).ceil() * 32;
  }

  @override
  Future<NetImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<NetImage>(this);

  @override
  ImageStreamCompleter loadImage(NetImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[DiagnosticsProperty<ImageProvider>('Image provider', this)],
    );
  }

  Future<ui.Codec> _load(NetImage key, ImageDecoderCallback decode) async {
    var loaded = false;
    try {
      final bytes = await ImageDiskCache.load(key.url);
      loaded = true;
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final tw = key.targetW;
      final th = key.targetH;
      if (tw == null && th == null) return decode(buffer);
      return decode(buffer, getTargetSize: (int iw, int ih) {
        if (iw <= 0 || ih <= 0) return const ui.TargetImageSize();
        final double s;
        if (tw != null && th != null) {
          s = key.cover ? math.max(tw / iw, th / ih) : math.min(tw / iw, th / ih);
        } else if (tw != null) {
          s = tw / iw;
        } else {
          s = th! / ih;
        }
        if (s >= 1) return const ui.TargetImageSize();
        return ui.TargetImageSize(width: math.max(1, (iw * s).round()), height: math.max(1, (ih * s).round()));
      });
    } catch (_) {
      // Hatalı görsel önbellekte kalmasın: sonraki çizimde yeniden denensin. İnen dosya görsel değilse
      // (ör. hata sayfası) telefondaki kopyası da silinir.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      if (loaded) unawaited(ImageDiskCache.forget(key.url));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) => other is NetImage && other.url == url && other.targetW == targetW && other.targetH == targetH && other.cover == cover;

  @override
  int get hashCode => Object.hash(url, targetW, targetH, cover);

  @override
  String toString() => 'NetImage("$url", $targetW×$targetH)';
}

/// Image.network yerine: telefon önbelleğinden okur ve ekrandaki boyutunda çözer.
/// Genişlik/yükseklik verilmezse görsel en fazla ekran boyutunda çözülür.
class NetImg extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageErrorWidgetBuilder? errorBuilder;
  final bool gaplessPlayback;
  /// Çizim alanı biliniyorsa (ör. kare kart): mantıksal piksel. width/height'tan önce gelir.
  final Size? box;
  /// Tam çözünürlük (yakınlaştırılabilen fotoğraf görüntüleyici).
  final bool fullRes;
  const NetImg(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.gaplessPlayback = false,
    this.box,
    this.fullRes = false,
  });

  @override
  Widget build(BuildContext context) {
    // Yalnızca ekran ölçüsüne ve piksel yoğunluğuna bağlı: klavye açılıp kapanınca görseller yeniden kurulmaz.
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
    final screen = MediaQuery.maybeSizeOf(context) ?? const Size(420, 900);
    double? fin(double? v) => v != null && v.isFinite && v > 0 ? v : null;
    final bw = fin(box?.width ?? width);
    final bh = fin(box?.height ?? height);
    final NetImage provider;
    if (fullRes) {
      provider = NetImage(url);
    } else if (bw != null || bh != null) {
      provider = NetImage(url, targetW: NetImage.px(bw, dpr), targetH: NetImage.px(bh, dpr), cover: fit == BoxFit.cover || fit == BoxFit.fill);
    } else if (fit == BoxFit.cover || fit == BoxFit.fill || fit == BoxFit.fitWidth) {
      // Alan bilinmiyor ve görsel alanı örtecek: genişlik en fazla ekran genişliği kadar (uzun görsel bulanıklaşmasın).
      provider = NetImage(url, targetW: NetImage.px(screen.width, dpr));
    } else {
      provider = NetImage(url, targetW: NetImage.px(screen.width, dpr), targetH: NetImage.px(screen.height, dpr), cover: false);
    }
    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: gaplessPlayback,
      filterQuality: FilterQuality.medium,
      errorBuilder: errorBuilder ?? (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
