// ignore_for_file: experimental_member_use
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Kulaklıkla konuşma kalitesi (kablolu ve Bluetooth).
/// Telefon "görüşme" modunda Bluetooth kulaklık düşük kaliteli arama hattına (SCO, 8-16 kHz) geçer ve karşı taraf
/// sesi uğultulu / kesik duyar; kablolu kulaklıkta da görüşme modunun sert işlemesi sesi boğar.
/// Kulaklık bağlıyken ses "medya" modunda çalışır: dinleme yüksek kaliteli hattan (A2DP) gelir, konuşma kablolu
/// kulaklığın ya da (Bluetooth'ta) telefonun kendi mikrofonundan temiz alınır. Kulaklık yokken hoparlörde yankı
/// olmasın diye "görüşme" modu kullanılır.
class HeadsetAudio {
  HeadsetAudio._();
  static final HeadsetAudio instance = HeadsetAudio._();

  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);
  StreamSubscription<dynamic>? _sub;
  bool? _applied;
  bool _manual = false; // ses ayarını biz devraldık mı (kulaklık takıldı)

  /// Oda açılınca (ses bağlantısından önce) çağrılır.
  Future<void> start() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final now = await const MethodChannel('trlive/device').invokeMethod<bool>('headsetConnected') ?? false;
      await _apply(now);
    } catch (_) {/* eski derleme: varsayılan ayar */}
    if (_sub != null) return;
    try {
      _sub = const EventChannel('trlive/headset').receiveBroadcastStream().listen((v) => _apply(v == true), onError: (_) {});
    } catch (_) {}
  }

  /// Oda kapanınca (ses bağlantısı kapanmadan önce) çağrılır: ses ayarı LiveKit'e geri verilir.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _applied = null;
    if (!_manual) return;
    _manual = false;
    try {
      await lk.AudioManager.instance.setAudioSessionOptions(const lk.AudioSessionOptions.communication());
      await lk.AudioManager.instance.setAudioSessionManagementMode(lk.AudioSessionManagementMode.automatic);
    } catch (_) {/* desteklenmeyen cihaz */}
  }

  Future<void> _apply(bool headset) async {
    connected.value = headset;
    if (_applied == headset) return;
    _applied = headset;
    // Kulaklık yokken LiveKit'in kendi (görüşme) ayarına dokunulmaz; yalnız kulaklık takılınca devralınır.
    if (!headset && !_manual) return;
    try {
      // LiveKit sesi kendisi yönettiği için ayar onun üzerinden verilir (bağlanınca da korunur).
      _manual = true;
      await lk.AudioManager.instance.setAudioSessionOptions(
          headset ? const lk.AudioSessionOptions.mediaPlayback() : const lk.AudioSessionOptions.communication());
    } catch (_) {/* desteklenmeyen cihaz */}
  }
}
