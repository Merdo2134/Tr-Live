import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_vap_kit/flutter_vap_kit.dart';
import 'package:lottie/lottie.dart';
import '../services/media_cache.dart';
import 'svga_lite.dart';

/// Adresin uzantısına göre doğru oynatıcıyı seçer: svga, Lottie (json), şeffaf mp4 (VAP), webp/gif/png.
/// [repeat] true ise döngüde oynar (avatar çerçevesi); false ise bir kez oynar ve [onDone] çağrılır.
class AnimAsset extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final bool repeat;
  final VoidCallback? onDone;
  final String? format;
  /// Oynatılamazsa nedenini bildirir (ekranda gösterilir; sorun bulmak için).
  final ValueChanged<String>? onFail;
  /// true: dosya telefon belleğine indirilir (hediyeler). false: doğrudan internetten oynar (çerçeveler).
  final bool cache;
  const AnimAsset({super.key, required this.url, this.fit = BoxFit.contain, this.repeat = false, this.onDone, this.format, this.onFail, this.cache = true});

  static String extOf(String url) {
    final path = url.toLowerCase().split('?').first;
    final i = path.lastIndexOf('.');
    return i < 0 ? '' : path.substring(i + 1);
  }

  /// Oynatıcının kendi bitişini bildirdiği türler (diğerleri için çağıran zamanlayıcı kullanır).
  static bool reportsEnd(String url, [String? format]) {
    final e = extOf(url);
    return e == 'svga' || e == 'mp4' || e == 'json' || format == 'svga' || format == 'mp4' || format == 'lottie';
  }

  @override
  State<AnimAsset> createState() => _AnimAssetState();
}

class _AnimAssetState extends State<AnimAsset> {
  File? _file;

  bool _failed = false;
  bool _done = false;
  Timer? _doneTimer;

  @override
  void initState() {
    super.initState();
    if (widget.cache) _resolve();
  }

  @override
  void dispose() {
    _doneTimer?.cancel();
    super.dispose();
  }

  /// Oynatma bitti: yalnızca bir kez ve bu parça hâlâ ekrandayken bildirilir
  /// (eski bir zamanlayıcı sıradaki hediyenin animasyonunu erken kesmesin).
  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone?.call();
  }

  /// Hata bir kez ve çizim bittikten sonra bildirilir (build sırasında bildirim/kayıt açmak sorun çıkarır).
  void _fail(String message) {
    if (_failed) return;
    _failed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFail?.call(message);
    });
  }

  Future<void> _resolve() async {
    try {
      final f = await MediaCache.get(widget.url);
      if (mounted) setState(() => _file = f);
    } catch (e) {
      if (mounted) {
        _fail('İndirilemedi: $e');
        _finish();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final ext = AnimAsset.extOf(w.url);
    final fmt = w.format ?? '';
    if (!w.cache) return _network(w, ext, fmt);
    final file = _file;
    if (file == null) return const SizedBox.shrink();
    if (ext == 'svga' || fmt == 'svga') return SvgaLite(file: file, fit: w.fit, repeat: w.repeat, onDone: w.onDone == null ? null : _finish, onFail: w.onFail == null ? null : _fail);
    if (ext == 'mp4' || fmt == 'mp4') {
      return VapPlayer.file(file.path, fit: w.fit, loop: w.repeat, onComplete: w.repeat ? null : _finish, onError: (err) {
        _fail('MP4 oynatılamadı: $err');
        _finish();
      });
    }
    if (ext == 'json' || fmt == 'lottie') {
      return Lottie.file(
        file,
        fit: w.fit,
        repeat: w.repeat,
        onLoaded: (c) {
          if (!w.repeat && w.onDone != null) {
            _doneTimer?.cancel();
            _doneTimer = Timer(c.duration + const Duration(milliseconds: 300), _finish);
          }
        },
        errorBuilder: (_, err, ___) {
          _fail('Lottie açılamadı: $err');
          return const SizedBox.shrink();
        },
      );
    }
    return Image.file(file, fit: w.fit, gaplessPlayback: true, errorBuilder: (_, err, ___) {
      _fail('Görsel açılamadı: $err');
      return const SizedBox.shrink();
    });
  }

  Widget _network(AnimAsset w, String ext, String fmt) {
    if (ext == 'svga' || fmt == 'svga') return SvgaLite(url: w.url, fit: w.fit, repeat: w.repeat, onDone: w.onDone == null ? null : _finish, onFail: w.onFail == null ? null : _fail);
    if (ext == 'mp4' || fmt == 'mp4') {
      return VapPlayer.network(w.url, fit: w.fit, loop: w.repeat, onComplete: w.repeat ? null : _finish, onError: (err) {
        _fail('MP4 oynatılamadı: $err');
        _finish();
      });
    }
    if (ext == 'json' || fmt == 'lottie') {
      return Lottie.network(w.url, fit: w.fit, repeat: w.repeat, errorBuilder: (_, err, ___) {
        _fail('Lottie açılamadı: $err');
        return const SizedBox.shrink();
      });
    }
    return Image.network(w.url, fit: w.fit, gaplessPlayback: true, errorBuilder: (_, err, ___) {
      _fail('Görsel açılamadı: $err');
      return const SizedBox.shrink();
    });
  }
}
