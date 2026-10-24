import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api.dart';
import '../services/inbox_service.dart';
import '../services/presence_service.dart';
import '../services/socket_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/presence_widgets.dart';
import 'messages_screen.dart';
import 'notification_screens.dart';
import 'social_screens.dart';
import 'support_screens.dart';
import 'user_screens.dart';

/// Yoho saat biçimi: bugün 14:30 · dün "Dün 14:30" · daha eski "26-10-06" (yıl-ay-gün).
String yohoTime(dynamic iso, {bool withClock = false}) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final clock = '${two(d.hour)}:${two(d.minute)}';
  if (day == today) return clock;
  if (day == today.subtract(const Duration(days: 1))) return 'Dün $clock';
  final date = '${two(d.year % 100)}-${two(d.month)}-${two(d.day)}';
  return withClock ? '$date $clock' : date;
}

/// Sohbet / duyuru akışında tarih ayracı gerekir mi (5 dakikadan uzun ara veya gün değişimi).
bool needsStamp(dynamic prevIso, dynamic iso) {
  final a = DateTime.tryParse((prevIso ?? '').toString())?.toLocal();
  final b = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (a == null || b == null) return true;
  return b.difference(a).inMinutes.abs() >= 5 || a.day != b.day || a.month != b.month || a.year != b.year;
}

/// Ortadaki gri tarih yazısı (Yoho: "Dün 18:51").
class TimeStamp extends StatelessWidget {
  final dynamic iso;
  const TimeStamp(this.iso, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(child: Text(yohoTime(iso, withClock: true), style: const TextStyle(color: Pal.textDim, fontSize: 12.5))),
      );
}

/// Mesajlar (Yoho): üstte yana kayan kategori kartları, altında sohbet listesi.
/// [inSheet]: oda içinde zarf düğmesiyle açılan "Sohbet" penceresi (başlık + kapat düğmesi).
class MessagesHome extends StatefulWidget {
  final bool inSheet;
  const MessagesHome({super.key, this.inSheet = false});

  @override
  State<MessagesHome> createState() => _MessagesHomeState();
}

class _MessagesHomeState extends State<MessagesHome> {
  List<Map<String, dynamic>> _conv = [];
  Map<String, dynamic> _sum = {};
  int _support = 0;
  int _notify = 0; // okunmamış bildirim
  Map<String, dynamic>? _family; // üyesi olduğum aile (aile sohbeti kartı)
  int _familyUnread = 0;
  bool _loading = true;
  String? _error;
  StreamSubscription? _sub;
  Timer? _debounce;
  final Set<String> _typing = {}; // şu an yazan kişiler (listede "yazıyor..." görünür)
  final Map<String, Timer> _typingTimers = {};

