import 'package:flutter/material.dart';

/// Figma tasarımından alınan süs görselleri (assets/figma/). Dosya yoksa boş alan çizilir (uygulama çökmez).
class Fig extends StatelessWidget {
  final String name;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool flipX;
  final AlignmentGeometry alignment;
  const Fig(this.name, {super.key, this.width, this.height, this.fit = BoxFit.contain, this.flipX = false, this.alignment = Alignment.center});

  static String path(String name) => 'assets/figma/$name.webp';

  static ImageProvider provider(String name) => AssetImage(path(name));

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      path(name),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => SizedBox(width: width, height: height),
    );
    if (!flipX) return img;
    return Transform(alignment: Alignment.center, transform: Matrix4.diagonal3Values(-1, 1, 1), child: img);
  }
}

/// Figma'daki pembe / mor tonlar (ilişki ve koruyucu sayfaları).
class FigPal {
  FigPal._();
  static const pink = Color(0xFFFF4FA8);
  static const pinkDeep = Color(0xFFE8318C);
  static const pinkSoft = Color(0xFFFFE3F2);
  static const pinkBg = Color(0xFFFDE7F3);
  static const pinkText = Color(0xFFE6007E);
  static const purpleText = Color(0xFF8B3FC9);
  static const purpleCard1 = Color(0xFFF1DDFF);
  static const purpleCard2 = Color(0xFFC9A8FF);
  static const purpleBorder = Color(0xFFE5C2FF);
  static const blueText = Color(0xFF2E5AAC);
  static const blueCard1 = Color(0xFFE2EEFF);
  static const blueCard2 = Color(0xFFADCBFF);
  static const blueBorder = Color(0xFFC4DAFF);
  static const ink = Color(0xFF1C1C1E);
  static const grey = Color(0xFF8E8E93);

  static const pinkButton = LinearGradient(colors: [Color(0xFFFF7AC8), Color(0xFFFF4FA8)], begin: Alignment.topCenter, end: Alignment.bottomCenter);
}

/// Figma'daki büyük yuvarlak pembe düğme.
class FigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final Gradient? gradient;
  final Color? color;
  final Color textColor;
  final double fontSize;
  const FigButton(this.label, {super.key, this.onTap, this.height = 52, this.gradient, this.color, this.textColor = Colors.white, this.fontSize = 18});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(height / 2),
          onTap: onTap,
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              gradient: color == null ? (gradient ?? FigPal.pinkButton) : null,
              color: color,
              borderRadius: BorderRadius.circular(height / 2),
              boxShadow: const [BoxShadow(color: Color(0x33FF4FA8), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Center(child: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: fontSize))),
          ),
        ),
      ),
    );
  }
}
