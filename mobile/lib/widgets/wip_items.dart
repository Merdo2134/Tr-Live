import 'package:flutter/material.dart';
import 'common.dart';

/// WIP öğelerinin kodla çizilen önizlemesi (Görünüm sayfası ve yönetim): çerçeve, rozet, sohbet balonu,
/// giriş efekti ve araç.
Widget wipItemArt(String type, int level, double size) {
  final s = WipStyle.of(level);
  switch (type) {
    case 'frame':
      final r = size * 0.28;
      return SizedBox(
        width: size * 0.8,
        height: size * 0.8,
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          CircleAvatar(radius: r, backgroundColor: Colors.white12, child: Icon(Icons.person, size: r, color: Colors.white54)),
          WipFrame.around(level, r),
        ]),
      );
    case 'badge':
      return WipChip(level: level);
    case 'chat_bubble':
      return WipBubble(level: level, fallback: const Color(0x8C13285A), child: const Text('Merhaba', style: TextStyle(fontSize: 12)));
    case 'vehicle':
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: size * 0.62,
          height: size * 0.62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [(s?.color ?? Colors.purple).withValues(alpha: 0.55), Colors.transparent]),
          ),
          child: Text(s?.vehicle ?? '🚗', style: TextStyle(fontSize: size * 0.34)),
        ),
        Text(s?.vehicleName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white70)),
      ]);
    default:
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(gradient: LinearGradient(colors: s?.gradient ?? const [Colors.purple, Colors.pink]), borderRadius: BorderRadius.circular(10)),
        child: Text(wipLabel(level), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
      );
  }
}

/// WIP aracı odaya giriş: kademenin aracı (emoji) parlayan iz bırakarak sağdan gelir, ortada kısa durur
/// (hafifçe sallanır), soldan çıkar. Altında kademe rozeti ve araç adı.
class WipVehicleDrive extends StatefulWidget {
  final int level;
  final int durationMs;
  const WipVehicleDrive({super.key, required this.level, this.durationMs = 4600});

  @override
  State<WipVehicleDrive> createState() => _WipVehicleDriveState();
}

class _WipVehicleDriveState extends State<WipVehicleDrive> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.durationMs))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = WipStyle.of(widget.level);
    if (s == null) return const SizedBox.shrink();
    final w = MediaQuery.sizeOf(context).width;
    final size = w * 0.34;
    final colors = s.gradient;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          const inEnd = 0.22, outStart = 0.78;
          double dx;
          var moving = true;
          if (t < inEnd) {
            dx = (1 - Curves.easeOutCubic.transform(t / inEnd)) * w;
          } else if (t > outStart) {
            dx = -Curves.easeInCubic.transform((t - outStart) / (1 - outStart)) * w;
          } else {
            dx = 0;
            moving = false;
          }
          final bob = (t * widget.durationMs / 140) % 2 < 1 ? 2.0 : -2.0;
          return Transform.translate(
            offset: Offset(dx, bob),
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              // Hareket ederken arkasında renkli iz.
              Positioned(
                left: size * 0.55,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: moving ? 1 : 0.35,
                  child: Container(
                    width: w * 0.5,
                    height: size * 0.28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      gradient: LinearGradient(colors: [for (final c in colors) c.withValues(alpha: 0.75), Colors.transparent]),
                    ),
                  ),
                ),
              ),
              child!,
            ]),
          );
        },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [s.color.withValues(alpha: 0.6), s.color.withValues(alpha: 0.0)]),
            ),
            child: Text(s.vehicle, style: TextStyle(fontSize: size * 0.62, shadows: [Shadow(color: s.color, blurRadius: 18)])),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white54, width: 0.8)),
            child: Text('${s.label} · ${s.vehicleName}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 2)])),
          ),
        ]),
      ),
    );
  }
}
