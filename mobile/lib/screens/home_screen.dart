import 'dart:async';
import 'package:flutter/material.dart';
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

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TR Live'),
        actions: [
          IconButton(
            tooltip: 'Favoriler ve son girilenler',
            icon: const Icon(Icons.star_border),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverScreen())),
          ),
          IconButton(
            tooltip: 'Liderlik tablosu',
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
          ),
          IconButton(
            tooltip: 'Gizli odaya kodla gir',
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: _joinByCode,
          ),
          IconButton(
            tooltip: 'Kullanıcı ara',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchScreen())),
          ),
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: Session.me,
            builder: (_, me, __) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: const Icon(Icons.monetization_on, size: 18, color: Colors.amber),
                label: Text(fmtNumber(me?['coins'])),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: GiftRibbonOverlay(
        child: IndexedStack(index: _index, children: [
          RoomsTab(key: _audioKey, type: 'audio'),
          RoomsTab(key: _videoKey, type: 'video'),
          const MessagesScreen(),
          const FamilyScreen(),
          const ProfileScreen(),
        ]),
      ),
      floatingActionButton: _index <= 1
          ? FloatingActionButton.extended(
              onPressed: () async {
                final tab = _index == 0 ? _audioKey.currentState : _videoKey.currentState;
                await tab?.createRoom();
              },
              icon: const Icon(Icons.add),
              label: const Text('Oda aç'),
            )
          : null,
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
  const RoomsTab({super.key, required this.type});

  @override
  State<RoomsTab> createState() => RoomsTabState();
}

class RoomsTabState extends State<RoomsTab> {
  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;
  String? _error;
  String _q = '';
  Timer? _debounce;

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
      final r = await Api.get('/api/rooms', query: {'type': widget.type, if (_q.isNotEmpty) 'q': _q});
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rooms.isEmpty) return LoadError(message: _error!, onRetry: refresh);
    final list = RefreshIndicator(
      onRefresh: refresh,
      child: _rooms.isEmpty
          ? ListView(children: [const SizedBox(height: 120), Center(child: Text(_q.isEmpty ? 'Şu an açık oda yok. İlk odayı sen aç!' : 'Aramanıza uyan oda yok.'))])
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: _rooms.length,
              itemBuilder: (_, i) {
                final r = _rooms[i];
                final owner = mapOf(r['owner']);
                return ListTile(
                  leading: CircleAvatar(child: Icon(widget.type == 'video' ? Icons.videocam : Icons.mic)),
                  title: Text((r['name'] ?? '').toString()),
                  subtitle: Text(
                    '${owner?['displayName'] ?? ''} · ${r['memberCount']} kişi · ${r['micCount']}/${r['seatCount']} mikrofon'
                    '${(r['tags'] is List && (r['tags'] as List).isNotEmpty) ? '\n#${(r['tags'] as List).join('  #')}' : ''}',
                  ),
                  isThreeLine: r['tags'] is List && (r['tags'] as List).isNotEmpty,
                  trailing: r['locked'] == true ? const Icon(Icons.lock_outline) : const Icon(Icons.chevron_right),
                  onTap: () => _open(r['id'] as String, (r['name'] ?? '').toString(), locked: r['locked'] == true),
                );
              },
            ),
    );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Oda, yayıncı veya etiket ara', isDense: true, border: OutlineInputBorder()),
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), () {
              _q = v.trim();
              refresh();
            });
          },
        ),
      ),
      Expanded(child: list),
    ]);
  }
}