  @override
  void initState() {
    super.initState();
    _load();
    _sub = SocketService.instance.events.listen((e) {
      if (!mounted) return;
      if (e['type'] == 'typing') {
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
      if (e['type'] == 'support_message' || e['type'] == 'agency_invite' || e['type'] == 'cp_request' || e['type'] == 'notify' || e['type'] == 'family_chat') {
        _loadBadges();
        return;
      }
      if (e['type'] != 'dm') return;
      final from = mapOf(e['message'])?['senderId']?.toString();
      if (from != null && _typing.remove(from)) _typingTimers.remove(from)?.cancel();
      // Art arda gelen mesajlarda tek yenileme yeterli.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) _loadConversations();
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

  Future<void> _load() async {
    await Future.wait([_loadConversations(), _loadBadges()]);
  }

  Future<void> _loadConversations() async {
    try {
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
      if (!mounted) return;
      setState(() {
        _conv = conv;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _loadBadges() async {
    try {
      final s = await Api.get('/api/inbox-summary');
      final u = await Api.get('/api/support/unread');
      final n = await Api.get('/api/me/notifications/unread').catchError((_) => <String, dynamic>{});
      final fam = mapOf((await Api.get('/api/families/mine').catchError((_) => <String, dynamic>{}))['family']);
      var famUnread = 0;
      if (fam?['id'] != null) {
        final fu = await Api.get('/api/families/${fam!['id']}/chat/unread').catchError((_) => <String, dynamic>{});
        famUnread = (fu['unread'] as num?)?.toInt() ?? 0;
      }
      if (!mounted) return;
      setState(() {
        _sum = s;
        _support = (u['unread'] as num?)?.toInt() ?? 0;
        _notify = (n['unread'] as num?)?.toInt() ?? 0;
        _family = fam;
        _familyUnread = famUnread;
      });
    } catch (_) {/* rozetler olmasa da kartlar çalışır */}
  }

  int _n(String k) => (_sum[k] as num?)?.toInt() ?? 0;

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    Inbox.refresh();
    Inbox.refreshBadges();
    if (mounted) _load();
  }

  // ---------- Kartlar ----------
  Widget _cards(double w) {
    final m = homeMargin(w);
    final cw = (w * 0.2).clamp(68.0, 96.0).toDouble();
    final ch = (w * 0.236).clamp(80.0, 112.0).toDouble();
    final gap = (w * 0.016).clamp(5.0, 9.0).toDouble();
    final icon = cw * 0.44;
    final fam = _family;
    final items = <_InboxCard>[
      _InboxCard('Bildirimler', const Color(0xFF1F2A55), _icon(Icons.notifications_active_rounded, const Color(0xFF60A5FA), icon), _notify, () => _push(const NotificationsPage())),
      if (fam != null)
        _InboxCard('Aile\nSohbeti', const Color(0xFF3A1F4F), _icon(Icons.groups_rounded, const Color(0xFFC084FC), icon), _familyUnread,
            () => _push(FamilyChatPage(familyId: fam['id'].toString(), familyName: (fam['name'] ?? 'Aile').toString()))),
      // Ajans daveti: yalnızca bekleyen davet varken görünür (yanıt buradan verilir).
      if (_n('agency') > 0)
        _InboxCard('Ajans\ndaveti', const Color(0xFF3A1F55), _icon(Icons.business_center_rounded, const Color(0xFFB794F4), icon), _n('agency'), () => _push(const AgencyInvitesScreen())),
      _InboxCard('Arkadaşlık\nisteği', const Color(0xFF2B2650), _icon(Icons.waving_hand_rounded, const Color(0xFFFFC43D), icon), Inbox.badges.value['friends'] ?? 0, () => _push(const FriendRequestsScreen())),
      _InboxCard('TR Live Ekibi', const Color(0xFF173D2E), TeamAvatar(size: icon), _n('team'), () => _push(const OfficialChannelScreen(kind: 'team'))),
      _InboxCard('Etkinlik\nPromosyonu', const Color(0xFF3D321A), _icon(Icons.campaign_rounded, const Color(0xFFFF9F0A), icon), _n('event'), () => _push(const OfficialChannelScreen(kind: 'event'))),
      _InboxCard('Çevrimiçi\nHizmet', const Color(0xFF123B45), _icon(Icons.support_agent_rounded, const Color(0xFF38D5F5), icon), _support, () => _push(const SupportChatScreen())),
      _InboxCard('Ödül\nBildirimleri', const Color(0xFF3D1A36), _icon(Icons.card_giftcard_rounded, const Color(0xFFE879F9), icon), _n('reward'), () => _push(const OfficialChannelScreen(kind: 'reward'))),
    ];
    return SizedBox(
      height: ch,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: gap),
        itemBuilder: (_, i) {
          final c = items[i];
          return Semantics(
            button: true,
            label: c.badge > 0 ? '${c.label.replaceAll('\n', ' ')}, ${c.badge} yeni' : c.label.replaceAll('\n', ' '),
            child: Material(
              color: c.color,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: c.onTap,
                child: SizedBox(
                  width: cw,
                  child: Column(children: [
                    SizedBox(height: ch * 0.12),
                    Badge(
                      isLabelVisible: c.badge > 0,
                      label: Text(c.badge > 99 ? '99+' : '${c.badge}'),
                      offset: const Offset(4, -4),
                      child: SizedBox(width: icon, height: icon, child: c.icon),
                    ),
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(c.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.2, color: Pal.text)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _icon(IconData i, Color c, double s) => FittedBox(child: Icon(i, color: c, size: s));

  // ---------- Sohbet satırı ----------
  Widget _row(Map<String, dynamic> c, double w) {
    final peer = mapOf(c['peer']);
    final unread = (c['unread'] as num? ?? 0).toInt();
    final r = (w * 0.066).clamp(22.0, 30.0).toDouble();
    final m = homeMargin(w);
    final rowH = (w * 0.19).clamp(64.0, 84.0).toDouble();
    final typing = _typing.contains(peer?['id']?.toString());
    return InkWell(
      onTap: peer == null ? null : () => _push(ChatScreen(peer: peer)),
      child: SizedBox(
        height: rowH,
        child: Row(children: [
          SizedBox(width: m),
          PresenceAvatar(userId: peer?['id']?.toString(), child: UserAvatar(user: peer, radius: r)),
          SizedBox(width: m),
          Expanded(
            child: DecoratedBox(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x1FFFFFFF), width: 0.8))),
              child: Padding(
                padding: EdgeInsets.only(right: m),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: UserName(user: peer, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                    const SizedBox(width: 8),
                    Text(yohoTime(c['lastMessageAt']), style: const TextStyle(fontSize: 12.5, color: Pal.textDim)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: typing
                          ? const Text('yazıyor...', maxLines: 1, style: TextStyle(fontSize: 14, color: Pal.green, fontStyle: FontStyle.italic))
                          : Text(
                              '${c['lastFromMe'] == true ? 'Sen: ' : ''}${c['lastMessage'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: unread > 0 ? Pal.text : Pal.textDim, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400),
                            ),
                    ),
                    if (unread > 0) ...[const SizedBox(width: 6), Badge(label: Text(unread > 99 ? '99+' : '$unread'))],
                  ]),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _header(double w) {
    final m = homeMargin(w);
    if (widget.inSheet) {
      return Padding(
        padding: EdgeInsets.fromLTRB(m, 14, m - 6, 8),
        child: Row(children: [
          const Expanded(child: Text('Sohbet', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
          IconButton(tooltip: 'Arkadaşlarım', onPressed: () => _push(const FriendsScreen()), icon: const Icon(Icons.people_alt_outlined, color: Pal.text)),
          IconButton(tooltip: 'Kapat', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Pal.text)),
        ]),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(m, 10, m - 6, 12),
      child: Row(children: [
        Expanded(child: Text('Mesajlar', style: TextStyle(fontSize: (w * 0.072).clamp(24.0, 30.0).toDouble(), fontWeight: FontWeight.w900))),
        IconButton(tooltip: 'Arkadaşlarım', onPressed: () => _push(const FriendsScreen()), icon: const Icon(Icons.people_alt_outlined, color: Pal.text, size: 28)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: ValueListenableBuilder<Map<String, int>>(
        valueListenable: Inbox.badges,
        builder: (context, _, __) => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            // Alt menü ve küçültülmüş oda balonu son satırı örtmesin.
            padding: EdgeInsets.only(bottom: widget.inSheet ? 16 : 96),
            children: [
              _header(w),
              _cards(w),
              const SizedBox(height: 10),
              if (_loading)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (_error != null && _conv.isEmpty)
                LoadError(message: _error!, onRetry: _load)
              else if (_conv.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 48, 24, 24),
                  child: Column(children: [
                    Icon(Icons.forum_outlined, size: 56, color: Pal.textDim),
                    SizedBox(height: 10),
                    Text('Henüz mesajın yok.\nArkadaşlarınla sohbet etmek için sağ üstteki arkadaş listesine dokun.', textAlign: TextAlign.center, style: TextStyle(color: Pal.textDim, height: 1.4)),
                  ]),
                )
              else
                for (final c in _conv) _row(c, w),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxCard {
  final String label;
  final Color color;
  final Widget icon;
  final int badge;
  final VoidCallback onTap;
  const _InboxCard(this.label, this.color, this.icon, this.badge, this.onTap);
}

/// Oda içinde zarf düğmesi: alttan açılan "Sohbet" penceresi (Yoho). Sohbete dokununca sohbet tam ekran açılır,
/// geri gelince pencere yerinde durur; oda arkada çalışmaya devam eder.
Future<void> showInboxSheet(BuildContext context) {
  final h = MediaQuery.sizeOf(context).height;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Pal.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    clipBehavior: Clip.antiAlias,
    builder: (_) => SizedBox(height: h * 0.72, child: const MessagesHome(inSheet: true)),
  );
}

/// TR Live Ekibi simgesi (Yoho Ekibi'nin yerinde): yeşil-turkuaz yuvarlak üstünde "TR".
class TeamAvatar extends StatelessWidget {
  final double size;
  const TeamAvatar({super.key, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: kGoldDeep)),
        child: Text('TR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.4, height: 1.0)),
      );
}

/// Arkadaşlık isteği (Yoho): yalnızca son 7×24 saatteki bekleyen istekler.
class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  int _v = 0;
  final Set<String> _busy = {};

  /// [rel]: null = arkadaşlık isteği; 'friend' / 'cp' = yakınlık ilişki isteği (CP sistemi).
  Future<void> _respond(String userId, bool accept, [String? rel]) async {
    final key = '${rel ?? 'f'}:$userId';
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    final r = await guard(
      context,
      () => rel == null
          ? Api.post('/api/friends/${accept ? 'accept' : 'decline'}/$userId')
          : Api.post('/api/cp/with/$userId/${accept ? 'accept' : 'decline'}'),
    );
    if (!mounted) return;
    setState(() => _busy.remove(key));
    if (r != null) {
      if (accept) toast(context, rel == 'cp' ? 'Artık CP\'siniz! ❤' : rel == 'kanka' ? 'Artık kankasınız!' : rel == 'friend' ? 'Artık en iyi arkadaşsınız!' : 'Artık arkadaşsınız.');
      setState(() => _v++);
      Inbox.refreshBadges();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('Arkadaşlık isteği', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Kullanıcı ara', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchScreen())), icon: const Icon(Icons.search, size: 28)),
        ],
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Text('Sadece geçerli istekleri göster (7*24 saat içinde)', style: TextStyle(color: Pal.textDim, fontSize: 13)),
        ),
        Expanded(
          child: AsyncBody<List<Map<String, dynamic>>>(
            version: _v,
            // Arkadaşlık istekleri + CP sisteminden gelen ilişki istekleri (Arkadaş / CP) tek listede.
            load: () async {
              final res = await Future.wait([
                Api.get('/api/friends/requests'),
                Api.get('/api/cp/requests').catchError((_) => <String, dynamic>{}),
              ]);
              final list = [
                ...listOf(res[1]['requests']).map((x) => {...x, 'rel': x['kind']}),
                ...listOf(res[0]['requests']),
              ];
              list.sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
              return list;
            },
            builder: (context, reqs, reload) => reqs.isEmpty
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.waving_hand_outlined, size: 72, color: Pal.textDim),
                      SizedBox(height: 14),
                      Text('Hiç arkadaşlık isteği yok', style: TextStyle(color: Pal.textDim, fontSize: 15)),
                    ]),
                  )
                : RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(children: [
                      for (final r in reqs)
                        Builder(builder: (context) {
                          final u = mapOf(r['user']);
                          final id = u?['id']?.toString() ?? '';
                          final rel = r['rel'] as String?;
                          final busy = _busy.contains('${rel ?? 'f'}:$id');
                          return ListTile(
                            leading: GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id))),
                              child: UserAvatar(user: u, radius: 24),
                            ),
                            title: UserName(user: u, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: rel == null
                                ? Text(yohoTime(r['createdAt'], withClock: true), style: const TextStyle(color: Pal.textDim, fontSize: 12))
                                : Text('${rel == 'cp' ? '❤ CP' : rel == 'kanka' ? '🤜 Kanka' : '🤝 En İyi Arkadaş'} olarak seçti · ${yohoTime(r['createdAt'], withClock: true)}',
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFF7EB3), fontSize: 12)),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Pal.green, foregroundColor: Colors.white, minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12), shape: const StadiumBorder()),
                                onPressed: busy ? null : () => _respond(id, true, rel),
                                child: const Text('Kabul et'),
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(foregroundColor: Pal.textDim, minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12), shape: const StadiumBorder()),
                                onPressed: busy ? null : () => _respond(id, false, rel),
                                child: const Text('Reddet'),
                              ),
                            ]),
                          );
                        }),
                    ]),
                  ),
          ),
        ),
      ]),
    );
  }
}

/// Ajans davetleri: ajans sahibinin gönderdiği yayıncılık davetleri. Kabul edilince ajansın yayıncısı olunur.
class AgencyInvitesScreen extends StatefulWidget {
  const AgencyInvitesScreen({super.key});

  @override
  State<AgencyInvitesScreen> createState() => _AgencyInvitesScreenState();
}

class _AgencyInvitesScreenState extends State<AgencyInvitesScreen> {
  int _v = 0;
  final Set<String> _busy = {};

  Future<void> _respond(String id, bool accept) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    final r = await guard(context, () => Api.post('/api/agency-requests/$id/respond', {'accept': accept}));
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (r != null) {
      toast(context, accept ? 'Ajansa katıldın, artık yayıncısın! 🎉' : 'Davet reddedildi.');
      setState(() => _v++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const Text('Ajans daveti', style: TextStyle(fontWeight: FontWeight.w800))),
      body: AsyncBody<List<Map<String, dynamic>>>(
        version: _v,
        load: () async => listOf((await Api.get('/api/broadcaster/requests'))['requests']).where((x) => x['direction'] == 'invite').toList(),
        builder: (context, list, reload) => list.isEmpty
            ? const Center(child: Text('Bekleyen ajans daveti yok.', style: TextStyle(color: Pal.textDim, fontSize: 15)))
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView(padding: const EdgeInsets.all(12), children: [
                  for (final r in list)
                    Builder(builder: (context) {
                      final a = mapOf(r['agency']);
                      final id = r['id'].toString();
                      final busy = _busy.contains(id);
                      final logo = Api.absoluteUrl(a?['logoUrl'] as String?);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(colors: [Color(0xFF3A1F55), Color(0xFF1E1236)]),
                          border: Border.all(color: const Color(0x55B794F4)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: const Color(0xFF6D28D9),
                              backgroundImage: logo == null ? null : NetImage(logo, targetW: 132, targetH: 132),
                              child: logo == null ? const Icon(Icons.business_center_rounded, color: Colors.white) : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text((a?['name'] ?? 'Ajans').toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                Text(yohoTime(r['createdAt'], withClock: true), style: const TextStyle(color: Pal.textDim, fontSize: 12)),
                              ]),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          const Text('Seni yayıncı olarak ajansına davet ediyor. Kabul edersen bu ajansın yayıncısı olursun.', style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(foregroundColor: Pal.textDim, shape: const StadiumBorder()),
                                onPressed: busy ? null : () => _respond(id, false),
                                child: const Text('Reddet'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Pal.green, foregroundColor: Colors.white, shape: const StadiumBorder()),
                                onPressed: busy ? null : () => _respond(id, true),
                                child: const Text('Kabul et'),
                              ),
                            ),
                          ]),
                        ]),
                      );
                    }),
                ]),
              ),
      ),
    );
  }
}

