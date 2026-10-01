import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/common.dart';

const _statusText = {
  'pending': 'İnceleniyor',
  'approved': 'Onaylı',
  'rejected': 'Reddedildi (tekrar başvurabilirsiniz)',
  'suspended': 'Askıya alındı',
  'active': 'Aktif',
};

/// Dönem listesi (Türkiye saati): bu ay ve önceki 5 ay, "YYYY-AA".
List<String> recentPeriods() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 3));
  return [
    for (var i = 0; i < 6; i++)
      () {
        final d = DateTime.utc(now.year, now.month - i, 1);
        return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
      }(),
  ];
}

class AgencyScreen extends StatefulWidget {
  const AgencyScreen({super.key});

  @override
  State<AgencyScreen> createState() => _AgencyScreenState();
}

class _AgencyScreenState extends State<AgencyScreen> {
  int _version = 0;

  void _reload() {
    if (mounted) setState(() => _version++);
  }

  Future<Map<String, dynamic>> _load() async {
    final mine = await Api.get('/api/agencies/mine');
    final b = await Api.get('/api/broadcaster/me');
    final reqs = await Api.get('/api/broadcaster/requests');
    return {'owned': mapOf(mine['owned']), 'broadcaster': mapOf(b['broadcaster']), 'requests': listOf(reqs['requests'])};
  }

  Future<void> _act(String? confirmText, Future<Map<String, dynamic>> Function() action, {String? done}) async {
    if (confirmText != null && !await confirm(context, confirmText)) return;
    if (!mounted) return;
    final r = await guard(context, action);
    if (r == null || !mounted) return;
    if (done != null) toast(context, done);
    _reload();
  }

  Future<void> _createAgency() async {
    final name = await askText(context, 'Ajans adı');
    if (name == null || !mounted) return;
    final desc = await askText(context, 'Kısa açıklama (isteğe bağlı)');
    if (!mounted) return;
    await _act(null, () => Api.post('/api/agencies', {'name': name, if (desc != null) 'description': desc}), done: 'Ajans başvurunuz alındı; yönetici onayı bekleniyor.');
  }

