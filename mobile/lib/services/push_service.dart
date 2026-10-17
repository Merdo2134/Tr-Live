import 'dart:async';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import '../version.dart';
import 'api.dart';
import 'socket_service.dart';

/// Yönetim panelinden "herkese telefon bildirimi". Uygulama açıkken ya da arka planda çalışırken soketten anında
/// telefon bildirimi olarak düşer; uygulama kapalıyken gönderilenler, uygulama açılınca / öne gelince gösterilir.
class PushService with WidgetsBindingObserver {
  PushService._();
  static final PushService _observer = PushService._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static StreamSubscription? _sub;
  static const _lastKey = 'push_last_id';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'trlive_announce',
      'TR Live duyuruları',
      channelDescription: 'Yönetimden gelen duyurular',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  static Future<void> _show(int id, String title, String body) async {
    await _init();
    await _plugin.show(id, title, body, _details);
  }

  /// Sunucuya yeni bildirim var mı diye sorar. İlk çalışmada yalnızca son numarayı kaydeder (eski bildirimler
  /// yeni kurulan telefona yığılmasın).
  static Future<void> poll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    var last = prefs.getString(_lastKey);
    final r = await http
        .get(Uri.parse('${Api.baseUrl}/api/push/latest?after=${last ?? '0'}'), headers: {'X-App-Version': kAppVersion})
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return;
    final j = jsonDecode(r.body);
    if (j is! Map) return;
    if (last == null) {
      await prefs.setString(_lastKey, '${j['lastId'] ?? '0'}');
      return;
    }
    // Sunucudaki son numara telefondakinden küçükse (veritabanı sıfırlandı) baştan say.
    final serverLast = int.tryParse('${j['lastId'] ?? '0'}') ?? 0;
    if ((int.tryParse(last) ?? 0) > serverLast) last = '0';
    var maxId = int.tryParse(last) ?? 0;
    final list = j['messages'] is List ? j['messages'] as List : const [];
    for (final m in list) {
      if (m is! Map) continue;
      final id = int.tryParse('${m['id']}') ?? 0;
      if (id <= maxId) continue;
      await _show(id, '${m['title'] ?? 'TR Live'}', '${m['body'] ?? ''}');
      maxId = id;
    }
    await prefs.setString(_lastKey, '$maxId');
  }

  /// Uygulama açılışında: bildirim izni, anlık (soket) bildirimler ve kaçırılanların kontrolü.
  static Future<void> start() async {
    _sub ??= SocketService.instance.events.listen((e) async {
      if (e['type'] != 'push') return;
      final id = int.tryParse('${e['id']}') ?? 0;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final last = int.tryParse(prefs.getString(_lastKey) ?? '0') ?? 0;
        if (id <= last) return;
        await prefs.setString(_lastKey, '$id');
        await _show(id, '${e['title'] ?? 'TR Live'}', '${e['body'] ?? ''}');
      } catch (_) {}
    });
    try {
      await _init();
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } catch (_) {/* izin verilmezse bildirim gösterilmez, uygulama çalışır */}
    // Uygulama öne gelince kaçırılan bildirimler sorulur.
    WidgetsBinding.instance.removeObserver(_observer);
    WidgetsBinding.instance.addObserver(_observer);
    try {
      await poll();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(poll().catchError((_) {}));
  }
}
