import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/common.dart';

const _rewardCategories = [
  ['frame', 'Çerçeve'],
  ['badge', 'Rozet'],
  ['vehicle', 'Araç'],
  ['entrance_effect', 'Giriş efekti'],
  ['chat_bubble', 'Sohbet balonu'],
  ['mic_wave', 'Mikrofon dalgası'],
  ['mini_card', 'Profil kartı'],
  ['room_card', 'Oda kartı'],
];

/// Yönetim → Haftalık etkinlikler: her etkinliği aç/kapat, Yıldız hediyelerini seç, ilk 3'ün ödüllerini ve kuralları ayarla.
/// Hafta bitince (Pazartesi 00:00) ödüller kendiliğinden verilir.
class AdminWeeklyEventsPage extends StatefulWidget {
  const AdminWeeklyEventsPage({super.key});

  @override
  State<AdminWeeklyEventsPage> createState() => _AdminWeeklyEventsPageState();
}

class _AdminWeeklyEventsPageState extends State<AdminWeeklyEventsPage> {
  int _v = 0;

  Future<void> _put(String kind, Map<String, dynamic> body, {String done = 'Kaydedildi.'}) async {
    final r = await guard(context, () => Api.put('/api/admin/weekly-events/$kind', body));
    if (r == null || !mounted) return;
    toast(context, done);
    setState(() => _v++);
  }

