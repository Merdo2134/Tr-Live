import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
import 'app_theme.dart';
import 'common.dart';
import 'level_badge.dart';

/// CP (yakınlık) sistemi: iki kişi arasındaki puan, 5 kademe, 3. kademeden itibaren Arkadaş / CP ilişkisi,
/// 5. kademede odada yan yana oturan CP'ler arasında kalp efekti.
const kCpPink = Color(0xFFFF4F9A);
const kCpRose = Color(0xFFFF7EB3);
const kCpMaxLevel = 5;
const kCpEffectLevel = 5; // odada kalp efekti

String cpRelationLabel(String? r) => switch (r) { 'cp' => 'CP', 'friend' => 'Arkadaş', _ => '' };

/// Kalp şekli: [c] merkez, [s] genişlik.
Path heartPath(Offset c, double s) {
  final w = s, h = s * 0.92;
  final x = c.dx - w / 2, y = c.dy - h / 2;
  return Path()
    ..moveTo(x + w / 2, y + h * 0.28)
    ..cubicTo(x + w / 2, y + h * 0.05, x + w * 0.08, y - h * 0.02, x + w * 0.04, y + h * 0.32)
    ..cubicTo(x, y + h * 0.58, x + w * 0.3, y + h * 0.76, x + w / 2, y + h)
    ..cubicTo(x + w * 0.7, y + h * 0.76, x + w, y + h * 0.58, x + w * 0.96, y + h * 0.32)
    ..cubicTo(x + w * 0.92, y - h * 0.02, x + w / 2, y + h * 0.05, x + w / 2, y + h * 0.28)
    ..close();
}

/// Kademe kalpleri (dolu / boş).
class CpHearts extends StatelessWidget {
  final int level;
  final double size;
  const CpHearts({super.key, required this.level, this.size = 16});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= kCpMaxLevel; i++)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.08),
            child: Icon(i <= level ? Icons.favorite : Icons.favorite_border, size: size, color: i <= level ? kCpPink : Colors.white38),
          ),
      ]);
}

/// Profil kartında iki kişi arasındaki yakınlık: kademe, ilerleme, puan kuralları ve ilişki seçimi (Arkadaş / CP).
class CpPanel extends StatefulWidget {
  final String userId;
  final String? displayName;
  const CpPanel({super.key, required this.userId, this.displayName});

  @override
  State<CpPanel> createState() => _CpPanelState();
}

class _CpPanelState extends State<CpPanel> {
  Map<String, dynamic>? _s;
  bool _busy = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    // Karşı taraf istek gönderir / kabul eder / bitirirse panel kendini yeniler.
    _sub = SocketService.instance.events.listen((e) {
      final t = e['type'];
      if (t == 'cp_update' && e['userId']?.toString() == widget.userId) _load();
      if (t == 'cp_request' && mapOf(e['from'])?['id']?.toString() == widget.userId) _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/api/cp/with/${widget.userId}');
      if (mounted) setState(() => _s = r);
    } catch (_) {/* panel gizli kalır */}
  }

