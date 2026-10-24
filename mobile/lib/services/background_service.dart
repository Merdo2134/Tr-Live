import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// NotificationVisibility iki pakette de var; balon için flutter_overlay_window'unki kullanılır.
import 'package:flutter_foreground_task/flutter_foreground_task.dart' hide NotificationVisibility;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'error_log.dart';
import 'room_dock.dart';
import 'socket_service.dart';

/// Odadayken uygulamanın arka planda kesintisiz çalışması ve diğer uygulamaların üzerinde yüzen balon:
///  - Ön plan servisi (bildirimli): Android uygulamayı kapatmaz; oda sesi ve (mikrofondaysanız) mikrofon açık kalır.
///  - Yüzen balon: uygulamadan çıkınca ekranda küçük bir balon kalır, dokununca uygulamaya dönülür.
///  - Geri dönünce bağlantı hemen yenilenir.
/// Hiçbir hata uygulamayı çökertmez; her adım korumalıdır.
class BackgroundService with WidgetsBindingObserver {
  BackgroundService._();
  static final BackgroundService instance = BackgroundService._();

  bool _inited = false;
  bool _running = false;
  bool _withMic = false; // servis "mikrofon" türüyle mi çalışıyor
  bool _wantMic = false; // kullanıcı mikrofonda mı
  bool _foreground = true; // uygulama ekranda mı (Android 12+ arka plandan servis başlatmaya izin vermez)
  bool _wasHidden = false; // gerçekten arka plana gidildi mi (bildirim perdesi / izin penceresi sayılmaz)