  Future<void> _pickGift(Map<String, dynamic> e) async {
    final gifts = await guard(context, () async => listOf((await Api.get('/api/admin/catalog'))['gifts']).where((g) => g['isActive'] == true).toList());
    if (gifts == null || !mounted) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * 0.7,
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.8),
          itemCount: gifts.length,
          itemBuilder: (_, i) {
            final g = gifts[i];
            final u = Api.absoluteUrl(g['iconUrl'] as String?);
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(c, g),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Expanded(child: u == null ? const Icon(Icons.card_giftcard) : NetImg(u, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard))),
                  Text((g['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  Text('${fmtNumber(g['coinPrice'])} 🪙', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                ]),
              ),
            );
          },
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _put(e['kind'].toString(), {'giftId': picked['id']}, done: 'Yıldız hediyesi: ${picked['name']}');
  }

  Future<void> _editRules(Map<String, dynamic> e) async {
    final rules = (e['rules'] ?? '').toString();
    final ctl = TextEditingController(text: rules.trim().isEmpty ? (e['defaultRules'] ?? '').toString() : rules);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kurallar (her satır bir madde)'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(controller: ctl, maxLines: 10, minLines: 5, maxLength: 3000, decoration: const InputDecoration(border: OutlineInputBorder())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      ),
    );
    final text = ctl.text;
    ctl.dispose();
    if (ok != true || !mounted) return;
    await _put(e['kind'].toString(), {'rules': text});
  }

  /// Ödül ekleme: Coin, WIP üyeliği ya da öğe (çerçeve, rozet, araç…).
  Future<Map<String, dynamic>?> _newReward() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.monetization_on, color: Colors.amber), title: const Text('Coin'), onTap: () => Navigator.pop(c, 'coins')),
          ListTile(leading: const Icon(Icons.workspace_premium, color: Colors.lightBlueAccent), title: const Text('WIP üyeliği'), onTap: () => Navigator.pop(c, 'wip')),
          ListTile(leading: const Icon(Icons.filter_frames, color: Colors.pinkAccent), title: const Text('Öğe (çerçeve, rozet, araç, balon…)'), onTap: () => Navigator.pop(c, 'item')),
        ]),
      ),
    );
    if (type == null || !mounted) return null;
    if (type == 'coins') {
      final v = await askText(context, 'Coin miktarı', keyboard: TextInputType.number);
      final n = int.tryParse((v ?? '').trim());
      if (v == null) return null;
      if (n == null || n < 1) {
        if (mounted) toast(context, 'Geçerli bir miktar girin.', error: true);
        return null;
      }
      return {'type': 'coins', 'amount': n};
    }
    if (type == 'wip') {
      final f = await formDialog(context, 'WIP üyeliği', ['Kademe (1-10)', 'Gün'], initial: {'Kademe (1-10)': '1', 'Gün': '7'});
      if (f == null) return null;
      final level = int.tryParse(f['Kademe (1-10)']?.trim() ?? '');
      final days = int.tryParse(f['Gün']?.trim() ?? '');
      if (level == null || level < 1 || level > 10 || days == null || days < 1) {
        if (mounted) toast(context, 'Kademe 1-10, gün 1 ve üzeri olmalı.', error: true);
        return null;
      }
      return {'type': 'wip', 'level': level, 'days': days};
    }
    if (!mounted) return null;
    final cat = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final k in _rewardCategories) ListTile(title: Text(k[1]), onTap: () => Navigator.pop(c, k[0])),
        ]),
      ),
    );
    if (cat == null || !mounted) return null;
    final items = await guard(context, () async => listOf((await Api.get('/api/admin/grantables', query: {'category': cat}))['items']));
    if (items == null || !mounted) return null;
    if (items.isEmpty) {
      toast(context, 'Bu türde öğe yok. Önce katalogdan ekleyin.', error: true);
      return null;
    }
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * 0.6,
        child: ListView(children: [
          for (final it in items)
            ListTile(
              leading: SizedBox(
                width: 40,
                height: 40,
                child: Api.absoluteUrl(it['imageUrl'] as String?) == null
                    ? const Icon(Icons.auto_awesome)
                    : NetImg(Api.absoluteUrl(it['imageUrl'] as String?)!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image)),
              ),
              title: Text((it['name'] ?? '').toString()),
              onTap: () => Navigator.pop(c, it),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return null;
    final d = await askText(context, 'Kaç gün?', keyboard: TextInputType.number, initial: '7');
    final days = int.tryParse((d ?? '').trim());
    if (d == null) return null;
    if (days == null || days < 1) {
      if (mounted) toast(context, 'Gün 1 ve üzeri olmalı.', error: true);
      return null;
    }
    return {'type': 'item', 'category': cat, 'itemKey': picked['key'], 'days': days};
  }

  Map<String, dynamic> _rawRewards(Map<String, dynamic> e) {
    final raw = mapOf(e['rewards']) ?? {};
    return {for (final k in ['1', '2', '3']) k: listOf(raw[k])};
  }

  Future<void> _addReward(Map<String, dynamic> e, String rank) async {
    final r = await _newReward();
    if (r == null || !mounted) return;
    final all = _rawRewards(e);
    all[rank] = [...listOf(all[rank]), r];
    await _put(e['kind'].toString(), {'rewards': all}, done: 'Ödül eklendi.');
  }

  Future<void> _removeReward(Map<String, dynamic> e, String rank, int index) async {
    final all = _rawRewards(e);
    final list = [...listOf(all[rank])];
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    all[rank] = list;
    await _put(e['kind'].toString(), {'rewards': all}, done: 'Ödül kaldırıldı.');
  }

  String _title(Map<String, dynamic> e) {
    final kind = e['kind'].toString();
    if (kind.startsWith('star')) return 'Haftalık Yıldız ${kind.substring(4)}';
    return (e['title'] ?? kind).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Haftalık etkinlikler')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_v),
        load: () async => listOf((await Api.get('/api/admin/weekly-events'))['events']),
        builder: (context, events, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            const Text(
              'Hafta Pazartesi 00:00\'da başlar (Türkiye saati). Hafta bitince her etkinliğin ilk 3\'üne buradaki ödüller '
              'otomatik verilir ve "Etkinlik" duyurusu yayınlanır. Yıldız etkinliği için hediye seçilmezse o yıldız görünmez.',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 10),
            for (final e in events) _card(e),
          ]),
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> e) {
    final kind = e['kind'].toString();
    final enabled = e['enabled'] == true;
    final gift = mapOf(e['gift']);
    final view = mapOf(e['rewardsView']) ?? {};
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(_title(e), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            Switch(value: enabled, onChanged: (v) => _put(kind, {'enabled': v}, done: v ? 'Etkinlik açıldı.' : 'Etkinlik kapatıldı.')),
          ]),
          if (e['isStar'] == true)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: SizedBox(
                width: 36,
                height: 36,
                child: Api.absoluteUrl(gift?['iconUrl'] as String?) == null
                    ? const Icon(Icons.card_giftcard)
                    : NetImg(Api.absoluteUrl(gift?['iconUrl'] as String?)!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard)),
              ),
              title: Text(gift == null ? 'Hediye seçilmedi' : 'Hediye: ${gift['name']}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (gift != null) IconButton(tooltip: 'Hediyeyi kaldır', icon: const Icon(Icons.close), onPressed: () => _put(kind, {'giftId': null}, done: 'Hediye kaldırıldı.')),
                FilledButton.tonal(onPressed: () => _pickGift(e), child: Text(gift == null ? 'Seç' : 'Değiştir')),
              ]),
            ),
          for (final rank in ['1', '2', '3']) ...[
            const SizedBox(height: 6),
            Row(children: [
              Text('${const {'1': '🥇', '2': '🥈', '3': '🥉'}[rank]} $rank. sıra', style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(onPressed: () => _addReward(e, rank), icon: const Icon(Icons.add, size: 18), label: const Text('Ödül ekle')),
            ]),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < listOf(view[rank]).length; i++)
                InputChip(
                  label: Text((listOf(view[rank])[i]['label'] ?? '').toString(), style: const TextStyle(fontSize: 12)),
                  onDeleted: () => _removeReward(e, rank, i),
                ),
              if (listOf(view[rank]).isEmpty) const Text('Ödül yok', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ],
          const SizedBox(height: 6),
          OutlinedButton.icon(onPressed: () => _editRules(e), icon: const Icon(Icons.rule), label: const Text('Kuralları düzenle')),
        ]),
      ),
    );
  }
}
