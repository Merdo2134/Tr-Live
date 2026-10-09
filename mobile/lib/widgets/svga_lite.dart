import 'dart:io' show ZLibCodec;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// SVGA 2.x oynatıcısı (dış paket gerektirmez). Görsel katmanları (konum, ölçek, dönüş, saydamlık) oynatır.
// Desteklenmeyenler: vektör şekiller, kırpma yolu, matte maskeleri ve gömülü ses.

class _Reader {
  final Uint8List d;
  int p;
  final int end;
  _Reader(this.d, [int start = 0, int? stop])
      : p = start,
        end = stop ?? d.length;
  bool get more => p < end;
  int varint() {
    var r = 0;
    var shift = 0;
    while (p < end) {
      final b = d[p++];
      r |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
    }
    return r;
  }

  double f32() {
    final v = ByteData.sublistView(d, p, p + 4).getFloat32(0, Endian.little);
    p += 4;
    return v;
  }

  /// Uzunluk-önekli alanın içeriği için alt okuyucu.
  _Reader sub() {
    final len = varint();
    final r = _Reader(d, p, p + len);
    p += len;
    return r;
  }

  Uint8List bytes() {
    final len = varint();
    final v = Uint8List.sublistView(d, p, p + len);
    p += len;
    return v;
  }

  String str() => String.fromCharCodes(bytes());

  void skip(int wire) {
    if (wire == 0) {
      varint();
    } else if (wire == 1) {
      p += 8;
    } else if (wire == 2) {
      p += varint();
    } else if (wire == 5) {
      p += 4;
    } else {
      p = end;
    }
  }
}

class _SvgaFrame {
  final double alpha;
  final double w;
  final double h;
  final List<double> m; // a b c d tx ty
  _SvgaFrame(this.alpha, this.w, this.h, this.m);
}

class _SvgaSprite {
  final String key;
  final List<_SvgaFrame?> frames;
  _SvgaSprite(this.key, this.frames);
}

class SvgaMovie {
  final double vw;
  final double vh;
  final int fps;
  final int frames;
  final List<_SvgaSprite> sprites;
  final Map<String, ui.Image> images;
  SvgaMovie(this.vw, this.vh, this.fps, this.frames, this.sprites, this.images);

  Duration get duration => Duration(milliseconds: (frames * 1000 / (fps <= 0 ? 20 : fps)).round().clamp(100, 600000));

  void dispose() {
    for (final i in images.values) {
      i.dispose();
    }
  }

  static final Map<String, Uint8List> _cache = {};

