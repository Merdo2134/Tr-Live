import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/app_theme.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/crown_icon.dart';
import '../widgets/room_card.dart';
import '../widgets/room_theme.dart';
import '../widgets/seat_picker.dart';
import '../services/api.dart';
import '../services/inbox_service.dart';
import '../services/room_dock.dart';
import 'discover_screen.dart';
import '../widgets/common.dart';
import '../widgets/gift_ribbon.dart';
import 'family_screen.dart';
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
  String _side = 'audio'; // son açık oda tarafı: sesli | görüntülü

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

  Widget _miniBar(RoomRequest req) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 88,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.primaryContainer,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.graphic_eq),
          title: Text(req.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: const Text('Oda açık · dokunarak büyüt'),
          onTap: RoomDock.expand,
          trailing: IconButton(tooltip: 'Odadan ayrıl', icon: const Icon(Icons.close), onPressed: () => RoomDock.exitHandler?.call()),
        ),
      ),
    );
  }

  void _select(int i) {
    setState(() {
      _index = i;
      if (i == 0) _side = 'audio';
      if (i == 2) _side = 'video';
    });
    if (i == 0) _audioKey.currentState?.refresh();
    if (i == 2) _videoKey.currentState?.refresh();
  }

  Future<void> _createRoom() async {
    final tab = _side == 'video' ? _videoKey.currentState : _audioKey.currentState;
    await tab?.createRoom(type: _side);
  }

  /// Üst satır: Sesli | Akış | Görüntülü | Mesajlar | Profil
  Widget _topRow() {
    Widget item(int i, IconData icon, IconData activeIcon, String label, {Widget? badge}) {
      final sel = _index == i;
      final color = sel ? Pal.cyan : Pal.textDim;
      return Expanded(
        child: Semantics(
          button: true,
          selected: sel,
          label: label,
          child: InkWell(
            onTap: () => _select(i),
            child: Container(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: sel ? Pal.cyan : Colors.transparent, width: 3))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                badge ?? Icon(sel ? activeIcon : icon, color: color, size: 26),
                const SizedBox(height: 2),
                FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: sel ? FontWeight.w800 : FontWeight.w500))),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(color: Pal.surface, border: Border(bottom: BorderSide(color: Pal.outline, width: 0.8))),
      child: Row(children: [
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
            builder: (_, n, __) => Badge(label: Text('$n'), isLabelVisible: n > 0, child: Icon(_index == 3 ? Icons.chat_bubble : Icons.chat_bubble_outline, color: _index == 3 ? Pal.cyan : Pal.textDim, size: 26)),
          ),
        ),
        item(4, Icons.person_outline, Icons.person, 'Profil'),
      ]),
    );
  }

  /// Alt satır: TRLive tacı (sıralamalar) ve oda açma düğmesi.
  Widget _bottomRow() {
    final video = _side == 'video';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(color: Pal.surface, border: Border(top: BorderSide(color: Pal.outline, width: 0.8))),
        child: Row(children: [
          Semantics(
            button: true,
            label: 'TRLive sıralamaları',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const CrownIcon(size: 34),
                  const SizedBox(width: 6),
                  Text('TRLive', style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w800, fontSize: MediaQuery.sizeOf(context).width < 360 ? 17 : 20, letterSpacing: 1, color: Pal.text)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: _createRoom,
              child: Ink(
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: video ? const [Pal.purple, Pal.cyan] : const [Color(0xFFFF7A18), Pal.pink]),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [BoxShadow(color: (video ? Pal.purple : Pal.pink).withValues(alpha: 0.35), blurRadius: 12)],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(video ? Icons.videocam : Icons.mic, color: Colors.white),
                  const SizedBox(width: 8),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(video ? 'Görüntülü yayın aç' : 'Sesli oda aç', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)))),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _topRow(),
          Expanded(
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
        ]),
      ),
      bottomNavigationBar: _bottomRow(),
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
  String _mode = 'popular'; // friends (Takip) | popular (Popüler) | near (Yakında)
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
      final r = await Api.get('/api/rooms', query: {'type': widget.type, if (_q.isNotEmpty) 'q': _q, if (region != null) 'region': region});
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

  Future<void> createRoom({String? type}) async {
    var roomType = type ?? widget.type;
    final nameCtl = TextEditingController();
    final tagsCtl = TextEditingController();
    final pwCtl = TextEditingController();
    var seats = 8;
    var hidden = false;
    var theme = 'default';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('Yayın başlat'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'audio', icon: Icon(Icons.mic), label: Text('Sesli')),
                ButtonSegment(value: 'video', icon: Icon(Icons.videocam), label: Text('Görüntülü')),
              ],
              selected: {roomType},
              onSelectionChanged: (v) => setS(() => roomType = v.first),
            ),
            const SizedBox(height: 8),
            TextField(controller: nameCtl, maxLength: 60, decoration: const InputDecoration(labelText: 'Oda adı')),
            TextField(controller: tagsCtl, decoration: const InputDecoration(labelText: 'Etiketler (en fazla 3, virgülle)', hintText: 'müzik, sohbet, karaoke')),
            TextField(controller: pwCtl, obscureText: true, maxLength: 12, decoration: const InputDecoration(labelText: 'Oda şifresi (isteğe bağlı, 4-12)')),
            SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Gizli oda (kodla girilir)'), value: hidden, onChanged: (v) => setS(() => hidden = v)),
            const SizedBox(height: 4),
            ThemePicker(value: theme, onChanged: (v) => setS(() => theme = v)),
            const SizedBox(height: 8),
            SeatLayoutPicker(value: seats, onChanged: (v) => setS(() => seats = v)),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aç')),
          ],
        ),
      ),
    );
    final name = nameCtl.text.trim();
    final tags = tagsCtl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final pw = pwCtl.text.trim();
    nameCtl.dispose();
    tagsCtl.dispose();
    pwCtl.dispose();
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.post('/api/rooms', {
          'name': name.isEmpty ? 'TR Live Odası' : name,
          'roomType': roomType,
          'seatCount': seats,
          if (tags.isNotEmpty) 'tags': tags,
          if (pw.isNotEmpty) 'password': pw,
          'hidden': hidden,
          'theme': theme,
        }));
    final room = mapOf(r?['room']);
    if (room != null && mounted) {
      if (room['joinCode'] != null) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Gizli oda hazır'),
            content: Text('Davet kodu: ${room['joinCode']}\nBu kodu yalnızca girmesini istediklerinize verin. Kodu oda ayarlarından da görebilirsiniz.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
          ),
        );
      }
      if (mounted) await _open(room['id'] as String, room['name'] as String);
    }
  }

  Widget _topTab(String id, String label) {
    final sel = _mode == id;
    return GestureDetector(
      onTap: () {
        setState(() => _mode = id);
        refresh();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: sel ? Pal.cyan : Colors.transparent, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 16, fontWeight: sel ? FontWeight.w800 : FontWeight.w600, color: sel ? const Color(0xFF00212A) : Pal.text)),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final small = w < 360;
    return Padding(
      padding: EdgeInsets.fromLTRB(small ? 8 : 12, 6, small ? 0 : 4, 4),
      child: Row(children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [_topTab('friends', 'Takip'), _topTab('popular', 'Popüler'), _topTab('near', 'Yakında')]),
          ),
        ),
        IconButton(tooltip: 'Oda ara', icon: Icon(_searching ? Icons.close : Icons.search, color: Pal.cyan), onPressed: toggleSearch),
        PopupMenuButton<String>(
          tooltip: 'Diğer',
          icon: const Icon(Icons.more_vert, color: Pal.text),
          onSelected: (v) {
            switch (v) {
              case 'family':
                Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Aile')), body: const FamilyScreen())));
              case 'fav':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverScreen()));
              case 'code':
                widget.onJoinCode?.call();
              case 'user':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchScreen()));
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'family', child: ListTile(leading: Icon(Icons.groups), title: Text('Aile'), dense: true)),
            PopupMenuItem(value: 'fav', child: ListTile(leading: Icon(Icons.star), title: Text('Favoriler ve son girilenler'), dense: true)),
            PopupMenuItem(value: 'code', child: ListTile(leading: Icon(Icons.vpn_key), title: Text('Gizli odaya kodla gir'), dense: true)),
            PopupMenuItem(value: 'user', child: ListTile(leading: Icon(Icons.person_search), title: Text('Kullanıcı ara'), dense: true)),
          ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cols = Resp.roomColumns(MediaQuery.sizeOf(context).width);
    final empty = _mode == 'friends'
        ? 'Takip ettiğin kişilerin açık odası yok.'
        : _mode == 'near'
            ? 'Şehrinde açık oda yok. Profilinden şehrini girdiysen burada aynı şehirdekiler görünür.'
            : (_q.isEmpty ? 'Şu an açık oda yok. İlk odayı sen aç!' : 'Aramanıza uyan oda yok.');
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _rooms.isEmpty) {
      body = LoadError(message: _error!, onRetry: refresh);
    } else {
      body = RefreshIndicator(
        onRefresh: refresh,
        child: _rooms.isEmpty
            ? ListView(children: [const BannerCarousel(), const SizedBox(height: 60), Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(color: Pal.textDim))))])
            : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: BannerCarousel()),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 96),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.78),
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
      _topBar(context),
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
