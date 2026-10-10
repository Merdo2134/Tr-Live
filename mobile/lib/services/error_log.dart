import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../version.dart';
import 'api.dart';
import 'device_info.dart';

/// Yakalanan hataları (uygulamayı çökertmeden) saklar; Profil > "Hata kaydı"ndan görülüp kopyalanabilir.
/// Ayrıca sunucuya gönderilir (yönetim paneli > Hata kayıtları): telefona dokunmadan sorun görülebilsin.
class ErrorLog {
  ErrorLog._();
  static const _key = 'error_log';
  static const _pendingKey = 'error_pending';
  static const _max = 30;
  static const _maxPending = 20;
  static final List<String> _mem = [];
  static final List<Map<String, String>> _pending = [];
  static Timer? _flushTimer;
  static bool _flushing = false;
  static DateTime? _lastAdd;
  static String? _lastLine;

  static void add(String where, Object error, [StackTrace? stack]) {
    final now = DateTime.now();
    final stackText = (stack ?? StackTrace.empty).toString().split('\n').take(6).join('\n');
    final line = '${now.toIso8601String()} · $where\n$error\n$stackText';
    debugPrint(line);
    // Aynı hata saniyede onlarca kez gelirse (ör. her karede çizim hatası) tek kayıt yeter.
    final head = '$where|$error';
    final last = _lastAdd;
    if (_lastLine == head && last != null && now.difference(last) < const Duration(seconds: 5)) return;
    _lastLine = head;
    _lastAdd = now;
    _mem.add(line);
    if (_mem.length > _max) _mem.removeAt(0);
    _save();
    final message = error.toString();
    _pending.add({
      'source': where.length > 80 ? where.substring(0, 80) : where,
      'message': message.length > 1000 ? message.substring(0, 1000) : message,
      'stack': stackText.length > 2000 ? stackText.substring(0, 2000) : stackText,
      'at': now.toUtc().toIso8601String(),
    });
    if (_pending.length > _maxPending) _pending.removeAt(0);
    _savePending();
    _flushTimer ??= Timer(const Duration(seconds: 20), () {
      _flushTimer = null;
      flush();
    });
  }

  static Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, _mem);
    } catch (_) {/* kayıt yazılamasa da sorun değil */}
  }

  static bool _pendingLoaded = false;

  /// Önceki açılıştan kalan, gönderilemeyen kayıtlar yeni kayıtların önüne eklenir (üzerine yazılıp kaybolmasın).
  static Future<void> _loadPendingOnce() async {
    if (_pendingLoaded) return;
    _pendingLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_pendingKey);
      if (raw == null) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      final old = <Map<String, String>>[];
      for (final e in list) {
        if (e is Map) old.add(e.map((k, v) => MapEntry(k.toString(), v.toString())));
      }
      _pending.insertAll(0, old);
      while (_pending.length > _maxPending) {
        _pending.removeAt(0);
      }
    } catch (_) {/* bozuk kayıt: yoksay */}
  }

  static Future<void> _savePending() async {
    await _loadPendingOnce();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_pendingKey, jsonEncode(_pending));
    } catch (_) {/* yoksay */}
  }

  /// Önceki açılışta gönderilemeyen kayıtları yükleyip gönderir.
  static Future<void> flushSaved() async {
    await _loadPendingOnce();
    await flush();
  }

  /// Bekleyen hataları sunucuya gönderir. Başarısız olursa sonra tekrar denenir; burada yeni hata üretilmez.
  static Future<void> flush() async {
    if (_flushing || _pending.isEmpty || Api.token == null) return;
    _flushing = true;
    final batch = List<Map<String, String>>.of(_pending);
    try {
      await Api.post('/api/client-errors', {'appVersion': kAppVersion, 'device': DeviceInfo.shortName, 'errors': batch});
      _pending.removeWhere(batch.contains);
      await _savePending();
    } catch (_) {/* internet yoksa sonra */} finally {
      _flushing = false;
    }
  }

  static Future<List<String>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getStringList(_key) ?? const [];
      for (final s in saved) {
        if (!_mem.contains(s)) _mem.insert(0, s);
      }
    } catch (_) {/* yoksay */}
    return List.of(_mem.reversed);
  }

  static Future<void> clear() async {
    _mem.clear();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {/* yoksay */}
  }
}
