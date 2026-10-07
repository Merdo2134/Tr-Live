import 'package:flutter/material.dart';

/// Altın taç (TRLive logosu). Vektör olarak çizilir; her boyutta keskin kalır.
class CrownIcon extends StatelessWidget {
  final double size;
  const CrownIcon({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size * 0.78, child: CustomPaint(painter: _CrownPainter()));
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final body = Path()
      ..moveTo(w * 0.04, h * 0.30)
      ..lineTo(w * 0.28, h * 0.58)
      ..lineTo(w * 0.50, h * 0.08)
      ..lineTo(w * 0.72, h * 0.58)
      ..lineTo(w * 0.96, h * 0.30)
      ..lineTo(w * 0.86, h * 0.84)
      ..lineTo(w * 0.14, h * 0.84)
      ..close();
    final gold = Paint()
      ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE27A), Color(0xFFE0A21A), Color(0xFFB87408)]).createShader(Offset.zero & s);
    canvas.drawPath(body, gold);
    canvas.drawPath(body, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.025..color = const Color(0xFF8A5A00));
    // alt bant
    final band = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.12, h * 0.84, w * 0.76, h * 0.14), Radius.circular(h * 0.05));
    canvas.drawRRect(band, gold);
    canvas.drawRRect(band, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.02..color = const Color(0xFF8A5A00));
    // ucu inciler
    final pearl = Paint()..color = const Color(0xFFFFF6D6);
    for (final p in [Offset(w * 0.04, h * 0.28), Offset(w * 0.50, h * 0.06), Offset(w * 0.96, h * 0.28)]) {
      canvas.drawCircle(p, w * 0.055, pearl);
      canvas.drawCircle(p, w * 0.055, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.015..color = const Color(0xFF8A5A00));
    }
    // taşlar
    final gem = [const Color(0xFFFF4F9A), const Color(0xFF1FD6F5), const Color(0xFFFF4F9A)];
    final xs = [0.30, 0.50, 0.70];
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(w * xs[i], h * 0.66), w * 0.05, Paint()..color = gem[i]);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
