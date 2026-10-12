import 'dart:io' show File, ZLibCodec;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

// SVGA 2.x oynatıcısı (dış paket gerektirmez). Görsel katmanları (konum, ölçek, dönüş, saydamlık) oynatır.
// Desteklenmeyenler: vektör şekiller, kırpma yolu, matte maskeleri ve gömülü ses.

class SvgaReader {
  final Uint8List d;
  int p;
  final int end;
  SvgaReader(this.d, [int start = 0, int? stop])
      : p = start,
        end = stop ?? d.length;
  bool get more => p < end;
  int varint() {
    var r = 0;
    var shift = 0;
    while (p < end) {
      final b = d[p++];
      r |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) break;
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
  SvgaReader sub() {
    final len = varint();
    final r = SvgaReader(d, p, p + len);
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

class SvgaFrame {
  final double alpha;
  final double w;
  final double h;
  final List<double> m; // a b c d tx ty
  SvgaFrame(this.alpha, this.w, this.h, this.m);
}

class SvgaSprite {
  final String key;
  final List<SvgaFrame?> frames;
  SvgaSprite(this.key, this.frames);
}

class SvgaMovie {
  final double vw;
  final double vh;
  final int fps;
  final int frames;
  final List<SvgaSprite> sprites;
  final Map<String, ui.Image> images;
  SvgaMovie(this.vw, this.vh, this.fps, this.frames, this.sprites, this.images);

  Duration get duration => Duration(milliseconds: (frames * 1000 / (fps <= 0 ? 20 : fps)).round().clamp(100, 600000));

  void dispose() {
    for (final i in images.values) {
      i.dispose();
    }
  }

  static Future<SvgaMovie> load({File? file, String? url}) async {
    final Uint8List raw;
    if (file != null) {
      raw = await file.readAsBytes();
    } else {
      final r = await http.get(Uri.parse(url!)).timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) throw Exception('svga indirilemedi (${r.statusCode})');
      raw = r.bodyBytes;
    }
    final data = Uint8List.fromList(ZLibCodec().decode(raw));
    return _parse(data);
  }

  static Future<SvgaMovie> _parse(Uint8List data) async {
    final rd = SvgaReader(data);
    double vw = 0, vh = 0;
    var fps = 20, frames = 0;
    final rawImages = <String, Uint8List>{};
    final sprites = <SvgaSprite>[];
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

  static SvgaSprite _parseSprite(SvgaReader r, int total) {
    var key = '';
    final fr = <SvgaFrame?>[];
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
    return SvgaSprite(key, fr);
  }

  static SvgaFrame? _parseFrame(SvgaReader r) {
    double alpha = 1.0;
    double w = 0.0, h = 0.0;
    List<double> m = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
    while (r.more) {
      final t = r.varint();
      final f = t >> 3;
      final w2 = t & 7;
      if (f == 1 && w2 == 5) {
        alpha = r.f32();
      } else if (f == 2 && w2 == 2) {
        final s = r.sub();
        while (s.more) {
          final t2 = s.varint();
          final f2 = t2 >> 3;
          if (f2 == 1 && (t2 & 7) == 5) w = s.f32();
          else if (f2 == 2 && (t2 & 7) == 5) h = s.f32();
          else s.skip(t2 & 7);
        }
      } else if (f == 3 && w2 == 2) {
        final s = r.sub();
        int idx = 0;
        while (s.more && idx < 6) {
          final t3 = s.varint();
          if (t3 >> 3 == idx + 1 && (t3 & 7) == 5) {
            m[idx++] = s.f32();
          } else {
            s.skip(t3 & 7);
          }
        }
      } else {
        r.skip(w2);
      }
    }
    return SvgaFrame(alpha, w, h, m);
  }
}
