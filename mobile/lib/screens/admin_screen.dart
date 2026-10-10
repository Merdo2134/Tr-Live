import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/anim_asset.dart';
import '../widgets/common.dart';
import 'admin_content.dart';
import 'admin_dashboard.dart';
import 'admin_payouts.dart';
import 'support_screens.dart';

/// Telefondan dosya seçip sunucuya yükler. Sunucu türü dosyanın içinden anlar (svga, mp4, Lottie, webp, gif, png).
/// [alpha]: yan yana şeffaf mp4'te şeffaflık maskesinin yeri ('left' / 'right').
Future<Map<String, dynamic>?> pickAndUploadMedia(BuildContext context, {String alpha = 'left'}) async {
  final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
  if (r == null || r.files.isEmpty || !context.mounted) return null;
  final Uint8List? bytes = r.files.first.bytes;
  if (bytes == null || bytes.isEmpty) {
    toast(context, 'Dosya okunamadı.', error: true);
    return null;
  }
  if (bytes.length > 40 * 1024 * 1024) {
    toast(context, 'Dosya 40 MB sınırını aşıyor.', error: true);
    return null;
  }
  toast(context, 'Yükleniyor (${(bytes.length / 1048576).toStringAsFixed(1)} MB)…');
  return guard(context, () => Api.postBytes('/api/admin/media', bytes, 'application/octet-stream', query: {'alpha': alpha}));
}


/// Animasyonun ilk karesini (şeffaf PNG) alıp sunucuya yükler; hediye ikonu için. Başarısızsa null.
Future<String?> autoIconFromAnimation(BuildContext context, String animUrl) async {
  final abs = Api.absoluteUrl(animUrl);
  if (abs == null) return null;
  final key = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -2000,
      top: 0,
      width: 256,
      height: 256,
      child: IgnorePointer(child: RepaintBoundary(key: key, child: AnimAsset(url: abs, repeat: false, fit: BoxFit.contain))),
    ),
  );
  overlay.insert(entry);
  try {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    final obj = key.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return null;
    final img = await obj.toImage(pixelRatio: 1.5);
    final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    if (raw == null || png == null) return null;
    var visible = false;
    for (var i = 3; i < raw.lengthInBytes; i += 4 * 17) {
      if (raw.getUint8(i) > 8) {
        visible = true;
        break;
      }
    }
    if (!visible) return null;
    final r = await Api.postBytes('/api/admin/media', png.buffer.asUint8List(), 'application/octet-stream', query: {'alpha': 'left'});
    return r['url']?.toString();
  } catch (_) {
    return null;
  } finally {
    entry.remove();
  }
}

/// Yüklenen dosyanın canlı önizlemesi (hediye animasyonu veya çerçeve).
Widget mediaPreview(String? url, {bool frame = false, double size = 170}) {
  final u = Api.absoluteUrl(url != null && url.trim().isNotEmpty ? url.trim() : null);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B3C5D), Color(0xFF061A2B)]),
      borderRadius: BorderRadius.circular(12),
    ),
    child: u == null
        ? const Center(child: Text('Önizleme', style: TextStyle(color: Colors.white38)))
        : Stack(alignment: Alignment.center, children: [
            if (frame) Icon(Icons.person, size: size * 0.45, color: Colors.white24),
            Positioned.fill(child: AnimAsset(key: ValueKey(u), url: u, repeat: true, fit: BoxFit.contain, cache: !frame)),
          ]),
  );
}

/// Katalogdaki tüm hediye ve çerçeveleri önizlemeyle listeler; açıp kapatma ve "bana ver" burada.
class CatalogListPage extends StatefulWidget {
  const CatalogListPage({super.key});

  @override
  State<CatalogListPage> createState() => _CatalogListPageState();
}