/// Ekip / Etkinlik / Ödül duyuruları (Yoho resmi hesap sayfası): tarih ayraçlı akış, görselli kartlar,
/// görselsiz ekip mesajları baloncuk olarak. En yenisi en altta.
class OfficialChannelScreen extends StatefulWidget {
  final String kind; // team | event | reward
  const OfficialChannelScreen({super.key, required this.kind});

  static String titleOf(String kind) => switch (kind) {
        'event' => 'Etkinlik Promosyonu',
        'reward' => 'Ödül Bildirimleri',
        _ => 'TR Live Ekibi',
      };

  @override
  State<OfficialChannelScreen> createState() => _OfficialChannelScreenState();
}

class _OfficialChannelScreenState extends State<OfficialChannelScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Kart açıldı: yalnızca bu türün rozeti sıfırlanır.
    Api.post('/api/inbox-summary/seen', {'kind': widget.kind}).catchError((_) => <String, dynamic>{});
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final list = listOf((await Api.get('/api/announcements', query: {'kind': widget.kind}))['announcements']).reversed.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
    return list;
  }

  /// Bağlantı tarayıcıda / ilgili uygulamada açılır; açılamazsa kopyalanır.
  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (ok || !mounted) return;
    Clipboard.setData(ClipboardData(text: url));
    toast(context, 'Bağlantı kopyalandı.');
  }

  Widget _action() {
    switch (widget.kind) {
      case 'event':
        return const Icon(Icons.campaign_rounded, color: Color(0xFFFF9F0A), size: 30);
      case 'reward':
        return const Icon(Icons.card_giftcard_rounded, color: Color(0xFFE879F9), size: 30);
      default:
        return const TeamAvatar(size: 34);
    }
  }

  Widget _linkRow(String url) => InkWell(
        onTap: () => _openLink(url),
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.only(top: 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1FFFFFFF)))),
          child: const Row(children: [
            Expanded(child: Text('Görmek için tıklayın', style: TextStyle(color: Pal.textDim, fontSize: 13))),
            Icon(Icons.chevron_right, color: Pal.textDim),
          ]),
        ),
      );

  Widget _item(Map<String, dynamic> a, double w) {
    final img = Api.absoluteUrl(a['imageUrl'] as String?);
    final link = a['linkUrl'] as String?;
    final title = (a['title'] ?? '').toString();
    final text = (a['text'] ?? '').toString();
    // Görselsiz ekip mesajı: solda ekip simgesi, yanında gri baloncuk.
    if (img == null && widget.kind == 'team') {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TeamAvatar(size: 40),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(color: Pal.surfaceHi, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title.isNotEmpty) Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              if (title.isNotEmpty) const SizedBox(height: 4),
              Text(text, style: const TextStyle(fontSize: 15, height: 1.35)),
              if (link != null) _linkRow(link),
            ]),
          ),
        ),
        SizedBox(width: w * 0.08),
      ]);
    }
    if (widget.kind == 'event') return _eventCard(title, text, img, link);
    // Kart: üstte görsel, altta başlık ve metin.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Pal.outline, width: 0.8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (img != null)
          AspectRatio(
            aspectRatio: 1.8,
            child: NetImg(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Pal.surfaceHi)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(fontSize: 15, height: 1.35)),
            if (link != null) _linkRow(link),
          ]),
        ),
      ]),
    );
  }

  /// Etkinlik duyurusu: altın-pembe parlak çerçeve, görselin üstünde başlık, "ETKİNLİK" etiketi ve büyük düğme.
  Widget _eventCard(String title, String text, String? img, String? link) {
    final head = Stack(children: [
      AspectRatio(
        aspectRatio: 1.7,
        child: img != null
            ? NetImg(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF3A0F72)))
            : const DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF6D28D9), Color(0xFFDB2777), Color(0xFFF59E0B)])),
                child: Center(child: Icon(Icons.emoji_events_rounded, color: Colors.white70, size: 72)),
              ),
      ),
      // Alttan karartma: başlık görselin üstünde okunsun.
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0xCC000000)])),
        ),
      ),
      Positioned(
        left: 12,
        top: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFD54F), Color(0xFFFF8F00)]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x66FF8F00), blurRadius: 8)],
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.local_fire_department_rounded, size: 15, color: Color(0xFF3A1600)),
            SizedBox(width: 3),
            Text('ETKİNLİK', style: TextStyle(color: Color(0xFF3A1600), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
          ]),
        ),
      ),
      if (title.isNotEmpty)
        Positioned(
          left: 14,
          right: 14,
          bottom: 12,
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, height: 1.2, shadows: [Shadow(color: Colors.black87, blurRadius: 6)]),
          ),
        ),
    ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: kGoldLight),
        boxShadow: const [BoxShadow(color: Color(0x55E6B13A), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: const Color(0xFF14102A), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (text.isNotEmpty) Text(text, style: const TextStyle(fontSize: 15, height: 1.4, color: Color(0xFFE5E7EB))),
              if (link != null) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _openLink(link),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(colors: kGoldDeep),
                    ),
                    child: const Text('Hemen katıl', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(OfficialChannelScreen.titleOf(widget.kind), style: const TextStyle(color: Color(0xFFFF4F6E), fontWeight: FontWeight.w800)),
        actions: [Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: _action()))],
      ),
      body: AsyncBody<List<Map<String, dynamic>>>(
        load: _load,
        builder: (context, items, reload) => items.isEmpty
            ? const EmptyState(icon: Icons.notifications_none, text: 'Henüz bildirim yok.')
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(homeMargin(w), 0, homeMargin(w), 24),
                  itemCount: items.length,
                  itemBuilder: (_, i) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (i == 0 || needsStamp(items[i - 1]['createdAt'], items[i]['createdAt'])) TimeStamp(items[i]['createdAt']),
                    _item(items[i], w),
                  ]),
                ),
              ),
      ),
    );
  }
}
