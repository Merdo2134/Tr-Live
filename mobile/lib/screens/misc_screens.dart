import 'package:flutter/material.dart';
import '../services/api.dart';
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
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cüzdan geçmişi')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        load: () async => listOf((await Api.get('/api/me/wallet'))['transactions']),
        builder: (context, items, reload) => items.isEmpty
            ? const Center(child: Text('Henüz işlem yok.'))
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView(children: [
                  for (final t in items)
                    ListTile(
                      leading: Icon((t['diamondAmount'].toString() != '0') ? Icons.diamond : Icons.monetization_on, color: (t['diamondAmount'].toString() != '0') ? Colors.cyanAccent : Colors.amber),
                      title: Text(_types[t['type']] ?? t['type'].toString()),
                      subtitle: Text('${t['description'] ?? ''}\n${_date(t['createdAt'])}'),
                      isThreeLine: true,
                      trailing: Text(
                        t['diamondAmount'].toString() != '0' ? '+${fmtNumber(t['diamondAmount'])} 💎' : '${fmtNumber(t['coinAmount'])} Coin',
                        style: TextStyle(color: t['coinAmount'].toString().startsWith('-') ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold),
                      ),
                    ),
                ]),
              ),
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

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  int _version = 0;

  static const _typeNames = {'frame': 'Avatar çerçevesi', 'entrance_effect': 'Giriş efekti', 'badge': 'Rozet', 'profile_effect': 'Profil efekti'};

  Future<void> _toggle(Map<String, dynamic> item) async {
    final equipped = item['equipped'] == true;
    final r = await guard<bool>(context, () async {
      await Api.post(equipped ? '/api/inventory/unequip' : '/api/inventory/equip', {'itemId': item['id']});
      return true;
    });
    if (r == true && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Envanter')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_version),
        load: () async => listOf((await Api.get('/api/inventory'))['items']),
        builder: (context, items, reload) => items.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Envanteriniz boş. Öğeler yönetici veya etkinlikler aracılığıyla eklenir.', textAlign: TextAlign.center)))
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView(children: [
                  for (final i in items)
                    ListTile(
                      leading: Api.absoluteUrl(i['assetUrl'] as String?) != null && i['itemType'] == 'frame'
                          ? Image.network(Api.absoluteUrl(i['assetUrl'] as String?)!, width: 40, height: 40, errorBuilder: (_, __, ___) => const Icon(Icons.image))
                          : const Icon(Icons.auto_awesome),
                      title: Text((i['itemName'] ?? '').toString()),
                      subtitle: Text('${_typeNames[i['itemType']] ?? i['itemType']}${i['expiresAt'] != null ? ' · ${_date(i['expiresAt'])} tarihine kadar' : ''}'),
                      trailing: i['equipped'] == true
                          ? FilledButton.tonal(onPressed: () => _toggle(i), child: const Text('Çıkar'))
                          : OutlinedButton(onPressed: () => _toggle(i), child: const Text('Kullan')),
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
