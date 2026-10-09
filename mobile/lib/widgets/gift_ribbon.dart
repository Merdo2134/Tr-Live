import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
import 'anim_asset.dart';
import 'common.dart';

/// Hediye şeridi ve giriş efektleri için üst katman.
/// [roomId] verilirse o odanın hediyeleri ve girişleri, verilmezse yalnızca global şeritler gösterilir.
class GiftRibbonOverlay extends StatefulWidget {
  final Widget child;
  final String? roomId;
  /// Bu cihazda hediye / giriş efektleri gösterilsin mi (oda araçlarındaki "Efekt ve Ses").
  static bool effectsOn = true;
  const GiftRibbonOverlay({super.key, required this.child, this.roomId});

  @override
  State<GiftRibbonOverlay> createState() => _GiftRibbonOverlayState();
}

class _GiftRibbonOverlayState extends State<GiftRibbonOverlay> {
  final List<Map<String, dynamic>> _queue = [];
  Map<String, dynamic>? _current;
  Map<String, dynamic>? _entrance;
  StreamSubscription? _sub;
  Timer? _timer;
  Timer? _entranceTimer;
  // Tam ekran hediye animasyonu (şeffaf mp4 = Tencent VAP, lottie, webp/gif). Sırayla, tek tek oynar.
  final List<Map<String, dynamic>> _anims = [];
  Map<String, dynamic>? _anim;
  int _animSeq = 0;
  Timer? _animTimer;

  @override
  void initState() {
    super.initState();
    _sub = SocketService.instance.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _entranceTimer?.cancel();
    _animTimer?.cancel();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> e) {
    if (!GiftRibbonOverlay.effectsOn) return;
    final type = e['type'];
    if (type == 'lucky_bag_global') {
      _enqueue(e); // süper çanta duyurusu: tüm odalarda ve ana ekranda
    } else if (type == 'global_gift_ribbon') {
      // Aynı odadaysak zaten room_gift ile göstereceğiz.
      if (widget.roomId != null && e['roomId'] == widget.roomId) return;
      _enqueue(e);
    } else if (type == 'room_gift' && widget.roomId != null && e['roomId'] == widget.roomId) {
      _enqueueAnim(mapOf(e['gift']));
      _enqueue(e);
    } else if (type == 'room_member_joined' && widget.roomId != null && e['roomId'] == widget.roomId) {
      final effect = mapOf(e['entranceEffect']);
      if (effect != null) _showEntrance(e, effect);
    }
  }

  void _enqueueAnim(Map<String, dynamic>? gift) {
    final url = Api.absoluteUrl(gift?['animationUrl'] as String?);
    if (gift == null || url == null) return;
    if (_anims.length < 5) _anims.add({'url': url, 'format': (gift['animationFormat'] ?? '').toString()});
    if (_anim == null) _nextAnim();
  }

  void _nextAnim() {
    _animTimer?.cancel();
    if (!mounted) return;
    if (_anims.isEmpty) {
      setState(() => _anim = null);
      return;
    }
    final a = _anims.removeAt(0);
    setState(() => _anim = {...a, 'seq': ++_animSeq});
    // Güvenlik süresi: oynatıcı bitiş bildirmese de ekran açık kalmasın.
    final still = !AnimAsset.reportsEnd(a['url'] as String, a['format'] as String);
    _animTimer = Timer(Duration(seconds: still ? 4 : 20), _nextAnim);
  }

