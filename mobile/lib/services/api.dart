import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

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
  static String? token;

  /// Oturum süresi dolduğunda (401) çağrılır; main.dart çıkış ekranına yönlendirir.
  static void Function()? onUnauthorized;

  static Map<String, String> _headers([String contentType = 'application/json']) => {
        'Content-Type': contentType,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$baseUrl$path');
    return query == null || query.isEmpty ? u : u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  /// Sunucu "/uploads/xyz.png" gibi göreli adres döndürebilir.
  static String? absoluteUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return url.startsWith('http') ? url : '$baseUrl$url';
  }

  static Future<Map<String, dynamic>> _send(Future<http.Response> Function() request, {Duration? timeout}) async {
    http.Response r;
    try {
      r = await request().timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw ApiException('Sunucu yanıt vermedi. Lütfen tekrar deneyin.');
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
    if (r.statusCode == 401 && token != null) onUnauthorized?.call();
    final message = data is Map && data['message'] is String ? data['message'] as String : 'İstek başarısız (${r.statusCode}).';
    throw ApiException(message, r.statusCode);
  }

  static Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send(() => http.get(_uri(path, query), headers: _headers()));

  static Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) =>
      _send(() => http.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  static Future<Map<String, dynamic>> patch(String path, [Map<String, dynamic>? body]) =>
      _send(() => http.patch(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  static Future<Map<String, dynamic>> put(String path, [Map<String, dynamic>? body]) =>
      _send(() => http.put(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  static Future<Map<String, dynamic>> delete(String path, [Map<String, dynamic>? body]) =>
      _send(() => http.delete(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)));

  /// Ham görsel yükleme (png / jpeg / webp).
  static Future<Map<String, dynamic>> putBytes(String path, Uint8List bytes, String contentType) =>
      _send(() => http.put(_uri(path), headers: _headers(contentType), body: bytes));

  /// Ham dosya gönderimi (POST) — büyük dosyalar için uzun zaman aşımı.
  static Future<Map<String, dynamic>> postBytes(String path, Uint8List bytes, String contentType, {Map<String, String>? query}) =>
      _send(() => http.post(_uri(path, query), headers: _headers(contentType), body: bytes), timeout: const Duration(minutes: 3));
}
