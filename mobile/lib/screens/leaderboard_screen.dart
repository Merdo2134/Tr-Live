import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/common.dart';
import 'user_screens.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _type = 'senders';
  String _period = 'weekly';

  static const _types = {'senders': 'Hediye gönderenler', 'receivers': 'Hediye alanlar', 'families': 'Aileler'};
  static const _periods = {'daily': 'Günlük', 'weekly': 'Haftalık', 'monthly': 'Aylık', 'all': 'Tümü'};

  Color _medal(int rank) => rank == 1 ? Colors.amber : rank == 2 ? Colors.grey.shade300 : rank == 3 ? Colors.brown.shade300 : Colors.white24;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liderlik tablosu')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, children: [
            for (final e in _types.entries) ChoiceChip(label: Text(e.value), selected: _type == e.key, onSelected: (_) => setState(() => _type = e.key)),
          ]),
        ),
        Wrap(spacing: 8, children: [
          for (final e in _periods.entries) ChoiceChip(label: Text(e.value), selected: _period == e.key, onSelected: (_) => setState(() => _period = e.key)),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Kendinize gönderilen hediyeler sıralamaya dahil edilmez.', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        Expanded(
          child: AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey('$_type$_period'),
            load: () async => listOf((await Api.get('/api/leaderboards', query: {'type': _type, 'period': _period}))['entries']),
            builder: (context, entries, reload) => entries.isEmpty
                ? const Center(child: Text('Bu dönemde henüz kayıt yok.'))
                : RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(children: [
                      for (final e in entries)
                        ListTile(
                          leading: CircleAvatar(backgroundColor: _medal((e['rank'] as num).toInt()), foregroundColor: Colors.black, child: Text('${e['rank']}')),
                          title: _type == 'families' ? Text((mapOf(e['family'])?['name'] ?? '').toString()) : UserName(user: mapOf(e['user'])),
                          subtitle: _type == 'families' ? Text('Seviye ${mapOf(e['family'])?['level']}') : null,
                          trailing: Text('${fmtNumber(e['total'])} ${_type == 'receivers' ? '💎' : 'Coin'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          onTap: _type == 'families'
                              ? null
                              : () {
                                  final id = mapOf(e['user'])?['id'];
                                  if (id is String) Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)));
                                },
                        ),
                    ]),
                  ),
          ),
        ),
      ]),
    );
  }
}
