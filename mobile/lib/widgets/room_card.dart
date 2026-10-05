import 'package:flutter/material.dart';
import '../services/api.dart';
import 'app_theme.dart';

/// Ana sayfadaki oda kartı: arka plan görseli, etiket, oda adı, kişi sayısı ve CANLI rozeti.
class RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onTap;
  const RoomCard({super.key, required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final owner = room['owner'] is Map ? Map<String, dynamic>.from(room['owner'] as Map) : null;
    final image = Api.absoluteUrl((room['themeImageUrl'] as String?)?.isNotEmpty == true ? room['themeImageUrl'] as String : owner?['avatarUrl'] as String?);
    final tags = room['tags'] is List ? (room['tags'] as List).map((e) => e.toString()).toList() : <String>[];
    final isVideo = room['roomType'] == 'video';
    final label = (tags.isNotEmpty ? tags.first : (isVideo ? 'video' : 'sesli')).toUpperCase();
    final count = room['memberCount'] ?? 0;
    return Semantics(
      button: true,
      label: '${room['name']}, $count kişi',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Pal.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Pal.outline, width: 1.2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Stack(fit: StackFit.expand, children: [
              if (image != null)
                Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink(), loadingBuilder: (c, w, p) => p == null ? w : const SizedBox.shrink()),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x33000000), Color(0x00000000), Color(0xCC000000)], stops: [0, 0.4, 1]),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                right: 40,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.outline)),
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.text, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.6)),
                  ),
                ),
              ),
              if (room['locked'] == true) const Positioned(right: 10, top: 10, child: Icon(Icons.lock, size: 18, color: Pal.amber)),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((room['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, shadows: [Shadow(blurRadius: 6, color: Colors.black87)])),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.person, size: 16, color: Colors.white),
                    const SizedBox(width: 3),
                    Text('$count', style: const TextStyle(color: Colors.white, fontSize: 14)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Pal.pink, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Pal.pink.withValues(alpha: 0.5), blurRadius: 8)]),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.circle, size: 7, color: Colors.white),
                          SizedBox(width: 4),
                          Flexible(child: Text('CANLI', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11))),
                        ]),
                      ),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
