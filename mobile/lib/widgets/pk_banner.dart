import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/common.dart';

/// Oda üstündeki PK şeridi: iki tarafın skoru, kalan süre ve en çok destek verenler.
class PkBanner extends StatefulWidget {
  final Map<String, dynamic> pk;
  final String roomId;
  final VoidCallback? onCancel;
  const PkBanner({super.key, required this.pk, required this.roomId, this.onCancel});

  @override
  State<PkBanner> createState() => _PkBannerState();
}

class _PkBannerState extends State<PkBanner> {
  Timer? _timer;
  late int _left;
  DateTime _stamp = DateTime.now();

  @override
  void initState() {
    super.initState();
    _sync();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final passed = DateTime.now().difference(_stamp).inSeconds;
      setState(() => _left = ((widget.pk['remainingSeconds'] as num?)?.toInt() ?? 0) - passed < 0 ? 0 : ((widget.pk['remainingSeconds'] as num?)?.toInt() ?? 0) - passed);
    });
  }

  void _sync() {
    _left = (widget.pk['remainingSeconds'] as num?)?.toInt() ?? 0;
    _stamp = DateTime.now();
  }

  @override
  void didUpdateWidget(covariant PkBanner old) {
    super.didUpdateWidget(old);
    if (old.pk['remainingSeconds'] != widget.pk['remainingSeconds'] || old.pk['status'] != widget.pk['status']) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _clock(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final pk = widget.pk;
    final a = mapOf(pk['a']) ?? {};
    final b = mapOf(pk['b']) ?? {};
    final status = pk['status']?.toString();
    final sa = BigInt.tryParse(a['score'].toString()) ?? BigInt.zero;
    final sb = BigInt.tryParse(b['score'].toString()) ?? BigInt.zero;
    final total = sa + sb;
    final ratio = total == BigInt.zero ? 0.5 : sa.toDouble() / total.toDouble();
    final mineIsA = a['roomId'] == widget.roomId;
    final result = pk['result']?.toString();
    String title;
    if (status == 'pending') {
      title = 'PK daveti bekleniyor...';
    } else if (status == 'finished') {
      title = result == 'draw' ? 'PK berabere' : ((result == 'a') == mineIsA ? 'Kazandınız! 🎉' : 'Rakip kazandı');
    } else if (status == 'active') {
      title = 'PK  ${_clock(_left)}';
    } else {
      title = 'PK sona erdi';
    }
    Widget side(Map<String, dynamic> x, bool left) => Expanded(
          child: Column(children: [
            Text((mapOf(x['host'])?['displayName'] ?? x['roomName'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Text(fmtNumber(x['score']), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: left ? Colors.lightBlueAccent : Colors.pinkAccent)),
            Text(
              [for (final t in listOf(x['top'])) (mapOf(t['user'])?['displayName'] ?? '').toString()].take(3).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ]),
        );
    return Material(
      color: Colors.black38,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
            if (widget.onCancel != null && (status == 'pending' || status == 'active'))
              IconButton(visualDensity: VisualDensity.compact, tooltip: status == 'pending' ? 'Daveti geri çek' : 'PK\'yı bitir', icon: const Icon(Icons.close, size: 18), onPressed: widget.onCancel),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [side(a, true), const Text('VS', style: TextStyle(fontWeight: FontWeight.bold)), side(b, false)]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                Expanded(flex: (ratio * 1000).round().clamp(1, 999), child: Container(color: Colors.lightBlueAccent)),
                Expanded(flex: ((1 - ratio) * 1000).round().clamp(1, 999), child: Container(color: Colors.pinkAccent)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
