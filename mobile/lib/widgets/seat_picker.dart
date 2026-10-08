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

/// Koltuk düzeni (Figma "Mikrofon Modu"): her satırdaki koltuk sayısı, yukarıdan aşağıya.
List<int> seatRows(int n) {
  switch (n) {
    case 2:
      return [2];
    case 4:
      return [2, 2];
    case 5:
      return [1, 4];
    case 6:
      return [2, 4];
    case 8:
      return [4, 4];
    case 9:
      return [1, 4, 4];
    case 12:
      return [2, 5, 5];
    case 15:
      return [5, 5, 5];
    case 20:
      return [5, 5, 5, 5];
  }
  final rows = <int>[];
  for (var left = n; left > 0; left -= 4) {
    rows.add(left >= 4 ? 4 : left);
  }
  return rows;
}

/// Oda içinde "Mikrofon Modu" penceresi: koltuk sayısını seçtirir. Seçilen sayıyı döndürür.
Future<int?> showMicModeSheet(BuildContext context, {required int current}) {
  const modes = [2, 4, 5, 6, 8, 9, 12, 15, 20];
  final list = modes.contains(current) ? modes : [...modes, current]..sort();
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) => SafeArea(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: Container(
          color: const Color(0xFF1B1B1F),
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              color: const Color(0xFFFFE100),
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              child: Row(children: [
                const Expanded(child: Text('Mikrofon Modu', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 20))),
                IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.cancel, color: Colors.black, size: 32)),
              ]),
            ),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                padding: const EdgeInsets.all(12),
                mainAxisSpacing: 8,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
                children: [
                  for (final n in list)
                    InkWell(
                      onTap: () => Navigator.pop(c, n),
                      child: Column(children: [
                        Expanded(
                          child: Stack(children: [
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B1B4A), Color(0xFF3A63B8)]),
                                ),
                                padding: const EdgeInsets.all(6),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  for (final r in seatRows(n))
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        for (var i = 0; i < r; i++)
                                          Container(margin: const EdgeInsets.symmetric(horizontal: 2), width: 14, height: 14, decoration: const BoxDecoration(color: Colors.white54, shape: BoxShape.circle)),
                                      ]),
                                    ),
                                ]),
                              ),
                            ),
                            if (n == current)
                              const Positioned(top: 4, right: 4, child: CircleAvatar(radius: 12, backgroundColor: Color(0xFFFFE100), child: Icon(Icons.check, size: 16, color: Colors.black))),
                          ]),
                        ),
                        const SizedBox(height: 6),
                        Text('$n Mikrofon', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                ],
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