  Future<void> _browseAgencies() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: AsyncBody<List<Map<String, dynamic>>>(
          load: () async => listOf((await Api.get('/api/agencies'))['agencies']),
          builder: (c, list, reload) => list.isEmpty
              ? const Center(child: Text('Aktif ajans yok.'))
              : ListView(children: [
                  for (final a in list)
                    ListTile(
                      leading: const Icon(Icons.business),
                      title: Text(a['name'].toString()),
                      subtitle: Text('${a['broadcasterCount'] ?? 0} yayıncı${(a['description'] ?? '').toString().isEmpty ? '' : '\n${a['description']}'}'),
                      trailing: FilledButton.tonal(onPressed: () => Navigator.pop(c, a), child: const Text('Başvur')),
                    ),
                ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _act(null, () => Api.post('/api/agencies/${picked['id']}/apply'), done: 'Başvurunuz ajansa iletildi.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajans ve yayıncı')),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: _load,
        builder: (context, data, reload) {
          final owned = mapOf(data['owned']);
          final b = mapOf(data['broadcaster']);
          final requests = listOf(data['requests']);
          final agency = mapOf(b?['agency']);
          final bStatus = b?['status']?.toString();
          final canBeBroadcaster = owned == null && (b == null || bStatus == 'rejected');
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              if (canBeBroadcaster)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Yayıncı ol', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(bStatus == 'rejected' ? 'Önceki başvurunuz reddedildi. Yeniden başvurabilirsiniz.' : 'Yayıncı başvurunuz yönetici tarafından incelenir. Onaylanınca bir ajansa katılabilir veya bağımsız yayın yapabilirsiniz.'),
                      const SizedBox(height: 10),
                      FilledButton.icon(onPressed: () => _act(null, () => Api.post('/api/broadcaster/apply'), done: 'Başvurunuz alındı.'), icon: const Icon(Icons.podcasts), label: const Text('Yayıncı olarak başvur')),
                    ]),
                  ),
                ),
              if (b != null && bStatus != 'rejected') _broadcasterCard(b, bStatus, agency),
              for (final r in requests)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: Text(r['direction'] == 'invite' ? '${mapOf(r['agency'])?['name']} sizi davet etti' : '${mapOf(r['agency'])?['name']} ajansına başvurunuz bekliyor'),
                    trailing: r['direction'] == 'invite'
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: () => _act(null, () => Api.post('/api/agency-requests/${r['id']}/respond', {'accept': true}), done: 'Ajansa katıldınız.')),
                            IconButton(icon: const Icon(Icons.close, color: Colors.redAccent), onPressed: () => _act(null, () => Api.post('/api/agency-requests/${r['id']}/respond', {'accept': false}))),
                          ])
                        : const Text('Bekliyor'),
                  ),
                ),
              if (b != null && agency == null && (bStatus == 'pending' || bStatus == 'approved'))
                OutlinedButton.icon(onPressed: _browseAgencies, icon: const Icon(Icons.business), label: const Text('Ajanslara göz at ve başvur')),
              const SizedBox(height: 12),
              if (owned != null) _ownerCard(owned),
              if (owned == null && (b == null || bStatus == 'rejected'))
                OutlinedButton.icon(onPressed: _createAgency, icon: const Icon(Icons.add_business), label: const Text('Ajans kur')),
            ]),
          );
        },
      ),
    );
  }

  Widget _broadcasterCard(Map<String, dynamic> b, String? status, Map<String, dynamic>? agency) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.podcasts, color: Colors.pinkAccent),
            const SizedBox(width: 8),
            Text('Yayıncı · ${_statusText[status] ?? status}', style: Theme.of(context).textTheme.titleMedium),
          ]),
          if (status == 'approved') ...[
            const SizedBox(height: 10),
            Text('Bu ay (${b['period']}): ${fmtNumber(b['periodDiamonds'])} 💎 · ${fmtDuration((b['periodSeconds'] as num?) ?? 0)} yayın'),
            Text('Toplam: ${fmtNumber(b['totalDiamonds'])} 💎'),
            const SizedBox(height: 4),
            const Text('Kendinize gönderilen hediyeler yayıncı kazancına ve ajans komisyonuna dahil edilmez.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
          if (agency != null) ...[
            const Divider(height: 24),
            Row(children: [
              const Icon(Icons.business),
              const SizedBox(width: 8),
              Expanded(child: Text('Ajans: ${agency['name']}')),
              TextButton(onPressed: () => _act('Ajanstan ayrılmak istiyor musunuz?', () => Api.post('/api/broadcaster/leave-agency')), child: const Text('Ayrıl')),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _ownerCard(Map<String, dynamic> owned) {
    final active = owned['status'] == 'active';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.business),
            const SizedBox(width: 8),
            Expanded(child: Text(owned['name'].toString(), style: Theme.of(context).textTheme.titleMedium)),
            Chip(label: Text(_statusText[owned['status']] ?? owned['status'].toString()), visualDensity: VisualDensity.compact),
          ]),
          if (active) ...[
            Text('Komisyon oranı: %${((owned['commissionBps'] as num) / 100).toStringAsFixed(2)}'),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => AgencyDashboardScreen(agencyId: owned['id'].toString())));
                _reload();
              },
              icon: const Icon(Icons.dashboard),
              label: const Text('Ajans paneli'),
            ),
          ] else
            Text(owned['status'] == 'pending' ? 'Başvurunuz yönetici onayı bekliyor.' : 'Ajansınız şu anda kullanılamıyor. Destek ile iletişime geçin.'),
        ]),
      ),
    );
  }
}

class AgencyDashboardScreen extends StatefulWidget {
  final String agencyId;
  const AgencyDashboardScreen({super.key, required this.agencyId});

  @override
  State<AgencyDashboardScreen> createState() => _AgencyDashboardScreenState();
}

class _AgencyDashboardScreenState extends State<AgencyDashboardScreen> {
  int _version = 0;
  late String _period = recentPeriods().first;

  void _reload() {
    if (mounted) setState(() => _version++);
  }

