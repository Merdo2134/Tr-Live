import 'dart:async';
import 'package:flutter/material.dart';
import '../services/music_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/crown_icon.dart';
import '../widgets/room_card.dart';
import '../widgets/room_theme.dart';
import '../widgets/seat_picker.dart';
import '../services/api.dart';
import '../widgets/drag_bubble.dart';
import '../services/inbox_service.dart';
import '../services/room_dock.dart';
import 'discover_screen.dart';
import '../widgets/common.dart';
import '../widgets/gift_ribbon.dart';
import 'feed_screen.dart';
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

  @override
  void initState() {
    super.initState();
    Inbox.start();
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
    Inbox.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: _scaffold(context)),
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
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFFFF4081)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.graphic_eq, color: Colors.white, size: 22),
            Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
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
              child: IndexedStack(index: _index, children: [
                RoomsTab(key: _audioKey, type: 'audio', onJoinCode: _joinByCode),
                const FeedScreen(),
                RoomsTab(key: _videoKey, type: 'video', onJoinCode: _joinByCode),
                const MessagesScreen(),
                const ProfileScreen(),
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
  String _mode = 'popular'; // friends (İlgili: takip ettiklerin) | popular (Sıcak) | near (Yakında)
  bool _fresh = false; // Sıcak > "Yeni yayıncı" süzgeci (son 30 günde açılmış hesaplar)
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
      final region = _mode == 'popular' ? null : _mode;
      final r = await Api.get('/api/rooms', query: {
        'type': widget.type,
        if (_q.isNotEmpty) 'q': _q,
        if (region != null) 'region': region,
        if (_mode == 'popular' && _fresh) 'fresh': '1',
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

  /// Oda aç: kayıtlı odan varsa doğrudan girer. Yoksa bir kez kurulum penceresi açılır (ad, etiket, koltuk düzeni, tema).
  Future<void> createRoom({String? type}) async {
    final roomType = type ?? widget.type;
    final mine = await guard(context, () => Api.get('/api/rooms/mine'));
    if (mine == null || !mounted) return;
    final profile = mapOf(mapOf(mine['rooms'])?[roomType]);
    final body = <String, dynamic>{'roomType': roomType};
    if (profile == null) {
      final setup = await _setupDialog(roomType);
      if (setup == null || !mounted) return;
      body.addAll(setup);
    }
    final r = await guard(context, () => Api.post('/api/rooms', body));
    final room = mapOf(r?['room']);
    if (room != null && mounted) await _open(room['id'] as String, room['name'] as String);
  }

  Future<Map<String, dynamic>?> _setupDialog(String roomType) async {
    final nameCtl = TextEditingController();
    final tagsCtl = TextEditingController();
    var seats = roomType == 'video' ? 4 : 8;
    var theme = 'default';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(roomType == 'video' ? 'Görüntülü odanı kur' : 'Sesli odanı kur'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'Odanı bir kez kurarsın. Sonraki seferlerde "Oda aç"a basman yeterli: aynı ad ve etiketlerle doğrudan odana girersin. Ad ve etiketleri oda içinde oda adına dokunarak değiştirebilirsin.',
                style: TextStyle(color: Pal.textDim, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(controller: nameCtl, maxLength: 60, decoration: const InputDecoration(labelText: 'Oda adı')),
              TextField(controller: tagsCtl, decoration: const InputDecoration(labelText: 'Etiketler (en fazla 3, virgülle)', hintText: 'müzik, sohbet, karaoke')),
              const SizedBox(height: 12),
              SeatLayoutPicker(value: seats, onChanged: (v) => setS(() => seats = v)),
              const SizedBox(height: 12),
              ThemePicker(value: theme, onChanged: (v) => setS(() => theme = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                if (nameCtl.text.trim().length < 2) return toast(c, 'Oda adı en az 2 karakter olmalı.', error: true);
                Navigator.pop(c, true);
              },
              child: const Text('Kur ve aç'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtl.text.trim();
    final tags = tagsCtl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    nameCtl.dispose();
    tagsCtl.dispose();
    if (ok != true) return null;
    return {'name': name, 'seatCount': seats, 'theme': theme, if (tags.isNotEmpty) 'tags': tags};
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
      padding: EdgeInsets.fromLTRB(m, 0, m - 6, 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              _topTab('friends', 'İlgili'),
              _topTab('popular', 'Sıcak'),
              _topTab('near', 'Yakında'),
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
            SizedBox(
              width: 38,
              height: 38,
              child: PopupMenuButton<String>(
              tooltip: 'Diğer',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, color: Pal.text),
              onSelected: (v) {
                switch (v) {
                  case 'fav':
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverScreen()));
                  case 'code':
                    widget.onJoinCode?.call();
                  case 'user':
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchScreen()));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'fav', child: ListTile(leading: Icon(Icons.star), title: Text('Favoriler ve son girilenler'), dense: true)),
                PopupMenuItem(value: 'code', child: ListTile(leading: Icon(Icons.vpn_key), title: Text('Gizli odaya kodla gir'), dense: true)),
                PopupMenuItem(value: 'user', child: ListTile(leading: Icon(Icons.person_search), title: Text('Kullanıcı ara'), dense: true)),
              ],
            ),
            ),
          ]),
        ),
      ]),
    );
  }

  /// Süzgeç çipleri (Yoho "Tavsiyeler · Yeni yayıncı"): yalnızca Sıcak sekmesinde.
  Widget _filterChips(double w) {
    final m = homeMargin(w);
    final h = (w * 0.074).clamp(28.0, 36.0).toDouble();
    Widget chip(String label, Widget lead, bool sel, VoidCallback onTap) => Padding(
          padding: EdgeInsets.only(right: homeGap(w)),
          child: InkWell(
            borderRadius: BorderRadius.circular(h / 2),
            onTap: onTap,
            child: Container(
              height: h,
              padding: EdgeInsets.symmetric(horizontal: h * 0.5),
              decoration: BoxDecoration(
                color: sel ? Pal.green.withValues(alpha: 0.16) : Pal.surface,
                borderRadius: BorderRadius.circular(h / 2),
                border: Border.all(color: sel ? Pal.green.withValues(alpha: 0.5) : Pal.outline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                lead,
                SizedBox(width: h * 0.22),
                Text(label, style: TextStyle(fontSize: h * 0.46, fontWeight: FontWeight.w700, color: sel ? Pal.green : Pal.textDim)),
              ]),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(m, homeGap(w), m, homeGap(w)),
      child: Row(children: [
        chip('Tavsiyeler', Icon(Icons.star_rounded, size: h * 0.62, color: _fresh ? Pal.textDim : Pal.green), !_fresh, () {
          if (!_fresh) return;
          setState(() => _fresh = false);
          refresh();
        }),
        chip('Yeni yayıncı', Icon(Icons.mic_rounded, size: h * 0.58, color: _fresh ? Pal.green : Pal.textDim), _fresh, () {
          if (_fresh) return;
          setState(() => _fresh = true);
          refresh();
        }),
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
        : _mode == 'near'
            ? 'Şehrinde açık oda yok. Profilinden şehrini girdiysen burada aynı şehirdekiler görünür.'
            : _fresh
                ? 'Şu an yeni yayıncıların açık odası yok.'
                : (_q.isEmpty ? 'Şu an açık oda yok. İlk odayı sen aç!' : 'Aramanıza uyan oda yok.');
    final head = <Widget>[
      const BannerCarousel(),
      if (_mode == 'popular') _filterChips(w) else SizedBox(height: gap),
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
              suffixIcon: IconButton(
                tooltip: 'Kullanıcı ara',
                icon: const Icon(Icons.person_search),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchScreen())),
              ),
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
