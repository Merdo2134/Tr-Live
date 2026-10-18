import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/anim_asset.dart';
import '../widgets/common.dart';
import '../widgets/wip_items.dart';
import 'user_screens.dart';

/// Haftalık etkinlik grupları (banner'lar ve sayfalar bu üç gruba göre).
enum EventGroup { couple, royal, star }

/// Renkler banner görsellerinin tonlarından: Kral & Kraliçe mor-pembe + altın, Çift kahve-bordo + altın,
/// Yıldızlar koyu kırmızı perde + altın.
class EventTheme {
  final String title;
  final String subtitle;
  final String emoji;
  /// [koyu, orta, açık] renk geçişi.
  final List<Color> colors;
  final Color accent;
  /// Sayfa zemini.
  final Color background;
  /// Banner görseli (750x250).
  final String asset;
  const EventTheme(this.title, this.subtitle, this.emoji, this.colors, this.accent, this.background, this.asset);

  static EventTheme of(EventGroup g) => switch (g) {
        EventGroup.couple => const EventTheme('Haftanın Çifti', 'En çok CP hediyesi gönderen çiftler', '💞',
            [Color(0xFF4A170A), Color(0xFF8E2F14), Color(0xFFE3A35C)], Color(0xFFFFCB8E), Color(0xFF1B0C07), 'assets/images/event_couple.webp'),
        EventGroup.royal => const EventTheme('Haftalık Kral ve Kraliçe', 'Haftanın en çok hediye alan erkeği ve kadını', '👑',
            [Color(0xFF3A1352), Color(0xFFA0307F), Color(0xFFE9B94C)], Color(0xFFFFD66E), Color(0xFF170A21), 'assets/images/event_royal.webp'),
        EventGroup.star => const EventTheme('Haftalık Yıldızlar', 'Seçili 4 hediyeden en çok gönderenler', '⭐',
            [Color(0xFF4A070B), Color(0xFFA11D1F), Color(0xFFF0B43C)], Color(0xFFFFD45C), Color(0xFF170405), 'assets/images/event_star.webp'),
      };
}

String _d2(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${_d2(d.day)}.${_d2(d.month)}.${d.year}';

/// Kral & Kraliçe banner'ının sol altındaki tarih kutusu (görseldeki eski tarihin yerine, bu haftanın tarihleri).
class EventWeekDates extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  const EventWeekDates({super.key, this.start, this.end});

  @override
  Widget build(BuildContext context) {
    final s = start ?? _thisMonday();
    final e = (end ?? s.add(const Duration(days: 7))).subtract(const Duration(seconds: 1));
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(left: w * 0.016, top: box.maxHeight * 0.6),
            child: Container(
              width: w * 0.33,
              height: box.maxHeight * 0.31,
              padding: EdgeInsets.symmetric(horizontal: w * 0.012),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(w * 0.015),
                gradient: LinearGradient(colors: [const Color(0xFF2A1238).withValues(alpha: 0.92), const Color(0xFF5A2A63).withValues(alpha: 0.85)]),
                border: Border.all(color: const Color(0xFFE9B94C).withValues(alpha: 0.7), width: 1),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${_date(s)} 00:00', style: _dateStyle),
                  Text('${_date(e)} 23:59:59', style: _dateStyle),
                ]),
              ),
            ),
          ),
      );
    });
  }

  static const _dateStyle = TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, height: 1.15, shadows: [Shadow(color: Colors.black, blurRadius: 3)]);

  static DateTime _thisMonday() {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }
}

/// Etkinlik banner görseli (3:1) — ana sayfa kartında ve etkinlik sayfasının başında aynı.
class EventBannerImage extends StatelessWidget {
  final EventGroup group;
  final DateTime? weekStart;
  final DateTime? weekEnd;
  const EventBannerImage({super.key, required this.group, this.weekStart, this.weekEnd});

  @override
  Widget build(BuildContext context) {
    final t = EventTheme.of(group);
    return Stack(children: [
      Positioned.fill(child: Image.asset(t.asset, fit: BoxFit.cover, errorBuilder: (_, __, ___) => DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: t.colors))))),
      if (group == EventGroup.royal) Positioned.fill(child: EventWeekDates(start: weekStart, end: weekEnd)),
    ]);
  }
}

