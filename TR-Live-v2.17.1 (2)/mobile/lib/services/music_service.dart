import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'api.dart';

/// Odadaki ortak müziği her cihazda yerel olarak, sunucu konumuna senkron çalar.
/// Sunucu "positionMs" (alındığı andaki konum) gönderir; şimdiki konum = positionMs + (şimdi - alındığıAn).
class MusicService {
  MusicService._();
  static final MusicService instance = MusicService._();

  final ValueNotifier<Map<String, dynamic>?> state = ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  final ValueNotifier<double> volume = ValueNotifier<double>(1.0);
  final ValueNotifier<bool> muted = ValueNotifier<bool>(false);

  AudioPlayer? _player;
  String? _roomId;
  String? _trackId;
  DateTime _receivedAt = DateTime.now();
  Timer? _resync;

  AudioPlayer get _p => _player ??= AudioPlayer();

  /// Panelde ilerleme çubuğu için şimdiki konum (ms).
  int currentPositionMs() {
    final s = state.value;
    if (s == null) return 0;
    final base = (s['positionMs'] as num?)?.toInt() ?? 0;
    if (s['status'] != 'playing') return base;
    final dur = (mapOf(s['track'])?['durationMs'] as num?)?.toInt() ?? 1 << 30;
    final pos = base + DateTime.now().difference(_receivedAt).inMilliseconds;
    return pos > dur ? dur : pos;
  }

  Future<void> bind(String roomId) async {
    _roomId = roomId;
    await refresh();
    _resync?.cancel();
    // Sapmayı düzeltmek için 30 sn'de bir sunucu durumuyla yeniden eşitle.
    _resync = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> refresh() async {
    final id = _roomId;
    if (id == null) return;
    try {
      final r = await Api.get('/api/rooms/$id/music');
      final s = mapOf(r['state']);
      if (s != null && _roomId == id) await apply(s);
    } catch (_) {/* oda kapanmış olabilir */}
  }

  Future<void> apply(Map<String, dynamic> s) async {
    _receivedAt = DateTime.now();
    state.value = s;
    final track = mapOf(s['track']);
    final status = s['status'];
    try {
      if (track == null || status == 'stopped') {
        _trackId = null;
        await _player?.stop();
        return;
      }
      final url = Api.absoluteUrl(track['url'] as String?);
      if (url == null) return;
      if (track['id'] != _trackId) {
        _trackId = track['id'] as String?;
        await _p.setUrl(url);
      }
      error.value = null;
      await _p.setVolume(muted.value ? 0 : volume.value);
      final position = (s['positionMs'] as num?)?.toInt() ?? 0;
      await _p.seek(Duration(milliseconds: position + (status == 'playing' ? 150 : 0)));
      if (status == 'playing') {
        unawaited(_p.play()); // play() şarkı bitene kadar tamamlanmaz; beklenmez
      } else {
        await _p.pause();
      }
    } catch (e) {
      error.value = 'Müzik çalınamadı. Bağlantınızı kontrol edin.';
    }
  }

  Future<void> setVolume(double v) async {
    volume.value = v;
    if (!muted.value) await _player?.setVolume(v);
  }

  Future<void> setMuted(bool m) async {
    muted.value = m;
    await _player?.setVolume(m ? 0 : volume.value);
  }

  Future<void> unbind() async {
    _resync?.cancel();
    _resync = null;
    _roomId = null;
    _trackId = null;
    state.value = null;
    error.value = null;
    try {
      await _player?.stop();
    } catch (_) {/* yoksay */}
  }
}