class _CatalogListPageState extends State<CatalogListPage> {
  List<Map<String, dynamic>> _gifts = [];
  List<Map<String, dynamic>> _frames = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await guard(context, () => Api.get('/api/admin/catalog'));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r != null) {
        _gifts = [for (final g in (r['gifts'] as List? ?? [])) if (g is Map) Map<String, dynamic>.from(g)];
        _frames = [for (final f in (r['frames'] as List? ?? [])) if (f is Map) Map<String, dynamic>.from(f)];
      }
    });
  }

  Future<void> _toggle(String kind, Map<String, dynamic> it, bool v) async {
    final r = await guard(context, () => Api.post('/api/admin/catalog/$kind/${it['id']}/active', {'isActive': v}));
    if (r != null) setState(() => it['isActive'] = v);
  }

  Future<void> _delete(String kind, Map<String, dynamic> it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Silinsin mi?'),
        content: Text('"${it['name']}" kalıcı olarak silinecek. Geçmişte kullanıldıysa silinmez, gizlenir.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil'))],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.delete('/api/admin/$kind/${it['id']}'));
    if (r != null && mounted) {
      toast(context, r['hidden'] == true ? (r['note'] ?? 'Gizlendi.').toString() : 'Silindi.');
      _load();
    }
  }

  Future<void> _grantSelf(Map<String, dynamic> f) async {
    final r = await guard(context, () => Api.post('/api/admin/users/${Session.id}/inventory', {'itemType': 'frame', 'itemKey': f['id'], 'itemName': f['name']}));
    if (r != null && mounted) toast(context, '"${f['name']}" envanterine eklendi.');
  }

  Widget _card(String kind, Map<String, dynamic> it, {required bool frame}) {
    final active = it['isActive'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Expanded(child: LayoutBuilder(builder: (c, box) => Center(child: mediaPreview((frame ? it['imageUrl'] : it['animationUrl'] ?? it['iconUrl']) as String?, frame: frame, size: box.biggest.shortestSide)))),
          const SizedBox(height: 6),
          Text(it['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (!frame) Text('${fmtNumber(it['coinPrice'])} coin · ${it['category']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(active ? 'Açık' : 'Kapalı', style: TextStyle(color: active ? Colors.greenAccent : Colors.white38)),
            Switch(value: active, onChanged: (v) => _toggle(kind, it, v)),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (frame) TextButton(onPressed: () => _grantSelf(it), child: const Text('Bana ver')),
            TextButton(style: TextButton.styleFrom(foregroundColor: Colors.redAccent), onPressed: () => _delete(frame ? 'frames' : 'gifts', it), child: const Text('Sil')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Katalog önizleme')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                Text('Hediyeler (${_gifts.length})', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 0.72,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: [for (final g in _gifts) _card('gifts', g, frame: false)],
                ),
                const SizedBox(height: 16),
                Text('Çerçeveler (${_frames.length})', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 0.72,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: [for (final f in _frames) _card('frames', f, frame: true)],
                ),
              ]),
            ),
    );
  }
}

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Yönetici: tüm paneller. Yardımcı admin: yalnızca kullanıcı (nick, fotoğraf, ban).
    final admin = Session.isAdmin;
    final tabs = <Tab>[
      if (admin) const Tab(text: 'Panel'),
      const Tab(text: 'Kullanıcı'),
      const Tab(text: 'Destek'),
      if (admin) const Tab(text: 'Yetkililer'),
      if (admin) const Tab(text: 'Ajans/Yayıncı'),
      if (admin) const Tab(text: 'Maaş/Dönem'),
      if (admin) const Tab(text: 'Şikâyetler'),
      if (admin) const Tab(text: 'Güvenlik'),
      if (admin) const Tab(text: 'Bayi'),
      if (admin) const Tab(text: 'Katalog'),
      if (admin) const Tab(text: 'Banner/Duyuru'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(admin ? 'Yönetim paneli' : 'Yardımcı admin paneli'),
          bottom: TabBar(isScrollable: true, tabs: tabs),
        ),
        body: TabBarView(children: [
          if (admin) const DashboardTab(),
          const _UsersTab(),
          const SupportAdminTab(),
          if (admin) const _StaffTab(),
          if (admin) const _AgenciesTab(),
          if (admin) const PayoutsTab(),
          if (admin) const _ReportsTab(),
          if (admin) const _SecurityTab(),
          if (admin) const _DealersTab(),
          if (admin) const _CatalogTab(),
          if (admin) const ContentTab(),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Yetkililer (yalnızca yönetici)
class _StaffTab extends StatefulWidget {
  const _StaffTab();

  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  List<Map<String, dynamic>> _staff = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await guard(context, () => Api.get('/api/admin/staff'));
    if (!mounted) return;
    setState(() {
      _staff = listOf(r?['staff']);
      _loading = false;
    });
  }

  Future<void> _set(String userId, String role, String done) async {
    final r = await guard(context, () => Api.post('/api/admin/users/$userId/staff-role', {'role': role}));
    if (r == null || !mounted) return;
    toast(context, done);
    await _load();
  }

  Future<void> _add() async {
    final u = await pickUser(context, admin: true);
    if (u == null || !mounted) return;
    if (u['systemRole'] == 'admin') return toast(context, 'Bu kişi zaten yönetici.', error: true);
    await _set(u['id'].toString(), 'support', 'Yardımcı admin yetkisi verildi.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
        'Yardımcı admin yalnızca: kullanıcının adını ve profil fotoğrafını değiştirebilir, süreli veya süresiz ban atabilir. '
        'Para, WIP, ajans, maaş, katalog ve güvenlik ayarlarına erişemez.',
      ),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _add, icon: const Icon(Icons.person_add), label: const Text('Yardımcı admin ekle')),
      const SizedBox(height: 8),
      for (final u in _staff)
        Card(
          child: ListTile(
            leading: Icon(u['systemRole'] == 'admin' ? Icons.shield : Icons.support_agent),
            title: Text((u['displayName'] ?? '').toString()),
            subtitle: Text('@${u['username']} · ${u['systemRole'] == 'admin' ? 'Yönetici' : 'Yardımcı admin'}'),
            trailing: u['systemRole'] == 'support'
                ? TextButton(onPressed: () async {
                    if (await confirm(context, '@${u['username']} yetkisi alınsın mı?', action: 'Yetkiyi al') && mounted) {
                      await _set(u['id'].toString(), 'user', 'Yetki alındı.');
                    }
                  }, child: const Text('Yetkiyi al'))
                : null,
          ),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ Kullanıcı
class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  Map<String, dynamic>? _user;

  Future<void> _pick() async {
    final u = await pickUser(context, admin: true);
    if (u != null && mounted) setState(() => _user = u);
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action, String done) async {
    final r = await guard(context, action);
    if (r == null || !mounted) return;
    toast(context, done);
    await _refreshUser();
  }

  Future<void> _refreshUser() async {
    final id = _user?['id'];
    if (id == null) return;
    try {
      final r = await Api.get('/api/admin/users', query: {'q': id.toString()});
      final list = listOf(r['users']);
      if (list.isNotEmpty && mounted) setState(() => _user = list.first);
    } catch (_) {/* eski bilgi kalsın */}
  }

  Future<void> _coins() async {
    final f = await formDialog(context, 'Coin düzenle', ['Miktar (çıkarmak için - ile)', 'Neden']);
    if (f == null || !mounted) return;
    final amount = int.tryParse(f['Miktar (çıkarmak için - ile)'] ?? '');
    if (amount == null || amount == 0) return toast(context, 'Geçerli bir miktar girin.', error: true);
    await _run(() => Api.postOnce('/api/admin/users/${_user!['id']}/coins', {'amount': amount, 'reason': f['Neden']}), 'Coin güncellendi.');
  }

  Future<void> _wip() async {
    const lvlLabel = 'Seviye (1-10, SWIP = 11)';
    final f = await formDialog(context, 'WIP ver', [lvlLabel, 'Gün'], initial: {lvlLabel: '1', 'Gün': '30'});
    if (f == null || !mounted) return;
    final level = int.tryParse(f[lvlLabel] ?? '');
    final days = int.tryParse(f['Gün'] ?? '');
    if (level == null || days == null) return toast(context, 'Seviye ve gün sayı olmalı.', error: true);
    await _run(() => Api.post('/api/admin/users/${_user!['id']}/wip', {'level': level, 'days': days}), 'WIP verildi.');
  }

  Future<void> _inventory() async {
    final u = _user;
    if (u == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => GrantItemPage(user: u)));
  }

  Future<void> _ban() async {
    final f = await formDialog(context, 'Ban', ['Süre (saat; boş bırakırsanız süresiz)', 'Neden'], initial: {'Süre (saat; boş bırakırsanız süresiz)': ''});
    if (f == null || !mounted) return;
    final raw = f['Süre (saat; boş bırakırsanız süresiz)'] ?? '';
    final hours = raw.isEmpty ? null : num.tryParse(raw.replaceAll(',', '.'));
    if (raw.isNotEmpty && (hours == null || hours <= 0)) return toast(context, 'Süre geçerli bir sayı olmalı.', error: true);
    await _run(() => Api.post('/api/admin/users/${_user!['id']}/ban', {if (hours != null) 'hours': hours, 'reason': f['Neden']}),
        hours == null ? 'Süresiz banlandı.' : 'Banlandı.');
  }

  Future<void> _rename() async {
    final f = await formDialog(context, 'Görünen adı değiştir', ['Yeni ad'], initial: {'Yeni ad': (_user?['displayName'] ?? '').toString()});
    if (f == null || !mounted) return;
    await _run(() => Api.post('/api/admin/users/${_user!['id']}/display-name', {'displayName': f['Yeni ad']}), 'Ad değiştirildi.');
  }

  Future<void> _restrict() async {
    final f = await formDialog(context, 'Sohbet kısıtı', ['Süre (dakika; 0 = kısıtı kaldır)'], initial: {'Süre (dakika; 0 = kısıtı kaldır)': '60'});
    if (f == null || !mounted) return;
    final minutes = int.tryParse(f['Süre (dakika; 0 = kısıtı kaldır)'] ?? '');
    if (minutes == null || minutes < 0 || minutes > 10080) return toast(context, 'Süre 0-10080 dakika olmalı.', error: true);
    await _run(() => Api.post('/api/admin/users/${_user!['id']}/chat-restriction', {'minutes': minutes}), minutes == 0 ? 'Sohbet kısıtı kaldırıldı.' : 'Sohbet kısıtlandı.');
  }

  Future<void> _revokeSessions() async {
    if (!await confirm(context, 'Bu kullanıcının tüm cihazlardaki oturumları kapatılsın mı? Yeniden giriş yapması gerekir.', action: 'Oturumları kapat', destructive: true)) return;
    if (!mounted) return;
    await _run(() => Api.post('/api/admin/users/${_user!['id']}/sessions/revoke-all'), 'Tüm oturumlar kapatıldı.');
  }

  String _restrictLine(Map<String, dynamic> u) {
    final until = DateTime.tryParse((u['chatRestrictedUntil'] ?? '').toString())?.toLocal();
    if (until == null) return '';
    return '\nSohbet kısıtı: ${until.toString().substring(0, 16)} kadar';
  }

  String _banLine(Map<String, dynamic> u) {
    if (u['accountStatus'] != 'banned') return '';
    final until = u['bannedUntil'];
    final when = until == null ? 'süresiz' : 'bitiş: ${DateTime.parse(until.toString()).toLocal().toString().substring(0, 16)}';
    final why = (u['banReason'] ?? '').toString();
    return '\nBan ($when)${why.isEmpty ? '' : ' · $why'}';
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final admin = Session.isAdmin;
    return ListView(padding: const EdgeInsets.all(16), children: [
      FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.search), label: const Text('Kullanıcı bul (ID, ad)')),
      if (u != null) ...[
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: UserAvatar(user: u),
            title: Text((u['displayName'] ?? '').toString()),
            subtitle: Text('ID: ${u['publicId'] ?? '-'} · @${u['username']} · ${u['systemRole']} · ${u['accountStatus']}'
                '${admin ? '\nCoin: ${fmtNumber(u['coins'])} · Diamond: ${fmtNumber(u['diamonds'])}' : ''}${_banLine(u)}${_restrictLine(u)}'),
            isThreeLine: true,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          // Yardımcı admin + yönetici
          OutlinedButton.icon(onPressed: _rename, icon: const Icon(Icons.edit), label: const Text('Nick değiştir')),
          OutlinedButton.icon(
            onPressed: () async {
              if (await confirm(context, 'Profil fotoğrafı kaldırılsın mı?', action: 'Kaldır') && mounted) {
                await _run(() => Api.post('/api/admin/users/${u['id']}/avatar', {'avatarUrl': null}), 'Fotoğraf kaldırıldı.');
              }
            },
            icon: const Icon(Icons.hide_image_outlined),
            label: const Text('Fotoğrafı kaldır'),
          ),
          if (u['accountStatus'] == 'active')
            OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent), onPressed: _ban, icon: const Icon(Icons.gavel), label: const Text('Banla'))
          else if (u['accountStatus'] == 'banned')
            OutlinedButton.icon(onPressed: () => _run(() => Api.post('/api/admin/users/${u['id']}/unban', {}), 'Ban kaldırıldı.'), icon: const Icon(Icons.lock_open), label: const Text('Banı kaldır')),
          OutlinedButton.icon(onPressed: _restrict, icon: const Icon(Icons.speaker_notes_off_outlined), label: Text(u['chatRestrictedUntil'] != null ? 'Sohbet kısıtını değiştir' : 'Sohbet kısıtı')),
          // Yalnızca yönetici
          if (admin) OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserDevicesScreen(user: u))), icon: const Icon(Icons.devices), label: const Text('Cihazlar')),
          if (admin) OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent), onPressed: _revokeSessions, icon: const Icon(Icons.logout), label: const Text('Oturumları kapat')),
          if (admin) OutlinedButton.icon(onPressed: _coins, icon: const Icon(Icons.monetization_on), label: const Text('Coin düzenle')),
          if (admin) OutlinedButton.icon(onPressed: _wip, icon: const Icon(Icons.workspace_premium), label: const Text('WIP ver')),
          if (admin) OutlinedButton.icon(onPressed: () => _run(() => Api.delete('/api/admin/users/${u['id']}/wip'), 'WIP kaldırıldı.'), icon: const Icon(Icons.remove_circle_outline), label: const Text('WIP al')),
          if (admin) OutlinedButton.icon(onPressed: _inventory, icon: const Icon(Icons.inventory_2), label: const Text('Öğe ver (çerçeve, rozet…)')),
        ]),
      ],
    ]);
  }
}

