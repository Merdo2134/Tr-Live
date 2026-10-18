import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import 'common.dart';

/// Uçan yazı: sohbet bölümünün en üstünde sağdan sola kayan yazı (ücretli "uçan yazı" ve "Hoş geldin" selamı).
/// Tek şeritte arka arkaya sırayla geçer; biri bitince sıradaki başlar.
class FlyTextQueue extends ChangeNotifier {
  final List<Map<String, dynamic>> _wait = [];
  final List<Map<String, dynamic>?> lanes = [null];

  /// Şu an kayan yazı var mı (sohbetin üstünde yer açmak için).
  bool get active => lanes.any((l) => l != null);
  int _seq = 0;
  bool _dead = false;

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }

  void add(Map<String, dynamic> m) {
    if (_dead) return;
    if (_wait.length >= 12) _wait.removeAt(0);
    _wait.add(m);
    _pump();
  }

  void _pump() {
    if (_dead) return;
    for (var i = 0; i < lanes.length && _wait.isNotEmpty; i++) {
      if (lanes[i] != null) continue;
      lanes[i] = {..._wait.removeAt(0), '_seq': ++_seq};
      notifyListeners();
    }
  }

  void done(int lane) {
    if (_dead) return;
    lanes[lane] = null;
    notifyListeners();
    Timer(const Duration(milliseconds: 150), _pump);
  }
}

class FlyTextLayer extends StatelessWidget {
  final FlyTextQueue queue;
  const FlyTextLayer({super.key, required this.queue});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: queue,
        builder: (context, _) => SizedBox(
          height: 40,
          child: Stack(clipBehavior: Clip.none, children: [
            for (var i = 0; i < queue.lanes.length; i++)
              if (queue.lanes[i] != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: i * 44.0,
                  child: _FlyItem(key: ValueKey(queue.lanes[i]!['_seq']), m: queue.lanes[i]!, onDone: () => queue.done(i)),
                ),
          ]),
        ),
      ),
    );
  }
}

class _FlyItem extends StatefulWidget {
  final Map<String, dynamic> m;
  final VoidCallback onDone;
  const _FlyItem({super.key, required this.m, required this.onDone});

  @override
  State<_FlyItem> createState() => _FlyItemState();
}

class _FlyItemState extends State<_FlyItem> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 7500));
  final _key = GlobalKey();
  double _itemW = 260;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final w = _key.currentContext?.size?.width;
      if (w != null && mounted) setState(() => _itemW = w);
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.sizeOf(context).width;
    final m = widget.m;
    final u = mapOf(m['user']);
    final welcome = mapOf(m['welcomeTo']);
    final colors = welcome != null
        ? const [Color(0xF000BFA5), Color(0xE064DD17), Color(0x0064DD17)]
        : const [Color(0xF0FF4081), Color(0xE07C4DFF), Color(0x007C4DFF)];
    final pill = Container(
      key: _key,
      constraints: BoxConstraints(maxWidth: sw * 0.9),
      height: 38,
      padding: const EdgeInsets.fromLTRB(3, 3, 18, 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        gradient: LinearGradient(colors: colors, stops: const [0, 0.75, 1]),
        border: const Border(top: BorderSide(color: Color(0x80FFFFFF), width: 0.8)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(1.4),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
          child: UserAvatar(user: u, radius: 14.5),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: sw * 0.28),
          child: Text(
            '${u?['displayName'] ?? ''}:',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFFFF59D), fontWeight: FontWeight.w900, fontSize: 13.5, shadows: [Shadow(color: Colors.black54, blurRadius: 3)]),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            (m['text'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, shadows: [Shadow(color: Colors.black54, blurRadius: 3)]),
          ),
        ),
        if (welcome != null) const Padding(padding: EdgeInsets.only(left: 4), child: Text('👏', style: TextStyle(fontSize: 20))),
      ]),
    );
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: pill,
        builder: (_, child) {
          // Sağ kenarın dışından girer, sol kenarın dışına tamamen çıkar.
          final dx = sw - (sw + _itemW) * _c.value;
          return Transform.translate(offset: Offset(dx, 0), child: Align(alignment: Alignment.centerLeft, child: child));
        },
      ),
    );
  }
}
