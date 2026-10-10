import 'dart:math' as math;
import 'package:flutter/material.dart';

/// SWIP (süper WIP) seviyesi: WIP 1–10'un üstündeki tek kademe (hayalet mod). Sunucudaki wip_tiers ile aynı.
const int kSwipLevel = 11;

/// "WIP 7" / "SWIP".
String wipLabel(int? level) {
  if (level == null || level < 1) return '';
  return level >= kSwipLevel ? 'SWIP' : 'WIP $level';
}

/// Dar yerler için: "W7" / "SW".
String wipShort(int level) => level >= kSwipLevel ? 'SW' : 'W$level';

/// Sunucudan sayı ya da metin gelebilir.
int? wipLevelOf(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

enum WipNameFx { plain, glow, pulse, shimmer, fire, ghost }

/// Kademe görünümü (Yoho VIP'teki gibi her kademenin kendi rengi, isim efekti, sohbet balonu, çerçevesi ve giriş aracı).
/// Ayrıcalıkların kendisi (oda sayısı, dokunulmazlık ...) sunucudan gelir; burası yalnızca görünüm.
class WipStyle {
  final int level;
  final String title;
  final Color color;
  /// Rozet, şerit ve çerçeve renkleri (açık tonlar).
  final List<Color> gradient;
  /// Sohbet balonu (koyu tonlar: beyaz yazı okunur kalsın).
  final List<Color> bubble;
  /// Balon köşesindeki süs ('' = yok).
  final String emblem;
  final String vehicle;
  final String vehicleName;
  final WipNameFx nameFx;
  final List<Color> nameColors;
  /// Giriş şeridinin ekranda kalma süresi.
  final int entranceMs;
  const WipStyle(this.level, this.title, this.color, this.gradient, this.bubble, this.emblem, this.vehicle, this.vehicleName, this.nameFx, this.nameColors, this.entranceMs);

  static WipStyle? of(int? level) {
    if (level == null || level < 1) return null;
    return _styles[level > kSwipLevel ? kSwipLevel : level];
  }

  static List<WipStyle> get all => [for (var i = 1; i <= kSwipLevel; i++) _styles[i]!];

  String get label => wipLabel(level);
  bool get isSwip => level >= kSwipLevel;
  /// 6 ve üzeri: dönen, parlayan çerçeve.
  bool get animatedFrame => level >= 6;
  /// 8 ve üzeri: çerçevede yıldız parıltıları.
  bool get sparkles => level >= 8;
  String get nameFxText => switch (nameFx) {
        WipNameFx.plain => level >= 3 ? 'Kalın renkli isim' : 'Renkli isim',
        WipNameFx.glow => 'Parlayan isim',
        WipNameFx.pulse => 'Neon nabız isim',
        WipNameFx.shimmer => 'Hareketli parıltılı isim',
        WipNameFx.fire => 'Ateşli isim',
        WipNameFx.ghost => 'Hayalet isim',
      };
}

const _gold = [Color(0xFFFFF8E1), Color(0xFFFFC43D), Color(0xFFFF8F00), Color(0xFFFFC43D), Color(0xFFFFF8E1)];
const _jade = [Color(0xFFB9F6CA), Color(0xFF00E5A0), Color(0xFF00897B), Color(0xFF00E5A0), Color(0xFFB9F6CA)];
const _ice = [Color(0xFF80D8FF), Color(0xFFFFFFFF), Color(0xFF2979FF), Color(0xFFFFFFFF), Color(0xFF80D8FF)];
const _rainbow = [Color(0xFFFF5252), Color(0xFFFFD740), Color(0xFF69F0AE), Color(0xFF40C4FF), Color(0xFFE040FB), Color(0xFFFF5252)];
const _fire = [Color(0xFFFFF176), Color(0xFFFF9800), Color(0xFFFF1744), Color(0xFFFF9800), Color(0xFFFFF176)];
const _ghost = [Color(0xFFFFFFFF), Color(0xFFC9B8FF), Color(0xFF7C4DFF), Color(0xFFC9B8FF), Color(0xFFFFFFFF)];

const Map<int, WipStyle> _styles = {
  1: WipStyle(1, 'Bronz', Color(0xFFCD7F32), [Color(0xFF8D5524), Color(0xFFCD7F32)], [Color(0xFF5D3A1A), Color(0xFF8D5524)], '',
      '🛵', 'Scooter', WipNameFx.plain, <Color>[], 1500),
  2: WipStyle(2, 'Gümüş', Color(0xFFC0C0C0), [Color(0xFF6E7B8B), Color(0xFFC9D1DA)], [Color(0xFF3E4A59), Color(0xFF6E7B8B)], '',
      '🏍️', 'Motosiklet', WipNameFx.plain, <Color>[], 1600),
  3: WipStyle(3, 'Altın', Color(0xFFFFD700), [Color(0xFF9C6A00), Color(0xFFFFD54A)], [Color(0xFF6B4A00), Color(0xFFA87C00)], '✦',
      '🚗', 'Klasik Araba', WipNameFx.plain, <Color>[], 1800),
  4: WipStyle(4, 'Zümrüt', Color(0xFF2ECC71), [Color(0xFF0B6E3B), Color(0xFF2ECC71)], [Color(0xFF0B4F2E), Color(0xFF178A4C)], '❖',
      '🚙', 'Arazi Aracı', WipNameFx.glow, <Color>[], 2000),
  5: WipStyle(5, 'Ametist', Color(0xFFB36BFF), [Color(0xFF4A1D96), Color(0xFFB36BFF)], [Color(0xFF3B1677), Color(0xFF7B3FD0)], '💜',
      '🏎️', 'Yarış Arabası', WipNameFx.pulse, <Color>[], 2200),
  6: WipStyle(6, 'Kraliyet', Color(0xFFFFC43D), [Color(0xFF7A4B00), Color(0xFFFFC43D), Color(0xFFFFF3C4)],
      [Color(0xFF6B3F00), Color(0xFFB8860B), Color(0xFF6B3F00)], '👑', '🛥️', 'Lüks Yat', WipNameFx.shimmer, _gold, 2400),
  7: WipStyle(7, 'Yeşim', Color(0xFF00E5A0), [Color(0xFF004D40), Color(0xFF00BFA5), Color(0xFFA7FFEB)],
      [Color(0xFF00443A), Color(0xFF00897B)], '🌿', '🚁', 'Helikopter', WipNameFx.shimmer, _jade, 2600),
  8: WipStyle(8, 'Buz', Color(0xFF80D8FF), [Color(0xFF0D47A1), Color(0xFF2979FF), Color(0xFF80D8FF)],
      [Color(0xFF0D3B8A), Color(0xFF1E88E5), Color(0xFF0D3B8A)], '❄️', '🛩️', 'Özel Jet', WipNameFx.shimmer, _ice, 2800),
  9: WipStyle(9, 'Gökkuşağı', Color(0xFFFF7AD9), [Color(0xFFFF5252), Color(0xFFFFD740), Color(0xFF69F0AE), Color(0xFF40C4FF), Color(0xFFE040FB)],
      [Color(0xFFB71C1C), Color(0xFFEF6C00), Color(0xFF2E7D32), Color(0xFF1565C0), Color(0xFF6A1B9A)], '🌈', '🚀', 'Roket', WipNameFx.shimmer, _rainbow, 3000),
  10: WipStyle(10, 'Ateş', Color(0xFFFF2B2B), [Color(0xFF8A0F1B), Color(0xFFFF2B2B), Color(0xFFFFB13B)],
      [Color(0xFF5A0A12), Color(0xFFB71C1C), Color(0xFFE65100)], '🔥', '🐉', 'Ejderha', WipNameFx.fire, _fire, 3300),
  11: WipStyle(11, 'Hayalet', Color(0xFFC9B8FF), [Color(0xFF1A1033), Color(0xFF5E35B1), Color(0xFFC9B8FF)],
      [Color(0xFF140B2E), Color(0xFF3A2470), Color(0xFF140B2E)], '👻', '🛸', 'Hayalet UFO', WipNameFx.ghost, _ghost, 3600),
};

/// WIP sohbet balonu süslemesi. Seviye yoksa [fallback] düz renk.
BoxDecoration wipBubbleDecoration(int? level, {required Color fallback, double radius = 12}) {
  final s = WipStyle.of(level);
  if (s == null) return BoxDecoration(color: fallback, borderRadius: BorderRadius.circular(radius));
  final high = s.level >= 6;
  return BoxDecoration(
    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [for (final c in s.bubble) c.withValues(alpha: 0.82)]),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: (high ? s.gradient.last : s.color).withValues(alpha: high ? 0.85 : 0.6), width: high ? 1.3 : 0.9),
    boxShadow: high ? [BoxShadow(color: s.color.withValues(alpha: 0.45), blurRadius: 8)] : null,
  );
}

