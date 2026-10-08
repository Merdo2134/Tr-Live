import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import 'common.dart';

/// Şanslı çanta kademeleri (sunucudaki ayarla aynı; sunucu doğrular).
const _tiers = [
  ('n3', false, 3000, 10),
  ('n6', false, 6000, 20),
  ('n9', false, 9000, 30),
  ('s30', true, 30000, 50),
  ('s60', true, 60000, 50),
  ('s90', true, 90000, 50),
];

/// Çanta gönderme penceresi.
Future<void> showBagSend(BuildContext context, String roomId) async {
  final noteCtl = TextEditingController();
  var picked = 'n3';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) {
        final t = _tiers.firstWhere((x) => x.$1 == picked);
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(c).bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Şanslı Çanta', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Coin odadakilere rastgele paylaştırılır. Dağıtılmayan kısım sana iade edilir.', style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final x in _tiers)
                  ChoiceChip(
                    selected: picked == x.$1,
                    onSelected: (_) => setS(() => picked = x.$1),
                    label: Text('${x.$2 ? '⭐ Süper ' : ''}${fmtNumber(x.$3)} 🪙 • ${x.$4} kişi'),
                  ),
              ]),
              if (t.$2) ...[
                const SizedBox(height: 10),
                const Text('Süper çanta: tüm odalarda duyurulur, 60 sn açılır; açmak isteyenler önce aşağıdaki notu sohbete yazar.', style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                TextField(controller: noteCtl, maxLength: 100, decoration: const InputDecoration(labelText: 'Çanta notu')),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.redeem),
                  label: Text('Gönder (${fmtNumber(t.$3)} Coin)'),
                  onPressed: () async {
                    final r = await guard(c, () => Api.post('/api/rooms/$roomId/lucky-bags', {'tier': picked, if (t.$2) 'note': noteCtl.text.trim()}));
                    if (r != null && c.mounted) Navigator.pop(c);
                  },
                ),
              ),
            ]),
          ),
        );
      },
    ),
  );
  noteCtl.dispose();
}

/// Çantayı açma penceresi (geri sayım, not, aç).
Future<void> showBagClaim(BuildContext context, String roomId, Map<String, dynamic> bag) {
  return showDialog<void>(context: context, builder: (c) => _ClaimDialog(roomId: roomId, bag: bag));
}

class _ClaimDialog extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic> bag;
  const _ClaimDialog({required this.roomId, required this.bag});
  @override
  State<_ClaimDialog> createState() => _ClaimDialogState();
}

class _ClaimDialogState extends State<_ClaimDialog> {
  Timer? _t;
  int _left = 0;
  bool _noteSent = false;
  String? _won;

  Map<String, dynamic> get _b => widget.bag;
  bool get _super => _b['kind'] == 'super';

  @override
  void initState() {
    super.initState();
    _won = _b['mine']?.toString();
    _tick();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final end = DateTime.tryParse((_b['expiresAt'] ?? '').toString())?.toLocal();
    final left = end == null ? 0 : end.difference(DateTime.now()).inSeconds;
    if (mounted) setState(() => _left = left < 0 ? 0 : left);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _sendNote() async {
    final r = await guard(context, () => Api.post('/api/rooms/${widget.roomId}/messages', {'text': (_b['note'] ?? '').toString()}));
    if (r != null && mounted) setState(() => _noteSent = true);
  }

  Future<void> _open() async {
    final r = await guard(context, () => Api.post('/api/lucky-bags/${_b['id']}/claim'));
    if (r != null && mounted) setState(() { _won = r['amount'].toString(); _b['mine'] = _won; });
  }

  @override
  Widget build(BuildContext context) {
    final sender = mapOf(_b['sender']);
    final expired = _left <= 0;
    return AlertDialog(
      title: Text(_super ? '⭐ Süper Şanslı Çanta' : '🧧 Şanslı Çanta'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        UserAvatar(user: sender, radius: 26),
        const SizedBox(height: 6),
        Text('${sender?['displayName'] ?? ''} gönderdi', style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('${fmtNumber(_b['totalCoins'])} Coin • ${_b['claimed']}/${_b['slots']} kişi açtı', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        if (_won != null)
          Text('🎉 ${fmtNumber(_won)} Coin kazandın!', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.amber))
        else if (expired)
          const Text('Süre doldu.', style: TextStyle(color: Colors.redAccent))
        else
          Text('Kalan süre: $_left sn', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (_super && _won == null && !expired) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
            child: Text('Not: "${_b['note']}"', textAlign: TextAlign.center),
          ),
          const SizedBox(height: 6),
          const Text('Çantayı açmak için bu notu sohbete bir kez yaz.', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
        if (_won == null && !expired) ...[
          if (_super && !_noteSent) OutlinedButton(onPressed: _sendNote, child: const Text('Notu gönder')),
          FilledButton(onPressed: (_super && !_noteSent) ? null : _open, child: const Text('Çantayı Aç')),
        ],
      ],
    );
  }
}

/// Günlük görev sayfası.
Future<void> showDailySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => FutureBuilder<Map<String, dynamic>>(
      future: Api.get('/api/me/daily'),
      builder: (c, snap) {
        if (snap.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text(errorText(snap.error!)));
        if (!snap.hasData) return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
        final d = snap.data!;
        final streak = (d['streak'] as num?)?.toInt() ?? 0;
        final target = (d['streakTarget'] as num?)?.toInt() ?? 7;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('Günlük Görevler', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                Text('${fmtNumber(d['xp'])} XP', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (var i = 1; i <= target; i++)
                  Column(children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: i <= streak ? Colors.amber : Colors.white12,
                      child: i == target ? Icon(Icons.card_giftcard, size: 18, color: i <= streak ? Colors.black : Colors.white54) : Text('$i', style: TextStyle(color: i <= streak ? Colors.black : Colors.white54, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 2),
                    Text(i == target ? '${fmtNumber(d['streakCoins'])}🪙' : 'XP', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                  ]),
              ]),
              const SizedBox(height: 4),
              Text('Her gün tüm görevleri bitir; $target gün üst üste yaparsan ${fmtNumber(d['streakCoins'])} Coin kazanırsın. Bir gün aksatırsan seri sıfırlanır.', style: const TextStyle(color: Colors.white60, fontSize: 12)),
              const Divider(height: 22),
              for (final t in listOf(d['tasks']))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(t['done'] == true ? Icons.check_circle : Icons.radio_button_unchecked, color: t['done'] == true ? Colors.greenAccent : Colors.white38),
                  title: Text((t['label'] ?? '').toString()),
                  trailing: Text('${t['count']}/${t['target']}'),
                ),
            ]),
          ),
        );
      },
    ),
  );
}
