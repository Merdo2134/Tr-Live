import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api.dart';

/// Uygulama boyunca tek WebSocket bağlantısı. Kopunca otomatik yeniden bağlanır
/// ve bağlı olunan odaya yeniden abone olur.
class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _controller.stream;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _retry;
  Timer? _ping;
  bool _wanted = false;
  int _attempt = 0;
  String? _roomId;

  void start() {
    _wanted = true;
    _attempt = 0;
    _connect();
  }

  /// Uygulama arka plandan dönünce bağlantıyı hemen yeniler (bekleme süresini beklemeden).
  void reconnectNow() {
    if (!_wanted) return;
    _retry?.cancel();
    _attempt = 0;
    _connect();
  }

  void stop() {
    _wanted = false;
    _roomId = null;
    _retry?.cancel();
    _teardown();
  }

  void subscribeRoom(String roomId) {
    _roomId = roomId;
    _send({'type': 'room_subscribe', 'roomId': roomId});
  }

  void unsubscribeRoom() {
    if (_roomId != null) _send({'type': 'room_unsubscribe'});
    _roomId = null;
  }

  void _send(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {/* bağlantı yoksa yeniden bağlanınca abone olunur */}
  }

  void _connect() {
    if (!_wanted || Api.token == null) return;
    _teardown();
    final base = Uri.parse(Api.baseUrl);
    final uri = Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/ws',
      queryParameters: {'token': Api.token!},
    );
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      channel.ready.then((_) {}, onError: (_) {}); // bağlantı hatası stream üzerinden de gelir; yakalanmamış istisna olmasın
      _sub = channel.stream.listen(_onData, onDone: _onClosed, onError: (_) => _onClosed(), cancelOnError: true);
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => _send({'type': 'ping'}));
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onData(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final message = Map<String, dynamic>.from(decoded);
      if (message['type'] == 'connected') {
        _attempt = 0;
        if (_roomId != null) _send({'type': 'room_subscribe', 'roomId': _roomId});
      }
      _controller.add(message);
    } catch (_) {/* bozuk mesajı yoksay */}
  }

  void _onClosed() {
    final code = _channel?.closeCode;
    _teardown();
    // 1008: kimlik doğrulama reddedildi, 4001: hesap yasaklandı/şifre değişti/silindi.
    if (code == 1008 || code == 4001) {
      _wanted = false;
      Api.onUnauthorized?.call();
      return;
    }
    _controller.add({'type': 'socket_closed'});
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_wanted) return;
    _retry?.cancel();
    final seconds = min(30, 1 << min(_attempt, 5));
    _attempt += 1;
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  void _teardown() {
    _ping?.cancel();
    _ping = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {/* yoksay */}
    _channel = null;
  }
}
