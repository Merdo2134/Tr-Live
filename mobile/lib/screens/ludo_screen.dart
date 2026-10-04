import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../services/socket_service.dart';
import '../widgets/common.dart';

const _colors = [Color(0xFFE53935), Color(0xFF43A047), Color(0xFFFDD835), Color(0xFF1E88E5)];
const _colorNames = ['Kırmızı', 'Yeşil', 'Sarı', 'Mavi'];

// Sunucudaki 52 karelik ortak yol (ludo.js ile aynı sıra). (sütun, satır), 15x15 ızgara.
final List<Offset> _path = () {
  final p = <Offset>[];
  for (var x = 1; x <= 5; x++) { p.add(Offset(x.toDouble(), 6)); }
  for (var y = 5; y >= 0; y--) { p.add(Offset(6, y.toDouble())); }
  p..add(const Offset(7, 0))..add(const Offset(8, 0));
  for (var y = 1; y <= 5; y++) { p.add(Offset(8, y.toDouble())); }
  for (var x = 9; x <= 14; x++) { p.add(Offset(x.toDouble(), 6)); }
  p..add(const Offset(14, 7))..add(const Offset(14, 8));
  for (var x = 13; x >= 9; x--) { p.add(Offset(x.toDouble(), 8)); }
  for (var y = 9; y <= 14; y++) { p.add(Offset(8, y.toDouble())); }
  p..add(const Offset(7, 14))..add(const Offset(6, 14));
  for (var y = 13; y >= 9; y--) { p.add(Offset(6, y.toDouble())); }
  for (var x = 5; x >= 0; x--) { p.add(Offset(x.toDouble(), 8)); }
  p..add(const Offset(0, 7))..add(const Offset(0, 6));
  return p;
}();

const _safe = {0, 8, 13, 21, 26, 34, 39, 47};
const _baseOrigin = [Offset(0, 0), Offset(9, 0), Offset(9, 9), Offset(0, 9)];

Offset _homeCell(int seat, int i) {
  switch (seat) {
    case 0: return Offset(1.0 + i, 7);
    case 1: return Offset(7, 1.0 + i);
    case 2: return Offset(13.0 - i, 7);
    default: return Offset(7, 13.0 - i);
  }
}

/// Taşın ızgara üzerindeki merkez koordinatı (hücre birimi).
Offset tokenCenter(int seat, int progress, int token) {
  if (progress < 0) {
    final o = _baseOrigin[seat];
    return Offset(o.dx + 1.5 + (token % 2) * 3, o.dy + 1.5 + (token ~/ 2) * 3) + const Offset(0.5, 0.5);
  }
  if (progress <= 50) return _path[(seat * 13 + progress) % 52] + const Offset(0.5, 0.5);
  if (progress <= 55) return _homeCell(seat, progress - 51) + const Offset(0.5, 0.5);
  const spread = [Offset(-0.5, -0.5), Offset(0.5, -0.5), Offset(-0.5, 0.5), Offset(0.5, 0.5)];
  final d = [const Offset(-0.35, 0), const Offset(0, -0.35), const Offset(0.35, 0), const Offset(0, 0.35)][seat];
  return const Offset(7.5, 7.5) + d + spread[token] * 0.25;
}

