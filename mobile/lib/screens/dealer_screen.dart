import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/common.dart';

class DealerScreen extends StatefulWidget {
  const DealerScreen({super.key});

  @override
  State<DealerScreen> createState() => _DealerScreenState();
}

class _DealerScreenState extends State<DealerScreen> {
  int _version = 0;
  final _username = TextEditingController();
  final _amount = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _sell() async {
    final amount = int.tryParse(_amount.text.trim());
    if (_username.text.trim().isEmpty || amount == null || amount <= 0) return toast(context, 'Kullanıcı adı ve geçerli bir miktar girin.', error: true);
    if (!await confirm(context, '@${_username.text.trim()} kullanıcısına ${fmtNumber(amount)} Coin satılacak.', action: 'Sat')) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final r = await guard(context, () => Api.postOnce('/api/dealer/sell', {'username': _username.text.trim(), 'amount': amount}));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      toast(context, 'Satış tamamlandı. Kalan bakiye: ${fmtNumber(r['dealerBalance'])}');
      _amount.clear();
      setState(() => _version++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bayi paneli')),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: () => Api.get('/api/dealer/me'),
        builder: (context, data, reload) {
          final dealer = mapOf(data['dealer']) ?? {};
          final txs = listOf(data['transactions']);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(child: ListTile(leading: const Icon(Icons.storefront), title: Text((dealer['name'] ?? '').toString()), subtitle: Text('Bakiye: ${fmtNumber(dealer['coinBalance'])} Coin'))),
              const SizedBox(height: 12),
              TextField(controller: _username, autocorrect: false, decoration: const InputDecoration(labelText: 'Kullanıcı adı', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Coin miktarı', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              FilledButton(onPressed: _busy ? null : _sell, child: const Text('Coin sat')),
              const Divider(height: 32),
              Text('Son işlemler', style: Theme.of(context).textTheme.titleMedium),
              for (final t in txs) ListTile(dense: true, title: Text('${t['type']} · ${fmtNumber(t['coinAmount'])} Coin'), subtitle: Text((t['username'] != null ? '@${t['username']} · ' : '') + (t['description'] ?? '').toString())),
            ]),
          );
        },
      ),
    );
  }
}