  Future<void> _post(String action, [Map<String, dynamic>? body, String? done]) async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await guard(context, () => Api.post('/api/cp/with/${widget.userId}/$action', body ?? const {}));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) _s = r;
    });
    if (r != null && done != null) toast(context, done);
  }

  Future<void> _choose(String kind) async {
    final name = widget.displayName ?? 'Bu kişi';
    final ok = await confirm(
      context,
      kind == 'cp' ? '$name kişisine CP isteği gönderilsin mi? Kabul ederse CP olursunuz (herkesin tek CP\'si olur).' : '$name kişisine Arkadaş ilişkisi isteği gönderilsin mi?',
      action: 'Gönder',
    );
    if (ok) await _post('request', {'kind': kind}, 'İstek gönderildi.');
  }

  Future<void> _end(String relation) async {
    final ok = await confirm(context, '${cpRelationLabel(relation)} ilişkisi bitirilsin mi? Yakınlık puanınız korunur.', action: 'Bitir', destructive: true);
    if (ok) await _post('end', null, 'İlişki bitirildi.');
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();
    final level = (s['level'] as num?)?.toInt() ?? 0;
    final exp = double.tryParse('${s['exp']}') ?? 0;
    final start = double.tryParse('${s['levelStartExp']}') ?? 0;
    final next = double.tryParse('${s['nextLevelExp']}') ?? 1;
    final maxed = s['maxed'] == true;
    final progress = maxed ? 1.0 : ((exp - start) / math.max(1, next - start)).clamp(0.0, 1.0).toDouble();
    final relation = (s['relation'] ?? 'none').toString();
    final req = mapOf(s['request']);
    final canChoose = s['canChoose'] == true;
    final chooseLevel = (s['chooseLevel'] as num?)?.toInt() ?? 3;

    Widget btn(String label, IconData icon, VoidCallback? onTap, {bool primary = false, Color color = kCpPink}) => Expanded(
          child: primary
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(38), padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: _busy ? null : onTap,
                  icon: Icon(icon, size: 17),
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color.withValues(alpha: 0.7)), minimumSize: const Size.fromHeight(38), padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: _busy ? null : onTap,
                  icon: Icon(icon, size: 17),
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
                ),
        );

    final List<Widget> actions;
    if (req != null && req['fromMe'] != true) {
      actions = [
        Text('${widget.displayName ?? 'Bu kişi'} seni ${cpRelationLabel(req['kind'] as String?)} olarak seçti', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          btn('Reddet', Icons.close, () => _post('decline', null, 'İstek reddedildi.'), color: Colors.white70),
          const SizedBox(width: 8),
          btn('Kabul et', Icons.favorite, () => _post('accept', null, 'Artık ${cpRelationLabel(req['kind'] as String?)}sınız!'), primary: true),
        ]),
      ];
    } else if (req != null) {
      actions = [
        Row(children: [
          Expanded(child: Text('${cpRelationLabel(req['kind'] as String?)} isteği gönderildi, yanıt bekleniyor', style: const TextStyle(color: Colors.white70, fontSize: 13))),
          TextButton(onPressed: _busy ? null : () => _post('decline', null, 'İstek geri çekildi.'), child: const Text('Geri çek')),
        ]),
      ];
    } else if (relation != 'none') {
      actions = [
        Row(children: [
          if (relation == 'friend' && canChoose) ...[btn('CP olarak seç', Icons.favorite, () => _choose('cp'), primary: true), const SizedBox(width: 8)],
          if (relation == 'cp' && canChoose) ...[btn('Arkadaş yap', Icons.people_alt_outlined, () => _choose('friend')), const SizedBox(width: 8)],
          btn('İlişkiyi bitir', Icons.heart_broken_outlined, () => _end(relation), color: Colors.white60),
        ]),
      ];
    } else if (canChoose) {
      actions = [
        Row(children: [
          btn('Arkadaş olarak seç', Icons.people_alt_outlined, () => _choose('friend'), color: Pal.cyan),
          const SizedBox(width: 8),
          btn('CP olarak seç', Icons.favorite, () => _choose('cp'), primary: true),
        ]),
      ];
    } else {
      actions = [
        Text('Seviye $chooseLevel olunca Arkadaş ya da CP olarak seçebilirsiniz.', style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
      ];
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A1230), Color(0xFF241338)]),
        border: Border.all(color: kCpPink.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.favorite, color: kCpPink, size: 18),
          const SizedBox(width: 6),
          Text(relation == 'none' ? 'Yakınlık' : 'Yakınlık · ${cpRelationLabel(relation)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const Spacer(),
          CpHearts(level: level, size: 15),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: Colors.white12, valueColor: const AlwaysStoppedAnimation(kCpPink)),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text(level == 0 ? 'Seviye yok' : 'Seviye $level', style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(maxed ? '${fmtNumber(s['exp'])} exp · en yüksek' : '${fmtNumber(s['exp'])} / ${fmtNumber(s['nextLevelExp'])} exp', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        const SizedBox(height: 4),
        const Text('Günde 10 mesaj 100 exp · hediyeler Coin değeri kadar · CP hediyesi 1,5 kat', style: TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 10),
        ...actions,
      ]),
    );
  }
}

