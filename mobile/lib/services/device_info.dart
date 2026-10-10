import 'dart:io' show Platform;
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../version.dart';

/// Oturumlarım ekranında görünen cihaz bilgisi. Cihaz kimliği uygulama kurulumuna özel rastgele bir değerdir
/// (telefonun donanım kimliği okunmaz); uygulama silinip kurulunca yenisi üretilir.
class DeviceInfo {
  DeviceInfo._();
  static const _key = 'device_id';
  static Map<String, dynamic>? _cached;

  static Future<String> _installId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(saved)) return saved;
    final rnd = Random.secure();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final id = List.generate(32, (_) => chars[rnd.nextInt(chars.length)]).join();
    await prefs.setString(_key, id);
    return id;
  }

  /// {id, name, platform, appVersion, emulator}. Okunamayan alanlar boş geçilir; hata fırlatmaz.
  static Future<Map<String, dynamic>> collect() async {
    final cached = _cached;
    if (cached != null) return cached;
    String id = '';
    try {
      id = await _installId();
    } catch (_) {/* kayıt okunamadı */}
    String? name;
    bool emulator = false;
    String platform = 'android';
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        final maker = a.manufacturer.trim();
        final model = a.model.trim();
        final full = model.toLowerCase().startsWith(maker.toLowerCase()) ? model : '$maker $model';
        name = '${full.trim()} · Android ${a.version.release}'.trim();
        emulator = !a.isPhysicalDevice;
      } else if (Platform.isIOS) {
        platform = 'ios';
      }
    } catch (_) {/* cihaz bilgisi alınamadı: yalnızca kimlik ve sürüm gönderilir */}
    final out = <String, dynamic>{
      if (id.isNotEmpty) 'id': id,
      if (name != null && name.isNotEmpty) 'name': name.length > 80 ? name.substring(0, 80) : name,
      'platform': platform,
      'appVersion': kAppVersion,
      'emulator': emulator,
    };
    _cached = out;
    return out;
  }

  /// Hata kayıtlarında kullanılan kısa cihaz adı.
  static String get shortName => (_cached?['name'] as String?) ?? 'Android';
}
