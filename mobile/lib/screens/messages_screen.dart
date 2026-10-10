import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/inbox_service.dart';
import '../services/presence_service.dart';
import '../services/session.dart';
import '../services/socket_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/presence_widgets.dart';
import '../widgets/safety_actions.dart';
import 'family_screen.dart';
import 'social_screens.dart';
import 'support_screens.dart';
import 'user_screens.dart';

const _shortMonths = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

/// Bugün: 14:30 · bu yıl: 1 Eki · önceki yıllar: 1 Eki 2025
String _time(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  final today = d.year == now.year && d.month == now.month && d.day == now.day;
  if (today) return '${two(d.hour)}:${two(d.minute)}';
  return d.year == now.year ? '${d.day} ${_shortMonths[d.month - 1]}' : '${d.day} ${_shortMonths[d.month - 1]} ${d.year}';
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
  Future<void> Function()? _reload; // listeyi yerinde yeniler (kaydırma konumu korunur, yükleniyor halkası çıkmaz)
  bool _special = false; // "Özel Takip": yalnızca takip ettiğim kişilerle olan sohbetler
  Set<String> _following = {};
  Timer? _debounce;
  final Set<String> _typing = {}; // şu an yazan kişiler (listede "yazıyor..." görünür)
  final Map<String, Timer> _typingTimers = {};

  @override
  void initState() {
    super.initState();
    _sub = SocketService.instance.events.listen((e) {
      if (e['type'] == 'typing' && mounted) {
        final id = e['userId']?.toString();
        if (id == null) return;
        _typingTimers[id]?.cancel();
        setState(() => _typing.add(id));
        _typingTimers[id] = Timer(const Duration(seconds: 4), () {
          _typingTimers.remove(id);
          if (mounted) setState(() => _typing.remove(id));
        });
        return;
      }
      if (e['type'] != 'dm' || !mounted) return;
      final from = mapOf(e['message'])?['senderId']?.toString();
      if (from != null && _typing.remove(from)) _typingTimers.remove(from)?.cancel();
      // Art arda gelen mesajlarda tek yenileme yeterli.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) _reload?.call();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _newChat() async {
    final u = await pickUser(context);
    if (u == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: u)));
    if (mounted) setState(() => _version++);
  }

  Future<List<Map<String, dynamic>>> _loadAll() async {
    final conv = listOf((await Api.get('/api/messages/conversations'))['conversations']);
    // Çevrimiçi noktaları: ilk durum yanıttan, sonraki değişiklikler soketten gelir.
    final ids = <String>[];
    for (final c in conv) {
      final id = mapOf(c['peer'])?['id']?.toString();
      if (id == null) continue;
      ids.add(id);
      PresenceService.seed(id, c['presence']);
    }
    PresenceService.watch(ids);
    try {
      final f = listOf((await Api.get('/api/users/${Session.id}/following'))['users']);
      _following = {for (final u in f) u['id'].toString()};
    } catch (_) {/* filtre olmadan da liste görünür */}
    return conv;
  }

  void _openNotices() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final k in const [['team', 'Ekip duyuruları', Icons.workspace_premium], ['event', 'Etkinlik duyuruları', Icons.campaign], ['reward', 'Ödül bildirimleri', Icons.card_giftcard]])
            ListTile(
              leading: Icon(k[2] as IconData),
              title: Text(k[1] as String),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => AnnouncementsScreen(kind: k[0] as String, title: k[1] as String)));
              },
            ),
        ]),
      ),
    );
  }

  Widget _segment(String label, bool on, VoidCallback onTap) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: on ? Pal.cyan : Pal.outline, width: on ? 1.6 : 1),
              color: on ? Pal.cyan.withValues(alpha: 0.08) : Colors.transparent,
            ),
            child: Text(label, style: TextStyle(color: on ? Pal.cyan : Pal.textDim, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ),
      );

  Widget _conversation(Map<String, dynamic> c) {
    final peer = mapOf(c['peer']);
    final unread = (c['unread'] as num? ?? 0).toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.s),
      child: Material(
        color: Pal.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.lg), side: const BorderSide(color: Pal.outline, width: 0.8)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Rad.lg),
          onTap: () async {
            if (peer == null) return;
            await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)));
            Inbox.refresh();
            if (mounted) _reload?.call();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.m, Gap.m),
            child: Row(children: [
              PresenceAvatar(userId: peer?['id']?.toString(), child: UserAvatar(user: peer, radius: 24)),
              const SizedBox(width: Gap.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: UserName(user: peer, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    const SizedBox(width: Gap.s),
                    Text(_time(c['lastMessageAt']), style: const TextStyle(fontSize: 12, color: Pal.textDim)),
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    Expanded(
                      child: _typing.contains(peer?['id']?.toString())
                          ? const Text('yazıyor...', maxLines: 1, style: TextStyle(fontSize: 13.5, color: Pal.green, fontStyle: FontStyle.italic))
                          : Text('${c['lastFromMe'] == true ? 'Sen: ' : ''}${c['lastMessage']}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: unread > 0 ? Pal.text : Pal.textDim, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400)),
                    ),
                    if (unread > 0) Badge(label: Text(unread > 99 ? '99+' : '$unread')),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _newChat, tooltip: 'Yeni mesaj', child: const Icon(Icons.edit)),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_version),
        load: _loadAll,
        builder: (context, all, reload) {
          _reload = reload;
          final list = _special ? all.where((c) => _following.contains(mapOf(c['peer'])?['id']?.toString())).toList() : all;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              // Başlık: Sohbet (okunmamış) · Aile · Arkadaşlar
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.l, Gap.m, Gap.s, Gap.s),
                child: Row(children: [
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: Inbox.unread,
                      builder: (_, n, __) => Text('Sohbet ($n)', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12), shape: const StadiumBorder(), side: BorderSide(color: Pal.cyan.withValues(alpha: 0.5))),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Aile')), body: const FamilyScreen()))),
                    icon: const Icon(Icons.groups, size: 18),
                    label: const Text('Aile'),
                  ),
                  IconButton(tooltip: 'Duyurular', onPressed: _openNotices, icon: const Icon(Icons.notifications_none, color: Pal.textDim)),
                  IconButton(tooltip: 'Arkadaşlar', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen())), icon: const Icon(Icons.people_outline, color: Pal.textDim)),
                ]),
              ),
              const _InboxCards(),
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.m),
                child: Row(children: [
                  _segment('Tüm', !_special, () => setState(() => _special = false)),
                  const SizedBox(width: Gap.m),
                  _segment('Özel Takip', _special, () => setState(() => _special = true)),
                ]),
              ),
              if (list.isEmpty)
                EmptyState(
                  icon: Icons.forum_outlined,
                  text: _special ? 'Takip ettiğin kişilerle henüz sohbetin yok.' : 'Henüz mesajın yok. Arkadaşlarınla sohbet başlatmak için sağ alttaki düğmeye dokun.',
                ),
              for (final c in list) _conversation(c),
            ]),
          );
        },
      ),
    );
  }
}

