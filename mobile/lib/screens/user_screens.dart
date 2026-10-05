import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/safety_actions.dart';
import 'feed_screen.dart';
import 'messages_screen.dart';

/// Kapak, avatar (çerçeveli), isim, rozetler ve sayaçlar. Kendi ve başkasının profilinde ortak kullanılır.
class ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> p;
  final List<Widget> actions;
  final VoidCallback? onFollowers;
  final VoidCallback? onFollowing;
  final VoidCallback? onVisitors;
  const ProfileHeader({super.key, required this.p, this.actions = const [], this.onFollowers, this.onFollowing, this.onVisitors});

  String? get _frameUrl {
    final items = p['equipped'];
    if (items is! List) return null;
    for (final i in items) {
      if (i is Map && i['itemType'] == 'frame') return Api.absoluteUrl(i['assetUrl'] as String?);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cover = Api.absoluteUrl(p['coverUrl'] as String?);
    final wip = mapOf(p['wip']);
    final family = mapOf(p['family']);
    final broadcaster = mapOf(p['broadcaster']);
    final agency = mapOf(broadcaster?['agency']);
    final hidden = p['isHidden'] == true && p['username'] == 'Gizli Kullanıcı';
    final frame = _frameUrl;
    final features = mapOf(wip?['features']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 190,
        child: Stack(children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: cover != null
                ? Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.white12))
                : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFFFF4081)]))),
          ),
          Positioned(
            left: 16,
            bottom: 0,
            child: Stack(alignment: Alignment.center, children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).scaffoldBackgroundColor),
                child: UserAvatar(user: p, radius: 44),
              ),
              if (frame != null) IgnorePointer(child: Image.network(frame, width: 112, height: 112, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
            ]),
          ),
          Positioned(right: 12, bottom: 4, child: Row(children: actions)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          UserName(
            user: {'displayName': p['displayName'], 'wipLevel': wip?['level'], 'nameColor': features?['nameColor']},
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (!hidden) Text('@${p['username']}', style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            Chip(label: Text('Seviye ${p['coinLevel']}'), avatar: const Icon(Icons.monetization_on, size: 16, color: Colors.amber), visualDensity: VisualDensity.compact),
            Chip(label: Text('Hediye ${p['giftLevel']}'), avatar: const Icon(Icons.diamond, size: 16, color: Colors.cyanAccent), visualDensity: VisualDensity.compact),
            if (family != null) Chip(label: Text(family['name'].toString()), avatar: const Icon(Icons.groups, size: 16), visualDensity: VisualDensity.compact),
            if (broadcaster != null)
              Chip(
                label: Text(agency != null ? 'Yayıncı · ${agency['name']}' : 'Yayıncı'),
                avatar: const Icon(Icons.podcasts, size: 16, color: Colors.pinkAccent),
                visualDensity: VisualDensity.compact,
              ),
          ]),
          if (!hidden && (p['bio'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(p['bio'].toString())),
          if (!hidden && (p['city'] != null || p['country'] != null || p['age'] != null))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [if (p['age'] != null) '${p['age']} yaş', if (p['city'] != null) p['city'], if (p['country'] != null) p['country']].join(' · '),
                style: const TextStyle(color: Colors.white60),
              ),
            ),
          if (!hidden) ...[
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _Stat('Takipçi', p['followers'], onFollowers),
              _Stat('Takip', p['following'], onFollowing),
              if (p['visitorCount'] != null) _Stat('Ziyaretçi', p['visitorCount'], onVisitors),
            ]),
          ],
        ]),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final dynamic value;
  final VoidCallback? onTap;
  const _Stat(this.label, this.value, this.onTap);

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            Text(fmtNumber(value), style: Theme.of(context).textTheme.titleMedium),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
      );
}

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  int _version = 0;
  bool _postsTab = false;

  Widget _tabs() {
    Widget t(String label, bool sel, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: sel ? Pal.cyan : Pal.outline, width: sel ? 2.5 : 1))),
              child: Center(child: Text(label, style: TextStyle(fontSize: 16, fontWeight: sel ? FontWeight.w800 : FontWeight.w500, color: sel ? Pal.cyan : Pal.textDim))),
            ),
          ),
        );
    return Row(children: [t('Profil', !_postsTab, () => setState(() => _postsTab = false)), t('Paylaşım', _postsTab, () => setState(() => _postsTab = true))]);
  }

  Widget _info(Map<String, dynamic> p) {
    final place = [p['city'], p['country']].where((e) => e != null && '$e'.isNotEmpty).join(', ');
    final bio = (p['bio'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (place.isNotEmpty) Row(children: [const Icon(Icons.place_outlined, size: 18, color: Pal.cyan), const SizedBox(width: 6), Text(place)]),
        if (bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(bio, style: const TextStyle(height: 1.4))),
        if (place.isEmpty && bio.isEmpty) const Text('Bu kullanıcı henüz hakkında bir şey yazmadı.', style: TextStyle(color: Pal.textDim)),
      ]),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          if (widget.userId != Session.id)
            PopupMenuButton<String>(
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
        ],
      ),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: () async => mapOf((await Api.get('/api/users/${widget.userId}'))['profile']) ?? {},
        builder: (context, p, reload) {
          final isSelf = widget.userId == Session.id;
          final hidden = p['isHidden'] == true && p['username'] == 'Gizli Kullanıcı';
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(children: [
              ProfileHeader(
                p: p,
                onFollowers: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserListScreen(title: 'Takipçiler', path: '/api/users/${widget.userId}/followers'))),
                onFollowing: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserListScreen(title: 'Takip edilenler', path: '/api/users/${widget.userId}/following'))),
              ),
              if (!isSelf && !hidden)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Expanded(
                      child: p['isFollowing'] == true
                          ? OutlinedButton.icon(onPressed: () => _toggleFollow(p), icon: const Icon(Icons.check), label: const Text('Takip ediliyor'))
                          : FilledButton.icon(onPressed: () => _toggleFollow(p), icon: const Icon(Icons.person_add), label: const Text('Takip et')),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: {'id': widget.userId, 'displayName': p['displayName'], 'avatarUrl': p['avatarUrl'], 'nameColor': mapOf(mapOf(p['wip'])?['features'])?['nameColor'], 'wipLevel': mapOf(p['wip'])?['level']}))),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Mesaj'),
                    ),
                  ]),
                ),
              if (hidden) const Padding(padding: EdgeInsets.all(24), child: Text('Bu kullanıcı profilini gizlemiş.', textAlign: TextAlign.center)),
              if (!hidden) ...[
                _tabs(),
                if (_postsTab) FeedList(key: ValueKey('posts-${widget.userId}-$_version'), userId: widget.userId, shrink: true) else _info(p),
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
