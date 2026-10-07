import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/common.dart';

class WipScreen extends StatefulWidget {
  const WipScreen({super.key});

  @override
  State<WipScreen> createState() => _WipScreenState();
}

class _WipScreenState extends State<WipScreen> {
  int _version = 0;

  Future<Map<String, dynamic>> _load() async {
    final tiers = await Api.get('/api/wip/tiers');
    final mine = await Api.get('/api/wip');
    return {'tiers': listOf(tiers['tiers']), 'current': mapOf(mine['wip'])};
  }

  Future<void> _buy(Map<String, dynamic> tier, Map<String, dynamic> plan, Map<String, dynamic>? current) async {
    final price = fmtNumber(plan['priceCoins']);
    final extending = current != null && current['level'] == tier['level'];
    final msg = extending
        ? '${tier['name']} süreniz ${plan['durationDays']} gün uzatılacak. $price Coin harcanacak.'
        : '${tier['name']} satın alınacak (${plan['durationDays']} gün). $price Coin harcanacak.';
    if (!await confirm(context, msg, action: 'Satın al')) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.post('/api/wip/purchase', {'planId': plan['id']}));
    if (r == null || !mounted) return;
    Session.setCoins((r['balance'] ?? Session.coins).toString());
    toast(context, 'WIP etkinleştirildi.');
    setState(() => _version++);
  }

  List<String> _featureLines(Map<String, dynamic> f) => [
        'Renkli isim ve WIP rozeti',
        'Aynı anda ${f['maxRooms']} oda açma',
        if (f['viewVisitors'] == true) 'Profil ziyaretçilerini görme',
        if (f['kickImmunity'] == true) 'Moderatörler tarafından atılamama',
        if (f['profileEffect'] == true) 'Profil efekti kullanma',
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WIP üyelik')),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: _load,
        builder: (context, data, reload) {
          final tiers = listOf(data['tiers']);
          final current = mapOf(data['current']);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Card(
                color: current == null ? null : Colors.amber.withValues(alpha: 0.15),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: current == null
                      ? const Text('Aktif WIP üyeliğiniz yok. Aşağıdan bir kademe seçerek ayrıcalıklara kavuşun.')
                      : Text('Aktif: ${current['name']}\nBitiş: ${DateTime.tryParse(current['expiresAt'].toString())?.toLocal().toString().substring(0, 16) ?? ''}'),
                ),
              ),
              for (final t in tiers)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.workspace_premium, color: parseColor(mapOf(t['features'])?['nameColor'] as String?) ?? Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(child: Text(t['name'].toString(), style: Theme.of(context).textTheme.titleMedium)),
                        if (current != null && current['level'] == t['level']) const Chip(label: Text('Aktif'), visualDensity: VisualDensity.compact),
                      ]),
                      const SizedBox(height: 8),
                      for (final line in _featureLines(mapOf(t['features']) ?? {})) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [const Icon(Icons.check, size: 16, color: Colors.greenAccent), const SizedBox(width: 6), Expanded(child: Text(line))])),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        for (final plan in listOf(t['plans']))
                          FilledButton.tonal(
                            onPressed: (current != null && (current['level'] as num) > (t['level'] as num)) ? null : () => _buy(t, plan, current),
                            child: Text('${plan['durationDays']} gün · ${fmtNumber(plan['priceCoins'])} Coin'),
                          ),
                      ]),
                    ]),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