// ------------------------------------------------------------ Ajans / yayıncı
class _AgenciesTab extends StatefulWidget {
  const _AgenciesTab();

  @override
  State<_AgenciesTab> createState() => _AgenciesTabState();
}

class _AgenciesTabState extends State<_AgenciesTab> {
  int _v = 0;

  Future<Map<String, dynamic>> _load() async {
    final a = await Api.get('/api/admin/agencies');
    final b = await Api.get('/api/admin/broadcasters');
    return {'agencies': listOf(a['agencies']), 'broadcasters': listOf(b['broadcasters'])};
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action, {String? done}) async {
    final r = await guard(context, action);
    if (r == null || !mounted) return;
    if (done != null) toast(context, done);
    setState(() => _v++);
  }

  Future<void> _overrideCommission(Map<String, dynamic> a) async {
    final f = await formDialog(context, 'Ajansa özel komisyon', ['Komisyon % (boş = genel kademe tablosu)'],
        initial: {'Komisyon % (boş = genel kademe tablosu)': a['overrideBps'] == null ? '' : '${(a['overrideBps'] as num) / 100}'});
    if (f == null || !mounted) return;
    final raw = (f['Komisyon % (boş = genel kademe tablosu)'] ?? '').replaceAll(',', '.');
    int? bps;
    if (raw.isNotEmpty) {
      final pct = double.tryParse(raw);
      if (pct == null || pct < 0 || pct > 100) return toast(context, '0 ile 100 arasında bir oran girin.', error: true);
      bps = (pct * 100).round();
    }
    await _run(() => Api.post('/api/admin/agencies/${a['id']}/commission-override', {'bps': bps}), done: 'Güncellendi.');
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Map<String, dynamic>>(
      key: ValueKey(_v),
      load: _load,
      builder: (context, data, reload) {
        final agencies = listOf(data['agencies']);
        final broadcasters = listOf(data['broadcasters']);
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Text('Ajanslar (${agencies.length})', style: Theme.of(context).textTheme.titleMedium),
            for (final a in agencies)
              Card(
                child: ListTile(
                  title: Text(a['name'].toString()),
                  subtitle: Text('Sahip: @${a['ownerUsername']} · ${a['status']} · kod: ${a['agencyCode'] ?? '-'} · ${a['overrideBps'] == null ? 'kademeli komisyon' : '%${((a['overrideBps'] as num) / 100).toStringAsFixed(1)} özel'} · ${a['broadcasterCount']} yayıncı'),
                  trailing: !Session.isAdmin
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (s) {
                            if (s == 'override') _overrideCommission(a);
                            if (s == 'active' || s == 'suspended' || s == 'rejected') _run(() => Api.post('/api/admin/agencies/${a['id']}/status', {'status': s}), done: 'Güncellendi.');
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'active', child: Text('Onayla / aktif et')),
                            PopupMenuItem(value: 'suspended', child: Text('Askıya al')),
                            PopupMenuItem(value: 'rejected', child: Text('Reddet')),
                            PopupMenuItem(value: 'override', child: Text('Ajansa özel komisyon')),
                          ],
                        ),
                ),
              ),
            const SizedBox(height: 16),
            Text('Yayıncılar (${broadcasters.length})', style: Theme.of(context).textTheme.titleMedium),
            for (final b in broadcasters)
              Card(
                child: ListTile(
                  title: Text('${b['displayName']} (@${b['username']})'),
                  subtitle: Text('${b['status']}${b['agencyName'] != null ? ' · ${b['agencyName']}' : ''}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (s) => _run(() => Api.post('/api/admin/broadcasters/${b['userId']}/status', {'status': s}), done: 'Güncellendi.'),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'approved', child: Text('Onayla')),
                      PopupMenuItem(value: 'rejected', child: Text('Reddet')),
                      PopupMenuItem(value: 'suspended', child: Text('Askıya al')),
                    ],
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }
}

// ------------------------------------------------------------------------ Bayi
class _DealersTab extends StatefulWidget {
  const _DealersTab();

  @override
  State<_DealersTab> createState() => _DealersTabState();
}

class _DealersTabState extends State<_DealersTab> {
  int _v = 0;

  Future<void> _run(Future<Map<String, dynamic>> Function() action, {String? done}) async {
    final r = await guard(context, action);
    if (r == null || !mounted) return;
    if (done != null) toast(context, done);
    setState(() => _v++);
  }

  Future<void> _create() async {
    final f = await formDialog(context, 'Bayi oluştur', ['Bayi adı']);
    if (f == null || !mounted) return;
    final owner = await pickUser(context, admin: true);
    if (!mounted) return;
    await _run(() => Api.post('/api/admin/dealers', {'name': f['Bayi adı'], if (owner != null) 'ownerUserId': owner['id']}), done: 'Bayi oluşturuldu.');
  }

  Future<void> _credit(Map<String, dynamic> d) async {
    final f = await formDialog(context, 'Bayiye Coin yükle', ['Miktar']);
    final amount = int.tryParse(f?['Miktar'] ?? '');
    if (amount == null || !mounted) return;
    await _run(() => Api.post('/api/admin/dealers/${d['id']}/coins', {'amount': amount}), done: 'Bayi bakiyesi güncellendi.');
  }

  Future<void> _sell(Map<String, dynamic> d) async {
    final u = await pickUser(context, admin: true);
    if (u == null || !mounted) return;
    final f = await formDialog(context, '${u['displayName']} için Coin sat', ['Miktar']);
    final amount = int.tryParse(f?['Miktar'] ?? '');
    if (amount == null || !mounted) return;
    await _run(() => Api.post('/api/admin/dealers/${d['id']}/sell', {'userId': u['id'], 'amount': amount}), done: 'Satış tamamlandı.');
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<Map<String, dynamic>>>(
      key: ValueKey(_v),
      load: () async => listOf((await Api.get('/api/admin/dealers'))['dealers']),
      builder: (context, dealers, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_business), label: const Text('Bayi oluştur')),
          for (final d in dealers)
            Card(
              child: ListTile(
                title: Text(d['name'].toString()),
                subtitle: Text('Sahip: ${d['ownerUsername'] != null ? '@${d['ownerUsername']}' : '-'} · Bakiye: ${fmtNumber(d['coinBalance'])}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (a) => a == 'credit' ? _credit(d) : _sell(d),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'credit', child: Text('Bayiye Coin yükle')),
                    PopupMenuItem(value: 'sell', child: Text('Kullanıcıya Coin sat')),
                  ],
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// --------------------------------------------------------------------- Katalog
class _CatalogTab extends StatelessWidget {
  const _CatalogTab();

  Future<void> _giftForm(BuildContext context) async {
    final name = TextEditingController();
    final price = TextEditingController();
    final icon = TextEditingController();
    final anim = TextEditingController();
    var format = 'auto';
    var alphaSide = 'left';
    var category = 'popular';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('Hediye ekle'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad')),
              TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Coin fiyatı')),
              TextField(controller: icon, decoration: const InputDecoration(labelText: 'İkon adresi (https veya yüklenen dosya)')),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('İkonu telefondan yükle'),
                  onPressed: () async {
                    final m = await pickAndUploadMedia(c);
                    if (m != null) setS(() => icon.text = m['url'].toString());
                  },
                ),
              ),
              if (icon.text.trim().isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Container(width: 72, height: 72, decoration: BoxDecoration(color: const Color(0xFF0B3C5D), borderRadius: BorderRadius.circular(10)), child: Image.network(Api.absoluteUrl(icon.text.trim()) ?? '', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38)))),
              if (anim.text.trim().isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('İkonu animasyonun ilk karesinden yap'),
                    onPressed: () async {
                      final u = await autoIconFromAnimation(c, anim.text);
                      if (u != null) {
                        setS(() => icon.text = u);
                      } else if (c.mounted) {
                        toast(c, 'İlk kare alınamadı.', error: true);
                      }
                    },
                  ),
                ),
              TextField(controller: anim, decoration: const InputDecoration(labelText: 'Animasyon adresi (https veya yüklenen dosya)')),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: mediaPreview(anim.text)),
              Row(children: [
                const Text('Şeffaflık:  ', style: TextStyle(color: Colors.white70)),
                DropdownButton<String>(
                  value: alphaSide,
                  items: const [
                    DropdownMenuItem(value: 'left', child: Text('Sol yarıda (siyah-beyaz)')),
                    DropdownMenuItem(value: 'right', child: Text('Sağ yarıda (siyah-beyaz)')),
                  ],
                  onChanged: (v) => setS(() => alphaSide = v ?? 'left'),
                ),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Animasyonu telefondan yükle'),
                  onPressed: () async {
                    final m = await pickAndUploadMedia(c, alpha: alphaSide);
                    if (m == null) return;
                    setS(() {
                      anim.text = m['url'].toString();
                      format = 'auto';
                    });
                    if (c.mounted) toast(c, 'Yüklendi: ${m['kind']} (${(((m['size'] as num?) ?? 0) / 1048576).toStringAsFixed(1)} MB). ${m['note'] ?? ''}');
                    if (icon.text.trim().isEmpty && c.mounted) {
                      final u = await autoIconFromAnimation(c, anim.text);
                      if (u != null) {
                        setS(() => icon.text = u);
                        if (c.mounted) toast(c, 'İkon animasyonun ilk karesinden otomatik oluşturuldu.');
                      } else if (c.mounted) {
                        toast(c, 'İlk kare otomatik alınamadı; ikonu elle yükleyebilirsin.', error: true);
                      }
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: format,
                decoration: const InputDecoration(labelText: 'Animasyon biçimi'),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('Otomatik (uzantıdan)')),
                  DropdownMenuItem(value: 'mp4', child: Text('Şeffaf MP4 (VAP)')),
                  DropdownMenuItem(value: 'lottie', child: Text('Lottie (.json)')),
                  DropdownMenuItem(value: 'svga', child: Text('SVGA')),
                  DropdownMenuItem(value: 'webp', child: Text('WebP')),
                  DropdownMenuItem(value: 'gif', child: Text('GIF')),
                  DropdownMenuItem(value: 'png', child: Text('PNG')),
                ],
                onChanged: (v) => setS(() => format = v ?? 'auto'),
              ),
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'Hediye sekmesi'),
                items: const [
                  DropdownMenuItem(value: 'popular', child: Text('Popüler')),
                  DropdownMenuItem(value: 'event', child: Text('Etkinlik')),
                  DropdownMenuItem(value: 'private', child: Text('Kişiye Özel')),
                  DropdownMenuItem(value: 'vip', child: Text('Vip (WIP 3+)')),
                  DropdownMenuItem(value: 'lucky', child: Text('Şanslı')),
                ],
                onChanged: (v) => setS(() => category = v ?? 'popular'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ekle')),
          ],
        ),
      ),
    );
    final body = {
      'name': name.text.trim(),
      'coinPrice': price.text.trim(),
      'iconUrl': icon.text.trim().isEmpty ? null : icon.text.trim(),
      'animationUrl': anim.text.trim().isEmpty ? null : anim.text.trim(),
      if (format != 'auto') 'animationFormat': format,
      'category': category,
    };
    name.dispose();
    price.dispose();
    icon.dispose();
    anim.dispose();
    if (ok != true || !context.mounted) return;
    final r = await guard(context, () => Api.post('/api/admin/gifts', body));
    if (r != null && context.mounted) toast(context, 'Hediye eklendi. Kimlik: ${r['id']}');
  }

  Future<void> _storeForm(BuildContext context) async {
    final name = TextEditingController();
    final url = TextEditingController();
    final price = TextEditingController(text: '500000');
    final days = TextEditingController(text: '14');
    var category = 'frame';
    var forSale = true;
    var alphaSide = 'left';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('Mağaza ürünü ekle'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<String>(
                isExpanded: true,
                value: category,
                items: const [
                  DropdownMenuItem(value: 'frame', child: Text('Çerçeve')),
                  DropdownMenuItem(value: 'chat_bubble', child: Text('Sohbet Balonu')),
                  DropdownMenuItem(value: 'entrance_effect', child: Text('Özel Giriş')),
                  DropdownMenuItem(value: 'mini_card', child: Text('Mini Kart')),
                  DropdownMenuItem(value: 'mic_wave', child: Text('Mikrofon Dalgası')),
                  DropdownMenuItem(value: 'vehicle', child: Text('Araç')),
                  DropdownMenuItem(value: 'badge', child: Text('Rozet (yalnızca yönetici verir)')),
                ],
                onChanged: (v) => setS(() => category = v ?? 'frame'),
              ),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Mağazada satılsın'), subtitle: const Text('Kapalıysa yalnızca sen kullanıcıya verirsin'), value: forSale && category != 'badge', onChanged: category == 'badge' ? null : (v) => setS(() => forSale = v)),
              TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fiyat (coin)')),
              TextField(controller: days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Süre (gün)')),
              TextField(controller: url, decoration: const InputDecoration(labelText: 'Görsel/animasyon adresi')),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: mediaPreview(url.text, frame: category == 'frame')),
              Row(children: [
                const Text('MP4 şeffaflık:  ', style: TextStyle(color: Colors.white70)),
                DropdownButton<String>(
                  value: alphaSide,
                  items: const [DropdownMenuItem(value: 'left', child: Text('Sol yarıda')), DropdownMenuItem(value: 'right', child: Text('Sağ yarıda'))],
                  onChanged: (v) => setS(() => alphaSide = v ?? 'left'),
                ),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Telefondan yükle'),
                  onPressed: () async {
                    final m = await pickAndUploadMedia(c, alpha: alphaSide);
                    if (m == null) return;
                    setS(() => url.text = m['url'].toString());
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ekle')),
          ],
        ),
      ),
    );
    final body = {
      'category': category,
      'name': name.text.trim(),
      'imageUrl': url.text.trim(),
      'priceCoins': price.text.trim(),
      'durationDays': int.tryParse(days.text.trim()) ?? 14,
      'forSale': forSale,
    };
    name.dispose();
    url.dispose();
    price.dispose();
    days.dispose();
    if (ok != true || !context.mounted) return;
    final r = await guard(context, () => Api.post('/api/admin/store/items', body));
    if (r != null && context.mounted) toast(context, 'Mağazaya eklendi.');
  }

  Future<void> _frameForm(BuildContext context) async {
    final name = TextEditingController();
    final url = TextEditingController();
    var alphaSide = 'left';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('Çerçeve ekle'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad')),
              TextField(controller: url, decoration: const InputDecoration(labelText: 'Görsel adresi (https veya yüklenen dosya)')),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: mediaPreview(url.text, frame: true)),
              Row(children: [
                const Text('MP4 şeffaflık:  ', style: TextStyle(color: Colors.white70)),
                DropdownButton<String>(
                  value: alphaSide,
                  items: const [
                    DropdownMenuItem(value: 'left', child: Text('Sol yarıda')),
                    DropdownMenuItem(value: 'right', child: Text('Sağ yarıda')),
                  ],
                  onChanged: (v) => setS(() => alphaSide = v ?? 'left'),
                ),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Telefondan yükle (svga, mp4, webp, gif, json)'),
                  onPressed: () async {
                    final m = await pickAndUploadMedia(c, alpha: alphaSide);
                    if (m == null) return;
                    setS(() => url.text = m['url'].toString());
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ekle')),
          ],
        ),
      ),
    );
    final body = {'name': name.text.trim(), 'imageUrl': url.text.trim()};
    name.dispose();
    url.dispose();
    if (ok != true || !context.mounted) return;
    final r = await guard(context, () => Api.post('/api/admin/frames', body));
    if (r != null && context.mounted) toast(context, 'Çerçeve eklendi. Kimlik: ${r['id']}');
  }

  /// Birçok dosyayı bir seferde yükler; her dosya için ad (dosya adından), fiyat ve sekme aynı olur.
  Future<void> _bulk(BuildContext context, {required bool frames}) async {
    final price = TextEditingController(text: '100');
    var category = 'popular';
    var alpha = 'left';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(frames ? 'Toplu çerçeve yükle' : 'Toplu hediye yükle'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Sonraki ekranda birden fazla dosya seçersin. Ad dosya adından alınır.', style: TextStyle(color: Colors.white70)),
              if (!frames) TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Hepsi için coin fiyatı')),
              if (!frames)
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Hediye sekmesi'),
                  items: const [
                    DropdownMenuItem(value: 'popular', child: Text('Popüler')),
                    DropdownMenuItem(value: 'event', child: Text('Etkinlik')),
                    DropdownMenuItem(value: 'private', child: Text('Kişiye Özel')),
                    DropdownMenuItem(value: 'vip', child: Text('Vip (WIP 3+)')),
                    DropdownMenuItem(value: 'lucky', child: Text('Şanslı')),
                  ],
                  onChanged: (v) => setS(() => category = v ?? 'popular'),
                ),
              DropdownButtonFormField<String>(
                value: alpha,
                decoration: const InputDecoration(labelText: 'MP4 şeffaflık maskesi'),
                items: const [
                  DropdownMenuItem(value: 'left', child: Text('Sol yarıda')),
                  DropdownMenuItem(value: 'right', child: Text('Sağ yarıda')),
                ],
                onChanged: (v) => setS(() => alpha = v ?? 'left'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Dosyaları seç')),
          ],
        ),
      ),
    );
    final priceText = price.text.trim();
    price.dispose();
    if (ok != true || !context.mounted) return;
    final r = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
    if (r == null || r.files.isEmpty || !context.mounted) return;
    final log = <String>[];
    var done = 0;
    for (final f in r.files) {
      final path = f.path;
      final base = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
      final name = base.length < 2 ? '$base ' : (base.length > 80 ? base.substring(0, 80) : base);
      if (path == null) {
        log.add('✗ ${f.name}: dosya okunamadı');
        continue;
      }
      if (context.mounted) toast(context, 'Yükleniyor ${done + log.length + 1}/${r.files.length}: ${f.name}');
      try {
        final bytes = await File(path).readAsBytes();
        final m = await Api.postBytes('/api/admin/media', bytes, 'application/octet-stream', query: {'alpha': alpha});
        if (frames) {
          await Api.post('/api/admin/frames', {'name': name, 'imageUrl': m['url']});
        } else {
          await Api.post('/api/admin/gifts', {
            'name': name,
            'coinPrice': priceText,
            'animationUrl': m['url'],
            'animationFormat': m['format'],
            'category': category,
          });
        }
        done++;
      } catch (e) {
        log.add('✗ ${f.name}: ${errorText(e)}');
      }
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$done / ${r.files.length} eklendi'),
        content: SingleChildScrollView(child: Text(log.isEmpty ? 'Hepsi eklendi.' : log.join('\n'))),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
      ),
    );
  }

  Future<void> _create(BuildContext context, String title, List<String> labels, String path, Map<String, dynamic> Function(Map<String, String>) body) async {
    final f = await formDialog(context, title, labels);
    if (f == null || !context.mounted) return;
    final r = await guard(context, () => Api.post(path, body(f)));
    if (r != null && context.mounted) toast(context, 'Oluşturuldu. Kimlik: ${r['id']}');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Adresler https:// ile başlamalıdır. Oluşan kimlik, envanterde "Anahtar" olarak kullanılır.', style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.grid_view),
        label: const Text('Katalog listesi (önizleme)'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CatalogListPage())),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        icon: const Icon(Icons.card_giftcard),
        label: const Text('Hediye ekle'),
        onPressed: () => _giftForm(context),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        icon: const Icon(Icons.library_add),
        label: const Text('Toplu hediye yükle (çok dosya)'),
        onPressed: () => _bulk(context, frames: false),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        icon: const Icon(Icons.library_add),
        label: const Text('Toplu çerçeve yükle (çok dosya)'),
        onPressed: () => _bulk(context, frames: true),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.monetization_on),
        label: const Text('Coin paketleri (Yükleme Merkezi)'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoinPackagesPage())),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.list_alt),
        label: const Text('Mağaza ürünleri (aç/kapat/sil)'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreItemsPage())),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        icon: const Icon(Icons.storefront),
        label: const Text('Mağaza ürünü ekle'),
        onPressed: () => _storeForm(context),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        icon: const Icon(Icons.filter_frames),
        label: const Text('Avatar çerçevesi ekle'),
        onPressed: () => _frameForm(context),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Giriş efekti ekle'),
        onPressed: () => _create(context, 'Giriş efekti ekle', ['Ad', 'Animasyon adresi (Lottie json)'], '/api/admin/entrance-effects',
            (f) => {'name': f['Ad'], 'animationUrl': f['Animasyon adresi (Lottie json)']}),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ Şikâyetler
