import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/inbox_service.dart';
import '../widgets/anim_asset.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import 'messages_screen.dart';
import 'user_screens.dart';

/// Arkadaşlarım ve bana gelen arkadaşlık istekleri. Yalnızca arkadaşlar mesajlaşabilir.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  int _version = 0;

  void _reload() {
    if (mounted) setState(() => _version++);
    Inbox.refreshBadges();
  }

  Future<void> _respond(String userId, bool accept) async {
    final r = await guard(context, () => Api.post('/api/friends/${accept ? 'accept' : 'decline'}/$userId'));
    if (r != null) {
      if (mounted && accept) toast(context, 'Artık arkadaşsınız.');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Arkadaşlar'), bottom: const TabBar(tabs: [Tab(text: 'Arkadaşlarım'), Tab(text: 'İstekler')])),
        body: TabBarView(children: [
          AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey('f$_version'),
            load: () async => listOf((await Api.get('/api/friends'))['users']),
            builder: (context, users, reload) => users.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Henüz arkadaşın yok. Bir profile girip "Arkadaş ekle" diyebilirsin.', textAlign: TextAlign.center)))
                : RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(children: [
                      for (final u in users)
                        ListTile(
                          leading: UserAvatar(user: u),
                          title: UserName(user: u),
                          subtitle: Text('@${u['username']}'),
                          trailing: IconButton(
                            tooltip: 'Mesaj',
                            icon: const Icon(Icons.chat_bubble_outline, color: Pal.cyan),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: u))),
                          ),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: u['id'] as String))),
                        ),
                    ]),
                  ),
          ),
          AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey('r$_version'),
            load: () async => listOf((await Api.get('/api/friends/requests'))['requests']),
            builder: (context, reqs, reload) => reqs.isEmpty
                ? const Center(child: Text('Bekleyen istek yok.'))
                : RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(children: [
                      for (final r in reqs)
                        ListTile(
                          leading: UserAvatar(user: mapOf(r['user'])),
                          title: UserName(user: mapOf(r['user'])),
                          subtitle: const Text('Arkadaşlık isteği gönderdi'),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: mapOf(r['user'])?['id'] as String))),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.check_circle, color: Colors.greenAccent), onPressed: () => _respond(mapOf(r['user'])?['id'] as String, true)),
                            IconButton(icon: const Icon(Icons.cancel, color: Colors.redAccent), onPressed: () => _respond(mapOf(r['user'])?['id'] as String, false)),
                          ]),
                        ),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Seviye Merkezi: Yayıncı / Kullanıcı seviyesi, exp çubuğu ve ayrıcalıklar tablosu (Figma).
class LevelsScreen extends StatefulWidget {
  const LevelsScreen({super.key});

  @override
  State<LevelsScreen> createState() => _LevelsScreenState();
}

class _LevelsScreenState extends State<LevelsScreen> {
  bool _broadcaster = false; // Figma'da önce Yayıncı, ama kullanıcı seviyesi öntanımlı

  static const _ranges = [
    [1, 19], [20, 29], [30, 39], [40, 49], [50, 59], [60, 69], [70, 79], [80, 89], [90, 99], [100, 119], [120, 139], [140, 149], [150, 160],
  ];
  static const _chipColors = [
    [Color(0xFF16A34A), Color(0xFF22D3EE)], [Color(0xFF2563EB), Color(0xFF22D3EE)], [Color(0xFF7C3AED), Color(0xFFA78BFA)],
    [Color(0xFFE11D48), Color(0xFFFB7185)], [Color(0xFFEA580C), Color(0xFFFBBF24)], [Color(0xFF9333EA), Color(0xFFF472B6)],
  ];

  String? _frame(Map<String, dynamic> p) {
    final items = p['equipped'];
    if (items is! List) return null;
    for (final i in items) {
      if (i is Map && i['itemType'] == 'frame') return Api.absoluteUrl(i['assetUrl'] as String?);
    }
    return null;
  }

  String _fmt(String v) => fmtNumber(v);

