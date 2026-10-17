import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/api.dart';
import 'anim_asset.dart';
import 'level_badge.dart';
import 'common.dart';

/// Giriş şeridinin ekranda kalma süresi: WIP kademesine göre, WIP yoksa kısa.
int entranceHoldMs(Map<String, dynamic> user) => WipStyle.of(wipLevelOf(user['wipEntrance'] ?? user['wipLevel']))?.entranceMs ?? 2200;

/// Gelen girişleri sıraya alır; aynı anda yalnızca bir şerit gösterilir. Herkes için (WIP olmayanlar sade şeritle).
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
    if (_dead) return;
    final wip = WipStyle.of(wipLevelOf(user['wipEntrance'] ?? user['wipLevel'])) != null;
    // Kalabalık odada sıra uzamasın: WIP olmayan girişler sıra doluysa atlanır, WIP'ler öne geçer.
    if (_q.length >= 6) {
      if (!wip) return;
      final i = _q.indexWhere((u) => WipStyle.of(wipLevelOf(u['wipEntrance'] ?? u['wipLevel'])) == null);
      if (i < 0) return;
      _q.removeAt(i);
    }
    _q.add(user);
    _next();
  }

  void _next() {
    if (_dead || _busy || _q.isEmpty) return; // oda kapandıktan sonra gecikmeli çağrı gelebilir
    _busy = true;
    current = _q.removeAt(0);
    notifyListeners();
    Timer(Duration(milliseconds: 600 + entranceHoldMs(current!) + 600), () {
      if (_dead) return;
      current = null;
      _busy = false;
      notifyListeners();
      Future.delayed(const Duration(milliseconds: 150), _next);
    });
  }
}

/// Odanın ortasından geçen giriş şeridi: çerçeveli fotoğraf, rozetler, ad ve "odaya girdi".
/// (Araç burada yok: araç, mağazadan alınan ayrı "giriş aracı" efektidir ve yalnızca onu takanlarda odada belirir.)
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
  int _hold = 2200;

  int get _total => 600 + _hold + 600;

  @override
  void initState() {
    super.initState();
    _hold = entranceHoldMs(widget.user);
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
    final h = entranceHoldMs(widget.user);
    if (h != _hold) {
      _hold = h;
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
    // Kendi katmanında: şerit kayarken odanın geri kalanı yeniden çizilmez.
    return RepaintBoundary(child: _banner());
  }

  Widget _banner() {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
      final u = widget.user;
      final s = WipStyle.of(wipLevelOf(u['wipEntrance'] ?? u['wipLevel']));
      final lvl = s?.level ?? 0;
      final total = _total;
      final inEnd = 600 / total, outStart = (600 + _hold) / total;
      final name = (u['displayName'] ?? '').toString();
      final k = (w / 400).clamp(0.82, 1.15).toDouble();
      final barH = 34 * k;
      final avR = 21 * k;
      // Şerit rengi: WIP kademesinin koyu tonu; WIP yoksa lacivert. Kenarlar altın (WIP) / gümüş.
      final dark = s?.bubble ?? const [Color(0xFF13285A), Color(0xFF0B1636)];
      final edge = s == null ? const [Color(0x00CFD8DC), Color(0xFFCFD8DC), Color(0x00CFD8DC)] : const [Color(0x00FFD54F), Color(0xFFFFE082), Color(0xFFFFB300), Color(0x00FFB300)];
      final frameUrl = Api.absoluteUrl(u['frameUrl'] as String?);
      final coin = (u['coinLevel'] as num?)?.toInt();
      final gift = (u['giftLevel'] as num?)?.toInt();
      final strip = SizedBox(
        width: w * 0.92,
        height: avR * 2 * 1.3,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
          // Bant
          Positioned(
            left: avR * 1.1,
            right: 0,
            child: Container(
              height: barH,
              padding: EdgeInsets.only(left: avR * 1.15, right: 10 * k),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [dark.first.withValues(alpha: 0.95), dark.last.withValues(alpha: 0.9), dark.last.withValues(alpha: 0)], stops: const [0, 0.75, 1]),
                boxShadow: s != null && lvl >= 6 ? [BoxShadow(color: s.color.withValues(alpha: 0.55), blurRadius: 12)] : null,
              ),
              child: Row(children: [
                if (s != null) WipChip(level: u['wipBadge'] ?? u['wipLevel'], compact: true),
                if (coin != null) Padding(padding: EdgeInsets.only(left: 4 * k), child: LevelPill(level: coin, send: true, height: 15 * k)),
                if (gift != null && gift > 1) Padding(padding: EdgeInsets.only(left: 3 * k), child: LevelPill(level: gift, send: false, height: 15 * k)),
                SizedBox(width: 6 * k),
                Flexible(
                  child: WipNameText(
                    name,
                    level: s?.level,
                    color: s == null ? const Color(0xFF7DD3FC) : const Color(0xFFFFE082),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14 * k + math.min(lvl, 10) * 0.15, shadows: const [Shadow(blurRadius: 4, color: Colors.black87)]),
                  ),
                ),
                SizedBox(width: 5 * k),
                Text('odaya girdi', style: TextStyle(color: Colors.white, fontSize: 12.5 * k, fontWeight: FontWeight.w700, shadows: const [Shadow(blurRadius: 3, color: Colors.black54)])),
              ]),
            ),
          ),
          // Üst ve alt parlak kenar çizgileri
          Positioned(left: avR * 1.1, right: 0, top: (avR * 2 * 1.3 - barH) / 2 - 1, child: Container(height: 1.6, decoration: BoxDecoration(gradient: LinearGradient(colors: edge)))),
          Positioned(left: avR * 1.1, right: 0, bottom: (avR * 2 * 1.3 - barH) / 2 - 1, child: Container(height: 1.6, decoration: BoxDecoration(gradient: LinearGradient(colors: edge)))),
          // Çerçeveli fotoğraf
          Positioned(
            left: avR * 0.3,
            child: SizedBox(
              width: avR * 2,
              height: avR * 2,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: s?.color ?? const Color(0xFFCFD8DC)),
                  child: UserAvatar(user: u, radius: avR - 1.5),
                ),
                if (frameUrl == null) WipFrame.around(wipLevelOf(u['wipFrame'] ?? u['wipLevel']), avR),
                if (frameUrl != null)
                  Positioned(
                    left: -(avR * kFrameScale - avR),
                    top: -(avR * kFrameScale - avR),
                    width: avR * 2 * kFrameScale,
                    height: avR * 2 * kFrameScale,
                    child: IgnorePointer(child: AnimAsset(key: ValueKey(frameUrl), url: frameUrl, repeat: true, cache: false)),
                  ),
              ]),
            ),
          ),
        ]),
      );
      return AnimatedBuilder(
        animation: _c,
        child: strip,
        builder: (context, child) {
          final t = _c.value;
          double dx;
          if (t < inEnd) {
            dx = (1 - Curves.easeOutCubic.transform(t / inEnd)) * w; // sağdan gelir
          } else if (t > outStart) {
            dx = -Curves.easeInCubic.transform((t - outStart) / (1 - outStart)) * w; // soldan çıkar
          } else {
            dx = 0;
          }
          return Transform.translate(offset: Offset(dx, 0), child: Align(alignment: Alignment.centerLeft, child: child));
        },
      );
    });
  }
}
