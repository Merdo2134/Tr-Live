import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/image_pick.dart';
import 'user_screens.dart';

String timeAgo(dynamic iso) {
  final t = DateTime.tryParse('$iso')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'az önce';
  if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
  if (d.inHours < 24) return '${d.inHours} sa. önce';
  if (d.inDays < 7) return '${d.inDays} gün önce';
  return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
}

/// Keşfet sekmesi: "Takip Edilen | Genel" gönderi akışı ve gönderi paylaşma.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  bool _following = false;
  int _version = 0;

  Future<void> _compose() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ComposePostScreen()));
    if (ok == true && mounted) setState(() => _version++);
  }

  Widget _seg(String label, bool sel, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(color: sel ? Pal.cyan : Colors.transparent, borderRadius: BorderRadius.circular(20)),
            child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: sel ? const Color(0xFF00212A) : Pal.textDim))),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _compose, tooltip: 'Paylaş', child: const Icon(Icons.add_a_photo)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            const Expanded(child: Text('Keşfet', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Pal.text))),
            Container(
              width: 210,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: Pal.outline)),
              child: Row(children: [
                _seg('Takip Edilen', _following, () => setState(() => _following = true)),
                _seg('Genel', !_following, () => setState(() => _following = false)),
              ]),
            ),
          ]),
        ),
        Expanded(child: FeedList(key: ValueKey('$_following-$_version'), scope: _following ? 'following' : 'all')),
      ]),
    );
  }
}

/// Sayfalı gönderi listesi. [userId] verilirse yalnızca o kullanıcının gönderileri gösterilir.
class FeedList extends StatefulWidget {
  final String scope;
  final String? userId;
  final bool shrink;
  const FeedList({super.key, this.scope = 'all', this.userId, this.shrink = false});

  @override
  State<FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<FeedList> {
  final List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _more = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      final before = reset || _posts.isEmpty ? null : _posts.last['createdAt'].toString();
      final r = await Api.get('/api/posts', query: {'scope': widget.scope, if (widget.userId != null) 'userId': widget.userId!, if (before != null) 'before': before});
      if (!mounted) return;
      setState(() {
        if (reset) _posts.clear();
        _posts.addAll(listOf(r['posts']));
        _more = r['hasMore'] == true;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    if (_error != null && _posts.isEmpty) return LoadError(message: _error!, onRetry: () => _load(reset: true));
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(shrinkWrap: widget.shrink, physics: widget.shrink ? const NeverScrollableScrollPhysics() : null, children: [
          const SizedBox(height: 80),
          Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(widget.scope == 'following' ? 'Takip ettiklerinin henüz gönderisi yok.' : 'Henüz gönderi yok. İlk paylaşımı sen yap!', textAlign: TextAlign.center, style: const TextStyle(color: Pal.textDim)))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        shrinkWrap: widget.shrink,
        physics: widget.shrink ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _posts.length + (_more ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _posts.length) {
            _load();
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          }
          return PostCard(
            key: ValueKey(_posts[i]['id']),
            post: _posts[i],
            onDeleted: () => setState(() => _posts.removeAt(i)),
          );
        },
      ),
    );
  }
}

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback onDeleted;
  const PostCard({super.key, required this.post, required this.onDeleted});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _liked = widget.post['liked'] == true;
  late int _likes = (widget.post['likeCount'] as num?)?.toInt() ?? 0;
  late int _comments = (widget.post['commentCount'] as num?)?.toInt() ?? 0;
  late bool _following = widget.post['following'] == true;

  Map<String, dynamic>? get _user => mapOf(widget.post['user']);

  Future<void> _like() async {
    final was = _liked;
    setState(() {
      _liked = !was;
      _likes += was ? -1 : 1;
    });
    try {
      final r = was ? await Api.delete('/api/posts/${widget.post['id']}/like') : await Api.post('/api/posts/${widget.post['id']}/like');
      if (mounted) setState(() => _likes = (r['likeCount'] as num).toInt());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = was;
        _likes += was ? 1 : -1;
      });
      toast(context, errorText(e), error: true);
    }
  }

  Future<void> _follow() async {
    final id = _user?['id'];
    final r = await guard<bool>(context, () async {
      await Api.post('/api/users/$id/follow');
      return true;
    });
    if (r == true && mounted) setState(() => _following = true);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Bu gönderi silinsin mi?', action: 'Sil')) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.delete('/api/posts/${widget.post['id']}'));
    if (r != null) widget.onDeleted();
  }

  Future<void> _openComments() async {
    final added = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CommentsSheet(postId: widget.post['id'].toString()),
    );
    if (added != null && mounted) setState(() => _comments += added);
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final img = Api.absoluteUrl(widget.post['imageUrl'] as String?);
    final text = (widget.post['text'] ?? '').toString();
    final mine = widget.post['mine'] == true;
    final staff = Session.isStaff;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Pal.outline, width: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: u == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: u['id'] as String))),
            child: UserAvatar(user: u, radius: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              UserName(user: u, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(timeAgo(widget.post['createdAt']), style: const TextStyle(color: Pal.textDim, fontSize: 12)),
            ]),
          ),
          if (!mine && !_following)
            FilledButton(
              onPressed: _follow,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 14), backgroundColor: Pal.amber, foregroundColor: const Color(0xFF2A1D00)),
              child: const Text('Takip et +', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          if (mine || staff) IconButton(tooltip: 'Sil', icon: const Icon(Icons.delete_outline, color: Pal.textDim), onPressed: _delete),
        ]),
        if (img != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: Image.network(img, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 120, child: Center(child: Icon(Icons.broken_image, color: Pal.textDim)))),
              ),
            ),
          ),
        if (text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(text, style: const TextStyle(fontSize: 14.5, height: 1.35))),
        const SizedBox(height: 6),
        Row(children: [
          TextButton.icon(
            onPressed: _like,
            style: TextButton.styleFrom(foregroundColor: _liked ? Pal.pink : Pal.textDim, padding: const EdgeInsets.symmetric(horizontal: 8)),
            icon: Icon(_liked ? Icons.favorite : Icons.favorite_border, size: 20),
            label: Text('$_likes'),
          ),
          TextButton.icon(
            onPressed: _openComments,
            style: TextButton.styleFrom(foregroundColor: Pal.textDim, padding: const EdgeInsets.symmetric(horizontal: 8)),
            icon: const Icon(Icons.mode_comment_outlined, size: 20),
            label: Text('$_comments'),
          ),
        ]),
      ]),
    );
  }
}

