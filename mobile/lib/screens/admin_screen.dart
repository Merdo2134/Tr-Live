import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import 'admin_payouts.dart';

/// Birden fazla alanlı basit form penceresi; {etiket: değer} döner.
Future<Map<String, String>?> formDialog(BuildContext context, String title, List<String> labels, {Map<String, String> initial = const {}}) async {
  final controllers = {for (final l in labels) l: TextEditingController(text: initial[l] ?? '')};
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final l in labels) TextField(controller: controllers[l], decoration: InputDecoration(labelText: l)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tamam')),
      ],
    ),
  );
  final values = {for (final l in labels) l: controllers[l]!.text.trim()};
  for (final c in controllers.values) {
    c.dispose();
  }
  return ok == true ? values : null;
}

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Yönetici: tüm paneller. Yardımcı admin: yalnızca kullanıcı (nick, fotoğraf, ban).
    final admin = Session.isAdmin;
    final tabs = <Tab>[
      const Tab(text: 'Kullanıcı'),
      if (admin) const Tab(text: 'Yetkililer'),
      if (admin) const Tab(text: 'Ajans/Yayıncı'),
      if (admin) const Tab(text: 'Maaş/Dönem'),
      if (admin) const Tab(text: 'Şikâyetler'),
      if (admin) const Tab(text: 'Güvenlik'),
      if (admin) const Tab(text: 'Bayi'),
      if (admin) const Tab(text: 'Katalog'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(admin ? 'Yönetim paneli' : 'Yardımcı admin paneli'),
          bottom: admin ? TabBar(isScrollable: true, tabs: tabs) : null,
        ),
        body: TabBarView(children: [
          const _UsersTab(),
          if (admin) const _StaffTab(),
          if (admin) const _AgenciesTab(),
          if (admin) const PayoutsTab(),
          if (admin) const _ReportsTab(),
          if (admin) const _SecurityTab(),
          if (admin) const _DealersTab(),
          if (admin) const _CatalogTab(),
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
    await _run(() => Api.post('/api/admin/users/${_user!['id']}/coins', {'amount': amount, 'reason': f['Neden']}), 'Coin güncellendi.');
  }

  Future<void> _wip() async {
    final f = await formDialog(context, 'WIP ver', ['Seviye (1-5)', 'Gün'], initial: {'Seviye (1-5)': '1', 'Gün': '30'});
    if (f == null || !mounted) return;
    final level = int.tryParse(f['Seviye (1-5)'] ?? '');
    final days = int.tryParse(f['Gün'] ?? '');
    if (level == null || days == null) return toast(context, 'Seviye ve gün sayı olmalı.', error: true);
    await _run(() => Api.post('/api/admin/users/${_user!['id']}/wip', {'level': level, 'days': days}), 'WIP verildi.');
  }

  Future<void> _inventory() async {
    final f = await formDialog(context, 'Envanter öğesi ver', ['Tip (frame/entrance_effect/badge/profile_effect)', 'Anahtar (katalog kimliği)', 'Ad']);
    if (f == null || !mounted) return;
    await _run(
      () => Api.post('/api/admin/users/${_user!['id']}/inventory', {
        'itemType': f['Tip (frame/entrance_effect/badge/profile_effect)'],
        'itemKey': f['Anahtar (katalog kimliği)'],
        'itemName': f['Ad'],
      }),
      'Öğe eklendi.',
    );
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
      FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.search), label: const Text('Kullanıcı bul')),
      if (u != null) ...[
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: UserAvatar(user: u),
            title: Text((u['displayName'] ?? '').toString()),
            subtitle: Text('@${u['username']} · ${u['systemRole']} · ${u['accountStatus']}'
                '${admin ? '\nCoin: ${fmtNumber(u['coins'])} · Diamond: ${fmtNumber(u['diamonds'])}' : ''}${_banLine(u)}'),
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
          // Yalnızca yönetici
          if (admin) OutlinedButton.icon(onPressed: _coins, icon: const Icon(Icons.monetization_on), label: const Text('Coin düzenle')),
          if (admin) OutlinedButton.icon(onPressed: _wip, icon: const Icon(Icons.workspace_premium), label: const Text('WIP ver')),
          if (admin) OutlinedButton.icon(onPressed: () => _run(() => Api.delete('/api/admin/users/${u['id']}/wip'), 'WIP kaldırıldı.'), icon: const Icon(Icons.remove_circle_outline), label: const Text('WIP al')),
          if (admin) OutlinedButton.icon(onPressed: _inventory, icon: const Icon(Icons.inventory_2), label: const Text('Envanter ver')),
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
      FilledButton.icon(
        icon: const Icon(Icons.card_giftcard),
        label: const Text('Hediye ekle'),
        onPressed: () => _create(context, 'Hediye ekle', ['Ad', 'Coin fiyatı', 'İkon adresi', 'Animasyon adresi'], '/api/admin/gifts',
            (f) => {'name': f['Ad'], 'coinPrice': f['Coin fiyatı'], 'iconUrl': f['İkon adresi'], 'animationUrl': f['Animasyon adresi']}),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        icon: const Icon(Icons.filter_frames),
        label: const Text('Avatar çerçevesi ekle'),
        onPressed: () => _create(context, 'Çerçeve ekle', ['Ad', 'Görsel adresi'], '/api/admin/frames', (f) => {'name': f['Ad'], 'imageUrl': f['Görsel adresi']}),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        icon: const Icon(Icons.library_music),
        label: const Text('Müzik ekle (lisanslı)'),
        onPressed: () async {
          final f = await formDialog(context, 'Müzik ekle', ['Başlık', 'Sanatçı', 'Şarkı adresi (https, mp3/aac)', 'Süre (saniye)', 'Kapak adresi (isteğe bağlı)', 'Lisans notu (zorunlu)']);
          if (f == null || !context.mounted) return;
          final secs = int.tryParse(f['Süre (saniye)'] ?? '');
          if (secs == null || secs <= 0) return toast(context, 'Süre saniye cinsinden bir sayı olmalı.', error: true);
          final r = await guard(context, () => Api.post('/api/admin/music/tracks', {
                'title': f['Başlık'],
                'artist': f['Sanatçı'],
                'url': f['Şarkı adresi (https, mp3/aac)'],
                'durationMs': secs * 1000,
                if ((f['Kapak adresi (isteğe bağlı)'] ?? '').isNotEmpty) 'coverUrl': f['Kapak adresi (isteğe bağlı)'],
                'licenseNote': f['Lisans notu (zorunlu)'],
              }));
          if (r != null && context.mounted) toast(context, 'Müzik eklendi.');
        },
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
    final res = await guard(context, () => Api.post('/api/admin/users/$id/status', {'status': 'banned', 'reason': 'Şikâyet: ${r['reason']}'}));
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
                        if (r['roomId'] != null) Text('Oda: ${r['roomId']}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
