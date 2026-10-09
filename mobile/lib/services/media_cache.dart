import 'dart:io';
import 'package:http/http.dart' as http;
import 'api.dart';

/// Hediye/çerçeve dosyalarını kullanıcının telefonuna (uygulama önbelleği) bir kez indirir; sonra internetsiz oynatır.
/// Dosya adı sunucudaki benzersiz adrese bağlıdır, aynı dosya ikinci kez indirilmez.
class MediaCache {
  static final Map<String, Future<File>> _inflight = {};
  static Directory? _dir;
  static const int maxBytes = 400 * 1024 * 1024;

  static Future<Directory> _root() async {
    final d = _dir ?? Directory('${Directory.systemTemp.path}/trlive_media');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  static String _name(String url) {
    final path = url.split('?').first;
    final last = path.split('/').last;
    final safe = last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final h = path.hashCode.toUnsigned(32).toRadixString(16);
    return '${h}_$safe';
  }

  /// Dosya telefonda varsa onu, yoksa indirip kaydederek döndürür.
  static Future<File> get(String url) {
    return _inflight.putIfAbsent(url, () async {
      try {
        final dir = await _root();
        final f = File('${dir.path}/${_name(url)}');
        if (await f.exists() && await f.length() > 0) {
          f.setLastModified(DateTime.now()).catchError((_) => null);
          return f;
        }
        final r = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 2));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw Exception('indirilemedi (${r.statusCode})');
        final tmp = File('${f.path}.part');
        await tmp.writeAsBytes(r.bodyBytes, flush: true);
        await tmp.rename(f.path);
        _trim(dir);
        return f;
      } finally {
        _inflight.remove(url);
      }
    });
  }

  /// Arka planda önceden indirir (hediye paneli açılınca); hatalar yutulur.
  static void prefetch(Iterable<String?> urls) {
    for (final u in urls) {
      if (u == null || u.isEmpty) continue;
      get(u).then((_) {}, onError: (_) {});
    }
  }

  static bool _giftsWarmed = false;

  /// Tüm hediye animasyonlarını (bir kez) telefona indirir; hediye gelince anında oynar.
  static Future<void> warmGifts({bool force = false}) async {
    if (_giftsWarmed && !force) return;
    try {
      final r = await Api.get('/api/gifts');
      final list = r['gifts'];
      if (list is! List) return;
      _giftsWarmed = true;
      prefetch([for (final g in list) if (g is Map) Api.absoluteUrl(g['animationUrl'] as String?)]);
    } catch (_) {/* internet yoksa sonra denenir */}
  }

  static Future<void> _trim(Directory dir) async {
    try {
      final files = <File>[];
      var total = 0;
      await for (final e in dir.list()) {
        if (e is File && !e.path.endsWith('.part')) {
          files.add(e);
          total += await e.length();
        }
      }
      if (total <= maxBytes) return;
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      for (final f in files) {
        if (total <= maxBytes * 0.8) break;
        total -= await f.length();
        await f.delete();
      }
    } catch (_) {/* temizlik başarısızsa yoksay */}
  }
}
