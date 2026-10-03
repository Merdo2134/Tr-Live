import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/inbox_service.dart';
import '../services/session.dart';
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

  @override
  void dispose() {
    Inbox.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TR Live'),
        actions: [
          IconButton(
            tooltip: 'Liderlik tablosu',
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
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
        // Senior Developer Notu: "const [" ifadesi kaldırıldı.
        // İçerideki ValueListenableBuilder dinamik olduğu için listenin kendisi const olamaz.
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

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final r = await Api.get('/api/rooms', query: {'type': widget.type});
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

  Future<void> _open(String id, String name, {bool locked = false}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => RoomScreen(roomId: id, initialName: name, locked: locked)));
    if (mounted) refresh();
  }

  Future<void> createRoom() async {
    final nameCtl = TextEditingController();
    final tagsCtl = TextEditingController();
    final pwCtl = TextEditingController();
    var seats = 8;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(widget.type == 'video' ? 'Görüntülü oda aç' : 'Sesli oda aç'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtl, maxLength: 60, decoration: const InputDecoration(labelText: 'Oda adı')),
            TextField(controller: tagsCtl, decoration: const InputDecoration(labelText: 'Etiketler (en fazla 3, virgülle)', hintText: 'müzik, sohbet, karaoke')),
            TextField(controller: pwCtl, obscureText: true, maxLength: 12, decoration: const InputDecoration(labelText: 'Oda şifresi (isteğe bağlı, 4-12)')),
            const SizedBox(height: 8),
            Row(children: [
              const Text('Koltuk sayısı'),
              const Spacer(),
              DropdownButton<int>(
                value: seats,
                items: [for (final n in const) DropdownMenuItem(value: n, child: Text('$n koltuk'))],
                onChanged: (v) => setS(() => seats = v ?? 8),
              ),
            ]),
          ]),
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
        }));
    final room = mapOf(r?['room']);
    if (room != null && mounted) await _open(room['id'] as String, room['name'] as String);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rooms.isEmpty) return LoadError(message: _error!, onRetry: refresh);
    return RefreshIndicator(
      onRefresh: refresh,
      child: _rooms.isEmpty
          ? ListView(children: const [SizedBox(height: 160), Center(child: Text('Şu an açık oda yok. İlk odayı sen aç!'))])
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
  }
}
