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
  static const _personalKey = 'notify_last_id';

  /// Kişiye özel bildirime dokunulunca (ana sayfa ayarlar): oda açıldı → odaya gir, istek/takip → profili aç.
  static void Function(String kind, Map<String, dynamic> data)? onOpen;

  static const _socialDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'trlive_social',
      'Arkadaşlar ve odalar',
      channelDescription: 'Arkadaşlık isteği, yeni takipçi, arkadaşın oda açması',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

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
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => _handleTap(r.payload),
    );
    _ready = true;
  }

  static void _handleTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final j = jsonDecode(payload);
      if (j is! Map) return;
      final data = j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : <String, dynamic>{};
      onOpen?.call('${j['kind'] ?? ''}', data);
    } catch (_) {}
  }

  /// Kişiye özel bildirim (yerel bildirim numarası, yönetim duyurularıyla çakışmasın diye ayrı aralıkta).
  static Future<void> _showPersonal(Map<dynamic, dynamic> m) async {
    final id = int.tryParse('${m['id']}') ?? 0;
    await _init();
    await _plugin.show(
      1000000000 + (id % 900000000),
      '${m['title'] ?? 'TR Live'}',
      '${m['body'] ?? ''}',
      _socialDetails,
      payload: jsonEncode({'kind': m['kind'], 'data': m['data']}),
    );
  }

  /// Uygulama kapalıyken gelen kişiye özel bildirimler (açılınca / öne gelince). İlk çalışmada yalnızca son numara
  /// kaydedilir (eski bildirimler yığılmasın).
  static Future<void> pollPersonal() async {
    if (Api.token == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final last = prefs.getString(_personalKey);
    final j = await Api.get('/api/me/notifications/pending', query: {'after': last ?? '0'});
    if (last == null) {
      await prefs.setString(_personalKey, '${j['lastId'] ?? '0'}');
      return;
    }
    var maxId = int.tryParse(last) ?? 0;
    final serverLast = int.tryParse('${j['lastId'] ?? '0'}') ?? 0;
    if (maxId > serverLast) maxId = 0; // veritabanı sıfırlandı
    for (final m in (j['notifications'] is List ? j['notifications'] as List : const [])) {
      if (m is! Map) continue;
      final id = int.tryParse('${m['id']}') ?? 0;
      if (id <= maxId) continue;
      await _showPersonal(m);
      maxId = id;
    }
    await prefs.setString(_personalKey, '$maxId');
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
      if (e['type'] == 'notify') {
        // Kişiye özel bildirim (soketten anında). Aynı numara iki kez gösterilmez.
        final id = int.tryParse('${e['id']}') ?? 0;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final last = int.tryParse(prefs.getString(_personalKey) ?? '0') ?? 0;
          if (id <= last) return;
          await prefs.setString(_personalKey, '$id');
          await _showPersonal(e);
        } catch (_) {}
        return;
      }
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
    try {
      await pollPersonal();
    } catch (_) {}
    // Uygulama bildirime dokunularak açıldıysa ilgili yere gidilir.
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final payload = launch?.notificationResponse?.payload;
        Future.delayed(const Duration(seconds: 2), () => _handleTap(payload));
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(poll().catchError((_) {}));
      unawaited(pollPersonal().catchError((_) {}));
    }
  }
}