class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  int _v = 0;

  Future<void> _resolve(Map<String, dynamic> r, String status) async {
    final note = await askText(context, status == 'resolved' ? 'Çözüm notu (isteğe bağlı)' : 'Reddetme notu (isteğe bağlı)');
    if (!mounted) return;
    final res = await guard(context, () => Api.post('/api/admin/reports/${r['id']}/resolve', {'status': status, if (note != null) 'note': note}));
    if (res != null && mounted) setState(() => _v++);
  }

  Future<void> _ban(Map<String, dynamic> r) async {
    final id = r['targetUserId'];
    if (id == null || !await confirm(context, '@${r['target']} hesabı yasaklansın mı?', action: 'Yasakla')) return;
    if (!mounted) return;
    final res = await guard(context, () => Api.post('/api/admin/users/$id/ban', {'reason': 'Şikâyet: ${r['reason']}'}));
    if (res != null && mounted) toast(context, 'Hesap yasaklandı.');
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<Map<String, dynamic>>>(
      key: ValueKey(_v),
      load: () async => listOf((await Api.get('/api/admin/reports'))['reports']),
      builder: (context, reports, reload) => reports.isEmpty
          ? const Center(child: Text('Açık şikâyet yok.'))
          : RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                for (final r in reports)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['kind']} · ${r['reason']}', style: Theme.of(context).textTheme.titleSmall),
                        Text('Şikâyet eden: @${r['reporter']}${r['target'] != null ? '  →  @${r['target']}' : ''}'),
                        if ((r['details'] ?? '').toString().isNotEmpty) Text(r['details'].toString(), style: const TextStyle(color: Colors.white70)),
                        if (r['roomId'] != null) Text('Oda: ${r['roomId']}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          FilledButton.tonal(onPressed: () => _resolve(r, 'resolved'), child: const Text('Çözüldü')),
                          OutlinedButton(onPressed: () => _resolve(r, 'dismissed'), child: const Text('Reddet')),
                          if (Session.isStaff && r['targetUserId'] != null)
                            OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent), onPressed: () => _ban(r), child: const Text('Hesabı yasakla')),
                        ]),
                      ]),
                    ),
                  ),
              ]),
            ),
    );
  }
}

