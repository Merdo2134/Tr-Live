import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/image_pick.dart';

/// Yönetici: ana sayfa banner'ları ve Mesajlar ekranındaki duyurular.
class ContentTab extends StatefulWidget {
  const ContentTab({super.key});

  @override
  State<ContentTab> createState() => _ContentTabState();
}

class _ContentTabState extends State<ContentTab> {
  List<Map<String, dynamic>> _banners = [];
  List<Map<String, dynamic>> _news = [];
  bool _loading = true;

  static const _kinds = {'team': 'Ekip', 'event': 'Etkinlik', 'reward': 'Ödül'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await Api.get('/api/admin/banners');
      final a = await Api.get('/api/announcements');
      if (!mounted) return;
      setState(() {
        _banners = listOf(b['banners']);
        _news = listOf(a['announcements']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, errorText(e), error: true);
    }
  }

  Future<void> _addBanner() async {
    final img = await pickImage(context, maxWidth: 1600);
    if (img == null || !mounted) return;
    final f = await formDialog(context, 'Banner', ['Başlık (isteğe bağlı)', 'Bağlantı (https://…, isteğe bağlı)']);
    if (f == null || !mounted) return;
    final ok = await guard<bool>(context, () async {
      final up = await Api.putBytes('/api/admin/banners/image', img.bytes, img.mime);
      await Api.post('/api/admin/banners', {'imageUrl': up['url'], 'title': f['Başlık (isteğe bağlı)'], 'linkUrl': f['Bağlantı (https://…, isteğe bağlı)']});
      return true;
    });
    if (ok == true) _load();
  }

  Future<void> _toggleBanner(Map<String, dynamic> b) async {
    final r = await guard(context, () => Api.patch('/api/admin/banners/${b['id']}', {'active': b['active'] != true}));
    if (r != null) _load();
  }

  Future<void> _deleteBanner(Map<String, dynamic> b) async {
    if (!await confirm(context, 'Banner silinsin mi?', action: 'Sil')) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.delete('/api/admin/banners/${b['id']}'));
    if (r != null) _load();
  }

  Future<void> _addNews() async {
    var kind = 'event';
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('Duyuru ekle'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [for (final e in _kinds.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                selected: {kind},
                onSelectionChanged: (v) => setS(() => kind = v.first),
              ),
              const SizedBox(height: 8),
              TextField(controller: title, maxLength: 80, decoration: const InputDecoration(labelText: 'Başlık')),
              TextField(controller: body, maxLines: 5, maxLength: 2000, decoration: const InputDecoration(labelText: 'Metin')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yayınla')),
          ],
        ),
      ),
    );
    final t = title.text.trim();
    final b = body.text.trim();
    title.dispose();
    body.dispose();
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.post('/api/admin/announcements', {'kind': kind, 'title': t, 'text': b}));
    if (r != null) _load();
  }

  Future<void> _deleteNews(Map<String, dynamic> a) async {
    if (!await confirm(context, 'Duyuru silinsin mi?', action: 'Sil')) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.delete('/api/admin/announcements/${a['id']}'));
    if (r != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        const Expanded(child: Text('Ana sayfa banner’ları', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        FilledButton.icon(onPressed: _addBanner, icon: const Icon(Icons.add_photo_alternate), label: const Text('Ekle')),
      ]),
      const SizedBox(height: 8),
      if (_banners.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Henüz banner yok.', style: TextStyle(color: Pal.textDim))),
      for (final b in _banners)
        Card(
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 72, height: 40, child: Image.network(Api.absoluteUrl(b['imageUrl'] as String?) ?? '', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Pal.surfaceHi))),
            ),
            title: Text((b['title'] ?? 'Başlıksız').toString()),
            subtitle: Text(b['active'] == true ? 'Yayında' : 'Gizli'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(value: b['active'] == true, onChanged: (_) => _toggleBanner(b)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteBanner(b)),
            ]),
          ),
        ),
      const Divider(height: 32),
      Row(children: [
        const Expanded(child: Text('Duyurular', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        FilledButton.icon(onPressed: _addNews, icon: const Icon(Icons.campaign), label: const Text('Ekle')),
      ]),
      const SizedBox(height: 8),
      if (_news.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Henüz duyuru yok.', style: TextStyle(color: Pal.textDim))),
      for (final a in _news)
        Card(
          child: ListTile(
            title: Text('${_kinds[a['kind']] ?? ''} · ${a['title']}'),
            subtitle: Text('${a['text']}', maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteNews(a)),
          ),
        ),
    ]);
  }
}
