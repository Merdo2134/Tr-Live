import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/event_screen.dart';
import '../services/api.dart';
import 'app_theme.dart';
import 'common.dart';

/// Ana sayfa üstündeki banner'lar: haftalık etkinlik kartları (Çift, Kral & Kraliçe, Yıldız; dokununca etkinlik
/// sayfası açılır) ve yönetici panelinden eklenen banner'lar (bağlantısı varsa dokununca açılır).
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  List<Map<String, dynamic>> _items = [];
  // Sonsuz döngü: çok büyük sayfa sayısının ortasından başlanır, hep ileri kayar; sondan sonra yine baştaki banner gelir.
  static const _loopBase = 10000;
  late final PageController _ctl = PageController(initialPage: _loopBase);
  Timer? _timer;
  int _page = _loopBase;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Etkinlikler: açık olan her grup için bir kart (gruptaki ilk liderle).
      final events = <Map<String, dynamic>>[];
      try {
        final ov = await Api.get('/api/events');
        final ev = listOf(ov['events']);
        Map<String, dynamic>? first(bool Function(String k) test) => ev.where((e) => test(e['kind'].toString())).firstOrNull;
        final couple = first((k) => k == 'couple');
        final royal = first((k) => k == 'king' || k == 'queen');
        final star = first((k) => k.startsWith('star'));
        final ws = DateTime.tryParse((ov['weekStart'] ?? '').toString())?.toLocal();
        final we = DateTime.tryParse((ov['weekEnd'] ?? '').toString())?.toLocal();
        Map<String, dynamic> card(EventGroup g, Map<String, dynamic> e) => {'event': g, 'kind': e['kind'], 'leader': e['leader'], 'ws': ws, 'we': we};
        if (couple != null) events.add(card(EventGroup.couple, couple));
        if (royal != null) events.add(card(EventGroup.royal, royal));
        if (star != null) events.add(card(EventGroup.star, star));
      } catch (_) {}
      // Banner'lar alınamasa da etkinlik kartları gösterilir.
      var banners = <Map<String, dynamic>>[];
      try {
        banners = listOf((await Api.get('/api/banners'))['banners']);
      } catch (_) {}
      if (!mounted) return;
      setState(() => _items = [...events, ...banners]);
      // İlk gösterilen sayfa her zaman 1. banner olsun.
      final start = _items.isEmpty ? _loopBase : _loopBase - (_loopBase % _items.length);
      _page = start;
      // Sayfa görünümü bu karede kuruluyor: atlama bir sonraki karede yapılır (önceden kurulmadan atlanmaya çalışılıyor,
      // sayfa ile sayaç uyuşmuyor ve banner dokunulana kadar dönmüyordu).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ctl.hasClients) _ctl.jumpToPage(start);
      });
      _timer?.cancel();
      if (_items.length > 1) {
        _timer = Timer.periodic(const Duration(seconds: 4), (_) {
          if (!mounted || !_ctl.hasClients) return;
          // Kullanıcı o an kaydırıyorsa bekle; konum her zaman denetleyiciden okunur.
          if (_ctl.position.isScrollingNotifier.value) return;
          final cur = _ctl.page?.round() ?? _page;
          _ctl.animateToPage(cur + 1, duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
        });
      }
    } catch (_) {
      // Banner olmasa da ana sayfa çalışır.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    // Yoho: kenarlardan genişliğin %3,7'si içeride, en/boy ≈ 3:1, köşeler hafif yuvarlak.
    final m = homeMargin(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(m, 0, m, 0),
      child: AspectRatio(
        aspectRatio: 3.0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(children: [
            PageView.builder(
              controller: _ctl,
              itemCount: _loopBase * 2,
              physics: _items.length > 1 ? null : const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final item = _items[i % _items.length];
                final group = item['event'];
                if (group is EventGroup) {
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventScreen(group: group, initialKind: item['kind']?.toString()))),
                    child: _EventBanner(group: group, leader: mapOf(item['leader']), weekStart: item['ws'] as DateTime?, weekEnd: item['we'] as DateTime?),
                  );
                }
                final url = Api.absoluteUrl(item['imageUrl'] as String?);
                final link = Uri.tryParse((item['linkUrl'] ?? '').toString());
                final img = url == null
                    ? const ColoredBox(color: Pal.surfaceHi)
                    : NetImg(url, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => const ColoredBox(color: Pal.surfaceHi));
                if (link == null || !(link.scheme == 'https' || link.scheme == 'http')) return img;
                return GestureDetector(onTap: () => launchUrl(link, mode: LaunchMode.externalApplication), child: img);
              },
            ),
            if (_items.length > 1)
              Positioned(
                bottom: 5,
                left: 0,
                right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < _items.length; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(color: i == _page % _items.length ? Colors.white : Colors.white38, shape: BoxShape.circle),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Etkinlik banner'ı: etkinliğin görseli; altta şimdiki lider (varsa) küçük bir şeritte.
class _EventBanner extends StatelessWidget {
  final EventGroup group;
  final Map<String, dynamic>? leader;
  final DateTime? weekStart;
  final DateTime? weekEnd;
  const _EventBanner({required this.group, this.leader, this.weekStart, this.weekEnd});

  @override
  Widget build(BuildContext context) {
    final t = EventTheme.of(group);
    final u = mapOf(leader?['user']);
    final p = mapOf(leader?['partner']);
    final leaderName = u == null ? null : (p == null ? '${u['displayName']}' : '${u['displayName']} & ${p['displayName']}');
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      return Stack(children: [
        Positioned.fill(child: EventBannerImage(group: group, weekStart: weekStart, weekEnd: weekEnd)),
        if (leaderName != null)
          Positioned(
            right: h * 0.06,
            bottom: h * 0.1,
            child: Container(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.36),
              padding: EdgeInsets.symmetric(horizontal: h * 0.06, vertical: h * 0.025),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(h * 0.1), border: Border.all(color: t.accent.withValues(alpha: 0.7))),
              child: Text('👑 $leaderName', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: h * 0.085, color: t.accent, fontWeight: FontWeight.w800)),
            ),
          ),
      ]);
    });
  }
}