/// Etkinliğin bitimine kalan süre: "2g 05:12:33".
String eventCountdown(DateTime? end) {
  if (end == null) return '';
  var d = end.difference(DateTime.now());
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  final days = d.inDays;
  return '${days > 0 ? '${days}g ' : ''}${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// Etkinlik sayfası: üstte başlık ve geri sayım, altında Sıralama / Ödüller / Kurallar sekmeleri.
/// Kral & Kraliçe sayfasında Kral/Kraliçe seçimi; Yıldız sayfasında haftanın 4 hediyesi arasında seçim.
class EventScreen extends StatefulWidget {
  final EventGroup group;
  /// Açılışta gösterilecek etkinlik (ör. yalnızca Kraliçe açıksa 'queen').
  final String? initialKind;
  const EventScreen({super.key, required this.group, this.initialKind});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  late String _kind = widget.initialKind ?? switch (widget.group) {
    EventGroup.couple => 'couple',
    EventGroup.royal => 'king',
    EventGroup.star => 'star1',
  };
  List<Map<String, dynamic>> _stars = [];
  Map<String, dynamic>? _data;
  String? _error;
  int _seq = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _data != null) setState(() {});
    });
    _init();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    if (widget.group == EventGroup.star) {
      try {
        final o = await Api.get('/api/events');
        _stars = listOf(o['events']).where((e) => e['kind'].toString().startsWith('star')).toList();
        if (_stars.isNotEmpty) _kind = _stars.first['kind'].toString();
      } catch (_) {}
    }
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _error = null);
    try {
      final d = await Api.get('/api/events/$_kind');
      if (!mounted || seq != _seq) return;
      setState(() => _data = d);
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = errorText(e));
    }
  }

  void _select(String kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _data = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = EventTheme.of(widget.group);
    final end = DateTime.tryParse((_data?['weekEnd'] ?? '').toString())?.toLocal();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: t.background,
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              backgroundColor: t.colors.first,
              foregroundColor: Colors.white,
              title: Text(t.title, style: TextStyle(fontWeight: FontWeight.w900, color: t.accent)),
            ),
            // Banner görseli (ana sayfadakiyle aynı) ve geri sayım.
            SliverToBoxAdapter(
              child: _Header(
                theme: t,
                group: widget.group,
                countdown: eventCountdown(end),
                weekStart: DateTime.tryParse((_data?['weekStart'] ?? '').toString())?.toLocal(),
                weekEnd: end,
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabsHeader(
                TabBar(
                  indicatorColor: t.accent,
                  indicatorWeight: 3,
                  labelColor: t.accent,
                  unselectedLabelColor: Colors.white60,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                  tabs: const [Tab(text: 'Sıralama'), Tab(text: 'Ödüller'), Tab(text: 'Kurallar')],
                ),
                t,
              ),
            ),
          ],
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [t.colors.first.withValues(alpha: 0.55), t.background]),
            ),
            child: Column(children: [
              if (widget.group == EventGroup.royal) _royalSwitch(t),
              if (widget.group == EventGroup.star) _starSwitch(t),
              Expanded(child: _body(t)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _royalSwitch(EventTheme t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(24)),
          child: Row(children: [
            for (final k in const [['king', '🤴 Kral'], ['queen', '👸 Kraliçe']])
              Expanded(
                child: GestureDetector(
                  onTap: () => _select(k[0]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: _kind == k[0] ? LinearGradient(colors: t.colors.take(2).toList()) : null,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(k[1], style: TextStyle(fontWeight: FontWeight.w900, color: _kind == k[0] ? Colors.white : Colors.white60)),
                  ),
                ),
              ),
          ]),
        ),
      );

  Widget _starSwitch(EventTheme t) {
    if (_stars.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 84,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 10, 12, 4), children: [
        for (final s in _stars)
          GestureDetector(
            onTap: () => _select(s['kind'].toString()),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 78,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kind == s['kind'] ? t.accent : Colors.white12, width: _kind == s['kind'] ? 2 : 1),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 34, height: 34, child: _giftIcon(mapOf(s['gift']))),
                const SizedBox(height: 4),
                Text((mapOf(s['gift'])?['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _giftIcon(Map<String, dynamic>? gift) {
    final u = Api.absoluteUrl(gift?['iconUrl'] as String?);
    if (u == null) return const Icon(Icons.card_giftcard, color: Colors.white70);
    return NetImg(u, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.white70));
  }

  Widget _body(EventTheme t) {
    if (widget.group == EventGroup.star && _stars.isEmpty && _data == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
          ]),
        ),
      );
    }
    final d = _data;
    if (d == null) return const Center(child: CircularProgressIndicator());
    return TabBarView(children: [
      RefreshIndicator(onRefresh: _load, child: _ranking(d, t)),
      _rewards(d, t),
      _rules(d),
    ]);
  }

  // ------------------------------------------------------------ Sıralama
  Widget _ranking(Map<String, dynamic> d, EventTheme t) {
    final list = listOf(d['leaderboard']);
    final last = listOf(d['lastWinners']);
    final me = mapOf(d['me']);
    final unit = (d['scoreUnit'] ?? 'Coin').toString();
    final enabled = d['enabled'] == true;
    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [
        if (widget.group == EventGroup.star && d['gift'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 28, height: 28, child: _giftIcon(mapOf(d['gift']))),
              const SizedBox(width: 8),
              Expanded(child: Text('Bu hafta en çok "${mapOf(d['gift'])?['name']}" gönderen kazanır', style: const TextStyle(color: Colors.white70, fontSize: 13))),
            ]),
          ),
        if (last.isNotEmpty) _lastWinners(last, t, unit),
        if (!enabled)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Bu etkinlik şu an kapalı.', style: TextStyle(color: Colors.white60))))
        else if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Bu hafta henüz sıralamaya giren yok.\nİlk sen ol!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, height: 1.4))),
          )
        else ...[
          _podium(list.take(3).toList(), t, unit),
          const SizedBox(height: 10),
          for (final r in list.skip(3)) _row(r, t, unit),
        ],
      ]),
      Positioned(left: 0, right: 0, bottom: 0, child: _meBar(me, t, unit)),
    ]);
  }

  void _openUser(Map<String, dynamic>? u) {
    final id = u?['id']?.toString();
    if (id == null || u?['isHidden'] == true) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)));
  }

  /// Çiftte iki avatar üst üste ve aralarında kalp; diğerlerinde tek avatar.
  Widget _avatars(Map<String, dynamic> r, double radius, {Color? ring}) {
    final u = mapOf(r['user']);
    final p = mapOf(r['partner']);
    Widget av(Map<String, dynamic>? x) => GestureDetector(
          onTap: () => _openUser(x),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, color: ring ?? Colors.white24),
            child: UserAvatar(user: x, radius: radius),
          ),
        );
    if (p == null) return av(u);
    return SizedBox(
      width: radius * 3.6 + 8,
      height: radius * 2 + 4,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 0, child: av(u)),
        Positioned(right: 0, child: av(p)),
        Positioned(left: 0, right: 0, bottom: -4, child: Center(child: Text('💞', style: TextStyle(fontSize: radius * 0.8)))),
      ]),
    );
  }

  String _names(Map<String, dynamic> r) {
    final a = (mapOf(r['user'])?['displayName'] ?? '').toString();
    final b = mapOf(r['partner'])?['displayName']?.toString();
    return b == null ? a : '$a & $b';
  }

  Widget _podium(List<Map<String, dynamic>> top, EventTheme t, String unit) {
    const medals = ['🥇', '🥈', '🥉'];
    const rings = [Color(0xFFFFD54A), Color(0xFFCFD8DC), Color(0xFFD7A26B)];
    Widget spot(int i, double radius, double lift) {
      if (i >= top.length) return const Expanded(child: SizedBox.shrink());
      final r = top[i];
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(top: lift),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(medals[i], style: TextStyle(fontSize: i == 0 ? 30 : 24)),
            const SizedBox(height: 2),
            _avatars(r, radius, ring: rings[i]),
            const SizedBox(height: 6),
            Text(_names(r), maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 2),
            Text('${fmtNumber(r['score'])} $unit', style: TextStyle(color: t.accent, fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [t.colors[1].withValues(alpha: 0.35), Colors.white.withValues(alpha: 0.04)]),
        border: Border.all(color: t.accent.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        spot(1, 26, 22),
        spot(0, 34, 0),
        spot(2, 24, 28),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> r, EventTheme t, String unit) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [t.colors[1].withValues(alpha: 0.22), Colors.white.withValues(alpha: 0.03)]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.accent.withValues(alpha: 0.18)),
        ),
        child: Row(children: [
          SizedBox(width: 30, child: Text('${r['rank']}', style: TextStyle(fontWeight: FontWeight.w900, color: t.accent.withValues(alpha: 0.85)))),
          _avatars(r, 18),
          const SizedBox(width: 10),
          Expanded(child: Text(_names(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text('${fmtNumber(r['score'])} $unit', style: TextStyle(color: t.accent, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
      );

  Widget _lastWinners(List<Map<String, dynamic>> last, EventTheme t, String unit) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🏆 Geçen haftanın kazananları', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          for (final r in last)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Text(const ['🥇', '🥈', '🥉'][((r['rank'] as num?)?.toInt() ?? 1).clamp(1, 3) - 1], style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                _avatars(r, 13),
                const SizedBox(width: 8),
                Expanded(child: Text(_names(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                Text('${fmtNumber(r['score'])} $unit', style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
              ]),
            ),
        ]),
      );

  Widget _meBar(Map<String, dynamic>? me, EventTheme t, String unit) => Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: t.colors.take(2).toList()),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
        ),
        child: Row(children: [
          const Icon(Icons.person_pin_circle, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              me == null ? 'Bu hafta henüz listede değilsin' : 'Senin sıran: ${me['rank']}.',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          if (me != null) Text('${fmtNumber(me['score'])} $unit', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
        ]),
      );

  // ------------------------------------------------------------ Ödüller
  Widget _rewards(Map<String, dynamic> d, EventTheme t) {
    final rewards = mapOf(d['rewards']) ?? {};
    const medals = ['🥇', '🥈', '🥉'];
    final couple = widget.group == EventGroup.couple;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text(
        couple ? 'Hafta bitince ilk 3 çiftin İKİ KİŞİSİNE de ödüller otomatik verilir.' : 'Hafta bitince ilk 3\'e ödüller otomatik verilir.',
        style: const TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 10),
      for (var i = 0; i < 3; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(colors: [t.colors[1].withValues(alpha: 0.30 - i * 0.07), Colors.white.withValues(alpha: 0.04)]),
            border: Border.all(color: t.accent.withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${medals[i]} ${i + 1}. sıra', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            if (listOf(rewards['${i + 1}']).isEmpty)
              const Text('Ödül tanımlanmadı.', style: TextStyle(color: Colors.white54))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [for (final r in listOf(rewards['${i + 1}'])) _rewardChip(r, t)]),
          ]),
        ),
    ]);
  }

  Widget _rewardChip(Map<String, dynamic> r, EventTheme t) {
    Widget art;
    final type = r['type'];
    if (type == 'coins') {
      art = const Icon(Icons.monetization_on, color: Color(0xFFFFC107), size: 40);
    } else if (type == 'wip') {
      art = FittedBox(child: wipItemArt('badge', (r['level'] as num?)?.toInt() ?? 1, 60));
    } else if (r['wipLevel'] != null) {
      art = FittedBox(child: wipItemArt((r['category'] ?? 'badge').toString(), (r['wipLevel'] as num).toInt(), 70));
    } else {
      final u = Api.absoluteUrl(r['imageUrl'] as String?);
      art = u == null ? const Icon(Icons.card_giftcard, color: Colors.white70, size: 36) : AnimAsset(url: u, repeat: true, cache: false);
    }
    return Container(
      width: 104,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
      child: Column(children: [
        SizedBox(height: 56, child: Center(child: art)),
        const SizedBox(height: 6),
        if (r['kindLabel'] != null) Text(r['kindLabel'].toString(), style: TextStyle(fontSize: 10, color: t.accent, fontWeight: FontWeight.w800)),
        Text((r['label'] ?? '').toString(), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ------------------------------------------------------------ Kurallar
  Widget _rules(Map<String, dynamic> d) {
    final lines = (d['rules'] ?? '').toString().split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (var i = 0; i < lines.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
              child: Text('${i + 1}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(lines[i], style: const TextStyle(height: 1.4))),
          ]),
        ),
    ]);
  }
}

class _Header extends StatelessWidget {
  final EventTheme theme;
  final EventGroup group;
  final String countdown;
  final DateTime? weekStart;
  final DateTime? weekEnd;
  const _Header({required this.theme, required this.group, required this.countdown, this.weekStart, this.weekEnd});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.colors.first,
      child: Column(children: [
        AspectRatio(aspectRatio: 3, child: EventBannerImage(group: group, weekStart: weekStart, weekEnd: weekEnd)),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [theme.colors.first, theme.colors[1].withValues(alpha: 0.85), theme.colors.first]),
            border: Border(bottom: BorderSide(color: theme.accent.withValues(alpha: 0.5))),
          ),
          child: Row(children: [
            Expanded(child: Text(theme.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5))),
            if (countdown.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(12), border: Border.all(color: theme.accent.withValues(alpha: 0.6))),
                child: Text('⏳ $countdown', style: TextStyle(color: theme.accent, fontWeight: FontWeight.w900, fontSize: 12.5)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Sekmeler kaydırınca üstte sabit kalır.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  final TabBar tabs;
  final EventTheme theme;
  _TabsHeader(this.tabs, this.theme);

  @override
  double get minExtent => tabs.preferredSize.height;
  @override
  double get maxExtent => tabs.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: theme.colors.first, child: tabs);

  @override
  bool shouldRebuild(covariant _TabsHeader old) => old.tabs != tabs || old.theme != theme;
}
