import 'package:flutter/material.dart';

/// Seviye görünümleri (yeni tasarım): **taç = gönderme (atış) seviyesi**, **kalp = alma (alış) seviyesi**.
/// Küçük etiket: renkli hap + sağda simge, solda seviye sayısı. Büyük rozet: seviye sayfasında.

// Gönderme (Coin) seviyesi kademeleri: 7 etiket / 7 rozet (yeşil yıldız → kırmızı yakut taç).
const _sendSteps = [1, 11, 21, 41, 61, 81, 101];

int sendTier(int level) {
  var t = 1;
  for (var i = 0; i < _sendSteps.length; i++) {
    if (level >= _sendSteps[i]) t = i + 1;
  }
  return t;
}

/// Alma (Elmas) seviyesi kademeleri: 12 etiket, her 10 seviyede bir (1–10, 11–20 … 111+).
int recvTier(int level) => ((level - 1) ~/ 10 + 1).clamp(1, 12);

/// Alma rozetleri: 10 kademe (16 seviyede bir).
int recvBadgeTier(int level) => ((level - 1) ~/ 16 + 1).clamp(1, 10);

int _lv(dynamic v) => (v is num ? v.toInt() : int.tryParse('$v') ?? 1).clamp(1, 999);

/// Seviye etiketi. [send] true: taçlı gönderme seviyesi, false: kalpli alma seviyesi. [height]: dp.
class LevelPill extends StatelessWidget {
  final dynamic level;
  final bool send;
  final double height;
  const LevelPill({super.key, required this.level, required this.send, this.height = 16});

  @override
  Widget build(BuildContext context) {
    final lv = _lv(level);
    final asset = send ? 'assets/images/lv_send_${sendTier(lv)}.png' : 'assets/images/lv_recv_${recvTier(lv)}.png';
    final w = height * 96 / 42;
    return SizedBox(
      width: w,
      height: height,
      child: Stack(fit: StackFit.expand, children: [
        Image.asset(asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        Positioned(
          left: height * 0.32,
          top: 0,
          bottom: 0,
          width: w * 0.5,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$lv',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: height * 0.62,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  shadows: const [Shadow(color: Color(0x99000000), blurRadius: 2, offset: Offset(0, 0.5))],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Büyük seviye rozeti (konfetili daire). [size]: genişlik dp.
class LevelBadgeImage extends StatelessWidget {
  final dynamic level;
  final bool send;
  final double size;
  const LevelBadgeImage({super.key, required this.level, required this.send, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final lv = _lv(level);
    final asset = send ? 'assets/images/badge_send_${sendTier(lv)}.webp' : 'assets/images/badge_recv_${recvBadgeTier(lv)}.webp';
    return Image.asset(asset, width: size, height: size * 495 / 555, fit: BoxFit.contain, errorBuilder: (_, __, ___) => SizedBox(width: size, height: size * 495 / 555));
  }
}

/// CP seviye etiketi (LV3–LV5 tasarımı; 1–2 için aynı pembe tonda kodla çizilir).
class CpLevelPill extends StatelessWidget {
  final int level;
  final double height;
  const CpLevelPill({super.key, required this.level, this.height = 18});

  @override
  Widget build(BuildContext context) {
    final w = height * 114 / 42;
    if (level >= 3) {
      return Image.asset('assets/images/cp_lv${level.clamp(3, 5)}.png', width: w, height: height, fit: BoxFit.fill);
    }
    return Container(
      width: w,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(height / 2), gradient: const LinearGradient(colors: [Color(0xFFFF7EB3), Color(0xFFFF4F9A)])),
      child: Text('LV$level', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: height * 0.62, height: 1.0)),
    );
  }
}
