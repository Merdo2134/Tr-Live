import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'inbox_service.dart';
import 'music_service.dart';
import 'room_dock.dart';
import 'session.dart';
import 'socket_service.dart';

class AuthService {
  static const _key = 'token';

  static Future<void> _save(Map<String, dynamic> r) async {
    Api.token = r['token'] as String?;
    final prefs = await SharedPreferences.getInstance();
    if (Api.token != null) await prefs.setString(_key, Api.token!);
    final u = mapOf(r['user']);
    if (u != null) Session.me.value = u;
    SocketService.instance.start();
  }

  static Future<void> login(String username, String password) async =>
      _save(await Api.post('/api/auth/login', {'username': username, 'password': password}));

  static Future<void> register(String username, String password, String displayName) async =>
      _save(await Api.post('/api/auth/register', {'username': username, 'password': password, 'displayName': displayName}));

  static Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    Api.token = prefs.getString(_key);
  }

  /// Yerel oturumu temizler (sunucuya istek atmaz).
  static Future<void> logout() async {
    // Açık (veya küçültülmüş) oda varsa: oturum hâlâ geçerliyken odadan çık, sonra odayı ve müziği kapat.
    // Aksi halde oda arka planda açık kalıyor, sonraki girişte eski oda yeni kullanıcıyla açılıyordu.
    final rid = RoomDock.request.value?.roomId;
    if (rid != null && Api.token != null) {
      try {
        await Api.post('/api/rooms/$rid/leave').timeout(const Duration(seconds: 5));
      } catch (_) {/* çıkış yine de sürer */}
    }
    RoomDock.close();
    try {
      await MusicService.instance.unbind();
    } catch (_) {}
    SocketService.instance.stop();
    Inbox.stop();
    Api.token = null;
    Session.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
