import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/common.dart';

/// Oda sahibi: PK için rakip oda ve süre seçer, davet gönderir.
Future<void> showPkChallengeSheet(BuildContext context, {required String roomId}) async {
  var seconds = 300;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Text('PK süresi'),
              const Spacer(),
              DropdownButton<int>(
                value: seconds,
                items: [for (final s in const [60, 180, 300, 600, 900, 1800]) DropdownMenuItem(value: s, child: Text('${s ~/ 60} dk'))],
                onChanged: (v) => setS(() => seconds = v ?? seconds),
              ),
            ]),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerLeft, child: Text('Meydan okunacak oda', style: TextStyle(fontWeight: FontWeight.bold)))),
          Expanded(
            child: AsyncBody<List<Map<String, dynamic>>>(
              load: () async => listOf((await Api.get('/api/pk/rooms'))['rooms']),
              builder: (c2, rooms, reload) => rooms.isEmpty
                  ? const Center(child: Text('Uygun oda yok.'))
                  : ListView(children: [
                      for (final r in rooms)
                        ListTile(
                          leading: const Icon(Icons.sports_mma),
                          title: Text(r['name'].toString()),
                          subtitle: Text('${r['ownerName']} · ${r['memberCount']} kişi'),
                          trailing: FilledButton.tonal(
                            onPressed: () async {
                              final res = await guard(context, () => Api.post('/api/pk/challenge', {'roomId': roomId, 'targetRoomId': r['id'], 'durationSeconds': seconds}));
                              if (res != null && c.mounted) {
                                Navigator.pop(c);
                                toast(context, 'PK daveti gönderildi.');
                              }
                            },
                            child: const Text('Davet et'),
                          ),
                        ),
                    ]),
            ),
          ),
        ]),
      ),
    ),
  );
}

/// Gelen PK davetini kabul/ret iletişim kutusu.
Future<void> showPkInviteDialog(BuildContext context, Map<String, dynamic> pk) async {
  final a = mapOf(pk['a']) ?? {};
  final host = mapOf(a['host']);
  final accept = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('PK daveti'),
      content: Text('${host?['displayName'] ?? 'Bir oda sahibi'} ("${a['roomName']}") sizi ${((pk['durationSeconds'] as num?) ?? 0) ~/ 60} dakikalık PK\'ya davet etti.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Reddet')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kabul et')),
      ],
    ),
  );
  if (accept == null || !context.mounted) return;
  await guard(context, () => Api.post('/api/pk/${pk['id']}/respond', {'accept': accept}));
}
