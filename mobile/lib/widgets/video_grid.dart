import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Çoklu yayın (görüntülü ızgara) yerleşimi. Hücreler genişliği 1 olan bir alanda tanımlıdır;
/// alanın yüksekliği [aspect] × genişliktir. İlk hücre her zaman yayıncınındır (koltuk 0).
class VideoGridSpec {
  final double aspect;
  final List<Rect> cells;
  const VideoGridSpec(this.aspect, this.cells);
}

/// Çoklu yayında seçilebilen kişi sayıları (Figma).
const List<int> kVideoGridModes = [4, 6, 9, 12];

VideoGridSpec videoGridFor(int n) {
  const c = 1 / 3;
  switch (n) {
    case 4: // yayıncı solda büyük, sağda 3 konuk alt alta
      return VideoGridSpec(1, [
        const Rect.fromLTWH(0, 0, 0.75, 1),
        for (var i = 0; i < 3; i++) Rect.fromLTWH(0.75, i * c, 0.25, c),
      ]);
    case 6: // yayıncı sol üstte 2×2, sağda 2, altta 3
      return const VideoGridSpec(1, [
        Rect.fromLTWH(0, 0, 2 * c, 2 * c),
        Rect.fromLTWH(2 * c, 0, c, c),
        Rect.fromLTWH(2 * c, c, c, c),
        Rect.fromLTWH(0, 2 * c, c, c),
        Rect.fromLTWH(c, 2 * c, c, c),
        Rect.fromLTWH(2 * c, 2 * c, c, c),
      ]);
    case 9:
      return VideoGridSpec(1, [for (var i = 0; i < 9; i++) Rect.fromLTWH((i % 3) * c, (i ~/ 3) * c, c, c)]);
    case 12:
      return VideoGridSpec(0.75, [for (var i = 0; i < 12; i++) Rect.fromLTWH((i % 4) * 0.25, (i ~/ 4) * 0.25, 0.25, 0.25)]);
  }
  // Eski odalarda kalan diğer sayılar: eşit kare hücreler.
  final count = math.max(n, 1);
  final cols = count <= 4 ? 2 : (count <= 9 ? 3 : (count <= 16 ? 4 : 5));
  final rows = (count / cols).ceil();
  final cell = 1 / cols;
  return VideoGridSpec(rows * cell, [for (var i = 0; i < count; i++) Rect.fromLTWH((i % cols) * cell, (i ~/ cols) * cell, cell, cell)]);
}

/// Boş konuk koltuğu simgesi (Figma: koltuk/kanepe çizgisi).
const IconData kEmptySeatIcon = Icons.weekend_outlined;

/// Boş hücre zemini (Figma: açık lila, yarı saydam) ve ızgara çizgisi.
const Color kGridEmptyFill = Color(0x66C8B5EC);
const Color kGridLine = Color(0x8CFFFFFF);
const Color kGridHostFill = Color(0xFF2A1450);

/// Mikrofon modu penceresinde görüntülü odalar için küçük önizleme.
class VideoGridThumb extends StatelessWidget {
  final int n;
  const VideoGridThumb(this.n, {super.key});

  @override
  Widget build(BuildContext context) {
    final spec = videoGridFor(n);
    return LayoutBuilder(builder: (context, box) {
      final w = math.min(box.maxWidth, box.maxHeight / spec.aspect);
      final h = w * spec.aspect;
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF5B1A86), Color(0xFF1B3F8F), Color(0xFF0A8EA6)]),
        ),
        child: Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              for (var i = 0; i < spec.cells.length; i++)
                Positioned(
                  left: spec.cells[i].left * w,
                  top: spec.cells[i].top * w,
                  width: spec.cells[i].width * w,
                  height: spec.cells[i].height * w,
                  child: Container(
                    decoration: BoxDecoration(color: i == 0 ? kGridHostFill : kGridEmptyFill, border: Border.all(color: kGridLine, width: 0.5)),
                    child: Icon(i == 0 ? Icons.videocam : kEmptySeatIcon, color: Colors.white70, size: math.min(spec.cells[i].width, spec.cells[i].height) * w * 0.38),
                  ),
                ),
            ]),
          ),
        ),
      );
    });
  }
}
