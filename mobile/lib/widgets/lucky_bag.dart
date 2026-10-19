import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import 'common.dart';
import 'fig.dart';
import 'level_badge.dart';

/// Şanslı çanta kademeleri (sunucudaki ayarla aynı; sunucu doğrular).
const _tiers = [
  ('n3', false, 3000, 10),
  ('n6', false, 6000, 20),
  ('n9', false, 9000, 30),
  ('s30', true, 30000, 50),
  ('s60', true, 60000, 50),
  ('s90', true, 90000, 50),
];

/// Figma'daki sarı düğme (Tamam / Gönder).
Widget _yellowButton(String text, VoidCallback? onTap, {double height = 44, Widget? child}) => GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFBD9), Color(0xFFFFE97A)]),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: child ?? Text(text, style: const TextStyle(color: Color(0xFFE5257E), fontWeight: FontWeight.w800, fontSize: 16)),
      ),
    );

/// Şanslı çanta kuralları (Figma metni).
void _bagRules(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 30),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 1.4),
          image: DecorationImage(image: Fig.provider('bag_card'), fit: BoxFit.cover, onError: (_, __) {}),
          color: const Color(0xFFE8258A),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Şanslı çanta kuralları', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 14),
          const Text(
            '1- Bir şanslı çanta gönderdiğinizde, seçtiğiniz miktarda Coin bakiyenizden harcanır. Şanslı çanta atıldığında '
            'oda içerisindeki kullanıcılar şanslı çantadan Coin alır.\n\n'
            '2- Şanslı çantayı açtığınızda rastgele miktarda Coin alırsınız.\n\n'
            '3- Süresi dolunca açılmamış Coinler gönderen kullanıcıya iade edilir.\n\n'
            '4- Şanslı çanta göndermek EXP değerinize etki etmez.\n\n'
            '5- Herhangi bir reklam içeriği yasaktır, aksi taktirde sonsuza dek yasaklanırsınız!',
            style: TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 18),
          _yellowButton('Tamam', () => Navigator.pop(c), height: 40),
        ]),
      ),
    ),
  );
}

/// Çanta gönderme penceresi (Figma "Şanslı çanta gönder"): pembe perdeli zemin, Şanslı / Süper sekmesi,
/// kırmızı zarflar (seçilende parıltı), Coin ve kişi sayısı, sarı Gönder düğmesi.
Future<void> showBagSend(BuildContext context, String roomId) async {
  final noteCtl = TextEditingController();
  var picked = 'n3';
  var slots = 50; // süper çantada kişi sayısı
  var sending = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) {
        final t = _tiers.firstWhere((x) => x.$1 == picked);
        final isSuper = t.$2;
        final list = _tiers.where((x) => x.$2 == isSuper).toList();

        Widget tab(String label, bool sup) {
          final sel = isSuper == sup;
          return Expanded(
            child: GestureDetector(
              onTap: () => setS(() => picked = sup ? 's30' : 'n3'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: sel ? Colors.white : Colors.white24, borderRadius: BorderRadius.circular(17)),
                child: Text(label, style: TextStyle(color: sel ? const Color(0xFFE5257E) : Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          );
        }

        Widget card((String, bool, int, int) x) {
          final sel = picked == x.$1;
          return GestureDetector(
            onTap: () => setS(() => picked = x.$1),
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              if (sel) const Positioned(left: -14, right: -14, top: 14, bottom: 14, child: IgnorePointer(child: Fig('bag_mid', fit: BoxFit.fill))),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: sel ? Colors.white.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.10),
                  border: Border.all(color: sel ? const Color(0xFFFFE97A) : Colors.white30, width: sel ? 2 : 1),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Fig('bag_icon', width: 46, height: 60),
                  const SizedBox(height: 6),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Fig('bag_coin', width: 16, height: 16),
                    const SizedBox(width: 3),
                    Text(fmtNumber(x.$3), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
                  ]),
                  const SizedBox(height: 2),
                  Text(x.$2 ? '$slots kişi' : '${x.$4} kişi', style: const TextStyle(fontSize: 11.5, color: Color(0xFFFFF3B0), fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          );
        }

        return Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.viewInsetsOf(c).bottom + 14),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            color: const Color(0xFFE8258A),
            image: DecorationImage(image: Fig.provider('bag_card'), fit: BoxFit.cover, alignment: Alignment.topCenter, onError: (_, __) {}),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.circular(2))),
                SizedBox(
                  height: 44,
                  child: Stack(alignment: Alignment.center, children: [
                    Text(isSuper ? 'Süper Şanslı Çanta' : 'Şanslı Çanta', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                    Positioned(
                      right: 0,
                      child: IconButton(tooltip: 'Kurallar', onPressed: () => _bagRules(c), icon: const Icon(Icons.help_outline, color: Colors.white)),
                    ),
                  ]),
                ),
                Row(children: [tab('Şanslı Çanta', false), const SizedBox(width: 10), tab('Süper Şanslı Çanta', true)]),
                const SizedBox(height: 18),
                Row(children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: card(list[i])),
                  ],
                ]),
                if (isSuper) ...[
                  const SizedBox(height: 16),
                  const Align(alignment: Alignment.centerLeft, child: Text('Kaç kişi açabilsin?', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (final n in const [50, 100, 150, 200])
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setS(() => slots = n),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: slots == n ? Colors.white : Colors.white24,
                            ),
                            child: Text('$n', style: TextStyle(color: slots == n ? const Color(0xFFE5257E) : Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtl,
                    maxLength: 100,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Çanta notu (açmak isteyenler sohbete yazar)',
                      hintStyle: const TextStyle(color: Colors.white70, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white24,
                      isDense: true,
                      counterStyle: const TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const Text('Süper çanta tüm odalarda duyurulur; geri sayım bitince açılır.', style: TextStyle(color: Color(0xFFFFF3B0), fontSize: 12)),
                ],
                const SizedBox(height: 18),
                _yellowButton(
                  '',
                  sending
                      ? null
                      : () async {
                          setS(() => sending = true);
                          final r = await guard(c, () => Api.postOnce('/api/rooms/$roomId/lucky-bags', {'tier': picked, if (isSuper) 'note': noteCtl.text.trim(), if (isSuper) 'slots': slots}));
                          if (!c.mounted) return;
                          setS(() => sending = false);
                          if (r != null) Navigator.pop(c);
                        },
                  height: 48,
                  child: sending
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFE5257E)))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Gönder  ', style: TextStyle(color: Color(0xFFE5257E), fontWeight: FontWeight.w900, fontSize: 17)),
                          const Fig('bag_coin', width: 18, height: 18),
                          const SizedBox(width: 3),
                          Text(fmtNumber(t.$3), style: const TextStyle(color: Color(0xFFE5257E), fontWeight: FontWeight.w900, fontSize: 17)),
                        ]),
                ),
              ]),
            ),
          ),
        );
      },
    ),
  );
  noteCtl.dispose();
}

