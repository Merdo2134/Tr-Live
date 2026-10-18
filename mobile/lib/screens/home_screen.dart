import 'dart:async';
import 'package:flutter/material.dart';
import '../services/music_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/crown_icon.dart';
import '../widgets/room_card.dart';
import '../services/api.dart';
import '../widgets/drag_bubble.dart';
import '../services/inbox_service.dart';
import '../services/room_dock.dart';
import '../services/socket_service.dart';
import '../widgets/common.dart';
import '../widgets/gift_ribbon.dart';
import 'feed_screen.dart';
import 'go_live_screen.dart';
import 'leaderboard_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'room_screen.dart';
import 'user_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final _audioKey = GlobalKey<RoomsTabState>();
  final _videoKey = GlobalKey<RoomsTabState>();

  StreamSubscription? _cpSub;

  @override
  void initState() {
    super.initState();
    Inbox.start();
    // CP sistemi: biri seni Arkadaş / CP olarak seçince kısa bildirim (yanıt: Mesajlar → Arkadaşlık isteği ya da profil kartı).
    _cpSub = SocketService.instance.events.listen((e) {
      if (!mounted) return;
      if (e['type'] == 'agency_invite') {
        final a = (mapOf(e['agency'])?['name'] ?? 'Bir ajans').toString();
        toast(context, '$a seni yayıncı olarak davet etti (Mesajlar → Ajans daveti)');
        return;
      }
      if (e['type'] == 'event_reward') {
        toast(context, '🏆 ${e['title'] ?? 'Etkinlik'} oldun!${e['rewarded'] == true ? ' Ödüllerin hesabına eklendi.' : ''}');
        return;
      }
      if (e['type'] == 'agency_created') {
        final a = (mapOf(e['agency'])?['name'] ?? 'Ajans').toString();
        toast(context, '"$a" ajansının sahibi oldun 🎉 (Profil → Ajans Merkezi)');
        return;
      }
      if (e['type'] != 'cp_request') return;
      final name = (mapOf(e['from'])?['displayName'] ?? 'Biri').toString();
      toast(context, '$name seni ${e['kind'] == 'cp' ? 'CP' : 'Arkadaş'} olarak seçti ❤ (Mesajlar → Arkadaşlık isteği)');
    });
  }

  Future<void> _joinByCode() async {
    final code = await askText(context, 'Gizli oda davet kodu', hint: '6 karakter');
    if (code == null || !mounted) return;
    final r = await guard(context, () => Api.post('/api/rooms/by-code', {'code': code}));
    if (r == null || !mounted) return;
    await openRoom(context, RoomRequest(roomId: r['roomId'].toString(), name: (r['name'] ?? 'Oda').toString(), code: code.trim().toUpperCase()));
  }

  @override
  void dispose() {
    _cpSub?.cancel();
    Inbox.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Oda tam ekran açıkken ana sayfa arkada çizilmez ve animasyonları durur (oda kapanınca/küçülünce aynen geri gelir).
      Positioned.fill(
        child: ValueListenableBuilder<RoomRequest?>(
          valueListenable: RoomDock.request,
          builder: (context, req, child) => ValueListenableBuilder<bool>(
            valueListenable: RoomDock.minimized,
            builder: (context, min, child) {
              final covered = req != null && !min;
              return Offstage(offstage: covered, child: TickerMode(enabled: !covered, child: child!));
            },
            child: child,
          ),
          child: _scaffold(context),
        ),
      ),
      // Açık oda: küçültülünce Offstage ile arka planda yaşamaya devam eder (ses kesilmez).
      ValueListenableBuilder<RoomRequest?>(
        valueListenable: RoomDock.request,
        builder: (context, req, _) {
          if (req == null) return const SizedBox.shrink();
          return ValueListenableBuilder<bool>(
            valueListenable: RoomDock.minimized,
            builder: (context, min, _) => Stack(children: [
              Positioned.fill(
                child: Offstage(
                  offstage: min,
                  child: TickerMode(
                    enabled: !min,
                    child: RoomScreen(key: ValueKey(RoomDock.serial), roomId: req.roomId, initialName: req.name, locked: req.locked, code: req.code),
                  ),
                ),
              ),
              if (min) _miniBar(req),
            ]),
          );
        },
      ),
    ]);
  }

  static final ValueNotifier<Offset?> _roomBubblePos = ValueNotifier<Offset?>(null);

  /// Küçültülmüş oda: sürüklenebilir yuvarlak balon. Dokununca büyür, sağ üstteki X odadan çıkarır.
  Widget _miniBar(RoomRequest req) {
    final initial = req.name.trim().isEmpty ? '?' : trUpper(req.name.trim().characters.first);
    return DragBubble(
      pos: _roomBubblePos,
      size: 64,
      initial: const Offset(-1, -170),
      onTap: RoomDock.expand,
      child: Stack(clipBehavior: Clip.none, children: [
        // Oda fotoğrafı yuvarlak içinde döner (plak gibi); fotoğraf yoksa odanın baş harfi.
        ValueListenableBuilder<String?>(
          valueListenable: RoomDock.cover,
          builder: (context, cover, _) => _SpinningRoomCover(cover: cover, initial: initial),
        ),
        // Müzik yalnızca odanın içinde: dışarıda ayrı müzik balonu yok, çalıyorsa oda balonunda küçük nota görünür.
        Positioned(
          left: -2,
          bottom: -2,
          child: ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: MusicService.instance.state,
            builder: (_, st, __) => st?['status'] == 'playing'
                ? const CircleAvatar(radius: 10, backgroundColor: Colors.black87, child: Icon(Icons.music_note, size: 13, color: Colors.pinkAccent))
                : const SizedBox.shrink(),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => RoomDock.exitHandler?.call(),
            child: const Padding(padding: EdgeInsets.all(6), child: CircleAvatar(radius: 10, backgroundColor: Colors.black87, child: Icon(Icons.close, size: 13, color: Colors.white))),
          ),
        ),
      ]),
    );
  }

  void _select(int i) {
    setState(() => _index = i);
    if (i == 0) _audioKey.currentState?.refresh();
    if (i == 2) _videoKey.currentState?.refresh();
  }

  /// Alt satır (Yoho: yalnızca simge): Sesli | Akış | Görüntülü | Mesajlar | Profil. Seçili simge dolu ve renkli.
  Widget _tabRow() {
    Widget item(int i, IconData icon, IconData activeIcon, String label, {Widget? badge}) {
      final sel = _index == i;
      final color = sel ? Pal.cyan : Pal.textDim;
      return Expanded(
        child: Semantics(
          button: true,
          selected: sel,
          label: label,
          child: Tooltip(
            message: label,
            child: InkWell(
              onTap: () => _select(i),
              child: SizedBox(height: 56, child: Center(child: badge ?? Icon(sel ? activeIcon : icon, color: color, size: 28))),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(color: Pal.surface, border: Border(top: BorderSide(color: Pal.outline, width: 0.8))),
      child: SafeArea(top: false, child: Row(children: [
        item(0, Icons.mic_none, Icons.mic, 'Sesli'),
        item(1, Icons.dynamic_feed_outlined, Icons.dynamic_feed, 'Akış'),
        item(2, Icons.videocam_outlined, Icons.videocam, 'Görüntülü'),
        item(
          3,
          Icons.chat_bubble_outline,
          Icons.chat_bubble,
          'Mesajlar',
          badge: ValueListenableBuilder<int>(
            valueListenable: Inbox.unread,
            builder: (_, n, __) => Badge(label: Text('$n'), isLabelVisible: n > 0, child: Icon(_index == 3 ? Icons.chat_bubble : Icons.chat_bubble_outline, color: _index == 3 ? Pal.cyan : Pal.textDim, size: 28)),
          ),
        ),
        item(
          4,
          Icons.person_outline,
          Icons.person,
          'Profil',
          badge: ValueListenableBuilder<Map<String, int>>(
            valueListenable: Inbox.badges,
            builder: (_, b, __) => Badge(smallSize: 9, isLabelVisible: (b['total'] ?? 0) > 0, child: Icon(_index == 4 ? Icons.person : Icons.person_outline, color: _index == 4 ? Pal.cyan : Pal.textDim, size: 28)),
          ),
        ),
      ])),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      body: Column(children: [
          // Yoho'da ayrı üst çubuk yok: her sekme kendi başlığını çizer (Sesli/Görüntülü: sekmeler + taç + oda aç).
          Expanded(
            child: SafeArea(
              bottom: false,
              child: GiftRibbonOverlay(
              // Görünmeyen sekmelerin animasyonları durur (TickerMode); yalnızca açık sekme çalışır.
              child: IndexedStack(index: _index, children: [
                TickerMode(enabled: _index == 0, child: RoomsTab(key: _audioKey, type: 'audio', onJoinCode: _joinByCode)),
                TickerMode(enabled: _index == 1, child: const FeedScreen()),
                TickerMode(enabled: _index == 2, child: RoomsTab(key: _videoKey, type: 'video', onJoinCode: _joinByCode)),
                TickerMode(enabled: _index == 3, child: const MessagesScreen()),
                TickerMode(enabled: _index == 4, child: const ProfileScreen()),
              ]),
            ),
            ),
          ),
        ]),
      bottomNavigationBar: _tabRow(),
    );
  }
}

/// Odayı dock'ta açar. Oda sahibi başka odaya geçerse kendi odası kapanacağı için önce sorulur.
Future<void> openRoom(BuildContext context, RoomRequest req) async {
  if (RoomDock.isOpen && RoomDock.request.value?.roomId != req.roomId && RoomDock.myRole == 'owner') {
    final ok = await confirm(context, 'Başka odaya geçerseniz kendi odanız kapanır. Devam edilsin mi?', action: 'Geç');
    if (!ok) return;
  }
  RoomDock.open(req);
}

class RoomsTab extends StatefulWidget {
  final String type; // audio | video
  final VoidCallback? onJoinCode;
  const RoomsTab({super.key, required this.type, this.onJoinCode});

  @override
  State<RoomsTab> createState() => RoomsTabState();
}

class RoomsTabState extends State<RoomsTab> {
  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;
  String? _error;
  String _q = '';
  Timer? _debounce;
  String _mode = 'popular'; // popular (Popüler) | friends (Takip: takip ettiğin yayıncılar)
  bool _searching = false;

  void toggleSearch() => setState(() {
        _searching = !_searching;
        if (!_searching && _q.isNotEmpty) {
          _q = '';
          refresh();
        }
      });

  void _dockChanged() {
    if (mounted && (!RoomDock.isOpen || RoomDock.minimized.value)) refresh();
  }

  @override
  void initState() {
    super.initState();
    RoomDock.request.addListener(_dockChanged);
    RoomDock.minimized.addListener(_dockChanged);
    refresh();
  }

  @override
  void dispose() {
    RoomDock.request.removeListener(_dockChanged);
    RoomDock.minimized.removeListener(_dockChanged);
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final r = await Api.get('/api/rooms', query: {
        'type': widget.type,
        if (_q.isNotEmpty) 'q': _q,
        if (_mode == 'friends') 'region': 'friends',
      });
      if (!mounted) return;
      setState(() {
        _rooms = listOf(r['rooms']);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _open(String id, String name, {bool locked = false}) => openRoom(context, RoomRequest(roomId: id, name: name, locked: locked));

  /// Oda aç. Sesli oda bir kez kurulur: kayıtlıysa doğrudan odana girersin. Görüntülü yayın açık değilse her seferinde
  /// "Yayın başlat" ekranı gelir (kamera önizlemesi, başlık, tür, Canlı/Çoklu seçimi); açıksa doğrudan girersin.
  Future<void> createRoom({String? type}) async {
    final roomType = type ?? widget.type;
    final mine = await guard(context, () => Api.get('/api/rooms/mine'));
    if (mine == null || !mounted) return;
    final rooms = mapOf(mine['rooms']) ?? <String, dynamic>{};
    final profile = mapOf(rooms[roomType]);
    if (profile != null && (roomType == 'audio' || profile['activeRoomId'] != null)) {
      final r = await guard(context, () => Api.post('/api/rooms', {'roomType': roomType}));
      final room = mapOf(r?['room']);
      if (room != null && mounted) await _open(room['id'] as String, (room['name'] ?? '').toString());
      return;
    }
    final room = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => GoLiveScreen(initialType: roomType, profiles: rooms)),
    );
    if (room != null && mounted) await _open(room['id'] as String, (room['name'] ?? '').toString());
  }

  /// Yoho sekmesi: seçili olan büyük ve kalın, altında kısa çizgi; diğerleri küçük ve soluk.
  Widget _topTab(String id, String label) {
    final sel = _mode == id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_mode == id) return;
        setState(() => _mode = id);
        refresh();
      },
      // Yoho ölçüsü: yazı merkezi durum çubuğunun 21 dp altında, çizgi 39 dp'de; seçili 23 sp kalın, diğerleri 18 sp.
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: SizedBox(
          height: 44,
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const SizedBox(height: 8),
            SizedBox(
              height: 26,
              // Görünmez kalın kopya genişliği sabitler: sekme değişince şerit boyu/ölçeği oynamaz.
              child: Stack(alignment: Alignment.center, children: [
                Opacity(opacity: 0, child: Text(label, style: const TextStyle(fontSize: 23, height: 1.0, fontWeight: FontWeight.w900))),
                Text(label, style: TextStyle(fontSize: sel ? 23 : 18, height: 1.0, fontWeight: sel ? FontWeight.w900 : FontWeight.w600, color: sel ? Pal.text : Pal.textDim)),
              ]),
            ),
            const SizedBox(height: 4),
            Container(width: 10, height: 3.5, decoration: BoxDecoration(color: sel ? Pal.text : Colors.transparent, borderRadius: BorderRadius.circular(2))),
          ]),
        ),
      ),
    );
  }

  /// Üst satır (Yoho): İlgili · Sıcak · Yakında sekmeleri; sağda sıralama (taç), arama, oda aç ve diğer.
  Widget _topBar(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final m = homeMargin(w);
    final video = widget.type == 'video';
    Widget icon(IconData i, String tip, VoidCallback onTap, {Color? color}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          icon: Icon(i, color: color ?? Pal.text, size: 25),
          onPressed: onTap,
        );
    // Sekme bloğu 44 dp + 11 dp: banner durum çubuğunun 55 dp altında başlar (Yoho).
    return Padding(
      padding: EdgeInsets.fromLTRB(m, 0, m, 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              _topTab('popular', 'Popüler'),
              _topTab('friends', 'Takip'),
            ]),
          ),
        ),
        // Sağdaki simgeler sekme yazısıyla aynı hizada (merkez 21 dp).
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Semantics(
              button: true,
              label: 'Sıralamalar',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                child: const Padding(padding: EdgeInsets.all(6), child: CrownIcon(size: 24)),
              ),
            ),
            icon(_searching ? Icons.close : Icons.search, 'Oda ara', toggleSearch),
            Tooltip(
              message: video ? 'Görüntülü yayın aç' : 'Sesli oda aç',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: createRoom,
                child: Ink(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: video ? const [Pal.purple, Pal.cyan] : const [Pal.orange, Pal.pink]),
                  ),
                  child: Icon(video ? Icons.videocam : Icons.mic, color: Colors.white, size: 18),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cols = Resp.roomColumns(w);
    final m = homeMargin(w);
    final gap = homeGap(w);
    // Yoho ızgarası: kare görsel + altında ad alanı; satırlar arası ek boşluk yok (ad alanı boşluğu da sağlar).
    final cw = (w - 2 * m - gap * (cols - 1)) / cols;
    final ratio = cw / (cw + RoomCard.titleAreaFor(w));
    final empty = _mode == 'friends'
        ? 'Takip ettiğin kişilerin açık odası yok.'
        : (_q.isEmpty ? 'Şu an açık oda yok. İlk odayı sen aç!' : 'Aramanıza uyan oda yok.');
    final head = <Widget>[
      const BannerCarousel(),
      SizedBox(height: gap),
    ];
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _rooms.isEmpty) {
      body = LoadError(message: _error!, onRetry: refresh);
    } else {
      body = RefreshIndicator(
        onRefresh: refresh,
        child: _rooms.isEmpty
            ? ListView(children: [...head, const SizedBox(height: 48), Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(color: Pal.textDim))))])
            : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: Column(mainAxisSize: MainAxisSize.min, children: head)),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(m, 0, m, 96),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 0, crossAxisSpacing: gap, childAspectRatio: ratio),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final r = _rooms[i];
                          return RoomCard(room: r, onTap: () => _open(r['id'] as String, (r['name'] ?? '').toString(), locked: r['locked'] == true));
                        },
                        childCount: _rooms.length,
                      ),
                    ),
                  ),
                ],
              ),
      );
    }
    return Column(children: [
      // Sekmelerin ölçüsü telefonun yazı boyutundan etkilenmez (Yoho gibi sabit).
      MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling), child: _topBar(context)),
      if (_searching)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Oda, yayıncı veya etiket ara',
              isDense: true,
              // Kullanıcı arama ve gizli odaya kodla giriş (eski ⋮ menüsündeydi) arama kutusunun sağında.
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Gizli odaya kodla gir',
                  icon: const Icon(Icons.vpn_key_outlined),
                  onPressed: widget.onJoinCode,
                ),
                IconButton(
                  tooltip: 'Kullanıcı ara',
                  icon: const Icon(Icons.person_search),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchScreen())),
                ),
              ]),
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () {
                _q = v.trim();
                refresh();
              });
            },
          ),
        ),
      Expanded(child: body),
    ]);
  }
}


/// Küçültülmüş oda balonu: oda fotoğrafı yavaşça döner.
class _SpinningRoomCover extends StatefulWidget {
  final String? cover;
  final String initial;
  const _SpinningRoomCover({required this.cover, required this.initial});

  @override
  State<_SpinningRoomCover> createState() => _SpinningRoomCoverState();
}

class _SpinningRoomCoverState extends State<_SpinningRoomCover> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFFFF4081)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.graphic_eq, color: Colors.white, size: 22),
        Text(widget.initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
      ]),
    );
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
      ),
      child: ClipOval(
        child: RepaintBoundary(
          child: RotationTransition(
            turns: _spin,
            child: widget.cover == null
                ? fallback
                : NetImg(widget.cover!, box: const Size.square(64), fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
          ),
        ),
      ),
    );
  }
}
