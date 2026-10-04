import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../services/api.dart';
import '../services/music_service.dart';
import '../services/session.dart';
import '../services/socket_service.dart';
import '../widgets/common.dart';
import '../widgets/gift_ribbon.dart';
import '../widgets/safety_actions.dart';
import '../widgets/pk_banner.dart';
import '../widgets/room_theme.dart';
import 'gift_sheet.dart';
import 'ludo_screen.dart';
import 'pk_sheet.dart';
import 'music_sheet.dart';
import 'user_screens.dart';

const _roleLabels = {'owner': 'Oda sahibi', 'cohost': 'Yardımcı sahip', 'moderator': 'Moderatör', 'user': 'Üye'};
const _roleLevel = {'user': 1, 'moderator': 2, 'cohost': 3, 'owner': 4};

class RoomScreen extends StatefulWidget {
  final String roomId;
  final String initialName;
  final bool locked;
  final String? code; // gizli oda davet kodu
  const RoomScreen({super.key, required this.roomId, this.initialName = 'Oda', this.locked = false, this.code});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  Map<String, dynamic>? _room;
  Map<String, dynamic> _me = {};
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  bool _joined = false;
  bool _closing = false;
  bool _rejoining = false;

  lk.Room? _lk;
  bool _lkConnecting = false;
  String? _lkError;
  bool _micOn = true;
  bool _camOn = true;

  StreamSubscription? _sub;

  final List<Map<String, dynamic>> _messages = [];
  final _chatCtl = TextEditingController();
  final _chatScroll = ScrollController();
  bool _sending = false;
  bool _chatMuted = false;

  // Oda içi sayı tahtası (kullanıcı → alınan toplam Coin) ve PK durumu
  final Map<String, String> _scores = {};
  Map<String, dynamic>? _pk;
  bool _inviteOpen = false;

  bool get _isManager => _myRole == 'owner' || _myRole == 'cohost' || _myRole == 'moderator';
  bool get _chatOpen => _room?['chatEnabled'] != false || _isManager;

  bool get _isVideo => _room?['roomType'] == 'video';
  int get _seatCount => (_room?['seatCount'] as num?)?.toInt() ?? 8;
  String get _myRole => (_me['role'] ?? 'user').toString();
  bool get _onSeat => _me['microphone'] == true;

  @override
  void initState() {
    super.initState();
    _sub = SocketService.instance.events.listen(_onEvent);
    _enter();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _chatCtl.dispose();
    _chatScroll.dispose();
    MusicService.instance.unbind();
    SocketService.instance.unsubscribeRoom();
    if (_joined) {
      _joined = false;
      Api.post('/api/rooms/${widget.roomId}/leave').catchError((_) => <String, dynamic>{});
    }
    final room = _lk;
    _lk = null;
    if (room != null) {
      room.removeListener(_onLkChanged);
      room.disconnect().whenComplete(() => room.dispose());
    }
    super.dispose();
  }

  // ---------- Giriş / çıkış ----------
  Future<void> _enter() async {
    try {
      String? password;
      if (widget.locked) {
        password = await askText(context, 'Oda şifresi', obscure: true);
        if (password == null) {
          if (mounted) Navigator.pop(context);
          return;
        }
      }
      final r = await Api.post('/api/rooms/${widget.roomId}/join', {if (password != null) 'password': password, if (widget.code != null) 'code': widget.code});
      if (!mounted) {
        Api.post('/api/rooms/${widget.roomId}/leave').catchError((_) => <String, dynamic>{});
        return;
      }
      _joined = true;
      _room = mapOf(r['room']);
      _me = mapOf(r['me']) ?? {};
      SocketService.instance.subscribeRoom(widget.roomId);
      await _loadMembers();
      if (!mounted) return;
      setState(() => _loading = false);
      _connectLivekit();
      _loadMessages();
      _loadExtras();
      MusicService.instance.bind(widget.roomId);
    } catch (e) {
      if (!mounted) return;
      toast(context, errorText(e), error: true);
      Navigator.pop(context);
    }
  }

  Future<void> _loadExtras() async {
    try {
      final s = await Api.get('/api/rooms/${widget.roomId}/scoreboard');
      final pk = await Api.get('/api/rooms/${widget.roomId}/pk');
      if (!mounted) return;
      setState(() {
        _scores
          ..clear()
          ..addEntries(listOf(s['scoreboard']).map((x) => MapEntry(x['userId'].toString(), x['coins'].toString())));
        _pk = mapOf(pk['pk']);
      });
    } catch (_) {/* ek özellikler yüklenemese de oda çalışır */}
  }

