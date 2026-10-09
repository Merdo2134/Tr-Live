import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/anim_asset.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';

/// Kategoriler: [anahtar, Mağaza adı, Görünüm adı]
const _cats = [
  ['frame', 'Çerçeve', 'Çerçeve'],
  ['chat_bubble', 'Sohbet Balonu', 'Sohbet Balonu'],
  ['entrance_effect', 'Özel Giriş', 'Giriş Etkisi'],
  ['mini_card', 'Mini Kart', 'Mini Kart'],
  ['mic_wave', 'Mikrofon Dalgası', 'Mikrofon Dalgası'],
  ['vehicle', 'Araç', 'Araç'],
];

String _fmtDate(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

/// Kategori seçici (üst satır): yatay kaydırmalı hap düğmeler.
Widget _catBar(List<List<String>> cats, String sel, int labelIndex, ValueChanged<String> onSel) {
  return SizedBox(
    height: 46,
    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), children: [
      for (final c in cats)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onSel(c[0]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: sel == c[0] ? Pal.cyan : Colors.transparent, borderRadius: BorderRadius.circular(18)),
              child: Text(c[labelIndex], style: TextStyle(fontWeight: FontWeight.w700, color: sel == c[0] ? const Color(0xFF00212A) : Pal.textDim)),
            ),
          ),
        ),
    ]),
  );
}

/// Ürün görseli: çerçeve/efekt animasyonlu olabilir.
Widget _itemImage(String? url, String category) {
  final u = Api.absoluteUrl(url);
  if (u == null) return const Icon(Icons.image_not_supported_outlined, color: Colors.white38, size: 40);
  return AnimAsset(url: u, repeat: true, cache: false);
}

/// Önizleme: çerçeve ise kendi avatarının üstünde göster.
void _preview(BuildContext context, String category, String name, String? url) {
  final u = Api.absoluteUrl(url);
  showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      backgroundColor: const Color(0xFF1B1B1F),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          SizedBox(
            width: 260,
            height: 260,
            child: category == 'frame'
                ? Stack(alignment: Alignment.center, children: [
                    UserAvatar(user: Session.me.value, radius: 60),
                    if (u != null) AnimAsset(url: u, repeat: true, cache: false),
                  ])
                : (u == null ? const SizedBox.shrink() : AnimAsset(url: u, repeat: true, cache: false)),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat')),
        ]),
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  final String category;
  final String? url;
  final String name;
  final String topLeft;
  final Widget middle;
  final Widget buttons;
  const _Tile({required this.category, required this.url, required this.name, required this.topLeft, required this.middle, required this.buttons});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.outline)),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.schedule, size: 11, color: Pal.textDim),
          const SizedBox(width: 2),
          Expanded(child: Text(topLeft, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Pal.textDim))),
          InkWell(onTap: () => _preview(context, category, name, url), child: const Text('Önizleme', style: TextStyle(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.w700))),
        ]),
        Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _itemImage(url, category))),
        middle,
        const SizedBox(height: 6),
        buttons,
      ]),
    );
  }
}

Widget _greenBtn(String label, VoidCallback? onTap, {Color color = const Color(0xFF12C84A), bool outline = false}) => Expanded(
      child: SizedBox(
        height: 26,
        child: outline
            ? OutlinedButton(style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: color, side: BorderSide(color: color), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))), onPressed: onTap, child: FittedBox(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))))
            : FilledButton(style: FilledButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: color, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))), onPressed: onTap, child: FittedBox(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))),
      ),
    );

SliverGridDelegate get _gridDelegate => const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.66);

