import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import 'app_theme.dart';
import 'common.dart';

/// Ana sayfa üstündeki banner'lar. Yönetici panelinden eklenir; yoksa hiçbir şey çizilmez.
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
      final r = await Api.get('/api/banners');
      if (!mounted) return;
      setState(() => _items = listOf(r['banners']));
      // İlk gösterilen sayfa her zaman 1. banner olsun.
      final start = _items.isEmpty ? _loopBase : _loopBase - (_loopBase % _items.length);
      _page = start;
      if (_ctl.hasClients) _ctl.jumpToPage(start);
      _timer?.cancel();
      if (_items.length > 1) {
        _timer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (!mounted || !_ctl.hasClients) return;
          _ctl.animateToPage(_page + 1, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
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
    return Padding(
      padding: EdgeInsets.fromLTRB(Resp.margin(MediaQuery.sizeOf(context).width) - 6, 0, Resp.margin(MediaQuery.sizeOf(context).width) - 6, 10),
      child: AspectRatio(
        aspectRatio: 2.4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(children: [
            PageView.builder(
              controller: _ctl,
              itemCount: _loopBase * 2,
              physics: _items.length > 1 ? null : const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final url = Api.absoluteUrl(_items[i % _items.length]['imageUrl'] as String?);
                return url == null
                    ? const ColoredBox(color: Pal.surfaceHi)
                    : Image.network(url, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => const ColoredBox(color: Pal.surfaceHi));
              },
            ),
            if (_items.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < _items.length; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page % _items.length ? 14 : 6,
                      height: 6,
                      decoration: BoxDecoration(color: i == _page % _items.length ? Pal.cyan : Colors.white54, borderRadius: BorderRadius.circular(3)),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