class _BoardPainter extends CustomPainter {
  final Map<String, dynamic>? tokens; // "0": [..4]
  final Set<String> legal; // "seat:token"
  final double pulse;
  _BoardPainter(this.tokens, this.legal, this.pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 15;
    Rect cell(Offset c) => Rect.fromLTWH(c.dx * u, c.dy * u, u, u);
    final fill = Paint();
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8..color = Colors.black26;

    fill.color = const Color(0xFFF5F0E6);
    canvas.drawRect(Offset.zero & size, fill);

    // Üsler
    for (var s = 0; s < 4; s++) {
      final o = _baseOrigin[s];
      fill.color = _colors[s];
      canvas.drawRect(Rect.fromLTWH(o.dx * u, o.dy * u, 6 * u, 6 * u), fill);
      fill.color = Colors.white.withValues(alpha: 0.85);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH((o.dx + 1) * u, (o.dy + 1) * u, 4 * u, 4 * u), Radius.circular(u * 0.6)), fill);
      for (var t = 0; t < 4; t++) {
        final c = tokenCenter(s, -1, t);
        fill.color = _colors[s].withValues(alpha: 0.25);
        canvas.drawCircle(Offset(c.dx * u, c.dy * u), u * 0.42, fill);
      }
    }

    // Ortak yol
    for (var i = 0; i < 52; i++) {
      final r = cell(_path[i]);
      fill.color = Colors.white;
      canvas.drawRect(r, fill);
      if (i % 13 == 0) {
        fill.color = _colors[i ~/ 13];
        canvas.drawRect(r, fill);
      }
      canvas.drawRect(r, line);
      if (_safe.contains(i) && i % 13 != 0) _star(canvas, r.center, u * 0.3, Colors.black38);
    }
    // Ev sütunları
    for (var s = 0; s < 4; s++) {
      for (var i = 0; i < 5; i++) {
        final r = cell(_homeCell(s, i));
        fill.color = _colors[s].withValues(alpha: 0.75);
        canvas.drawRect(r, fill);
        canvas.drawRect(r, line);
      }
    }
    // Merkez
    final c = Offset(7.5 * u, 7.5 * u);
    final tl = Offset(6 * u, 6 * u), tr = Offset(9 * u, 6 * u), bl = Offset(6 * u, 9 * u), br = Offset(9 * u, 9 * u);
    void tri(Offset a, Offset b, Color col) {
      fill.color = col;
      canvas.drawPath(Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy)..lineTo(c.dx, c.dy)..close(), fill);
    }
    tri(tl, bl, _colors[0]);
    tri(tl, tr, _colors[1]);
    tri(tr, br, _colors[2]);
    tri(bl, br, _colors[3]);

    // Taşlar
    final t = tokens;
    if (t == null) return;
    final placed = <String, int>{};
    for (final entry in t.entries) {
      final seat = int.tryParse(entry.key);
      if (seat == null || entry.value is! List) continue;
      final list = entry.value as List;
      for (var i = 0; i < list.length; i++) {
        final p = (list[i] as num).toInt();
        var ctr = tokenCenter(seat, p, i);
        final key = '${ctr.dx.toStringAsFixed(1)},${ctr.dy.toStringAsFixed(1)}';
        final n = placed[key] ?? 0;
        placed[key] = n + 1;
        if (p >= 0 && p < 56 && n > 0) ctr += Offset(0.18 * n, -0.18 * n);
        final pos = Offset(ctr.dx * u, ctr.dy * u);
        final isLegal = legal.contains('$seat:$i');
        if (isLegal) {
          fill.color = Colors.white.withValues(alpha: 0.35 + 0.35 * pulse);
          canvas.drawCircle(pos, u * (0.55 + 0.12 * pulse), fill);
        }
        fill.color = Colors.black38;
        canvas.drawCircle(pos + Offset(0, u * 0.05), u * 0.36, fill);
        fill.color = _colors[seat];
        canvas.drawCircle(pos, u * 0.34, fill);
        canvas.drawCircle(pos, u * 0.34, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = Colors.white);
      }
    }
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => old.tokens != tokens || old.pulse != pulse || old.legal != legal;
}

/// Odada oynanan ücretsiz Ludo. Bahis/Coin yoktur; tüm kurallar sunucuda işletilir.
class LudoScreen extends StatefulWidget {
  final String roomId;
  final bool canManage;
  const LudoScreen({super.key, required this.roomId, required this.canManage});

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _game;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  StreamSubscription? _sub;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  Timer? _tick;
  int _left = 0;
  DateTime _stamp = DateTime.now();

