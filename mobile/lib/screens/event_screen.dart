import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/anim_asset.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import '../widgets/fig.dart';
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

/// Etkinlik sayfası (Figma): Kral & Kraliçe, Haftalık Yıldızlar ve Haftanın Çifti. Üstte etkinlik görseli ve
/// "Kural", geri sayım, seçimler (Kral/Kraliçe · Yayıncı/Destekçi + 4 hediye · Bu Hafta/Geçen Hafta),
/// sıralama ve altta kendi sıran. "Kural" sayfasında Kural ve Ödül sekmeleri.
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
  int _week = 0; // 0 bu hafta, -1 geçen hafta
  String _side = 'sender'; // yıldız: sender = Destekçi, receiver = Yayıncı
  String? _thisWeekEnd; // geri sayım her zaman bu haftanın bitişine göre (Geçen Hafta seçiliyken de)

  bool get _royal => widget.group == EventGroup.royal;
  bool get _star => widget.group == EventGroup.star;
  bool get _couple => widget.group == EventGroup.couple;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (_star) {
      try {
        final o = await Api.get('/api/events');
        _stars = listOf(o['events']).where((e) => e['kind'].toString().startsWith('star')).toList();
        if (_stars.isNotEmpty && !_stars.any((s) => s['kind'] == _kind)) _kind = _stars.first['kind'].toString();
      } catch (_) {}
    }
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _error = null);
    try {
      final d = await Api.get('/api/events/$_kind', query: {'week': '$_week', if (_star) 'side': _side});
      if (!mounted || seq != _seq) return;
      setState(() {
        _data = d;
        if (_week == 0 && d['weekEnd'] != null) _thisWeekEnd = d['weekEnd'].toString();
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = errorText(e));
    }
  }

  void _set(VoidCallback change) {
    // Eski liste yeni gelene kadar ekranda kalır (seçim düğmeleri kaybolup gelmesin).
    setState(change);
    _load();
  }

  void _openUser(Map<String, dynamic>? u) {
    final id = u?['id']?.toString();
    if (id == null || u?['isHidden'] == true) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)));
  }

  Color get _bg => _royal ? const Color(0xFF3A0F72) : _star ? const Color(0xFF4A1206) : const Color(0xFF4E1C25);

  String get _hero => _royal ? 'evr_hero' : _star ? 'evs_hero' : 'evc_hero';

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final k = w / 430;
    final d = _data;
    final end = DateTime.tryParse('${_thisWeekEnd ?? d?['weekEnd'] ?? ''}')?.toLocal();
    final list = listOf(d?['leaderboard']);
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: EdgeInsets.only(bottom: 110 * k + MediaQuery.paddingOf(context).bottom), children: [
            _heroBlock(k, list),
            SizedBox(height: 8 * k),
            Center(child: _countdown(k, end)),
            SizedBox(height: 12 * k),
            if (_royal) _royalSwitch(k),
            if (_star) ...[_starSides(k), SizedBox(height: 14 * k), _starGifts(k), SizedBox(height: 10 * k), _weekSwitch(k)],
            if (_couple) _weekSwitch(k),
            SizedBox(height: 12 * k),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
                ]),
              )
            else if (d == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (d['enabled'] != true)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Bu etkinlik şu an kapalı.', style: TextStyle(color: Colors.white70))))
            else if (_royal)
              _royalPanel(k, list)
            else if (_star)
              _starList(k, list)
            else
              _couplePanel(k, list),
          ]),
        ),
        Positioned(
          left: 8,
          top: MediaQuery.paddingOf(context).top + 6,
          child: CircleAvatar(backgroundColor: Colors.black38, child: IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18))),
        ),
        if (d != null && d['enabled'] == true) Positioned(left: 0, right: 0, bottom: 0, child: _footer(k, mapOf(d['me']))),
      ]),
    );
  }

  // ---------------------------------------------------------------- üst görsel
  Widget _heroBlock(double k, List<Map<String, dynamic>> list) {
    final heroH = _royal ? 560 * k : 520 * k;
    return SizedBox(
      height: _royal ? heroH + 40 * k : heroH,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 0, right: 0, top: 0, height: heroH, child: Fig(_hero, fit: BoxFit.cover, alignment: Alignment.topCenter)),
        Positioned(left: 0, right: 0, top: heroH - 60 * k, height: 60 * k, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_bg.withValues(alpha: 0), _bg])))),
        Positioned(
          right: 0,
          top: (_royal ? 360 : _star ? 430 : 290) * k,
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _EventRulesPage(group: widget.group, data: _data ?? const {}, hero: _hero, bg: _bg))),
            child: SizedBox(
              width: 72 * k,
              height: 30 * k,
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(child: Fig(_couple ? 'evc_rule_tag' : 'btn_rules', fit: BoxFit.fill)),
                Padding(padding: EdgeInsets.only(left: 8 * k), child: Text('Kural', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13 * k))),
              ]),
            ),
          ),
        ),
        if (_royal) Positioned(left: 14 * k, right: 14 * k, top: 410 * k, child: _royalWinners(k)),
        if (_star) Positioned(left: 0, right: 0, top: heroH - 50 * k, child: Fig('evs_divider', width: 430 * k, height: 93 * k * 0.6, fit: BoxFit.fill)),
      ]),
    );
  }

  /// Kral & Kraliçe: iki taçlı çerçevede bu haftanın kralı ve kraliçesi.
  Widget _royalWinners(double k) {
    return _RoyalLeaders(k: k, onTap: _openUser);
  }

  Widget _countdown(double k, DateTime? end) {
    final bg = _royal ? 'evr_count' : _couple ? 'evc_count' : null;
    final child = end == null ? const SizedBox() : _Countdown(end: end, color: Colors.white, plain: true, fontSize: 14 * k);
    if (bg == null) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 22 * k, vertical: 4 * k),
        decoration: BoxDecoration(color: const Color(0xFF6B1B0A), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFD9A441))),
        child: child,
      );
    }
    return SizedBox(
      width: (_royal ? 200 : 180) * k,
      height: (_royal ? 46 : 34) * k,
      child: Stack(alignment: Alignment.center, children: [Positioned.fill(child: Fig(bg, fit: BoxFit.fill)), Padding(padding: EdgeInsets.only(top: _royal ? 8 * k : 0), child: child)]),
    );
  }

  Widget _imgButton(String on, String off, bool active, String label, double w, double h, VoidCallback onTap, {double fs = 15}) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(child: Fig(active ? on : off, fit: BoxFit.fill)),
            Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: fs, shadows: const [Shadow(color: Colors.black38, blurRadius: 2)])),
          ]),
        ),
      );

  Widget _royalSwitch(double k) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _imgButton('evr_btn_on', 'evr_btn_off', _kind == 'king', 'KRAL', 150 * k, 63 * k, () { if (!(_kind == 'king')) _set(() => _kind = 'king'); }, fs: 20 * k),
        SizedBox(width: 12 * k),
        _imgButton('evr_btn_on', 'evr_btn_off', _kind == 'queen', 'KRALİÇE', 150 * k, 63 * k, () { if (!(_kind == 'queen')) _set(() => _kind = 'queen'); }, fs: 20 * k),
      ]);

  Widget _weekSwitch(double k) {
    if (_royal) {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _imgButton('evr_pill_on', 'evr_pill_off', _week == 0, 'Bu Hafta', 110 * k, 39 * k, () { if (!(_week == 0)) _set(() => _week = 0); }, fs: 12 * k),
        SizedBox(width: 6 * k),
        _imgButton('evr_pill_on', 'evr_pill_off', _week == -1, 'Geçen Hafta', 110 * k, 39 * k, () { if (!(_week == -1)) _set(() => _week = -1); }, fs: 12 * k),
      ]);
    }
    final on = _star ? 'evs_btn_on' : 'evc_btn_on';
    final off = _star ? 'evs_btn_off' : 'evc_btn_off';
    final w = (_star ? 96 : 140) * k;
    final h = (_star ? 30 : 44) * k;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _imgButton(on, off, _week == 0, 'Bu Hafta', w, h, () { if (!(_week == 0)) _set(() => _week = 0); }, fs: (_star ? 10 : 14) * k),
      SizedBox(width: 14 * k),
      _imgButton(on, off, _week == -1, 'Geçen Hafta', w, h, () { if (!(_week == -1)) _set(() => _week = -1); }, fs: (_star ? 10 : 14) * k),
    ]);
  }

  Widget _starSides(double k) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _imgButton('evs_btn_on', 'evs_btn_off', _side == 'receiver', 'Yayıncı', 140 * k, 43 * k, () { if (!(_side == 'receiver')) _set(() => _side = 'receiver'); }, fs: 15 * k),
        SizedBox(width: 30 * k),
        _imgButton('evs_btn_on', 'evs_btn_off', _side == 'sender', 'Destekçi', 140 * k, 43 * k, () { if (!(_side == 'sender')) _set(() => _side = 'sender'); }, fs: 15 * k),
      ]);

  Widget _starGifts(double k) {
    if (_stars.isEmpty) return const SizedBox();
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (final s in _stars)
        GestureDetector(
          onTap: () { if (!(s['kind'] == _kind)) _set(() => _kind = s['kind'].toString()); },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 3 * k),
            child: SizedBox(
              width: 84 * k,
              height: 104 * k,
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(child: Fig(s['kind'] == _kind ? 'evs_gift_on' : 'evs_gift_off', fit: BoxFit.fill)),
                Padding(padding: EdgeInsets.only(bottom: 6 * k), child: SizedBox(width: 44 * k, height: 44 * k, child: _giftIcon(mapOf(s['gift'])))),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _giftIcon(Map<String, dynamic>? gift) {
    final u = Api.absoluteUrl(gift?['iconUrl'] as String?);
    if (u == null) return const Icon(Icons.card_giftcard, color: Colors.white70);
    return NetImg(u, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.white70));
  }

  String _score(dynamic v) => fmtNumber(v);

  Widget _ring(Map<String, dynamic>? u, double size, String frame, {double inset = 0.24}) => GestureDetector(
        onTap: () => _openUser(u),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            UserAvatar(user: u, radius: size * (0.5 - inset)),
            Positioned.fill(child: IgnorePointer(child: Fig(frame))),
          ]),
        ),
      );

  // ---------------------------------------------------------------- Kral & Kraliçe listesi
  Widget _royalPanel(double k, List<Map<String, dynamic>> list) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12 * k),
      child: Column(children: [
        Fig('evr_panel_top', width: 406 * k, height: 100 * k, fit: BoxFit.fill),
        Transform.translate(
          offset: Offset(0, -40 * k),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 6 * k),
            padding: EdgeInsets.fromLTRB(8 * k, 0, 8 * k, 14 * k),
            decoration: const BoxDecoration(color: Color(0xFF5B0F4E), border: Border.symmetric(vertical: BorderSide(color: Color(0xFFD9A441), width: 2))),
            child: Column(children: [
              _weekSwitch(k),
              SizedBox(height: 12 * k),
              if (list.isEmpty) _empty(),
              for (final e in list) _royalRow(k, e),
            ]),
          ),
        ),
        Transform.translate(offset: Offset(0, -40 * k), child: Fig('evr_panel_bottom', width: 406 * k, height: 58 * k, fit: BoxFit.fill)),
      ]),
    );
  }

  Widget _empty() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(child: Text('Bu hafta henüz sıralamaya giren yok.\nİlk sen ol!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.4))),
      );

  Widget _royalRow(double k, Map<String, dynamic> e) {
    final rank = (e['rank'] as num?)?.toInt() ?? 0;
    final top = rank <= 3;
    final u = mapOf(e['user']);
    return GestureDetector(
      onTap: () => _openUser(u),
      child: SizedBox(
        height: 74 * k,
        child: Stack(children: [
          Positioned.fill(child: Fig(top ? 'evr_row_top' : 'evr_row', fit: BoxFit.fill)),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16 * k, 14 * k, 18 * k, 6 * k),
              child: Row(children: [
                SizedBox(width: 30 * k, child: top ? Fig('rank_$rank', width: 26 * k, height: 23 * k) : Text('$rank', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14 * k))),
                top ? _ring(u, 50 * k, 'evr_rank_frame', inset: 0.2) : UserAvatar(user: u, radius: 18 * k),
                SizedBox(width: 10 * k),
                Expanded(
                  child: Text('${u?['displayName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: top ? const Color(0xFF6B2A00) : Colors.white, fontWeight: FontWeight.w800, fontSize: 14 * k)),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10 * k, vertical: 2 * k),
                  decoration: BoxDecoration(color: const Color(0xFF3C0D6B), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFF1D27A))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_score(e['score']), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12 * k)),
                    SizedBox(width: 3 * k),
                    Fig('icon_diamond', width: 12 * k, height: 10 * k),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- Yıldızlar listesi
  Widget _starList(double k, List<Map<String, dynamic>> list) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14 * k),
      child: Column(children: [
        if (list.isEmpty) _empty(),
        for (final e in list) _starRow(k, e),
      ]),
    );
  }

  Widget _starRow(double k, Map<String, dynamic> e) {
    final rank = (e['rank'] as num?)?.toInt() ?? 0;
    final first = rank == 1;
    final u = mapOf(e['user']);
    return GestureDetector(
      onTap: () => _openUser(u),
      child: Container(
        height: 88 * k,
        margin: EdgeInsets.only(bottom: 10 * k),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: Fig(first ? 'evs_row_top' : 'evs_row', fit: BoxFit.fill)),
          if (first) Positioned(left: 2 * k, top: -6 * k, child: Fig('evs_medal', width: 28 * k, height: 38 * k)),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18 * k),
              child: Row(children: [
                SizedBox(width: 20 * k, child: first ? const SizedBox() : Text('$rank', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14 * k))),
                _ring(u, 66 * k, first ? 'evs_frame_top' : 'evs_frame', inset: 0.2),
                SizedBox(width: 12 * k),
                Expanded(child: Text('${u?['displayName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15 * k))),
                SizedBox(
                  width: 120 * k,
                  height: 30 * k,
                  child: Stack(alignment: Alignment.center, children: [
                    Positioned.fill(child: Fig(first ? 'evs_pill_off' : 'evs_pill_on', fit: BoxFit.fill)),
                    Text(_score(e['score']), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13 * k)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- Haftanın Çifti
  Widget _couplePanel(double k, List<Map<String, dynamic>> list) {
    final top = list.take(3).toList();
    final rest = list.skip(3).toList();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14 * k),
      child: Column(children: [
        if (list.isEmpty) _empty(),
        if (top.isNotEmpty)
          Container(
            padding: EdgeInsets.fromLTRB(4 * k, 34 * k, 4 * k, 30 * k),
            decoration: BoxDecoration(image: DecorationImage(image: Fig.provider('evc_panel'), fit: BoxFit.fill, onError: (_, __) {})),
            child: Column(children: [for (final e in top) _coupleTop(k, e)]),
          ),
        SizedBox(height: 12 * k),
        for (final e in rest) _coupleRow(k, e),
      ]),
    );
  }

  Widget _coupleTop(double k, Map<String, dynamic> e) {
    final rank = (e['rank'] as num?)?.toInt() ?? 1;
    final a = mapOf(e['user']);
    final b = mapOf(e['partner']);
    final left = rank == 1 ? 'evc_frame1f' : rank == 2 ? 'evc_frame2' : 'evc_frame3';
    final right = rank == 1 ? 'evc_frame1m' : rank == 2 ? 'evc_frame2' : 'evc_frame3';
    final band = rank == 1 ? const [Color(0xFF7A1B3E), Color(0xFF3F0E2B)] : rank == 2 ? const [Color(0xFF241A6E), Color(0xFF140F45)] : const [Color(0xFF3E1A4F), Color(0xFF241030)];
    return SizedBox(
      height: 108 * k,
      child: Stack(alignment: Alignment.center, children: [
        Positioned(
          left: 60 * k,
          right: 60 * k,
          top: 26 * k,
          height: 62 * k,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: band),
              border: const Border.symmetric(horizontal: BorderSide(color: Color(0xFFE9C46A), width: 1.4)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_score(e['score']), style: TextStyle(color: const Color(0xFFFFD54F), fontWeight: FontWeight.w800, fontSize: 15 * k)),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                Text(_short('${a?['displayName'] ?? ''}', 9), style: TextStyle(color: Colors.white, fontSize: 11 * k)),
                Text(_short('${b?['displayName'] ?? ''}', 9), style: TextStyle(color: Colors.white, fontSize: 11 * k)),
              ]),
            ]),
          ),
        ),
        Positioned(top: 0, child: Fig('evc_wings', width: 50 * k, height: 45 * k)),
        Positioned(left: 0, child: _ring(a, 92 * k, left, inset: 0.24)),
        Positioned(right: 0, child: _ring(b, 92 * k, right, inset: 0.24)),
      ]),
    );
  }

  Widget _coupleRow(double k, Map<String, dynamic> e) {
    final a = mapOf(e['user']);
    final b = mapOf(e['partner']);
    return Container(
      height: 62 * k,
      margin: EdgeInsets.only(bottom: 10 * k),
      padding: EdgeInsets.symmetric(horizontal: 14 * k),
      decoration: BoxDecoration(color: const Color(0xFF3C1420), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFB98A5A), width: 1.2)),
      child: Row(children: [
        SizedBox(width: 22 * k, child: Text('${e['rank']}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13 * k))),
        SizedBox(
          width: 98 * k,
          height: 44 * k,
          child: Stack(alignment: Alignment.center, children: [
            Positioned(left: 0, child: GestureDetector(onTap: () => _openUser(a), child: UserAvatar(user: a, radius: 22 * k))),
            Positioned(right: 0, child: GestureDetector(onTap: () => _openUser(b), child: UserAvatar(user: b, radius: 22 * k))),
            Fig('evc_heart', width: 22 * k, height: 19 * k),
          ]),
        ),
        SizedBox(width: 12 * k),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a?['displayName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13 * k)),
            Text('${b?['displayName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13 * k)),
          ]),
        ),
        Fig('icon_diamond', width: 12 * k, height: 10 * k),
        SizedBox(width: 3 * k),
        Text(_score(e['score']), style: TextStyle(color: const Color(0xFFFFD54F), fontWeight: FontWeight.w700, fontSize: 12 * k)),
      ]),
    );
  }

  // ---------------------------------------------------------------- altta kendi sıram
  Widget _footer(double k, Map<String, dynamic>? me) {
    final u = Session.me.value;
    final bg = _royal ? 'evr_footer' : _star ? 'evs_footer' : 'evc_footer';
    final dark = _couple;
    return SizedBox(
      height: 96 * k + MediaQuery.paddingOf(context).bottom,
      child: Stack(children: [
        Positioned.fill(child: Fig(bg, fit: BoxFit.fill)),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18 * k, 18 * k, 18 * k, MediaQuery.paddingOf(context).bottom + 8 * k),
            child: Row(children: [
              SizedBox(width: 42 * k, child: Text(me == null ? '99+' : '${me['rank']}', style: TextStyle(color: dark ? const Color(0xFF5B2A12) : Colors.white, fontWeight: FontWeight.w900, fontSize: 15 * k))),
              _royal ? _ring(u, 56 * k, 'evr_me_frame', inset: 0.2) : UserAvatar(user: u, radius: 24 * k),
              SizedBox(width: 10 * k),
              Expanded(child: Text('${u?['displayName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: dark ? const Color(0xFF5B2A12) : Colors.white, fontWeight: FontWeight.w800, fontSize: 15 * k))),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12 * k, vertical: 3 * k),
                decoration: BoxDecoration(color: dark ? const Color(0xFF5B1A22) : const Color(0xFF3C0D6B), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFF1D27A))),
                child: Text(me == null ? '0' : _score(me['score']), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13 * k)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

String _short(String s, int n) => s.characters.length <= n ? s : '${s.characters.take(n)}..';

/// Kral & Kraliçe üst bölümündeki iki taçlı çerçeve: bu haftanın kralı ve kraliçesi (her biri kendi sıralamasından).
class _RoyalLeaders extends StatefulWidget {
  final double k;
  final void Function(Map<String, dynamic>? u) onTap;
  const _RoyalLeaders({required this.k, required this.onTap});

  @override
  State<_RoyalLeaders> createState() => _RoyalLeadersState();
}

class _RoyalLeadersState extends State<_RoyalLeaders> {
  late final Future<List<Map<String, dynamic>?>> _future = _load();

  Future<List<Map<String, dynamic>?>> _load() async {
    final r = await Future.wait([Api.get('/api/events/king'), Api.get('/api/events/queen')]);
    return [for (final x in r) listOf(x['leaderboard']).isEmpty ? null : listOf(x['leaderboard']).first];
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.k;
    final onTap = widget.onTap;
    final w = 402 * k;
    final h = w * 341 / 702;
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: _future,
      builder: (context, snap) {
        final leaders = snap.data ?? const [null, null];
        Widget slot(Map<String, dynamic>? e, double cx) {
          final u = mapOf(e?['user']);
          return Positioned(
            left: cx - 60 * k,
            top: 0,
            width: 120 * k,
            height: h,
            child: GestureDetector(
              onTap: () => onTap(u),
              child: Column(children: [
                SizedBox(height: h * 0.22),
                UserAvatar(user: u, radius: 34 * k),
                SizedBox(height: h * 0.15),
                Text(u == null ? '-' : _short('${u['displayName'] ?? ''}', 12), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12 * k)),
                Text(e == null ? '' : fmtNumber(e['score']), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11 * k)),
              ]),
            ),
          );
        }

        return SizedBox(
          width: w,
          height: h,
          child: Stack(children: [
            slot(leaders[0], w * 0.25),
            slot(leaders[1], w * 0.75),
            Positioned.fill(child: IgnorePointer(child: Fig('evr_winners', fit: BoxFit.fill))),
          ]),
        );
      },
    );
  }
}