  static Future<SvgaMovie> load(String url) async {
    var raw = _cache[url];
    if (raw == null) {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) throw Exception('svga indirilemedi');
      raw = r.bodyBytes;
      if (_cache.length > 3) _cache.remove(_cache.keys.first);
      _cache[url] = raw;
    }
    final data = Uint8List.fromList(ZLibCodec().decode(raw));
    return _parse(data);
  }

  static Future<SvgaMovie> _parse(Uint8List data) async {
    final rd = _Reader(data);
    double vw = 0, vh = 0;
    var fps = 20, frames = 0;
    final rawImages = <String, Uint8List>{};
    final sprites = <_SvgaSprite>[];
    while (rd.more) {
      final tag = rd.varint();
      final field = tag >> 3;
      final wire = tag & 7;
      if (field == 2 && wire == 2) {
        final s = rd.sub();
        while (s.more) {
          final t = s.varint();
          final f = t >> 3;
          final w = t & 7;
          if (f == 1 && w == 5) {
            vw = s.f32();
          } else if (f == 2 && w == 5) {
            vh = s.f32();
          } else if (f == 3 && w == 0) {
            fps = s.varint();
          } else if (f == 4 && w == 0) {
            frames = s.varint();
          } else {
            s.skip(w);
          }
        }
      } else if (field == 3 && wire == 2) {
        final e = rd.sub();
        String? key;
        Uint8List? val;
        while (e.more) {
          final t = e.varint();
          if (t >> 3 == 1 && t & 7 == 2) {
            key = e.str();
          } else if (t >> 3 == 2 && t & 7 == 2) {
            val = e.bytes();
          } else {
            e.skip(t & 7);
          }
        }
        if (key != null && val != null) rawImages[key] = val;
      } else if (field == 4 && wire == 2) {
        sprites.add(_parseSprite(rd.sub(), frames));
      } else {
        rd.skip(wire);
      }
    }
    if (vw <= 0 || vh <= 0 || frames <= 0) throw Exception('svga başlığı geçersiz');
    final images = <String, ui.Image>{};
    for (final e in rawImages.entries) {
      try {
        final codec = await ui.instantiateImageCodec(e.value);
        final fr = await codec.getNextFrame();
        images[e.key] = fr.image;
        codec.dispose();
      } catch (_) {/* görsel çözülemezse o katman çizilmez */}
    }
    return SvgaMovie(vw, vh, fps, frames, sprites, images);
  }

  static _SvgaSprite _parseSprite(_Reader r, int total) {
    var key = '';
    final fr = <_SvgaFrame?>[];
    while (r.more) {
      final t = r.varint();
      final f = t >> 3;
      final w = t & 7;
      if (f == 1 && w == 2) {
        key = r.str();
      } else if (f == 2 && w == 2) {
        fr.add(_parseFrame(r.sub()));
      } else {
        r.skip(w);
      }
    }
    return _SvgaSprite(key, fr);
  }

  static _SvgaFrame? _parseFrame(_Reader r) {
    double alpha = 0, lw = 0, lh = 0;
    var m = <double>[1, 0, 0, 1, 0, 0];
    while (r.more) {
      final t = r.varint();
      final f = t >> 3;
      final w = t & 7;
      if (f == 1 && w == 5) {
        alpha = r.f32();
      } else if (f == 2 && w == 2) {
        final l = r.sub();
        while (l.more) {
          final lt = l.varint();
          final lf = lt >> 3;
          if (lt & 7 == 5) {
            final v = l.f32();
            if (lf == 3) lw = v;
            if (lf == 4) lh = v;
          } else {
            l.skip(lt & 7);
          }
        }
      } else if (f == 3 && w == 2) {
        final tr = r.sub();
        m = <double>[0, 0, 0, 0, 0, 0];
        while (tr.more) {
          final tt = tr.varint();
          final tf = tt >> 3;
          if (tt & 7 == 5) {
            final v = tr.f32();
            if (tf >= 1 && tf <= 6) m[tf - 1] = v;
          } else {
            tr.skip(tt & 7);
          }
        }
      } else {
        r.skip(w);
      }
    }
    if (alpha <= 0 || lw <= 0 || lh <= 0) return null;
    return _SvgaFrame(alpha, lw, lh, m);
  }
}

class _SvgaPainter extends CustomPainter {
  final SvgaMovie movie;
  final Animation<double> t;
  final BoxFit fit;
  _SvgaPainter(this.movie, this.t, this.fit) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final idx = (t.value * movie.frames).floor().clamp(0, movie.frames - 1);
    final fitted = applyBoxFit(fit, Size(movie.vw, movie.vh), size);
    final dst = Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(dst.left, dst.top);
    canvas.scale(dst.width / movie.vw, dst.height / movie.vh);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final s in movie.sprites) {
      if (s.key.endsWith('.matte') || idx >= s.frames.length) continue;
      final f = s.frames[idx];
      final img = movie.images[s.key];
      if (f == null || img == null) continue;
      canvas.save();
      final m = f.m;
      canvas.transform(Float64List.fromList(<double>[m[0], m[1], 0, 0, m[2], m[3], 0, 0, 0, 0, 1, 0, m[4], m[5], 0, 1]));
      paint.color = Color.fromRGBO(255, 255, 255, f.alpha.clamp(0.0, 1.0));
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), Rect.fromLTWH(0, 0, f.w, f.h), paint);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SvgaPainter old) => old.movie != movie || old.fit != fit;
}

class SvgaLite extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final bool repeat;
  final VoidCallback? onDone;
  const SvgaLite({super.key, required this.url, this.fit = BoxFit.contain, this.repeat = false, this.onDone});

  @override
  State<SvgaLite> createState() => _SvgaLiteState();
}

class _SvgaLiteState extends State<SvgaLite> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  SvgaMovie? _movie;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await SvgaMovie.load(widget.url);
      if (!mounted) {
        m.dispose();
        return;
      }
      _c.duration = m.duration;
      setState(() => _movie = m);
      if (widget.repeat) {
        _c.repeat();
      } else {
        _c.forward().whenComplete(() {
          if (mounted) widget.onDone?.call();
        });
      }
    } catch (_) {
      if (mounted) widget.onDone?.call();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _movie?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _movie;
    if (m == null) return const SizedBox.shrink();
    return CustomPaint(painter: _SvgaPainter(m, _c, widget.fit), size: Size.infinite);
  }
}
