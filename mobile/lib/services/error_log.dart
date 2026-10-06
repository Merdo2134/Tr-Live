import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yakalanan hataları (uygulamayı çökertmeden) saklar; Profil > "Hata kaydı"ndan görülüp kopyalanabilir.
class ErrorLog {
  ErrorLog._();
  static const _key = 'error_log';
  static const _max = 30;
  static final List<String> _mem = [];

  static void add(String where, Object error, [StackTrace? stack]) {
    final line = '${DateTime.now().toIso8601String()} · $where\n$error\n${(stack ?? StackTrace.empty).toString().split('\n').take(6).join('\n')}';
    debugPrint(line);
    _mem.add(line);
    if (_mem.length > _max) _mem.removeAt(0);
    _save();
  }

  static Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, _mem);
    } catch (_) {/* kayıt yazılamasa da sorun değil */}
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
