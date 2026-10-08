import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api.dart';
import 'common.dart';

const _yellow = Color(0xFFFFE100);
const roleLabels = {'owner': 'Oda sahibi', 'cohost': 'Yardımcı sahip', 'moderator': 'Moderatör', 'user': 'Üye'};
const presetTags = ['Sohbet', 'Eğlence', 'Müzik', 'Yarışma', 'Film'];
const _tagColors = {
  'Sohbet': [Color(0xFF00B4FF), Color(0xFF0066FF)],
  'Eğlence': [Color(0xFFFF3DCB), Color(0xFFC800FF)],
  'Müzik': [Color(0xFF8BD400), Color(0xFF2FB500)],
  'Yarışma': [Color(0xFFB000FF), Color(0xFF7A00FF)],
  'Film': [Color(0xFFFF2D55), Color(0xFFC40030)],
};

Widget tagChip(String t, {bool selected = true, VoidCallback? onTap}) {
  final c = _tagColors[t] ?? const [Color(0xFF00B4FF), Color(0xFF0066FF)];
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: c),
        borderRadius: BorderRadius.circular(14),
        border: selected ? Border.all(color: Colors.white, width: 1.5) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (selected && onTap != null) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.check_circle, size: 14, color: Colors.white)),
        Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
      ]),
    ),
  );
}

Widget _sheetShell(BuildContext c, String title, Widget child, {double height = 0.75}) {
  return SafeArea(
    child: Container(
      height: MediaQuery.sizeOf(c).height * height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A3A3F), Color(0xFF111114)]),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
          child: Row(children: [
            const SizedBox(width: 40),
            Expanded(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(c),
              child: const CircleAvatar(radius: 18, backgroundColor: _yellow, child: Icon(Icons.close, color: Colors.black, size: 22)),
            ),
          ]),
        ),
        Expanded(child: child),
      ]),
    ),
  );
}

/// İzleyiciler listesi.
void showViewers(BuildContext context, List<Map<String, dynamic>> members, void Function(Map<String, dynamic>) onTap) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) => _sheetShell(
      c,
      'İzleyiciler (${members.length})',
      ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        for (final m in members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: UserAvatar(user: mapOf(m['user']), radius: 24),
            title: UserName(user: mapOf(m['user'])),
            subtitle: Text(roleLabels[m['role']] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: m['microphone'] == true ? const Icon(Icons.mic, size: 18, color: Colors.greenAccent) : null,
            onTap: () {
              Navigator.pop(c);
              onTap(m);
            },
          ),
      ]),
    ),
  );
}

/// Katkı listesi (odaya en çok hediye gönderenler).
void showContributions(BuildContext context, String roomId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) => _sheetShell(c, 'Katkı Listesi', _Contributions(roomId: roomId), height: 0.85),
  );
}

class _Contributions extends StatefulWidget {
  final String roomId;
  const _Contributions({required this.roomId});
  @override
  State<_Contributions> createState() => _ContributionsState();
}

class _ContributionsState extends State<_Contributions> {
  bool _total = true;
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _rows = null; _error = null; });
    try {
      final r = await Api.get('/api/rooms/${widget.roomId}/contributions', query: {'range': _total ? 'total' : 'day'});
      if (mounted) setState(() => _rows = listOf(r['contributions']));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Widget _tab(String label, bool active, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: active ? _yellow : Colors.white24, borderRadius: BorderRadius.circular(6)),
            child: Center(child: Text(label, style: TextStyle(color: active ? Colors.black : Colors.white70, fontWeight: FontWeight.w800))),
          ),
        ),
      );

  Widget _podium(Map<String, dynamic>? row, int rank, double h) {
    final colors = {1: const Color(0xFF7B2CFF), 2: const Color(0xFF3B6BFF), 3: const Color(0xFF3B6BFF)};
    if (row == null) return Expanded(child: SizedBox(height: h));
    final u = mapOf(row['user']);
    return Expanded(
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text(rank == 1 ? '👑' : '🥈', style: TextStyle(fontSize: rank == 1 ? 26 : 20)),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.amber, width: 2.5)),
          child: UserAvatar(user: u, radius: rank == 1 ? 34 : 28),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: colors[rank], borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
          child: Column(children: [
            Text((u?['displayName'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            Text(fmtCompact(row['total']), style: const TextStyle(fontWeight: FontWeight.w800)),
            const Icon(Icons.diamond, size: 14, color: Colors.lightBlueAccent),
            Text('$rank', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            _tab('24 Saat.', !_total, () { if (_total) { _total = false; _load(); } }),
            _tab('Toplam', _total, () { if (!_total) { _total = true; _load(); } }),
          ]),
        ),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
      else if (rows == null) const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (rows.isEmpty) const Expanded(child: Center(child: Text('Henüz katkı yok.', style: TextStyle(color: Colors.white60))))
      else
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
            SizedBox(
              height: 190,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _podium(rows.length > 1 ? rows[1] : null, 2, 150),
                _podium(rows[0], 1, 190),
                _podium(rows.length > 2 ? rows[2] : null, 3, 140),
              ]),
            ),
            const SizedBox(height: 8),
            for (var i = 3; i < rows.length; i++) ...[
              ListTile(
                leading: SizedBox(
                  width: 92,
                  child: Row(children: [
                    SizedBox(width: 30, child: Text('${i + 1}-', style: const TextStyle(fontWeight: FontWeight.w800))),
                    UserAvatar(user: mapOf(rows[i]['user']), radius: 22),
                  ]),
                ),
                title: UserName(user: mapOf(rows[i]['user'])),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.diamond, size: 18, color: Colors.lightBlueAccent),
                  Text(fmtCompact(rows[i]['total']), style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
              const Divider(height: 1, color: Colors.white12),
            ],
          ]),
        ),
    ]);
  }
}

