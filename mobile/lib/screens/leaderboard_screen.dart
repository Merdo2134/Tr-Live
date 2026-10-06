import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/crown_icon.dart';
import 'user_screens.dart';

/// TRLive sıralamaları: Günlük / Haftalık / Aylık × Yayıncı, Destekçi, Ajans, Aile, Oda, CP.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _type = 'receivers';
  String _period = 'daily';

  static const _types = [
    ('receivers', 'Yayıncı', Icons.mic),
    ('senders', 'Destekçi', Icons.volunteer_activism),
    ('agencies', 'Ajans', Icons.business),
    ('families', 'Aile', Icons.groups),
    ('rooms', 'Oda', Icons.meeting_room),
    ('cp', 'CP', Icons.favorite),
  ];
  static const _periods = {'daily': 'Günlük', 'weekly': 'Haftalık', 'monthly': 'Aylık'};

  static const _gold = [Color(0xFFFFC43D), Color(0xFFD7DEE6), Color(0xFFCD8B5A)];
  Color _medal(int rank) => rank <= 3 ? _gold[rank - 1] : Pal.surfaceHi;

  String _unit() => _type == 'receivers' ? '💎' : 'Coin';

  Widget _row(Map<String, dynamic> e) {
    final rank = (e['rank'] as num).toInt();
    Widget title;
    Widget? subtitle;
    Widget leading;
    VoidCallback? tap;
    switch (_type) {
      case 'families':
        final f = mapOf(e['family']);
        title = Text((f?['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700));
        subtitle = Text('Seviye ${f?['level']}');
        leading = const CircleAvatar(child: Icon(Icons.groups));
      case 'agencies':
        final a = mapOf(e['agency']);
        title = Text((a?['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700));
        leading = CircleAvatar(backgroundImage: a?['logoUrl'] == null ? null : NetworkImage(Api.absoluteUrl(a!['logoUrl'] as String)!), child: a?['logoUrl'] == null ? const Icon(Icons.business) : null);
      case 'rooms':
        final r = mapOf(e['room']);
        title = Text((r?['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700));
        subtitle = Text('${r?['memberCount'] ?? 0} kişi · ${r?['roomType'] == 'video' ? 'Görüntülü' : 'Sesli'}');
        leading = CircleAvatar(child: Icon(r?['roomType'] == 'video' ? Icons.videocam : Icons.mic));
      case 'cp':
        final u = mapOf(e['user']);
        final p = mapOf(e['partner']);
        title = Row(children: [
          Flexible(child: UserName(user: u, style: const TextStyle(fontWeight: FontWeight.w700))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.favorite, size: 16, color: Pal.pink)),
          Flexible(child: UserName(user: p, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]);
        leading = Stack(children: [
          UserAvatar(user: u, radius: 18),
          Positioned(left: 20, child: UserAvatar(user: p, radius: 18)),
        ]);
        leading = SizedBox(width: 56, height: 36, child: leading);
      default:
        final u = mapOf(e['user']);
        title = UserName(user: u, style: const TextStyle(fontWeight: FontWeight.w700));
        leading = UserAvatar(user: u, radius: 20);
        tap = () {
          final id = u?['id'];
          if (id is String) Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)));
        };
    }
    return ListTile(
      onTap: tap,
      leading: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 30,
          child: rank <= 3
              ? Icon(Icons.workspace_premium, color: _medal(rank), size: 28)
              : Text('$rank', textAlign: TextAlign.center, style: const TextStyle(color: Pal.textDim, fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        const SizedBox(width: 8),
        leading,
      ]),
      title: title,
      subtitle: subtitle,
      trailing: Text('${fmtNumber(e['total'])} ${_unit()}', style: TextStyle(fontWeight: FontWeight.w800, color: rank <= 3 ? _medal(rank) : Pal.text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: const [CrownIcon(size: 30), SizedBox(width: 8), Text('TRLive', style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w800, letterSpacing: 1))]),
      ),
      body: Column(children: [
        // Günlük / Haftalık / Aylık
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: Pal.outline)),
            child: Row(children: [
              for (final e in _periods.entries)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _period = e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(color: _period == e.key ? Pal.cyan : Colors.transparent, borderRadius: BorderRadius.circular(20)),
                      child: Center(child: Text(e.value, style: TextStyle(fontWeight: FontWeight.w800, color: _period == e.key ? const Color(0xFF00212A) : Pal.textDim))),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        // Yayıncı, Destekçi, Ajans, Aile, Oda, CP
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final t in _types)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(t.$3, size: 18, color: _type == t.$1 ? Pal.amber : Pal.textDim),
                  label: Text(t.$2, style: TextStyle(fontWeight: FontWeight.w700, color: _type == t.$1 ? Pal.amber : Pal.textDim)),
                  selected: _type == t.$1,
                  selectedColor: Pal.surfaceHi,
                  side: BorderSide(color: _type == t.$1 ? Pal.amber : Pal.outline),
                  onSelected: (_) => setState(() => _type = t.$1),
                ),
              ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(alignment: Alignment.centerLeft, child: Text('Kendinize gönderilen hediyeler sıralamaya dahil edilmez.', style: TextStyle(color: Pal.textDim, fontSize: 12))),
        ),
        Expanded(
          child: AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey('$_type$_period'),
            load: () async => listOf((await Api.get('/api/leaderboards', query: {'type': _type, 'period': _period}))['entries']),
            builder: (context, entries, reload) => entries.isEmpty
                ? const Center(child: Text('Bu dönemde henüz kayıt yok.', style: TextStyle(color: Pal.textDim)))
                : RefreshIndicator(onRefresh: reload, child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [for (final e in entries) _row(e)])),
          ),
        ),
      ]),
    );
  }
}
