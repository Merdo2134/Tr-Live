import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/app_theme.dart';
import '../widgets/room_card.dart';
import '../widgets/room_theme.dart';
import '../services/api.dart';
import '../services/inbox_service.dart';
import '../services/session.dart';
import '../services/room_dock.dart';
import 'discover_screen.dart';
import '../widgets/common.dart';
import '../widgets/gift_ribbon.dart';
import 'family_screen.dart';
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
  final _roomsKey = GlobalKey<RoomsTabState>();

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

  Widget _scaffold(BuildContext context) {
    final showTitle = _index == 3 || _index == 4;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (showTitle)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: Row(children: [
                Expanded(child: Text(_index == 3 ? 'Mesajlar' : 'Profil', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Pal.text))),
                ValueListenableBuilder<Map<String, dynamic>?>(
                  valueListenable: Session.me,
                  builder: (_, me, __) => Chip(
                    avatar: const Icon(Icons.monetization_on, size: 18, color: Pal.amber),
                    label: Text(fmtNumber(me?['coins'])),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ]),
            ),
          Expanded(
            child: GiftRibbonOverlay(
              child: IndexedStack(index: _index, children: [
                RoomsTab(key: _roomsKey),
                const DiscoverScreen(embedded: true),
                HubScreen(onCreate: _startBroadcast, onJoinCode: _joinByCode),
                const MessagesScreen(),
                const ProfileScreen(),
              ]),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        height: 64,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          if (i == 0) _roomsKey.currentState?.refresh();
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic), label: 'Party'),
          const NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Keşfet'),
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Giriş Sayfası'),
          NavigationDestination(
            icon: ValueListenableBuilder<int>(
              valueListenable: Inbox.unread,
              builder: (_, n, __) => Badge(label: Text('$n'), isLabelVisible: n > 0, child: const Icon(Icons.chat_bubble_outline)),
            ),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: 'Mesajlar',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }

  /// Yayın başlat: odayı RoomsTab açar; sekme henüz yüklenmediyse önce Party'ye geçilir.
  Future<void> _startBroadcast(String type) async {
    setState(() => _index = 0);
    await WidgetsBinding.instance.endOfFrame;
    await _roomsKey.currentState?.createRoom(type: type);
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
  const RoomsTab({super.key});

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
      final r = await Api.get('/api/rooms', query: {if (_q.isNotEmpty) 'q': _q, if (region != null) 'region': region});
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

  Future<void> createRoom({String type = 'audio'}) async {
    var roomType = type;
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
            Row(children: [
              const Text('Koltuk sayısı'),
              const Spacer(),
              DropdownButton<int>(
                value: seats,
                items: [for (final n in const [2, 5, 8, 9, 12, 15, 20]) DropdownMenuItem(value: n, child: Text('$n koltuk'))],
                onChanged: (v) => setS(() => seats = v ?? 8),
              ),
            ]),
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
      padding: EdgeInsets.fromLTRB(small ? 8 : 12, 8, small ? 4 : 8, 6),
      child: Row(children: [
        IconButton(
          tooltip: 'Liderlik tablosu',
          icon: const Icon(Icons.workspace_premium, color: Pal.amber),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
        ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [_topTab('friends', 'Takip'), _topTab('popular', 'Popüler'), _topTab('near', 'Yakında')]),
          ),
        ),
        IconButton(
          tooltip: 'Yayın başlat',
          style: IconButton.styleFrom(backgroundColor: Pal.cyan, foregroundColor: const Color(0xFF00212A)),
          icon: const Icon(Icons.mic, size: 20),
          onPressed: () => createRoom(),
        ),
        IconButton(tooltip: 'Oda ara', icon: Icon(_searching ? Icons.close : Icons.search, color: Pal.cyan), onPressed: toggleSearch),
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
            ? ListView(children: [const SizedBox(height: 100), Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(color: Pal.textDim))))])
            : GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 96),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.78),
                itemCount: _rooms.length,
                itemBuilder: (_, i) {
                  final r = _rooms[i];
                  return RoomCard(room: r, onTap: () => _open(r['id'] as String, (r['name'] ?? '').toString(), locked: r['locked'] == true));
                },
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

/// "Giriş Sayfası": yayın başlatma ve ana kısayollar.
class HubScreen extends StatelessWidget {
  final Future<void> Function(String type) onCreate;
  final VoidCallback onJoinCode;
  const HubScreen({super.key, required this.onCreate, required this.onJoinCode});

  Widget _big(String label, IconData icon, List<Color> colors, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(22)),
          child: Column(children: [
            Icon(icon, size: 38, color: Colors.white),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Pal.outline)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 30, color: color),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.text, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  Widget _page(BuildContext context, String title, Widget body) => Scaffold(appBar: AppBar(title: Text(title)), body: body);

  @override
  Widget build(BuildContext context) {
    final cols = MediaQuery.sizeOf(context).width < 600 ? 3 : 5;
    final tiles = <Widget>[
      _tile(context, 'Aile', Icons.groups, Pal.cyan, () => Navigator.push(context, MaterialPageRoute(builder: (_) => _page(context, 'Aile', const FamilyScreen())))),
      _tile(context, 'Liderlik', Icons.emoji_events, Pal.amber, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen()))),
      _tile(context, 'Favoriler', Icons.star, Pal.pink, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverScreen()))),
      _tile(context, 'Kodla gir', Icons.vpn_key, Pal.amber, onJoinCode),
      _tile(context, 'Kullanıcı ara', Icons.person_search, Pal.cyan, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchScreen()))),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
      const Text('Giriş Sayfası', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Pal.text)),
      const SizedBox(height: 16),
      Row(children: [
        _big('Sesli yayın', Icons.mic, const [Color(0xFFFF7A18), Color(0xFFFF4F9A)], () => onCreate('audio')),
        const SizedBox(width: 12),
        _big('Canlı yayın', Icons.videocam, const [Pal.purple, Pal.cyan], () => onCreate('video')),
      ]),
      const SizedBox(height: 20),
      GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1, children: tiles),
    ]);
  }
}
