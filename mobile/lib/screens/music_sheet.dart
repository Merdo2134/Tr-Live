import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/local_music.dart';
import '../services/music_service.dart';
import '../services/session.dart';
import '../widgets/common.dart';

String _mmss(num ms) {
  final s = (ms / 1000).floor();
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Oda müzik çalar paneli. [canManage]: oda sahibi / yardımcı sahip / moderatör.
Future<void> showMusicSheet(BuildContext context, {required String roomId, required bool canManage, required bool canQueue}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF16112B),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: _MusicPanel(roomId: roomId, canManage: canManage, canQueue: canQueue),
    ),
  );
}

class _MusicPanel extends StatefulWidget {
  final String roomId;
  final bool canManage;
  final bool canQueue;
  const _MusicPanel({required this.roomId, required this.canManage, required this.canQueue});

  @override
  State<_MusicPanel> createState() => _MusicPanelState();
}

class _MusicPanelState extends State<_MusicPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _disc = AnimationController(vsync: this, duration: const Duration(seconds: 10));
  Timer? _tick;
    double? _dragging; // ilerleme çubuğu sürüklenirken

  String? _progress; // "2/5 yükleniyor"

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _dragging == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _disc.dispose();
    super.dispose();
  }

  String get _base => '/api/rooms/${widget.roomId}/music';

  Future<void> _call(Future<Map<String, dynamic>> Function() action, {String? done}) async {
    final r = await guard(context, action);
    if (r != null && done != null && mounted) toast(context, done);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _player(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 12, 4),
        child: Row(children: [
          const Expanded(child: Text('Çalma listesi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          if (_progress != null)
            Padding(padding: const EdgeInsets.only(right: 10), child: Text(_progress!, style: const TextStyle(color: Colors.white70, fontSize: 12)))
          else if (widget.canManage || widget.canQueue)
            FilledButton.icon(onPressed: _addFiles, icon: const Icon(Icons.add), label: const Text('Müzik ekle')),
        ]),
      ),
      Expanded(child: _playlist()),
    ]);
  }

  /// Üstteki çalar kartı (Yoho tarzı): dönen plak, şarkı adı, ilerleme, kontroller; sağ üstte küçült.
  Widget _player() {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: MusicService.instance.state,
      builder: (context, s, _) {
        final track = mapOf(s?['track']);
        final status = (s?['status'] ?? 'stopped').toString();
        final playing = status == 'playing';
        if (playing && !_disc.isAnimating) {
          _disc.repeat();
        } else if (!playing && _disc.isAnimating) {
          _disc.stop();
        }
        final duration = ((track?['durationMs'] as num?) ?? 0).toDouble();
        final position = (_dragging ?? MusicService.instance.currentPositionMs().toDouble()).clamp(0, duration > 0 ? duration : 1).toDouble();
        final cover = Api.absoluteUrl(track?['coverUrl'] as String?);
        Widget disc = Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black, border: Border.all(color: Colors.white24, width: 4)),
          child: ClipOval(
            child: cover != null
                ? Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.pinkAccent, size: 32))
                : const Icon(Icons.music_note, color: Colors.pinkAccent, size: 32),
          ),
        );
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(colors: [Color(0xFF3A1C71), Color(0xFFD76D77)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(children: [
            Row(children: [
              RotationTransition(turns: _disc, child: disc),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(track?['title']?.toString() ?? 'Şu an müzik çalmıyor', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text((track?['artist'] ?? '').toString().isEmpty ? (playing ? 'Çalıyor' : (track != null ? 'Duraklatıldı' : 'Listeden bir şarkı seç')) : track!['artist'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
              IconButton(tooltip: 'Küçült', icon: const Icon(Icons.keyboard_arrow_down, size: 28), onPressed: () => Navigator.of(context).maybePop()),
            ]),
            if (track != null)
              SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), activeTrackColor: Colors.white, inactiveTrackColor: Colors.white30, thumbColor: Colors.white),
                child: Row(children: [
                  Text(_mmss(position), style: const TextStyle(fontSize: 11)),
                  Expanded(
                    child: Slider(
                      value: position,
                      max: duration > 0 ? duration : 1,
                      onChangeStart: widget.canManage ? (v) => setState(() => _dragging = v) : null,
                      onChanged: widget.canManage ? (v) => setState(() => _dragging = v) : null,
                      onChangeEnd: widget.canManage
                          ? (v) async {
                              setState(() => _dragging = null);
                              await _call(() => Api.post('$_base/seek', {'positionMs': v.round()}));
                            }
                          : null,
                    ),
                  ),
                  Text(_mmss(duration), style: const TextStyle(fontSize: 11)),
                ]),
              ),
            Row(children: [
              ValueListenableBuilder<bool>(
                valueListenable: MusicService.instance.muted,
                builder: (_, muted, __) => IconButton(onPressed: () => MusicService.instance.setMuted(!muted), icon: Icon(muted ? Icons.volume_off : Icons.volume_up, size: 22)),
              ),
              Expanded(
                child: ValueListenableBuilder<double>(
                  valueListenable: MusicService.instance.volume,
                  builder: (_, vol, __) => SliderTheme(
                    data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), activeTrackColor: Colors.white, inactiveTrackColor: Colors.white30, thumbColor: Colors.white),
                    child: Slider(value: vol, onChanged: (v) => MusicService.instance.setVolume(v)),
                  ),
                ),
              ),
              if (widget.canManage) ...[
                IconButton(
                  iconSize: 36,
                  onPressed: track == null ? null : () => _call(() => playing ? Api.post('$_base/pause') : Api.post('$_base/play')),
                  icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                ),
                IconButton(tooltip: 'Sonraki', onPressed: () => _call(() => Api.post('$_base/next')), icon: const Icon(Icons.skip_next, size: 28)),
                IconButton(tooltip: 'Durdur', onPressed: track == null ? null : () => _call(() => Api.post('$_base/stop')), icon: const Icon(Icons.stop_circle_outlined, size: 26)),
              ],
            ]),
            if (!widget.canManage)
              const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Müziği oda yetkilileri yönetir; sen sadece sesini ayarlarsın.', style: TextStyle(color: Colors.white70, fontSize: 11))),
            ValueListenableBuilder<String?>(
              valueListenable: MusicService.instance.error,
              builder: (_, e, __) => e == null ? const SizedBox.shrink() : Text(e, style: const TextStyle(color: Colors.yellowAccent, fontSize: 12)),
            ),
          ]),
        );
      },
    );
  }

  /// Tek liste: üstte çalan şarkı, altında sıradakiler (ekleme sırasıyla).
  Widget _playlist() {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: MusicService.instance.state,
      builder: (context, s, _) {
        final queue = listOf(s?['queue']);
        final current = mapOf(s?['track']);
        final playing = s?['status'] == 'playing';
        if (queue.isEmpty && current == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.library_music, size: 56, color: Colors.white38),
                const SizedBox(height: 12),
                Text(widget.canManage || widget.canQueue ? '"Müzik ekle" ile telefonundan bir veya birden çok şarkı seç.\nSeçtiğin sırayla listeye girer ve odada çalar.' : 'Listede şarkı yok.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
              ]),
            ),
          );
        }
        return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
          if (current != null)
            ListTile(
              dense: true,
              tileColor: Colors.white10,
              leading: Icon(playing ? Icons.graphic_eq : Icons.pause_circle_outline, color: Colors.pinkAccent),
              title: Text((current['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${(current['artist'] ?? '').toString().isEmpty ? 'Bilinmeyen sanatçı' : current['artist']} · ${_mmss((current['durationMs'] as num?) ?? 0)}'),
            ),
          for (var i = 0; i < queue.length; i++)
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 13, backgroundColor: Colors.white12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
              title: Text((mapOf(queue[i]['track'])?['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${(mapOf(queue[i]['track'])?['artist'] ?? '').toString().isEmpty ? 'Bilinmeyen sanatçı' : mapOf(queue[i]['track'])?['artist']} · ${_mmss((mapOf(queue[i]['track'])?['durationMs'] as num?) ?? 0)}'),
              trailing: (widget.canManage || queue[i]['addedBy'] == Session.id)
                  ? IconButton(icon: const Icon(Icons.close), onPressed: () => _call(() => Api.delete('$_base/queue/${queue[i]['id']}')))
                  : null,
            ),
        ]);
      },
    );
  }

  Future<void> _addFiles() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (r == null || r.files.isEmpty || !mounted) return;
    setState(() => _progress = '1/${r.files.length} yükleniyor…');
    final res = await LocalMusic.instance.addPickedToRoom(widget.roomId, r.files, onProgress: (d, t) {
      if (mounted) setState(() => _progress = d >= t ? null : '${d + 1}/$t yükleniyor…');
    });
    if (!mounted) return;
    setState(() => _progress = null);
    if (res.added > 0 && res.skipped == 0) {
      toast(context, '${res.added} şarkı listeye eklendi.');
    } else if (res.added > 0) {
      toast(context, '${res.added} şarkı eklendi, ${res.skipped} eklenemedi: ${res.error ?? ''}', error: true);
    } else {
      toast(context, res.error ?? 'Şarkı eklenemedi.', error: true);
    }
  }
}