/// Kural / Ödül sayfası (etkinliğin kendi tonunda).
class _EventRulesPage extends StatefulWidget {
  final EventGroup group;
  final Map<String, dynamic> data;
  final String hero;
  final Color bg;
  const _EventRulesPage({required this.group, required this.data, required this.hero, required this.bg});

  @override
  State<_EventRulesPage> createState() => _EventRulesPageState();
}

class _EventRulesPageState extends State<_EventRulesPage> {
  int _tab = 0; // 0 Kural, 1 Ödül

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final k = w / 430;
    final d = widget.data;
    final lines = '${d['rules'] ?? ''}'.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final rewards = mapOf(d['rewards']) ?? {};
    final royal = widget.group == EventGroup.royal;
    final couple = widget.group == EventGroup.couple;
    final panel = royal ? const Color(0xFF2F1A8C) : couple ? const Color(0xFF3A2120) : const Color(0xFF2A1A16);
    final title = royal ? (d['kind'] == 'queen' ? 'Kraliçe' : 'Kral') : couple ? 'Çift' : 'Destekçi';
    return Scaffold(
      backgroundColor: widget.bg,
      body: ListView(padding: EdgeInsets.only(bottom: 30 + MediaQuery.paddingOf(context).bottom), children: [
        SizedBox(
          height: 280 * k,
          child: Stack(children: [
            Positioned.fill(child: Fig(widget.hero, fit: BoxFit.cover, alignment: Alignment.topCenter)),
            Positioned(left: 0, right: 0, bottom: 0, height: 70 * k, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [widget.bg.withValues(alpha: 0), widget.bg])))),
            Positioned(
              left: 8,
              top: MediaQuery.paddingOf(context).top + 6,
              child: CircleAvatar(backgroundColor: Colors.black38, child: IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18))),
            ),
          ]),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final (i, label) in [(0, 'KURAL'), (1, 'ÖDÜL')])
            GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8 * k),
                child: SizedBox(
                  width: 150 * k,
                  height: royal ? 40 * k : 44 * k,
                  child: Stack(alignment: Alignment.center, children: [
                    Positioned.fill(child: Fig(royal ? (_tab == i ? 'evr_tab_on' : 'evr_tab_off') : couple ? (_tab == i ? 'evc_btn_on' : 'evc_btn_off') : (_tab == i ? 'evs_btn_on' : 'evs_btn_off'), fit: BoxFit.fill)),
                    Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17 * k)),
                  ]),
                ),
              ),
            ),
        ]),
        SizedBox(height: 16 * k),
        Container(
          margin: EdgeInsets.symmetric(horizontal: 16 * k),
          padding: EdgeInsets.all(16 * k),
          decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFD9A441), width: 2)),
          child: _tab == 0
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: _ribbon('Etkinlik Kuralları', k)),
                  SizedBox(height: 12 * k),
                  for (var i = 0; i < lines.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: 10 * k),
                      child: Text('${i + 1}- ${lines[i]}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13 * k, height: 1.45)),
                    ),
                  SizedBox(height: 6 * k),
                  Center(
                    child: Text('Etkinlik Zamanı\nHer Pazartesi 00:00 - Pazar 23:59:59', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14 * k, height: 1.5)),
                  ),
                ])
              : Column(children: [
                  if (couple) Padding(padding: EdgeInsets.only(bottom: 10 * k), child: Text('Ödüller çiftin iki kişisine de verilir.', style: TextStyle(color: Colors.white70, fontSize: 12 * k))),
                  for (var r = 1; r <= 3; r++) ...[
                    _ribbon('Top$r $title Ödülleri', k),
                    SizedBox(height: 12 * k),
                    if (listOf(rewards['$r']).isEmpty)
                      Padding(padding: EdgeInsets.only(bottom: 16 * k), child: const Text('Ödül tanımlanmadı.', style: TextStyle(color: Colors.white54)))
                    else
                      Padding(
                        padding: EdgeInsets.only(bottom: 18 * k),
                        child: Wrap(alignment: WrapAlignment.center, spacing: 10 * k, runSpacing: 10 * k, children: [for (final x in listOf(rewards['$r'])) _rewardTile(x, k)]),
                      ),
                  ],
                ]),
        ),
      ]),
    );
  }

  Widget _ribbon(String text, double k) => Container(
        padding: EdgeInsets.symmetric(horizontal: 22 * k, vertical: 6 * k),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFF6D47A), Color(0xFFD9A441), Color(0xFFF6D47A)]),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Text(text, style: TextStyle(color: const Color(0xFF5B2A00), fontWeight: FontWeight.w900, fontSize: 15 * k)),
      );

  Widget _rewardTile(Map<String, dynamic> r, double k) {
    Widget art;
    final type = r['type'];
    if (type == 'coins') {
      art = const Fig('coin_crown');
    } else if (type == 'wip') {
      art = FittedBox(child: wipItemArt('badge', (r['level'] as num?)?.toInt() ?? 1, 60));
    } else if (r['wipLevel'] != null) {
      art = FittedBox(child: wipItemArt((r['category'] ?? 'badge').toString(), (r['wipLevel'] as num).toInt(), 70));
    } else {
      final u = Api.absoluteUrl(r['imageUrl'] as String?);
      art = u == null ? const Icon(Icons.card_giftcard, color: Colors.white70, size: 36) : AnimAsset(url: u, repeat: true, cache: false);
    }
    return SizedBox(
      width: 78 * k,
      child: Column(children: [
        Container(
          width: 72 * k,
          height: 72 * k,
          padding: EdgeInsets.all(8 * k),
          decoration: BoxDecoration(
            color: const Color(0xFF7A1020),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD9A441), width: 2),
          ),
          child: Center(child: art),
        ),
        SizedBox(height: 4 * k),
        if (r['kindLabel'] != null) Text('${r['kindLabel']}', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10.5 * k)),
        Text('${r['label'] ?? ''}', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10.5 * k)),
      ]),
    );
  }
}

/// Geri sayım: yalnızca bu küçük yazı her saniye yenilenir (sayfanın geri kalanı yeniden çizilmez).
class _Countdown extends StatefulWidget {
  final DateTime end;
  final Color color;
  /// true: Figma'daki gibi "3 Gün 17:23:59" (simgesiz).
  final bool plain;
  final double fontSize;
  const _Countdown({required this.end, required this.color, this.plain = false, this.fontSize = 12.5});

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _text() {
    var d = widget.end.difference(DateTime.now());
    if (d.isNegative) d = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.inDays} Gün ${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) => Text(
        widget.plain ? _text() : '⏳ ${eventCountdown(widget.end)}',
        style: TextStyle(color: widget.color, fontWeight: FontWeight.w800, fontSize: widget.fontSize),
      );
}