/// Mağaza (AVM): kategori çubuğu, Coins Mağazası, Satın al / Gönder.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  String _cat = 'frame';
  bool _points = false;
  int _version = 0;

  Future<void> _buy(Map<String, dynamic> item, {String? toUserId, String? toName}) async {
    final price = fmtNumber(item['priceCoins']);
    final who = toName == null ? '' : '\n$toName adlı arkadaşına hediye edilecek.';
    if (!await confirm(context, '"${item['name']}" ${item['durationDays']} gün için $price coin karşılığında alınsın mı?$who', action: toUserId == null ? 'Satın al' : 'Gönder')) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.post('/api/store/buy', {'itemId': item['id'], if (toUserId != null) 'toUserId': toUserId}));
    if (r == null || !mounted) return;
    toast(context, toUserId == null ? 'Satın alındı. Görünüm sayfasından etkinleştirebilirsin.' : 'Hediye gönderildi.');
    await Session.refresh();
    if (mounted) setState(() => _version++);
  }

  Future<void> _send(Map<String, dynamic> item) async {
    final friends = await guard(context, () => Api.get('/api/friends'));
    if (friends == null || !mounted) return;
    final list = listOf(friends['users']);
    if (list.isEmpty) return toast(context, 'Önce arkadaş eklemelisin.', error: true);
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(children: [
          const Padding(padding: EdgeInsets.all(8), child: Text('Kime gönderilsin?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Expanded(
            child: ListView(children: [
              for (final u in list) ListTile(leading: UserAvatar(user: u), title: UserName(user: u), onTap: () => Navigator.pop(c, u)),
            ]),
          ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    await _buy(item, toUserId: picked['id'] as String, toName: (picked['displayName'] ?? '').toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mağaza'),
        actions: [
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: Session.me,
            builder: (_, __, ___) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.monetization_on, color: Colors.amber, size: 18), const SizedBox(width: 4), Text(fmtNumber(Session.coins), style: const TextStyle(fontWeight: FontWeight.w800))])),
            ),
          ),
        ],
      ),
      body: Column(children: [
        _catBar([for (final c in _cats) [c[0], c[1]]], _cat, 1, (v) => setState(() => _cat = v)),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            _toggle('Coins Mağazası', !_points, () => setState(() => _points = false)),
            const SizedBox(width: 10),
            _toggle('Puan Mağazası', _points, () => setState(() => _points = true)),
          ]),
        ),
        Expanded(
          child: _points
              ? const Center(child: Text('Puan Mağazası çok yakında.', style: TextStyle(color: Pal.textDim)))
              : AsyncBody<List<Map<String, dynamic>>>(
                  key: ValueKey('$_cat-$_version'),
                  load: () async => listOf((await Api.get('/api/store/items', query: {'category': _cat}))['items']),
                  builder: (context, items, reload) => items.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Bu kategoride henüz ürün yok.', style: TextStyle(color: Pal.textDim))))
                      : RefreshIndicator(
                          onRefresh: reload,
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            gridDelegate: _gridDelegate,
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final it = items[i];
                              return _Tile(
                                category: _cat,
                                url: it['imageUrl'] as String?,
                                name: (it['name'] ?? '').toString(),
                                topLeft: '${it['durationDays']} gün',
                                middle: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  const Icon(Icons.monetization_on, color: Colors.amber, size: 15),
                                  const SizedBox(width: 3),
                                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(fmtNumber(it['priceCoins']), style: const TextStyle(fontWeight: FontWeight.w800)))),
                                ]),
                                buttons: Row(children: [_greenBtn('Satın al', () => _buy(it)), const SizedBox(width: 4), _greenBtn('Gönder', () => _send(it), outline: true)]),
                              );
                            },
                          ),
                        ),
                ),
        ),
      ]),
    );
  }

  Widget _toggle(String label, bool on, VoidCallback onTap) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: on ? const LinearGradient(colors: [Color(0xFF00A8FF), Color(0xFF7FE0FF)]) : null, color: on ? null : Colors.white12),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: on ? Colors.white : Colors.white38)),
          ),
        ),
      );
}

/// Görünüm (eski envanter): satın alınan / hediye edilen ürünler; Etkinleştir / Kaldır.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  String _cat = 'frame';
  int _version = 0;

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
    final order = ['vehicle', 'frame', 'chat_bubble', 'entrance_effect', 'mic_wave', 'mini_card'];
    final cats = [for (final k in order) _cats.firstWhere((c) => c[0] == k)];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Görünüm'),
        actions: [IconButton(tooltip: 'Mağaza', icon: const Icon(Icons.storefront), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreScreen())))],
      ),
      body: Column(children: [
        _catBar([for (final c in cats) [c[0], c[2]]], _cat, 1, (v) => setState(() => _cat = v)),
        Expanded(
          child: AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey(_version),
            load: () async => listOf((await Api.get('/api/inventory'))['items']),
            builder: (context, all, reload) {
              final items = all.where((i) => i['itemType'] == _cat).toList();
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Bu kategoride ürünün yok.', style: TextStyle(color: Pal.textDim)),
                      const SizedBox(height: 10),
                      FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreScreen())), icon: const Icon(Icons.storefront), label: const Text('Mağazaya git')),
                    ]),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: reload,
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  gridDelegate: _gridDelegate,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[i];
                    final on = it['equipped'] == true;
                    return Stack(children: [
                      Positioned.fill(
                        child: _Tile(
                          category: _cat,
                          url: it['assetUrl'] as String?,
                          name: (it['itemName'] ?? '').toString(),
                          topLeft: it['expiresAt'] == null ? 'Süresiz' : 'Son tarih',
                          middle: Text(it['expiresAt'] == null ? '' : _fmtDate(it['expiresAt']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: Pal.textDim)),
                          buttons: Row(children: [_greenBtn(on ? 'Kaldır' : 'Etkinleştir', () => _toggle(it), color: on ? Colors.black : const Color(0xFF12C84A))]),
                        ),
                      ),
                      if (on) const Positioned(left: 6, top: 22, child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 18)),
                    ]);
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
