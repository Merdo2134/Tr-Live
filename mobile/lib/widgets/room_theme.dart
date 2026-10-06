import 'package:flutter/material.dart';
import '../services/api.dart';

class RoomThemeDef {
  final String key;
  final String label;
  final List<Color> colors;
  const RoomThemeDef(this.key, this.label, this.colors);
}

/// Sunucudaki izinli tema listesiyle birebir aynı anahtarlar.
const roomThemes = <RoomThemeDef>[
  RoomThemeDef('default', 'Varsayılan', [Color(0xFF14121F), Color(0xFF14121F)]),
  RoomThemeDef('neon', 'Neon', [Color(0xFF12002B), Color(0xFF00334E), Color(0xFF3A0050)]),
  RoomThemeDef('galaxy', 'Galaksi', [Color(0xFF05051A), Color(0xFF1B1347), Color(0xFF3B1E6E)]),
  RoomThemeDef('sunset', 'Gün batımı', [Color(0xFF2B0E1F), Color(0xFF7A2B3A), Color(0xFFB5542E)]),
  RoomThemeDef('forest', 'Orman', [Color(0xFF06170F), Color(0xFF0F3B25), Color(0xFF1C5A3A)]),
  RoomThemeDef('royal', 'Kraliyet', [Color(0xFF1A1033), Color(0xFF3B2470), Color(0xFF8A6A1F)]),
  RoomThemeDef('ocean', 'Okyanus', [Color(0xFF021A2B), Color(0xFF05445E), Color(0xFF0B6E8A)]),
  RoomThemeDef('rose', 'Gül', [Color(0xFF2B0A1C), Color(0xFF6B1F45), Color(0xFFB04A78)]),
];

RoomThemeDef themeOf(String? key) => roomThemes.firstWhere((t) => t.key == key, orElse: () => roomThemes.first);

/// Oda arka planı: özel görsel (WIP 4+) varsa o, yoksa tema degradesi.
class RoomThemeBackground extends StatelessWidget {
  final String? theme;
  final String? imageUrl;
  final Widget child;
  const RoomThemeBackground({super.key, required this.theme, this.imageUrl, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = themeOf(theme);
    final img = Api.absoluteUrl(imageUrl);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: t.colors.length == 1 ? [t.colors.first, t.colors.first] : t.colors),
        image: img == null
            ? null
            : DecorationImage(image: NetworkImage(img), fit: BoxFit.cover, colorFilter: const ColorFilter.mode(Color(0x66000000), BlendMode.darken)),
      ),
      child: child,
    );
  }
}

/// Tema seçici (küçük renk daireleri).
class ThemePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const ThemePicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final t in roomThemes)
        GestureDetector(
          onTap: () => onChanged(t.key),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: t.colors.length == 1 ? [Colors.white24, Colors.white24] : t.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                border: Border.all(color: value == t.key ? Colors.pinkAccent : Colors.white24, width: value == t.key ? 3 : 1),
              ),
            ),
            const SizedBox(height: 2),
            Text(t.label, style: const TextStyle(fontSize: 11)),
          ]),
        ),
    ]);
  }
}