/// Mesajlar ekranının üstündeki üç kategori kartı (Yoho düzeni).
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

  Widget _card(String label, IconData icon, Color iconColor, int badge, VoidCallback onTap) {
    return Expanded(
      child: Semantics(
        button: true,
        label: badge > 0 ? '$label, $badge yeni' : label,
        child: Material(
          color: Pal.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.lg), side: const BorderSide(color: Pal.outline, width: 0.8)),
          child: InkWell(
            borderRadius: BorderRadius.circular(Rad.lg),
            onTap: onTap,
            child: SizedBox(
              height: 104,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.s, Gap.m),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(
                    child: Badge(
                      isLabelVisible: badge > 0,
                      label: Text(badge > 99 ? '99+' : '$badge'),
                      offset: const Offset(6, -4),
                      child: Icon(icon, size: 34, color: iconColor),
                    ),
                  ),
                  const Spacer(),
                  Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.2, color: Pal.text)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _n(String k) => (_sum[k] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.l, Gap.xs, Gap.l, Gap.m),
      child: ValueListenableBuilder<Map<String, int>>(
        valueListenable: Inbox.badges,
        builder: (context, b, _) => Row(children: [
          _card('Arkadaşlık İsteği', Icons.waving_hand, const Color(0xFFFFC43D), b['friends'] ?? 0, () => _open(const FriendsScreen())),
          const SizedBox(width: Gap.s),
          _card('Çevrimiçi Sohbet', Icons.forum, const Color(0xFF4FC3F7), 0, () => _open(const SupportChatScreen())),
          const SizedBox(width: Gap.s),
          _card('Ajans Mesajı', Icons.apartment, Pal.cyan, _n('team'), () => _open(const AnnouncementsScreen(kind: 'team', title: 'Ajans Mesajı'))),
        ]),
      ),
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
  // "Yazıyor...": karşı taraf yazarken 4 sn gösterilir; ben yazarken en fazla 2,5 sn'de bir bildirilir.
  bool _peerTyping = false;
  Timer? _typingTimer;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  String get _peerId => widget.peer['id'].toString();

  void _onInput(String text) {
    if (text.trim().isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) < const Duration(milliseconds: 2500)) return;
    _lastTypingSent = now;
    SocketService.instance.send({'type': 'typing', 'to': _peerId});
  }

  @override
  void initState() {
    super.initState();
    _load();
    PresenceService.watch([_peerId]);
    _sub = SocketService.instance.events.listen((e) {
      if (e['type'] == 'connected' && mounted) {
        _load(); // bağlantı koptuysa arada gelen mesajları al
        return;
      }
      // Karşı taraf mesajlarımı okudu: "Görüldü".
      if (e['type'] == 'dm_read' && e['userId']?.toString() == _peerId) {
        if (!mounted) return;
        final at = e['at'] ?? DateTime.now().toUtc().toIso8601String();
        setState(() {
          for (final m in _messages) {
            if (m['senderId'] == Session.id && m['readAt'] == null) m['readAt'] = at;
          }
        });
        return;
      }
      if (e['type'] == 'typing' && e['userId']?.toString() == _peerId) {
        if (!mounted) return;
        _typingTimer?.cancel();
        setState(() => _peerTyping = true);
        _typingTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _peerTyping = false);
        });
        return;
      }
      if (e['type'] != 'dm') return;
      final m = mapOf(e['message']);
      if (m == null || m['senderId'] != _peerId) return;
      // Mesaj geldi: "yazıyor" biter.
      _typingTimer?.cancel();
      if (_peerTyping && mounted) setState(() => _peerTyping = false);
      if (!mounted || _messages.any((x) => x['id'] == m['id'])) return; // aynı mesaj iki kez eklenmesin
      setState(() => _messages.add(m));
      _toEnd();
      Api.get('/api/messages/with/$_peerId').then((_) => Inbox.refresh()).catchError((_) => <String, dynamic>{}); // okundu işaretle
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _typingTimer?.cancel();
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
          child: Row(children: [
            PresenceAvatar(userId: _peerId, dotSize: 10, child: UserAvatar(user: peer, radius: 16)),
            const SizedBox(width: 8),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                UserName(user: peer),
                if (_peerTyping)
                  const Text('yazıyor...', style: TextStyle(fontSize: 11, color: Pal.green, fontStyle: FontStyle.italic))
                else
                  PresenceLine(userId: _peerId, fontSize: 11),
              ]),
            ),
          ]),
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
                            // "Görüldü" yalnızca okunan son mesajımın altında gösterilir.
                            final seen = mine && m['readAt'] != null && !_messages.skip(i + 1).any((x) => x['senderId'] == Session.id && x['readAt'] != null);
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                decoration: BoxDecoration(color: mine ? Colors.pinkAccent.shade400 : Colors.white12, borderRadius: BorderRadius.circular(16)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text((m['text'] ?? '').toString()),
                                  Text(seen ? '${_time(m['createdAt'])} · Görüldü' : _time(m['createdAt']), style: const TextStyle(fontSize: 11, color: Colors.white54)),
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
                  onChanged: _onInput,
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