String fmtCompact(dynamic v) {
  final n = BigInt.tryParse(v.toString()) ?? BigInt.zero;
  if (n >= BigInt.from(1000000)) return '${(n.toInt() / 1000000).toStringAsFixed(1)}M';
  if (n >= BigInt.from(1000)) return '${(n.toInt() / 1000).toStringAsFixed(n >= BigInt.from(100000) ? 0 : 1)}K';
  return n.toString();
}

/// Oda kartı: kapak, başlık, duyuru, isim kartı (etiketler), yöneticiler.
void showRoomCard(
  BuildContext context, {
  required Map<String, dynamic> room,
  required Map<String, dynamic>? owner,
  required List<Map<String, dynamic>> managers,
  required bool canEdit,
  required VoidCallback onEdit,
  required VoidCallback onSettings,
}) {
  final cover = Api.absoluteUrl(room['coverUrl'] as String?) ?? Api.absoluteUrl(owner?['avatarUrl'] as String?);
  final tags = ((room['tags'] as List?) ?? const []).map((e) => e.toString()).toList();
  final announcement = (room['announcement'] ?? '').toString();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) => SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.85),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A3A3F), Color(0xFF111114)]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(14), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 96,
              height: 104,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: _yellow, width: 3), color: Colors.white12),
              clipBehavior: Clip.antiAlias,
              child: cover == null ? const Icon(Icons.image, color: Colors.white38, size: 36) : Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white38)),
            ),
            const Spacer(),
            if (canEdit)
              GestureDetector(
                onTap: () { Navigator.pop(c); onEdit(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: _yellow, borderRadius: BorderRadius.circular(18)),
                  child: const Text('Düzenle', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
                ),
              ),
            const SizedBox(width: 10),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(c),
              child: const CircleAvatar(radius: 18, backgroundColor: _yellow, child: Icon(Icons.close, color: Colors.black, size: 22)),
            ),
          ]),
          const SizedBox(height: 12),
          Text((room['name'] ?? '').toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          if ((room['roomNumber'] ?? '').toString().isNotEmpty) Text('Oda ID: ${room['roomNumber']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 14),
          const Text('Oda Duyurusu', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(announcement.isEmpty ? 'Henüz duyuru yok.' : announcement, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 14),
          const Text('Oda İsim Kartı', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final t in tags) tagChip(t, selected: false), if (tags.isEmpty) const Text('Etiket yok', style: TextStyle(color: Colors.white54))]),
          const SizedBox(height: 14),
          const Text('Oda Yöneticileri', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (final m in managers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: UserAvatar(user: mapOf(m['user']), radius: 22),
              title: UserName(user: mapOf(m['user'])),
              subtitle: Text(roleLabels['${m['role']}'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          if (canEdit)
            TextButton.icon(
              onPressed: () { Navigator.pop(c); onSettings(); },
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Oda ayarları (kilit, gizleme, tema…)'),
            ),
        ]),
      ),
    ),
  );
}

/// Oda bilgilerini düzenleme sayfası (kapak, başlık, duyuru, isim kartı, yönetici silme).
class RoomEditScreen extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic> room;
  final List<Map<String, dynamic>> managers;
  final bool isOwner;
  const RoomEditScreen({super.key, required this.roomId, required this.room, required this.managers, required this.isOwner});
  @override
  State<RoomEditScreen> createState() => _RoomEditScreenState();
}

