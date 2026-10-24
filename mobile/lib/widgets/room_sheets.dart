import 'package:flutter/material.dart';
import '../services/api.dart';
import 'app_theme.dart';
import 'common.dart';
import 'cosmetics.dart';
import 'fig.dart';
import 'image_pick.dart';
import 'level_badge.dart';
import 'room_categories.dart';

const _yellow = Color(0xFFFFE100);
const roleLabels = {'owner': 'Oda sahibi', 'cohost': 'Yardımcı sahip', 'moderator': 'Moderatör', 'user': 'Üye'};
final presetTags = [for (final c in kRoomCategories) c.label];

/// Sunucudaki etiket (küçük harf) → ekranda gösterilen ad ("eğlence" → "Eğlence").
String tagLabel(String t) => roomCategoryOf(t)?.label ?? t;

Widget tagChip(String t, {bool selected = true, VoidCallback? onTap}) {
  final c = roomCategoryOf(t)?.colors ?? const [Color(0xFF00B4FF), Color(0xFF0066FF)];
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
        Text(tagLabel(t), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
      ]),
    ),
  );
}

Widget _sheetShell(BuildContext c, String title, Widget child) {
  return SafeArea(
    child: Container(
      height: MediaQuery.sizeOf(c).height * 0.75,
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

/// Katkı listesi (Figma "Katkı listesi"): 24 Saat / Toplam (ömür boyu), taçlı çerçeveli ilk 3 kürsü ve sıralı liste.
void showContributions(BuildContext context, String roomId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) => SafeArea(
      child: Container(
        height: MediaQuery.sizeOf(c).height * (779 / 932),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1B1446), Color(0xFF0B0C24)]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
            child: Row(children: [
              const SizedBox(width: 40),
              const Expanded(child: Text('Katkı Listesi', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white))),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(c),
                child: const CircleAvatar(radius: 17, backgroundColor: Colors.white24, child: Icon(Icons.close, color: Colors.white, size: 20)),
              ),
            ]),
          ),
          Expanded(child: _Contributions(roomId: roomId)),
        ]),
      ),
    ),
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
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() { _rows = null; _error = null; });
    try {
      final r = await Api.get('/api/rooms/${widget.roomId}/contributions', query: {'range': _total ? 'total' : 'day'});
      if (mounted && seq == _seq) setState(() => _rows = padRanking(listOf(r['contributions'])));
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = errorText(e));
    }
  }

  void _set(bool total) {
    if (_total == total) return;
    _total = total;
    _load();
  }

  Widget _tabs(double k) => Container(
        height: 37 * k,
        margin: EdgeInsets.symmetric(horizontal: 10 * k),
        padding: EdgeInsets.all(2 * k),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(19 * k)),
        child: Row(children: [
          for (final (label, total) in const [('24 Saat', false), ('Toplam', true)])
            Expanded(
              child: GestureDetector(
                onTap: () => _set(total),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17 * k),
                    gradient: _total == total ? const LinearGradient(colors: kGoldDeep) : null,
                  ),
                  child: Text(label, style: TextStyle(color: _total == total ? Colors.white : Colors.white60, fontWeight: FontWeight.w800, fontSize: 14 * k)),
                ),
              ),
            ),
        ]),
      );

  /// Kürsü: taçlı çerçeve + avatar, altında bayrak (ad, seviyeler), en altta elmas ve tutar.
  Widget _podium(Map<String, dynamic>? row, int rank, double k) {
    final first = rank == 1;
    final w = (first ? 150 : 135) * k;
    final frameH = (first ? 152 : 136) * k;
    final avatar = (first ? 100 : 90) * k;
    final bannerW = (first ? 121 : 111) * k;
    final bannerH = (first ? 176 : 144) * k;
    final bannerTop = (first ? 94 : 88) * k;
    final scoreTop = (first ? 273 : 234) * k;
    final u = mapOf(row?['user']);
    return SizedBox(
      width: w,
      height: scoreTop + (first ? 33 : 26) * k,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Positioned(top: bannerTop, width: bannerW, height: bannerH, child: Fig(first ? 'kat_banner1' : 'kat_banner2', fit: BoxFit.fill)),
        Positioned(
          top: (first ? 23 : 25) * k,
          child: u == null
              ? CircleAvatar(radius: avatar / 2, backgroundColor: Colors.white10, child: Icon(Icons.person, color: Colors.white24, size: avatar * 0.5))
              : UserAvatar(user: u, radius: avatar / 2),
        ),
        Positioned(top: 0, width: w, height: frameH, child: IgnorePointer(child: Fig('kat_top$rank', fit: BoxFit.contain))),
        if (u != null)
          Positioned(
            top: (first ? 160 : 136) * k,
            width: bannerW - 8 * k,
            child: Column(children: [
              Text((u['displayName'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13 * k)),
              SizedBox(height: 4 * k),
              FittedBox(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  LevelPill(level: u['coinLevel'] ?? 1, send: true, height: 14 * k),
                  SizedBox(width: 3 * k),
                  LevelPill(level: u['giftLevel'] ?? 1, send: false, height: 14 * k),
                ]),
              ),
            ]),
          ),
        Positioned(
          top: scoreTop,
          child: Container(
            height: (first ? 33 : 26) * k,
            constraints: BoxConstraints(minWidth: 96 * k),
            padding: EdgeInsets.symmetric(horizontal: 10 * k),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(17 * k),
              border: Border.all(color: const Color(0x66FFD54F)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Fig('kat_crown_dia', width: 18 * k, height: 18 * k),
              SizedBox(width: 4 * k),
              Text(row == null ? '0' : fmtCompact(row['total']), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: (first ? 15 : 13) * k)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> r, int i, double k) {
    final u = mapOf(r['user']);
    return Container(
        height: 87 * k,
        padding: EdgeInsets.symmetric(horizontal: 21 * k),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white12))),
        child: Row(children: [
          SizedBox(width: 36 * k, child: Text('${i + 1}-', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14 * k))),
          UserAvatar(user: u, radius: 24 * k),
          SizedBox(width: 12 * k),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              u == null ? Text('—', style: TextStyle(color: Colors.white38, fontSize: 14 * k)) : UserName(user: u),
              if (u != null) SizedBox(height: 5 * k),
              if (u != null) Row(children: [
                LevelPill(level: u['coinLevel'] ?? 1, send: true, height: 14 * k),
                SizedBox(width: 4 * k),
                LevelPill(level: u['giftLevel'] ?? 1, send: false, height: 14 * k),
              ]),
            ]),
          ),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Fig('kat_dia', width: 25 * k, height: 23 * k),
            SizedBox(height: 2 * k),
            Text(fmtCompact(r['total']), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13 * k)),
          ]),
        ]),
      );
  }

  @override
  Widget build(BuildContext context) {
    final k = MediaQuery.sizeOf(context).width / 430;
    final rows = _rows;
    return Column(children: [
      SizedBox(height: 8 * k),
      _tabs(k),
      SizedBox(height: 14 * k),
      if (_error != null)
        Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
      else if (rows == null)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 3 * k),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _podium(rows.length > 1 ? rows[1] : null, 2, k),
                  _podium(rows[0], 1, k),
                  _podium(rows.length > 2 ? rows[2] : null, 3, k),
                ]),
              ),
              SizedBox(height: 16 * k),
              for (var i = 3; i < rows.length; i++) _row(rows[i], i, k),
            ]),
          ),
        ),
    ]);
  }
}