/// Profilde CP eşi: iki avatar arasında kalp ve kademe.
class CpPartnerCard extends StatelessWidget {
  final Map<String, dynamic> cp;
  final VoidCallback? onTap;
  const CpPartnerCard({super.key, required this.cp, this.onTap});

  @override
  Widget build(BuildContext context) {
    final partner = mapOf(cp['partner']);
    final level = (cp['level'] as num?)?.toInt() ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [Color(0xFF5A1240), Color(0xFF2B1446)]),
          border: Border.all(color: kCpPink.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          UserAvatar(user: partner, radius: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((partner?['displayName'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 3),
              if (level >= 1) CpLevelPill(level: level, height: 17) else CpHearts(level: level, size: 13),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: kCpPink, borderRadius: BorderRadius.circular(12)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.favorite, size: 14, color: Colors.white),
              SizedBox(width: 3),
              Text('CP', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Odada yan yana oturan 5. kademe CP'ler: ortada kalp atışı gibi büyüyüp küçülen kalp ve iki avatarın
/// dairesinin çevresinden çıkan küçük kalpler. Yalnızca çizim yapar (dokunmaları geçirir, koltuk düzenini değiştirmez).
/// [a] ve [b] avatar merkezleri, [r] avatar yarıçapı; hepsi bu widget'ın kendi koordinatlarında.
class CpSeatHearts extends StatefulWidget {
  final Offset a;
  final Offset b;
  final double r;
  const CpSeatHearts({super.key, required this.a, required this.b, required this.r});

  @override
  State<CpSeatHearts> createState() => _CpSeatHeartsState();
}

class _CpSeatHeartsState extends State<CpSeatHearts> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(child: CustomPaint(painter: _CpHeartsPainter(_c, widget.a, widget.b, widget.r), size: Size.infinite)),
      );
}

class _CpHeartsPainter extends CustomPainter {
  final Animation<double> t;
  final Offset a;
  final Offset b;
  final double r;
  _CpHeartsPainter(this.t, this.a, this.b, this.r) : super(repaint: t);

  static const _perSeat = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    // Çevreden çıkan küçük kalpler: her avatarda 6 tane, farklı açı ve zamanlarda doğup dışarı süzülür.
    for (final (center, seed) in [(a, 0), (b, 3)]) {
      for (var i = 0; i < _perSeat; i++) {
        final life = (v * 2 + i / _perSeat + seed * 0.07) % 1.0;
        final ang = (i * 137.5 + seed * 40 + (v * 2 + i / _perSeat).floor() * 53) * math.pi / 180;
        final dir = Offset(math.cos(ang), math.sin(ang));
        final p = center + dir * (r * (1.0 + 0.55 * life)) + Offset(0, -r * 0.35 * life);
        final fade = math.sin(math.pi * life);
        final s = r * (0.2 + 0.12 * fade);
        canvas.drawPath(heartPath(p, s), Paint()..color = kCpRose.withValues(alpha: 0.9 * fade));
      }
    }
    // Ortadaki kalp: kalp atışı (iki hızlı vuruş, sonra dinlenme).
    final beat = (v * 4) % 1.0;
    double k;
    if (beat < 0.12) {
      k = math.sin(beat / 0.12 * math.pi);
    } else if (beat > 0.2 && beat < 0.34) {
      k = 0.7 * math.sin((beat - 0.2) / 0.14 * math.pi);
    } else {
      k = 0;
    }
    final mid = Offset.lerp(a, b, 0.5)!;
    final gap = (b - a).distance - 2 * r;
    final base = math.max(r * 0.55, math.min(r * 0.8, gap + r * 0.35));
    final hs = base * (0.88 + 0.22 * k);
    final path = heartPath(mid, hs);
    canvas.drawPath(path, Paint()
      ..color = kCpPink.withValues(alpha: 0.45 + 0.35 * k)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, hs * 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF9AC8), kCpPink, Color(0xFFE0115F)])
            .createShader(Rect.fromCenter(center: mid, width: hs, height: hs)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, hs * 0.05)
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_CpHeartsPainter old) => old.a != a || old.b != b || old.r != r || old.t != t;
}