// ------------------------------------------------------------------- Güvenlik
class _SecurityTab extends StatefulWidget {
  const _SecurityTab();

  @override
  State<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<_SecurityTab> {
  int _v = 0;

  Future<Map<String, dynamic>> _load() async {
    final e = await Api.get('/api/admin/security/events', query: {'limit': '60'});
    final b = await Api.get('/api/admin/security/blocks');
    return {'events': listOf(e['events']), 'stats': mapOf(e['stats']), 'blocks': listOf(b['blocks'])};
  }

  Future<void> _addBlock() async {
    final f = await formDialog(context, 'IP engelle', ['IP adresi', 'Süre (dakika, boş = süresiz)', 'Neden']);
    if (f == null || !mounted) return;
    final minutes = int.tryParse(f['Süre (dakika, boş = süresiz)'] ?? '');
    final r = await guard(context, () => Api.post('/api/admin/security/blocks', {'ip': f['IP adresi'], if (minutes != null) 'minutes': minutes, 'reason': f['Neden']}));
    if (r != null && mounted) setState(() => _v++);
  }

  Future<void> _unblock(String ip) async {
    final r = await guard(context, () => Api.delete('/api/admin/security/blocks/${Uri.encodeComponent(ip)}'));
    if (r != null && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Map<String, dynamic>>(
      key: ValueKey(_v),
      load: _load,
      builder: (context, data, reload) {
        final events = listOf(data['events']);
        final blocks = listOf(data['blocks']);
        final stats = mapOf(data['stats']) ?? {};
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Card(child: ListTile(leading: const Icon(Icons.shield), title: const Text('Güvenlik duvarı'), subtitle: Text('Aktif yasak: ${stats['bans'] ?? 0} · Kaydedilen olay: ${stats['eventsLogged'] ?? 0}'))),
            Row(children: [
              Text('Engelli IP\'ler (${blocks.length})', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(onPressed: _addBlock, icon: const Icon(Icons.add), label: const Text('Ekle')),
            ]),
            for (final b in blocks)
              ListTile(
                dense: true,
                leading: const Icon(Icons.block, color: Colors.redAccent),
                title: Text(b['ip'].toString()),
                subtitle: Text('${b['reason'] ?? ''}${b['until'] != null ? '\nBitiş: ${b['until']}' : '\nSüresiz'}'),
                trailing: IconButton(icon: const Icon(Icons.lock_open), tooltip: 'Engeli kaldır', onPressed: () => _unblock(b['ip'].toString())),
              ),
            const Divider(),
            Text('Son güvenlik olayları', style: Theme.of(context).textTheme.titleMedium),
            for (final e in events)
              ListTile(
                dense: true,
                leading: Icon(e['event_type'].toString().startsWith('ip_') ? Icons.gavel : Icons.warning_amber, size: 20),
                title: Text(e['event_type'].toString()),
                subtitle: Text('${e['ip'] ?? '-'} · ${e['created_at']}'),
              ),
          ]),
        );
      },
    );
  }
}


