import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Kırpma biçimi: çerçeve oranı (genişlik / yükseklik), çıktı genişliği (px) ve daire kılavuzu.
/// Çıktı her zaman JPEG'dir (veritabanında az yer kaplar).
class CropSpec {
  final double aspect;
  final int outWidth;
  final bool circle;
  final String title;
  const CropSpec(this.aspect, this.outWidth, {this.circle = false, required this.title});

  /// Profil fotoğrafı: kare, daire kılavuzlu.
  static const avatar = CropSpec(1, 720, circle: true, title: 'Profil fotoğrafını ayarla');

  /// Profil kapak fotoğrafı: profil sayfasındaki alanla aynı oran (genişlik × 0,62).
  static const profileCover = CropSpec(1 / 0.62, 1080, title: 'Kapak fotoğrafını ayarla');

  /// Oda fotoğrafı: oda kartındaki kare görsel.
  static const roomCover = CropSpec(1, 720, title: 'Oda fotoğrafını ayarla');

  /// Ana sayfa bannerı: 3:1.
  static const banner = CropSpec(3, 1200, title: 'Bannerı ayarla');

  /// Mesajlar > duyuru kartı görseli (kartta 1,8:1).
  static const announcement = CropSpec(1.8, 1080, title: 'Duyuru görselini ayarla');

  int get outHeight => (outWidth / aspect).round();
}

/// Kırpma ekranını açar; kullanıcı "Kullan" derse JPEG baytlarını, vazgeçerse null döndürür.
Future<Uint8List?> cropImage(BuildContext context, Uint8List bytes, CropSpec spec) async {
  ui.Image? source;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    source = (await codec.getNextFrame()).image;
    codec.dispose();
  } catch (_) {
    source = null;
  }
  if (source == null) return null;
  final ui.Image decoded = source;
  if (!context.mounted) {
    decoded.dispose();
    return null;
  }
  // Görsel, kırpma ekranı tamamen kapanınca (State.dispose) bırakılır: kapanma animasyonu sırasında hâlâ çiziliyor.
  return Navigator.of(context, rootNavigator: true).push<Uint8List>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => _CropScreen(source: decoded, spec: spec)),
  );
}

class _CropScreen extends StatefulWidget {
  final ui.Image source;
  final CropSpec spec;
  const _CropScreen({required this.source, required this.spec});

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  Rect _frame = Rect.zero; // kırpma çerçevesi (ekran koordinatı)
  double _base = 1; // görselin çerçeveyi tam örttüğü ölçek
  double _zoom = 1; // kullanıcının yakınlaştırması (1..5)
  Offset _offset = Offset.zero; // görselin sol üst köşesi (ekran koordinatı)
  Size _laidOut = Size.zero;
  bool _busy = false;

  @override
  void dispose() {
    widget.source.dispose();
    super.dispose();
  }

  // Sıkıştırma hareketinin başlangıç durumu
  double _startZoom = 1;
  Offset _startFocal = Offset.zero;
  Offset _startOffset = Offset.zero;

  double get _imgW => widget.source.width.toDouble();
  double get _imgH => widget.source.height.toDouble();
  double get _scale => _base * _zoom;

