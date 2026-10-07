import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/common.dart';
import 'user_screens.dart';

const _roleNames = {'owner': 'Aile sahibi', 'admin': 'Yönetici', 'member': 'Üye'};

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  int _version = 0;

  void _changed() {
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Map<String, dynamic>?>(
      key: ValueKey(_version),
      load: () async => mapOf((await Api.get('/api/families/mine'))['family']),
      builder: (context, family, reload) =>
          family == null ? _FamilyBrowser(onChanged: _changed) : _FamilyDetail(family: family, onChanged: _changed),
    );
  }
}

/// Aile yokken: aileleri ara, katıl veya yeni aile kur.
class _FamilyBrowser extends StatefulWidget {
  final VoidCallback onChanged;
  const _FamilyBrowser({required this.onChanged});

  @override
  State<_FamilyBrowser> createState() => _FamilyBrowserState();
}

class _FamilyBrowserState extends State<_FamilyBrowser> {
  final _search = TextEditingController();
  int _version = 0;

  Widget _logo(Map<String, dynamic> f) {
    final url = Api.absoluteUrl(f['logoUrl'] as String?);
    return CircleAvatar(
      backgroundImage: url == null ? null : NetworkImage(url),
      onBackgroundImageError: url == null ? null : (_, __) {},
      child: url == null ? const Icon(Icons.groups) : null,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Aile kur'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtl, maxLength: 40, decoration: const InputDecoration(labelText: 'Aile adı')),
          TextField(controller: descCtl, maxLength: 300, maxLines: 2, decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kur')),
        ],
      ),
    );
    final name = nameCtl.text.trim();
    final desc = descCtl.text.trim();
    nameCtl.dispose();
    descCtl.dispose();
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.post('/api/families', {'name': name, 'description': desc}));
    if (r != null) widget.onChanged();
  }

  Future<void> _join(Map<String, dynamic> f) async {
    if (!await confirm(context, '"${f['name']}" ailesine katılmak istiyor musunuz?', action: 'Katıl')) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.post('/api/families/${f['id']}/join'));
    if (r != null) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => setState(() => _version++),
              decoration: InputDecoration(
                hintText: 'Aile ara',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => setState(() => _version++)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Kur')),
        ]),
      ),
      Expanded(
        child: AsyncBody<List<Map<String, dynamic>>>(
          key: ValueKey('$_version${_search.text}'),
          load: () async => listOf((await Api.get('/api/families', query: {'q': _search.text.trim()}))['families']),
          builder: (context, list, reload) => list.isEmpty
              ? const Center(child: Text('Aile bulunamadı.'))
              : RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(children: [
                    for (final f in list)
                      ListTile(
                        leading: _logo(f),
                        title: Text(f['name'].toString()),
                        subtitle: Text('Seviye ${f['level']} · ${f['memberCount']}/${f['capacity']} üye · ${fmtNumber(f['totalPoints'])} puan'),
                        trailing: OutlinedButton(onPressed: () => _join(f), child: const Text('Katıl')),
                      ),
                  ]),
                ),
        ),
      ),
    ]);
  }
}

class _FamilyDetail extends StatefulWidget {
  final Map<String, dynamic> family;
  final VoidCallback onChanged;
  const _FamilyDetail({required this.family, required this.onChanged});

  @override
  State<_FamilyDetail> createState() => _FamilyDetailState();
}

class _FamilyDetailState extends State<_FamilyDetail> {
  int _v = 0;

  String get _id => widget.family['id'].toString();
  String get _myRole => (widget.family['myRole'] ?? 'member').toString();

  Future<void> _run(String message, Future<Map<String, dynamic>> Function() action, {bool leaves = false}) async {
    if (!await confirm(context, message)) return;
    if (!mounted) return;
    final r = await guard(context, action);
    if (r == null || !mounted) return;
    leaves ? widget.onChanged() : setState(() => _v++);
  }

