import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/effect_prefs.dart';
import '../services/error_log.dart';
import '../services/room_dock.dart';
import '../services/session.dart';
import '../services/socket_service.dart';
import 'anim_asset.dart';
import 'common.dart';
import 'wip_items.dart';

/// Hediye şeridi ve giriş efektleri için üst katman.
/// [roomId] verilirse o odanın hediyeleri ve girişleri, verilmezse yalnızca global şeritler gösterilir.
class GiftRibbonOverlay extends StatefulWidget {
  final Widget child;
  final String? roomId;
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
  // 10'lu atılan hediyenin animasyonu 10 kez arka arkaya oynar: her tekrar bir önceki bitince hemen başlar
  // (iç içe girmesin diye aynı anda tek animasyon).
  final List<Map<String, dynamic>> _anims = []; // sırada bekleyen tekrarlar
  final List<Map<String, dynamic>> _active = []; // şu an ekranda oynayanlar
  final Map<int, Timer> _animTimers = {};
  int _animSeq = 0;
  Timer? _pumpTimer;
  DateTime _lastStart = DateTime(2000);
  static const _maxLayers = 1;
  static const _repeatGap = Duration.zero;
  static const _maxRepeats = 10;

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
    _pumpTimer?.cancel();
    for (final t in _animTimers.values) {
      t.cancel();
    }
    _gTimer?.cancel();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> e) {
    // Her efekt türü "Efekt ve Ses" ayarlarından ayrı ayrı kapatılabilir (EffectPrefs).
    final type = e['type'];
    if (type == 'lucky_bag_global' || type == 'lucky_gift_win' || type == 'global_gift_ribbon') {
      if (!EffectPrefs.globalNotice) return;
      // Global duyurular (büyük hediye, süper çanta, büyük şanslı kazanç): yalnızca açık odalarda (hediyenin atıldığı
      // oda dahil), odanın üstünden geçen ayrı şeritte. Ana ekranda ve oda küçültülmüşken gösterilmez.
      if (widget.roomId == null || RoomDock.minimized.value) return;
      if (e['roomId'] == widget.roomId) {
        // Hediyenin atıldığı oda: önce yalnızca ortadaki oda şeridi geçer; o bitince yarım saniye sonra üst şerit bir kez geçer
        // (ikisi aynı anda görünmesin).
        _afterRoomRibbon(() => _enqueueGlobal(e));
      } else {
        _enqueueGlobal(e);
      }
    } else if (type == 'room_gift' && widget.roomId != null && e['roomId'] == widget.roomId) {
      // Önce ikon koltuğa uçar (oda ekranı), sonra tam ekran animasyon başlar.
      final g = mapOf(e['gift']);
      // Adet kadar tekrar (10'lu → 10 kez, en fazla 10).
      final times = ((e['quantity'] as num?)?.toInt() ?? 1).clamp(1, _maxRepeats);
      if (EffectPrefs.giftAnim) {
        Future.delayed(const Duration(milliseconds: 1300), () {
          if (mounted) _enqueueAnim(g, times: times);
        });
      }
      if (EffectPrefs.giftRibbon && !_mergeCombo(e)) _enqueue(e);
    } else if (type == 'lucky_bag_claimed' && widget.roomId != null && e['roomId'] == widget.roomId && e['user'] != null) {
      if (EffectPrefs.giftRibbon) _enqueue(e); // çantadan kim ne kadar aldı: odanın ortasından geçen kısa şerit
    } else if ((type == 'room_member_joined' || type == 'local_entrance') && widget.roomId != null && e['roomId'] == widget.roomId) {
      final effect = mapOf(e['entranceEffect']);
      // SWIP araçları kapatılamaz (Yoho'daki gibi en üst kademe her zaman görünür).
      final swip = effect?['kind'] == 'wip_vehicle' && (wipLevelOf(effect?['level']) ?? 0) >= 11;
      if (effect != null && (EffectPrefs.entranceFx || swip)) _showEntrance(e, effect);
    }
  }

  void _enqueueAnim(Map<String, dynamic>? gift, {int times = 1}) {
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
    // Sıra çok uzamasın (art arda yüzlerce hediye): en fazla 30 tekrar bekler.
    for (var i = 0; i < times && _anims.length < 30; i++) {
      _anims.add({'url': url, 'format': (gift['animationFormat'] ?? '').toString(), 'sound': true});
    }
    _pump();
  }

  /// Sıradaki tekrarı başlatır: oynayan yoksa (önceki bittiyse) hemen.
  void _pump() {
    _pumpTimer?.cancel();
    if (!mounted || _anims.isEmpty) return;
    if (_active.length >= _maxLayers) return; // oynayan bitince _animDone yeniden çağırır
    final wait = _repeatGap - DateTime.now().difference(_lastStart);
    if (wait > Duration.zero) {
      _pumpTimer = Timer(wait, _pump);
      return;
    }
    final a = {..._anims.removeAt(0), 'seq': ++_animSeq};
    _lastStart = DateTime.now();
    setState(() => _active.add(a));
    final seq = a['seq'] as int;
    // Güvenlik süresi: oynatıcı bitiş bildirmese de katman ekranda kalmasın.
    final still = !AnimAsset.reportsEnd(a['url'] as String, a['format'] as String);
    _animTimers[seq] = Timer(Duration(seconds: still ? 4 : 20), () => _animDone(seq));
    if (_anims.isNotEmpty && _active.length < _maxLayers) _pumpTimer = Timer(_repeatGap, _pump);
  }

  void _animDone(int seq) {
    _animTimers.remove(seq)?.cancel();
    if (!mounted) return;
    setState(() => _active.removeWhere((x) => x['seq'] == seq));
    _pump();
  }

  Widget _buildAnim(Map<String, dynamic> a) {
    final seq = a['seq'] as int;
    return Positioned.fill(
      key: ValueKey('anim-$seq'),
      child: IgnorePointer(
        child: AnimAsset(
          url: a['url'] as String,
          format: a['format'] as String,
          key: ValueKey(seq),
          sound: a['sound'] == true,
          onDone: () => _animDone(seq),
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

  // Global şerit kanalı (oda şeridinden bağımsız sıra).
  final List<Map<String, dynamic>> _gQueue = [];
  Map<String, dynamic>? _gCurrent;
  int _gSeq = 0;
  Timer? _gTimer;

  /// Ortadaki oda şeridi (ve sırada bekleyenler) bitince yarım saniye sonra [run] çalışır (en fazla 15 sn beklenir).
  void _afterRoomRibbon(VoidCallback run) {
    var waited = 0;
    void check() {
      if (!mounted) return;
      if ((_current != null || _queue.isNotEmpty) && waited < 15000) {
        waited += 300;
        Future.delayed(const Duration(milliseconds: 300), check);
        return;
      }
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) run();
      });
    }
    // Oda şeridi aynı anda gelen olayla kuyruğa girsin diye kısa bir an beklenir.
    Future.delayed(const Duration(milliseconds: 400), check);
  }

  // Son gösterilen global duyurular: aynı duyuru iki kez gelirse (ör. iki bağlantıdan) bir kez gösterilir.
  final Map<String, DateTime> _gSeen = {};

  void _enqueueGlobal(Map<String, dynamic> e) {
    final now = DateTime.now();
    _gSeen.removeWhere((_, t) => now.difference(t).inSeconds > 30);
    final key = (e['eventId'] ??
            '${e['type']}|${mapOf(e['sender'])?['id']}|${mapOf(e['gift'])?['id']}|${e['quantity']}|${e['totalCoins']}|${e['bagId']}|${e['win']}')
        .toString();
    if (_gSeen.containsKey(key)) return;
    _gSeen[key] = now;
    if (_gQueue.length < 8) _gQueue.add(e);
    if (_gCurrent == null) _nextGlobal();
  }

  void _nextGlobal() {
    _gTimer?.cancel();
    if (!mounted) return;
    if (_gQueue.isEmpty) {
      setState(() => _gCurrent = null);
      return;
    }
    final e = _gQueue.removeAt(0);
    setState(() {
      _gCurrent = e;
      _gSeq++;
    });
    _gTimer = Timer(const Duration(milliseconds: 5200), _nextGlobal);
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
    _timer = Timer(Duration(milliseconds: _stripMs(e) + 200), _next);
  }

  /// Çanta payı şeritleri kısa (art arda çok gelir), hediye şeritleri uzun.
  int _stripMs(Map<String, dynamic> e) => e['type'] == 'lucky_bag_claimed' ? 2800 : 5000;

  int _entranceSeq = 0;

  void _showEntrance(Map<String, dynamic> e, Map<String, dynamic> effect) {
    // Oda küçültülmüşken giriş aracı / efekti oynatılmaz.
    if (widget.roomId != null && RoomDock.minimized.value) return;
    _entranceTimer?.cancel();
    setState(() => _entrance = {'user': e['user'], 'effect': effect, 'seq': ++_entranceSeq});
    final ms = (effect['durationMs'] as num?)?.toInt() ?? 4000;
    _entranceTimer = Timer(Duration(milliseconds: ms.clamp(1000, 10000)), () {
      if (mounted) setState(() => _entrance = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    // Odada şerit odanın ortasından geçer (koltukların altı, sohbetin üstü); ana sayfada en üstte.
    final ribbonTop = MediaQuery.sizeOf(context).height * 0.42;
    return Stack(children: [
      widget.child,
      for (final a in _active) _buildAnim(a),
      if (_entrance != null) _buildEntrance(top),
      if (_current != null)
        Positioned(
          top: widget.roomId != null ? ribbonTop : top,
          left: 0,
          right: 0,
          child: _SlideStrip(key: ValueKey(_currentSeq), bump: _bump, durationMs: _stripMs(_current!), child: _buildRibbon(_current!)),
        ),
      // Global şerit: odada ve ana ekranda en üstten (durum çubuğunun hemen altından) geçer.
      if (_gCurrent != null)
        Positioned(
          top: MediaQuery.of(context).padding.top,
          left: 0,
          right: 0,
          child: _SlideStrip(key: ValueKey('g$_gSeq'), durationMs: 5000, child: _buildRibbon(_gCurrent!)),
        ),
    ]);
  }

  /// Çantadan pay alan kişi: pembe şerit, kese ve Coin.
  Widget _buildBagClaimRibbon(Map<String, dynamic> e) {
    final u = mapOf(e['user']);
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0x00FF4F9A), Color(0xEEFF4F9A), Color(0xEEB0127A), Color(0x00B0127A)]),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Image.asset('assets/images/lucky_pouch.webp', width: 30, height: 30),
            const SizedBox(width: 6),
            UserAvatar(user: u, radius: 13),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${u?['displayName'] ?? 'Biri'} çantadan aldı',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 13.5, shadows: [Shadow(color: Colors.black45, blurRadius: 3)]),
              ),
            ),
            const SizedBox(width: 6),
            Image.asset('assets/images/lucky_coin.png', width: 18, height: 18),
            const SizedBox(width: 3),
            Text(fmtNumber(e['amount']), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFFE082), fontSize: 15)),
          ]),
        ),
      ),
    );
  }

  /// Global hediye şeridi (yeni tasarım): kırmızı-altın bant üzerinde gönderen → alan, hediye ve adet.
  Widget _buildGlobalRibbon(Map<String, dynamic> e) {
    final gift = mapOf(e['gift']) ?? {};
    final sender = mapOf(e['sender']);
    final receivers = e['receivers'] is List ? (e['receivers'] as List) : const [];
    final names = receivers
        .map((r) => (r is Map && r['user'] is Map ? (r['user'] as Map)['displayName'] : (r is Map ? r['displayName'] : null)))
        .whereType<String>()
        .toList();
    final icon = Api.absoluteUrl(gift['iconUrl'] as String?);
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        // Küçük tutulur (üstten geçerken odayı kapatmasın): ekranın ~%68'i, en fazla 290 dp; yükseklik görsel oranında.
        final w = (box.maxWidth * 0.68).clamp(0.0, 290.0).toDouble();
        final h = w / 3;
        final fs = (h * 0.16).clamp(9.0, 14.0).toDouble();
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              Positioned.fill(child: Image.asset('assets/images/gift_ribbon_gold.webp', fit: BoxFit.fill)),
              // Kırmızı alanın içi (görselde yaklaşık %35–%80 yükseklik).
              Positioned(
                left: w * 0.08,
                right: w * 0.08,
                top: h * 0.36,
                height: h * 0.44,
                child: Row(children: [
                  UserAvatar(user: sender, radius: h * 0.15),
                  SizedBox(width: w * 0.02),
                  // Gönderen ve alıcı alt alta; sağda hediyenin görseli ve adedi.
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: 'Gönderen ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: fs * 0.85)),
                          TextSpan(text: '${sender?['displayName'] ?? 'Biri'}', style: TextStyle(color: const Color(0xFFFFE082), fontWeight: FontWeight.w900, fontSize: fs)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.2, shadows: [Shadow(color: Colors.black54, blurRadius: 3)]),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: 'Alıcı ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: fs * 0.85)),
                          TextSpan(text: names.isEmpty ? 'herkes' : names.join(', '), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: fs)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.2, shadows: [Shadow(color: Colors.black54, blurRadius: 3)]),
                      ),
                    ]),
                  ),
                  if (icon != null) NetImg(icon, width: h * 0.4, height: h * 0.4, errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.white)),
                  SizedBox(width: w * 0.01),
                  Text('x${e['quantity'] ?? 1}', style: TextStyle(color: const Color(0xFFFFD54F), fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: fs * 1.3, shadows: const [Shadow(color: Color(0xFFFF6D00), blurRadius: 6)])),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
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
            Image.asset('assets/images/lucky_pouch.webp', width: 30, height: 30),
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
    if (e['type'] == 'lucky_bag_claimed') return _buildBagClaimRibbon(e);
    if (e['type'] == 'global_gift_ribbon') return _buildGlobalRibbon(e);
    final gift = mapOf(e['gift']) ?? {};
    final sender = mapOf(e['sender']);
    final receivers = e['receivers'] is List ? (e['receivers'] as List) : const [];
    final names = receivers
        .map((r) => (r is Map && r['user'] is Map ? (r['user'] as Map)['displayName'] : (r is Map ? r['displayName'] : null)))
        .whereType<String>()
        .toList();
    final icon = Api.absoluteUrl(gift['iconUrl'] as String?);
    final combo = (e['combo'] as num?)?.toInt() ?? 1;
    final qty = (e['quantity'] as num?)?.toInt() ?? 1;
    // Şanslı hediyede en yüksek çarpan şeritte gösterilir (x2 ve üzeri).
    final lucky = mapOf(e['lucky']);
    final luckyBest = (lucky?['best'] as num?)?.toInt() ?? 0;
    Map<String, dynamic>? firstReceiver;
    if (receivers.isNotEmpty) {
      final r = receivers.first;
      firstReceiver = r is Map && r['user'] is Map ? Map<String, dynamic>.from(r['user'] as Map) : (r is Map ? Map<String, dynamic>.from(r) : null);
    }
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: LayoutBuilder(builder: (context, box) {
          // Ekran genişliğine göre kendini ölçekler; isimler uzunsa kısaltılır, şerit içeriği kadar genişler.
          final sw = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
          final k = (sw / 400).clamp(0.82, 1.2).toDouble();
          final h = 46 * k;
          final giftSize = 58 * k;
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 6 * k),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: sw * 0.94),
                child: SizedBox(
                  height: giftSize,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Container(
                        height: h,
                        padding: EdgeInsets.fromLTRB(3 * k, 3 * k, 14 * k, 3 * k),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(h / 2),
                          gradient: const LinearGradient(colors: [Color(0xF26A11CB), Color(0xE6C2185B), Color(0x99FF6FA8), Color(0x00FF6FA8)], stops: [0, 0.45, 0.8, 1]),
                          border: const Border(top: BorderSide(color: Color(0x88FFFFFF), width: 0.8)),
                          boxShadow: const [BoxShadow(color: Color(0x66E040FB), blurRadius: 12)],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          // Gönderen: altın halkalı fotoğraf
                          Container(
                            padding: EdgeInsets.all(1.6 * k),
                            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFFF1A8), Color(0xFFFFB300), Color(0xFFFF8F00)])),
                            child: UserAvatar(user: sender, radius: (h - 9 * k) / 2),
                          ),
                          SizedBox(width: 7 * k),
                          Flexible(
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                '${sender?['displayName'] ?? 'Biri'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5 * k, height: 1.1, shadows: const [Shadow(color: Colors.black45, blurRadius: 3)]),
                              ),
                              Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: 'gönderdi ', style: TextStyle(color: Colors.white70, fontSize: 11 * k)),
                                  TextSpan(
                                    text: names.isEmpty ? 'herkese' : (names.length == 1 ? names.first : '${names.first} +${names.length - 1}'),
                                    style: TextStyle(color: const Color(0xFFFFE082), fontSize: 11.5 * k, fontWeight: FontWeight.w800),
                                  ),
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(height: 1.15),
                              ),
                            ]),
                          ),
                          if (firstReceiver != null) ...[
                            SizedBox(width: 6 * k),
                            Container(
                              padding: EdgeInsets.all(1.2 * k),
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFF80AB)),
                              child: UserAvatar(user: firstReceiver, radius: 12 * k),
                            ),
                          ],
                        ]),
                      ),
                    ),
                    // Hediye: şeridin ucuna taşan, arkası parlayan büyük ikon
                    Transform.translate(
                      offset: Offset(-10 * k, 0),
                      child: Container(
                        width: giftSize,
                        height: giftSize,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [Color(0xAAFFE082), Color(0x33FF4081), Color(0x00FF4081)]),
                        ),
                        child: icon != null
                            ? NetImg(icon, width: giftSize * 0.86, height: giftSize * 0.86, errorBuilder: (_, __, ___) => Icon(Icons.card_giftcard, color: Colors.white, size: 30 * k))
                            : Icon(Icons.card_giftcard, color: Colors.white, size: 30 * k),
                      ),
                    ),
                    if (luckyBest >= 2)
                      Container(
                        margin: EdgeInsets.only(right: 4 * k),
                        padding: EdgeInsets.symmetric(horizontal: 5 * k, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFF00C853), borderRadius: BorderRadius.circular(8)),
                        child: Text('🔔 x$luckyBest', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11 * k)),
                      ),
                    // Adet / combo: her artışta büyüyüp yerine oturur.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: Tween<double>(begin: 1.8, end: 1).animate(anim), child: child),
                      child: Text(
                        'x${combo > 1 ? combo : qty}',
                        key: ValueKey('$combo-$qty'),
                        style: TextStyle(
                          fontSize: 28 * k,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: const Color(0xFFFFE082),
                          shadows: const [Shadow(color: Color(0xFFFF6D00), blurRadius: 8), Shadow(color: Color(0xFF6A11CB), offset: Offset(1.5, 1.5))],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Giriş aracı / özel giriş efekti. Araç sabit bir görselse (png/webp/jpg) odanın ortasından sağdan sola geçer;
  /// animasyonsa (svga, Lottie, şeffaf mp4, gif) tam ekran oynar. Altında "X, Araç ile geldi" yazar.
  Widget _buildEntrance(double top) {
    final user = mapOf(_entrance!['user']);
    final effect = mapOf(_entrance!['effect']) ?? {};
    final url = Api.absoluteUrl(effect['animationUrl'] as String?);
    final wipVehicle = effect['kind'] == 'wip_vehicle';
    final wipLevel = wipVehicle ? wipLevelOf(effect['level']) : null;
    final vehicle = effect['kind'] == 'vehicle' || wipVehicle;
    final ext = url == null ? '' : AnimAsset.extOf(url);
    final still = const {'png', 'jpg', 'jpeg', 'webp'}.contains(ext);
    final ms = ((effect['durationMs'] as num?)?.toInt() ?? 4000).clamp(1000, 10000);
    final name = (user?['displayName'] ?? 'Biri').toString();
    final itemName = wipVehicle ? (WipStyle.of(wipLevel)?.vehicleName ?? '') : (effect['itemName'] ?? '').toString();
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(alignment: Alignment.center, children: [
          // WIP aracı: kodla çizilir (dosya gerekmez).
          if (wipVehicle && wipLevel != null)
            WipVehicleDrive(key: ValueKey('wipveh-${_entrance!['seq']}'), level: wipLevel, durationMs: ms)
          else if (url != null && vehicle && still)
            _VehicleDrive(key: ValueKey('veh-${_entrance!['seq']}'), url: url, durationMs: ms)
          else if (url != null)
            AnimAsset(key: ValueKey('ent-${_entrance!['seq']}'), url: url, cache: false, sound: true),
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
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.62),
                    child: Text(
                      vehicle && itemName.isNotEmpty ? '$name, $itemName ile geldi' : '$name odaya girdi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Sabit görselli giriş aracı: sağdan gelir, ortada kısa süre durur (hafifçe sallanarak), soldan çıkar.
class _VehicleDrive extends StatefulWidget {
  final String url;
  final int durationMs;
  const _VehicleDrive({super.key, required this.url, required this.durationMs});

  @override
  State<_VehicleDrive> createState() => _VehicleDriveState();
}

class _VehicleDriveState extends State<_VehicleDrive> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.durationMs))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final size = w * 0.62;
    // Kendi katmanında: araç kayarken yalnızca konumu değişir, görsel ve oda yeniden çizilmez.
    return RepaintBoundary(
      child: AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        const inEnd = 0.25, outStart = 0.75;
        double dx;
        if (t < inEnd) {
          dx = (1 - Curves.easeOutCubic.transform(t / inEnd)) * w;
        } else if (t > outStart) {
          dx = -Curves.easeInCubic.transform((t - outStart) / (1 - outStart)) * w;
        } else {
          dx = 0;
        }
        final bob = (t * widget.durationMs / 120) % 2 < 1 ? 1.5 : -1.5;
        return Transform.translate(offset: Offset(dx, bob), child: child);
      },
      child: RepaintBoundary(
        child: SizedBox(
          width: size,
          height: size,
          child: NetImg(widget.url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
      ),
      ),
    );
  }
}

/// Şeridi sağdan sola kaydırarak geçirir (giriş → bekleme → çıkış).
class _SlideStrip extends StatefulWidget {
  final Widget child;
  /// Değişince (combo) şerit ekranda kalır ve bekleme süresi baştan başlar.
  final int bump;
  final int durationMs;
  const _SlideStrip({super.key, required this.child, this.bump = 0, this.durationMs = 5000});
  @override
  State<_SlideStrip> createState() => _SlideStripState();
}

class _SlideStripState extends State<_SlideStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.durationMs))..forward();

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
    return RepaintBoundary(
      child: AnimatedBuilder(
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
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}