  Future<Map<String, dynamic>> _load() async {
    final d = await Api.get('/api/agencies/${widget.agencyId}/dashboard', query: {'period': _period});
    final r = await Api.get('/api/agencies/${widget.agencyId}/requests');
    return {'dashboard': d, 'requests': listOf(r['requests'])};
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() action, {String? confirmText, String? done}) async {
    if (confirmText != null && !await confirm(context, confirmText)) return;
    if (!mounted) return;
    final r = await guard(context, action);
    if (r == null || !mounted) return;
    if (done != null) toast(context, done);
    _reload();
  }

  Future<void> _invite() async {
    final u = await pickUser(context);
    if (u == null || !mounted) return;
    await _act(() => Api.post('/api/agencies/${widget.agencyId}/invite', {'userId': u['id']}), done: '${u['displayName']} kullanıcısına davet gönderildi.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajans paneli'), actions: [
        IconButton(tooltip: 'Yayıncı davet et', icon: const Icon(Icons.person_add), onPressed: _invite),
      ]),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey('$_version$_period'),
        load: _load,
        builder: (context, data, reload) {
          final d = mapOf(data['dashboard']) ?? {};
          final totals = mapOf(d['totals']) ?? {};
          final broadcasters = listOf(d['broadcasters']);
          final requests = listOf(data['requests']);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Row(children: [
                const Text('Dönem'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _period,
                  items: [for (final p in recentPeriods()) DropdownMenuItem(value: p, child: Text(p))],
                  onChanged: (v) {
                    if (v != null) setState(() => _period = v);
                  },
                ),
              ]),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Toplam yayıncı kazancı: ${fmtNumber(totals['diamonds'])} 💎'),
                    Text('Toplam yayın süresi: ${fmtDuration((totals['seconds'] as num?) ?? 0)}'),
                    const Divider(),
                    Text('Komisyon (bu dönem, tahakkuk): ${fmtNumber(totals['commissionAccrued'])} 💎'),
                    Text('Komisyon (bu dönem, ödendi): ${fmtNumber(totals['commissionPaid'])} 💎'),
                    Text('Ödenmemiş toplam komisyon: ${fmtNumber(totals['commissionUnpaidAllTime'])} 💎'),
                  ]),
                ),
              ),
              if (requests.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text('Bekleyen istekler', style: Theme.of(context).textTheme.titleMedium)),
                for (final r in requests)
                  Card(
                    child: ListTile(
                      leading: UserAvatar(user: mapOf(r['user'])),
                      title: Text((mapOf(r['user'])?['displayName'] ?? '').toString()),
                      subtitle: Text(r['direction'] == 'apply' ? 'Ajansa başvurdu' : 'Davetiniz bekliyor'),
                      trailing: r['direction'] == 'apply'
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: () => _act(() => Api.post('/api/agency-requests/${r['id']}/respond', {'accept': true}), done: 'Yayıncı ajansa eklendi.')),
                              IconButton(icon: const Icon(Icons.close, color: Colors.redAccent), onPressed: () => _act(() => Api.post('/api/agency-requests/${r['id']}/respond', {'accept': false}))),
                            ])
                          : null,
                    ),
                  ),
              ],
              Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text('Yayıncılar (${broadcasters.length})', style: Theme.of(context).textTheme.titleMedium)),
              if (broadcasters.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Henüz yayıncı yok. Sağ üstten davet gönderebilirsiniz.')),
              for (final x in broadcasters)
                Card(
                  child: ListTile(
                    leading: UserAvatar(user: x),
                    title: Text((x['displayName'] ?? '').toString()),
                    subtitle: Text('@${x['username']} · ${_statusText[x['status']] ?? x['status']}\n${fmtNumber(x['diamonds'])} 💎 · ${fmtDuration((x['seconds'] as num?) ?? 0)}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Ajanstan çıkar',
                      icon: const Icon(Icons.person_remove),
                      onPressed: () => _act(() => Api.post('/api/agencies/${widget.agencyId}/broadcasters/${x['id']}/remove'), confirmText: 'Yayıncı ajanstan çıkarılsın mı?'),
                    ),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
