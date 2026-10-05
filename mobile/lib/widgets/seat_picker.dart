import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Koltuk düzeni seçici: sayı çipleri ve seçilen düzenin küçük önizlemesi.
class SeatLayoutPicker extends StatelessWidget {
  static const options = [2, 4, 5, 6, 8, 9, 12, 15, 20];
  final int value;
  final ValueChanged<int> onChanged;
  const SeatLayoutPicker({super.key, required this.value, required this.onChanged});

  int get _cols => value <= 5 ? (value <= 2 ? 2 : (value == 4 ? 2 : 3)) : (value == 6 ? 3 : (value == 9 ? 3 : 4));

  @override
  Widget build(BuildContext context) {
    final cols = _cols;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Koltuk düzeni', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final n in options)
          ChoiceChip(
            showCheckmark: false,
            avatar: Icon(Icons.event_seat, size: 16, color: n == value ? Pal.cyan : Pal.textDim),
            label: Text('$n'),
            selected: n == value,
            selectedColor: Pal.surfaceHi,
            side: BorderSide(color: n == value ? Pal.cyan : Pal.outline),
            onSelected: (_) => onChanged(n),
          ),
      ]),
      const SizedBox(height: 10),
      Center(
        child: SizedBox(
          width: 180,
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: cols,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (var i = 0; i < value; i++)
                Container(
                  decoration: BoxDecoration(color: i == 0 ? Pal.cyan.withValues(alpha: 0.35) : Pal.surfaceHi, borderRadius: BorderRadius.circular(8), border: Border.all(color: Pal.outline)),
                  child: Icon(i == 0 ? Icons.star : Icons.event_seat, size: 14, color: i == 0 ? Pal.amber : Pal.textDim),
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}
