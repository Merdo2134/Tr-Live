import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as overlay;
import 'package:shared_preferences/shared_preferences.dart';
import 'error_log.dart';
import 'room_dock.dart';
import 'socket_service.dart';

class BackgroundService with WidgetsBindingObserver {
  BackgroundService._();
  static final BackgroundService instance = BackgroundService._();

  bool _inited = false;
  bool _running = false;
  bool _withMic = false;
  String _roomName = 'Oda';
  StreamSubscription? _overlaySub;

  void init() {
    if (_inited) return;
    _inited = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'tlive_room',
          channelName: 'Oda',
          channelDescription: 'Odadayken uygulamanın arka planda kesintisiz çalışmasını sağlar.',
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
    try {
      _overlaySub = overlay.FlutterOverlayWindow.overlayListener.listen((data) {
        if (data == 'open') FlutterForegroundTask.launchApp();
      });
    } catch (e, s) {
      ErrorLog.add('Balon dinleyicisi kurulamadı', e, s);
    }
  }

  Future<void> roomOpened(String name) async {
    _roomName = name;
    await _startService();
  }

  Future<void> roomClosed() async {
    _withMic = false;
    await _hideBubble();
    await _stopService();
  }

  Future<void> micChanged(bool onMic) async {
    if (_withMic == onMic) return;
    _withMic = onMic;
    if (_running) {
      await _stopService();
      await _startService();
    }
  }

  Future<void> _startService() async {
    if (_running) return;
    try {
      final types = <ForegroundServiceType>[
        ForegroundServiceType.mediaPlayback,
        if (_withMic) ForegroundServiceType.microphone,
      ];
      final result = await FlutterForegroundTask.startService(
        serviceId: 4721,
        serviceTypes: types,
        notificationTitle: 'TR Live',
        notificationText: '$_roomName odasındasınız.',
      );
      _running = result is ServiceRequestSuccess;
    } catch (e, s) {
      _running = false;
      ErrorLog.add('Ön plan servisi başlatılamadı', e, s);
      if (_withMic) {
        _withMic = false;
        await _startService();
      }
    }
  }

  Future<void> _stopService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e, s) {
      ErrorLog.add('Ön plan servisi durdurulamadı', e, s);
    }
    _running = false;
  }

  Future<void> ensurePermissions(Future<bool> Function(String message, String action) ask) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!(prefs.getBool('asked_battery') ?? false)) {
        await prefs.setBool('asked_battery', true);
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          final ok = await ask('Oda kapanmasın diye arka planda kısıtlanmamanız gerekir. Pil kısıtlamasını kaldırmak için izin verir misiniz?', 'İste');
          if (ok) await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      }
      if (!(prefs.getBool('asked_overlay') ?? false)) {
        await prefs.setBool('asked_overlay', true);
        if (!await overlay.FlutterOverlayWindow.isPermissionGranted()) {
          final ok = await ask('Başka uygulamadayken odanın üstünde küçük bir balon kalması için "Diğer uygulamaların üzerinde göster" izni vermelisiniz.', 'İzin Talebi');
          if (ok) await overlay.FlutterOverlayWindow.requestPermission();
        }
      }
    } catch (e, s) {
      ErrorLog.add('İzinler istenemedi', e, s);
    }
  }

  Future<void> _showBubble() async {
    try {
      if (RoomDock.isOpen || !await overlay.FlutterOverlayWindow.isPermissionGranted()) return;
      if (await overlay.FlutterOverlayWindow.isActive()) return;
      await overlay.FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: 'TR Live',
        overlayContent: '$_roomName odasındasınız.',
        flag: overlay.OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: overlay.PositionGravity.auto,
        height: 190,
        width: 190,
      );
    } catch (e, s) {
      ErrorLog.add('Balon gösterilemedi', e, s);
    }
  }

  Future<void> _hideBubble() async {
    try {
      if (await overlay.FlutterOverlayWindow.isActive()) {
        await overlay.FlutterOverlayWindow.closeOverlay();
      }
    } catch (e, s) {
      ErrorLog.add('Balon kapatılamadı', e, s);
    }
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _showBubble();
    } else if (state == AppLifecycleState.resumed) {
      _hideBubble();
      SocketService.instance.reconnectNow();
    }
  }
}

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
          onTap: () => overlay.FlutterOverlayWindow.shareData('open'),
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFF1F0BF3), Color(0xFFFF4F49)]),
              boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)],
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Icon(Icons.mic, color: Colors.white, size: 44),
          ),
        ),
      ),
    );
  }
}
