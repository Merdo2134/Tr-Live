import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'socket_service.dart';

/// Okunmamış özel mesaj sayısı (sekme rozeti için).
class Inbox {
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);
  static StreamSubscription? _sub;

  static void start() {
    _sub?.cancel();
    _sub = SocketService.instance.events.listen((e) {
      if (e['type'] == 'dm' || e['type'] == 'connected') refresh();
    });
    refresh();
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    unread.value = 0;
  }

  static Future<void> refresh() async {
    try {
      final r = await Api.get('/api/messages/unread-count');
      unread.value = (r['unread'] as num?)?.toInt() ?? 0;
    } catch (_) {/* oturum yoksa yoksay */}
  }
}