  /// Mikrofon izni verilmiş mi (verilmemişse "mikrofon" türlü servis denenmez; Android 14 reddeder ve 5 sn bekletir).
  Future<bool> _micAllowed() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await const MethodChannel('trlive/device').invokeMethod<bool>('hasMicPermission') ?? false;
    } on MissingPluginException {
      return true; // ana ekran kodu yok (eski derleme): mikrofon türü yine denenir, olmazsa yalnız medya türü açılır
    } catch (_) {
      return false;
    }
  }
  String _roomName = 'Oda';

  /// Uygulama açılırken bir kez çağrılır.
  void init() {
    if (_inited) return;
    _inited = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'trlive_room',
          channelName: 'Oda',
          channelDescription: 'Odadayken uygulamanın arka planda çalışmasını sağlar.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    } catch (e, s) {
      ErrorLog.add('Arka plan servisi hazırlanamadı', e, s);
    }
  }

  // ---------- Oda açılınca / kapanınca ----------
  // Aç/kapat/mikrofon işlemleri sırayla çalışır: oda değiştirirken "kapat" bitmeden gelen "aç" atlanıp
  // servis odadayken durmasın diye tek kuyruktan geçer.
  Future<void> _chain = Future<void>.value();
  Future<void> _queue(Future<void> Function() job) {
    final next = _chain.then((_) => job()).catchError((Object e, StackTrace s) => ErrorLog.add('Arka plan servisi', e, s));
    _chain = next;
    return next;
  }

  Future<void> roomOpened(String name) => _queue(() async {
        _roomName = name;
        if (_running) {
          // Oda değişti: servis açık kalır, yalnız bildirim yazısı güncellenir.
          try {
            await FlutterForegroundTask.updateService(notificationText: '$name odasındasınız · dönmek için dokun');
          } catch (_) {}
          return;
        }
        await _startService();
      });

  Future<void> roomClosed() => _queue(() async {
        _withMic = false;
        _wantMic = false;
        await _stopService();
      });

  /// Mikrofona çıkınca/inince çağrılır. Servis mümkünse baştan "mikrofon" türüyle açılır; bu yüzden çoğu zaman
  /// hiçbir şey yapılmaz. Servisi yeniden başlatmak gerekiyorsa yalnızca uygulama ekrandayken yapılır:
  /// arka planda kapatılan servis Android 12+ tarafından yeniden açtırılmaz ve oda bağlantısı düşer.
  Future<void> micChanged(bool onMic) => _queue(() async {
        _wantMic = onMic;
        if (!_running && _foreground && RoomDock.isOpen) {
          await _startService();
          return;
        }
        if (!onMic || _withMic || !_running || !_foreground || !await _micAllowed()) return;
        await _restart();
      });

  Future<void> _restart() async {
    await _stopService();
    await _startService();
  }

  /// Servis; mikrofon izni varsa mikrofon + medya türüyle, yoksa yalnız medya türüyle açılır.
  Future<void> _startService() async {
    if (_running) return;
    if (await _micAllowed() && await _tryStart(withMic: true)) return;
    await _tryStart(withMic: false);
  }

  Future<bool> _tryStart({required bool withMic}) async {
    try {
      final result = await FlutterForegroundTask.startService(
        serviceId: 4721,
        serviceTypes: [ForegroundServiceTypes.mediaPlayback, if (withMic) ForegroundServiceTypes.microphone],
        notificationTitle: 'TR Live',
        notificationText: '$_roomName odasındasınız · dönmek için dokun',
      );
      _running = result is ServiceRequestSuccess;
      if (_running) _withMic = withMic;
      if (result is ServiceRequestFailure && !withMic) ErrorLog.add('Ön plan servisi başlatılamadı', result.error, StackTrace.current);
      return _running;
    } catch (e, s) {
      _running = false;
      // Mikrofon izni yoksa "mikrofon" türü reddedilir; yalnız medya türüyle denenir (hata kaydı gerekmez).
      if (!withMic) ErrorLog.add('Ön plan servisi başlatılamadı', e, s);
      return false;
    }
  }

  /// Uygulama ekrana dönünce: servis bir sebeple kapandıysa yeniden açılır; mikrofondayken servis mikrofon türünde
  /// değilse (izin sonradan verildi) şimdi yükseltilir.
  Future<void> _ensureOnResume() => _queue(() async {
        if (!RoomDock.isOpen || !_foreground) return;
        try {
          _running = await FlutterForegroundTask.isRunningService;
        } catch (_) {}
        if (!_running) {
          await _startService();
        } else if (_wantMic && !_withMic && _foreground && await _micAllowed()) {
          await _restart();
        }
      });

  Future<void> _stopService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    } catch (e, s) {
      ErrorLog.add('Ön plan servisi durdurulamadı', e, s);
    }
    _running = false;
  }

  // ---------- İzin (bir kez) ----------
  /// Odaya ilk girişte çağrılır. Tek izin: bildirim (Android 13+). Odadayken üstte sabit "… odasındasınız" bildirimi
  /// görünür; dokununca odaya dönülür. Balon ve pil izni yoktur. Android'in kendi penceresi açılır, ek soru sorulmaz.
  Future<void> ensurePermissions(Future<bool> Function(String message, String action) ask) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('asked_notification') ?? false) return;
      await prefs.setBool('asked_notification', true);
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (e, s) {
      ErrorLog.add('Bildirim izni istenemedi', e, s);
    }
  }

  // ---------- Uygulama ön/arka plan ----------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _foreground = false;
      _wasHidden = true;
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _ensureOnResume();
      if (_wasHidden) SocketService.instance.reconnectNow();
      _wasHidden = false;
    }
  }
}

/// Yüzen balonun içeriği (ayrı bir Flutter motorunda çalışır; giriş noktası main.dart'taki overlayMain). Dokununca ana uygulamaya "open" gönderir.
void overlayMainImpl() {
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _Bubble()));
}

class _Bubble extends StatelessWidget {
  const _Bubble();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: GestureDetector(
          onTap: () => FlutterOverlayWindow.shareData('open'),
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF1FD6F5), Color(0xFFFF4F9A)]),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Icon(Icons.mic, color: Colors.white, size: 44),
          ),
        ),
      ),
    );
  }
}
