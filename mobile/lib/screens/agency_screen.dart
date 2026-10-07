import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import '../widgets/common.dart';

const _statusText = {
  'pending': 'İnceleniyor',
  'approved': 'Onaylı',
  'rejected': 'Reddedildi (tekrar başvurabilirsiniz)',
  'suspended': 'Askıya alındı',
  'active': 'Aktif',
};

const _kycText = {'none': 'Doğrulanmadı', 'pending': 'İnceleniyor', 'approved': 'Onaylı', 'rejected': 'Reddedildi'};

String periodTitle(String key) {
  if (key.startsWith('W')) return 'Hafta ${key.substring(1)}';
  return key;
}

double _ratio(num value, num target) => target <= 0 ? 1 : (value / target).clamp(0, 1).toDouble();

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

  Future<void> _applyByCode() async {
    final code = await askText(context, 'Ajans kodu (8 hane)', keyboard: TextInputType.number);
    if (code == null || !mounted) return;
    final info = await guard(context, () => Api.get('/api/agencies/by-code/${code.trim()}'));
    if (info == null || !mounted) return;
    final a = mapOf(info['agency']) ?? {};
    if (!await confirm(context, '"${a['name']}" ajansına başvurulsun mu?', action: 'Başvur')) return;
    if (!mounted) return;
    await _act(null, () => Api.post('/api/agencies/apply-by-code', {'code': code.trim()}), done: 'Başvurunuz ajansa iletildi.');
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
                      Text(bStatus == 'rejected' ? 'Önceki başvurunuz reddedildi. Yeniden başvurabilirsiniz.' : 'Yayıncı başvurunuz yönetici tarafından incelenir. Onaylanınca bir ajansa katılabilirsiniz.'),
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
              if (b != null && agency == null && (bStatus == 'pending' || bStatus == 'approved')) ...[
                FilledButton.tonalIcon(onPressed: _applyByCode, icon: const Icon(Icons.pin), label: const Text('Ajans koduyla başvur')),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: _browseAgencies, icon: const Icon(Icons.business), label: const Text('Ajanslara göz at ve başvur')),
              ],
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

  Widget _target(String label, String value, double ratio, bool met) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text(value, style: TextStyle(color: met ? Colors.greenAccent : Colors.white70)),
          if (met) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.check_circle, size: 16, color: Colors.greenAccent)),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: ratio, minHeight: 6, borderRadius: BorderRadius.circular(3)),
      ]),
    );
  }

  Widget _progressPanel(Map<String, dynamic> b) {
    final p = mapOf(b['progress']);
    if (p == null) return const SizedBox.shrink();
    final cur = (p['currency'] ?? 'USD').toString();
    final seconds = (p['seconds'] as num?) ?? 0;
    final diamonds = BigInt.tryParse(p['diamonds'].toString()) ?? BigInt.zero;
    final next = mapOf(p['next']);
    final tier = p['tier'];
    final tiers = listOf(mapOf(b['config'])?['salaryTiers']);
    final target = next ?? (tiers.isNotEmpty ? tiers.last : null);
    final targetHours = (target?['hours'] as num?) ?? 0;
    final targetDia = BigInt.tryParse((target?['diamonds'] ?? '0').toString()) ?? BigInt.zero;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(height: 24),
      Text('Dönem: ${periodTitle(p['periodKey'].toString())}', style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(tier == null ? 'Henüz maaş kademesine ulaşmadınız.' : 'Kademe $tier · tahmini maaş ${fmtMoney(p['estimatedCents'], cur)}'),
      if (p['atRisk'] == true)
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
          child: Text(
            p['eventsMet'] == false
                ? 'Zorunlu resmi etkinlik sayısı tamamlanmadı; maaşınızdan kesinti uygulanacak (${fmtMoney(p['baseCents'], cur)} → ${fmtMoney(p['estimatedCents'], cur)}).'
                : 'Yayın saati hedefi tutmadı; maaşınızdan kesinti uygulanacak (${fmtMoney(p['baseCents'], cur)} → ${fmtMoney(p['estimatedCents'], cur)}).',
            style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
          ),
        ),
      if (target != null) ...[
        _target('Yayın süresi (hedef $targetHours sa)', fmtDuration(seconds), _ratio(seconds, targetHours * 3600), seconds >= targetHours * 3600),
        _target('Diamond (hedef ${fmtNumber(targetDia.toString())})', '${fmtNumber(diamonds.toString())} 💎', targetDia == BigInt.zero ? 1 : (diamonds.toDouble() / targetDia.toDouble()).clamp(0, 1).toDouble(), diamonds >= targetDia),
      ],
      if (p['requireOfficialEvents'] == true)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('Resmi etkinlik: ${p['eventCount']}/${p['minEventCount']}', style: TextStyle(color: p['eventsMet'] == true ? Colors.greenAccent : Colors.orangeAccent))),
      const SizedBox(height: 6),
      const Text('Kendinize gönderilen hediyeler yayıncı kazancına ve ajans komisyonuna dahil edilmez.', style: TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 8),
      Row(children: [
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HostStatementsScreen())),
          icon: const Icon(Icons.receipt_long),
          label: const Text('Maaş özetlerim'),
        ),
      ]),
    ]);
  }

  Widget _kycRow(Map<String, dynamic> b) {
    final kyc = (b['kycStatus'] ?? 'none').toString();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        const Icon(Icons.verified_user_outlined, size: 18),
        const SizedBox(width: 6),
        Expanded(child: Text('Kimlik doğrulama (maaş ödemesi için gerekir): ${_kycText[kyc] ?? kyc}', style: const TextStyle(fontSize: 12))),
        if (kyc == 'none' || kyc == 'rejected')
          TextButton(onPressed: () => _act(null, () => Api.post('/api/me/kyc/request'), done: 'Başvurunuz alındı.'), child: const Text('Başvur')),
      ]),
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
            const SizedBox(height: 6),
            Text('Toplam kazanç: ${fmtNumber(b['totalDiamonds'])} 💎'),
            _progressPanel(b),
            _kycRow(b),
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
    final code = owned['agencyCode']?.toString();
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
            if (code != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.pin),
                title: Text('Ajans kodu: $code', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                subtitle: const Text('Yayıncılar bu kodla ajansınıza başvurur.'),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    toast(context, 'Kod kopyalandı.');
                  },
                ),
              ),
            const SizedBox(height: 6),
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

