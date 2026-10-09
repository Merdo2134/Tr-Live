import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/anim_asset.dart';
import 'family_screen.dart';
import '../widgets/entrance_strip.dart';
import '../widgets/lucky_bag.dart';
import '../widgets/room_sheets.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../services/api.dart';
import '../widgets/music_bubble.dart';
import '../services/background_service.dart';
import '../services/inbox_service.dart';
import '../services/media_cache.dart';
import '../services/music_service.dart';
import '../services/room_dock.dart';
import '../services/session.dart';
import '../services/socket_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/crown_icon.dart';
import '../widgets/gift_ribbon.dart';
import '../widgets/safety_actions.dart';
import '../widgets/pk_banner.dart';
import '../widgets/room_theme.dart';
import '../widgets/seat_picker.dart';
import 'gift_sheet.dart';
import 'ludo_screen.dart';
import 'pk_sheet.dart';
import 'music_sheet.dart';
import 'messages_screen.dart';
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
  final Map<String, GlobalKey> _seatKeys = {}; // koltuk avatarı konumları (hediye uçuşu için)
  final GlobalKey _stageKey = GlobalKey();
  final GlobalKey _viewersKey = GlobalKey();
  final List<_GiftFlightData> _flights = [];
  int _flightSeq = 0;
  Map<String, dynamic>? _myFamily; // ailesi olanlarda üst köşede kısayol
  Map<String, dynamic> _me = {};
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  bool _joined = false;
  bool _closing = false;
  bool _rejoining = false;
  Timer? _beat;

  lk.Room? _lk;
  bool _lkConnecting = false;
  int _lkRetries = 0; // ses bağlantısı koparsa artan bekleme ile yeniden bağlanılır
  Timer? _lkTick; // LiveKit değişikliklerinde tüm odayı saniyede onlarca kez yeniden çizmemek için
  String? _password; // kilitli odada yeniden katılırken gerekir
  String? _lkError;
  bool _micOn = true;
  bool _camOn = true;

  StreamSubscription? _sub;

  final List<Map<String, dynamic>> _messages = [];
  final _chatCtl = TextEditingController();
  final _chatScroll = ScrollController();
  bool _sending = false;
  bool _chatMuted = false;
  bool _inputOpen = false;
  bool _roomMuted = false;

  // Oda içi sayı tahtası (kullanıcı → alınan toplam Coin) ve PK durumu
  final Map<String, String> _scores = {};
  Map<String, dynamic>? _pk;
  bool _inviteOpen = false;

  bool get _isManager => _myRole == 'owner' || _myRole == 'cohost' || _myRole == 'moderator';
  bool get _chatOpen => _room?['chatEnabled'] != false || _isManager;

  bool get _isVideo => _room?['roomType'] == 'video';
  final EntranceQueue _entrance = EntranceQueue();
  final List<Map<String, dynamic>> _bags = []; // bu odadaki açık şanslı çantalar
  int get _seatCount => (_room?['seatCount'] as num?)?.toInt() ?? 8;
  String get _myRole => (_me['role'] ?? 'user').toString();
  bool get _onSeat => _me['microphone'] == true;

  @override
  void initState() {
    super.initState();
    _sub = SocketService.instance.events.listen(_onEvent);
    RoomDock.exitHandler = _onBack;
    WidgetsBinding.instance.addObserver(this);
    MediaCache.warmGifts();
    Api.get('/api/families/mine').then((r) {
      if (mounted) setState(() => _myFamily = mapOf(r['family']));
    }).catchError((_) {});
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
    _resync();
  }

  /// Bağlantı koptuktan / uygulama arka plandan döndükten sonra kaçırılan olayları telafi eder:
  /// koltuklar, üyeler, sohbet, puanlar, PK, çantalar ve müzik sunucudan yeniden alınır.
  Future<void> _resync() async {
    if (!_joined || _closing || !mounted) return;
    SocketService.instance.subscribeRoom(widget.roomId);
    try {
      await _loadMembers();
    } catch (_) {/* ağ yoksa bir sonraki sinyalde */}
    if (!mounted || _closing) return;
    _loadMessages();
    _loadExtras();
    MusicService.instance.refresh();
    if (_lk == null && !_lkConnecting) _connectLivekit();
  }

  @override
  void dispose() {
    _beat?.cancel();
    _lkTick?.cancel();
    _entrance.dispose();
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
      room.disconnect().whenComplete(() => room.dispose()).catchError((_) {});
    }
    super.dispose();
  }

  // ---------- Giriş / çıkış ----------
  Future<void> _enter() async {
    try {
      String? password;
      if (widget.locked) {
        await WidgetsBinding.instance.endOfFrame; // initState içinde hemen diyalog açılmasın (ilk kare çizilsin)
        if (!mounted) return;
        password = await askText(context, 'Oda şifresi', obscure: true);
        if (password == null) {
          if (mounted) RoomDock.close();
          return;
        }
      }
      _password = password;
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
      // Kendi giriş şeridim (WIP seviyeme göre) de odaya girerken görünür.
      final meRow = _members.where((m) => m['userId']?.toString() == Session.id);
      final meUser = meRow.isEmpty ? null : mapOf(meRow.first['user']);
      if (meUser != null && GiftRibbonOverlay.effectsOn) _entrance.add(meUser);
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
      final lb = await Api.get('/api/rooms/${widget.roomId}/lucky-bags');
      if (mounted) setState(() => _bags..clear()..addAll(listOf(lb['bags'])));
    } catch (_) {}
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
    if (_inQueue) toast(context, _micRequest ? 'Mikrofon isteğin gönderildi. Yetkili onaylayınca mikrofona çıkabilirsin.' : 'Sıraya girdiniz. Sıra size gelince haber verilir.');
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

  Future<void> _loadMembers() async {
    final r = await Api.get('/api/rooms/${widget.roomId}/members');
    if (!mounted) return;
    final list = listOf(r['members']);
    setState(() => _members = list);
    if (!_joined || _closing) return;
    // Kendi durumumu da sunucuyla eşitle (bağlantı kopukken mikrofondan indirilmiş / rolüm değişmiş olabilir).
    final mine = list.where((m) => m['userId']?.toString() == Session.id).firstOrNull;
    if (mine == null) {
      _rejoin(); // sunucu bizi odadan çıkarmış (ör. uzun bağlantı kopukluğu): yeniden katıl
      return;
    }
    final wasOnSeat = _onSeat;
    setState(() => _me = {..._me, 'role': mine['role'], 'seatIndex': mine['seatIndex'], 'microphone': mine['microphone']});
    if (wasOnSeat != _onSeat) {
      BackgroundService.instance.micChanged(_onSeat);
      _syncPublish();
    }
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
      _scrollChatToEnd(force: true);
    } catch (_) {/* sohbet yüklenemese de oda çalışır */}
  }

  /// Sohbetin sonuna kaydırır. Kullanıcı yukarı kaydırıp eski mesajları okuyorsa ([force] yoksa) yerinden oynatmaz.
  void _scrollChatToEnd({bool force = false}) {
    if (!force && _chatScroll.hasClients && _chatScroll.position.extentAfter > 120) return;
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
      final r = await Api.post('/api/rooms/${widget.roomId}/join', {if (_password != null) 'password': _password, if (widget.code != null) 'code': widget.code});
      if (!mounted || _closing) {
        Api.post('/api/rooms/${widget.roomId}/leave').catchError((_) => <String, dynamic>{});
        return;
      }
      _joined = true;
      final me = mapOf(r['me']);
      if (me != null) _me = me;
      SocketService.instance.subscribeRoom(widget.roomId);
      await _loadMembers();
      if (!mounted) return;
      if (_lk == null && !_lkConnecting) _connectLivekit();
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
    // Oda açıkken üstünde duran pencereler (Ludo, alt pencereler, diyaloglar) kapanmış odanın üstünde kalmasın.
    if (!RoomDock.minimized.value) Navigator.of(context).popUntil((r) => r.isFirst);
    RoomDock.close();
  }

  Future<void> _onBack() async {
    if (_closing) return;
    if (_myRole == 'owner') {
      final ok = await confirm(context, 'Odadan ayrılırsanız oda kapanır. Devam edilsin mi?', action: 'Odayı kapat');
      if (!ok || !mounted) return;
    }
    // Ağ yavaşsa çıkış düğmesi 20 sn donmasın: oda hemen kapanır, "leave" isteğini dispose() gönderir.
    _closing = true;
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
    if (type == 'connected') {
      _resync(); // soket yeniden bağlandı: arada kaçan olayları telafi et
      return;
    }
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
          if (ok == true && mounted) _takeMic(seat, true);
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
        _addSystemMessage('Sohbetler temizlendi.', color: const Color(0xFF34D399));
        break;
      case 'lucky_bag_new':
        final nb = mapOf(e['bag']);
        if (nb != null && e['roomId']?.toString() == widget.roomId) setState(() => _bags.add(nb));
        break;
      case 'lucky_bag_claimed':
        setState(() {
          final i = _bags.indexWhere((b) => b['id'] == e['bagId']);
          if (i >= 0) {
            _bags[i] = {..._bags[i], 'claimed': e['claimed']};
            if (e['done'] == true) _bags.removeAt(i);
          }
        });
        break;
      case 'lucky_bag_ended':
        setState(() => _bags.removeWhere((b) => b['id'] == e['bagId']));
        break;
      case 'room_member_joined':
        final u = mapOf(e['user']);
        if (u != null && !_members.any((m) => m['userId'] == u['id'])) {
          setState(() => _members.add({'userId': u['id'], 'role': 'user', 'microphone': false, 'seatIndex': null, 'user': u}));
        }
        if (u != null && u['id']?.toString() != Session.id && GiftRibbonOverlay.effectsOn) _entrance.add(u);
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
          _scrollChatToEnd(force: mapOf(e['user'])?['id']?.toString() == Session.id);
        }
        break;
      case 'room_message_deleted':
        setState(() => _messages.removeWhere((m) => m['id'] == e['messageId']));
        break;
      case 'room_chat_muted':
        setState(() => _chatMuted = (e['minutes'] as num? ?? 0) > 0);
        toast(context, _chatMuted ? 'Bu odada sohbette susturuldunuz.' : 'Sohbet yasağınız kaldırıldı.');
        break;
      case 'room_gift':
        _flyGift(e);
        break;
      case 'room_settings':
        if (e['seatCount'] != null && e['seatCount'] != _room?['seatCount']) {
          _addSystemMessage('Oda sahibi yeni bir mikrofon moduna geçmiştir. Geçerli mikrofon konumu değiştirilecektir.');
        }
        setState(() => _room = {
              ...?_room,
              'name': e['name'], 'tags': e['tags'], 'locked': e['locked'], 'chatEnabled': e['chatEnabled'],
              'theme': e['theme'], 'themeImageUrl': e['themeImageUrl'], 'scoreboardEnabled': e['scoreboardEnabled'], 'hidden': e['hidden'],
              if (e['seatCount'] != null) 'seatCount': e['seatCount'],
              if (e['micRequest'] != null) 'micRequest': e['micRequest'],
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
    if (_roomMuted) _applyRoomSound();
    final r = _lk;
    // Ses sunucusu bağlantısı koptuysa (ağ değişimi, sunucudan çıkarılma sonrası yeniden katılma) yeniden kur.
    if (r != null && r.connectionState == lk.ConnectionState.disconnected && !_lkConnecting && !_closing && mounted) {
      _lk = null;
      r.removeListener(_onLkChanged);
      r.disconnect().whenComplete(() => r.dispose()).catchError((_) {});
      final wait = Duration(seconds: 2 << _lkRetries.clamp(0, 4)); // 2, 4, 8, 16, 32 sn
      _lkRetries++;
      Future.delayed(wait, () {
        if (mounted && !_closing && _joined && _lk == null) _connectLivekit();
      });
    }
    // Konuşma göstergeleri vb. için yeniden çizim: en fazla 200 ms'de bir.
    if (_lkTick?.isActive ?? false) return;
    _lkTick = Timer(const Duration(milliseconds: 200), () {
      _lkTick = null;
      if (mounted) setState(() {});
    });
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
      _lkRetries = 0;
      await _syncPublish();
    } catch (e) {
      if (room != null) {
        room.removeListener(_onLkChanged);
        room.disconnect().whenComplete(() => room!.dispose()).catchError((_) {});
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
  bool get _micRequest => _room?['micRequest'] == true;

  Future<void> _takeMic([int? seat, bool invited = false]) async {
    // İstek modu: yetkili olmayan kullanıcı koltuğa dokununca istek gönderir (davetle gelirse doğrudan çıkar).
    if (_micRequest && !invited && !_onSeat && !_canSeatManage) {
      if (_inQueue) {
        toast(context, 'İsteğin zaten gönderildi; yetkili onayını bekle.');
      } else {
        await _toggleQueue();
      }
      return;
    }
    final r = await guard(context, () => Api.post('/api/rooms/${widget.roomId}/mic/take', {if (seat != null) 'seatIndex': seat}));
    if (r == null || !mounted) return;
    setState(() => _applySeat(Session.id, (r['seatIndex'] as num?)?.toInt(), true));
  }

  Future<void> _leaveMic() async {
    final r = await guard(context, () => Api.post('/api/rooms/${widget.roomId}/mic/leave'));
    if (r == null || !mounted) return;
    setState(() => _applySeat(Session.id, null, false));
  }

  /// Yetkili: mikrofon isteklerini onayla (davet gönder) veya reddet.
  void _micRequestsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final list = [for (final id in _queue) _members.where((m) => m['userId'] == id).firstOrNull].whereType<Map<String, dynamic>>().toList();
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Mikrofon istekleri', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Bekleyen istek yok.', style: TextStyle(color: Colors.white54))),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final m in list)
                    ListTile(
                      leading: UserAvatar(user: mapOf(m['user']), radius: 20),
                      title: UserName(user: mapOf(m['user'])),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Reddet',
                          icon: const Icon(Icons.close, color: Colors.redAccent),
                          onPressed: () async {
                            final r = await guard(context, () => Api.delete('/api/rooms/${widget.roomId}/mic/queue/${m['userId']}'));
                            if (r != null && mounted) setState(() => _queue = ((r['queue'] as List?) ?? const []).map((x) => x.toString()).toList());
                            if (c.mounted) setS(() {});
                          },
                        ),
                        FilledButton(
                          onPressed: () async {
                            final r = await guard(context, () => Api.post('/api/rooms/${widget.roomId}/members/${m['userId']}/mic-invite', {}));
                            if (r != null && mounted) toast(context, 'Mikrofona davet gönderildi.');
                          },
                          child: const Text('Onayla'),
                        ),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
            ]),
          );
        },
      ),
    );
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
    final owner = _members.where((m) => m['role'] == 'owner');
    showRoomCard(
      context,
      room: _room ?? const {},
      owner: owner.isEmpty ? null : mapOf(owner.first['user']),
      managers: managers,
      canEdit: canEdit,
      onEdit: () => _roomEdit(managers),
      onSettings: _roomSettings,
    );
  }

  Future<void> _roomEdit(List<Map<String, dynamic>> managers) async {
    final room = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(builder: (_) => RoomEditScreen(roomId: widget.roomId, room: _room ?? const {}, managers: managers, isOwner: _myRole == 'owner')),
    );
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

  /// Hediye atılınca hediyenin ikonu (png) gönderenden alıcıların koltuğuna uçar; ardından tam ekran animasyon oynar (Yoho).
  void _flyGift(Map<String, dynamic> e) {
    // Oda küçültülmüşken / uygulama arka plandayken animasyonlar donar; birikip açılışta yüzlercesi birden oynamasın.
    final ls = WidgetsBinding.instance.lifecycleState;
    if (RoomDock.minimized.value || (ls != null && ls != AppLifecycleState.resumed) || _flights.length > 40) return;
    final gift = mapOf(e['gift']);
    final icon = Api.absoluteUrl(gift?['iconUrl'] as String?);
    final stage = _stageKey.currentContext?.findRenderObject();
    if (icon == null || stage is! RenderBox || !stage.attached) return;
    Offset? centerOfBox(GlobalKey? key) {
      final box = key?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) return null;
      return stage.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
    }

    Offset? centerOf(String? userId) => userId == null ? null : centerOfBox(_seatKeys[userId]);

    final from = centerOf(mapOf(e['sender'])?['id']?.toString()) ?? Offset(stage.size.width / 2, stage.size.height * 0.86);
    final receivers = e['receivers'] is List ? (e['receivers'] as List) : const [];
    final fresh = <_GiftFlightData>[];
    for (final r in receivers.take(20)) {
      final rid = mapOf(r is Map ? r['user'] : null)?['id']?.toString();
      // Mikrofonda değilse (odadaysa) seyirci sayısı rozetine uçar.
      final to = centerOf(rid) ?? (rid == null ? null : centerOfBox(_viewersKey));
      if (to != null) fresh.add(_GiftFlightData(++_flightSeq, icon, from, to));
    }
    if (fresh.isEmpty) return;
    setState(() => _flights.addAll(fresh));
  }

  /// Mikrofon modu (Yoho): pencere açık kalır; seçim anında uygulanır, istek modu alttaki seçenekle açılıp kapanır.
  Future<void> _micMode() async {
    try {
      await showMicModeSheet(
        context,
        current: _seatCount,
        requestMode: _micRequest,
        onSelect: (n) async {
          final old = _seatCount;
          try {
            final r = await Api.patch('/api/rooms/${widget.roomId}', {'seatCount': n});
            final room = mapOf(r['room']);
            if (!mounted) return false;
            if (n != old && _room?['seatCount'] == old) {
              _addSystemMessage('Oda sahibi yeni bir mikrofon moduna geçmiştir. Geçerli mikrofon konumu değiştirilecektir.');
            }
            setState(() => _room = {...?_room, ...?room, 'seatCount': n});
            await _loadMembers(); // taşan koltuktakiler dinleyiciye inmiş olabilir
            return true;
          } catch (e) {
            if (mounted) toast(context, 'Mikrofon modu değişmedi: ${errorText(e)}', error: true);
            return false;
          }
        },
        onRequestMode: (on) => _patchRoom({'micRequest': on}),
      );
    } catch (e) {
      if (mounted) toast(context, 'Mikrofon modu penceresi açılamadı: $e', error: true);
    }
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
        final queueMode = !_onSeat && !_canSeatManage && (_micRequest || _noFreeSeat);
        final tools = <Widget>[
          feature(_roomMuted ? Icons.volume_off : Icons.volume_up, _roomMuted ? 'Sesi\nAç' : 'Sesi\nKapat', () => run(_toggleRoomSound), color: _roomMuted ? Colors.redAccent : null),
          if (_onSeat && _isVideo)
            feature(_camOn ? Icons.videocam : Icons.videocam_off, 'Kamera', () => run(() {
                  setState(() => _camOn = !_camOn);
                  _syncPublish();
                })),
          if (queueMode)
            feature(_inQueue ? Icons.hourglass_bottom : Icons.front_hand, _inQueue ? (_micRequest ? 'İsteği\nGeri Al' : 'Sıradan\nÇık') : (_micRequest ? 'Mikrofon\nİste' : 'Sıraya\nGir'), () => run(_toggleQueue), color: _inQueue ? Colors.orangeAccent : Colors.greenAccent),
          if (_onSeat) feature(Icons.mic_off, 'Mikrofondan\nİn', () => run(_leaveMic)),
          if (_canSeatManage && _micRequest) feature(Icons.how_to_reg, 'Mikrofon\nİstekleri', () => run(_micRequestsSheet), color: Colors.greenAccent),
          feature(Icons.share, 'Yayını\nPaylaş', () => run(_shareRoom)),
          feature(Icons.graphic_eq, 'Efekt\nve Ses', () => run(_effectsAndSound)),
          if (_isOwnerOrCohost) feature(chatOn ? Icons.speaker_notes_off : Icons.chat, chatOn ? 'Sohbet\nYasağı' : 'Sohbeti\nAç', () => need(_isOwnerOrCohost, () => _patchRoom({'chatEnabled': !chatOn})), color: chatOn ? null : Colors.greenAccent),
          if (_isManager) feature(Icons.library_music, 'Müzik\nSeç', () => run(_openMusic)),
          if (_isManager) feature(Icons.cleaning_services, 'Sohbet\nTemizleme', () => need(_isManager, _clearChat)),
          if (_myRole == 'owner') feature(locked ? Icons.lock : Icons.lock_open, 'Oda\nKilidi', () => need(_myRole == 'owner', _roomPassword), color: locked ? Colors.orangeAccent : null),
          if (_isOwnerOrCohost) feature(Icons.palette, 'Özel\nTemalar', () => need(_isOwnerOrCohost, _roomThemes)),
          if (_myRole == 'owner') feature(hidden ? Icons.visibility_off : Icons.visibility, 'Oda\nGizleme', () => need(_myRole == 'owner', _toggleHidden), color: hidden ? Colors.orangeAccent : null),
          if (_isOwnerOrCohost) feature(Icons.mic_external_on, 'Mikrofon\nModu', () {
            if (!_isOwnerOrCohost) {
              Navigator.pop(sheet);
              toast(context, 'Mikrofon modunu yalnızca oda sahibi ve yardımcı sahip değiştirebilir.', error: true);
              return;
            }
            Navigator.pop(sheet);
            // Alt pencerenin kapanma animasyonu bitmeden yenisini açmak bazı cihazlarda açılmıyor; kısa bekle.
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _micMode();
            });
          }),
          if (_myRole == 'owner') feature(Icons.power_settings_new, 'Odayı\nKapat', () => run(_closeRoom), color: Colors.redAccent),
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
                feature(Icons.redeem, 'Şanslı\nÇanta', () => run(() => showBagSend(context, widget.roomId)), color: Colors.redAccent),
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

  void _openMusic() => showMusicSheet(context, roomId: widget.roomId, canManage: _isManager, canQueue: _onSeat);

  Future<void> _clearChat() async {
    if (!await confirm(context, 'Odadaki tüm sohbet mesajları herkes için silinsin mi?', action: 'Temizle')) return;
    if (!mounted) return;
    await guard(context, () => Api.delete('/api/rooms/${widget.roomId}/messages'));
  }

  void _openGames() => Navigator.push(context, MaterialPageRoute(builder: (_) => LudoScreen(roomId: widget.roomId, canManage: _isManager)));

  /// Renkli saydam sohbet balonu: kullanıcı seviyesine göre renk (Yoho tarzı lacivert taban).
  Color _bubbleColor(Map<String, dynamic>? u) {
    final lvl = (u?['coinLevel'] as num?)?.toInt() ?? 1;
    if (lvl >= 60) return const Color(0x8CB7791F); // altın
    if (lvl >= 45) return const Color(0x8CBE185D); // pembe
    if (lvl >= 30) return const Color(0x8C6D28D9); // mor
    if (lvl >= 20) return const Color(0x8C1D4ED8); // mavi
    if (lvl >= 10) return const Color(0x8C0F766E); // turkuaz
    return const Color(0x8C13285A); // lacivert
  }

  void _addSystemMessage(String text, {Color color = const Color(0xFFFFE27A)}) {
    setState(() {
      _messages.add({'id': 'sys-${DateTime.now().microsecondsSinceEpoch}', 'system': true, 'text': text, 'color': color.toARGB32()});
      if (_messages.length > 200) _messages.removeAt(0);
    });
    _scrollChatToEnd();
  }

  /// Sohbet akışı (Yoho): koltukların altından alt bara kadar, saydam renkli balonlar.
  /// [overlay]: klavye açıkken karartının üstünde balonsuz düz yazı.
  Widget _chatPanel(double w, {bool overlay = false}) {
    if (_messages.isEmpty) return const SizedBox.shrink();
    final maxW = w * 0.78;
    return ListView.builder(
      controller: _chatScroll,
      padding: EdgeInsets.fromLTRB(8, overlay ? 10 : 2, w * 0.2, 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        if (m['system'] == true) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: maxW),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: overlay ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2) : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: overlay ? null : BoxDecoration(color: const Color(0x8C13285A), borderRadius: BorderRadius.circular(12)),
              child: Text((m['text'] ?? '').toString(), style: TextStyle(fontSize: 14.5, height: 1.3, color: Color((m['color'] as int?) ?? 0xFFFFE27A))),
            ),
          );
        }
        final u = mapOf(m['user']);
        final color = parseColor(u?['nameColor'] as String?) ?? Colors.white;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => _messageActions(m),
          onTap: () {
            final uid = u?['id']?.toString();
            final mem = _members.where((x) => x['userId'] == uid);
            if (mem.isNotEmpty) _memberSheet(mem.first);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              UserAvatar(user: u, radius: 17),
              const SizedBox(width: 8),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: WipNameText('${u?['displayName'] ?? ''}', level: (u?['wipLevel'] as num?)?.toInt(), color: color, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    const SizedBox(width: 6),
                    _pill('${u?['coinLevel'] ?? 1}', Pal.pink, icon: Icons.star),
                  ]),
                  const SizedBox(height: 4),
                  Container(
                    constraints: BoxConstraints(maxWidth: maxW - 42),
                    padding: overlay ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: overlay ? null : BoxDecoration(color: _bubbleColor(u), borderRadius: BorderRadius.circular(12)),
                    child: Text((m['text'] ?? '').toString(), style: const TextStyle(fontSize: 15, height: 1.25)),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  void _closeInput() {
    _kbSeen = false;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_inputOpen) setState(() => _inputOpen = false);
  }

  void _openInput() {
    if (!_chatOpen) {
      toast(context, 'Bu odada yazılı sohbet kapalı.', error: true);
      return;
    }
    _kbSeen = false;
    setState(() => _inputOpen = true);
    _scrollChatToEnd(force: true);
  }

  /// Yazı alanı (Yoho): klavyenin hemen üstünde beyaz şerit; boşluğa dokununca kapanır.
  Widget _inputBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Row(children: [
        IconButton(tooltip: 'Kapat', onPressed: _closeInput, icon: const Icon(Icons.keyboard_hide_outlined, color: Colors.black54)),
        Expanded(
          child: TextField(
            controller: _chatCtl,
            autofocus: true,
            maxLength: 300,
            enabled: !_chatMuted,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendChat(),
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: _chatMuted ? 'Sohbette susturuldunuz' : 'Selam...',
              hintStyle: const TextStyle(color: Colors.black38),
              filled: true,
              fillColor: const Color(0xFFF1F2F4),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              suffixIcon: IconButton(onPressed: _chatOpen ? _emojiSheet : null, icon: const Icon(Icons.sentiment_satisfied_alt, color: Colors.black54)),
            ),
          ),
        ),
        IconButton(onPressed: _sending || _chatMuted ? null : _sendChat, icon: const Icon(Icons.send, color: Color(0xFF16A34A))),
      ]),
    );
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
  /// Kendi koltuğuma dokununca (Zula gibi): koltuğu sessize al / koltuktan kalk / iptal.
  void _selfSeatSheet(Map<String, dynamic> m, int index) {
    final user = mapOf(m['user']);
    final roleName = const {'owner': 'Oda Sahibi', 'cohost': 'Yardımcı', 'admin': 'Yönetici'}[(m['role'] ?? '').toString()] ?? 'Üye';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: UserAvatar(user: user, radius: 22),
            title: Text((user?['displayName'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Koltuk #${index + 1} • $roleName'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: Session.id)));
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(_micOn ? Icons.mic_off : Icons.mic),
            title: Text(_micOn ? 'Koltuğu sessize al' : 'Sesi aç'),
            onTap: () {
              Navigator.pop(c);
              setState(() => _micOn = !_micOn);
              _syncPublish();
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Koltuktan Kalk', style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              Navigator.pop(c);
              _leaveMic();
            },
          ),
          ListTile(leading: const Icon(Icons.close), title: const Text('İptal'), onTap: () => Navigator.pop(c)),
        ]),
      ),
    );
  }

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
            final username = (profile?['publicId'] ?? user?['publicId'] ?? profile?['username'] ?? user?['username'] ?? '').toString();
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

  void _membersSheet() => showViewers(context, _members, _memberSheet);

  // ---------- Arayüz ----------
  // Koltuk ölçüleri sahne alanına göre _seatGrid içinde hesaplanır (kaydırma yok; her koltuk modu ekrana sığar).
  bool _showScoreRow = true;
  double? _seatScale; // klavye açılınca koltuklar küçülmesin diye son ölçek saklanır
  bool _kbSeen = false; // klavye geri tuşuyla kapanınca yazı alanı da kapansın
  bool get _seatCompact => _seatCount >= 12; // 12+ modda koltuklar küçük (Yoho: genişliğin ~%10'u)
  double get _seatNameH => _seatCompact ? 14 : 16;
  double get _seatScoreH => 16;
  bool get _scoreOn => _room?['scoreboardEnabled'] != false && _showScoreRow;
  // Bir koltuğun avatar alanı (slot) boyutu satıra göre değişir: üst (oda sahibi) satırı daha büyüktür.
  double _cellH(double slot) => slot + 2 + _seatNameH + (_scoreOn ? _seatScoreH + 2 : 0);

  Widget _seatFrame({required double slotSize, required Widget slot, required Widget name, Widget? score, VoidCallback? onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: _cellH(slotSize),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: slotSize, height: slotSize, child: slot),
          const SizedBox(height: 2),
          SizedBox(height: _seatNameH, child: Center(child: name)),
          if (_scoreOn) ...[const SizedBox(height: 2), SizedBox(height: _seatScoreH, child: Center(child: score ?? const SizedBox.shrink()))],
        ]),
      ),
    );
  }

  void _emptySeatTap(int index, bool reserved, bool locked) {
    if (reserved) return;
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
  }

  Widget _seatTile(int index, Map<String, dynamic>? m, double slotSize) {
    final seatR = (slotSize - 8) / 2;
    if (m == null) {
      final reserved = index == 0 && _myRole != 'owner';
      final locked = _lockedSeats.contains(index);
      return _seatFrame(
        slotSize: slotSize,
        onTap: () => _emptySeatTap(index, reserved, locked),
        slot: Center(
          child: Container(
            width: seatR * 2,
            height: seatR * 2,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.16), border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1)),
            child: Icon(reserved ? Icons.star_border : (locked ? Icons.lock : Icons.add), size: seatR * 0.95, color: locked ? Colors.orangeAccent : Colors.white),
          ),
        ),
        name: Text('${index + 1}', style: TextStyle(color: Colors.white, fontSize: _seatCompact ? 11 : 12.5, fontWeight: FontWeight.w600)),
      );
    }
    final userId = m['userId'].toString();
    final user = mapOf(m['user']);
    final video = _isVideo ? _videoFor(userId) : null;
    final speaking = _isSpeaking(userId);
    final isMe = userId == Session.id;
    final frameUrl = Api.absoluteUrl(user?['frameUrl'] as String?);
    final nameColor = parseColor(user?['nameColor'] as String?);
    return _seatFrame(
      slotSize: slotSize,
      onTap: () => isMe ? _selfSeatSheet(m, index) : _memberSheet(m),
      slot: KeyedSubtree(
        key: _seatKeys.putIfAbsent(userId, () => GlobalKey()),
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        if (video != null)
          SizedBox(width: seatR * 2, height: seatR * 2, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: video))
        else
          UserAvatar(user: user, radius: seatR),
        // Konuşma halkası: sabit boyutlu bindirme; konuşmasa da yer kaplar (saydam), düzeni değiştirmez.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                shape: video != null ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: video != null ? BorderRadius.circular(14) : null,
                border: Border.all(color: speaking ? Colors.greenAccent : Colors.transparent, width: 2.5),
              ),
            ),
          ),
        ),
        // Takılı avatar çerçevesi: avatarın biraz dışına taşar; dokunuşları engellemez.
        if (frameUrl != null && video == null)
          IgnorePointer(
            child: SizedBox(
              width: seatR * 2 * 1.4,
              height: seatR * 2 * 1.4,
              child: AnimAsset(key: ValueKey(frameUrl), url: frameUrl, repeat: true, cache: false),
            ),
          ),
        ]),
      ),
      name: Row(mainAxisSize: MainAxisSize.min, children: [
        if (m['role'] == 'owner') const Icon(Icons.star, size: 12, color: Colors.amber),
        Flexible(
          child: WipNameText(
            (user?['displayName'] ?? '').toString(),
            level: (user?['wipLevel'] as num?)?.toInt(),
            color: nameColor ?? Colors.white,
            style: TextStyle(fontSize: _seatCompact ? 10 : 11, height: 1.1, fontWeight: nameColor != null ? FontWeight.w800 : FontWeight.normal),
          ),
        ),
      ]),
      score: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
        child: Text('💎 ${fmtNumber(_scores[userId] ?? 0)}', style: TextStyle(fontSize: _seatCompact ? 10 : 11, color: Colors.amberAccent)),
      ),
    );
  }

  // Koltuk + sohbet bölgesi (Yoho): koltuklar başlığın altından sabit ölçüyle başlar, sohbet koltukların bittiği yerden akar.
  // Klavye açılınca koltuklar küçülmez/yer değiştirmez; oda kararır, mesajlar karartının üstünde görünür.
  Widget _stageBody() {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    if (_inputOpen && kb > 0) _kbSeen = true;
    if (_inputOpen && _kbSeen && kb == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _inputOpen && MediaQuery.viewInsetsOf(context).bottom == 0) _closeInput();
      });
    }
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      if (!_inputOpen || _seatScale == null) {
        final need = _seatAreaHeight(w, 1);
        _seatScale = ((box.maxHeight - 120) / need).clamp(0.6, 1.0).toDouble();
      }
      final sc = _seatScale!;
      final seatH = _seatAreaHeight(w, sc);
      return Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: seatH,
          // Koltuklar sabit; yalnızca hızlı dikey kaydırma (fling) odayı değiştirir.
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -1400) _switchRoom(1);
              if (v > 1400) _switchRoom(-1);
            },
            child: _seatGrid(w, sc),
          ),
        ),
        if (!_inputOpen) Positioned(left: 0, right: 0, top: seatH, bottom: 0, child: _chatPanel(w)),
        if (_inputOpen) ...[
          Positioned.fill(child: GestureDetector(onTap: _closeInput, child: const ColoredBox(color: Color(0xB8000000)))),
          Positioned.fill(child: _chatPanel(w, overlay: true)),
        ],
        if (_canSeatManage && _micRequest && _queue.isNotEmpty && !_inputOpen)
          Positioned(
            right: 8,
            top: seatH - 34,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _micRequestsSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)]),
                child: Text('Mikrofon istekleri (${_queue.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
      ]);
    });
  }

  double get _labelsH => 2 + _seatNameH + (_scoreOn ? _seatScoreH + 2 : 0);

  /// Koltuk alanının yüksekliği: son satırın merkezi + yarıçap + ad/puan satırları.
  double _seatAreaHeight(double w, double sc) {
    final spec = seatLayoutFor(_seatCount);
    _showScoreRow = _scoreFits(spec, w * sc);
    var cy = spec.topGap * w * sc + (spec.rows.first.dia * w * sc + 8) / 2;
    for (final p in spec.pitch) {
      cy += p * w * sc;
    }
    return cy + (spec.rows.last.dia * w * sc + 8) / 2 + _labelsH + 8;
  }

  /// Puan (elmas) satırı yalnızca satırlar arasında yer varsa gösterilir (çok koltuklu modlarda gizli, Yoho gibi).
  bool _scoreFits(SeatLayoutSpec spec, double w) {
    if (spec.pitch.isEmpty) return true;
    var minGap = double.infinity;
    for (var r = 0; r < spec.pitch.length; r++) {
      final gap = spec.pitch[r] * w - (spec.rows[r].dia * w + 8) / 2 - (spec.rows[r + 1].dia * w + 8) / 2;
      if (gap < minGap) minGap = gap;
    }
    return minGap >= 2 + _seatNameH + 2 + _seatScoreH + 6;
  }

  Widget _seatGrid(double w, double sc) {
    final bySeat = <int, Map<String, dynamic>>{
      for (final m in _members)
        if (m['seatIndex'] != null) (m['seatIndex'] as num).toInt(): m,
    };
    final spec = seatLayoutFor(_seatCount);
    final tiles = <Widget>[];
    var i = 0;
    var cy = spec.topGap * w * sc + (spec.rows.first.dia * w * sc + 8) / 2;
    for (var r = 0; r < spec.rows.length; r++) {
      final row = spec.rows[r];
      final slot = row.dia * w * sc + 8;
      // Hücre genişliği: komşu koltuklar arası mesafe (ad yazısı için), en az koltuk kadar.
      var minDx = 1.0;
      for (var k = 1; k < row.xs.length; k++) {
        final dx = row.xs[k] - row.xs[k - 1];
        if (dx < minDx) minDx = dx;
      }
      final tileW = (row.xs.length == 1 ? slot * 1.9 : minDx * w - 2).clamp(slot, slot * 2.2).toDouble();
      for (final x in row.xs) {
        if (i >= _seatCount) break;
        final idx = i++;
        tiles.add(Positioned(
          left: x * w - tileW / 2,
          top: cy - slot / 2,
          width: tileW,
          child: Center(child: _seatTile(idx, bySeat[idx], slot)),
        ));
      }
      if (r < spec.pitch.length) cy += spec.pitch[r] * w * sc;
    }
    return Stack(clipBehavior: Clip.none, children: tiles);
  }

  // ---------- Üst başlık (Figma) ----------
  Widget _glass({Key? key, required Widget child, VoidCallback? onTap, EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6), double radius = 22}) {
    return Material(
      key: key,
      color: Colors.black38,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }

  Widget _roomHeader() {
    final owner = _members.where((m) => m['role'] == 'owner');
    final ownerUser = owner.isEmpty ? null : mapOf(owner.first['user']);
    final name = (_room?['name'] ?? widget.initialName).toString();
    var total = BigInt.zero;
    for (final v in _scores.values) {
      total += BigInt.tryParse(v) ?? BigInt.zero;
    }
    final isOwnerHere = _room?['ownerId']?.toString() == Session.id;
    final cover = Api.absoluteUrl(_room?['coverUrl'] as String?);
    return Padding(
      padding: EdgeInsets.fromLTRB(10, MediaQuery.paddingOf(context).top + 4, 10, 0),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _glass(
              onTap: _roomInfo,
              padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
              radius: 28,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                cover != null
                    ? Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.amber, width: 2)),
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      )
                    : UserAvatar(user: ownerUser, radius: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_room?['hidden'] == true) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.visibility_off, size: 14)),
                      if (_room?['locked'] == true) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.lock, size: 14, color: Colors.orangeAccent)),
                      Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                    ]),
                    Text('ID:${(_room?['roomNumber'] ?? ownerUser?['publicId'] ?? '').toString()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ]),
                ),
              ]),
            ),
            ),
          ),
          const SizedBox(width: 8),
          // İzleyici sayısı üstte; dokununca "İzleyiciler" listesi.
          _glass(key: _viewersKey, onTap: _membersSheet, radius: 18, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.person, size: 18), const SizedBox(width: 4), Text('${_members.length}', style: const TextStyle(fontWeight: FontWeight.w800))])),
          const SizedBox(width: 6),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: _exitMenu,
            child: const CircleAvatar(radius: 18, backgroundColor: Colors.black38, child: Icon(Icons.close, size: 20)),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          _glass(radius: 14, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.diamond, size: 14, color: Colors.lightBlueAccent), const SizedBox(width: 4), Text(fmtNumber(total.toString()), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))])),
          const SizedBox(width: 6),
          if (!isOwnerHere)
            InkWell(
              onTap: _toggleFavorite,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _fav ? Colors.orange.shade800 : Colors.orange, borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_fav ? Icons.star : Icons.star_border, size: 14, color: Colors.white), const SizedBox(width: 4), Text(_fav ? 'Favoride' : 'Favori', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white))]),
              ),
            ),
          const Spacer(),
          // Aile kısayolu (yalnızca ailesi olanlarda); dokununca aile ekranı.
          if (_myFamily != null)
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FamilyScreen())),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.amber.withValues(alpha: 0.6))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: Colors.amber,
                    backgroundImage: Api.absoluteUrl(_myFamily?['logoUrl'] as String?) != null ? NetworkImage(Api.absoluteUrl(_myFamily?['logoUrl'] as String?)!) : null,
                    child: Api.absoluteUrl(_myFamily?['logoUrl'] as String?) == null ? const Icon(Icons.favorite, size: 11, color: Colors.black87) : null,
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 90),
                    child: Text((_myFamily?['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic)),
                  ),
                ]),
              ),
            ),
        ]),
        // Taç = Katkı Listesi, aile kısayolunun hemen altında sağda.
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          _viewerClub(),
          InkWell(
            onTap: () => showContributions(context, widget.roomId),
            child: const Padding(padding: EdgeInsets.all(2), child: CrownIcon(size: 26)),
          ),
        ]),
      ]),
    );
  }

  /// İzleyici kulübesi: odadaki en yüksek seviyeli ilk 3 kullanıcı, üst üste binen yuvarlak ikonlar.
  Widget _viewerClub() {
    final ownerId = _room?['ownerId']?.toString();
    final list = _members.where((m) => m['userId']?.toString() != ownerId).toList()
      ..sort((a, b) => (((mapOf(b['user'])?['coinLevel']) as num?) ?? 0).compareTo(((mapOf(a['user'])?['coinLevel']) as num?) ?? 0));
    final top = list.take(3).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: _membersSheet,
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: 24.0 * top.length + 12,
        height: 36,
        child: Stack(children: [
          for (var i = top.length - 1; i >= 0; i--)
            Positioned(
              left: 24.0 * i,
              top: 2,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                child: UserAvatar(user: mapOf(top[i]['user']), radius: 14),
              ),
            ),
        ]),
      ),
    );
  }

  /// X düğmesi: Küçült / Çıkış (Figma).
  void _exitMenu() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Kapat',
      barrierColor: Colors.black87,
      pageBuilder: (c, _, __) {
        Widget big(IconData icon, String label, VoidCallback onTap) => InkWell(
              onTap: onTap,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 76, height: 76, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(icon, size: 40, color: Colors.black)),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, decoration: TextDecoration.none)),
              ]),
            );
        return SafeArea(
          child: Stack(children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                big(Icons.close_fullscreen, 'Küçült', () {
                  Navigator.pop(c);
                  RoomDock.minimize();
                }),
                const SizedBox(height: 56),
                big(Icons.power_settings_new, 'Çıkış', () {
                  Navigator.pop(c);
                  _onBack();
                }),
              ]),
            ),
            Positioned(top: 10, right: 14, child: IconButton(onPressed: () => Navigator.pop(c), icon: const CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.close, color: Colors.white)))),
          ]),
        );
      },
    );
  }

  // ---------- Alt satır: 6 yuvarlak düğme (Figma) ----------
  void _toggleRoomSound() {
    setState(() => _roomMuted = !_roomMuted);
    _applyRoomSound();
    toast(context, _roomMuted ? 'Oda sesi kapatıldı (yalnızca sizde).' : 'Oda sesi açıldı.');
  }

  /// Uzaktaki konuşmacıların sesini bu cihazda kapatır / açar.
  void _applyRoomSound() {
    final room = _lk;
    if (room == null) return;
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        try {
          pub.track?.mediaStreamTrack.enabled = !_roomMuted;
        } catch (_) {/* iz henüz hazır değil */}
      }
    }
  }

  void _emojiSheet() {
    const emojis = ['😀', '😂', '🥰', '😍', '😎', '🤩', '😘', '😭', '😡', '👍', '👏', '🙏', '🔥', '💯', '🎉', '❤️', '💎', '🌹', '🎁', '👑', '🎤', '🎶', '😴', '🤔', '😅', '🥳', '😇', '🤗', '😜', '🙌', '💪', '✨'];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 8,
            children: [
              for (final e in emojis)
                InkWell(
                  onTap: () {
                    Navigator.pop(c);
                    setState(() {
                      _inputOpen = true;
                      _chatCtl.text += e;
                      _chatCtl.selection = TextSelection.collapsed(offset: _chatCtl.text.length);
                    });
                  },
                  child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Alt bar (Yoho ölçüleri): düğmeler ekran genişliğinin %14,35'i aralıkla, merkezleri sabit.
  /// Mikrofonda değilken: "Selam..." yazı kutusu + hediye, mesajlar, oyun, menü.
  /// Mikrofondayken: sohbet, mikrofon, emoji, hediye, mesajlar, oyun, menü.
  Widget _bottomBar() {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final d = (w * 0.100).clamp(38.0, 50.0).toDouble();
      final barH = d + 18;
      Widget at(double cx, Widget child, {double? size}) {
        final sz = size ?? d;
        return Positioned(left: cx * w - sz / 2, top: (barH - sz) / 2 - 2, width: sz, height: sz, child: child);
      }

      Widget circle(IconData icon, String tip, VoidCallback? onTap, {Color? color}) => Tooltip(
            message: tip,
            child: Material(
              color: Colors.black.withValues(alpha: 0.32),
              shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
              child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Icon(icon, color: color ?? Colors.white, size: d * 0.52)),
            ),
          );

      final gift = Tooltip(
        message: 'Hediye gönder',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _members.isEmpty ? null : () => _openGifts(),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8B5CF6), Color(0xFF6366F1), Color(0xFF38BDF8)]),
              boxShadow: [BoxShadow(color: Color(0x667C3AED), blurRadius: 10)],
            ),
            child: Icon(Icons.redeem, color: Colors.white, size: d * 0.56),
          ),
        ),
      );
      final mail = ValueListenableBuilder<int>(
        valueListenable: Inbox.unread,
        builder: (_, n, __) => Badge(
          isLabelVisible: n > 0,
          label: Text('$n'),
          offset: const Offset(-2, 2),
          child: circle(Icons.mail_outline, 'Mesajlar', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Mesajlar')), body: const MessagesScreen())))),
        ),
      );
      final games = Tooltip(
        message: 'Oyunlar',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _openGames,
          child: Container(
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFF59E0B)])),
            child: Icon(Icons.sports_esports, color: Colors.white, size: d * 0.56),
          ),
        ),
      );
      final menu = circle(Icons.grid_view_rounded, 'Oda araçları', _openTools);

      const step = 0.1435;
      final right = <Widget>[
        at(0.5, gift, size: d * 1.08),
        at(0.5 + step, mail),
        at(0.5 + step * 2, games),
        at(0.5 + step * 3, menu),
      ];
      final List<Widget> left;
      if (_onSeat) {
        left = [
          at(0.5 - step * 3, circle(Icons.chat_bubble_outline, 'Sohbet', _openInput)),
          at(0.5 - step * 2, GestureDetector(
            onLongPress: _leaveMic,
            child: circle(_micOn ? Icons.mic : Icons.mic_off, 'Mikrofon (uzun bas: mikrofondan in)', () {
              setState(() => _micOn = !_micOn);
              _syncPublish();
            }, color: _micOn ? Colors.white : Colors.redAccent),
          )),
          at(0.5 - step, circle(Icons.sentiment_satisfied_alt, 'Emoji', _chatOpen ? _emojiSheet : null)),
        ];
      } else {
        final pillH = (w * 0.087).clamp(34.0, 44.0).toDouble();
        left = [
          Positioned(
            left: w * 0.025,
            width: w * 0.394,
            top: (barH - pillH) / 2 - 2,
            height: pillH,
            child: Material(
              color: Colors.black.withValues(alpha: 0.32),
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _openInput,
                child: Row(children: [
                  const SizedBox(width: 10),
                  const Icon(Icons.chat_bubble_outline, size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_chatOpen ? 'Selam...' : 'Sohbet kapalı', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                ]),
              ),
            ),
          ),
        ];
      }
      return SizedBox(height: barH + 6, child: Stack(clipBehavior: Clip.none, children: [...left, ...right]));
    });
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
        // Klavye açılınca koltuk alanı yerinden oynamasın; boşluğu aşağıdaki sohbet bölgesi yönetir.
        resizeToAvoidBottomInset: false,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RoomThemeBackground(
                theme: _room?['theme']?.toString(),
                imageUrl: _room?['themeImageUrl']?.toString(),
                child: GiftRibbonOverlay(
                roomId: widget.roomId,
                child: Stack(key: _stageKey, fit: StackFit.expand, children: [
                Padding(
                padding: EdgeInsets.only(bottom: _inputOpen ? MediaQuery.viewInsetsOf(context).bottom : 0),
                child: Column(children: [
                  Stack(children: [
                    _roomHeader(),
                    if (_inputOpen) Positioned.fill(child: GestureDetector(onTap: _closeInput, child: const ColoredBox(color: Color(0xB8000000)))),
                  ]),
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
                  if (_pk != null)
                    PkBanner(
                      pk: _pk!,
                      roomId: widget.roomId,
                      onCancel: _myRole == 'owner' ? () => guard(context, () => Api.post('/api/pk/${_pk!['id']}/cancel')) : null,
                    ),
                  Expanded(child: _stageBody()),
                  if (_inputOpen) _inputBar() else _bottomBar(),
                ]),
              ),
                Positioned(left: 0, right: 0, top: MediaQuery.sizeOf(context).height * 0.36, child: EntranceStrip(queue: _entrance)),
                MusicBubble(onOpen: _openMusic),
                for (final f in _flights)
                  _GiftFlight(key: ValueKey(f.id), data: f, onDone: () {
                    if (mounted) setState(() => _flights.removeWhere((x) => x.id == f.id));
                  }),
                if (_bags.isNotEmpty)
                  Positioned(
                    left: 12,
                    top: MediaQuery.paddingOf(context).top + 100,
                    child: BagEnvelope(
                      count: _bags.length,
                      isSuper: _bags.any((b) => b['kind'] == 'super'),
                      onTap: () => showBagClaim(context, widget.roomId, _bags.first),
                    ),
                  ),
                ]))),
      ),
      ),
    );
  }
}


class _GiftFlightData {
  final int id;
  final String icon;
  final Offset from;
  final Offset to;
  _GiftFlightData(this.id, this.icon, this.from, this.to);
}

/// Hediye ikonunun gönderenden alıcıya uçuşu: hafif yay çizer, büyüyüp küçülür, varınca kaybolur.
class _GiftFlight extends StatefulWidget {
  final _GiftFlightData data;
  final VoidCallback onDone;
  const _GiftFlight({super.key, required this.data, required this.onDone});

  @override
  State<_GiftFlight> createState() => _GiftFlightState();
}

class _GiftFlightState extends State<_GiftFlight> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = Curves.easeInOutCubic.transform(_c.value);
            final arc = -60 * (1 - (2 * t - 1) * (2 * t - 1)); // ortada yukarı kavis
            final pos = Offset.lerp(d.from, d.to, t)! + Offset(0, arc);
            final size = 54.0 * (0.8 + 0.7 * (1 - (2 * t - 1).abs()));
            final opacity = _c.value > 0.85 ? (1 - _c.value) / 0.15 : 1.0;
            return Stack(children: [
              Positioned(
                left: pos.dx - size / 2,
                top: pos.dy - size / 2,
                width: size,
                height: size,
                child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: Image.network(d.icon, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