  @override
  Widget build(BuildContext context) {
    final rowColor = _broadcaster ? const Color(0xFF05052E) : const Color(0xFF2E0505);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('Seviye Merkezi')),
      body: AsyncBody<Map<String, dynamic>>(
        load: () async {
          final me = mapOf((await Api.get('/api/me'))['user']) ?? {};
          final lv = await Api.get('/api/me/levels');
          return {'me': me, 'lv': lv};
        },
        builder: (context, d, reload) {
          final me = mapOf(d['me']) ?? {};
          final lv = mapOf(d['lv']) ?? {};
          final info = mapOf(_broadcaster ? lv['broadcaster'] : lv['user']) ?? {};
          final level = (info['level'] as num?)?.toInt() ?? 1;
          final exp = BigInt.tryParse('${info['exp']}') ?? BigInt.zero;
          final start = BigInt.tryParse('${info['levelStartExp']}') ?? BigInt.zero;
          final next = BigInt.tryParse('${info['nextLevelExp']}') ?? BigInt.zero;
          final maxed = info['maxed'] == true;
          final span = next - start;
          final progress = maxed || span <= BigInt.zero ? 1.0 : ((exp - start).toDouble() / span.toDouble()).clamp(0.0, 1.0);
          final remaining = maxed ? BigInt.zero : next - exp;
          final frame = _frame(me);
          Widget seg(String label, bool on, VoidCallback onTap) => Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Container(
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: on ? const Color(0xFFFFEB3B) : const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(6)),
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 13)))),
                  ),
                ),
              );
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [seg('Yayıncı Seviyesi', _broadcaster, () => setState(() => _broadcaster = true)), seg('Kullanıcı Seviyesi', !_broadcaster, () => setState(() => _broadcaster = false))]),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1A1A1A), Colors.black])),
              child: Column(children: [
                SizedBox(
                  height: 190,
                  child: Stack(alignment: Alignment.center, children: [
                    UserAvatar(user: me, radius: 56),
                    if (frame != null) IgnorePointer(child: SizedBox(width: 56 * 2 * kFrameScale, height: 56 * 2 * kFrameScale, child: AnimAsset(url: frame, repeat: true, cache: false))),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Text('Lv.$level', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(width: 8),
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Colors.white24, color: Colors.white))),
                  const SizedBox(width: 8),
                  Text('Lv.${maxed ? level : level + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                Text('Mevcut Exp: ${_fmt(exp.toString())}  -  Gerekli Exp: ${_fmt(remaining.toString())}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_broadcaster ? 'Aldığın her elmas yayıncı exp\'i kazandırır.' : 'Gönderdiğin her coin kullanıcı exp\'i kazandırır.', style: const TextStyle(fontSize: 11, color: Pal.textDim)),
                ),
              ]),
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: Text('Ayrıcalıklar', style: TextStyle(color: Color(0xFFFFEB3B), fontSize: 17, fontWeight: FontWeight.w700)))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Table(
                border: TableBorder.all(color: Colors.white24, width: 0.8),
                columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(2.2)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  const TableRow(decoration: BoxDecoration(color: Color(0xFF1C1C1C)), children: [
                    Padding(padding: EdgeInsets.all(12), child: Center(child: Text('Seviye', style: TextStyle(fontWeight: FontWeight.w800)))),
                    Padding(padding: EdgeInsets.all(12), child: Center(child: Text('Etiket', style: TextStyle(fontWeight: FontWeight.w800)))),
                    Padding(padding: EdgeInsets.all(12), child: Center(child: Text('Ödül', style: TextStyle(fontWeight: FontWeight.w800)))),
                  ]),
                  for (var i = 0; i < _ranges.length; i++)
                    TableRow(
                      decoration: BoxDecoration(color: level >= _ranges[i][0] && level <= _ranges[i][1] ? rowColor.withValues(alpha: 1) : rowColor.withValues(alpha: 0.75)),
                      children: [
                        SizedBox(height: 64, child: Center(child: Text(_ranges[i][0] == _ranges[i][1] ? '${_ranges[i][0]}' : '${_ranges[i][0]}-${_ranges[i][1]}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: level >= _ranges[i][0] && level <= _ranges[i][1] ? const Color(0xFFFFEB3B) : Colors.white)))),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: LinearGradient(colors: _chipColors[i % _chipColors.length])),
                            child: Text('${_ranges[i][1]}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                          ),
                        ),
                        const Center(child: Text('-', style: TextStyle(color: Colors.white70))),
                      ],
                    ),
                ],
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Profildeki gradyanlı "Lv. xx" çubuğu (Figma).
Widget levelBar(String title, dynamic level, IconData icon, List<Color> colors) {
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(left: 2, bottom: 6), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
    Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: colors)),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 28),
        const Spacer(),
        Text('Lv. ${level ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
      ]),
    ),
  ]);
}
