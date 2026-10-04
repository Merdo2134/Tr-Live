import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import 'agency_screen.dart' show periodTitle;

/// Yönetici: ajans/maaş ayarları, dönem kapatma ve ödeme işaretleme, resmi etkinlikler, KYC.
class PayoutsTab extends StatefulWidget {
  const PayoutsTab({super.key});

  @override
  State<PayoutsTab> createState() => _PayoutsTabState();
}

class _PayoutsTabState extends State<PayoutsTab> {
  int _v = 0;

  Future<Map<String, dynamic>> _load() async {
    final c = await Api.get('/api/admin/agency-config');
    final p = await Api.get('/api/admin/payouts');
    final e = await Api.get('/api/admin/events');
    final k = await Api.get('/api/admin/kyc', query: {'status': 'pending'});
    return {'config': mapOf(c['config']), 'periods': listOf(p['periods']), 'events': listOf(e['events']), 'kyc': listOf(k['users'])};
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action, {String? done}) async {
    final r = await guard(context, action);
    if (r == null || !mounted) return;
    if (done != null) toast(context, done);
    setState(() => _v++);
  }

  // ---- ayarlar ----
  Future<void> _editSettings(Map<String, dynamic> st) async {
    var cycle = (st['cycle'] ?? 'monthly').toString();
    var events = st['requireOfficialEvents'] == true;
    final penalty = TextEditingController(text: '${((st['penaltyBps'] as num?) ?? 5000) / 100}');
    final minEv = TextEditingController(text: '${st['minEventCount'] ?? 0}');
    final cur = TextEditingController(text: (st['currency'] ?? 'USD').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('Genel ayarlar'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: cycle,
                decoration: const InputDecoration(labelText: 'Hesap dönemi'),
                items: const [DropdownMenuItem(value: 'weekly', child: Text('Haftalık (Pzt-Paz)')), DropdownMenuItem(value: 'monthly', child: Text('Aylık'))],
                onChanged: (v) => setS(() => cycle = v ?? cycle),
              ),
              TextField(controller: penalty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Hedef tutmazsa maaş kesintisi (%)')),
              SwitchListTile(dense: true, title: const Text('Resmi etkinlik katılımı zorunlu'), value: events, onChanged: (v) => setS(() => events = v)),
              TextField(controller: minEv, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Dönemde en az etkinlik sayısı')),
              TextField(controller: cur, maxLength: 3, decoration: const InputDecoration(labelText: 'Para birimi (örn. USD)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    final pct = double.tryParse(penalty.text.replaceAll(',', '.'));
    final min = int.tryParse(minEv.text.trim());
    final currency = cur.text.trim().toUpperCase();
    penalty.dispose();
    minEv.dispose();
    cur.dispose();
    if (ok != true || !mounted) return;
    if (pct == null || pct < 0 || pct > 100 || min == null) return toast(context, 'Değerleri kontrol edin.', error: true);
    await _run(() => Api.put('/api/admin/agency-config', {
          'settings': {'cycle': cycle, 'penaltyBps': (pct * 100).round(), 'requireOfficialEvents': events, 'minEventCount': min, 'currency': currency},
        }), done: 'Ayarlar kaydedildi.');
  }

  String _salaryText(List<Map<String, dynamic>> tiers) => tiers
      .map((t) => '${t['hours']}, ${t['diamonds']}, ${(BigInt.parse(t['salaryCents'].toString()) / BigInt.from(100)).toStringAsFixed(2)}')
      .join('\n');

  String _commissionText(List<Map<String, dynamic>> tiers) => tiers.map((t) => '${t['minDiamonds']}, ${(t['bps'] as num) / 100}').join('\n');

  Future<String?> _linesDialog(String title, String help, String initial) async {
    final ctl = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(help, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 8),
            TextField(controller: ctl, maxLines: 8, keyboardType: TextInputType.multiline, decoration: const InputDecoration(border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      ),
    );
    final text = ctl.text;
    ctl.dispose();
    return ok == true ? text : null;
  }

  Future<void> _editSalary(List<Map<String, dynamic>> tiers) async {
    final text = await _linesDialog(
      'Yayıncı maaş kademeleri',
      'Her satır bir kademe: saat, Diamond hedefi, maaş (para birimi cinsinden).\nÖrnek: 20, 10000, 50.00\nKademeler artan sırada olmalı.',
      _salaryText(tiers),
    );
    if (text == null || !mounted) return;
    final out = <Map<String, dynamic>>[];
    for (final line in text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)) {
      final parts = line.split(',').map((x) => x.trim()).toList();
      final hours = int.tryParse(parts.isNotEmpty ? parts[0] : '');
      final dia = BigInt.tryParse(parts.length > 1 ? parts[1] : '');
      final money = double.tryParse(parts.length > 2 ? parts[2].replaceAll(',', '.') : '');
      if (hours == null || dia == null || money == null || parts.length != 3) return toast(context, 'Satır hatalı: "$line"', error: true);
      out.add({'hours': hours, 'diamonds': dia.toString(), 'salaryCents': (money * 100).round().toString()});
    }
    await _run(() => Api.put('/api/admin/agency-config', {'salaryTiers': out}), done: 'Maaş kademeleri kaydedildi.');
  }

  Future<void> _editCommission(List<Map<String, dynamic>> tiers) async {
    final text = await _linesDialog(
      'Ajans komisyon kademeleri',
      'Her satır bir kademe: ekip Diamond eşiği, komisyon yüzdesi.\nÖrnek: 500000, 30\nİlk satır 0 ile başlamalı, eşikler artmalı.',
      _commissionText(tiers),
    );
    if (text == null || !mounted) return;
    final out = <Map<String, dynamic>>[];
    for (final line in text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)) {
      final parts = line.split(',').map((x) => x.trim()).toList();
      final min = BigInt.tryParse(parts.isNotEmpty ? parts[0] : '');
      final pct = double.tryParse(parts.length > 1 ? parts[1].replaceAll(',', '.') : '');
      if (min == null || pct == null || parts.length != 2) return toast(context, 'Satır hatalı: "$line"', error: true);
      out.add({'minDiamonds': min.toString(), 'bps': (pct * 100).round()});
    }
    await _run(() => Api.put('/api/admin/agency-config', {'commissionTiers': out}), done: 'Komisyon kademeleri kaydedildi.');
  }

  // ---- dönem / etkinlik ----
  Future<void> _closePeriod() async {
    final f = await formDialog(context, 'Dönemi kapat', ['Dönem (boş = bir önceki dönem; örn. 2026-09 veya W2026-09-28)']);
    if (f == null || !mounted) return;
    final key = f.values.first;
    if (!await confirm(context, 'Dönem kapatılınca tüm yayıncı ve ajans hesap özetleri oluşturulur. Bu işlem geri alınamaz.', action: 'Kapat')) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.post('/api/admin/payouts/close', {if (key.isNotEmpty) 'period': key}));
    if (r == null || !mounted) return;
    toast(context, '${periodTitle(r['periodKey'].toString())} kapatıldı: ${r['hostStatements']} yayıncı, ${r['agencyStatements']} ajans.');
    setState(() => _v++);
  }

  Future<void> _newEvent() async {
    final f = await formDialog(context, 'Resmi etkinlik', ['Başlık', 'Başlangıç (YYYY-AA-GG SS:DD, Türkiye saati)']);
    if (f == null || !mounted) return;
    final raw = f['Başlangıç (YYYY-AA-GG SS:DD, Türkiye saati)']!.replaceFirst(' ', 'T');
    final dt = DateTime.tryParse('$raw:00+03:00') ?? DateTime.tryParse('$raw+03:00');
    if (dt == null) return toast(context, 'Tarih biçimi geçersiz.', error: true);
    await _run(() => Api.post('/api/admin/events', {'title': f['Başlık'], 'startsAt': dt.toUtc().toIso8601String()}), done: 'Etkinlik eklendi.');
  }

  Future<void> _markAttendance(Map<String, dynamic> e) async {
    final u = await pickUser(context, admin: true);
    if (u == null || !mounted) return;
    await _run(() => Api.post('/api/admin/events/${e['id']}/attendance', {'userIds': [u['id']]}), done: 'Katılım işaretlendi.');
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Map<String, dynamic>>(
      key: ValueKey(_v),
      load: _load,
      builder: (context, data, reload) {
        final cfg = mapOf(data['config']) ?? {};
        final st = mapOf(cfg['settings']) ?? {};
        final sal = listOf(cfg['salaryTiers']);
        final com = listOf(cfg['commissionTiers']);
        final periods = listOf(data['periods']);
        final events = listOf(data['events']);
        final kyc = listOf(data['kyc']);
        final admin = Session.isAdmin;
        final cur = (st['currency'] ?? 'USD').toString();
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Genel ayarlar', style: Theme.of(context).textTheme.titleMedium),
                  Text('Dönem: ${st['cycle'] == 'weekly' ? 'haftalık' : 'aylık'} · hedef tutmazsa kesinti %${((st['penaltyBps'] as num?) ?? 0) / 100} · etkinlik zorunlu: ${st['requireOfficialEvents'] == true ? 'evet (${st['minEventCount']})' : 'hayır'} · $cur'),
                  if (admin) TextButton.icon(onPressed: () => _editSettings(st), icon: const Icon(Icons.tune), label: const Text('Düzenle')),
                  const Divider(),
                  Text('Yayıncı maaş kademeleri', style: Theme.of(context).textTheme.titleSmall),
                  for (final t in sal) Text('Kademe ${t['level']}: ${t['hours']} sa · ${fmtNumber(t['diamonds'])} 💎 → ${fmtMoney(t['salaryCents'], cur)}'),
                  if (admin) TextButton.icon(onPressed: () => _editSalary(sal), icon: const Icon(Icons.edit), label: const Text('Kademeleri düzenle')),
                  const Divider(),
                  Text('Ajans komisyon kademeleri', style: Theme.of(context).textTheme.titleSmall),
                  for (final t in com) Text('Kademe ${t['level']}: ≥ ${fmtNumber(t['minDiamonds'])} 💎 → %${((t['bps'] as num) / 100).toStringAsFixed(1)}'),
                  if (admin) TextButton.icon(onPressed: () => _editCommission(com), icon: const Icon(Icons.edit), label: const Text('Kademeleri düzenle')),
                  const Text('Not: Bu değerler örnektir; gerçek oranları sözleşmenize göre ayarlayın. Ödemeler platform dışında yapılır.', style: TextStyle(fontSize: 11, color: Colors.white54)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Kapanan dönemler', style: Theme.of(context).textTheme.titleMedium)),
              if (admin) FilledButton.tonalIcon(onPressed: _closePeriod, icon: const Icon(Icons.lock_clock), label: const Text('Dönemi kapat')),
            ]),
            if (periods.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Henüz kapanmış dönem yok.')),
            for (final p in periods)
              Card(
                child: ListTile(
                  title: Text(periodTitle(p['periodKey'].toString())),
                  subtitle: Text('${p['hosts']} yayıncı (${p['pendingHosts']} bekliyor) · ${p['agencies']} ajans (${p['pendingAgencies']} bekliyor)\nToplam maaş: ${fmtMoney(p['totalSalaryCents'], cur)}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => PeriodDetailScreen(periodId: p['id'].toString(), currency: cur)));
                    if (mounted) setState(() => _v++);
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Resmi etkinlikler', style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(onPressed: _newEvent, icon: const Icon(Icons.add), label: const Text('Ekle')),
            ]),
            for (final e in events)
              Card(
                child: ListTile(
                  title: Text(e['title'].toString()),
                  subtitle: Text('${DateTime.parse(e['startsAt'].toString()).toLocal().toString().substring(0, 16)} · ${e['attendees']} katılımcı'),
                  trailing: IconButton(tooltip: 'Katılım işaretle', icon: const Icon(Icons.how_to_reg), onPressed: () => _markAttendance(e)),
                ),
              ),
            const SizedBox(height: 8),
            Text('Kimlik doğrulama (KYC) bekleyenler', style: Theme.of(context).textTheme.titleMedium),
            if (kyc.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Bekleyen başvuru yok.')),
            for (final u in kyc)
              Card(
                child: ListTile(
                  title: Text('${u['displayName']} (@${u['username']})'),
                  trailing: !admin
                      ? null
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: () => _run(() => Api.post('/api/admin/users/${u['id']}/kyc', {'status': 'approved'}), done: 'Onaylandı.')),
                          IconButton(icon: const Icon(Icons.close, color: Colors.redAccent), onPressed: () => _run(() => Api.post('/api/admin/users/${u['id']}/kyc', {'status': 'rejected'}), done: 'Reddedildi.')),
                        ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

class PeriodDetailScreen extends StatefulWidget {
  final String periodId;
  final String currency;
  const PeriodDetailScreen({super.key, required this.periodId, required this.currency});

  @override
  State<PeriodDetailScreen> createState() => _PeriodDetailScreenState();
}

class _PeriodDetailScreenState extends State<PeriodDetailScreen> {
  int _v = 0;

  Future<void> _pay(String kind, String id, String what) async {
    if (!await confirm(context, '$what için ödeme platform dışında yapıldı mı? "Ödendi" olarak işaretlenecek.', action: 'Ödendi işaretle')) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.post('/api/admin/statements/$kind/$id/pay'));
    if (r != null && mounted) {
      toast(context, 'Ödendi olarak işaretlendi.');
      setState(() => _v++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dönem ayrıntısı')),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_v),
        load: () => Api.get('/api/admin/payouts/${widget.periodId}'),
        builder: (context, data, reload) {
          final hosts = listOf(data['hostStatements']);
          final ags = listOf(data['agencyStatements']);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Text('Ajans komisyonları', style: Theme.of(context).textTheme.titleMedium),
              for (final a in ags)
                Card(
                  child: ListTile(
                    title: Text('${a['agencyName']} · ${fmtNumber(a['commissionDiamonds'])} 💎'),
                    subtitle: Text('Ekip: ${fmtNumber(a['teamDiamonds'])} 💎 · %${((a['commissionBps'] as num) / 100).toStringAsFixed(1)} · ${a['hostCount']} yayıncı'),
                    trailing: a['status'] == 'paid'
                        ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                        : (Session.isAdmin ? TextButton(onPressed: () => _pay('agency', a['id'].toString(), a['agencyName'].toString()), child: const Text('Öde')) : const Text('Bekliyor')),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Yayıncı maaşları', style: Theme.of(context).textTheme.titleMedium),
              for (final h in hosts)
                Card(
                  child: ListTile(
                    title: Text('@${h['username']} · ${fmtMoney(h['salaryCents'], widget.currency)}'),
                    subtitle: Text('${fmtDuration((h['seconds'] as num?) ?? 0)} · ${fmtNumber(h['diamonds'])} 💎 · kademe ${h['tier'] ?? '-'}'
                        '${h['penaltyApplied'] == true ? ' · kesinti' : ''}\nKYC: ${h['kycStatus']}'),
                    isThreeLine: true,
                    trailing: h['status'] == 'paid'
                        ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                        : (Session.isAdmin ? TextButton(onPressed: () => _pay('host', h['id'].toString(), '@${h['username']}'), child: const Text('Öde')) : const Text('Bekliyor')),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
