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

  static const _titles = ['Ana Sayfa', 'Görüntülü', 'Mesajlar', 'Aile', 'Profil'];

  Widget _circleBtn({required IconData icon, required Color bg, required VoidCallback onTap, required String tip, required double size, Color fg = Colors.white, int badge = 0}) {
    return Tooltip(
      message: tip,
      child: InkResponse(
        onTap: onTap,
        radius: size * 0.7,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle, boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.45), blurRadius: 10)]),
            child: Icon(icon, color: fg, size: size * 0.5),
          ),
          if (badge > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(color: Pal.red, borderRadius: BorderRadius.circular(10)),
                child: Text(badge > 99 ? '99+' : '$badge', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final size = w < 360 ? 36.0 : (w < 420 ? 40.0 : 46.0);
    final home = _index <= 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(_titles[_index], style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Pal.text))),
          ),
        ),
        if (home) ...[
          _circleBtn(icon: Icons.group, bg: Pal.pink, size: size, tip: 'Favoriler ve son girilenler', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverScreen()))),
          SizedBox(width: size * 0.18),
          _circleBtn(icon: Icons.emoji_events, bg: Colors.transparent, fg: Pal.amber, size: size, tip: 'Liderlik tablosu', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen()))),
          SizedBox(width: size * 0.18),
          _circleBtn(
            icon: Icons.mic,
            bg: Pal.cyan,
            fg: const Color(0xFF00212A),
            size: size,
            tip: 'Oda aç',
            onTap: () async {
              final tab = _index == 0 ? _audioKey.currentState : _videoKey.currentState;
              await tab?.createRoom();
            },
          ),
          SizedBox(width: size * 0.18),
          ValueListenableBuilder<int>(
            valueListenable: Inbox.unread,
            builder: (_, n, __) => _circleBtn(icon: Icons.notifications, bg: Pal.amber, fg: const Color(0xFF2A1D00), size: size, tip: 'Bildirimler ve mesajlar', badge: n, onTap: () => setState(() => _index = 2)),
          ),
          SizedBox(width: size * 0.12),
          IconButton(
            tooltip: 'Oda ara',
            iconSize: size * 0.62,
            color: Pal.text,
            icon: const Icon(Icons.search),
            onPressed: () => (_index == 0 ? _audioKey.currentState : _videoKey.currentState)?.toggleSearch(),
          ),
        ] else
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: Session.me,
            builder: (_, me, __) => Chip(
              avatar: const Icon(Icons.monetization_on, size: 18, color: Pal.amber),
              label: Text(fmtNumber(me?['coins'])),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ]),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _header(context),
          Expanded(
            child: GiftRibbonOverlay(
              child: IndexedStack(index: _index, children: [
                RoomsTab(key: _audioKey, type: 'audio', onJoinCode: _joinByCode),
                RoomsTab(key: _videoKey, type: 'video', onJoinCode: _joinByCode),
                const MessagesScreen(),
                const FamilyScreen(),
                const ProfileScreen(),
              ]),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          if (i == 0) _audioKey.currentState?.refresh();
          if (i == 1) _videoKey.currentState?.refresh();
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic), label: 'Sesli'),
          const NavigationDestination(icon: Icon(Icons.videocam_outlined), selectedIcon: Icon(Icons.videocam), label: 'Görüntülü'),
          NavigationDestination(
            icon: ValueListenableBuilder<int>(
              valueListenable: Inbox.unread,
              builder: (_, n, __) => Badge(label: Text('$n'), isLabelVisible: n > 0, child: const Icon(Icons.chat_bubble_outline)),
            ),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: 'Mesaj',
          ),
          const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Aile'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
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
  final String type;
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
  bool _friends = false; // Trend / Arkadaşlar
  String _region = 'all'; // all | tr | other
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
      final region = _friends ? 'friends' : (_region == 'all' ? null : _region);
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

  Future<void> createRoom() async {
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
          title: Text(widget.type == 'video' ? 'Görüntülü oda aç' : 'Sesli oda aç'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          'roomType': widget.type,
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

  Widget _modeButton(String label, IconData icon, bool selected, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: selected ? Pal.surfaceHi : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? Pal.cyan : Pal.outline, width: 1.4)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: selected ? Pal.cyan : Pal.textDim),
              const SizedBox(width: 8),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: selected ? Pal.cyan : Pal.textDim))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _regionChip(String id, String label, {IconData? icon, Color color = Pal.cyan}) {
    final sel = _region == id;
    return ChoiceChip(
      showCheckmark: false,
      selected: sel,
      avatar: icon == null ? null : Icon(icon, size: 18, color: sel ? color : Pal.textDim),
      label: Text(label, style: TextStyle(color: sel ? color : Pal.textDim, fontWeight: FontWeight.w600)),
      selectedColor: Pal.surfaceHi,
      backgroundColor: Pal.surface,
      side: BorderSide(color: sel ? color : Pal.outline, width: 1.3),
      onSelected: (_) {
        setState(() => _region = id);
        refresh();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rooms.isEmpty) return LoadError(message: _error!, onRetry: refresh);
    final cols = Resp.roomColumns(MediaQuery.sizeOf(context).width);
    final empty = _friends
        ? 'Takip ettiğin kişilerin açık odası yok.'
        : (_q.isEmpty ? 'Şu an açık oda yok. İlk odayı sen aç!' : 'Aramanıza uyan oda yok.');
    final list = RefreshIndicator(
      onRefresh: refresh,
      child: _rooms.isEmpty
          ? ListView(children: [const SizedBox(height: 100), Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(color: Pal.textDim))))])
          : GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.05),
              itemCount: _rooms.length,
              itemBuilder: (_, i) {
                final r = _rooms[i];
                return RoomCard(room: r, onTap: () => _open(r['id'] as String, (r['name'] ?? '').toString(), locked: r['locked'] == true));
              },
            ),
    );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(children: [
          _modeButton('Trend', Icons.local_fire_department, !_friends, () {
            setState(() => _friends = false);
            refresh();
          }),
          const SizedBox(width: 12),
          _modeButton('Arkadaşlar', Icons.group, _friends, () {
            setState(() => _friends = true);
            refresh();
          }),
        ]),
      ),
      if (!_friends)
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _regionChip('all', 'Global'),
              const SizedBox(width: 8),
              _regionChip('tr', 'Türkiye', icon: Icons.flag),
              const SizedBox(width: 8),
              _regionChip('other', 'Diğer', icon: Icons.public, color: Pal.purple),
              const SizedBox(width: 8),
              ActionChip(
                avatar: const Icon(Icons.vpn_key, size: 18, color: Pal.amber),
                label: const Text('Kodla gir', style: TextStyle(color: Pal.amber, fontWeight: FontWeight.w600)),
                backgroundColor: Pal.surface,
                side: const BorderSide(color: Pal.outline, width: 1.3),
                onPressed: widget.onJoinCode,
              ),
            ],
          ),
        ),
      if (_searching)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
      const SizedBox(height: 4),
      Expanded(child: list),
    ]);
  }
}
