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
  final _ctl = PageController();
  Timer? _timer;
  int _page = 0;

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
      _timer?.cancel();
      if (_items.length > 1) {
        _timer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (!mounted || !_ctl.hasClients) return;
          _ctl.animateToPage((_page + 1) % _items.length, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
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
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: AspectRatio(
        aspectRatio: 2.4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(children: [
            PageView.builder(
              controller: _ctl,
              itemCount: _items.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final url = Api.absoluteUrl(_items[i]['imageUrl'] as String?);
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
                      width: i == _page ? 14 : 6,
                      height: 6,
                      decoration: BoxDecoration(color: i == _page ? Pal.cyan : Colors.white54, borderRadius: BorderRadius.circular(3)),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
