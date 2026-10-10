import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../version.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

List<Map<String, dynamic>> listOf(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

Map<String, dynamic>? mapOf(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;

class Api {
  static const baseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000');
  static const _timeout = Duration(seconds: 20);

  /// Kısa ömürlü erişim token'ı (1 saat). Eski sürümden kalma oturumlarda 30 günlük tek token olabilir.
  static String? token;

  /// Yenileme token'ı: erişim token'ı dolunca yenisini almak için. Her yenilemede değişir.
  static String? refreshToken;

  /// Erişim token'ının dolacağı an (cihaz saatinden bağımsız: yanıt anı + süre).
  static DateTime? tokenExpiresAt;

  /// Oturum gerçekten sona erdiğinde (yenileme de reddedildi) çağrılır; main.dart giriş ekranına yönlendirir.
  static void Function()? onUnauthorized;

  /// Token çifti yenilenince kalıcı olarak kaydetmek için (AuthService).
  static Future<void> Function()? onTokensChanged;

  /// Sunucu zorunlu güncelleme istediğinde (HTTP 426).
  static void Function(String message, String? url)? onUpdateRequired;

  static Future<bool>? _refreshing;

  static Map<String, String> _headers([String contentType = 'application/json']) => {
        'Content-Type': contentType,
        'X-App-Version': kAppVersion,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Giriş/yenileme yanıtındaki token alanlarını uygular. Yanıtta olmayan alan eski değerini korur.
  static void setTokens(Map<String, dynamic> r) {
    final t = r['token'];
    if (t is String && t.isNotEmpty) token = t;
    final rt = r['refreshToken'];
    if (rt is String && rt.isNotEmpty) refreshToken = rt;
    final exp = r['expiresIn'];
    tokenExpiresAt = exp is num ? DateTime.now().add(Duration(seconds: exp.toInt())) : null;
  }

  static void clearTokens() {
    token = null;
    refreshToken = null;
    tokenExpiresAt = null;
  }

  /// Erişim token'ını yeniler. true: yenilendi · false: oturum gerçekten bitti (çıkış gerekir).
  /// Ağ hatasında [ApiException] fırlatır; bu durumda oturum KAPATILMAZ (internet gelince tekrar denenir).
  /// Aynı anda gelen çağrılar tek bir yenileme isteğini paylaşır (yenileme token'ı tek kullanımlıktır).
  static Future<bool> refreshSession() {
    if (refreshToken == null) return Future.value(false);
    return _refreshing ??= _doRefresh();
  }

  static Future<bool> _doRefresh() async {
    await Future<void>.delayed(Duration.zero); // _refreshing atanmadan iş bitmesin
    try {
      final rt = refreshToken;
      if (rt == null) return false;
      http.Response r;
      try {
        r = await http
            .post(_uri('/api/auth/refresh'),
                headers: {'Content-Type': 'application/json', 'X-App-Version': kAppVersion},
                body: jsonEncode({'refreshToken': rt, 'device': {'appVersion': kAppVersion}}))
            .timeout(_timeout);
      } on TimeoutException {
        throw ApiException('Sunucu yanıt vermedi. Lütfen tekrar deneyin.');
      } catch (_) {
        throw ApiException('Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
      }
      if (r.statusCode == 200) {
        dynamic data;
        try {
          data = jsonDecode(utf8.decode(r.bodyBytes));
        } catch (_) {
          data = null;
        }
        if (data is! Map || data['token'] is! String) throw ApiException('Oturum yenilenemedi. Lütfen tekrar deneyin.');
        // Başka bir istek bu arada çıkış yaptırdıysa yeni token'lar yazılmaz.
        if (refreshToken != rt) return false;
        setTokens(Map<String, dynamic>.from(data));
        try {
          await onTokensChanged?.call();
        } catch (_) {/* kayıt yazılamasa da bu oturum çalışır */}
        return true;
      }
      if (r.statusCode == 401 || r.statusCode == 403) return false;
      throw ApiException('Oturum yenilenemedi (${r.statusCode}). Lütfen tekrar deneyin.', r.statusCode);
    } finally {
      _refreshing = null;
    }
  }

  /// Erişim token'ının süresi 2 dakikadan az kaldıysa önceden yeniler (gereksiz 401 turu olmasın).
  static Future<void> ensureFreshToken() async {
    final exp = tokenExpiresAt;
    if (token == null || refreshToken == null || exp == null) return;
    if (DateTime.now().isBefore(exp.subtract(const Duration(minutes: 2)))) return;
    await refreshSession();
  }

  static Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$baseUrl$path');
    return query == null || query.isEmpty ? u : u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  /// Sunucu "/uploads/xyz.png" gibi göreli adres döndürebilir.
  static String? absoluteUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return url.startsWith('http') ? url : '$baseUrl$url';
  }

  static Future<Map<String, dynamic>> _send(Future<http.Response> Function() request, {Duration? timeout, bool mutating = false, bool retried = false}) async {
    if (!retried) {
      try {
        await ensureFreshToken();
      } catch (_) {/* ağ hatası: istek yine denenir, hata oradan gösterilir */}
    }
    final sentToken = token; // istek bu token ile gidiyor (yanıt gelene kadar değişebilir)
    http.Response r;
    try {
      r = await request().timeout(timeout ?? _timeout);
    } on TimeoutException {
      // Değişiklik yapan istekte (hediye, satın alma…) sunucu işlemi yapmış olabilir: körü körüne tekrar ettirme.
      throw ApiException(mutating
          ? 'Sunucu zamanında yanıt vermedi; işlem gerçekleşmiş olabilir. Tekrar denemeden önce bakiyeni/sonucu kontrol et.'
          : 'Sunucu yanıt vermedi. Lütfen tekrar deneyin.');
    } catch (_) {
      throw ApiException('Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    }
    if (r.statusCode == 401 && token != null) {
      // Başka bir istek bu arada token'ı yeniledi: yeni token'la bir kez daha dene.
      if (!retried && token != sentToken) return _send(request, timeout: timeout, mutating: mutating, retried: true);
      // Erişim token'ının süresi dolmuş olabilir: bir kez yenileyip isteği tekrarla. 401'de sunucu isteği işlemez,
      // bu yüzden hediye gibi değişiklik yapan istekleri tekrarlamak güvenlidir.
      if (!retried && refreshToken != null) {
        if (await refreshSession()) return _send(request, timeout: timeout, mutating: mutating, retried: true);
      }
      // Yalnızca reddedilen token hâlâ geçerli oturumsa çıkış yapılır (bu arada çıkış/yeniden giriş olduysa dokunulmaz).
      if (token != null && token == sentToken) onUnauthorized?.call();
    }
    final message = data is Map && data['message'] is String ? data['message'] as String : 'İstek başarısız (${r.statusCode}).';
    if (r.statusCode == 426) {
      final url = data is Map && data['updateUrl'] is String ? data['updateUrl'] as String : null;
      onUpdateRequired?.call(message, url);
    }
    throw ApiException(message, r.statusCode);
  }

  static Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send(() => http.get(_uri(path, query), headers: _headers()));

  static Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) =>
      _send(() => http.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})), mutating: true);

  /// Para işlemleri için tek seferlik anahtar (Idempotency-Key).
  static String newIdempotencyKey() {
    final rnd = Random.secure();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(32, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Para harcayan istek (hediye, satın alma, bozdurma ...). Sunucu aynı anahtarla gelen isteği bir kez işler;
  /// bu yüzden ağ hatası / zaman aşımında aynı anahtarla bir kez kendiliğinden tekrar denenir — iki kez ödenmez.
  /// [key] verilirse o kullanılır (ör. ağ hatasından sonra kullanıcı aynı işlemi tekrar denediğinde).
  static Future<Map<String, dynamic>> postOnce(String path, Map<String, dynamic> body, {String? key}) async {
    final k = key ?? newIdempotencyKey();
    Future<http.Response> req() => http.post(_uri(path), headers: {..._headers(), 'Idempotency-Key': k}, body: jsonEncode(body));
    try {
      return await _send(req, mutating: true);
    } on ApiException catch (e) {
      if (e.statusCode != null) rethrow; // sunucu yanıt verdi: sonuç kesin
      await Future<void>.delayed(const Duration(seconds: 1));
      return _send(req, mutating: true);
    }
  }

  static Future<Map<String, dynamic>> patch(String path, [Map<String, dynamic>? body]) =>
      _send(() => http.patch(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})), mutating: true);

  static Future<Map<String, dynamic>> put(String path, [Map<String, dynamic>? body]) =>
      _send(() => http.put(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})), mutating: true);

  static Future<Map<String, dynamic>> delete(String path, [Map<String, dynamic>? body]) =>
      _send(() => http.delete(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)), mutating: true);

  /// Ham görsel yükleme (png / jpeg / webp).
  static Future<Map<String, dynamic>> putBytes(String path, Uint8List bytes, String contentType) =>
      _send(() => http.put(_uri(path), headers: _headers(contentType), body: bytes), timeout: const Duration(minutes: 2), mutating: true);

  /// Ham dosya gönderimi (POST) — büyük dosyalar için uzun zaman aşımı.
  static Future<Map<String, dynamic>> postBytes(String path, Uint8List bytes, String contentType, {Map<String, String>? query}) =>
      _send(() => http.post(_uri(path, query), headers: _headers(contentType), body: bytes), timeout: const Duration(minutes: 3), mutating: true);
}