  Future<void> _editDescription() async {
    final d = await askText(context, 'Aile açıklaması', initial: (widget.family['description'] ?? '').toString());
    if (d == null || !mounted) return;
    final r = await guard(context, () => Api.patch('/api/families/$_id', {'description': d}));
    if (r != null) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.family;
    return AsyncBody<List<Map<String, dynamic>>>(
      key: ValueKey(_v),
      load: () async => listOf((await Api.get('/api/families/$_id/members'))['members']),
      builder: (context, members, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.groups, size: 32),
                  const SizedBox(width: 12),
                  Expanded(child: Text(f['name'].toString(), style: Theme.of(context).textTheme.titleLarge)),
                  if (_myRole != 'member') IconButton(tooltip: 'Açıklamayı düzenle', icon: const Icon(Icons.edit), onPressed: _editDescription),
                ]),
                if ((f['description'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(f['description'].toString())),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  Chip(label: Text('Seviye ${f['level']}'), visualDensity: VisualDensity.compact),
                  Chip(label: Text('${members.length}/${f['capacity']} üye'), visualDensity: VisualDensity.compact),
                  Chip(label: Text('${fmtNumber(f['totalPoints'])} puan'), visualDensity: VisualDensity.compact),
                  Chip(label: Text(_roleNames[_myRole] ?? _myRole), visualDensity: VisualDensity.compact),
                ]),
                const SizedBox(height: 4),
                const Text('Aile puanı, aile üyelerinin aldığı hediyelerle artar.', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
          ),
          for (final m in members) _memberTile(m),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _myRole == 'owner'
                ? OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                    onPressed: () => _run('Aile dağıtılsın mı? Tüm üyeler ailesiz kalır.', () => Api.delete('/api/families/$_id'), leaves: true),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Aileyi dağıt'),
                  )
                : OutlinedButton.icon(
                    onPressed: () => _run('Aileden ayrılmak istiyor musunuz?', () => Api.post('/api/families/$_id/leave'), leaves: true),
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('Aileden ayrıl'),
                  ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> m) {
    final user = mapOf(m['user']);
    final role = (m['role'] ?? 'member').toString();
    final userId = m['userId'].toString();
    final canKick = (_myRole == 'owner' && role != 'owner') || (_myRole == 'admin' && role == 'member');
    return ListTile(
      leading: UserAvatar(user: user),
      title: UserName(user: user),
      subtitle: Text(_roleNames[role] ?? role),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId))),
      trailing: (canKick || (_myRole == 'owner' && role != 'owner'))
          ? PopupMenuButton<String>(
              onSelected: (a) {
                if (a == 'kick') _run('Bu üye aileden atılsın mı?', () => Api.post('/api/families/$_id/members/$userId/kick'));
                if (a == 'admin') _run('Bu üye yönetici yapılsın mı?', () => Api.post('/api/families/$_id/members/$userId/role', {'role': 'admin'}));
                if (a == 'member') _run('Yöneticilik alınsın mı?', () => Api.post('/api/families/$_id/members/$userId/role', {'role': 'member'}));
                if (a == 'transfer') _run('Aile sahipliği bu kullanıcıya devredilsin mi? Siz yönetici olarak kalırsınız.', () => Api.post('/api/families/$_id/transfer', {'userId': userId}), leaves: true);
              },
              itemBuilder: (_) => [
                if (_myRole == 'owner' && role == 'member') const PopupMenuItem(value: 'admin', child: Text('Yönetici yap')),
                if (_myRole == 'owner' && role == 'admin') const PopupMenuItem(value: 'member', child: Text('Yöneticiliği al')),
                if (_myRole == 'owner') const PopupMenuItem(value: 'transfer', child: Text('Sahipliği devret')),
                if (canKick) const PopupMenuItem(value: 'kick', child: Text('Aileden at')),
              ],
            )
          : null,
    );
  }
}
