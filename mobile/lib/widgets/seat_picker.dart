import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Koltuk düzeni seçici: sayı çipleri ve seçilen düzenin küçük önizlemesi.
class SeatLayoutPicker extends StatelessWidget {
  static const options = [2, 5, 8, 9, 12, 15, 20, 30];
  final int value;
  final ValueChanged<int> onChanged;
  const SeatLayoutPicker({super.key, required this.value, required this.onChanged});

  int get _cols => value <= 5 ? (value <= 2 ? 2 : (value == 4 ? 2 : 3)) : (value == 6 ? 3 : (value == 9 ? 3 : (value >= 30 ? 6 : (value >= 12 ? 5 : 4))));

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

/// Bir koltuk satırı: koltukların yatay merkezleri ve çapı (ikisi de sahne genişliğinin oranı).
class SeatRowSpec {
  final List<double> xs;
  final double dia;
  const SeatRowSpec(this.xs, this.dia);
}

/// Bir mikrofon modunun yerleşimi (Yoho ölçüleri, ekran genişliğine oranla):
/// [topGap]: başlığın altından ilk satırdaki koltuğun üst kenarına uzaklık,
/// [pitch]: art arda iki satırın merkezleri arası uzaklık.
class SeatLayoutSpec {
  final double topGap;
  final List<SeatRowSpec> rows;
  final List<double> pitch;
  const SeatLayoutSpec(this.topGap, this.rows, this.pitch);
}

const _x1 = [0.5];
const _x2 = [0.323, 0.677];
const _x2Top = [0.417, 0.583];
const _x4a = [0.118, 0.372, 0.628, 0.882];
const _x4b = [0.100, 0.367, 0.633, 0.900];
const _x4c = [0.114, 0.371, 0.629, 0.886];
const _x5 = [0.083, 0.2915, 0.5, 0.7085, 0.917];
const _x6 = [0.075, 0.245, 0.415, 0.585, 0.755, 0.925];

/// Yoho ekran görüntülerinden ölçülen yerleşimler.
const Map<int, SeatLayoutSpec> seatLayouts = {
  2: SeatLayoutSpec(0.116, [SeatRowSpec(_x2, 0.141)], []),
  4: SeatLayoutSpec(0.116, [SeatRowSpec(_x2, 0.141), SeatRowSpec(_x2, 0.141)], [0.239]),
  5: SeatLayoutSpec(0.116, [SeatRowSpec(_x1, 0.141), SeatRowSpec(_x4a, 0.131)], [0.239]),
  6: SeatLayoutSpec(0.116, [SeatRowSpec(_x2, 0.141), SeatRowSpec(_x4a, 0.131)], [0.239]),
  8: SeatLayoutSpec(0.112, [SeatRowSpec(_x4b, 0.132), SeatRowSpec(_x4b, 0.132)], [0.289]),
  9: SeatLayoutSpec(0.067, [SeatRowSpec(_x1, 0.150), SeatRowSpec(_x4c, 0.132), SeatRowSpec(_x4c, 0.132)], [0.249, 0.231]),
  12: SeatLayoutSpec(0.104, [SeatRowSpec(_x2Top, 0.1025), SeatRowSpec(_x5, 0.1025), SeatRowSpec(_x5, 0.1025)], [0.181, 0.182]),
  15: SeatLayoutSpec(0.103, [SeatRowSpec(_x5, 0.1025), SeatRowSpec(_x5, 0.1025), SeatRowSpec(_x5, 0.1025)], [0.213, 0.212]),
  20: SeatLayoutSpec(0.103, [SeatRowSpec(_x5, 0.1025), SeatRowSpec(_x5, 0.1025), SeatRowSpec(_x5, 0.1025), SeatRowSpec(_x5, 0.1025)], [0.205, 0.205, 0.205]),
  30: SeatLayoutSpec(0.100, [SeatRowSpec(_x6, 0.093), SeatRowSpec(_x6, 0.093), SeatRowSpec(_x6, 0.093), SeatRowSpec(_x6, 0.093), SeatRowSpec(_x6, 0.093)], [0.181, 0.181, 0.181, 0.181]),
};

/// Bilinmeyen sayı gelirse en yakın büyük mod kullanılır.
SeatLayoutSpec seatLayoutFor(int n) {
  final exact = seatLayouts[n];
  if (exact != null) return exact;
  final keys = seatLayouts.keys.toList()..sort();
  for (final k in keys) {
    if (k >= n) return seatLayouts[k]!;
  }
  return seatLayouts[30]!;
}

/// Her satırdaki koltuk sayısı, yukarıdan aşağıya.
List<int> seatRows(int n) => [for (final r in seatLayoutFor(n).rows) r.xs.length];

/// Mikrofon modu küçük önizlemesi (Yoho: gece sokağı fotoğrafı üstünde yarı saydam + koltuklar).
class SeatModeThumb extends StatelessWidget {
  final int n;
  const SeatModeThumb(this.n, {super.key});