class HostStatementsScreen extends StatelessWidget {
  const HostStatementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Maaş özetlerim')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        load: () async => listOf((await Api.get('/api/broadcaster/statements'))['statements']),
        builder: (context, list, reload) => RefreshIndicator(
          onRefresh: reload,
          child: list.isEmpty
              ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Henüz kapanmış bir dönem yok.')))])
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final s in list)
                    Card(
                      child: ListTile(
                        leading: Icon(s['status'] == 'paid' ? Icons.check_circle : Icons.hourglass_bottom, color: s['status'] == 'paid' ? Colors.greenAccent : Colors.amber),
                        title: Text('${periodTitle(s['periodKey'].toString())} · ${fmtMoney(s['salaryCents'])}'),
                        subtitle: Text('${fmtDuration((s['seconds'] as num?) ?? 0)} · ${fmtNumber(s['diamonds'])} 💎 · Kademe ${s['tier'] ?? '-'}'
                            '${s['penaltyApplied'] == true ? '\nKesinti uygulandı (ham maaş ${fmtMoney(s['baseSalaryCents'])})' : ''}'
                            '\n${s['status'] == 'paid' ? 'Ödendi' : 'Ödeme bekliyor'}'),
                        isThreeLine: true,
                      ),
                    ),
                ]),
        ),
      ),
    );
  }
}

