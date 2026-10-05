import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/inbox_service.dart';
import '../services/session.dart';
import '../services/socket_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/safety_actions.dart';
import 'user_screens.dart';

String _time(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  final today = d.year == now.year && d.month == now.month && d.day == now.day;
  return today ? '${two(d.hour)}:${two(d.minute)}' : '${two(d.day)}.${two(d.month)}';
}

/// Sohbetler sekmesi.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  int _version = 0;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = SocketService.instance.events.listen((e) {
      if (e['type'] == 'dm' && mounted) setState(() => _version++);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _newChat() async {
    final u = await pickUser(context);
    if (u == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: u)));
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _newChat, tooltip: 'Yeni mesaj', child: const Icon(Icons.edit)),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_version),
        load: () async => listOf((await Api.get('/api/messages/conversations'))['conversations']),
        builder: (context, list, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(children: [
            const _InboxCards(),
            if (list.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('Henüz mesajınız yok. Sağ alttaki düğmeyle yeni bir sohbet başlatın.', textAlign: TextAlign.center, style: TextStyle(color: Pal.textDim))),
            for (final c in list)
                    ListTile(
                      leading: UserAvatar(user: mapOf(c['peer'])),
                      title: UserName(user: mapOf(c['peer']), style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${c['lastFromMe'] == true ? 'Sen: ' : ''}${c['lastMessage']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(_time(c['lastMessageAt']), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                        if ((c['unread'] as num? ?? 0) > 0) Badge(label: Text('${c['unread']}')),
                      ]),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: mapOf(c['peer'])!)));
                        Inbox.refresh();
                        if (mounted) setState(() => _version++);
                      },
                    ),
          ]),
        ),
      ),
    );
  }
}

/// Mesajlar ekranının üstündeki dört kategori kartı.
class _InboxCards extends StatefulWidget {
  const _InboxCards();

  @override
  State<_InboxCards> createState() => _InboxCardsState();
}

class _InboxCardsState extends State<_InboxCards> {
  Map<String, dynamic> _sum = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/api/inbox-summary');
      if (mounted) setState(() => _sum = r);
    } catch (_) {
      // Rozetler olmasa da kartlar çalışır.
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    try {
      await Api.post('/api/inbox-summary/seen');
    } catch (_) {}
    _load();
  }

  Widget _card(String label, IconData icon, List<Color> colors, int badge, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            height: 92,
            decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(6),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 30, color: Colors.white),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5)),
            ]),
          ),
          if (badge > 0)
            Positioned(
              right: -4,
              top: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(color: Pal.red, shape: BoxShape.circle),
                child: Text('${badge > 99 ? '99+' : badge}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      ),
    );
  }

  int _n(String k) => (_sum[k] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final me = Session.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(children: [
        _card('Arkadaşlık isteği', Icons.group_add, const [Color(0xFF7A5CFF), Color(0xFFB45CFF)], _n('followers'), () => _open(UserListScreen(title: 'Yeni takipçiler', path: '/api/users/$me/followers'))),
        const SizedBox(width: 8),
        _card('Ekip', Icons.workspace_premium, const [Color(0xFFFFB347), Color(0xFFFF7A18)], _n('team'), () => _open(const AnnouncementsScreen(kind: 'team', title: 'Ekip'))),
        const SizedBox(width: 8),
        _card('Etkinlik duyurusu', Icons.campaign, const [Color(0xFF1FD6F5), Color(0xFF2FE6A8)], _n('event'), () => _open(const AnnouncementsScreen(kind: 'event', title: 'Etkinlik duyurusu'))),
        const SizedBox(width: 8),
        _card('Ödül bildirimleri', Icons.card_giftcard, const [Color(0xFFFF4F9A), Color(0xFF8E5CFF)], _n('reward'), () => _open(const AnnouncementsScreen(kind: 'reward', title: 'Ödül bildirimleri'))),
      ]),
    );
  }
}

class AnnouncementsScreen extends StatelessWidget {
  final String kind;
  final String title;
  const AnnouncementsScreen({super.key, required this.kind, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncBody<List<Map<String, dynamic>>>(
        load: () async => listOf((await Api.get('/api/announcements', query: {'kind': kind}))['announcements']),
        builder: (context, items, reload) => items.isEmpty
            ? const Center(child: Text('Henüz duyuru yok.', style: TextStyle(color: Pal.textDim)))
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView(padding: const EdgeInsets.all(12), children: [
                  for (final a in items)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 6),
                          Text('${a['text']}', style: const TextStyle(height: 1.35)),
                          const SizedBox(height: 8),
                          Text(_time(a['createdAt']), style: const TextStyle(color: Pal.textDim, fontSize: 12)),
                        ]),
                      ),
                    ),
                ]),
              ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> peer;
  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  StreamSubscription? _sub;

  String get _peerId => widget.peer['id'].toString();

  @override
  void initState() {
    super.initState();
    _load();
    _sub = SocketService.instance.events.listen((e) {
      if (e['type'] != 'dm') return;
      final m = mapOf(e['message']);
      if (m == null || m['senderId'] != _peerId) return;
      if (!mounted) return;
      setState(() => _messages.add(m));
      _toEnd();
      Api.get('/api/messages/with/$_peerId').then((_) => Inbox.refresh()).catchError((_) => <String, dynamic>{}); // okundu işaretle
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/api/messages/with/$_peerId');
      if (!mounted) return;
      setState(() {
        _messages = listOf(r['messages']);
        _loading = false;
        _error = null;
      });
      _toEnd();
      Inbox.refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final r = await guard(context, () => Api.post('/api/messages/with/$_peerId', {'text': text}));
    if (!mounted) return;
    setState(() => _sending = false);
    final m = mapOf(r?['message']);
    if (m != null) {
      setState(() => _messages.add(m));
      _ctl.clear();
      _toEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: _peerId))),
          child: Row(children: [UserAvatar(user: peer, radius: 16), const SizedBox(width: 8), Flexible(child: UserName(user: peer))]),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (a) async {
              if (a == 'block') {
                if (await blockUserDialog(context, _peerId, (peer['displayName'] ?? 'Kullanıcı').toString()) && mounted) Navigator.pop(context);
              }
              if (a == 'report' && _messages.isNotEmpty) {
                final last = _messages.lastWhere((m) => m['senderId'] == _peerId, orElse: () => _messages.last);
                if (mounted) reportDialog(context, kind: 'dm', targetUserId: _peerId, messageId: last['id'] as String?);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Şikâyet et')),
              PopupMenuItem(value: 'block', child: Text('Engelle')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? LoadError(message: _error!, onRetry: _load)
                  : _messages.isEmpty
                      ? const Center(child: Text('Sohbeti başlatmak için bir mesaj yazın.'))
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) {
                            final m = _messages[i];
                            final mine = m['senderId'] == Session.id;
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                decoration: BoxDecoration(color: mine ? Colors.pinkAccent.shade400 : Colors.white12, borderRadius: BorderRadius.circular(16)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text((m['text'] ?? '').toString()),
                                  Text(_time(m['createdAt']), style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                ]),
                              ),
                            );
                          },
                        ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: const InputDecoration(isDense: true, counterText: '', hintText: 'Mesaj yaz...', border: OutlineInputBorder()),
                ),
              ),
              IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