/// Sohbet balonu: WIP kademesine göre renk geçişi, kenar ışığı ve köşe süsü.
class WipBubble extends StatelessWidget {
  final int? level;
  final Color fallback;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;
  final Widget child;
  const WipBubble({super.key, required this.level, required this.fallback, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7), this.constraints});

  @override
  Widget build(BuildContext context) {
    final s = WipStyle.of(level);
    final box = Container(constraints: constraints, padding: padding, decoration: wipBubbleDecoration(level, fallback: fallback), child: child);
    if (s == null || s.emblem.isEmpty) return box;
    return Stack(clipBehavior: Clip.none, children: [
      box,
      Positioned(right: -5, top: -8, child: IgnorePointer(child: Text(s.emblem, style: const TextStyle(fontSize: 13)))),
    ]);
  }
}

/// Kod ile çizilen WIP avatar çerçevesi (takılı mağaza çerçevesi yokken). Avatarın merkezine göre çizer;
/// kendisine verilen alan avatardan büyük olmalı (Stack içinde Positioned ile kullanılır, düzeni değiştirmez).
class WipFrame extends StatefulWidget {
  final int level;
  final double avatarRadius;
  const WipFrame({super.key, required this.level, required this.avatarRadius});

  /// Stack içinde avatarın etrafına yerleştirir. Seviye yoksa boş.
  static Widget around(int? level, double avatarRadius) {
    if (WipStyle.of(level) == null) return const SizedBox.shrink();
    final e = avatarRadius * 0.35;
    return Positioned(
      left: -e,
      top: -e,
      right: -e,
      bottom: -e,
      child: IgnorePointer(child: WipFrame(level: level!, avatarRadius: avatarRadius)),
    );
  }

