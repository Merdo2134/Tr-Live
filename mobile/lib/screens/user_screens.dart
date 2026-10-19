import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/anim_asset.dart';
import '../services/session.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/fig.dart';
import 'guardian_screens.dart';
import 'relations_screens.dart';
import '../widgets/presence_widgets.dart';
import '../widgets/safety_actions.dart';
import 'edit_profile_screen.dart';
import 'family_screen.dart';
import 'feed_screen.dart';
import 'messages_screen.dart';
import '../widgets/level_badge.dart';
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

  static const _ink = Pal.text;
  static const _dim = Pal.textDim;

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

  Widget _profileOf(String id) => UserProfileScreen(userId: id);

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

  // Figma: kapak tam genişlik (375'e 343), çerçeveli avatar kapağın alt kenarında ortada, sağda koruyucu rozeti.
  Widget _header(Map<String, dynamic> p, bool hidden) {
    final cover = Api.absoluteUrl(p['coverUrl'] as String?) ?? Api.absoluteUrl(p['avatarUrl'] as String?);
    final frame = _frameOf(p);
    final wip = mapOf(p['wip']);
    final features = mapOf(wip?['features']);
    final w = MediaQuery.sizeOf(context).width;
    final s = w / 375;
    final coverH = 343 * s;
    final avatarR = 48 * s;
    final isSelf = widget.userId == Session.id;
    final guardianOn = p['guardianEnabled'] != false;
    return SizedBox(
      height: coverH + 92 * s,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: coverH,
          child: cover != null && !hidden
              ? NetImg(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Pal.surface))
              : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFF9AD5), Color(0xFF9C7BFF)], begin: Alignment.topLeft, end: Alignment.bottomRight))),
        ),
        // Avatar + çerçeve (kapağın alt kenarında)
        Positioned(
          left: 0,
          right: 0,
          top: coverH - 86 * s,
          child: Center(
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              if (features?['profileEffect'] == true && wipLevelOf(wip?['level']) != null)
                Positioned(left: -24, top: -24, right: -24, bottom: -24, child: IgnorePointer(child: WipAura(level: wipLevelOf(wip?['level'])!))),
              Container(
                decoration: const BoxDecoration(color: Pal.bg, shape: BoxShape.circle),
                padding: const EdgeInsets.all(2),
                child: UserAvatar(user: p, radius: avatarR),
              ),
              if (frame == null) WipFrame.around(wipLevelOf(p['wipFrame'] ?? wip?['level']), avatarR),
              if (frame != null) IgnorePointer(child: SizedBox(width: avatarR * 2 * kFrameScale, height: avatarR * 2 * kFrameScale, child: AnimAsset(url: frame, repeat: true, cache: false))),
            ]),
          ),
        ),
        // Koruyucu rozeti
        if (!hidden && (guardianOn || isSelf))
          Positioned(
            right: 6 * s,
            top: coverH + 6 * s,
            child: GuardianBadge(ownerId: widget.userId, guardian: mapOf(p['guardian']), size: 72 * s, profileBuilder: _profileOf),
          ),
        // Kendi profilinde sağ üstte düzenle (profil düzenleme sayfası).
        if (isSelf)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 6,
            right: 8,
            child: CircleAvatar(
              backgroundColor: Colors.black26,
              child: IconButton(
                tooltip: 'Profili düzenle',
                icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
                  if (mounted) setState(() => _version++);
                },
              ),
            ),
          ),
        if (!isSelf)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 6,
            right: 8,
            child: CircleAvatar(
              backgroundColor: Colors.black26,
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
    );
  }

  Widget _nameBlock(Map<String, dynamic> p, bool hidden) {
    final wip = mapOf(p['wip']);
    final features = mapOf(wip?['features']);
    return Column(children: [
      UserName(
        user: {'displayName': p['displayName'], 'wipLevel': wip?['level'], 'nameColor': features?['nameColor']},
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: _ink),
      ),
      if (!hidden) ...[
        const SizedBox(height: 6),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
          _genderPill(p),
          LevelPill(level: p['coinLevel'] ?? 1, send: true, height: 18),
          LevelPill(level: p['giftLevel'] ?? 1, send: false, height: 18),
          if (p['broadcaster'] != null) _pill(Icons.podcasts, 'Yayıncı', const Color(0xFFB0003A)),
        ]),
        const SizedBox(height: 4),
        Text('ID: ${p['publicId'] ?? '-'}', style: const TextStyle(color: _dim, fontSize: 12)),
        if (p['presence'] is Map) Padding(padding: const EdgeInsets.only(top: 2), child: PresenceLine(presence: mapOf(p['presence']), fontSize: 12)),
      ],
    ]);
  }

  Widget _genderPill(Map<String, dynamic> p) {
    final female = p['gender'] == 'female';
    final age = p['age'];
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(color: female ? const Color(0xFFFFD1E8) : const Color(0xFFCFE3FF), borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(female ? Icons.female : Icons.male, size: 13, color: female ? const Color(0xFFE6007E) : const Color(0xFF2F7BFF)),
        if (age != null) ...[
          const SizedBox(width: 2),
          Text('$age', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: female ? const Color(0xFFE6007E) : const Color(0xFF2F7BFF))),
        ],
      ]),
    );
  }

  Widget _pill(IconData icon, String text, Color color) => Container(
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
        ]),
      );

  Widget _medalRow(Map<String, dynamic> card) {
    final medals = listOf(card['medals']).take(4).toList();
    if (medals.isEmpty) return const SizedBox(height: 6);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final m in medals) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _medalImg(m, 60)),
      ]),
    );
  }

  Widget _medalImg(Map<String, dynamic> m, double size) {
    final url = Api.absoluteUrl(m['assetUrl'] as String?);
    return SizedBox(width: size, height: size, child: url == null ? const Icon(Icons.military_tech, color: Colors.amber) : NetImg(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.military_tech, color: Colors.amber)));
  }

  Widget _tabs() {
    Widget t(String label, int i) {
      final sel = _tab == i;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: TextStyle(fontSize: sel ? 20 : 17, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, color: sel ? _ink : _dim))),
              const SizedBox(height: 4),
              Container(height: 2.5, width: 32, decoration: BoxDecoration(color: sel ? _ink : Colors.transparent, borderRadius: BorderRadius.circular(2))),
            ]),
          ),
        ),
      );
    }

    return Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: Row(children: [t('Profil', 0), t('Başarılar', 1), t('Paylaşım', 2), t('İlişkiler', 3)]));
  }

  Widget _actions(Map<String, dynamic> p) {
    final st = (p['friendStatus'] ?? 'none').toString();
    final friendLabel = switch (st) { 'friends' => 'Arkadaşsınız', 'requested' => 'İstek gönderildi', 'incoming' => 'İsteği kabul et', _ => 'Arkadaş ekle' };
    final friendIcon = switch (st) { 'friends' => Icons.people, 'requested' => Icons.hourglass_top, 'incoming' => Icons.check, _ => Icons.person_add_alt_1 };
    final following = p['isFollowing'] == true;
    Widget btn(String label, IconData? icon, VoidCallback onTap, {bool filled = false}) => Expanded(
          child: Material(
            color: filled ? const Color(0xFFFF4FA8) : Pal.surfaceHi,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: SizedBox(
                height: 38,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (icon != null) Icon(icon, size: 17, color: filled ? Colors.white : _ink),
                  if (icon != null) const SizedBox(width: 5),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: TextStyle(color: filled ? Colors.white : _ink, fontWeight: FontWeight.w700)))),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(children: [
        btn(following ? 'Takip ediliyor' : 'Takip et', following ? Icons.check : Icons.add, () => _toggleFollow(p), filled: !following),
        const SizedBox(width: 8),
        btn(friendLabel, friendIcon, () => _friendAction(p)),
        if (st == 'friends') ...[
          const SizedBox(width: 8),
          btn('Mesaj', Icons.chat_bubble_outline, () => _push(ChatScreen(peer: {'id': widget.userId, 'displayName': p['displayName'], 'avatarUrl': p['avatarUrl'], 'nameColor': mapOf(mapOf(p['wip'])?['features'])?['nameColor'], 'wipLevel': mapOf(p['wip'])?['level']}))),
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
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (family != null) ...[
          GestureDetector(
            onTap: () => _push(FamilyPage(familyId: '${family['id']}')),
            child: Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(color: const Color(0xFF242424), borderRadius: BorderRadius.circular(16), image: DecorationImage(image: Fig.provider('fam_bar'), fit: BoxFit.fill, onError: (_, __) {})),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF7B2CFF)),
                clipBehavior: Clip.antiAlias,
                child: Api.absoluteUrl(family['logoUrl'] as String?) == null
                    ? const Icon(Icons.groups, color: Colors.white)
                    : NetImg(Api.absoluteUrl(family['logoUrl'] as String?)!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.groups, color: Colors.white)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trUpper('${family['name']}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 19)),
                  Text('Lvl ${family['level'] ?? 1}', style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic, fontSize: 13)),
                ]),
              ),
              const Text('Aile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
              const Icon(Icons.chevron_right, color: Colors.white, size: 28),
            ]),
          ),
          ),
          const SizedBox(height: 10),
        ],
        InkWell(
          borderRadius: BorderRadius.circular(16),
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
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: const LinearGradient(colors: [Color(0xFFB062FF), Color(0xFF5AA8F5), Color(0xFF2EE6F5)])),
            child: Row(children: [
              if (supporters.isEmpty)
                const Text('Henüz destekçi yok', style: TextStyle(color: Colors.white70))
              else
                SizedBox(
                  height: 40,
                  width: 40.0 + 20 * (supporters.length.clamp(1, 3) - 1),
                  child: Stack(children: [
                    for (var i = 0; i < supporters.length.clamp(0, 3); i++)
                      Positioned(left: 20.0 * i, child: UserAvatar(user: mapOf(supporters[i]['user']), radius: 20)),
                  ]),
                ),
              const Spacer(),
              const Text('Top Destekçiler', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
              const Icon(Icons.chevron_right, color: Colors.white, size: 28),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        DefaultTextStyle.merge(
          style: const TextStyle(color: _ink),
          child: Row(children: [
            Expanded(child: levelBar('Kullanıcı Seviyesi', p['coinLevel'], Icons.workspace_premium, const [Color(0xFFE81C8F), Color(0xFFFF2BD6)], send: true)),
            const SizedBox(width: 14),
            Expanded(child: levelBar('Yayıncı Seviyesi', p['giftLevel'], Icons.star, const [Color(0xFFFF3D5A), Color(0xFFFF8A2B)], send: false)),
          ]),
        ),
        const SizedBox(height: 20),
        const Text('Biyografi', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: _ink)),
        const SizedBox(height: 6),
        Text(bio.isEmpty ? 'Bu kullanıcı henüz hakkında bir şey yazmadı.' : bio, style: TextStyle(height: 1.35, fontSize: 13, fontWeight: FontWeight.w500, color: bio.isEmpty ? _dim : _ink)),
        if (place.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [const Icon(Icons.place_outlined, size: 18, color: Color(0xFFFF4FA8)), const SizedBox(width: 6), Text(place, style: const TextStyle(color: _ink))])),
        const SizedBox(height: 18),
        Row(children: [
          _count('Fanlar', p['followers'], () => _push(UserListScreen(title: 'Fanlar', path: '/api/users/${widget.userId}/followers'))),
          _count('Takip', p['following'], () => _push(UserListScreen(title: 'Takip edilenler', path: '/api/users/${widget.userId}/following'))),
          _count('Arkadaş', p['friends'], () {
            if (widget.userId == Session.id) _push(const FriendsScreen());
          }),
        ]),
      ]),
    );
  }

  Widget _count(String label, dynamic n, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Text(fmtNumber(n ?? 0), style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 16)),
              Text(label, style: const TextStyle(color: _dim, fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _gridTitle(String title) => Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _ink)));

  Widget _achievementsTab(Map<String, dynamic> card) {
    final gifts = listOf(card['gifts']);
    final medals = listOf(card['medals']);
    Widget box(Widget child) => Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Pal.surface, border: Border.all(color: Pal.outline)),
          padding: const EdgeInsets.all(6),
          child: child,
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _gridTitle('Hediyeler'),
      if (gifts.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Henüz hediye alınmamış.', style: TextStyle(color: _dim)))
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
                        : NetImg(Api.absoluteUrl(g['iconUrl'] as String?)!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.amber)),
                  ),
                  Text('x${g['quantity']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _ink)),
                ])),
            ],
          ),
        ),
      _gridTitle('Madalyalar'),
      if (medals.isEmpty)
        const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 24), child: Text('Henüz madalya yok.', style: TextStyle(color: _dim)))
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

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: const Color(0xFFFF4FA8))),
      child: Scaffold(
        backgroundColor: Pal.bg,
        body: Stack(children: [
          Positioned.fill(child: AsyncBody<Map<String, dynamic>>(
            version: _version,
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
                  _nameBlock(p, hidden),
                  if (hidden)
                    const Padding(padding: EdgeInsets.all(24), child: Text('Bu kullanıcı profilini gizlemiş.', textAlign: TextAlign.center, style: TextStyle(color: _dim)))
                  else ...[
                    _medalRow(card),
                    if (!isSelf) _actions(p),
                    _tabs(),
                    if (_tab == 0) _profileTab(p, card),
                    if (_tab == 1) _achievementsTab(card),
                    if (_tab == 2) FeedList(key: ValueKey('posts-${widget.userId}-$_version'), userId: widget.userId, shrink: true),
                    if (_tab == 3) RelationWall(key: ValueKey('rel-${widget.userId}-$_version'), userId: widget.userId, displayName: (p['displayName'] ?? '').toString(), profileBuilder: _profileOf),
                  ],
                ]),
              );
            },
          )),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 6,
            left: 10,
            child: CircleAvatar(backgroundColor: Colors.black26, child: IconButton(tooltip: 'Geri', icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white), onPressed: () => Navigator.maybePop(context))),
          ),
        ]),
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
