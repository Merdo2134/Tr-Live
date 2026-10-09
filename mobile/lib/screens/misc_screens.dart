import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../services/error_log.dart';
import '../widgets/common.dart';
import 'user_screens.dart';

String _date(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  static const _types = {
    'gift_sent': 'Hediye gönderildi',
    'gift_received': 'Hediye alındı',
    'wip_purchase': 'WIP satın alma',
    'dealer_credit': 'Bayi yüklemesi',
    'admin_adjustment': 'Yönetici düzenlemesi',
    'diamond_exchange': 'Elmas bozdurma',
    'lucky_bag_sent': 'Şanslı çanta gönderildi',
    'lucky_bag_received': 'Şanslı çanta kazancı',
    'lucky_bag_refund': 'Şanslı çanta iadesi',
    'daily_bonus': 'Günlük görev ödülü',
    'store_purchase': 'Mağaza alışverişi',
  };

  /// 5 Elmas = 1 Coin.
  static Future<void> exchange(BuildContext context, String diamonds, Future<void> Function() reload) async {
    final have = BigInt.tryParse(diamonds) ?? BigInt.zero;
    final ctl = TextEditingController();
    final amount = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final n = BigInt.tryParse(ctl.text.trim()) ?? BigInt.zero;
          final valid = n >= BigInt.from(5) && n % BigInt.from(5) == BigInt.zero && n <= have;
          return AlertDialog(
            title: const Text('Elmas Bozdur'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Elmasın: ${fmtNumber(diamonds)} 💎   •   Oran: 5 Elmas = 1 Coin'),
              const SizedBox(height: 8),
              TextField(
                controller: ctl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Bozdurulacak elmas (5 ve katları)'),
                onChanged: (_) => setS(() {}),
              ),
              const SizedBox(height: 8),
              Text(valid ? 'Alacağın: ${n ~/ BigInt.from(5)} Coin' : 'Geçerli bir miktar gir.', style: const TextStyle(color: Colors.white70)),
              Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setS(() => ctl.text = (have - have % BigInt.from(5)).toString()), child: const Text('Hepsi'))),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
              FilledButton(onPressed: valid ? () => Navigator.pop(c, n.toString()) : null, child: const Text('Bozdur')),
            ],
          );
        },
      ),
    );
    ctl.dispose();
    if (amount == null || !context.mounted) return;
    final r = await guard(context, () => Api.post('/api/me/diamonds/exchange', {'diamonds': amount}));
    if (r == null || !context.mounted) return;
    toast(context, '${r['exchangedCoins']} Coin hesabına eklendi.');
    await Session.refresh();
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cüzdan')),
      body: AsyncBody<Map<String, dynamic>>(
        load: () async {
          final tx = listOf((await Api.get('/api/me/wallet'))['transactions']);
          final me = mapOf((await Api.get('/api/me'))['user']) ?? {};
          return {'tx': tx, 'coins': me['coins'] ?? '0', 'diamonds': me['diamonds'] ?? '0', 'broadcaster': me['broadcasterStatus'] == 'approved'};
        },
        builder: (context, data, reload) {
          final items = listOf(data['tx']);
          final isBroadcaster = data['broadcaster'] == true;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(children: [
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: Column(children: [const Text('Coin'), Text(fmtNumber(data['coins']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.amber))])),
                      Expanded(child: Column(children: [const Text('Elmas'), Text('${fmtNumber(data['diamonds'])} 💎', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.cyanAccent))])),
                    ]),
                    const SizedBox(height: 10),
                    if (isBroadcaster)
                      const Text('Onaylı yayıncı: elmaslar maaş sistemiyle ödenir, bozdurulamaz.', style: TextStyle(color: Colors.white60, fontSize: 12))
                    else
                      FilledButton.icon(
                        onPressed: () => exchange(context, data['diamonds'].toString(), reload),
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Elmas Bozdur (5 💎 = 1 Coin)'),
                      ),
                  ]),
                ),
              ),
              if (items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Henüz işlem yok.'))),
              for (final t in items)
                ListTile(
                  leading: Icon((t['diamondAmount'].toString() != '0') ? Icons.diamond : Icons.monetization_on, color: (t['diamondAmount'].toString() != '0') ? Colors.cyanAccent : Colors.amber),
                  title: Text(_types[t['type']] ?? t['type'].toString()),
                  subtitle: Text('${t['description'] ?? ''}\n${_date(t['createdAt'])}'),
                  isThreeLine: true,
                  trailing: Text(
                    t['type'] == 'diamond_exchange'
                        ? '${t['coinAmount']} Coin'
                        : (t['diamondAmount'].toString() != '0' ? '+${fmtNumber(t['diamondAmount'])} 💎' : '${fmtNumber(t['coinAmount'])} Coin'),
                    style: TextStyle(color: t['coinAmount'].toString().startsWith('-') ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class VisitorsScreen extends StatelessWidget {
  const VisitorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil ziyaretçileri')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        load: () async => listOf((await Api.get('/api/me/visitors'))['visitors']),
        builder: (context, items, reload) => items.isEmpty
            ? const Center(child: Text('Henüz ziyaretçi yok.'))
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView(children: [
                  for (final v in items)
                    ListTile(
                      leading: UserAvatar(user: mapOf(v['user'])),
                      title: UserName(user: mapOf(v['user'])),
                      subtitle: Text('${v['visitCount']} ziyaret · ${_date(v['lastVisitedAt'])}'),
                      onTap: () {
                        final id = mapOf(v['user'])?['id'];
                        if (id is String) Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)));
                      },
                    ),
                ]),
              ),
      ),
    );
  }
}

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Engellenen kullanıcılar')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_version),
        load: () async => listOf((await Api.get('/api/blocks'))['users']),
        builder: (context, users, reload) => users.isEmpty
            ? const Center(child: Text('Engellediğiniz kimse yok.'))
            : ListView(children: [
                for (final u in users)
                  ListTile(
                    leading: UserAvatar(user: u),
                    title: Text((u['displayName'] ?? '').toString()),
                    subtitle: Text('@${u['username']}'),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final r = await guard<bool>(context, () async {
                          await Api.delete('/api/blocks/${u['id']}');
                          return true;
                        });
                        if (r == true && mounted) setState(() => _version++);
                      },
                      child: const Text('Engeli kaldır'),
                    ),
                  ),
              ]),
      ),
    );
  }
}


/// Yakalanan hataların kaydı: çökme olursa buradan kopyalayıp gönderebilirsiniz.
class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({super.key});

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  List<String> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await ErrorLog.load();
    if (mounted) setState(() {
      _items = l;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hata kaydı'), actions: [
        IconButton(
          tooltip: 'Tümünü kopyala',
          icon: const Icon(Icons.copy),
          onPressed: _items.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: _items.join('\n\n')));
                  toast(context, 'Kopyalandı.');
                },
        ),
        IconButton(
          tooltip: 'Temizle',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            await ErrorLog.clear();
            _load();
          },
        ),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Kayıtlı hata yok.', style: TextStyle(color: Colors.white54)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) => SelectableText(_items[i], style: const TextStyle(fontSize: 12)),
                ),
    );
  }
}
