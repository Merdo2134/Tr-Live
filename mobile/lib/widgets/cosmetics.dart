import 'package:flutter/material.dart';
import 'anim_asset.dart';
import 'net_image.dart';

/// Mağazadan alınıp takılan sohbet balonu: görsel, mesajın arkasına balonu dolduracak şekilde gerilir.
class StoreBubble extends StatelessWidget {
  final String url;
  final BoxConstraints? constraints;
  final Widget child;
  const StoreBubble({super.key, required this.url, required this.child, this.constraints});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: constraints,
      child: Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: NetImg(url, fit: BoxFit.fill, errorBuilder: (_, __, ___) => Container(decoration: BoxDecoration(color: const Color(0x8C13285A), borderRadius: BorderRadius.circular(14)))),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 10), child: child),
      ]),
    );
  }
}

/// Mağazadan alınan mikrofon dalgası: konuşurken avatarın çevresinde nabız gibi büyüyüp küçülür.
class MicWave extends StatefulWidget {
  final String url;
  const MicWave({super.key, required this.url});

  @override
  State<MicWave> createState() => _MicWaveState();
}

class _MicWaveState extends State<MicWave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.08).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
          child: AnimAsset(key: ValueKey(widget.url), url: widget.url, repeat: true, cache: false),
        ),
      ),
    );
  }
}

/// Profil kartı / oda kartı arka planı: görsel kartı kaplar, üstüne yazılar okunsun diye hafif karartma.
DecorationImage? cardBackground(String? url) => url == null
    ? null
    : DecorationImage(
        image: NetworkImage(url),
        fit: BoxFit.cover,
        colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.35), BlendMode.darken),
        onError: (_, __) {},
      );