  Widget _buildAnim() {
    final a = _anim!;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimAsset(
          url: a['url'] as String,
          format: a['format'] as String,
          key: ValueKey(a['seq']),
          onDone: _nextAnim,
          onFail: (m) {
            if (mounted) toast(context, '$m\n${a['url']}', error: true);
          },
        ),
      ),
    );
  }

  void _enqueue(Map<String, dynamic> e) {
    if (_queue.length < 10) _queue.add(e);
    if (_current == null) _next();
  }

  void _next() {
    _timer?.cancel();
    if (_queue.isEmpty) {
      if (mounted) setState(() => _current = null);
      return;
    }
    final e = _queue.removeAt(0);
    if (mounted) setState(() => _current = e);
    _timer = Timer(const Duration(milliseconds: 5200), _next);
  }

  void _showEntrance(Map<String, dynamic> e, Map<String, dynamic> effect) {
    _entranceTimer?.cancel();
    setState(() => _entrance = {'user': e['user'], 'effect': effect});
    final ms = (effect['durationMs'] as num?)?.toInt() ?? 4000;
    _entranceTimer = Timer(Duration(milliseconds: ms.clamp(1000, 10000)), () {
      if (mounted) setState(() => _entrance = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    return Stack(children: [
      widget.child,
      if (_anim != null) _buildAnim(),
      if (_entrance != null) _buildEntrance(top),
      if (_current != null) Positioned(top: top, left: 0, right: 0, child: _SlideStrip(key: ObjectKey(_current), child: _buildRibbon(_current!))),
    ]);
  }

  Widget _buildBagRibbon(Map<String, dynamic> e) {
    final sender = mapOf(e['sender']);
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0x009C6A00), Color(0xFFFFB300), Color(0xFFFFE082), Color(0xFFFFB300), Color(0x009C6A00)]),
            boxShadow: const [BoxShadow(color: Colors.amber, blurRadius: 14)],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🧧', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${sender?['displayName'] ?? 'Biri'} süper şanslı çanta gönderdi! ${fmtNumber(e['totalCoins'])} Coin • "${e['roomName'] ?? ''}"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF3A2500), fontSize: 13),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildRibbon(Map<String, dynamic> e) {
    if (e['type'] == 'lucky_bag_global') return _buildBagRibbon(e);
    final gift = mapOf(e['gift']) ?? {};
    final sender = mapOf(e['sender']);
    final receivers = e['receivers'] is List ? (e['receivers'] as List) : const [];
    final names = receivers
        .map((r) => (r is Map && r['user'] is Map ? (r['user'] as Map)['displayName'] : (r is Map ? r['displayName'] : null)))
        .whereType<String>()
        .toList();
    final icon = Api.absoluteUrl(gift['iconUrl'] as String?);
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0x00FF4081), Color(0xFFFF4081), Color(0xFF7C4DFF), Color(0x007C4DFF)]),
          ),
          child: Row(children: [
            if (icon != null) Image.network(icon, width: 32, height: 32, errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard)) else const Icon(Icons.card_giftcard),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${sender?['displayName'] ?? 'Biri'} → ${names.isEmpty ? 'herkes' : names.join(', ')}: ${gift['name'] ?? 'Hediye'} x${e['quantity']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildEntrance(double top) {
    final user = mapOf(_entrance!['user']);
    final effect = mapOf(_entrance!['effect']) ?? {};
    final url = Api.absoluteUrl(effect['animationUrl'] as String?);
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(alignment: Alignment.center, children: [
          if (url != null)
            AnimAsset(url: url, cache: false),
          Positioned(
            bottom: 140,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  UserAvatar(user: user, radius: 14),
                  const SizedBox(width: 8),
                  Text('${user?['displayName'] ?? 'Biri'} odaya girdi', style: const TextStyle(color: Colors.white)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}


/// Şeridi sağdan sola kaydırarak geçirir (giriş → bekleme → çıkış).
class _SlideStrip extends StatefulWidget {
  final Widget child;
  const _SlideStrip({super.key, required this.child});
  @override
  State<_SlideStrip> createState() => _SlideStripState();
}

class _SlideStripState extends State<_SlideStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5000))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value;
        double dx = 0;
        if (t < 0.12) {
          dx = (1 - Curves.easeOutCubic.transform(t / 0.12)) * w;
        } else if (t > 0.88) {
          dx = -Curves.easeInCubic.transform((t - 0.88) / 0.12) * w;
        }
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}