/// Çantayı açma penceresi (Figma: pembe kart, büyük yuvarlak düğme: geri sayım → AÇ).
Future<void> showBagClaim(BuildContext context, String roomId, Map<String, dynamic> bag) {
  return showDialog<void>(context: context, barrierColor: Colors.black54, builder: (c) => _ClaimDialog(roomId: roomId, bag: bag));
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
  int _toOpen = 0; // açılmasına kalan saniye (süper çanta geri sayımı)
  int _left = 1 << 30; // kapanmasına kalan saniye
  bool _noteSent = false;
  bool _busy = false;
  String? _won;
  String? _failed;

  Map<String, dynamic> get _b => widget.bag;
  bool get _super => _b['kind'] == 'super';

  @override
  void initState() {
    super.initState();
    _won = _b['mine']?.toString();
    _tick();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  int _secsTo(dynamic iso) {
    final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
    return d == null ? 0 : d.difference(DateTime.now()).inSeconds;
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      _toOpen = _super ? _secsTo(_b['opensAt']).clamp(0, 3600) : 0;
      _left = _secsTo(_b['expiresAt']);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _sendNote() async {
    setState(() => _busy = true);
    final r = await guard(context, () => Api.post('/api/rooms/${widget.roomId}/messages', {'text': (_b['note'] ?? '').toString()}));
    if (mounted) setState(() { _busy = false; if (r != null) _noteSent = true; });
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    Map<String, dynamic>? r;
    String? fail;
    try {
      r = await Api.post('/api/lucky-bags/${_b['id']}/claim');
    } catch (e) {
      fail = errorText(e);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) {
        _won = r['amount'].toString();
        _b['mine'] = _won;
      } else {
        // Figma: "Üzgünüm, bu şanslı çanta zaten açılmış..." (süresi dolan / tükenen çanta).
        _failed = fail ?? 'Üzgünüm, bu şanslı çanta zaten açılmış...';
      }
    });
    _t?.cancel();
  }

  String _mmss(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Widget _okButton() => _yellowButton('Tamam', () => Navigator.of(context).maybePop(), height: 38);

  @override
  Widget build(BuildContext context) {
    final sender = mapOf(_b['sender']);
    final expired = _left <= 0;
    final counting = _super && _toOpen > 0 && _won == null;
    final needNote = _super && !_noteSent && _won == null && !expired;
    final canOpen = _won == null && _failed == null && !expired && !counting && !needNote && !_busy;
    final name = '${sender?['displayName'] ?? ''}';
    Widget body;
    if (_won != null) {
      // Kazanç: parıltılı altın para, xTutar, Tebrikler!
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 110,
          height: 92,
          child: Stack(alignment: Alignment.center, children: [
            const Fig('fam_shine', width: 110, height: 110),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 520),
              curve: Curves.elasticOut,
              builder: (_, k, child) => Transform.scale(scale: k, child: child),
              child: const Fig('bag_coin', width: 66, height: 66),
            ),
          ]),
        ),
        Text('x${fmtNumber(_won)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 21)),
        const SizedBox(height: 2),
        const Text('Tebrikler!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 6),
        Text('$name takip et ve bir sonrakini kaçırma!', textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(color: Color(0xFFFFF3B0), fontWeight: FontWeight.w600, fontSize: 12.5)),
        const SizedBox(height: 12),
        _okButton(),
      ]);
    } else if (_failed != null || (expired && _won == null)) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        const Fig('bag_sad', width: 70, height: 70),
        const SizedBox(height: 12),
        Text(
          _failed == null || _failed!.contains('tükendi') || _failed!.contains('doldu') ? 'Üzgünüm, bu şanslı çanta zaten açılmış...' : _failed!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
        const SizedBox(height: 16),
        _okButton(),
      ]);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
          child: UserAvatar(user: sender, radius: 24),
        ),
        const SizedBox(height: 4),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 3),
        Row(mainAxisSize: MainAxisSize.min, children: [
          LevelPill(level: sender?['coinLevel'] ?? 1, send: true, height: 13),
          const SizedBox(width: 4),
          LevelPill(level: sender?['giftLevel'] ?? 1, send: false, height: 13),
        ]),
        const SizedBox(height: 4),
        Text(_super ? 'Süper şanslı çanta gönderdi' : 'Şanslı çanta gönderdi', style: const TextStyle(color: Color(0xFFFFF3B0), fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Fig('bag_coin', width: 20, height: 20),
          const SizedBox(width: 5),
          Text(fmtNumber(_b['totalCoins']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
        Text('${_b['claimed']}/${_b['slots']} kişi açtı', style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
        if (needNote) ...[
          const SizedBox(height: 8),
          Text('"${_b['note']}"', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 4),
          SizedBox(
            height: 30,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFE8258A), padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              onPressed: _busy ? null : _sendNote,
              child: const Text('Notu sohbete gönder ve aç'),
            ),
          ),
        ],
        const SizedBox(height: 10),
        // Yuvarlak düğme: AÇ (süper çantada önce geri sayım).
        GestureDetector(
          onTap: canOpen ? _open : null,
          child: Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x66FFFFFF)),
            child: Container(
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFDE7), Color(0xFFFFF176)]),
              ),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFFE5257E)))
                  : Text(counting ? _mmss(_toOpen) : 'AÇ', style: TextStyle(color: const Color(0xFFE5257E), fontWeight: FontWeight.w900, fontSize: counting ? 15 : 20)),
            ),
          ),
        ),
      ]);
    }
    // Odanın ortasında küçük kare kart.
    final side = (MediaQuery.sizeOf(context).width * 0.64).clamp(220.0, 290.0);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: side,
          height: side,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white, width: 1.4),
            image: DecorationImage(image: Fig.provider('bag_card'), fit: BoxFit.cover, onError: (_, __) {}),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF4D6D), Color(0xFFE8258A)]),
          ),
          child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: SizedBox(width: side - 28, child: body))),
        ),
        Positioned(right: -6, top: -6, child: InkWell(customBorder: const CircleBorder(), onTap: () => Navigator.pop(context), child: const CircleAvatar(radius: 13, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 15, color: Colors.white)))),
      ]),
    );
  }
}

/// Odada çanta varken görünen küçük kırmızı zarf (rozet = açık çanta sayısı).
class BagEnvelope extends StatelessWidget {
  final int count;
  final bool isSuper;
  final VoidCallback? onTap;
  final double size;
  const BagEnvelope({super.key, required this.count, this.isSuper = false, this.onTap, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size + 10,
        height: size + 8,
        child: Stack(clipBehavior: Clip.none, children: [
          // Odadaki çanta: Figma'daki kırmızı zarf (süper çantada altın parıltı).
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              decoration: isSuper ? const BoxDecoration(boxShadow: [BoxShadow(color: Color(0xAAFFC107), blurRadius: 12)]) : null,
              child: Fig('bag_icon', width: size * 0.78, height: size),
            ),
          ),
          if (count > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                child: Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ),
        ]),
      ),
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
