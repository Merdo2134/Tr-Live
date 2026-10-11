import 'package:flutter/material.dart';
import 'common.dart';

/// "Yayın isim kartı": odanın türü. Oda kartında sol alttaki renkli etiket olarak görünür.
/// Sunucuda odanın ilk etiketi olarak küçük harfle saklanır (ör. "eğlence").
class RoomCategory {
  final String label;
  final List<Color> colors;
  const RoomCategory(this.label, this.colors);

  /// Sunucuya gönderilen / saklanan etiket.
  String get tag => trLower(label);
}

const List<RoomCategory> kRoomCategories = [
  RoomCategory('Sohbet', [Color(0xFF00B4FF), Color(0xFF0066FF)]),
  RoomCategory('Eğlence', [Color(0xFFFF3DCB), Color(0xFFC800FF)]),
  RoomCategory('Müzik', [Color(0xFF8BD400), Color(0xFF2FB500)]),
  RoomCategory('Yarışma', [Color(0xFFB000FF), Color(0xFF7A00FF)]),
  RoomCategory('Film', [Color(0xFFFF2D55), Color(0xFFC40030)]),
  RoomCategory('Oyun', [Color(0xFFFFC400), Color(0xFFFF5A00)]),
];

/// Etikete karşılık gelen tür (büyük/küçük harf ve Türkçe karakter duyarsız); yoksa null.
RoomCategory? roomCategoryOf(String? tag) {
  if (tag == null) return null;
  final t = trLower(tag.trim());
  for (final c in kRoomCategories) {
    if (c.tag == t) return c;
  }
  return null;
}

/// Renkli tür çipi (Figma: yuvarlak, iki renkli geçiş, beyaz kalın yazı).
class CategoryChip extends StatelessWidget {
  final RoomCategory category;
  final double height;
  final bool selected;
  final VoidCallback? onTap;
  const CategoryChip({super.key, required this.category, required this.height, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: height * 0.55),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: category.colors),
        borderRadius: BorderRadius.circular(height / 2),
        border: selected ? Border.all(color: Colors.white, width: 1.6) : null,
      ),
      child: Text(
        category.label,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: TextStyle(color: Colors.white, fontSize: height * 0.56, height: 1.0, fontWeight: FontWeight.w700),
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: chip);
  }
}
