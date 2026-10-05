import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/room_dock.dart';
import '../widgets/common.dart';

/// Favori yayıncılar ve son girilen odalar. Yayıncı açıksa tek dokunuşla odasına girilir.
class DiscoverScreen extends StatefulWidget {
  /// Alt menüde sekme olarak kullanılırken true: oda açılınca sayfa kapatılmaz.
  final bool embedded;
  const DiscoverScreen({super.key, this.embedded = false});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<Map<String, dynamic>> _favs = [];
  List<Map<String, dynamic>> _recent = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await Api.get('/api/rooms/favorites');
      final r = await Api.get('/api/rooms/recent');
      if (!mounted) return;
      setState(() {
        _favs = listOf(f['hosts']);
        _recent = listOf(r['recent']);
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

  void _open(Map<String, dynamic>? room) {
    if (room == null) return;
    if (!widget.embedded) Navigator.pop(context);
    RoomDock.open(RoomRequest(roomId: room['id'].toString(), name: (room['name'] ?? 'Oda').toString(), locked: room['locked'] == true));
  }

  Future<void> _unfav(Map<String, dynamic> h) async {
    final id = mapOf(h['user'])?['id'];
    final r = await guard(context, () => Api.delete('/api/rooms/hosts/$id/favorite'));
    if (r != null) _load();
  }

  Widget _tile(Map<String, dynamic> x, {required bool fav}) {
    final user = mapOf(x['user']);
    final room = mapOf(x['room']);
    final live = room != null;
    return ListTile(
      leading: UserAvatar(user: user),
      title: UserName(user: user),
      subtitle: Text(live ? '🔴 ${room['name']} · ${room['memberCount']} kişi' : (fav ? 'Şu an yayında değil' : 'Son oda: ${x['roomName'] ?? ''} · kapalı')),
      trailing: fav
          ? IconButton(tooltip: 'Favorilerden çıkar', icon: const Icon(Icons.star, color: Colors.amber), onPressed: () => _unfav(x))
          : (live ? const Icon(Icons.chevron_right) : null),
      onTap: live ? () => _open(room) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Keşfet'), automaticallyImplyLeading: !widget.embedded, bottom: const TabBar(tabs: [Tab(text: 'Favoriler'), Tab(text: 'Son girilenler')])),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? LoadError(message: _error!, onRetry: _load)
                : TabBarView(children: [
                    RefreshIndicator(
                      onRefresh: _load,
                      child: _favs.isEmpty
                          ? ListView(children: const [SizedBox(height: 120), Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Henüz favori yok. Bir odadayken ★ simgesine dokunarak yayıncıyı favorilere ekleyin.', textAlign: TextAlign.center)))])
                          : ListView(children: [for (final h in _favs) _tile(h, fav: true)]),
                    ),
                    RefreshIndicator(
                      onRefresh: _load,
                      child: _recent.isEmpty
                          ? ListView(children: const [SizedBox(height: 120), Center(child: Text('Henüz bir odaya girmediniz.'))])
                          : ListView(children: [for (final h in _recent) _tile(h, fav: false)]),
                    ),
                  ]),
      ),
    );
  }
}
