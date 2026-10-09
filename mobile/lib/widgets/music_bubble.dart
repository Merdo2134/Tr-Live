import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/music_service.dart';
import 'drag_bubble.dart';

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
        return DragBubble(
          pos: musicBubblePos,
          size: 56,
          initial: const Offset(-1, -260),
          onTap: widget.onOpen,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1B1530),
              border: Border.all(color: Colors.pinkAccent, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
            ),
            child: ClipOval(
              child: Stack(alignment: Alignment.center, fit: StackFit.expand, children: [
                RotationTransition(
                  turns: _spin,
                  child: cover != null
                      ? Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.pinkAccent))
                      : const Icon(Icons.music_note, color: Colors.pinkAccent),
                ),
                if (!playing) const ColoredBox(color: Colors.black54, child: Icon(Icons.pause, color: Colors.white)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
