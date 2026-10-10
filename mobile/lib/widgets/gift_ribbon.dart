import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/error_log.dart';
import '../services/room_dock.dart';
import '../services/session.dart';
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
  int _currentSeq = 0; // şerit kimliği: combo güncellemesinde şerit yeniden kaymaz, yalnızca süresi uzar
  int _bump = 0;
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
    if (type == 'lucky_bag_global' || type == 'lucky_gift_win') {
      _enqueue(e); // süper çanta / büyük şanslı hediye kazancı duyurusu: tüm odalarda ve ana ekranda
    } else if (type == 'global_gift_ribbon') {
      // Aynı odadaysak zaten room_gift ile göstereceğiz.
      if (widget.roomId != null && e['roomId'] == widget.roomId) return;
      _enqueue(e);
    } else if (type == 'room_gift' && widget.roomId != null && e['roomId'] == widget.roomId) {
      // Önce ikon koltuğa uçar (oda ekranı), sonra tam ekran animasyon başlar.
      final g = mapOf(e['gift']);
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _enqueueAnim(g);
      });
      if (!_mergeCombo(e)) _enqueue(e);
    } else if (type == 'room_member_joined' && widget.roomId != null && e['roomId'] == widget.roomId) {
      final effect = mapOf(e['entranceEffect']);
      if (effect != null) _showEntrance(e, effect);
    }
  }

  void _enqueueAnim(Map<String, dynamic>? gift) {
    // Oda küçültülmüşken tam ekran hediye animasyonları birikmesin.
    if (widget.roomId != null && RoomDock.minimized.value) return;
    final url = Api.absoluteUrl(gift?['animationUrl'] as String?);
    if (gift == null) return;
    if (url == null) {
      if (gift['category'] == 'lucky') return; // şanslı hediyenin tam ekran animasyonu zorunlu değil
      // Kullanıcıya teknik mesaj gösterilmez; yalnızca yetkililere ve hata kaydına düşer.
      ErrorLog.add('Hediye animasyonu yok', '"${gift['name']}" için animasyon dosyası tanımlı değil');
      if (mounted && Session.isStaff) toast(context, '"${gift['name']}" hediyesinde animasyon dosyası yok (Yönetim → Katalog).', error: true);
      return;
    }
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
            ErrorLog.add('Hediye animasyonu oynatılamadı', '$m ${a['url']}');
            if (mounted && Session.isStaff) toast(context, 'Animasyon oynatılamadı: $m', error: true);
          },
        ),
      ),
    );
  }

  /// Aynı gönderen → aynı alıcılar, aynı hediye (combo serisi).
  String _comboKey(Map<String, dynamic> e) {
    final receivers = e['receivers'] is List ? (e['receivers'] as List) : const [];
    final ids = [for (final r in receivers) if (r is Map && r['user'] is Map) '${(r['user'] as Map)['id']}']..sort();
    return '${mapOf(e['sender'])?['id']}|${mapOf(e['gift'])?['id']}|${ids.join(',')}';
  }

  /// Combo: ekranda (ya da sırada) aynı serinin şeridi varsa yeni şerit açılmaz; sayaç güncellenir, süre uzar.
  bool _mergeCombo(Map<String, dynamic> e) {
    final combo = (e['combo'] as num?)?.toInt() ?? 1;
    if (combo < 2) return false;
    final key = _comboKey(e);
    final cur = _current;
    if (cur != null && cur['type'] == 'room_gift' && _comboKey(cur) == key) {
      _timer?.cancel();
      // Şerit beklemeye baştan döner (kalan ~4,4 sn); sıradaki şerit boşluk kalmadan gelsin.
      _timer = Timer(const Duration(milliseconds: 4600), _next);
      setState(() {
        _current = e;
        _bump++;
      });
      return true;
    }
    for (var i = 0; i < _queue.length; i++) {
      final q = _queue[i];
      if (q['type'] == 'room_gift' && _comboKey(q) == key) {
        _queue[i] = e;
        return true;
      }
    }
    return false;
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
    if (mounted) {
      setState(() {
        _current = e;
        _currentSeq++;
      });
    }
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
      if (_current != null) Positioned(top: top, left: 0, right: 0, child: _SlideStrip(key: ValueKey(_currentSeq), bump: _bump, child: _buildRibbon(_current!))),
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

  /// Büyük şanslı hediye kazancı (Yoho "çan" duyurusu).
  Widget _buildLuckyRibbon(Map<String, dynamic> e) {
    final sender = mapOf(e['sender']);
    final gift = mapOf(e['gift']);
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0x0000C853), Color(0xFF00C853), Color(0xFFFFD54F), Color(0xFF00C853), Color(0x0000C853)]),
            boxShadow: [BoxShadow(color: Color(0xAA00E676), blurRadius: 14)],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🔔', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${sender?['displayName'] ?? 'Biri'} ${gift?['name'] ?? 'şanslı hediye'} ile x${e['multiplier']} vurdu! +${fmtNumber(e['win'])} Coin',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 13, shadows: [Shadow(color: Colors.black54, blurRadius: 3)]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildRibbon(Map<String, dynamic> e) {
    if (e['type'] == 'lucky_bag_global') return _buildBagRibbon(e);
    if (e['type'] == 'lucky_gift_win') return _buildLuckyRibbon(e);
    final gift = mapOf(e['gift']) ?? {};
    final sender = mapOf(e['sender']);
    final receivers = e['receivers'] is List ? (e['receivers'] as List) : const [];
    final names = receivers
        .map((r) => (r is Map && r['user'] is Map ? (r['user'] as Map)['displayName'] : (r is Map ? r['displayName'] : null)))
        .whereType<String>()
        .toList();
    final icon = Api.absoluteUrl(gift['iconUrl'] as String?);
    final combo = (e['combo'] as num?)?.toInt() ?? 1;
    // Şanslı hediyede en yüksek çarpan şeritte gösterilir (x2 ve üzeri).
    final lucky = mapOf(e['lucky']);
    final luckyBest = (lucky?['best'] as num?)?.toInt() ?? 0;
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
            if (luckyBest >= 2) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF00C853), borderRadius: BorderRadius.circular(8)),
                child: Text('🔔 x$luckyBest', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
              ),
            ],
            if (combo > 1) ...[
              const SizedBox(width: 8),
              // Her combo'da sayı büyüyüp yerine oturur.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, anim) => ScaleTransition(scale: Tween<double>(begin: 1.8, end: 1).animate(anim), child: child),
                child: Text(
                  'x$combo',
                  key: ValueKey(combo),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFFFFD54F),
                    shadows: [Shadow(color: Color(0xFFFF6D00), blurRadius: 8)],
                  ),
                ),
              ),
            ],
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
  /// Değişince (combo) şerit ekranda kalır ve bekleme süresi baştan başlar.
  final int bump;
  const _SlideStrip({super.key, required this.child, this.bump = 0});
  @override
  State<_SlideStrip> createState() => _SlideStripState();
}

class _SlideStripState extends State<_SlideStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5000))..forward();

  @override
  void didUpdateWidget(covariant _SlideStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bump != widget.bump && _c.value > 0.12) _c.forward(from: 0.12);
  }

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
