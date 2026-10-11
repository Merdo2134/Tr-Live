import 'package:flutter/material.dart';
import '../services/api.dart';
import 'app_theme.dart';

/// Ana sayfa oda kartı (Yoho ölçüleri): kare kapak görseli, sol altta tür etiketi, sağ altta dinleyici sayısı ve
/// üstünde üst üste binen üye avatarları; oda adı görselin altında. Tüm ölçüler kart genişliğine oranlıdır.
class RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onTap;
  const RoomCard({super.key, required this.room, required this.onTap});

  /// Kartın görselinin altındaki ad alanı (genişliğe oranla); ızgara bu payı ayırır.
  static double titleAreaFor(double screenW) => (screenW * 0.104).clamp(38.0, 50.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final owner = room['owner'] is Map ? Map<String, dynamic>.from(room['owner'] as Map) : null;
    final themeImg = room['themeImageUrl'] as String?;
    final cover = room['coverUrl'] as String?;
    final image = Api.absoluteUrl(cover != null && cover.isNotEmpty ? cover : (themeImg != null && themeImg.isNotEmpty ? themeImg : owner?['avatarUrl'] as String?));
    final bags = (room['bagCount'] as num?)?.toInt() ?? 0;
    final tags = room['tags'] is List ? (room['tags'] as List).map((e) => e.toString()).where((t) => t.trim().isNotEmpty).toList() : <String>[];
    final isVideo = room['roomType'] == 'video';
    final count = room['memberCount'] ?? 0;
    final name = (room['name'] ?? '').toString();
    final avatars = [
      for (final a in (room['avatars'] is List ? room['avatars'] as List : const []))
        if (Api.absoluteUrl(a?.toString()) != null) Api.absoluteUrl(a.toString())!,
    ];
    final tag = tags.isNotEmpty ? tags.first : (isVideo ? 'Görüntülü' : 'Sohbet');
    final tagColor = isVideo ? const Color(0xFFFF9F0A) : const Color(0xFF16C25B);
    return Semantics(
      button: true,
      label: '$name, $count kişi',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        // Kart içi ölçüler kart genişliğine oranlı; telefonun yazı boyutu ayarı etiketleri taşırmasın.
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: LayoutBuilder(builder: (context, box) {
          final cw = box.maxWidth; // kart (görsel) genişliği; görsel karedir
          final inset = cw * 0.042;
          final tagH = (cw * 0.082).clamp(14.0, 20.0).toDouble();
          final av = (cw * 0.104).clamp(16.0, 26.0).toDouble();
          final shown = avatars.take(8).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: cw,
              height: cw,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(fit: StackFit.expand, children: [
                  const ColoredBox(color: Pal.surfaceHi),
                  if (image != null)
                    Image.network(
                      image,
                      fit: BoxFit.cover,
                      cacheWidth: (cw * MediaQuery.devicePixelRatioOf(context)).round().clamp(64, 720),
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      loadingBuilder: (c, w, p) => p == null ? w : const SizedBox.shrink(),
                    )
                  else
                    Center(child: Icon(isVideo ? Icons.videocam : Icons.graphic_eq, size: cw * 0.28, color: Pal.textDim)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0x8C000000)], stops: [0, 0.55, 1]),
                    ),
                  ),
                  // Sağ üst: kilit ve şanslı çanta.
                  Positioned(
                    right: inset,
                    top: inset,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (bags > 0) Text('🧧', style: TextStyle(fontSize: tagH)),
                      if (room['locked'] == true) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.lock, size: tagH, color: Pal.amber)),
                    ]),
                  ),
                  // Üye avatarları: sağa yaslı, %20 üst üste.
                  if (shown.isNotEmpty)
                    Positioned(
                      right: cw * 0.024,
                      bottom: inset + tagH + cw * 0.03,
                      width: av + av * 0.8 * (shown.length - 1),
                      height: av,
                      child: Stack(children: [
                        for (var i = 0; i < shown.length; i++)
                          Positioned(
                            left: av * 0.8 * i,
                            top: 0,
                            width: av,
                            height: av,
                            child: Container(
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.2), color: Pal.surfaceHi),
                              child: ClipOval(
                                child: Image.network(
                                  shown[i],
                                  fit: BoxFit.cover,
                                  cacheWidth: (av * MediaQuery.devicePixelRatioOf(context)).round().clamp(24, 96),
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  // Sol alt: tür etiketi.
                  Positioned(
                    left: inset,
                    bottom: inset,
                    height: tagH,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: cw * 0.55),
                      padding: EdgeInsets.symmetric(horizontal: tagH * 0.35),
                      decoration: BoxDecoration(color: tagColor, borderRadius: BorderRadius.circular(tagH * 0.28)),
                      // widthFactor 1: etiket yazıyı sarar (Container'ın alignment'ı en geniş hâline uzatırdı).
                      child: Center(widthFactor: 1, child: Text(tag, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: tagH * 0.72, height: 1.0, fontWeight: FontWeight.w700))),
                    ),
                  ),
                  // Sağ alt: dinleyici sayısı.
                  Positioned(
                    right: inset,
                    bottom: inset,
                    height: tagH,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.bar_chart_rounded, size: tagH * 0.95, color: const Color(0xFF2EE6A6)),
                      const SizedBox(width: 2),
                      Text('$count', style: TextStyle(color: Colors.white, fontSize: tagH * 0.82, height: 1.0, fontWeight: FontWeight.w800, shadows: const [Shadow(color: Colors.black54, blurRadius: 3)])),
                    ]),
                  ),
                ]),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(cw * 0.036, 0, cw * 0.02, 0),
                child: Align(
                  alignment: const Alignment(-1, -0.25),
                  child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Pal.text, fontWeight: FontWeight.w800, fontSize: (cw * 0.082).clamp(13.0, 17.0).toDouble())),
                ),
              ),
            ),
          ]);
        }),
        ),
      ),
    );
  }
}
