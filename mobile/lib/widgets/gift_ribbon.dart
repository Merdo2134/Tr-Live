import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_vap_kit/flutter_vap_kit.dart';
import 'package:lottie/lottie.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
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
    if (type == 'global_gift_ribbon') {
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
    final still = a['format'] != 'mp4' && a['format'] != 'lottie' && !(a['url'] as String).toLowerCase().split('?').first.endsWith('.mp4') && !(a['url'] as String).toLowerCase().split('?').first.endsWith('.json');
    _animTimer = Timer(Duration(seconds: still ? 4 : 15), _nextAnim);
  }

  Widget _buildAnim() {
    final a = _anim!;
    final url = a['url'] as String;
    final format = a['format'] as String;
    final key = ValueKey(a['seq']);
    final isLottie = format == 'lottie' || url.toLowerCase().split('?').first.endsWith('.json');
    final isVideo = format == 'mp4' || url.toLowerCase().split('?').first.endsWith('.mp4');
    Widget child;
    if (isVideo) {
      child = VapPlayer.network(url, key: key, fit: BoxFit.contain, onComplete: _nextAnim);
    } else if (isLottie) {
      child = Lottie.network(
        url,
        key: key,
        repeat: false,
        onLoaded: (c) {
          _animTimer?.cancel();
          _animTimer = Timer(c.duration + const Duration(milliseconds: 300), _nextAnim);
        },
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else {
      child = Image.network(url, key: key, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink());
    }
    return Positioned.fill(child: IgnorePointer(child: child));
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
    _timer = Timer(const Duration(seconds: 4), _next);
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
      if (_current != null) Positioned(top: top, left: 12, right: 12, child: _buildRibbon(_current!)),
    ]);
  }

  Widget _buildRibbon(Map<String, dynamic> e) {
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFF4081), Color(0xFF7C4DFF)]),
            borderRadius: BorderRadius.circular(24),
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
            Lottie.network(url, repeat: false, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
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
