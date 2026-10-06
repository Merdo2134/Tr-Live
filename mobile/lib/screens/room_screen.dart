import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../services/api.dart';
import '../services/background_service.dart';
import '../services/music_service.dart';
import '../services/room_dock.dart';
import '../services/session.dart';
import '../services/socket_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/gift_ribbon.dart';
import '../widgets/safety_actions.dart';
import '../widgets/pk_banner.dart';
import '../widgets/room_theme.dart';
import '../widgets/seat_picker.dart';
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

class _RoomScreenState extends State<RoomScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _room;
  Map<String, dynamic> _me = {};
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  bool _joined = false;
  bool _closing = false;
  bool _rejoining = false;
  Timer? _beat;

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
    RoomDock.exitHandler = _onBack;
    WidgetsBinding.instance.addObserver(this);
    _enter();
  }

  /// Her 25 sn'de sunucuya "oda açık" sinyali gider: üyeyi canlı tutar, WebSocket aboneliğini tazeler,
  /// oda sunucuda kapanmışsa kullanıcı sonsuza dek ölü odada kalmaz.
  void _startHeartbeat() {
    _beat?.cancel();
    _beat = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (!mounted || !_joined || _closing) return;
      SocketService.instance.subscribeRoom(widget.roomId);
      try {
        await Api.post('/api/rooms/${widget.roomId}/heartbeat');
      } on ApiException catch (e) {
        if (!mounted || _closing) return;
        if (e.statusCode == 404) {
          _exit('Oda kapandı.');
        } else if (e.statusCode == 403) {
          _rejoin();
        }
      } catch (_) {/* ağ kesintisi: bir sonraki sinyalde tekrar denenir */}
    });
  }

  /// Arka plandan dönünce oda bilgisi yenilenir (bağlantı arada kopmuş olabilir).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_joined || _closing || !mounted) return;
    SocketService.instance.subscribeRoom(widget.roomId);
    _loadMembers().catchError((_) {});
    _loadMessages().catchError((_) {});
  }

  @override
  void dispose() {
    _beat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (RoomDock.exitHandler == _onBack) RoomDock.exitHandler = null;
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
          if (mounted) RoomDock.close();
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
      _startHeartbeat();
      BackgroundService.instance.ensurePermissions((msg, action) => confirm(context, msg, action: action));
    } catch (e) {
      if (!mounted) return;
      toast(context, errorText(e), error: true);
      RoomDock.close();
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
    try {
      final q = await Api.get('/api/rooms/${widget.roomId}/mic/queue');
      final ownerId = _room?['ownerId']?.toString();
      final f = ownerId != null && ownerId != Session.id ? await Api.get('/api/rooms/hosts/$ownerId/favorite') : null;
      if (!mounted) return;
      setState(() {
        _queue = ((q['queue'] as List?) ?? const []).map((x) => x.toString()).toList();
        _fav = f?['favorite'] == true;
      });
    } catch (_) {}
  }

  // ---------- Sıra, favori, oda değiştirme ----------
  List<String> _queue = [];
  bool _fav = false;
  double _overscroll = 0;
  bool _switching = false;

  bool get _inQueue => _queue.contains(Session.id);
  bool get _noFreeSeat {
    final taken = <int>{for (final m in _members) if (m['seatIndex'] != null) (m['seatIndex'] as num).toInt()};
    for (var i = 1; i < _seatCount; i++) {
      if (!taken.contains(i) && !_lockedSeats.contains(i)) return false;
    }
    return true;
  }

  Future<void> _toggleQueue() async {
    final r = await guard(context, () => _inQueue ? Api.delete('/api/rooms/${widget.roomId}/mic/queue') : Api.post('/api/rooms/${widget.roomId}/mic/queue'));
    if (r == null || !mounted) return;
    setState(() => _queue = ((r['queue'] as List?) ?? const []).map((x) => x.toString()).toList());
    if (_inQueue) toast(context, 'Sıraya girdiniz. Sıra size gelince haber verilir.');
  }

  Future<void> _toggleFavorite() async {
    final ownerId = _room?['ownerId']?.toString();
    if (ownerId == null) return;
    final r = await guard(context, () => _fav ? Api.delete('/api/rooms/hosts/$ownerId/favorite') : Api.post('/api/rooms/hosts/$ownerId/favorite'));
    if (r == null || !mounted) return;
    setState(() => _fav = r['favorite'] == true);
    toast(context, _fav ? 'Yayıncı favorilere eklendi.' : 'Favorilerden çıkarıldı.');
  }

  /// Yukarı kaydır → sonraki oda, aşağı kaydır → önceki oda (sahip kendi odasından ayrılamaz).
  Future<void> _switchRoom(int dir) async {
    if (_switching || _myRole == 'owner') return;
    _switching = true;
    try {
      final r = await Api.get('/api/rooms', query: {'type': (_room?['roomType'] ?? 'audio').toString()});
      final list = listOf(r['rooms']).where((x) => x['locked'] != true && x['ownerId']?.toString() != Session.id).toList();
      if (!mounted) return;
      final cur = list.indexWhere((x) => x['id'] == widget.roomId);
      final others = list.where((x) => x['id'] != widget.roomId).toList();
      if (others.isEmpty) return toast(context, 'Geçilecek başka oda yok.');
      final all = list;
      final i = cur < 0 ? (dir > 0 ? 0 : all.length - 1) : (cur + dir + all.length) % all.length;
      final t = all[i];
      if (t['id'] == widget.roomId) return;
      RoomDock.open(RoomRequest(roomId: t['id'].toString(), name: (t['name'] ?? 'Oda').toString()));
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      _switching = false;
    }
  }

  bool _onScrollNote(ScrollNotification n) {
    if (n is ScrollStartNotification) _overscroll = 0;
    if (n is OverscrollNotification) _overscroll += n.overscroll;
    if (n is ScrollEndNotification) {
      final o = _overscroll;
      _overscroll = 0;
      if (o > 90) _switchRoom(1);
      if (o < -90) _switchRoom(-1);
    }
    return false;
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
      // Yalnızca sunucu açıkça reddederse (oda kapandı, engellendi...) odadan çıkarılır.
      // Ağ kesintisi gibi geçici hatalarda oda açık kalır ve biraz sonra yeniden denenir.
      final code = e is ApiException ? e.statusCode : null;
      if (code != null && code >= 400 && code < 500 && code != 429 && code != 408) {
        _exit(errorText(e));
      } else {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && !_closing && !_rejoining) _rejoin();
        });
      }
    } finally {
      _rejoining = false;
    }
  }

  void _exit(String message) {
    if (_closing || !mounted) return;
    _closing = true;
    _joined = false; // sunucu tarafında zaten çıkarıldık
    toast(context, message);
    RoomDock.close();
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
    RoomDock.close();
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
      case 'room_mic_queue':
        setState(() => _queue = ((e['queue'] as List?) ?? const []).map((x) => x.toString()).toList());
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
              if (e['seatCount'] != null) 'seatCount': e['seatCount'],
              if (e['lockedSeats'] != null) 'lockedSeats': e['lockedSeats'],
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
      BackgroundService.instance.micChanged(mic);
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
        BackgroundService.instance.micChanged(_onSeat); // izin verildikten sonra servis "mikrofon" türüne geçer
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

  /// Oda adına dokununca: ad ve etiketler (oda sahibi / yardımcı sahip düzenler) ve oda yöneticileri.
  Future<void> _roomInfo() async {
    final canEdit = _myRole == 'owner' || _myRole == 'cohost';
    final res = await guard(context, () => Api.get('/api/rooms/${widget.roomId}/managers'));
    if (!mounted) return;
    final managers = listOf(res?['managers']);
    final nameCtl = TextEditingController(text: (_room?['name'] ?? '').toString());
    final tagsCtl = TextEditingController(text: ((_room?['tags'] as List?) ?? const []).join(', '));
    String roleLabel(String r) => r == 'owner' ? 'Oda sahibi' : (r == 'cohost' ? 'Yardımcı sahip' : 'Moderatör');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Oda bilgileri'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (canEdit) ...[
              TextField(controller: nameCtl, maxLength: 60, decoration: const InputDecoration(labelText: 'Oda adı')),
              TextField(controller: tagsCtl, decoration: const InputDecoration(labelText: 'Etiketler (en fazla 3, virgülle)', hintText: 'müzik, sohbet')),
              const Padding(padding: EdgeInsets.only(top: 6), child: Text('Değişiklikler odanın bir sonraki açılışında da geçerli kalır.', style: TextStyle(color: Colors.white54, fontSize: 12))),
            ] else ...[
              Text((_room?['name'] ?? '').toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(((_room?['tags'] as List?) ?? const []).isEmpty ? 'Etiket yok' : '#${((_room?['tags'] as List).join('  #'))}'),
            ],
            const SizedBox(height: 16),
            const Text('Oda yöneticileri', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            for (final m in managers)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(user: mapOf(m['user']), radius: 18),
                title: UserName(user: mapOf(m['user'])),
                trailing: Text(roleLabel('${m['role']}'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ),
            if (managers.length <= 1) const Text('Henüz yönetici yok. Oda içinde bir kullanıcıya dokunup moderatör veya yardımcı sahip yapabilirsiniz.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(canEdit ? 'Vazgeç' : 'Kapat')),
          if (canEdit) FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      ),
    );
    final name = nameCtl.text.trim();
    final tags = tagsCtl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    nameCtl.dispose();
    tagsCtl.dispose();
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.patch('/api/rooms/${widget.roomId}', {'name': name, 'tags': tags}));
    final room = mapOf(r?['room']);
    if (room != null && mounted) setState(() => _room = {...?_room, ...room});
  }

  // ---------- Oda araçları (kayar pencere) ----------
  bool get _isOwnerOrCohost => _myRole == 'owner' || _myRole == 'cohost';

  Future<bool> _patchRoom(Map<String, dynamic> body) async {
    final r = await guard(context, () => Api.patch('/api/rooms/${widget.roomId}', body));
    final room = mapOf(r?['room']);
    if (room != null && mounted) setState(() => _room = {...?_room, ...room});
    return room != null;
  }

  Future<void> _micMode() async {
    final n = await showMicModeSheet(context, current: _seatCount);
    if (n == null || n == _seatCount || !mounted) return;
    if (n < _seatCount && !await confirm(context, 'Koltuk sayısı $n olacak. Fazla koltuklardakiler dinleyiciye iner. Devam edilsin mi?', action: 'Değiştir')) return;
    if (!mounted) return;
    if (await _patchRoom({'seatCount': n}) && mounted) toast(context, 'Mikrofon modu: $n mikrofon.');
  }

  Future<void> _shareRoom() async {
    final code = _room?['joinCode']?.toString();
    final name = (_room?['name'] ?? widget.initialName).toString();
    await Clipboard.setData(ClipboardData(text: '🎙 TR Live — "$name" odasına gel!${code != null ? '\nOda kodu: $code' : ''}'));
    if (mounted) toast(context, 'Oda daveti kopyalandı. İstediğin yere yapıştırıp paylaş.');
  }

  Future<void> _effectsAndSound() async {
    var on = GiftRibbonOverlay.effectsOn;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('Efekt ve Ses'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              title: const Text('Hediye ve giriş efektleri'),
              subtitle: const Text('Yalnızca bu cihazda geçerli.'),
              value: on,
              onChanged: (v) {
                setS(() => on = v);
                GiftRibbonOverlay.effectsOn = v;
              },
            ),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
        ),
      ),
    );
  }

  Future<void> _roomPassword() async {
    final ctl = TextEditingController();
    final locked = _room?['locked'] == true;
    final res = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(locked ? 'Oda kilidi (açık)' : 'Oda kilidi'),
        content: TextField(controller: ctl, obscureText: true, maxLength: 12, decoration: InputDecoration(labelText: locked ? 'Yeni şifre' : 'Oda şifresi (4-12 karakter)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          if (locked) TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Kilidi kaldır')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Kaydet')),
        ],
      ),
    );
    ctl.dispose();
    if (res == null || !mounted) return;
    if (res.isNotEmpty && res.length < 4) return toast(context, 'Şifre en az 4 karakter olmalı.', error: true);
    if (res.isEmpty && !locked) return;
    if (await _patchRoom({'password': res.isEmpty ? null : res}) && mounted) toast(context, res.isEmpty ? 'Oda kilidi kaldırıldı.' : 'Oda şifreyle kilitlendi.');
  }

  Future<void> _roomThemes() async {
    var theme = (_room?['theme'] ?? 'default').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('Özel Temalar'),
          content: SingleChildScrollView(child: ThemePicker(value: theme, onChanged: (v) => setS(() => theme = v))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Uygula')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) await _patchRoom({'theme': theme});
  }

  Future<void> _toggleHidden() async {
    final hide = _room?['hidden'] != true;
    if (!await confirm(context, hide ? 'Oda listeden gizlensin mi? Yalnızca davet koduyla girilebilir.' : 'Oda herkese açık listeye geri dönsün mü?', action: hide ? 'Gizle' : 'Göster')) return;
    if (!mounted) return;
    if (await _patchRoom({'hidden': hide}) && mounted) {
      final code = _room?['joinCode']?.toString();
      toast(context, hide ? 'Oda gizlendi.${code != null ? ' Kod: $code' : ''}' : 'Oda herkese açıldı.');
    }
  }

  void _openTools() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) {
        void run(VoidCallback f) {
          Navigator.pop(sheet);
          f();
        }

        void need(bool ok, VoidCallback f) {
          if (ok) return run(f);
          toast(context, 'Bu aracı kullanma yetkiniz yok.', error: true);
        }

        void soon(String what) {
          Navigator.pop(sheet);
          toast(context, '$what çok yakında.');
        }

        Widget feature(IconData icon, String label, VoidCallback onTap, {Color? color}) => InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white12)),
                    child: Icon(icon, size: 30, color: color ?? Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.15)),
                ]),
              ),
            );

        final chatOn = _room?['chatEnabled'] != false;
        final hidden = _room?['hidden'] == true;
        final locked = _room?['locked'] == true;
        final pkFree = _pk == null || !['pending', 'active'].contains(_pk!['status']);
        final tools = <Widget>[
          feature(Icons.share, 'Yayını\nPaylaş', () => run(_shareRoom)),
          feature(Icons.graphic_eq, 'Efekt\nve Ses', () => run(_effectsAndSound)),
          feature(chatOn ? Icons.speaker_notes_off : Icons.chat, chatOn ? 'Sohbet\nYasağı' : 'Sohbeti\nAç', () => need(_isOwnerOrCohost, () => _patchRoom({'chatEnabled': !chatOn})), color: chatOn ? null : Colors.greenAccent),
          feature(Icons.task_alt, 'Günlük\nGörev', () => soon('Günlük görevler')),
          feature(Icons.library_music, 'Müzik\nSeç', () => run(_openMusic)),
          feature(Icons.cleaning_services, 'Sohbet\nTemizleme', () => need(_isManager, _clearChat)),
          feature(locked ? Icons.lock : Icons.lock_open, 'Oda\nKilidi', () => need(_myRole == 'owner', _roomPassword), color: locked ? Colors.orangeAccent : null),
          feature(Icons.palette, 'Özel\nTemalar', () => need(_isOwnerOrCohost, _roomThemes)),
          feature(hidden ? Icons.visibility_off : Icons.visibility, 'Oda\nGizleme', () => need(_myRole == 'owner', _toggleHidden), color: hidden ? Colors.orangeAccent : null),
          feature(Icons.mic_external_on, 'Mikrofon\nModu', () => need(_isOwnerOrCohost, _micMode)),
          feature(Icons.settings, 'Oda\nAyarları', () => need(_isOwnerOrCohost, _roomSettings)),
        ];
        return DraggableScrollableSheet(
          initialChildSize: 0.62,
          minChildSize: 0.3,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scroll) => Container(
            decoration: const BoxDecoration(color: Color(0xFF1B1B1F), borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 10, 16, 24), children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              Row(children: [
                const Expanded(child: Text('İnteraktif Özellikler', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(onPressed: () => Navigator.pop(sheet), icon: const Icon(Icons.close)),
              ]),
              Wrap(spacing: 18, runSpacing: 4, children: [
                if (_myRole == 'owner') feature(Icons.sports_mma, 'PK', () => pkFree ? run(() => showPkChallengeSheet(context, roomId: widget.roomId)) : toast(context, 'Zaten bir PK sürüyor.', error: true), color: Colors.redAccent),
                feature(Icons.casino, 'Oyunlar\n(Ludo)', () => run(_openGames), color: Colors.lightBlueAccent),
                feature(Icons.redeem, 'Şanslı\nÇanta', () => soon('Şanslı çanta'), color: Colors.redAccent),
              ]),
              const SizedBox(height: 10),
              const Text('Temel Araçlar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              LayoutBuilder(builder: (context, box) {
                final per = (box.maxWidth / 84).floor().clamp(3, 6);
                final w = box.maxWidth / per;
                return Wrap(runSpacing: 6, children: [for (final t in tools) SizedBox(width: w, child: t)]);
              }),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _roomSettings() async {
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
              const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Oda adı ve etiketleri için oda adına dokunun.', style: TextStyle(color: Colors.white54, fontSize: 12))),
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
    final pw = pwCtl.text.trim();
    final img = imgCtl.text.trim();
    pwCtl.dispose();
    imgCtl.dispose();
    if (ok != true || !mounted) return;
    final prevImg = (_room?['themeImageUrl'] ?? '').toString();
    final r = await guard(context, () => Api.patch('/api/rooms/${widget.roomId}', {
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
            ? const Center(child: Text('Henüz mesaj yok.', style: TextStyle(color: Colors.white54)))
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
        const Padding(padding: EdgeInsets.all(8), child: Text('Bu odada yazılı sohbet kapalı.', style: TextStyle(color: Colors.white54))),
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

  /// Oda içi kullanıcı kartı (Figma): büyük avatar, rozetler, Yakın Arkadaşlarım, Madalyalar, yetkiye göre işlem düğmeleri.
  /// Yönetim düğmeleri yalnızca yetkisi olana görünür; normal kullanıcı yalnızca Etiketle / Hediye / Takip görür.
  void _memberSheet(Map<String, dynamic> m) {
    final userId = m['userId'].toString();
    final user = mapOf(m['user']);
    final isSelf = userId == Session.id;
    final role = (m['role'] ?? 'user').toString();
    final seat = m['seatIndex'] == null ? null : (m['seatIndex'] as num).toInt();
    // Yetkiler: kendi rolüm hedefin rolünden yüksek olmalı (oda sahibine dokunulamaz).
    final canMod = !isSelf && _canModerate(role);
    final canRole = !isSelf && (_myRole == 'owner' || _myRole == 'cohost') && role != 'owner' && (_myRole == 'owner' || role != 'cohost');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) {
        void close() => Navigator.pop(c);
        Widget action(IconData icon, String label, VoidCallback onTap, {Color color = Pal.amber}) => Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 22, backgroundColor: color, child: Icon(icon, color: Colors.black87, size: 24)),
                    const SizedBox(height: 4),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
            );
        Widget bigAction(IconData icon, String label, VoidCallback onTap) => Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: Pal.amber, size: 34),
                    const SizedBox(height: 2),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
            );
        return FutureBuilder<List<Map<String, dynamic>?>>(
          future: Future.wait([
            Api.get('/api/users/$userId').then<Map<String, dynamic>?>((r) => mapOf(r['profile'])).catchError((_) => null),
            Api.get('/api/users/$userId/card').then<Map<String, dynamic>?>((r) => r).catchError((_) => null),
          ]),
          builder: (context, snap) {
            final profile = snap.data?[0];
            final card = snap.data?[1];
            final supporters = listOf(card?['supporters']);
            final medals = listOf(card?['medals']);
            var following = profile?['isFollowing'] == true;
            final family = mapOf(profile?['family']);
            final username = (profile?['username'] ?? user?['username'] ?? '').toString();
            return StatefulBuilder(
              builder: (context, setS) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                    Container(
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
                      decoration: const BoxDecoration(color: Color(0xFF26262B), borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 52, 16, 0),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text((user?['displayName'] ?? '').toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            _pill('LV${user?['coinLevel'] ?? 1}', Pal.pink, icon: Icons.star),
                            _pill('Hediye ${user?['giftLevel'] ?? 1}', Pal.purple, icon: Icons.diamond),
                            if (user?['wipLevel'] != null) _pill('WIP ${user?['wipLevel']}', Pal.amber),
                            if (role != 'user') _pill(_roleLabels[role] ?? role, Pal.cyan),
                            if (family != null) _pill('${family['name']}', Pal.red),
                            if (seat != null) _pill('${seat + 1}. koltuk', Colors.white24),
                          ]),
                          const SizedBox(height: 8),
                          if (username.isNotEmpty)
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: username));
                                toast(context, 'Kimlik kopyalandı.');
                              },
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('ID: $username', style: const TextStyle(color: Colors.white70)),
                                const SizedBox(width: 4),
                                const Icon(Icons.copy, size: 14, color: Colors.white54),
                              ]),
                            ),
                          const SizedBox(height: 10),
                          const Text('Yakın Arkadaşlarım', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          if (snap.connectionState != ConnectionState.done)
                            const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                          else if (supporters.isEmpty)
                            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Henüz yok.', style: TextStyle(color: Colors.white54)))
                          else
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              for (final s in supporters)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 5),
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Pal.purple, width: 2)),
                                      child: UserAvatar(user: mapOf(s['user']), radius: 24),
                                    ),
                                    const SizedBox(height: 3),
                                    _pill('LV${mapOf(s['user'])?['coinLevel'] ?? 1}', Pal.purple),
                                  ]),
                                ),
                            ]),
                          const SizedBox(height: 12),
                          Container(
                            height: 64,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(border: Border.all(color: Pal.amber), borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              const Text('Madalyalar', style: TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: medals.isEmpty
                                    ? const Align(alignment: Alignment.centerRight, child: Text('Henüz yok', style: TextStyle(color: Colors.white54, fontSize: 12)))
                                    : ListView(scrollDirection: Axis.horizontal, reverse: true, children: [
                                        for (final md in medals)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 6),
                                            child: Tooltip(
                                              message: (md['name'] ?? '').toString(),
                                              child: Api.absoluteUrl(md['assetUrl'] as String?) != null
                                                  ? Image.network(Api.absoluteUrl(md['assetUrl'] as String?)!, width: 52, height: 52, errorBuilder: (_, __, ___) => const Icon(Icons.military_tech, color: Pal.amber, size: 40))
                                                  : const Icon(Icons.military_tech, color: Pal.amber, size: 40),
                                            ),
                                          ),
                                      ]),
                              ),
                            ]),
                          ),
                          // Yönetim düğmeleri: yalnızca yetkili olana görünür.
                          if (canMod || canRole) ...[
                            const SizedBox(height: 10),
                            Row(children: [
                              if (canRole)
                                action(Icons.manage_accounts, 'Yönetici', () {
                                  close();
                                  _roleChoice(userId, role);
                                }),
                              if (canMod)
                                seat != null
                                    ? action(Icons.mic_off, 'Mic Kapat', () { close(); _moderate(userId, 'mic-off'); }, color: Colors.white70)
                                    : action(Icons.mic, 'Mic Aç', () { close(); _moderate(userId, 'mic-invite', body: {}); }),
                              if (canMod) action(Icons.comments_disabled, 'Sohbet', () { close(); _muteChoice(userId); }),
                              if (canMod && seat != null) action(Icons.event_seat, 'Koltuk', () { close(); _moderate(userId, 'mic-off'); _lockSeat(seat, true); }),
                              if (canMod) action(Icons.exit_to_app, 'Odadan At', () async {
                                close();
                                if (await confirm(this.context, '${user?['displayName'] ?? 'Kullanıcı'} odadan atılsın mı?', action: 'At')) _moderate(userId, 'kick');
                              }),
                            ]),
                          ],
                          const SizedBox(height: 8),
                          const Divider(height: 1, color: Colors.white12),
                          Row(children: [
                            bigAction(Icons.alternate_email, 'Etiketle', () {
                              close();
                              final name = (user?['displayName'] ?? '').toString();
                              _chatCtl.text = '${_chatCtl.text}@$name ';
                              _chatCtl.selection = TextSelection.collapsed(offset: _chatCtl.text.length);
                            }),
                            bigAction(Icons.card_giftcard, 'Hediye Gönder', () {
                              close();
                              _openGifts(userId);
                            }),
                            if (!isSelf)
                              bigAction(following ? Icons.check : Icons.add, following ? 'Takipte' : 'Takip Et', () async {
                                final ok = await guard<bool>(this.context, () async {
                                  if (following) {
                                    await Api.delete('/api/users/$userId/follow');
                                  } else {
                                    await Api.post('/api/users/$userId/follow');
                                  }
                                  return true;
                                });
                                if (ok == true) setS(() => following = !following);
                              })
                            else
                              bigAction(Icons.person, 'Profilim', () {
                                close();
                                Navigator.push(this.context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
                              }),
                          ]),
                        ]),
                      ),
                    ),
                    // Üstte taşan büyük avatar (dokununca tam profil)
                    Positioned(
                      top: -48,
                      child: GestureDetector(
                        onTap: () {
                          close();
                          Navigator.push(this.context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
                        },
                        child: UserAvatar(user: user, radius: 48),
                      ),
                    ),
                    if (!isSelf)
                      Positioned(
                        top: 10,
                        left: 12,
                        child: IconButton(
                          tooltip: 'Şikâyet / engelle',
                          icon: const Icon(Icons.error_outline, color: Pal.amber, size: 30),
                          onPressed: () {
                            close();
                            _reportMenu(userId, (user?['displayName'] ?? 'Kullanıcı').toString(), canMod);
                          },
                        ),
                      ),
                    Positioned(
                      top: 10,
                      right: 12,
                      child: IconButton(tooltip: 'Kapat', icon: const CircleAvatar(radius: 16, backgroundColor: Pal.amber, child: Icon(Icons.close, color: Colors.black, size: 20)), onPressed: close),
                    ),
                  ]),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _pill(String text, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: Colors.white), const SizedBox(width: 3)],
          Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      );

  void _roleChoice(String userId, String role) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (role != 'moderator') ListTile(leading: const Icon(Icons.shield), title: const Text('Moderatör yap'), onTap: () { Navigator.pop(c); _moderate(userId, 'role', body: {'role': 'moderator'}); }),
          if (_myRole == 'owner' && role != 'cohost') ListTile(leading: const Icon(Icons.stars), title: const Text('Yardımcı sahip yap'), onTap: () { Navigator.pop(c); _moderate(userId, 'role', body: {'role': 'cohost'}); }),
          if (role != 'user') ListTile(leading: const Icon(Icons.remove_moderator), title: const Text('Yetkiyi al'), onTap: () { Navigator.pop(c); _moderate(userId, 'role', body: {'role': 'user'}); }),
        ]),
      ),
    );
  }

  void _muteChoice(String userId) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final mins in const [10, 60, 1440])
            ListTile(
              leading: const Icon(Icons.comments_disabled),
              title: Text('Sohbette sustur (${mins == 1440 ? '1 gün' : (mins == 60 ? '1 saat' : '$mins dk')})'),
              onTap: () { Navigator.pop(c); _moderate(userId, 'chat-mute', body: {'minutes': mins}); },
            ),
          ListTile(leading: const Icon(Icons.chat), title: const Text('Susturmayı kaldır'), onTap: () { Navigator.pop(c); _moderate(userId, 'chat-mute', body: {'minutes': 0}); }),
        ]),
      ),
    );
  }

  void _reportMenu(String userId, String name, bool canRoomBlock) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('Şikâyet et'), onTap: () { Navigator.pop(c); reportDialog(context, kind: 'user', targetUserId: userId, roomId: widget.roomId); }),
          ListTile(leading: const Icon(Icons.person_off_outlined), title: const Text('Kullanıcıyı engelle'), onTap: () { Navigator.pop(c); blockUserDialog(context, userId, name); }),
          if (canRoomBlock) ListTile(leading: const Icon(Icons.block), title: const Text('Bu odadan engelle'), onTap: () { Navigator.pop(c); _moderate(userId, 'block'); }),
        ]),
      ),
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
      final reserved = index == 0 && _myRole != 'owner';
      final locked = _lockedSeats.contains(index);
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: reserved
            ? null
            : () {
                if (index == 0) {
                  _takeMic(0); // oda sahibi kendi koltuğuna geri döner
                } else if (_canSeatManage) {
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
            child: Text('💎 ${fmtNumber(_scores[userId] ?? 0)}', style: const TextStyle(fontSize: 11, color: Colors.amberAccent)),
          ),
      ]),
    );
  }

  Widget _seatGrid() {
    final bySeat = <int, Map<String, dynamic>>{
      for (final m in _members)
        if (m['seatIndex'] != null) (m['seatIndex'] as num).toInt(): m,
    };
    final rows = seatRows(_seatCount);
    final maxCols = rows.reduce((a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: LayoutBuilder(builder: (context, box) {
        // Her koltuk aynı genişlikte; kısa satırlar ortalanır (Figma yerleşimi).
        final cw = (box.maxWidth / maxCols).clamp(0.0, 120.0);
        var next = 0;
        return Column(children: [
          for (final count in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var k = 0; k < count; k++)
                  Builder(builder: (_) {
                    final i = next++;
                    return SizedBox(width: cw, child: _seatTile(i, bySeat[i]));
                  }),
              ]),
            ),
        ]);
      }),
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
                  Text((mapOf(m['user'])?['displayName'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
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
          ] else if (_noFreeSeat && !_isManager)
            FilledButton.tonalIcon(
              onPressed: _toggleQueue,
              icon: Icon(_inQueue ? Icons.hourglass_bottom : Icons.queue),
              label: Text(_inQueue ? 'Sıradan çık (${_queue.indexOf(Session.id) + 1}.)' : 'Sıraya gir${_queue.isEmpty ? '' : ' (${_queue.length})'}'),
            )
          else
            FilledButton.icon(onPressed: () => _takeMic(), icon: const Icon(Icons.mic), label: const Text('Mikrofona çık')),
          const Spacer(),
          IconButton(tooltip: 'Oda araçları', onPressed: _openTools, icon: const Icon(Icons.apps_rounded)),
          IconButton.filled(tooltip: 'Hediye gönder', onPressed: _members.isEmpty ? null : () => _openGifts(), icon: const Icon(Icons.card_giftcard)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    RoomDock.myRole = _myRole;
    return ValueListenableBuilder<bool>(
      valueListenable: RoomDock.minimized,
      builder: (context, minimized, _) => PopScope(
      canPop: minimized, // küçültülmüşken geri tuşu ana ekrana aittir; açıkken odayı küçültür
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) RoomDock.minimize();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(children: [
            if (_room?['hidden'] == true) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.visibility_off, size: 18)),
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _roomInfo,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text((_room?['name'] ?? widget.initialName).toString(), overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.arrow_drop_down),
                  ]),
                ),
              ),
            ),
          ]),
          leading: IconButton(tooltip: 'Odayı küçült', icon: const Icon(Icons.keyboard_arrow_down), onPressed: RoomDock.minimize),
          actions: [
            if (_room?['ownerId']?.toString() != Session.id)
              IconButton(tooltip: _fav ? 'Favorilerden çıkar' : 'Favorilere ekle', icon: Icon(_fav ? Icons.star : Icons.star_border, color: _fav ? Colors.amber : null), onPressed: _toggleFavorite),
            IconButton(tooltip: 'Odadan ayrıl', icon: const Icon(Icons.logout), onPressed: _onBack),
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
                  Expanded(
                    flex: 5,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNote,
                      child: ListView(physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()), children: [_seatGrid(), _audience()]),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(flex: 3, child: _chatPanel()),
                  _bottomBar(),
                ]),
              )),
      ),
      ),
    );
  }
}
