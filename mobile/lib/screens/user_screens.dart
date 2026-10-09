import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/anim_asset.dart';
import '../services/session.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/safety_actions.dart';
import 'feed_screen.dart';
import 'messages_screen.dart';
import 'social_screens.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  int _version = 0;
  int _tab = 0; // 0 Profil · 1 Başarılar · 2 Paylaşım · 3 İlişkiler

  Future<Map<String, dynamic>> _load() async {
    final p = mapOf((await Api.get('/api/users/${widget.userId}'))['profile']) ?? {};
    Map<String, dynamic> card = {};
    try {
      card = await Api.get('/api/users/${widget.userId}/card');
    } catch (_) {/* kart yüklenemezse boş göster */}
    return {'p': p, 'card': card};
  }

  String? _frameOf(Map<String, dynamic> p) {
    final items = p['equipped'];
    if (items is! List) return null;
    for (final i in items) {
      if (i is Map && i['itemType'] == 'frame') return Api.absoluteUrl(i['assetUrl'] as String?);
    }
    return null;
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Future<void> _toggleFollow(Map<String, dynamic> p) async {
    final following = p['isFollowing'] == true;
    final r = await guard<bool>(context, () async {
      if (following) {
        await Api.delete('/api/users/${widget.userId}/follow');
      } else {
        await Api.post('/api/users/${widget.userId}/follow');
      }
      return true;
    });
    if (r == true && mounted) setState(() => _version++);
  }

  Future<void> _friendAction(Map<String, dynamic> p) async {
    final st = (p['friendStatus'] ?? 'none').toString();
    final id = widget.userId;
    Future<Map<String, dynamic>> Function()? call;
    String? done;
    switch (st) {
      case 'none':
        call = () => Api.post('/api/friends/request/$id');
        done = 'Arkadaşlık isteği gönderildi.';
      case 'incoming':
        call = () => Api.post('/api/friends/accept/$id');
        done = 'Artık arkadaşsınız.';
      case 'requested':
        if (!await confirm(context, 'Gönderdiğin arkadaşlık isteği geri çekilsin mi?', action: 'Geri çek') || !mounted) return;
        call = () => Api.delete('/api/friends/$id');
      case 'friends':
        if (!await confirm(context, 'Arkadaşlıktan çıkarılsın mı? Mesajlaşamazsınız.', action: 'Çıkar') || !mounted) return;
        call = () => Api.delete('/api/friends/$id');
    }
    if (call == null) return;
    final r = await guard(context, call);
    if (r != null && mounted) {
      if (done != null) toast(context, done);
      setState(() => _version++);
    }
  }

  Widget _header(Map<String, dynamic> p, bool hidden) {
    final cover = Api.absoluteUrl(p['coverUrl'] as String?) ?? Api.absoluteUrl(p['avatarUrl'] as String?);
    final frame = _frameOf(p);
    final wip = mapOf(p['wip']);
    final features = mapOf(wip?['features']);
    final w = MediaQuery.sizeOf(context).width;
    final coverH = w * 0.95;
    final medals = <Widget>[];
    return Column(children: [
      SizedBox(
        height: coverH + 70,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: coverH,
            child: cover != null && !hidden
                ? Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.white12))
                : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFFFF4081)], begin: Alignment.topLeft, end: Alignment.bottomRight))),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: coverH - 40,
            height: 44,
            child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Theme.of(context).scaffoldBackgroundColor]))),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: coverH - 70,
            child: Center(
              child: Stack(alignment: Alignment.center, children: [
                UserAvatar(user: p, radius: 46),
                if (frame != null) IgnorePointer(child: SizedBox(width: 200, height: 200, child: AnimAsset(url: frame, repeat: true, cache: false))),
              ]),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 6,
            left: 8,
            child: CircleAvatar(backgroundColor: Colors.black45, child: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white), onPressed: () => Navigator.maybePop(context))),
          ),
          if (widget.userId != Session.id)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 6,
              right: 8,
              child: CircleAvatar(
                backgroundColor: Colors.black45,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (a) async {
                    if (a == 'report') await reportDialog(context, kind: 'user', targetUserId: widget.userId);
                    if (a == 'block') {
                      if (await blockUserDialog(context, widget.userId, 'Bu kullanıcı') && mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'report', child: Text('Şikâyet et')),
                    PopupMenuItem(value: 'block', child: Text('Engelle')),
                  ],
                ),
              ),
            ),
        ]),
      ),
      UserName(
        user: {'displayName': p['displayName'], 'wipLevel': wip?['level'], 'nameColor': features?['nameColor']},
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      if (!hidden) ...[
        const SizedBox(height: 4),
        Text('ID: ${p['publicId'] ?? '-'}', style: const TextStyle(color: Pal.textDim)),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
          if (p['age'] != null) _chip(Icons.cake, '${p['age']}', const Color(0xFF3D8BFF)),
          _chip(Icons.star, '${p['coinLevel'] ?? 0}', const Color(0xFFFF2D6F)),
          if (p['broadcaster'] != null) _chip(Icons.podcasts, 'Yayıncı', const Color(0xFFB0003A)),
          ...medals,
        ]),
      ],
    ]);
  }

  Widget _chip(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        ]),
      );

  Widget _medalRow(Map<String, dynamic> card) {
    final medals = listOf(card['medals']).take(4).toList();
    if (medals.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final m in medals) Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _medalImg(m, 54)),
      ]),
    );
  }

  Widget _medalImg(Map<String, dynamic> m, double size) {
    final url = Api.absoluteUrl(m['assetUrl'] as String?);
    return SizedBox(width: size, height: size, child: url == null ? const Icon(Icons.military_tech, color: Colors.amber) : Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.military_tech, color: Colors.amber)));
  }

  Widget _tabs() {
    Widget t(String label, int i) {
      final sel = _tab == i;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: TextStyle(fontSize: 17, fontWeight: sel ? FontWeight.w900 : FontWeight.w500, color: sel ? Colors.white : Pal.textDim))),
              const SizedBox(height: 4),
              Container(height: 3, width: 34, decoration: BoxDecoration(color: sel ? Pal.cyan : Colors.transparent, borderRadius: BorderRadius.circular(2))),
            ]),
          ),
        ),
      );
    }

    return Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [t('Profil', 0), t('Başarılar', 1), t('Paylaşım', 2), t('İlişkiler', 3)]));
  }

  Widget _actions(Map<String, dynamic> p) {
    final st = (p['friendStatus'] ?? 'none').toString();
    final friendLabel = switch (st) { 'friends' => 'Arkadaşsınız', 'requested' => 'İstek gönderildi', 'incoming' => 'İsteği kabul et', _ => 'Arkadaş ekle' };
    final friendIcon = switch (st) { 'friends' => Icons.people, 'requested' => Icons.hourglass_top, 'incoming' => Icons.check, _ => Icons.person_add_alt_1 };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(children: [
        Expanded(
          child: p['isFollowing'] == true
              ? OutlinedButton(onPressed: () => _toggleFollow(p), child: const Text('Takip ediliyor'))
              : FilledButton(onPressed: () => _toggleFollow(p), child: const Text('Takip et')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: st == 'friends' || st == 'requested'
              ? OutlinedButton.icon(onPressed: () => _friendAction(p), icon: Icon(friendIcon, size: 18), label: FittedBox(fit: BoxFit.scaleDown, child: Text(friendLabel)))
              : FilledButton.tonalIcon(onPressed: () => _friendAction(p), icon: Icon(friendIcon, size: 18), label: FittedBox(fit: BoxFit.scaleDown, child: Text(friendLabel))),
        ),
        if (st == 'friends') ...[
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Mesaj',
            onPressed: () => _push(ChatScreen(peer: {'id': widget.userId, 'displayName': p['displayName'], 'avatarUrl': p['avatarUrl'], 'nameColor': mapOf(mapOf(p['wip'])?['features'])?['nameColor'], 'wipLevel': mapOf(p['wip'])?['level']})),
            icon: const Icon(Icons.chat_bubble_outline),
          ),
        ],
      ]),
    );
  }

  // ---- Sekmeler ----
  Widget _profileTab(Map<String, dynamic> p, Map<String, dynamic> card) {
    final family = mapOf(p['family']);
    final supporters = listOf(card['supporters']);
    final bio = (p['bio'] ?? '').toString();
    final place = [p['city'], p['country']].where((e) => e != null && '$e'.isNotEmpty).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (family != null)
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: const Color(0xFF15131F), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white12)),
            child: Row(children: [
              const CircleAvatar(radius: 20, backgroundColor: Color(0xFF7B2CFF), child: Icon(Icons.groups, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${family['name']}'.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 17)),
                  Text('Lvl ${family['level'] ?? 1}', style: const TextStyle(color: Pal.textDim, fontSize: 12)),
                ]),
              ),
              const Text('Aile', style: TextStyle(fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right),
            ]),
          ),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: supporters.isEmpty ? null : () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                    for (final x in supporters)
                      ListTile(leading: UserAvatar(user: mapOf(x['user'])), title: UserName(user: mapOf(x['user'])), trailing: Text('${fmtNumber(x['coins'])} 🪙')),
                  ]),
                ),
              ),
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [Color(0xFF9C5BFF), Color(0xFF22D3EE)])),
            child: Row(children: [
              if (supporters.isEmpty)
                const Text('Henüz destekçi yok', style: TextStyle(color: Colors.white70))
              else
                SizedBox(
                  height: 40,
                  width: 40.0 + 22 * (supporters.length.clamp(1, 5) - 1),
                  child: Stack(children: [
                    for (var i = 0; i < supporters.length.clamp(0, 5); i++)
                      Positioned(left: 22.0 * i, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)), child: UserAvatar(user: mapOf(supporters[i]['user']), radius: 18))),
                  ]),
                ),
              const Spacer(),
              const Text('Top Destekçiler', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: levelBar('Kullanıcı Seviyesi', p['coinLevel'], Icons.workspace_premium, const [Color(0xFFFF4081), Color(0xFF7C4DFF)])),
          const SizedBox(width: 12),
          Expanded(child: levelBar('Yayıncı Seviyesi', p['giftLevel'], Icons.star, const [Color(0xFFFF6D00), Color(0xFFFF1744)])),
        ]),
        const SizedBox(height: 18),
        const Text('Biyografi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 4),
        Text(bio.isEmpty ? 'Bu kullanıcı henüz hakkında bir şey yazmadı.' : bio, style: TextStyle(height: 1.4, color: bio.isEmpty ? Pal.textDim : null)),
        if (place.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [const Icon(Icons.place_outlined, size: 18, color: Pal.cyan), const SizedBox(width: 6), Text(place)])),
      ]),
    );
  }

  Widget _gridTitle(String title) => Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)));

  Widget _achievementsTab(Map<String, dynamic> card) {
    final gifts = listOf(card['gifts']);
    final medals = listOf(card['medals']);
    Widget box(Widget child) => Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white24)),
          padding: const EdgeInsets.all(6),
          child: child,
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _gridTitle('Hediyeler'),
      if (gifts.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Henüz hediye alınmamış.', style: TextStyle(color: Pal.textDim)))
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.9,
            children: [
              for (final g in gifts)
                box(Column(children: [
                  Expanded(
                    child: Api.absoluteUrl(g['iconUrl'] as String?) == null
                        ? const Icon(Icons.card_giftcard, color: Colors.amber)
                        : Image.network(Api.absoluteUrl(g['iconUrl'] as String?)!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.amber)),
                  ),
                  Text('x${g['quantity']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ])),
            ],
          ),
        ),
      _gridTitle('Madalyalar'),
      if (medals.isEmpty)
        const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 24), child: Text('Henüz madalya yok.', style: TextStyle(color: Pal.textDim)))
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [for (final m in medals) box(_medalImg(m, 60))],
          ),
        ),
    ]);
  }

  Widget _relationsTab(Map<String, dynamic> p) {
    Widget row(IconData icon, String title, dynamic count, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: Pal.cyan),
          title: Text(title),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(fmtNumber(count), style: const TextStyle(fontWeight: FontWeight.w800)), const Icon(Icons.chevron_right)]),
          onTap: onTap,
        );
    return Column(children: [
      const SizedBox(height: 8),
      row(Icons.favorite_border, 'Fanlar', p['followers'], () => _push(UserListScreen(title: 'Fanlar', path: '/api/users/${widget.userId}/followers'))),
      row(Icons.person_outline, 'Takip edilenler', p['following'], () => _push(UserListScreen(title: 'Takip edilenler', path: '/api/users/${widget.userId}/following'))),
      row(Icons.people_outline, 'Arkadaşlar', p['friends'], () {
        if (widget.userId == Session.id) _push(const FriendsScreen());
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: _load,
        builder: (context, data, reload) {
          final p = mapOf(data['p']) ?? {};
          final card = mapOf(data['card']) ?? {};
          final isSelf = widget.userId == Session.id;
          final hidden = p['isHidden'] == true && p['username'] == 'Gizli Kullanıcı';
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: EdgeInsets.zero, children: [
              _header(p, hidden),
              if (hidden)
                const Padding(padding: EdgeInsets.all(24), child: Text('Bu kullanıcı profilini gizlemiş.', textAlign: TextAlign.center))
              else ...[
                _medalRow(card),
                if (!isSelf) _actions(p),
                const SizedBox(height: 6),
                _tabs(),
                if (_tab == 0) _profileTab(p, card),
                if (_tab == 1) _achievementsTab(card),
                if (_tab == 2) FeedList(key: ValueKey('posts-${widget.userId}-$_version'), userId: widget.userId, shrink: true),
                if (_tab == 3) _relationsTab(p),
              ],
            ]),
          );
        },
      ),
    );
  }
}

