import 'package:flutter/material.dart';

/// Sürüklenebilir yuvarlak balon (sohbet baloncuğu gibi). Bırakılınca en yakın kenara yapışır.
/// [pos] dışarıda (static) tutulursa konum balon kapanıp açılınca korunur. Bir [Stack] içinde kullanılır.
class DragBubble extends StatefulWidget {
  final ValueNotifier<Offset?> pos;
  final double size;
  final Offset initial; // pos boşken: x = -1 → sağ kenar, y = alttan uzaklık (negatif) ya da üstten
  final EdgeInsets safe;
  final VoidCallback? onTap;
  final Widget child;
  const DragBubble({super.key, required this.pos, required this.child, this.size = 60, this.initial = const Offset(-1, -200), this.safe = const EdgeInsets.fromLTRB(4, 80, 4, 90), this.onTap});

  @override
  State<DragBubble> createState() => _DragBubbleState();
}

class _DragBubbleState extends State<DragBubble> {
  bool _dragging = false;

  ValueNotifier<Offset?> get pos => widget.pos;
  double get size => widget.size;
  Offset get initial => widget.initial;
  EdgeInsets get safe => widget.safe;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(builder: (context, c) {
        final maxX = c.maxWidth - size - safe.right;
        final maxY = c.maxHeight - size - safe.bottom;
        Offset clamp(Offset o) => Offset(o.dx.clamp(safe.left, maxX < safe.left ? safe.left : maxX).toDouble(), o.dy.clamp(safe.top, maxY < safe.top ? safe.top : maxY).toDouble());
        Offset start() {
          final x = initial.dx < 0 ? maxX : initial.dx;
          final y = initial.dy < 0 ? c.maxHeight + initial.dy : initial.dy;
          return clamp(Offset(x, y));
        }

        return ValueListenableBuilder<Offset?>(
          valueListenable: pos,
          builder: (context, p, _) {
            final o = clamp(p ?? start());
            return Stack(children: [
              AnimatedPositioned(
                duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                left: o.dx,
                top: o.dy,
                width: size,
                height: size,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  onPanStart: (_) => setState(() => _dragging = true),
                  onPanUpdate: (d) => pos.value = clamp((pos.value ?? o) + d.delta),
                  onPanEnd: (_) {
                    final cur = pos.value ?? o;
                    final snapX = (cur.dx + size / 2) < c.maxWidth / 2 ? safe.left : maxX;
                    setState(() => _dragging = false);
                    pos.value = clamp(Offset(snapX, cur.dy));
                  },
                  onPanCancel: () => setState(() => _dragging = false),
                  child: widget.child,
                ),
              ),
            ]);
          },
        );
      }),
    );
  }
}
