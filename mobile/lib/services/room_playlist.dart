import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'local_music.dart';
import 'music_service.dart';

/// Çalma düzeni (şimdi çalıyor ekranındaki düğmeler).
enum PlayMode { all, one, shuffle }

/// Oda yetkilisinin telefonundaki "Müziklerim" listesini odaya sırayla çalar (Yoho akışı):
/// listeden bir şarkıya dokununca o çalar; bitince bu telefon sıradakini kendisi yükleyip çalar
/// (Tümü: sırayla, Tek: aynı şarkı, Karıştır: rastgele). Önceki / sonraki de buradan.
/// Listeyi çalan telefon odadan çıkarsa sunucudaki son şarkı biter ve müzik durur.
class RoomPlaylist {
  RoomPlaylist._() {
    MusicService.instance.state.addListener(_onState);
  }
  static final RoomPlaylist instance = RoomPlaylist._();

  final ValueNotifier<PlayMode> mode = ValueNotifier<PlayMode>(PlayMode.all);
  /// Bu telefonun çaldığı (Müziklerim'deki) şarkının dosya yolu; null: liste bu telefondan çalınmıyor.
  final ValueNotifier<String?> currentPath = ValueNotifier<String?>(null);
  /// Şarkı yükleniyor (düğmeler kısa süre beklesin).
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  String? _roomId;
  String? _remoteId; // sunucudaki şarkı kimliği (bu telefonun yüklediği)
  String? _lastTrackId;
  String? _lastStatus;
  final _rnd = Random();

  List<LocalTrack> get _list => LocalMusic.instance.tracks.value;

  int get _index => _list.indexWhere((t) => t.path == currentPath.value);

  /// Odaya girince / çıkınca.
  void bind(String? roomId) {
    if (roomId == _roomId) return;
    _roomId = roomId;
    currentPath.value = null;
    _remoteId = null;
  }

  Future<void> playTrack(LocalTrack t) async {
    final room = _roomId;
    if (room == null || busy.value) return;
    busy.value = true;
    try {
      _remoteId = await LocalMusic.instance.sendToRoom(room, t, playNow: true);
      currentPath.value = t.path;
    } finally {
      busy.value = false;
    }
  }

  Future<void> next() async {
    final list = _list;
    if (currentPath.value == null || list.isEmpty) {
      // Liste bu telefondan çalınmıyor: sunucudaki sıraya geç.
      if (_roomId != null) await Api.post('/api/rooms/$_roomId/music/next');
      return;
    }
    await playTrack(list[_nextIndex()]);
  }

  Future<void> previous() async {
    final list = _list;
    if (list.isEmpty) return;
    final i = _index;
    await playTrack(list[i <= 0 ? list.length - 1 : i - 1]);
  }

  Future<void> stop() async {
    currentPath.value = null;
    _remoteId = null;
    if (_roomId != null) await Api.post('/api/rooms/$_roomId/music/stop');
  }

  int _nextIndex() {
    final list = _list;
    final i = _index;
    if (mode.value == PlayMode.shuffle && list.length > 1) {
      var j = i;
      while (j == i) {
        j = _rnd.nextInt(list.length);
      }
      return j;
    }
    if (i < 0) return 0;
    return (i + 1) % list.length;
  }

  /// Bu telefonun çaldığı şarkı bitince (sunucu "durdu" der) sıradaki çalınır.
  void _onState() {
    if (_roomId == null || MusicService.instance.roomId != _roomId) {
      _lastTrackId = null;
      _lastStatus = null;
      return;
    }
    final s = MusicService.instance.state.value;
    final track = mapOf(s?['track']);
    final status = s?['status']?.toString();
    final ended = _lastStatus == 'playing' && _lastTrackId != null && _lastTrackId == _remoteId && (track == null || status == 'stopped');
    // Başka biri başka bir şarkı açtıysa liste bu telefondan çalınmıyordur.
    if (track != null && _remoteId != null && track['id'] != _remoteId) {
      currentPath.value = null;
      _remoteId = null;
    }
    _lastTrackId = track?['id']?.toString();
    _lastStatus = status;
    if (!ended || currentPath.value == null || busy.value) return;
    final list = _list;
    if (list.isEmpty) return;
    if (mode.value == PlayMode.one) {
      final i = _index;
      if (i >= 0) unawaited(playTrack(list[i]).catchError((_) {}));
    } else {
      unawaited(playTrack(list[_nextIndex()]).catchError((_) {}));
    }
  }
}