class AgencyStatementsScreen extends StatelessWidget {
  final String agencyId;
  const AgencyStatementsScreen({super.key, required this.agencyId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hesap özetleri')),
      body: AsyncBody<Map<String, dynamic>>(
        load: () => Api.get('/api/agencies/$agencyId/statements'),
        builder: (context, data, reload) {
          final ags = listOf(data['agencyStatements']);
          final hosts = listOf(data['hostStatements']);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Text('Ajans komisyonu', style: Theme.of(context).textTheme.titleMedium),
              if (ags.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Henüz kapanmış dönem yok.')),
              for (final s in ags)
                Card(
                  child: ListTile(
                    leading: Icon(s['status'] == 'paid' ? Icons.check_circle : Icons.hourglass_bottom, color: s['status'] == 'paid' ? Colors.greenAccent : Colors.amber),
                    title: Text('${periodTitle(s['periodKey'].toString())} · ${fmtNumber(s['commissionDiamonds'])} 💎'),
                    subtitle: Text('Ekip: ${fmtNumber(s['teamDiamonds'])} 💎 · %${((s['commissionBps'] as num) / 100).toStringAsFixed(1)} · ${s['hostCount']} yayıncı\n${s['status'] == 'paid' ? 'Ödendi' : 'Ödeme bekliyor'}'),
                    isThreeLine: true,
                  ),
                ),
              const SizedBox(height: 8),
              Text('Yayıncı maaşları', style: Theme.of(context).textTheme.titleMedium),
              for (final s in hosts)
                Card(
                  child: ListTile(
                    title: Text('@${s['username']} · ${periodTitle(s['periodKey'].toString())}'),
                    subtitle: Text('${fmtMoney(s['salaryCents'])} · ${fmtDuration((s['seconds'] as num?) ?? 0)} · ${fmtNumber(s['diamonds'])} 💎'
                        '${s['penaltyApplied'] == true ? ' · kesinti' : ''} · ${s['status'] == 'paid' ? 'ödendi' : 'bekliyor'}'),
                  ),
                ),
            ]),
          );
        },
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

  void _reload() {
    if (mounted) setState(() => _version++);
  }

  Future<Map<String, dynamic>> _load() async {
    final d = await Api.get('/api/agencies/${widget.agencyId}/dashboard');
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
        IconButton(
          tooltip: 'Hesap özetleri',
          icon: const Icon(Icons.receipt_long),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AgencyStatementsScreen(agencyId: widget.agencyId))),
        ),
        IconButton(tooltip: 'Yayıncı davet et', icon: const Icon(Icons.person_add), onPressed: _invite),
      ]),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: _load,
        builder: (context, data, reload) {
          final d = mapOf(data['dashboard']) ?? {};
          final totals = mapOf(d['totals']) ?? {};
          final cur = (d['currency'] ?? 'USD').toString();
          final broadcasters = listOf(d['broadcasters']);
          final requests = listOf(data['requests']);
          final next = mapOf(totals['next']);
          final bps = (totals['commissionBps'] as num?) ?? 0;
          final team = BigInt.tryParse(totals['teamDiamonds'].toString()) ?? BigInt.zero;
          final nextMin = BigInt.tryParse((next?['minDiamonds'] ?? '0').toString()) ?? BigInt.zero;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Dönem: ${periodTitle(d['periodKey'].toString())}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Ekip Diamond: ${fmtNumber(totals['teamDiamonds'])} 💎'),
                    Text('Toplam yayın süresi: ${fmtDuration((totals['seconds'] as num?) ?? 0)}'),
                    const Divider(),
                    Text('Komisyon oranı: %${(bps / 100).toStringAsFixed(1)}${totals['overrideBps'] != null ? ' (ajansa özel)' : totals['commissionTier'] != null ? ' (kademe ${totals['commissionTier']})' : ''}'),
                    Text('Tahmini komisyon: ${fmtNumber(totals['estimatedCommissionDiamonds'])} 💎'),
                    Text('Yayıncı maaşları (tahmini, toplam): ${fmtMoney(totals['estimatedSalaryCents'], cur)}'),
                    if (next != null) ...[
                      const SizedBox(height: 8),
                      Text('Sonraki kademe: %${((next['bps'] as num) / 100).toStringAsFixed(1)} — ${fmtNumber(next['remaining'])} 💎 kaldı'),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: nextMin == BigInt.zero ? 1 : (team.toDouble() / nextMin.toDouble()).clamp(0, 1).toDouble(), minHeight: 6, borderRadius: BorderRadius.circular(3)),
                    ],
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
              if (broadcasters.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Henüz yayıncı yok. Sağ üstten davet gönderebilir veya ajans kodunuzu paylaşabilirsiniz.')),
              for (final x in broadcasters)
                Card(
                  child: ListTile(
                    leading: UserAvatar(user: x),
                    title: Text((x['displayName'] ?? '').toString()),
                    subtitle: Text('@${x['username']} · ${_statusText[x['status']] ?? x['status']}\n'
                        '${fmtNumber(x['diamonds'])} 💎 · ${fmtDuration((x['seconds'] as num?) ?? 0)} · Kademe ${x['tier'] ?? '-'}\n'
                        'Tahmini maaş: ${fmtMoney(x['estimatedCents'], cur)}${x['atRisk'] == true ? ' ⚠ kesinti riski' : ''}'),
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