  @override
  Widget build(BuildContext context) {
    final spec = seatLayoutFor(n);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      // Koltuk alanının yüksekliği (genişliğe oranla) önizlemeye sığdırılır, dikeyde ortalanır.
      var span = spec.rows.first.dia;
      for (final p in spec.pitch) {
        span += p;
      }
      span += spec.rows.last.dia * 0.5 - spec.rows.first.dia * 0.5;
      final scale = ((h * 0.78) / (span * w)).clamp(0.0, 0.92);
      final sw = w * scale; // önizlemedeki "sahne genişliği"
      final ox = (w - sw) / 2;
      final oy = (h - span * sw) / 2;
      final dots = <Widget>[];
      var cy = oy + spec.rows.first.dia * sw / 2;
      for (var r = 0; r < spec.rows.length; r++) {
        final row = spec.rows[r];
        final d = (row.dia * sw * 1.25).clamp(8.0, 40.0).toDouble();
        for (final x in row.xs) {
          dots.add(Positioned(
            left: ox + x * sw - d / 2,
            top: cy - d / 2,
            width: d,
            height: d,
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.22), border: Border.all(color: Colors.white54, width: 1)),
              child: Icon(Icons.add, size: d * 0.62, color: Colors.white),
            ),
          ));
        }
        if (r < spec.pitch.length) cy += spec.pitch[r] * sw;
      }
      return Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1B2733), Color(0xFF2B1A22), Color(0xFF0E0F14)]),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        // Bokeh ışıkları
        for (final b in const [[0.25, 0.18, Color(0x66FF7043)], [0.62, 0.12, Color(0x55FFB74D)], [0.8, 0.35, Color(0x4426C6DA)], [0.4, 0.62, Color(0x55E53935)], [0.15, 0.55, Color(0x4429B6F6)]])
          Positioned(
            left: (b[0] as double) * w - 9,
            top: (b[1] as double) * h - 9,
            child: Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: b[2] as Color, boxShadow: [BoxShadow(color: b[2] as Color, blurRadius: 10)])),
          ),
        ...dots,
      ]);
    });
  }
}

/// Oda içinde "Mikrofon modu" penceresi (Yoho). Pencere açık kalır; seçim [onSelect] ile uygulanır,
/// istek modu [onRequestMode] ile değişir. İkisi de başarılıysa true döndürmelidir.
Future<void> showMicModeSheet(
  BuildContext context, {
  required int current,
  required bool requestMode,
  required Future<bool> Function(int n) onSelect,
  required Future<bool> Function(bool on) onRequestMode,
}) {
  const modes = [2, 5, 8, 9, 12, 15, 20, 30];
  var cur = current;
  var req = requestMode;
  var busy = false;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) {
        Future<void> pick(int n) async {
          if (busy || n == cur) return;
          if (n < cur) {
            final ok = await showDialog<bool>(
              context: c,
              builder: (d) => AlertDialog(
                backgroundColor: Colors.white,
                title: const Text('Emin misin?', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
                content: const Text('Mikrofon modunu değiştirdikten sonra, mikrofondaki bazı kullanıcılar otomatik olarak kaldırılacaktır. Geçiş yapmayı onaylıyor musunuz?', style: TextStyle(color: Colors.black87)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w800))),
                  TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Onayla', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w800))),
                ],
              ),
            );
            if (ok != true || !c.mounted) return;
          }
          setS(() => busy = true);
          final done = await onSelect(n);
          if (!c.mounted) return;
          setS(() {
            busy = false;
            if (done) cur = n;
          });
        }

        Future<void> toggleReq() async {
          if (busy) return;
          setS(() => busy = true);
          final done = await onRequestMode(!req);
          if (!c.mounted) return;
          setS(() {
            busy = false;
            if (done) req = !req;
          });
        }

        return SafeArea(
          top: false,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: Container(
              color: Colors.white,
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.72),
              child: Stack(children: [
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF6A8DFF), Color(0xFF5B7CFA), Color(0xFF8B6CF3)])),
                    child: const Text('Mikrofon modu', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 19)),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Text(
                      'İpuçları: 1. Koltuk sayısını azaltırsan fazla koltuklardaki kullanıcılar dinleyiciye iner;\n2. İstek modu açıkken kullanıcılar mikrofona ancak yetkili onayıyla çıkar;',
                      style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ),
                  Flexible(
                    child: GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: 3,
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.80,
                      children: [
                        for (final n in modes)
                          GestureDetector(
                            onTap: () => pick(n),
                            child: Column(children: [
                              Expanded(
                                child: Stack(children: [
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: n == cur ? const Color(0xFF22C55E) : Colors.transparent, width: 3),
                                      ),
                                      padding: const EdgeInsets.all(1),
                                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: SeatModeThumb(n)),
                                    ),
                                  ),
                                  if (n == cur)
                                    const Positioned(top: 6, right: 6, child: CircleAvatar(radius: 12, backgroundColor: Color(0xFF22C55E), child: Icon(Icons.check, size: 17, color: Colors.white))),
                                ]),
                              ),
                              const SizedBox(height: 6),
                              Text('$n Mikrofon', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 15)),
                            ]),
                          ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: toggleReq,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      child: Row(children: [
                        Icon(req ? Icons.check_circle : Icons.radio_button_unchecked, color: req ? const Color(0xFF22C55E) : Colors.black26, size: 24),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Mikrofonda olmak için istekte bulunmanız gerekiyor.', style: TextStyle(color: Colors.black54, fontSize: 14))),
                      ]),
                    ),
                  ),
                ]),
                if (busy)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x33FFFFFF),
                      child: Center(child: CircleAvatar(radius: 28, backgroundColor: Colors.white, child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF22C55E))))),
                    ),
                  ),
              ]),
            ),
          ),
        );
      },
    ),
  );
}
