import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

/// Telefonun kendi hafızasından seçilen müzik dosyası.
class LocalTrack {
  final String path;
  final String title;
  final String artist;
  final int durationMs;
  final int sizeBytes;
  const LocalTrack({required this.path, required this.title, required this.artist, required this.durationMs, required this.sizeBytes});

  Map<String, dynamic> toJson() => {'path': path, 'title': title, 'artist': artist, 'durationMs': durationMs, 'sizeBytes': sizeBytes};
  factory LocalTrack.fromJson(Map<String, dynamic> j) => LocalTrack(
        path: j['path'] as String,
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      );
}

/// Telefon müzik kitaplığı: dosya seçme, kalıcı liste, telefonda dinleme ve odaya gönderme.
class LocalMusic {
  LocalMusic._();
  static final LocalMusic instance = LocalMusic._();

  static const maxBytes = 25 * 1024 * 1024; // sunucu sınırıyla aynı
  static const _prefsKey = 'local_music_v1';

  final ValueNotifier<List<LocalTrack>> tracks = ValueNotifier<List<LocalTrack>>([]);
  final ValueNotifier<String?> previewing = ValueNotifier<String?>(null); // çalan dosyanın yolu
  AudioPlayer? _preview;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).map((e) => LocalTrack.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      // Telefondan silinmiş dosyaları listeden düşür.
      tracks.value = [for (final t in list) if (await File(t.path).exists()) t];
    } catch (_) {/* bozuk kayıt: boş liste */}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, jsonEncode(tracks.value.map((t) => t.toJson()).toList()));
    } catch (_) {/* yoksay */}
  }

  /// "Sanatçı - Şarkı.mp3" adından başlık/sanatçı çıkarır.
  static ({String title, String artist}) parseName(String fileName) {
    var n = fileName.replaceFirst(RegExp(r'\.[A-Za-z0-9]{2,5}$'), '').replaceAll('_', ' ').trim();
    n = n.replaceFirst(RegExp(r'^\d{1,3}[\s.\-]+'), ''); // baştaki parça numarası
    final i = n.indexOf(' - ');
    if (i > 0 && i < n.length - 3) return (artist: n.substring(0, i).trim(), title: n.substring(i + 3).trim());
    return (artist: '', title: n.isEmpty ? 'Adsız parça' : n);
  }

  static String contentTypeOf(String path) {
    final e = path.toLowerCase().split('.').last;
    switch (e) {
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      default:
        return 'audio/mpeg';
    }
  }

  /// Dosya seçiciyi açar; seçilen ses dosyalarını listeye ekler. Eklenen sayısını döndürür.
  Future<int> pickAndAdd() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (r == null) return 0;
    final list = [...tracks.value];
    var added = 0;
    for (final f in r.files) {
      final path = f.path;
      if (path == null || list.any((t) => t.path == path)) continue;
      final dur = await _durationOf(path);
      if (dur == null) continue; // çalınamayan dosya
      final meta = parseName(f.name);
      list.add(LocalTrack(path: path, title: meta.title, artist: meta.artist, durationMs: dur, sizeBytes: f.size));
      added++;
    }
    tracks.value = list;
    await _save();
    return added;
  }

  Future<int?> _durationOf(String path) async {
    final p = AudioPlayer();
    try {
      final d = await p.setFilePath(path);
      return d?.inMilliseconds;
    } catch (_) {
      return null;
    } finally {
      await p.dispose();
    }
  }

  Future<void> remove(LocalTrack t) async {
    if (previewing.value == t.path) await stopPreview();
    tracks.value = tracks.value.where((x) => x.path != t.path).toList();
    await _save();
  }

  /// Telefonda (yalnızca kendiniz için) dinle / durdur.
  Future<void> togglePreview(LocalTrack t) async {
    if (previewing.value == t.path) return stopPreview();
    await stopPreview();
    final p = _preview ??= AudioPlayer();
    try {
      await p.setFilePath(t.path);
      previewing.value = t.path;
      unawaited(p.play().then((_) {
        if (previewing.value == t.path && p.processingState == ProcessingState.completed) previewing.value = null;
      }));
    } catch (_) {
      previewing.value = null;
      rethrow;
    }
  }

  Future<void> stopPreview() async {
    previewing.value = null;
    try {
      await _preview?.stop();
    } catch (_) {/* yoksay */}
  }

  /// Dosyayı odaya yükler. [playNow]: yetkili ise hemen çalar, değilse sıraya ekler.
  Future<void> sendToRoom(String roomId, LocalTrack t, {required bool playNow}) async {
    final file = File(t.path);
    if (!await file.exists()) throw ApiException('Dosya telefonda bulunamadı. Listeden kaldırıp yeniden ekleyin.');
    final size = await file.length();
    if (size > maxBytes) throw ApiException('Dosya çok büyük (en fazla 25 MB). Daha küçük bir dosya seçin.');
    final bytes = await file.readAsBytes();
    final up = await Api.postBytes('/api/rooms/$roomId/music/upload', bytes, contentTypeOf(t.path), query: {
      'title': t.title,
      if (t.artist.isNotEmpty) 'artist': t.artist,
      'durationMs': '${t.durationMs}',
    });
    final id = (up['track'] as Map?)?['id'];
    if (id == null) throw ApiException('Yükleme tamamlanamadı.');
    if (playNow) {
      await Api.post('/api/rooms/$roomId/music/play', {'trackId': id});
    } else {
      await Api.post('/api/rooms/$roomId/music/queue', {'trackId': id});
    }
  }
}
