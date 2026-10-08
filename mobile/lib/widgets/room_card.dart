import 'package:flutter/material.dart';
import '../services/api.dart';
import 'app_theme.dart';

/// Ana sayfadaki oda kartı: dikey görsel, köşe rozetleri, dinleyici sayısı ve altında oda adı.
class RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onTap;
  const RoomCard({super.key, required this.room, required this.onTap});

  Widget _pill(Widget child, {Color? color, Gradient? gradient}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color, gradient: gradient, borderRadius: BorderRadius.circular(10)),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final owner = room['owner'] is Map ? Map<String, dynamic>.from(room['owner'] as Map) : null;
    final themeImg = room['themeImageUrl'] as String?;
    final cover = room['coverUrl'] as String?;
    final image = Api.absoluteUrl(cover != null && cover.isNotEmpty ? cover : (themeImg != null && themeImg.isNotEmpty ? themeImg : owner?['avatarUrl'] as String?));
    final bags = (room['bagCount'] as num?)?.toInt() ?? 0;
    final tags = room['tags'] is List ? (room['tags'] as List).map((e) => e.toString()).toList() : <String>[];
    final isVideo = room['roomType'] == 'video';
    final count = room['memberCount'] ?? 0;
    final name = (room['name'] ?? '').toString();
    return Semantics(
      button: true,
      label: '$name, $count kişi',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(fit: StackFit.expand, children: [
                const ColoredBox(color: Pal.surfaceHi),
                if (image != null) Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink(), loadingBuilder: (c, w, p) => p == null ? w : const SizedBox.shrink()),
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x40000000), Color(0x00000000), Color(0x99000000)], stops: [0, 0.45, 1])),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  right: 8,
                  child: Row(children: [
                    Flexible(
                      child: _pill(
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(isVideo ? Icons.videocam : Icons.mic, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Flexible(child: Text(isVideo ? 'Görüntülü' : 'Sesli', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
                        ]),
                        gradient: LinearGradient(colors: isVideo ? const [Pal.purple, Pal.pink] : const [Color(0xFFFF7A18), Color(0xFFFF4A1C)]),
                      ),
                    ),
                    const Spacer(),
                    if (bags > 0) const Padding(padding: EdgeInsets.only(right: 4), child: Text('🧧', style: TextStyle(fontSize: 18))),
                    if (room['locked'] == true) const Icon(Icons.lock, size: 18, color: Pal.amber),
                  ]),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Row(children: [
                    if (tags.isNotEmpty)
                      Flexible(child: _pill(Text(tags.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF00212A), fontSize: 12, fontWeight: FontWeight.w700)), color: Pal.cyan)),
                    const Spacer(),
                    _pill(
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.signal_cellular_alt, size: 13, color: Colors.white),
                        const SizedBox(width: 3),
                        Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                      color: const Color(0x99000000),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.text, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ]),
      ),
    );
  }
}