class CommentsSheet extends StatefulWidget {
  final String postId;
  const CommentsSheet({super.key, required this.postId});

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  List<Map<String, dynamic>> _items = [];
  final _ctl = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  int _added = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/api/posts/${widget.postId}/comments');
      if (!mounted) return;
      setState(() {
        _items = listOf(r['comments']);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final t = _ctl.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    final r = await guard(context, () => Api.post('/api/posts/${widget.postId}/comments', {'text': t}));
    if (!mounted) return;
    setState(() => _sending = false);
    if (r != null) {
      _ctl.clear();
      _added++;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _added);
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: h * 0.7,
          child: Column(children: [
            const SizedBox(height: 12),
            const Text('Yorumlar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const Divider(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? LoadError(message: _error!, onRetry: _load)
                      : _items.isEmpty
                          ? const Center(child: Text('İlk yorumu sen yaz.', style: TextStyle(color: Pal.textDim)))
                          : ListView(children: [
                              for (final c in _items)
                                ListTile(
                                  leading: UserAvatar(user: mapOf(c['user']), radius: 18),
                                  title: UserName(user: mapOf(c['user']), style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text('${c['text']}'),
                                  trailing: Text(timeAgo(c['createdAt']), style: const TextStyle(color: Pal.textDim, fontSize: 11)),
                                ),
                            ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 12),
              child: Row(children: [
                Expanded(child: TextField(controller: _ctl, maxLength: 300, buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null, decoration: const InputDecoration(hintText: 'Yorum yaz…', isDense: true), onSubmitted: (_) => _send())),
                IconButton(onPressed: _sending ? null : _send, icon: const Icon(Icons.send, color: Pal.cyan)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class ComposePostScreen extends StatefulWidget {
  const ComposePostScreen({super.key});

  @override
  State<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<ComposePostScreen> {
  final _text = TextEditingController();
  PickedImage? _image;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final p = await pickImage(context);
    if (p != null && mounted) setState(() => _image = p);
  }

  Future<void> _publish() async {
    final t = _text.text.trim();
    if (t.isEmpty && _image == null) return toast(context, 'Bir metin yazın veya görsel ekleyin.', error: true);
    setState(() => _busy = true);
    final ok = await guard<bool>(context, () async {
      String? url;
      if (_image != null) url = (await Api.putBytes('/api/posts/image', _image!.bytes, _image!.mime))['url'] as String?;
      await Api.post('/api/posts', {'text': t, if (url != null) 'imageUrl': url});
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni gönderi'),
        actions: [TextButton(onPressed: _busy ? null : _publish, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Paylaş', style: TextStyle(fontWeight: FontWeight.w800)))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _text, maxLines: 6, maxLength: 1000, decoration: const InputDecoration(hintText: 'Ne düşünüyorsun?')),
        const SizedBox(height: 12),
        if (_image != null)
          Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(_image!.bytes, width: double.infinity, fit: BoxFit.cover)),
            Positioned(top: 6, right: 6, child: IconButton.filled(onPressed: () => setState(() => _image = null), icon: const Icon(Icons.close))),
          ])
        else
          OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.photo_library_outlined), label: const Text('Görsel ekle')),
      ]),
    );
  }
}