class _RoomEditScreenState extends State<RoomEditScreen> {
  late final TextEditingController _name = TextEditingController(text: (widget.room['name'] ?? '').toString());
  late final TextEditingController _ann = TextEditingController(text: (widget.room['announcement'] ?? '').toString());
  late final Set<String> _tags = {for (final t in (widget.room['tags'] as List?) ?? const []) t.toString()};
  late List<Map<String, dynamic>> _managers = [...widget.managers];
  String? _cover;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _cover = widget.room['coverUrl'] as String?;
  }

  @override
  void dispose() {
    _name.dispose();
    _ann.dispose();
    super.dispose();
  }

  String? _mime(List<int> b) {
    if (b.length > 12 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    return null;
  }

  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final mime = _mime(bytes);
    if (!mounted) return;
    if (mime == null) return toast(context, 'Yalnızca png, jpeg veya webp yüklenebilir.', error: true);
    if (bytes.length > 3 * 1024 * 1024) return toast(context, 'Görsel 3 MB’tan küçük olmalı.', error: true);
    setState(() => _busy = true);
    final r = await guard(context, () => Api.putBytes('/api/rooms/${widget.roomId}/cover', bytes, mime));
    if (mounted) setState(() { _busy = false; if (r != null) _cover = r['url'] as String?; });
  }

  Future<void> _removeManager(Map<String, dynamic> m) async {
    final u = mapOf(m['user']);
    if (!await confirm(context, '${u?['displayName'] ?? 'Kullanıcı'} yönetici listesinden çıkarılsın mı?', action: 'Sil')) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.delete('/api/rooms/${widget.roomId}/staff/${u?['id']}'));
    if (r != null && mounted) setState(() => _managers.removeWhere((x) => mapOf(x['user'])?['id'] == u?['id']));
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return toast(context, 'Oda başlığı en az 2 karakter olmalı.', error: true);
    setState(() => _busy = true);
    final r = await guard(context, () => Api.patch('/api/rooms/${widget.roomId}', {'name': _name.text.trim(), 'announcement': _ann.text.trim(), 'tags': _tags.take(3).toList()}));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) Navigator.pop(context, mapOf(r['room']));
  }

  @override
  Widget build(BuildContext context) {
    final cover = Api.absoluteUrl(_cover);
    final tagList = {...presetTags, ..._tags}.toList();
    final h = Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilgileri Düzenle'),
        actions: [TextButton(onPressed: _busy ? null : _save, child: const Text('Onayla', style: TextStyle(color: _yellow, fontWeight: FontWeight.w800, fontSize: 16)))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Yayın kapak resmini düzenle', style: h),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: _busy ? null : _pickCover,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 120,
                height: 130,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: _yellow, width: 3), color: Colors.white12),
                clipBehavior: Clip.antiAlias,
                child: cover == null ? const Icon(Icons.image, size: 40, color: Colors.white38) : Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image)),
              ),
              const Positioned(right: -10, bottom: -10, child: CircleAvatar(radius: 18, backgroundColor: _yellow, child: Icon(Icons.camera_alt, color: Colors.black, size: 20))),
            ]),
          ),
        ),
        const SizedBox(height: 22),
        Text('Oda başlığını düzenle', style: h),
        const SizedBox(height: 6),
        TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(border: OutlineInputBorder())),
        Text('Oda duyurusunu düzenle', style: h),
        const SizedBox(height: 6),
        TextField(controller: _ann, maxLength: 200, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Odadakilere duyuru yaz…')),
        const SizedBox(height: 8),
        Text('Oda isim kartını düzenle (en fazla 3)', style: h),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in tagList)
            tagChip(t, selected: _tags.contains(t), onTap: () => setState(() {
                  if (_tags.contains(t)) {
                    _tags.remove(t);
                  } else if (_tags.length < 3) {
                    _tags.add(t);
                  }
                })),
        ]),
        const SizedBox(height: 22),
        Text('Oda yöneticilerini düzenle', style: h),
        const SizedBox(height: 4),
        for (final m in _managers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: UserAvatar(user: mapOf(m['user']), radius: 22),
            title: UserName(user: mapOf(m['user'])),
            subtitle: Text(roleLabels['${m['role']}'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: (widget.isOwner && m['role'] != 'owner') ? IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _removeManager(m)) : null,
          ),
        if (_managers.length <= 1) const Text('Henüz yönetici yok. Odada bir kullanıcıya dokunup moderatör veya yardımcı sahip yapabilirsin.', style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}
