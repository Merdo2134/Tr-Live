import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/music_service.dart';
import 'drag_bubble.dart';
import 'net_image.dart';

final ValueNotifier<Offset?> musicBubblePos = ValueNotifier<Offset?>(null);

/// Müzik çalarken odada görünen yuvarlak, sürüklenebilir müzik balonu (dönen kapak). Dokununca panel açılır.
class MusicBubble extends StatefulWidget {
  final VoidCallback onOpen;
  const MusicBubble({super.key, required this.onOpen});

  @override
  State<MusicBubble> createState() => _MusicBubbleState();
}

class _MusicBubbleState extends State<MusicBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: MusicService.instance.state,
      builder: (context, s, _) {
        final track = mapOf(s?['track']);
        if (track == null) return const SizedBox.shrink();
        final playing = s?['status'] == 'playing';
        if (playing && !_spin.isAnimating) {
          _spin.repeat();
        } else if (!playing && _spin.isAnimating) {
          _spin.stop();
        }
        final cover = Api.absoluteUrl(track['coverUrl'] as String?);
        // Plak (yeni tasarım): siyah plak döner, ortasında şarkının kapağı. Duraklatılınca durur, üstünde ⏸.
        return DragBubble(
          pos: musicBubblePos,
          size: 58,
          initial: const Offset(-1, -230),
          onTap: widget.onOpen,
          child: Stack(alignment: Alignment.center, children: [
            RepaintBoundary(
              child: RotationTransition(
                turns: _spin,
                child: RepaintBoundary(
                  child: Stack(alignment: Alignment.center, children: [
                    Container(
                      decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 8)]),
                      child: ClipOval(child: Image.asset('assets/images/music_disc.png', width: 58, height: 58, fit: BoxFit.cover)),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 1.2), color: const Color(0xFF2A1F45)),
                      child: ClipOval(
                        child: cover != null
                            ? NetImg(cover, box: const Size.square(24), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 14, color: Colors.pinkAccent))
                            : const Icon(Icons.music_note, size: 14, color: Colors.pinkAccent),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            if (!playing)
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.pause_rounded, size: 18, color: Colors.white),
              ),
          ]),
        );
      },
    );
  }
}