  @override
  State<WipFrame> createState() => _WipFrameState();
}

class _WipFrameState extends State<WipFrame> with TickerProviderStateMixin {
  AnimationController? _c;

  bool get _animated => WipStyle.of(widget.level)?.animatedFrame == true;

  @override
  void initState() {
    super.initState();
    if (_animated) _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  @override
  void didUpdateWidget(WipFrame old) {
    super.didUpdateWidget(old);
    if (_animated && _c == null) {
      _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    } else if (!_animated && _c != null) {
      _c!.dispose();
      _c = null;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = WipStyle.of(widget.level);
    if (s == null) return const SizedBox.shrink();
    return RepaintBoundary(child: CustomPaint(painter: _WipFramePainter(s, widget.avatarRadius, _c), child: const SizedBox.expand()));
  }
}

class _WipFramePainter extends CustomPainter {
  final WipStyle s;
  final double avatarRadius;
  final Animation<double>? anim;
  _WipFramePainter(this.s, this.avatarRadius, this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim?.value ?? 0.0;
    final c = size.center(Offset.zero);
    final w = (avatarRadius * (s.level >= 6 ? 0.13 : 0.09)).clamp(1.5, 7.0).toDouble();
    final ringR = avatarRadius + w / 2 + 0.5;
    final rect = Rect.fromCircle(center: c, radius: ringR);
    final colors = s.gradient.length >= 2 ? s.gradient : [s.color, s.color];
    final wave = (math.sin(t * 2 * math.pi) + 1) / 2;

    // Dış ışıma (3 ve üzeri; hayalette nabız gibi).
    if (s.level >= 3) {
      final a = s.isSwip ? 0.2 + 0.35 * wave : (s.level >= 6 ? 0.45 : 0.3);
      canvas.drawCircle(
        c,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 1.8
          ..color = s.color.withValues(alpha: a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    ring.shader = s.animatedFrame
        ? SweepGradient(colors: [...colors, colors.first], transform: GradientRotation(t * 2 * math.pi)).createShader(rect)
        : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors).createShader(rect);
    canvas.drawCircle(c, ringR, ring);
    canvas.drawCircle(
      c,
      ringR - w / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.45),
    );

    // Mücevherler: 4+ tepede, 7+ yanlarda da.
    if (s.level >= 4) _gem(canvas, Offset(c.dx, c.dy - ringR), w * 1.35, colors);
    if (s.level >= 7) {
      _gem(canvas, Offset(c.dx - ringR, c.dy), w, colors);
      _gem(canvas, Offset(c.dx + ringR, c.dy), w, colors);
    }
    // Parıltılar: 8+ çerçevenin üzerinde döner.
    if (s.sparkles) {
      final n = s.level >= 10 ? 6 : 4;
      for (var i = 0; i < n; i++) {
        final ang = (i.isEven ? 1 : -1) * t * 2 * math.pi + i * 2 * math.pi / n;
        final p = c + Offset(math.cos(ang), math.sin(ang)) * ringR;
        final tw = (math.sin((t * 3 + i / n) * 2 * math.pi) + 1) / 2;
        _sparkle(canvas, p, w * (0.7 + 0.9 * tw), Colors.white.withValues(alpha: 0.45 + 0.55 * tw));
      }
    }
  }

  void _gem(Canvas canvas, Offset p, double r, List<Color> colors) {
    final path = Path()
      ..moveTo(p.dx, p.dy - r)
      ..lineTo(p.dx + r * 0.8, p.dy)
      ..lineTo(p.dx, p.dy + r)
      ..lineTo(p.dx - r * 0.8, p.dy)
      ..close();
    canvas.drawPath(path, Paint()..shader = LinearGradient(colors: [Colors.white, colors.last]).createShader(Rect.fromCircle(center: p, radius: r)));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.black26,
    );
  }

  void _sparkle(Canvas canvas, Offset p, double r, Color color) {
    final path = Path()
      ..moveTo(p.dx, p.dy - r)
      ..quadraticBezierTo(p.dx, p.dy, p.dx + r, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + r)
      ..quadraticBezierTo(p.dx, p.dy, p.dx - r, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WipFramePainter old) => old.s.level != s.level || old.avatarRadius != avatarRadius || old.anim != anim;
}

/// Profilde WIP ışık halesi (profil efekti ayrıcalığı): avatarın arkasında yumuşak parıltı.
class WipAura extends StatefulWidget {
  final int level;
  const WipAura({super.key, required this.level});

  @override
  State<WipAura> createState() => _WipAuraState();
}

class _WipAuraState extends State<WipAura> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
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
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              s.color.withValues(alpha: 0.30 + 0.25 * t),
              s.gradient.first.withValues(alpha: 0.12 + 0.1 * t),
              s.color.withValues(alpha: 0),
            ], stops: const [0.45, 0.72, 1.0]),
          ),
        );
      },
    );
  }
}
