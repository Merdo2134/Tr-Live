import 'package:flutter/foundation.dart';
import 'api.dart';

/// Giriş yapmış kullanıcının profili (kendi bakiyesi dahil).
class Session {
  static final ValueNotifier<Map<String, dynamic>?> me = ValueNotifier<Map<String, dynamic>?>(null);

  static Future<void> refresh() async {
    final r = await Api.get('/api/me');
    final u = mapOf(r['user']);
    if (u != null) me.value = u;
  }

  static String get id => me.value?['id']?.toString() ?? '';
  static String get coins => me.value?['coins']?.toString() ?? '0';
  static bool get isStaff => ['admin', 'support'].contains(me.value?['systemRole']);
  static bool get isAdmin => me.value?['systemRole'] == 'admin';

  static void setCoins(String coins) {
    final u = me.value;
    if (u != null) me.value = {...u, 'coins': coins};
  }

  static void clear() => me.value = null;
}
