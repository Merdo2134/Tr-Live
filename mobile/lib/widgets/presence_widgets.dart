import 'package:flutter/material.dart';
import '../services/presence_service.dart';
import 'app_theme.dart';

/// Avatarın sağ altına yeşil "çevrimiçi" noktası ekler (canlı güncellenir).
class PresenceAvatar extends StatelessWidget {
  final String? userId;
  final Widget child;
  final double dotSize;
  const PresenceAvatar({super.key, required this.userId, required this.child, this.dotSize = 13});

  @override
  Widget build(BuildContext context) {
    final id = userId;
    if (id == null || id.isEmpty) return child;
    return ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
      valueListenable: PresenceService.states,
      builder: (context, states, avatar) {
        final online = states[id]?['online'] == true;
        return Stack(clipBehavior: Clip.none, children: [
          avatar!,
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(color: Pal.green, shape: BoxShape.circle, border: Border.all(color: Pal.surface, width: 2)),
              ),
            ),
        ]);
      },
      child: child,
    );
  }
}

/// "Çevrimiçi" / "Son görülme ..." satırı. [presence] verilirse o gösterilir, verilmezse canlı durum izlenir.
class PresenceLine extends StatelessWidget {
  final String? userId;
  final Map<String, dynamic>? presence;
  final double fontSize;
  const PresenceLine({super.key, this.userId, this.presence, this.fontSize = 12});

  Widget _line(Map<String, dynamic>? p) {
    final label = presenceLabel(p);
    if (label == null) return const SizedBox.shrink();
    final online = p?['online'] == true;
    final color = online ? Pal.green : Pal.textDim;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w500))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final fixed = presence;
    if (fixed != null) return _line(fixed);
    final id = userId;
    if (id == null || id.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
      valueListenable: PresenceService.states,
      builder: (context, states, _) => _line(states[id]),
    );
  }
}
