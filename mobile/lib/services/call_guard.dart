import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Telefon araması (ya da WhatsApp gibi bir arama) gelince Android, uygulamaya "sesi geçici olarak bırak" der.
/// Bu sınıf o sinyali dinler: [inCall] true olunca oda sesi ve mikrofon kapatılır, arama bitince geri açılır.
/// (Oda müziği çalar zaten aynı sinyalle kendiliğinden durup devam eder.)
class CallGuard {
  CallGuard._();
  static final CallGuard instance = CallGuard._();

  /// Şu an bir arama sürüyor mu.
  final ValueNotifier<bool> inCall = ValueNotifier<bool>(false);
  StreamSubscription<AudioInterruptionEvent>? _sub;
  // Açık oda sayısı: oda değiştirirken yeni oda eskisi kapanmadan açılabilir; son oda kapanınca bırakılır.
  int _users = 0;

  /// Oda açılınca çağrılır.
  Future<void> start() async {
    _users++;
    if (_sub != null) return;
    try {
      final s = await AudioSession.instance;
      // Medya sesi (oda müziği hoparlörden normal çalsın). Kısa bildirim sesleri ("sesi kıs") arama sayılmaz.
      await s.configure(const AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(contentType: AndroidAudioContentType.music, usage: AndroidAudioUsage.media),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      _sub ??= s.interruptionEventStream.listen((e) {
        // Yalnızca geçici kesinti (gelen/giden arama, zil): kalıcı kesintide (başka uygulama müzik açtı) dokunulmaz.
        if (e.type != AudioInterruptionType.pause) return;
        inCall.value = e.begin;
      });
      // Sinyalleri alabilmek için uygulama ses odağını ister.
      await s.setActive(true);
    } catch (_) {/* desteklenmeyen cihaz: arama algılanmaz, oda yine çalışır */}
  }

  /// Oda kapanınca çağrılır; son oda da kapandıysa ses odağı bırakılır (başka uygulamalar normal çalsın).
  Future<void> stop() async {
    if (_users > 0) _users--;
    if (_users > 0) return;
    await _sub?.cancel();
    _sub = null;
    inCall.value = false;
    try {
      await (await AudioSession.instance).setActive(false);
    } catch (_) {}
  }
}