String fmtCompact(dynamic v) {
  final n = BigInt.tryParse(v.toString()) ?? BigInt.zero;
  // Türkçe ondalık ayırıcı virgül: 1,5K (1.5K okuyan 1500 sanır).
  if (n >= BigInt.from(1000000000)) return '${(n.toDouble() / 1000000000).toStringAsFixed(1).replaceAll('.', ',')}B';
  if (n >= BigInt.from(1000000)) return '${(n.toDouble() / 1000000).toStringAsFixed(1).replaceAll('.', ',')}M';
  if (n >= BigInt.from(1000)) return '${(n.toDouble() / 1000).toStringAsFixed(n >= BigInt.from(100000) ? 0 : 1).replaceAll('.', ',')}K';
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
        // Oda sahibinin takılı oda kartı (mağaza) varsa kartın arka planı olur.
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A3A3F), Color(0xFF111114)]),
          image: cardBackground(Api.absoluteUrl(owner?['roomCardUrl'] as String?)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(14), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 96,
              height: 104,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: _yellow, width: 3), color: Colors.white12),
              clipBehavior: Clip.antiAlias,
              child: cover == null ? const Icon(Icons.image, color: Colors.white38, size: 36) : NetImg(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white38)),
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
  late final Set<String> _tags = {for (final t in (widget.room['tags'] as List?) ?? const []) tagLabel(t.toString())};
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

  Future<void> _pickCover() async {
    final img = await pickImage(context, crop: CropSpec.roomCover);
    if (img == null || !mounted) return;
    setState(() => _busy = true);
    final r = await guard(context, () => Api.putBytes('/api/rooms/${widget.roomId}/cover', img.bytes, img.mime));
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
                child: cover == null ? const Icon(Icons.image, size: 40, color: Colors.white38) : NetImg(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image)),
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
