import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'wip_style.dart';

/// Gelen girişleri sıraya alır; aynı anda yalnızca bir şerit gösterilir.
class EntranceQueue extends ChangeNotifier {
  final List<Map<String, dynamic>> _q = [];
  Map<String, dynamic>? current;
  bool _busy = false;
  bool _dead = false;

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }

  void add(Map<String, dynamic> user) {
    if (_dead || WipStyle.of(wipLevelOf(user['wipLevel'])) == null || _q.length >= 6) return;
    _q.add(user);
    _next();
  }

  void _next() {
    if (_dead || _busy || _q.isEmpty) return; // oda kapandıktan sonra gecikmeli çağrı gelebilir
    _busy = true;
    current = _q.removeAt(0);
    notifyListeners();
    final s = WipStyle.of(wipLevelOf(current!['wipLevel']))!;
    Timer(Duration(milliseconds: 700 + s.entranceMs + 700), () {
      if (_dead) return;
      current = null;
      _busy = false;
      notifyListeners();
      Future.delayed(const Duration(milliseconds: 150), _next);
    });
  }
}

/// Odanın ortasından geçen WIP giriş şeridi: kademenin aracı (scooter → ejderha, SWIP'te UFO) şeridi çeker.
class EntranceStrip extends StatelessWidget {
  final EntranceQueue queue;
  const EntranceStrip({super.key, required this.queue});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: queue,
        builder: (context, _) {
          final u = queue.current;
          if (u == null) return const SizedBox.shrink();
          return EntranceBanner(key: ValueKey(u.hashCode), user: u);
        },
      ),
    );
  }
}

/// Tek giriş şeridi. [loop] verilirse (WIP ekranındaki önizleme) sürekli tekrar eder.
class EntranceBanner extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool loop;
  const EntranceBanner({super.key, required this.user, this.loop = false});
  @override
  State<EntranceBanner> createState() => _EntranceBannerState();
}

class _EntranceBannerState extends State<EntranceBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late WipStyle _s;

  int get _total => 700 + _s.entranceMs + 700;

  @override
  void initState() {
    super.initState();
    _s = WipStyle.of(wipLevelOf(widget.user['wipLevel'])) ?? WipStyle.of(1)!;
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: _total));
    if (widget.loop) {
      _c.repeat();
    } else {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(EntranceBanner old) {
    super.didUpdateWidget(old);
    final s = WipStyle.of(wipLevelOf(widget.user['wipLevel'])) ?? WipStyle.of(1)!;
    if (s.level != _s.level) {
      _s = s;
      _c.duration = Duration(milliseconds: _total);
      if (widget.loop) _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
      final s = _s;
      final total = _total;
      final inEnd = 700 / total, outStart = (700 + s.entranceMs) / total;
      final name = (widget.user['displayName'] ?? '').toString();
      final lvl = s.level;
      final light = lvl == 2 || lvl == 3; // gümüş/altın şeritte koyu yazı daha okunur
      final textColor = light ? const Color(0xFF2B1D00) : Colors.white;
      return AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          double dx;
          if (t < inEnd) {
            dx = (1 - Curves.easeOutCubic.transform(t / inEnd)) * w; // sağdan gelir
          } else if (t > outStart) {
            dx = -Curves.easeInCubic.transform((t - outStart) / (1 - outStart)) * w; // soldan çıkar
          } else {
            dx = 0;
          }
          final ms = t * total;
          final bob = math.sin(ms / 90) * (lvl >= 7 ? 2.2 : 1.4); // araç hafifçe sallanır / süzülür
          return Transform.translate(
            offset: Offset(dx, 0),
            child: Container(
              width: w,
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [s.gradient.first.withValues(alpha: 0), ...s.gradient, s.gradient.last.withValues(alpha: 0)]),
                boxShadow: [BoxShadow(color: s.color.withValues(alpha: lvl >= 6 ? 0.7 : 0.4), blurRadius: 6.0 + lvl * 2.5)],
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                // Araç önde (sola doğru gidiyor); arkasında hız çizgileri.
                Transform.translate(
                  offset: Offset(0, bob),
                  child: Text(
                    s.vehicle,
                    style: TextStyle(fontSize: 22 + lvl * 1.3, shadows: [Shadow(color: s.color, blurRadius: lvl >= 6 ? 12 : 4)]),
                  ),
                ),
                _SpeedLines(color: textColor.withValues(alpha: 0.7), phase: ms / 120),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$name ${s.vehicleName} ile geldi',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5 + math.min(lvl, 10) * 0.25,
                      shadows: light ? null : const [Shadow(blurRadius: 4, color: Colors.black54)],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
                  child: Text(s.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                ),
              ]),
            ),
          );
        },
      );
    });
  }
}

/// Aracın arkasında akan üç kısa çizgi.
class _SpeedLines extends StatelessWidget {
  final Color color;
  final double phase;
  const _SpeedLines({required this.color, required this.phase});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 18,
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: EdgeInsets.only(left: ((phase + i * 0.7) % 3) * 2),
            width: 8 - i * 1.5,
            height: 1.6,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
          ),
      ]),
    );
  }
}