class UserListScreen extends StatelessWidget {
  final String title;
  final String path;
  const UserListScreen({super.key, required this.title, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncBody<List<Map<String, dynamic>>>(
        load: () async => listOf((await Api.get(path))['users']),
        builder: (context, users, reload) => users.isEmpty
            ? const Center(child: Text('Liste boş.'))
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView(children: [
                  for (final u in users)
                    ListTile(
                      leading: UserAvatar(user: u),
                      title: UserName(user: u),
                      subtitle: u['isHidden'] == true && u['username'] == 'Gizli Kullanıcı' ? null : Text('@${u['username']}'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: u['id'] as String))),
                    ),
                ]),
              ),
      ),
    );
  }
}

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      try {
        final r = await Api.get('/api/users/search', query: {'q': v.trim()});
        if (!mounted) return;
        setState(() {
          _results = listOf(r['users']);
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(hintText: 'Kullanıcı ara...', border: InputBorder.none),
        ),
      ),
      body: Column(children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        Expanded(
          child: ListView(children: [
            for (final u in _results)
              ListTile(
                leading: UserAvatar(user: u),
                title: UserName(user: u),
                subtitle: Text('@${u['username']}'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: u['id'] as String))),
              ),
          ]),
        ),
      ]),
    );
  }
}
