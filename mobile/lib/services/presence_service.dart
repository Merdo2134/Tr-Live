import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'socket_service.dart';

/// Çevrimiçi durumu. Ekranlar görünen kişileri [watch] ile bildirir; sunucu anlık durumu ve sonraki
/// değişiklikleri soket üzerinden gönderir. Kişi durumunu gizlediyse kayıt tutulmaz (hiçbir şey gösterilmez).
class PresenceService {
  PresenceService._();

  /// userId -> {'online': bool, 'lastSeenAt': String?}
  static final ValueNotifier<Map<String, Map<String, dynamic>>> states = ValueNotifier(const {});
  static List<String> _watched = const [];
  static StreamSubscription? _sub;

  static void init() {
    _sub ??= SocketService.instance.events.listen(_onEvent);
  }

  static void _onEvent(Map<String, dynamic> m) {
    final type = m['type'];
    if (type == 'connected') {
      // Yeniden bağlanınca izleme listesi tekrar gönderilir.
      if (_watched.isNotEmpty) SocketService.instance.send({'type': 'presence_watch', 'userIds': _watched});
    } else if (type == 'presence_state') {
      final next = Map<String, Map<String, dynamic>>.of(states.value);
      // Anlık görüntüde olmayan izlenen kişiler (gizlemiş / engellemiş) listeden çıkarılır.
      for (final id in _watched) {
        next.remove(id);
      }
      for (final u in listOf(m['users'])) {
        final id = u['userId']?.toString();
        if (id != null) next[id] = {'online': u['online'] == true, 'lastSeenAt': u['lastSeenAt']};
      }
      states.value = next;
    } else if (type == 'presence') {
      final id = m['userId']?.toString();
      if (id == null) return;
      final next = Map<String, Map<String, dynamic>>.of(states.value);
      if (m['online'] != true && m['lastSeenAt'] == null) {
        next.remove(id); // durumunu gizledi
      } else {
        next[id] = {'online': m['online'] == true, 'lastSeenAt': m['lastSeenAt']};
      }
      states.value = next;
    }
  }

  /// Ekranda görünen kişiler (en fazla 100). Boş liste izlemeyi bırakır.
  static void watch(Iterable<String> userIds) {
    init();
    final ids = userIds.where((e) => e.isNotEmpty).toSet().take(100).toList();
    if (listEquals(ids, _watched)) return;
    _watched = ids;
    SocketService.instance.send({'type': 'presence_watch', 'userIds': ids});
  }

  /// API yanıtındaki "presence" alanını önbelleğe yazar (soket gelmeden önce de doğru görünsün).
  static void seed(String? userId, dynamic presence) {
    if (userId == null || userId.isEmpty) return;
    final p = mapOf(presence);
    final next = Map<String, Map<String, dynamic>>.of(states.value);
    if (p == null) {
      next.remove(userId);
    } else {
      next[userId] = {'online': p['online'] == true, 'lastSeenAt': p['lastSeenAt']};
    }
    states.value = next;
  }

  static void clear() {
    _watched = const [];
    states.value = const {};
  }
}

const _months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

/// "Çevrimiçi", "Son görülme 5 dk önce" ... Durum bilinmiyorsa (gizli) null.
String? presenceLabel(Map<String, dynamic>? p) {
  if (p == null) return null;
  if (p['online'] == true) return 'Çevrimiçi';
  final t = DateTime.tryParse((p['lastSeenAt'] ?? '').toString())?.toLocal();
  if (t == null) return null;
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Son görülme az önce';
  if (diff.inMinutes < 60) return 'Son görülme ${diff.inMinutes} dk önce';
  if (diff.inHours < 24) return 'Son görülme ${diff.inHours} sa önce';
  if (diff.inDays < 7) return 'Son görülme ${diff.inDays} gün önce';
  return 'Son görülme ${t.day} ${_months[t.month - 1]}';
}