/// Öğe ver: kategori seç, listeden öğeyi seç, gün yaz, gönder (WIP verme gibi tek ekranda).
class GrantItemPage extends StatefulWidget {
  final Map<String, dynamic> user;
  const GrantItemPage({super.key, required this.user});

  @override
  State<GrantItemPage> createState() => _GrantItemPageState();
}

class _GrantItemPageState extends State<GrantItemPage> {
  static const _cats = [
    ['frame', 'Çerçeve'],
    ['badge', 'Rozet'],
    ['chat_bubble', 'Sohbet Balonu'],
    ['entrance_effect', 'Giriş Efekti'],
    ['mini_card', 'Mini Kart'],
    ['mic_wave', 'Mikrofon Dalgası'],
    ['vehicle', 'Araç'],
  ];
  String _cat = 'frame';
  String? _selected;
  final _days = TextEditingController(text: '30');
  bool _sending = false;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _send(List<Map<String, dynamic>> items) async {
    final item = items.where((i) => i['key'] == _selected).firstOrNull;
    if (item == null) return toast(context, 'Önce bir öğe seç.', error: true);
    final d = _days.text.trim();
    final days = d.isEmpty || d == '0' ? null : int.tryParse(d);
    if (d.isNotEmpty && d != '0' && days == null) return toast(context, 'Gün sayı olmalı.', error: true);
    setState(() => _sending = true);
    final r = await guard(context, () => Api.post('/api/admin/users/${widget.user['id']}/grant', {'category': _cat, 'itemKey': item['key'], if (days != null) 'days': days}));
    if (!mounted) return;
    setState(() => _sending = false);
    if (r != null) toast(context, '"${item['name']}" ${widget.user['displayName']} kullanıcısına verildi.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Öğe ver · ${widget.user['displayName']}')),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), children: [
            for (final c in _cats)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(c[1]), selected: _cat == c[0], onSelected: (_) => setState(() {
                      _cat = c[0];
                      _selected = null;
                    })),
              ),
          ]),
        ),
        Expanded(
          child: AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey(_cat),
            load: () async => listOf((await Api.get('/api/admin/grantables', query: {'category': _cat}))['items']),
            builder: (context, items, reload) => Column(children: [
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('Bu kategoride öğe yok. Katalog sekmesinden ekle.'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(10),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.85),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final it = items[i];
                          final sel = it['key'] == _selected;
                          return InkWell(
                            onTap: () => setState(() => _selected = it['key'].toString()),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? Colors.greenAccent : Colors.white24, width: sel ? 2.5 : 1)),
                              child: Column(children: [
                                Expanded(child: LayoutBuilder(builder: (c, box) => Center(child: mediaPreview(it['imageUrl'] as String?, frame: _cat == 'frame', size: box.biggest.shortestSide)))),
                                Text(it['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: Row(children: [
                    SizedBox(width: 110, child: TextField(controller: _days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Gün (0 = süresiz)', isDense: true, border: OutlineInputBorder()))),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton.icon(onPressed: _sending || _selected == null ? null : () => _send(items), icon: const Icon(Icons.send), label: Text(_sending ? 'Gönderiliyor…' : 'Gönder'))),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Mağaza ürünlerini listele; aç/kapat (kapalı ürün mağazada ve "öğe ver" listesinde görünmez).
class StoreItemsPage extends StatefulWidget {
  const StoreItemsPage({super.key});

  @override
  State<StoreItemsPage> createState() => _StoreItemsPageState();
}

class _StoreItemsPageState extends State<StoreItemsPage> {
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mağaza ürünleri (silmek için sola kaydır)')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_v),
        load: () async => listOf((await Api.get('/api/admin/store/items'))['items']),
        builder: (context, items, reload) => items.isEmpty
            ? const Center(child: Text('Henüz ürün yok.'))
            : ListView(children: [
                for (final it in items)
                  Dismissible(
                    key: ValueKey(it['id']),
                    direction: DismissDirection.endToStart,
                    background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                    confirmDismiss: (_) async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Ürün silinsin mi?'),
                          content: Text('"${it['name']}" silinecek. Daha önce alındıysa silinmez, gizlenir.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil'))],
                        ),
                      );
                      if (ok != true || !context.mounted) return false;
                      final r = await guard(context, () => Api.delete('/api/admin/store/items/${it['id']}'));
                      if (r != null && context.mounted) {
                        toast(context, r['hidden'] == true ? (r['note'] ?? 'Gizlendi.').toString() : 'Silindi.');
                        setState(() => _v++);
                      }
                      return false;
                    },
                    child: SwitchListTile(
                    secondary: SizedBox(width: 48, height: 48, child: mediaPreview(it['imageUrl'] as String?, frame: it['category'] == 'frame', size: 48)),
                    title: Text(it['name'].toString()),
                    subtitle: Text('${it['category']} · ${fmtNumber(it['priceCoins'])} coin · ${it['durationDays']} gün${it['forSale'] == false ? ' · mağazada değil' : ''}'),
                    value: it['isActive'] == true,
                    onChanged: (v) async {
                      final r = await guard(context, () => Api.post('/api/admin/store/items/${it['id']}/active', {'isActive': v}));
                      if (r != null && mounted) setState(() => _v++);
                    },
                  ),
                  ),
              ]),
      ),
    );
  }
}