  @override
  void initState() {
    super.initState();
    _sub = SocketService.instance.events.listen((e) {
      if (e['type'] != 'room_game_state') return;
      final g = mapOf(e['game']);
      if (g == null || g['roomId'] != widget.roomId) return;
      _apply(g);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _game?['status'] == 'playing') setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic>? g) {
    if (!mounted) return;
    setState(() {
      _game = g;
      _left = (g?['secondsLeft'] as num?)?.toInt() ?? 0;
      _stamp = DateTime.now();
      _loading = false;
      _error = null;
    });
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/api/rooms/${widget.roomId}/game');
      _apply(mapOf(r['game']));
    } catch (e) {
      if (mounted) setState(() { _error = errorText(e); _loading = false; });
    }
  }

  int get _remaining => (_left - DateTime.now().difference(_stamp).inSeconds).clamp(0, 99);

  Map<String, dynamic>? get _me {
    for (final p in listOf(_game?['players'])) {
      if (mapOf(p['user'])?['id'] == Session.id) return p;
    }
    return null;
  }

  Future<void> _call(String path, [Map<String, dynamic>? body]) async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await guard(context, () => Api.post(path, body));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) return;
    final g = mapOf(r['game']);
    if (g != null) _apply(g);
    if (r['skipped'] == true) toast(context, 'Zar ${r['dice']}: oynanabilir taş yok, sıra geçti.');
    if (r['won'] == true) toast(context, 'Tebrikler, oyunu kazandınız! 🎉');
  }

  void _onBoardTap(TapUpDetails d, double side) {
    final g = _game;
    final me = _me;
    if (g == null || me == null || g['status'] != 'playing' || g['turnUserId'] != Session.id) return;
    final legal = (g['legal'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [];
    if (legal.isEmpty) return;
    final u = side / 15;
    final tap = Offset(d.localPosition.dx / u, d.localPosition.dy / u);
    final seat = (me['seat'] as num).toInt();
    final tokens = mapOf(g['tokens']);
    final mine = tokens?['$seat'] as List?;
    if (mine == null) return;
    int? best;
    var bestDist = 0.9;
    for (final i in legal) {
      final c = tokenCenter(seat, (mine[i] as num).toInt(), i);
      final dist = (c - tap).distance;
      if (dist < bestDist) { bestDist = dist; best = i; }
    }
    if (best != null) _call('/api/games/${g['id']}/move', {'token': best});
  }

  Widget _players(Map<String, dynamic> g) {
    final turn = g['turnUserId'];
    return Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
      for (final p in listOf(g['players']))
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _colors[(p['seat'] as num).toInt()], width: mapOf(p['user'])?['id'] == turn ? 3 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            UserAvatar(user: mapOf(p['user']), radius: 12),
            const SizedBox(width: 6),
            Text((mapOf(p['user'])?['displayName'] ?? '').toString(), style: const TextStyle(fontSize: 12)),
            if (((p['auto'] as num?) ?? 0) > 0) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.hourglass_bottom, size: 12, color: Colors.orangeAccent)),
          ]),
        ),
    ]);
  }

  Widget _lobby(Map<String, dynamic> g) {
    final players = listOf(g['players']);
    final joined = _me != null;
    final isCreator = g['createdBy'] == Session.id;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Ludo · oyuncular bekleniyor (${players.length}/4)', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final p in players)
        ListTile(
          leading: UserAvatar(user: mapOf(p['user'])),
          title: Text((mapOf(p['user'])?['displayName'] ?? '').toString()),
          trailing: CircleAvatar(radius: 8, backgroundColor: _colors[(p['seat'] as num).toInt()]),
        ),
      const SizedBox(height: 8),
      const Text('2-4 kişi oynar. Ücretsizdir; Coin bahsi yoktur. Zar için 30 sn süreniz var; üst üste 3 kez süre aşılırsa oyundan çıkarılırsınız.', style: TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 12),
      if (!joined) FilledButton.icon(onPressed: players.length >= 4 ? null : () => _call('/api/games/${g['id']}/join'), icon: const Icon(Icons.login), label: const Text('Katıl')),
      if (joined && !isCreator) OutlinedButton(onPressed: () => _call('/api/games/${g['id']}/leave'), child: const Text('Ayrıl')),
      if (isCreator) FilledButton.icon(onPressed: players.length < 2 ? null : () => _call('/api/games/${g['id']}/start'), icon: const Icon(Icons.play_arrow), label: const Text('Oyunu başlat')),
      if (isCreator || widget.canManage) TextButton(onPressed: () => _call('/api/games/${g['id']}/cancel'), child: const Text('Oyunu iptal et')),
    ]);
  }

  Widget _board(Map<String, dynamic> g) {
    final me = _me;
    final myTurn = g['turnUserId'] == Session.id;
    final legalList = (g['legal'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [];
    final legal = <String>{
      if (myTurn && me != null) for (final i in legalList) '${(me['seat'] as num).toInt()}:$i',
    };
    final dice = g['dice'];
    final turnPlayer = listOf(g['players']).where((p) => mapOf(p['user'])?['id'] == g['turnUserId']).firstOrNull;
    return ListView(padding: const EdgeInsets.all(12), children: [
      _players(g),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, c) {
        final side = math.min(c.maxWidth, 520.0);
        return Center(
          child: GestureDetector(
            onTapUp: (d) => _onBoardTap(d, side),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => CustomPaint(size: Size(side, side), painter: _BoardPainter(mapOf(g['tokens']), legal, _pulse.value)),
              ),
            ),
          ),
        );
      }),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Text(dice == null ? '?' : '$dice', style: const TextStyle(color: Colors.black87, fontSize: 28, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(me == null ? 'İzliyorsunuz' : (myTurn ? (dice == null ? 'Sıra sizde: zarı atın' : 'Parlayan taşa dokunun') : 'Sıra: ${mapOf(turnPlayer?['user'])?['displayName'] ?? ''}')),
          Text('Kalan süre: $_remaining sn', style: TextStyle(color: _remaining <= 8 ? Colors.redAccent : Colors.white54, fontSize: 12)),
          if (me != null) Text('Renginiz: ${_colorNames[(me['seat'] as num).toInt()]}', style: TextStyle(color: _colors[(me['seat'] as num).toInt()], fontSize: 12)),
        ]),
      ]),
      const SizedBox(height: 10),
      if (me != null)
        FilledButton.icon(
          onPressed: _busy || !myTurn || dice != null ? null : () => _call('/api/games/${g['id']}/roll'),
          icon: const Icon(Icons.casino),
          label: const Text('Zar at'),
        ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (me != null) TextButton(onPressed: () async { if (await confirm(context, 'Oyundan ayrılırsanız elenirsiniz.', action: 'Ayrıl') && mounted) _call('/api/games/${g['id']}/leave'); }, child: const Text('Oyundan ayrıl')),
        if (widget.canManage) TextButton(onPressed: () async { if (await confirm(context, 'Oyun iptal edilsin mi?', action: 'İptal et') && mounted) _call('/api/games/${g['id']}/cancel'); }, child: const Text('Oyunu iptal et')),
      ]),
    ]);
  }

  Widget _empty({String? message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.casino, size: 56, color: Colors.white38),
          const SizedBox(height: 12),
          Text(message ?? 'Odada açık oyun yok.'),
          const SizedBox(height: 12),
          if (widget.canManage) FilledButton.icon(onPressed: () => _call('/api/rooms/${widget.roomId}/games', {'type': 'ludo'}), icon: const Icon(Icons.add), label: const Text('Ludo kur')),
          if (!widget.canManage) const Text('Oyunu oda yetkilileri kurabilir.', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _game;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && g == null) {
      body = LoadError(message: _error!, onRetry: _load);
    } else if (g == null) {
      body = _empty();
    } else {
      switch (g['status']) {
        case 'waiting':
          body = _lobby(g);
          break;
        case 'playing':
          body = _board(g);
          break;
        case 'finished':
          final winner = listOf(g['players']).where((p) => mapOf(p['user'])?['id'] == g['winnerId']).firstOrNull;
          body = _empty(message: 'Oyun bitti. Kazanan: ${mapOf(winner?['user'])?['displayName'] ?? '-'} 🏆');
          break;
        default:
          body = _empty(message: 'Oyun iptal edildi.');
      }
    }
    return Scaffold(appBar: AppBar(title: const Text('Ludo')), body: body);
  }
}