  Future<void> _loadMembers() async {
    final r = await Api.get('/api/rooms/${widget.roomId}/members');
    if (!mounted) return;
    setState(() => _members = listOf(r['members']));
  }

  Future<void> _loadMessages() async {
    try {
      final r = await Api.get('/api/rooms/${widget.roomId}/messages');
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(listOf(r['messages']));
      });
      _scrollChatToEnd();
    } catch (_) {/* sohbet yüklenemese de oda çalışır */}
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
    });
  }

  Future<void> _sendChat() async {
    final text = _chatCtl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final r = await guard(context, () => Api.post('/api/rooms/${widget.roomId}/messages', {'text': text}));
    if (!mounted) return;
    setState(() => _sending = false);
    if (r != null) _chatCtl.clear();
  }

  Future<void> _rejoin() async {
    if (_rejoining || _closing) return;
    _rejoining = true;
    try {
      await Api.post('/api/rooms/${widget.roomId}/join');
      _joined = true;
      SocketService.instance.subscribeRoom(widget.roomId);
      await _loadMembers();
      if (_lk == null) _connectLivekit();
    } catch (e) {
      _exit(errorText(e));
    } finally {
      _rejoining = false;
    }
  }

  void _exit(String message) {
    if (_closing || !mounted) return;
    _closing = true;
    _joined = false; // sunucu tarafında zaten çıkarıldık
    toast(context, message);
    Navigator.of(context).pop();
  }

  Future<void> _onBack() async {
    if (_closing) return;
    if (_myRole == 'owner') {
      final ok = await confirm(context, 'Odadan ayrılırsanız oda kapanır. Devam edilsin mi?', action: 'Odayı kapat');
      if (!ok || !mounted) return;
    }
    _closing = true;
    if (_joined) {
      _joined = false;
      try {
        await Api.post('/api/rooms/${widget.roomId}/leave');
      } catch (_) {/* sunucu temizler */}
    }
    if (mounted) Navigator.of(context).pop();
  }

  bool _micInviteOpen = false;
  List<int> get _lockedSeats => ((_room?['lockedSeats'] as List?) ?? const []).map((x) => (x as num).toInt()).toList();
  bool get _canSeatManage => ['owner', 'cohost', 'moderator'].contains(_myRole);

  Future<void> _lockSeat(int index, bool locked) async {
    await guard(context, () => Api.post('/api/rooms/${widget.roomId}/seats/$index/lock', {'locked': locked}));
  }

  // ---------- Gerçek zamanlı olaylar ----------
  void _onEvent(Map<String, dynamic> e) {
    final type = e['type'];
    if (type == 'error' && e['code'] == 'not_member' && e['roomId'] == widget.roomId) {
      _rejoin();
      return;
    }
    if (type == 'mic_invite' && e['roomId'] == widget.roomId) {
      if (mounted && !_micInviteOpen && _members.every((m) => m['userId'] != Session.id || m['seatIndex'] == null)) {
        _micInviteOpen = true;
        final seat = (e['seatIndex'] as num?)?.toInt();
        showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Mikrofon daveti'),
            content: Text('${e['fromName'] ?? 'Oda yetkilisi'} sizi mikrofona davet ediyor${seat != null ? ' (${seat + 1}. koltuk)' : ''}.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Reddet')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Mikrofona çık')),
            ],
          ),
        ).then((ok) {
          _micInviteOpen = false;
          if (ok == true && mounted) _takeMic(seat);
        });
      }
      return;
    }
    if (type == 'pk_invite') {
      final pk = mapOf(e['pk']);
      if (pk != null && mounted && !_inviteOpen && mapOf(pk['b'])?['roomId'] == widget.roomId) {
        _inviteOpen = true;
        showPkInviteDialog(context, pk).whenComplete(() => _inviteOpen = false);
      }
      return;
    }
    if (type == 'room_game_state') return; // Ludo ekranı kendisi dinler
    if (type == 'pk_tick') {
      if (_pk != null && _pk!['id'] == e['pkId']) {
        setState(() {
          final a = {...?mapOf(_pk!['a']), 'score': e['scoreA']};
          final b = {...?mapOf(_pk!['b']), 'score': e['scoreB']};
          _pk = {..._pk!, 'a': a, 'b': b, 'remainingSeconds': e['remainingSeconds']};
        });
      }
      return;
    }
    if (type == 'pk_state') {
      final pk = mapOf(e['pk']);
      if (pk != null && (mapOf(pk['a'])?['roomId'] == widget.roomId || mapOf(pk['b'])?['roomId'] == widget.roomId)) {
        final st = pk['status'];
        setState(() => _pk = pk);
        if (st == 'finished' || st == 'declined' || st == 'cancelled') {
          Future.delayed(const Duration(seconds: 8), () {
            if (mounted && _pk?['id'] == pk['id'] && _pk?['status'] != 'active') setState(() => _pk = null);
          });
        }
      }
      return;
    }
    if (e['roomId'] != widget.roomId) return;
    switch (type) {
      case 'room_scoreboard':
        setState(() {
          _scores.clear();
          for (final x in listOf(e['scoreboard'])) {
            _scores[x['userId'].toString()] = x['coins'].toString();
          }
        });
        break;
      case 'room_chat_cleared':
        setState(() => _messages.clear());
        break;
      case 'room_member_joined':
        final u = mapOf(e['user']);
        if (u != null && !_members.any((m) => m['userId'] == u['id'])) {
          setState(() => _members.add({'userId': u['id'], 'role': 'user', 'microphone': false, 'seatIndex': null, 'user': u}));
        }
        break;
      case 'room_member_left':
        setState(() => _members.removeWhere((m) => m['userId'] == e['userId']));
        break;
      case 'room_seat_changed':
        setState(() => _applySeat(e['userId'].toString(), (e['seatIndex'] as num?)?.toInt(), e['microphone'] == true));
        break;
      case 'room_seats_locked':
        setState(() => _room = {...?_room, 'lockedSeats': e['lockedSeats']});
        break;
      case 'room_role_changed':
        setState(() {
          final i = _members.indexWhere((m) => m['userId'] == e['userId']);
          if (i >= 0) _members[i] = {..._members[i], 'role': e['role']};
          if (e['userId'] == Session.id) _me = {..._me, 'role': e['role']};
        });
        break;
      case 'room_message':
        if (!_messages.any((m) => m['id'] == e['id'])) {
          setState(() {
            _messages.add({'id': e['id'], 'user': e['user'], 'text': e['text'], 'createdAt': e['createdAt']});
            if (_messages.length > 200) _messages.removeAt(0);
          });
          _scrollChatToEnd();
        }
        break;
      case 'room_message_deleted':
        setState(() => _messages.removeWhere((m) => m['id'] == e['messageId']));
        break;
      case 'room_chat_muted':
        setState(() => _chatMuted = (e['minutes'] as num? ?? 0) > 0);
        toast(context, _chatMuted ? 'Bu odada sohbette susturuldunuz.' : 'Sohbet yasağınız kaldırıldı.');
        break;
      case 'room_settings':
        setState(() => _room = {
              ...?_room,
              'name': e['name'], 'tags': e['tags'], 'locked': e['locked'], 'chatEnabled': e['chatEnabled'],
              'theme': e['theme'], 'themeImageUrl': e['themeImageUrl'], 'scoreboardEnabled': e['scoreboardEnabled'], 'hidden': e['hidden'],
            });
        break;
      case 'room_music_state':
        final ms = mapOf(e['state']);
        if (ms != null) MusicService.instance.apply(ms);
        break;
      case 'room_closed':
        _exit('Oda kapatıldı.');
        break;
      case 'room_kicked':
        _exit('Odadan çıkarıldınız.');
        break;
      case 'room_blocked':
        _exit('Bu odadan engellendiniz.');
        break;
    }
  }

  void _applySeat(String userId, int? seat, bool mic) {
    final i = _members.indexWhere((m) => m['userId'] == userId);
    if (i >= 0) _members[i] = {..._members[i], 'seatIndex': seat, 'microphone': mic};
    if (userId == Session.id) {
      final changed = _me['microphone'] != mic;
      _me = {..._me, 'seatIndex': seat, 'microphone': mic};
      if (changed) _syncPublish();
    }
  }

  // ---------- LiveKit ----------
  void _onLkChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _connectLivekit() async {
    if (_lk != null || _lkConnecting) return;
    _lkConnecting = true;
    if (mounted) setState(() => _lkError = null);
    lk.Room? room;
    try {
      final t = await Api.post('/api/rooms/${widget.roomId}/livekit-token');
      final url = t['url'] as String?;
      final token = t['token'] as String?;
      if (url == null || url.isEmpty || token == null) throw ApiException('Ses sunucusu yapılandırılmamış.');
      room = lk.Room(roomOptions: lk.RoomOptions(adaptiveStream: true, dynacast: true));
      room.addListener(_onLkChanged);
      await room.connect(url, token);
      if (!mounted || _closing) {
        room.removeListener(_onLkChanged);
        await room.disconnect();
        await room.dispose();
        return;
      }
      _lk = room;
      await _syncPublish();
    } catch (e) {
      if (room != null) {
        room.removeListener(_onLkChanged);
        room.disconnect().whenComplete(() => room!.dispose());
      }
      if (mounted) setState(() => _lkError = errorText(e));
    } finally {
      _lkConnecting = false;
      if (mounted) setState(() {});
    }
  }

  /// Koltuktaysak mikrofonu (görüntülü odada kamerayı) yayına aç, değilsek kapat.
  Future<void> _syncPublish() async {
    final room = _lk;
    if (room == null) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(_onSeat && _micOn);
        if (_isVideo) await room.localParticipant?.setCameraEnabled(_onSeat && _camOn);
        return;
      } catch (_) {
        // Yayın izni sunucudan birkaç yüz ms içinde gelir; kısa süre bekleyip tekrar dene.
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    if (mounted && _onSeat) toast(context, 'Mikrofon açılamadı. Mikrofon/kamera iznini kontrol edin.', error: true);
  }

  bool _isSpeaking(String userId) {
    final room = _lk;
    if (room == null) return false;
    final local = room.localParticipant;
    if (local != null && local.identity == userId) return local.isSpeaking;
    for (final p in room.remoteParticipants.values) {
      if (p.identity == userId) return p.isSpeaking;
    }
    return false;
  }

  Widget? _videoFor(String userId) {
    final room = _lk;
    if (room == null) return null;
    lk.Participant? participant;
    final local = room.localParticipant;
    if (local != null && local.identity == userId) participant = local;
    for (final p in room.remoteParticipants.values) {
      if (p.identity == userId) participant = p;
    }
    if (participant == null) return null;
    for (final pub in participant.videoTrackPublications) {
      final track = pub.track;
      if (track != null && !pub.muted) return lk.VideoTrackRenderer(track as lk.VideoTrack);
    }
    return null;
  }

  // ---------- Eylemler ----------
  Future<void> _takeMic([int? seat]) async {
    final r = await guard(context, () => Api.post('/api/rooms/${widget.roomId}/mic/take', {if (seat != null) 'seatIndex': seat}));
    if (r == null || !mounted) return;
    setState(() => _applySeat(Session.id, (r['seatIndex'] as num?)?.toInt(), true));
  }

  Future<void> _leaveMic() async {
    final r = await guard(context, () => Api.post('/api/rooms/${widget.roomId}/mic/leave'));
    if (r == null || !mounted) return;
    setState(() => _applySeat(Session.id, null, false));
  }

  bool _canModerate(String targetRole) =>
      (_roleLevel[_myRole] ?? 0) >= 2 && (_roleLevel[_myRole] ?? 0) > (_roleLevel[targetRole] ?? 0) && targetRole != 'owner';

  Future<void> _moderate(String userId, String action, {Map<String, dynamic>? body}) async {
    await guard(context, () => Api.post('/api/rooms/${widget.roomId}/members/$userId/$action', body));
  }

  Future<void> _closeRoom() async {
    if (!await confirm(context, 'Oda kapatılsın mı? Herkes odadan çıkarılır.', action: 'Kapat')) return;
    if (!mounted) return;
    await guard(context, () => Api.post('/api/rooms/${widget.roomId}/close'));
  }

  Future<void> _roomSettings() async {
    final nameCtl = TextEditingController(text: (_room?['name'] ?? '').toString());
    final tagsCtl = TextEditingController(text: ((_room?['tags'] as List?) ?? const []).join(', '));
    final pwCtl = TextEditingController();
    final imgCtl = TextEditingController(text: (_room?['themeImageUrl'] ?? '').toString());
    var chatEnabled = _room?['chatEnabled'] != false;
    var scoreboard = _room?['scoreboardEnabled'] != false;
    var hidden = _room?['hidden'] == true;
    var theme = (_room?['theme'] ?? 'default').toString();
    var removePw = false;
    var regen = false;
    final code = _room?['joinCode']?.toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('Oda ayarları'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: nameCtl, maxLength: 60, decoration: const InputDecoration(labelText: 'Oda adı')),
              TextField(controller: tagsCtl, decoration: const InputDecoration(labelText: 'Etiketler (en fazla 3, virgülle)', hintText: 'müzik, sohbet')),
              if (_myRole == 'owner') ...[
                TextField(controller: pwCtl, obscureText: true, maxLength: 12, enabled: !removePw, decoration: InputDecoration(labelText: _room?['locked'] == true ? 'Yeni şifre (boş = değişmez)' : 'Oda şifresi (isteğe bağlı)')),
                if (_room?['locked'] == true) CheckboxListTile(dense: true, value: removePw, title: const Text('Şifreyi kaldır'), onChanged: (v) => setS(() => removePw = v == true)),
                SwitchListTile(dense: true, title: const Text('Odayı gizle (yalnızca kodla girilir)'), value: hidden, onChanged: (v) => setS(() => hidden = v)),
                if (hidden && code != null)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Davet kodu: $code', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
                    trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () { Clipboard.setData(ClipboardData(text: code)); toast(context, 'Kod kopyalandı.'); }),
                  ),
                if (hidden && code != null) CheckboxListTile(dense: true, value: regen, title: const Text('Kodu yenile'), onChanged: (v) => setS(() => regen = v == true)),
              ],
              SwitchListTile(dense: true, title: const Text('Yazılı sohbet açık'), value: chatEnabled, onChanged: (v) => setS(() => chatEnabled = v)),
              SwitchListTile(dense: true, title: const Text('Koltuk hediye sayacı'), value: scoreboard, onChanged: (v) => setS(() => scoreboard = v)),
              const SizedBox(height: 8),
              const Text('Oda teması'),
              const SizedBox(height: 6),
              ThemePicker(value: theme, onChanged: (v) => setS(() => theme = v)),
              TextField(controller: imgCtl, decoration: const InputDecoration(labelText: 'Özel arka plan görseli (https, WIP 4+)')),
              if (scoreboard)
                TextButton.icon(
                  onPressed: () async {
                    if (await confirm(c, 'Tüm koltuk hediye sayaçları sıfırlansın mı?', action: 'Sıfırla') && mounted) {
                      await guard(context, () => Api.post('/api/rooms/${widget.roomId}/scoreboard/reset'));
                    }
                  },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Sayaçları sıfırla'),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    final name = nameCtl.text.trim();
    final tags = tagsCtl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final pw = pwCtl.text.trim();
    final img = imgCtl.text.trim();
    nameCtl.dispose();
    tagsCtl.dispose();
    pwCtl.dispose();
    imgCtl.dispose();
    if (ok != true || !mounted) return;
    final prevImg = (_room?['themeImageUrl'] ?? '').toString();
    final r = await guard(context, () => Api.patch('/api/rooms/${widget.roomId}', {
          'name': name,
          'tags': tags,
          'chatEnabled': chatEnabled,
          'scoreboardEnabled': scoreboard,
          'theme': theme,
          if (img != prevImg) 'themeImageUrl': img.isEmpty ? null : img,
          if (_myRole == 'owner') 'hidden': hidden,
          if (_myRole == 'owner' && hidden && regen) 'regenerateCode': true,
          if (_myRole == 'owner' && removePw) 'password': null,
          if (_myRole == 'owner' && !removePw && pw.isNotEmpty) 'password': pw,
        }));
    final room = mapOf(r?['room']);
    if (room != null && mounted) setState(() => _room = {...?_room, ...room});
  }

  Widget _musicBar() {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: MusicService.instance.state,
      builder: (context, s, _) {
        final track = mapOf(s?['track']);
        if (track == null) return const SizedBox.shrink();
        final playing = s?['status'] == 'playing';
        return Material(
          color: Colors.white10,
          child: ListTile(
            dense: true,
            leading: Icon(playing ? Icons.graphic_eq : Icons.pause_circle_outline, color: Colors.pinkAccent),
            title: Text('${track['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text((track['artist'] ?? '').toString(), maxLines: 1),
            trailing: const Icon(Icons.queue_music),
            onTap: _openMusic,
          ),
        );
      },
    );
  }

  void _openMusic() => showMusicSheet(context, roomId: widget.roomId, canManage: _isManager, canQueue: _onSeat);

  Future<void> _clearChat() async {
    if (!await confirm(context, 'Odadaki tüm sohbet mesajları herkes için silinsin mi?', action: 'Temizle')) return;
    if (!mounted) return;
    await guard(context, () => Api.delete('/api/rooms/${widget.roomId}/messages'));
  }

  void _openGames() => Navigator.push(context, MaterialPageRoute(builder: (_) => LudoScreen(roomId: widget.roomId, canManage: _isManager)));

  Widget _chatPanel() {
    return Column(children: [
      if (_isManager)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Colors.white54),
            onPressed: _clearChat,
            icon: const Icon(Icons.cleaning_services_outlined, size: 16),
            label: const Text('Sohbeti temizle', style: TextStyle(fontSize: 12)),
          ),
        ),
      Expanded(
        child: _messages.isEmpty
            ? const Center(child: Text('Henüz mesaj yok.', style: TextStyle(color: Colors.white38)))
            : ListView.builder(
                controller: _chatScroll,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _messages.length,
                itemBuilder: (_, i) {
                  final m = _messages[i];
                  final u = mapOf(m['user']);
                  final color = parseColor(u?['nameColor'] as String?) ?? Colors.pinkAccent.shade100;
                  return GestureDetector(
                    onLongPress: () => _messageActions(m),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '${u?['displayName'] ?? ''}: ', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                        TextSpan(text: (m['text'] ?? '').toString()),
                      ])),
                    ),
                  );
                },
              ),
      ),
      if (_chatOpen)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _chatCtl,
                maxLength: 300,
                enabled: !_chatMuted,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendChat(),
                decoration: InputDecoration(isDense: true, counterText: '', hintText: _chatMuted ? 'Sohbette susturuldunuz' : 'Mesaj yaz...', border: const OutlineInputBorder()),
              ),
            ),
            IconButton(onPressed: _sending || _chatMuted ? null : _sendChat, icon: const Icon(Icons.send)),
          ]),
        )
      else
        const Padding(padding: EdgeInsets.all(8), child: Text('Bu odada yazılı sohbet kapalı.', style: TextStyle(color: Colors.white38))),
    ]);
  }

  void _messageActions(Map<String, dynamic> m) {
    final u = mapOf(m['user']);
    final mine = u?['id'] == Session.id;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (mine || _isManager)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Mesajı sil'),
              onTap: () {
                Navigator.pop(c);
                guard(context, () => Api.delete('/api/rooms/${widget.roomId}/messages/${m['id']}'));
              },
            ),
          if (!mine)
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Mesajı şikâyet et'),
              onTap: () {
                Navigator.pop(c);
                reportDialog(context, kind: 'room_message', targetUserId: u?['id'] as String?, roomId: widget.roomId, messageId: m['id'] as String?);
              },
            ),
        ]),
      ),
    );
  }

  void _openGifts([String? recipientId]) {
    final target = recipientId ??
        (_members.firstWhere((m) => m['role'] == 'owner', orElse: () => _members.isNotEmpty ? _members.first : <String, dynamic>{})['userId'] as String?);
    showGiftSheet(context, roomId: widget.roomId, members: _members, recipientId: target);
  }

  void _memberSheet(Map<String, dynamic> m) {
    final userId = m['userId'].toString();
    final user = mapOf(m['user']);
    final isSelf = userId == Session.id;
    final role = (m['role'] ?? 'user').toString();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) {
        void close() => Navigator.pop(c);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: UserAvatar(user: user),
                title: UserName(user: user, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${_roleLabels[role] ?? role}${m['seatIndex'] != null ? ' · ${(m['seatIndex'] as num).toInt() + 1}. koltuk' : ''}'),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profili gör'),
                onTap: () {
                  close();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: Text(isSelf ? 'Kendine hediye gönder' : 'Hediye gönder'),
                onTap: () {
                  close();
                  _openGifts(userId);
                },
              ),
              if (!isSelf && _canModerate(role)) ...[
                if (m['seatIndex'] != null)
                  ListTile(leading: const Icon(Icons.mic_off), title: const Text('Koltuktan kaldır'), onTap: () { close(); _moderate(userId, 'mic-off'); })
                else
                  ListTile(leading: const Icon(Icons.mic_none), title: const Text('Mikrofona davet et'), onTap: () { close(); _moderate(userId, 'mic-invite', body: {}); }),
                ListTile(leading: const Icon(Icons.comments_disabled), title: const Text('Sohbette sustur (10 dk)'), onTap: () { close(); _moderate(userId, 'chat-mute', body: {'minutes': 10}); }),
                ListTile(leading: const Icon(Icons.exit_to_app), title: const Text('Odadan at'), onTap: () { close(); _moderate(userId, 'kick'); }),
                ListTile(leading: const Icon(Icons.block), title: const Text('Engelle'), onTap: () { close(); _moderate(userId, 'block'); }),
              ],
              if (!isSelf) ...[
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Şikâyet et'),
                  onTap: () {
                    close();
                    reportDialog(context, kind: 'user', targetUserId: userId, roomId: widget.roomId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_off_outlined),
                  title: const Text('Kullanıcıyı engelle'),
                  onTap: () {
                    close();
                    blockUserDialog(context, userId, (user?['displayName'] ?? 'Kullanıcı').toString());
                  },
                ),
              ],
              if (!isSelf && (_myRole == 'owner' || _myRole == 'cohost') && role != 'owner') ...[
                if (role != 'moderator')
                  ListTile(leading: const Icon(Icons.shield), title: const Text('Moderatör yap'), onTap: () { close(); _moderate(userId, 'role', body: {'role': 'moderator'}); }),
                if (_myRole == 'owner' && role != 'cohost')
                  ListTile(leading: const Icon(Icons.stars), title: const Text('Yardımcı sahip yap'), onTap: () { close(); _moderate(userId, 'role', body: {'role': 'cohost'}); }),
                if (role != 'user')
                  ListTile(leading: const Icon(Icons.remove_moderator), title: const Text('Yetkiyi al'), onTap: () { close(); _moderate(userId, 'role', body: {'role': 'user'}); }),
              ],
            ]),
          ),
        );
      },
    );
  }

  void _membersSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            for (final m in _members)
              ListTile(
                leading: UserAvatar(user: mapOf(m['user']), radius: 18),
                title: UserName(user: mapOf(m['user'])),
                subtitle: Text(_roleLabels[m['role']] ?? ''),
                trailing: m['microphone'] == true ? const Icon(Icons.mic, size: 18) : null,
                onTap: () {
                  Navigator.pop(c);
                  _memberSheet(m);
                },
              ),
          ]),
        ),
      ),
    );
  }

  // ---------- Arayüz ----------
  Widget _seatTile(int index, Map<String, dynamic>? m) {
    if (m == null) {
      final reserved = index == 0;
      final locked = _lockedSeats.contains(index);
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: reserved
            ? null
            : () {
                if (_canSeatManage) {
                  showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (c) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(leading: const Icon(Icons.mic), title: const Text('Bu koltuğa otur'), onTap: () { Navigator.pop(c); _takeMic(index); }),
                        ListTile(
                          leading: Icon(locked ? Icons.lock_open : Icons.lock),
                          title: Text(locked ? 'Koltuğun kilidini aç' : 'Koltuğu kilitle'),
                          onTap: () { Navigator.pop(c); _lockSeat(index, !locked); },
                        ),
                      ]),
                    ),
                  );
                } else if (locked) {
                  toast(context, 'Bu koltuk kilitli.', error: true);
                } else {
                  _takeMic(index);
                }
              },
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white12,
            child: Icon(reserved ? Icons.star_border : (locked ? Icons.lock : Icons.add), color: locked ? Colors.orangeAccent : Colors.white54),
          ),
          const SizedBox(height: 4),
          Text('${index + 1}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      );
    }
    final userId = m['userId'].toString();
    final user = mapOf(m['user']);
    final video = _isVideo ? _videoFor(userId) : null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _memberSheet(m),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (video != null)
          SizedBox(width: 72, height: 72, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: video))
        else
          UserAvatar(user: user, radius: 26, speaking: _isSpeaking(userId)),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (m['role'] == 'owner') const Icon(Icons.star, size: 12, color: Colors.amber),
          Flexible(child: Text((user?['displayName'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
        ]),
        if (_room?['scoreboardEnabled'] != false)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
            child: Text('💎 ${fmtNumber(_scores[userId] ?? 0)}', style: const TextStyle(fontSize: 10, color: Colors.amberAccent)),
          ),
      ]),
    );
  }

  Widget _seatGrid() {
    final bySeat = <int, Map<String, dynamic>>{
      for (final m in _members)
        if (m['seatIndex'] != null) (m['seatIndex'] as num).toInt(): m,
    };
    final cols = _seatCount <= 5 ? 3 : 4;
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      childAspectRatio: 0.95,
      children: [for (var i = 0; i < _seatCount; i++) _seatTile(i, bySeat[i])],
    );
  }

  Widget _audience() {
    final list = _members.where((m) => m['seatIndex'] == null).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('İzleyiciler (${list.length})', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final m in list)
            GestureDetector(
              onTap: () => _memberSheet(m),
              child: SizedBox(
                width: 56,
                child: Column(children: [
                  UserAvatar(user: mapOf(m['user']), radius: 18),
                  Text((mapOf(m['user'])?['displayName'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(children: [
          if (_onSeat) ...[
            IconButton.filledTonal(
              tooltip: _micOn ? 'Mikrofonu sustur' : 'Mikrofonu aç',
              onPressed: () {
                setState(() => _micOn = !_micOn);
                _syncPublish();
              },
              icon: Icon(_micOn ? Icons.mic : Icons.mic_off),
            ),
            if (_isVideo) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: _camOn ? 'Kamerayı kapat' : 'Kamerayı aç',
                onPressed: () {
                  setState(() => _camOn = !_camOn);
                  _syncPublish();
                },
                icon: Icon(_camOn ? Icons.videocam : Icons.videocam_off),
              ),
            ],
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _leaveMic, child: const Text('Mikrofondan in')),
          ] else
            FilledButton.icon(onPressed: () => _takeMic(), icon: const Icon(Icons.mic), label: const Text('Mikrofona çık')),
          const Spacer(),
          if (_myRole == 'owner' && (_pk == null || !['pending', 'active'].contains(_pk!['status'])))
            IconButton(tooltip: 'PK başlat', onPressed: () => showPkChallengeSheet(context, roomId: widget.roomId), icon: const Icon(Icons.sports_mma)),
          IconButton(tooltip: 'Oyunlar (Ludo)', onPressed: _openGames, icon: const Icon(Icons.casino)),
          IconButton(tooltip: 'Müzik', onPressed: _openMusic, icon: const Icon(Icons.library_music)),
          IconButton.filled(tooltip: 'Hediye gönder', onPressed: _members.isEmpty ? null : () => _openGifts(), icon: const Icon(Icons.card_giftcard)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(children: [
            if (_room?['hidden'] == true) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.visibility_off, size: 18)),
            Flexible(child: Text((_room?['name'] ?? widget.initialName).toString(), overflow: TextOverflow.ellipsis)),
          ]),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _onBack),
          actions: [
            TextButton.icon(onPressed: _membersSheet, icon: const Icon(Icons.people_outline), label: Text('${_members.length}')),
            if (_myRole == 'owner' || _myRole == 'cohost') IconButton(tooltip: 'Oda ayarları', icon: const Icon(Icons.settings), onPressed: _roomSettings),
            if (_myRole == 'owner') IconButton(tooltip: 'Odayı kapat', icon: const Icon(Icons.power_settings_new), onPressed: _closeRoom),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RoomThemeBackground(
                theme: _room?['theme']?.toString(),
                imageUrl: _room?['themeImageUrl']?.toString(),
                child: GiftRibbonOverlay(
                roomId: widget.roomId,
                child: Column(children: [
                  if (_lkError != null)
                    Material(
                      color: Colors.red.shade900,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.error_outline),
                        title: Text('Ses/görüntü bağlanamadı: $_lkError', style: const TextStyle(fontSize: 12)),
                        trailing: TextButton(onPressed: _connectLivekit, child: const Text('Tekrar')),
                      ),
                    ),
                  _musicBar(),
                  if (_pk != null)
                    PkBanner(
                      pk: _pk!,
                      roomId: widget.roomId,
                      onCancel: _myRole == 'owner' ? () => guard(context, () => Api.post('/api/pk/${_pk!['id']}/cancel')) : null,
                    ),
                  Expanded(flex: 5, child: ListView(children: [_seatGrid(), _audience()])),
                  const Divider(height: 1),
                  Expanded(flex: 3, child: _chatPanel()),
                  _bottomBar(),
                ]),
              )),
      ),
    );
  }
}
