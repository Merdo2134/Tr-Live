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
  Timer? _poll;
  bool _focusPaused = false; // ses odağı "geçici kesinti" dedi
  bool _phoneMode = false; // telefonun ses modu: çalıyor / görüşmede

  void _update() => inCall.value = _focusPaused || _phoneMode;

  /// Android'in ses modunu saniyede bir okur: zil çalıyorsa ya da normal telefon görüşmesi sürüyorsa arama var.
  /// (Oda sesi sistemi ses odağını kendisi aldığı için odak sinyali bazı telefonlarda hiç gelmiyor; bu yol her zaman çalışır.)
  void _startPoll() {
    if (_poll != null || defaultTargetPlatform != TargetPlatform.android) return;
    final am = AndroidAudioManager();
    var busy = false;
    _poll = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (busy) return;
      busy = true;
      try {
        final m = await am.getMode();
        if (_poll != null) {
          _phoneMode = m == AndroidAudioHardwareMode.ringtone || m == AndroidAudioHardwareMode.inCall;
          _update();
        }
      } catch (_) {
        // Okunamayan mod (yeni Android sürümlerindeki yönlendirme modları): arama sayılmaz, ses takılı kalmasın.
        if (_poll != null) {
          _phoneMode = false;
          _update();
        }
      } finally {
        busy = false;
      }
    });
  }

  /// Oda açılınca çağrılır.
  Future<void> start() async {
    _users++;
    _startPoll();
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
        // Bitiş olayı ya da kalıcı / kısma türü kesinti bayrağı temizler (ses takılı kalmasın).
        _focusPaused = e.begin && e.type == AudioInterruptionType.pause;
        _update();
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
    _poll?.cancel();
    _poll = null;
    _focusPaused = false;
    _phoneMode = false;
    inCall.value = false;
    try {
      await (await AudioSession.instance).setActive(false);
    } catch (_) {}
  }
}
