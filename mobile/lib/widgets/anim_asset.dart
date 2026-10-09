import 'package:flutter/material.dart';
import 'package:flutter_vap_kit/flutter_vap_kit.dart';
import 'package:lottie/lottie.dart';
import 'package:svgaplayer_flutter/svgaplayer_flutter.dart';

/// Adresin uzantısına göre doğru oynatıcıyı seçer: svga, Lottie (json), şeffaf mp4 (VAP), webp/gif/png.
/// [repeat] true ise döngüde oynar (avatar çerçevesi); false ise bir kez oynar ve [onDone] çağrılır.
class AnimAsset extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final bool repeat;
  final VoidCallback? onDone;
  final String? format;
  const AnimAsset({super.key, required this.url, this.fit = BoxFit.contain, this.repeat = false, this.onDone, this.format});

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
  Widget build(BuildContext context) {
    final e = extOf(url);
    final f = format ?? '';
    if (e == 'svga' || f == 'svga') return _SvgaView(url: url, fit: fit, repeat: repeat, onDone: onDone);
    if (e == 'mp4' || f == 'mp4') {
      return VapPlayer.network(url, fit: fit, loop: repeat, onComplete: repeat ? null : onDone, onError: (_) => onDone?.call());
    }
    if (e == 'json' || f == 'lottie') {
      return Lottie.network(
        url,
        fit: fit,
        repeat: repeat,
        onLoaded: (c) {
          if (!repeat && onDone != null) Future.delayed(c.duration + const Duration(milliseconds: 300), onDone!);
        },
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return Image.network(url, fit: fit, gaplessPlayback: true, errorBuilder: (_, __, ___) => const SizedBox.shrink());
  }
}

class _SvgaView extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final bool repeat;
  final VoidCallback? onDone;
  const _SvgaView({required this.url, required this.fit, required this.repeat, this.onDone});

  @override
  State<_SvgaView> createState() => _SvgaViewState();
}

class _SvgaViewState extends State<_SvgaView> with SingleTickerProviderStateMixin {
  late final SVGAAnimationController _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c = SVGAAnimationController(vsync: this);
    _load();
  }

  Future<void> _load() async {
    try {
      final item = await SVGAParser.shared.decodeFromURL(widget.url);
      if (!mounted) return;
      _c.videoItem = item;
      setState(() => _ready = true);
      if (widget.repeat) {
        _c.repeat();
      } else {
        _c.forward().whenComplete(() {
          if (mounted) widget.onDone?.call();
        });
      }
    } catch (_) {
      if (mounted) widget.onDone?.call();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return SVGAImage(_c, fit: widget.fit);
  }
}
