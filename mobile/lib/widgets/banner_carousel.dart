import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import 'app_theme.dart';
import 'net_image.dart';

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
                final url = Api.absoluteUrl(_items[i % _items.length]['imageUrl'] as String?);
                return url == null
                    ? const ColoredBox(color: Pal.surfaceHi)
                    : NetImg(url, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => const ColoredBox(color: Pal.surfaceHi));
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
