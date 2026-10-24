import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/room_dock.dart';
import '../services/session.dart';
import '../services/socket_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import 'family_screen.dart';
import 'inbox_screens.dart';
import 'user_screens.dart';

/// Mesajlar → Bildirimler: beğeni, yorum, takipçi, arkadaşlık, aile bildirimi / daveti, arkadaşın oda açması.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = SocketService.instance.events.listen((e) {
      if (e['type'] == 'notify' && mounted) _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/api/me/notifications');
      if (!mounted) return;
      setState(() {
        _items = listOf(r['notifications']);
        _error = null;
      });
      Api.post('/api/me/notifications/seen').catchError((_) => <String, dynamic>{});
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  IconData _icon(String kind) => switch (kind) {
        'post_like' => Icons.favorite_rounded,
        'post_comment' => Icons.mode_comment_rounded,
        'follow' => Icons.person_add_alt_1_rounded,
        'friend_request' || 'friend_accept' => Icons.waving_hand_rounded,
        'room_open' => Icons.mic_rounded,
        'family_notice' || 'family_join' => Icons.groups_rounded,
        'guardian' => Icons.shield_rounded,
        'relation_request' => Icons.favorite_border_rounded,
        _ => Icons.notifications_rounded,
      };

  Color _color(String kind) => switch (kind) {
        'post_like' || 'relation_request' => Pal.pink,
        'post_comment' => Pal.cyan,
        'follow' || 'friend_request' || 'friend_accept' => Pal.amber,
        'room_open' => Pal.green,
        'family_notice' || 'family_join' => Pal.purple,
        _ => Pal.cyan,
      };

  void _open(Map<String, dynamic> n) {
    final kind = (n['kind'] ?? '').toString();
    final d = mapOf(n['data']) ?? {};
    final roomId = d['roomId']?.toString();
    if (roomId != null) {
      RoomDock.open(RoomRequest(roomId: roomId, name: (d['roomName'] ?? 'Oda').toString()));
      return;
    }
    Widget? page;
    if (kind == 'friend_request') {
      page = const FriendRequestsScreen();
    } else if (kind.startsWith('family')) {
      page = const FamilyScreen();
    } else if (kind.startsWith('post_')) {
      page = UserProfileScreen(userId: Session.id);
    } else if (d['userId'] != null) {
      page = UserProfileScreen(userId: d['userId'].toString());
    }
    if (page != null) Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: Pal.bg,
      appBar: AppBar(backgroundColor: Pal.bg, title: const Text('Bildirimler')),
      body: _error != null && items == null
          ? LoadError(message: _error!, onRetry: _load)
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? const Center(child: Text('Henüz bildirimin yok.', style: TextStyle(color: Pal.textDim)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72, color: Color(0x1FFFFFFF)),
                        itemBuilder: (_, i) {
                          final n = items[i];
                          final kind = (n['kind'] ?? '').toString();
                          return ListTile(
                            onTap: () => _open(n),
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: _color(kind).withValues(alpha: 0.18),
                              child: Icon(_icon(kind), color: _color(kind), size: 22),
                            ),
                            title: Text((n['title'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.text)),
                            subtitle: Text((n['body'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.textDim)),
                            trailing: Text(yohoTime(n['createdAt']), style: const TextStyle(color: Pal.textDim, fontSize: 12)),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// Aile sohbeti: ailenin tüm üyeleri kendi aralarında yazışır.
class FamilyChatPage extends StatefulWidget {
  final String familyId;
  final String familyName;
  const FamilyChatPage({super.key, required this.familyId, required this.familyName});

  @override
  State<FamilyChatPage> createState() => _FamilyChatPageState();
}

class _FamilyChatPageState extends State<FamilyChatPage> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _msgs = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  StreamSubscription? _sub;

  String get _base => '/api/families/${widget.familyId}/chat';

  @override
  void initState() {
    super.initState();
    _load();
    _sub = SocketService.instance.events.listen((e) {
      if (e['type'] != 'family_chat' || e['familyId'] != widget.familyId || !mounted) return;
      final m = mapOf(e['message']);
      if (m == null || _msgs.any((x) => x['id'] == m['id'])) return;
      setState(() => _msgs.add(m));
      _toEnd();
      Api.post('$_base/seen').catchError((_) => <String, dynamic>{});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get(_base);
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(listOf(r['messages']));
        _loading = false;
        _error = null;
      });
      _toEnd();
      Api.post('$_base/seen').catchError((_) => <String, dynamic>{});
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = errorText(e);
        });
      }
    }
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final r = await guard(context, () => Api.post(_base, {'text': text}));
    if (!mounted) return;
    setState(() => _sending = false);
    final m = mapOf(r?['message']);
    if (m != null) {
      _ctl.clear();
      if (!_msgs.any((x) => x['id'] == m['id'])) setState(() => _msgs.add(m));
      _toEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pal.bg,
      appBar: AppBar(
        backgroundColor: Pal.bg,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.familyName, style: const TextStyle(fontWeight: FontWeight.w700)),
          const Text('Aile sohbeti', style: TextStyle(fontSize: 12, color: Pal.textDim)),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? LoadError(message: _error!, onRetry: _load)
                  : _msgs.isEmpty
                      ? const Center(child: Text('Aile sohbetine ilk mesajı sen yaz!', style: TextStyle(color: Pal.textDim)))
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          itemCount: _msgs.length,
                          itemBuilder: (_, i) {
                            final m = _msgs[i];
                            final u = mapOf(m['user']);
                            final mine = u?['id'] == Session.id;
                            final stamp = i == 0 || needsStamp(_msgs[i - 1]['createdAt'], m['createdAt']);
                            return Column(children: [
                              if (stamp) TimeStamp(m['createdAt']),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!mine) ...[
                                      GestureDetector(
                                        onTap: () {
                                          final id = u?['id']?.toString();
                                          if (id != null && u?['isHidden'] != true) {
                                            Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)));
                                          }
                                        },
                                        child: UserAvatar(user: u, radius: 18),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Flexible(
                                      child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                                        if (!mine) Padding(padding: const EdgeInsets.only(bottom: 3), child: UserName(user: u, style: const TextStyle(fontSize: 12.5))),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                          decoration: BoxDecoration(
                                            color: mine ? null : Pal.surfaceHi,
                                            gradient: mine ? const LinearGradient(colors: kGoldDeep) : null,
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Text((m['text'] ?? '').toString(), style: const TextStyle(color: Colors.white, fontSize: 15)),
                                        ),
                                      ]),
                                    ),
                                  ],
                                ),
                              ),
                            ]);
                          },
                        ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: const TextStyle(color: Pal.text),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Ailene yaz...',
                    filled: true,
                    fillColor: Pal.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}
