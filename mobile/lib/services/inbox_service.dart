import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'socket_service.dart';

/// Okunmamış özel mesaj sayısı (sekme rozeti için).
class Inbox {
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);
  /// Profil kırmızı rozetleri: yeni ziyaretçi, yeni takipçi, bekleyen arkadaş isteği.
  static final ValueNotifier<Map<String, int>> badges = ValueNotifier<Map<String, int>>(const {'visitors': 0, 'followers': 0, 'friends': 0, 'total': 0});
  static StreamSubscription? _sub;
  static Timer? _timer;

  static void start() {
    _sub?.cancel();
    _sub = SocketService.instance.events.listen((e) {
      if (e['type'] == 'dm' || e['type'] == 'connected') refresh();
      if (e['type'] == 'friend_update' || e['type'] == 'connected') refreshBadges();
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refreshBadges());
    refresh();
    refreshBadges();
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    unread.value = 0;
    badges.value = const {'visitors': 0, 'followers': 0, 'friends': 0, 'total': 0};
  }

  static Future<void> refresh() async {
    try {
      final r = await Api.get('/api/messages/unread-count');
      unread.value = (r['unread'] as num?)?.toInt() ?? 0;
    } catch (_) {/* oturum yoksa yoksay */}
  }

  static Future<void> refreshBadges() async {
    try {
      final r = await Api.get('/api/me/badges');
      int n(String k) => (r[k] as num?)?.toInt() ?? 0;
      badges.value = {'visitors': n('visitors'), 'followers': n('followers'), 'friends': n('friends'), 'total': n('total')};
    } catch (_) {/* oturum yoksa yoksay */}
  }

  /// Liste açılınca ilgili rozeti sıfırlar.
  static Future<void> markSeen(String kind) async {
    try {
      await Api.post('/api/me/seen', {'kind': kind});
    } catch (_) {/* yoksay */}
    await refreshBadges();
  }
}