  /// Ekran ölçüsü değişince (ilk açılış, döndürme) çerçeve yeniden kurulur ve görsel ortalanır.
  void _layout(Size size) {
    if (size == _laidOut) return;
    _laidOut = size;
    const pad = 20.0;
    final maxW = size.width - pad * 2;
    final maxH = size.height * 0.62;
    var fw = maxW;
    var fh = fw / widget.spec.aspect;
    if (fh > maxH) {
      fh = maxH;
      fw = fh * widget.spec.aspect;
    }
    _frame = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.46), width: fw, height: fh);
    _base = math.max(_frame.width / _imgW, _frame.height / _imgH);
    _zoom = 1;
    _offset = Offset(_frame.center.dx - _imgW * _scale / 2, _frame.center.dy - _imgH * _scale / 2);
  }

  /// Görsel çerçevenin dışına kaçmasın: her zaman çerçeveyi tamamen örter.
  Offset _clamp(Offset o) {
    final w = _imgW * _scale;
    final h = _imgH * _scale;
    // Kayan nokta payı: alt sınır üst sınırı birkaç milyarda bir geçebilir (clamp hata vermesin).
    final minX = math.min(_frame.right - w, _frame.left);
    final minY = math.min(_frame.bottom - h, _frame.top);
    return Offset(o.dx.clamp(minX, _frame.left).toDouble(), o.dy.clamp(minY, _frame.top).toDouble());
  }

  void _onStart(ScaleStartDetails d) {
    _startZoom = _zoom;
    _startFocal = d.focalPoint;
    _startOffset = _offset;
  }

  void _onUpdate(ScaleUpdateDetails d) {
    setState(() {
      final z = (_startZoom * d.scale).clamp(1.0, 5.0).toDouble();
      // Parmakların altındaki görsel noktası parmakların altında kalır (yakınlaştırma + kaydırma birlikte).
      final anchor = (_startFocal - _startOffset) / (_base * _startZoom);
      _zoom = z;
      _offset = _clamp(d.focalPoint - anchor * _scale);
    });
  }

  Future<void> _done() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = _scale;
      final src = Rect.fromLTWH((_frame.left - _offset.dx) / s, (_frame.top - _offset.dy) / s, _frame.width / s, _frame.height / s)
          .intersect(Rect.fromLTWH(0, 0, _imgW, _imgH));
      // Kaynak görsel küçükse büyütülmez (bulanıklaşmasın); çıktı en fazla kaynak çözünürlüğü kadar olur.
      final outW = math.min(math.max(src.width.round(), 64), widget.spec.outWidth);
      final outH = math.max((outW / widget.spec.aspect).round(), 32);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.black, BlendMode.src);
      canvas.drawImageRect(widget.source, src, Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()), Paint()..filterQuality = FilterQuality.high);
      final picture = recorder.endRecording();
      final image = await picture.toImage(outW, outH);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (data == null) throw StateError('Görsel işlenemedi');
      final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final jpg = await compute(_encodeJpg, (rgba, outW, outH));
      if (mounted) Navigator.of(context).pop(jpg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fotoğraf hazırlanamadı: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, box) {
        _layout(box.biggest);
        final w = _imgW * _scale;
        final h = _imgH * _scale;
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onStart,
              onScaleUpdate: _onUpdate,
              child: Stack(children: [
                Positioned(left: _offset.dx, top: _offset.dy, width: w, height: h, child: RawImage(image: widget.source, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
                Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _MaskPainter(_frame, widget.spec.circle)))),
              ]),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(children: [
                Text(widget.spec.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Sürükle ve iki parmakla büyüt/küçült', style: TextStyle(color: Colors.white60, fontSize: 13)),
              ]),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('Vazgeç', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
                      onPressed: _busy ? null : _done,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Text('Kullan', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

/// Çerçevenin dışını karartır; çerçeveye ince beyaz kenar (profil fotoğrafında daire) çizer.
class _MaskPainter extends CustomPainter {
  final Rect frame;
  final bool circle;
  _MaskPainter(this.frame, this.circle);

  @override
  void paint(Canvas canvas, Size size) {
    final hole = Path();
    if (circle) {
      hole.addOval(frame);
    } else {
      hole.addRect(frame);
    }
    final mask = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), hole);
    canvas.drawPath(mask, Paint()..color = const Color(0xA6000000));
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(hole, line);
    if (circle) canvas.drawRect(frame, line..color = Colors.white24);
  }

  @override
  bool shouldRepaint(_MaskPainter old) => old.frame != frame || old.circle != circle;
}

/// Ayrı iş parçacığında: ham RGBA → JPEG (%88 kalite).
Uint8List _encodeJpg((Uint8List, int, int) a) {
  final (rgba, w, h) = a;
  final image = img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, bytesOffset: rgba.offsetInBytes, numChannels: 4, rowStride: w * 4);
  return img.encodeJpg(image, quality: 88);
}
