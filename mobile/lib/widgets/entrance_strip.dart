import 'dart:async';
import 'package:flutter/material.dart';

/// WIP seviyesine göre oda giriş şeridi görünümü.
class _Style {
  final List<Color> colors;
  final Color text;
  final Color glow;
  final String icon;
  final int holdMs;
  const _Style(this.colors, this.text, this.glow, this.icon, this.holdMs);
}

const _styles = <int, _Style>{
  1: _Style([Color(0xFF1F6F6B), Color(0xFF2FB5A8)], Colors.white, Color(0xFF2FB5A8), '✦', 1500),
  2: _Style([Color(0xFF1E4FA3), Color(0xFF3D8BFD)], Colors.white, Color(0xFF3D8BFD), '❖', 1700),
  3: _Style([Color(0xFF5B2A9E), Color(0xFFB36BFF)], Colors.white, Color(0xFFB36BFF), '✧', 1900),
  4: _Style([Color(0xFF9C6A00), Color(0xFFFFD54A)], Color(0xFF3A2500), Color(0xFFFFD54A), '★', 2200),
  5: _Style([Color(0xFF8A0F1B), Color(0xFFFF2B2B), Color(0xFFFFB13B)], Colors.white, Color(0xFFFF2B2B), '👑', 2800),
};

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
    final lvl = (user['wipLevel'] as num?)?.toInt();
    if (lvl == null || lvl < 1 || _q.length >= 6) return;
    if (_dead) return;
    _q.add(user);
    _next();
  }

  void _next() {
    if (_busy || _q.isEmpty) return;
    _busy = true;
    current = _q.removeAt(0);
    notifyListeners();
    final lvl = ((current!['wipLevel'] as num).toInt()).clamp(1, 5);
    Timer(Duration(milliseconds: 700 + _styles[lvl]!.holdMs + 700), () {
      if (_dead) return;
      current = null;
      _busy = false;
      notifyListeners();
      Future.delayed(const Duration(milliseconds: 150), _next);
    });
  }
}

/// Odanın ortasından soldan sağa geçen giriş şeridi.
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
          return _Strip(key: ValueKey(u.hashCode), user: u);
        },
      ),
    );
  }
}

class _Strip extends StatefulWidget {
  final Map<String, dynamic> user;
  const _Strip({super.key, required this.user});
  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final _Style _s;

  @override
  void initState() {
    super.initState();
    final lvl = ((widget.user['wipLevel'] as num).toInt()).clamp(1, 5);
    _s = _styles[lvl]!;
    final total = 700 + _s.holdMs + 700;
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: total))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final total = 700 + _s.holdMs + 700;
    final inEnd = 700 / total, outStart = (700 + _s.holdMs) / total;
    final name = (widget.user['displayName'] ?? '').toString();
    final lvl = (widget.user['wipLevel'] as num).toInt();
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
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Container(
            width: w,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_s.colors.first.withValues(alpha: 0), ..._s.colors, _s.colors.last.withValues(alpha: 0)]),
              boxShadow: [BoxShadow(color: _s.glow.withValues(alpha: lvl >= 4 ? 0.7 : 0.4), blurRadius: lvl * 6.0)],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_s.icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$name odaya girdi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _s.text, fontWeight: FontWeight.w800, fontSize: 14 + lvl * 0.6, shadows: const [Shadow(blurRadius: 4, color: Colors.black54)]),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
                child: Text('WIP $lvl', style: TextStyle(color: _s.text, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
            ]),
          ),
        );
      },
    );
  }
}
