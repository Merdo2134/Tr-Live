import 'dart:async';
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
    backgroundColor: Colors.transparent,
    builder: (c) => Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2B1650), Color(0xFF120B24), Color(0xFF0B0816)]),
      ),
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
  int _tab = 0; // 0: çalma listesi, 1: Müziklerim (telefondan seçilen, kalıcı)

  @override
  void initState() {
    super.initState();
    LocalMusic.instance.load();
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
    Widget tab(String label, int i) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                gradient: _tab == i ? const LinearGradient(colors: [Color(0xFFB146F5), Color(0xFFFF4F9A)]) : null,
              ),
              child: Text(label, style: TextStyle(fontWeight: _tab == i ? FontWeight.w800 : FontWeight.w600, color: _tab == i ? Colors.white : Colors.white60)),
            ),
          ),
        );
    return Column(children: [
      const SizedBox(height: 8),
      Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
      _player(),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
        child: Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [tab('Çalma listesi', 0), tab('Müziklerim', 1)]),
            ),
          ),
          const SizedBox(width: 10),
          if (_progress != null)
            Text(_progress!, style: const TextStyle(color: Colors.white70, fontSize: 12))
          else if (widget.canManage || widget.canQueue)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _addFiles,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [Color(0xFF40E3F2), Color(0xFF7F7BFF)])),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, size: 20, color: Colors.white),
                  SizedBox(width: 2),
                  Text('Ekle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
        ]),
      ),
      Expanded(child: _tab == 0 ? _playlist() : _library()),
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
        // Plak: siyah plak görseli, ortasında şarkının kapağı (yeni tasarım).
        Widget disc = SizedBox(
          width: 92,
          height: 92,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 14, offset: Offset(0, 4))]),
              child: ClipOval(child: Image.asset('assets/images/music_disc.png', width: 92, height: 92, fit: BoxFit.cover)),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 1.5), color: const Color(0xFF2A1F45)),
              child: ClipOval(
                child: cover != null
                    ? NetImg(cover, box: const Size.square(36), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.pinkAccent, size: 18))
                    : const Icon(Icons.music_note, color: Colors.pinkAccent, size: 18),
              ),
            ),
          ]),
        );
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [Color(0xFF5B2A9C), Color(0xFFB0306E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: Colors.white12),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6))],
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
                IconButton(tooltip: 'Durdur', onPressed: track == null ? null : () => _call(() => Api.post('$_base/stop')), icon: const Icon(Icons.stop_rounded, size: 26)),
                // Büyük oynat / duraklat düğmesi.
                GestureDetector(
                  onTap: track == null ? null : () => _call(() => playing ? Api.post('$_base/pause') : Api.post('$_base/play')),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.35), blurRadius: 12)],
                    ),
                    child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32, color: const Color(0xFF7B2CBF)),
                  ),
                ),
                IconButton(tooltip: 'Sonraki', onPressed: () => _call(() => Api.post('$_base/next')), icon: const Icon(Icons.skip_next_rounded, size: 30)),
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

  /// Telefondan şarkı seç: önce "Müziklerim"e kalıcı eklenir (bir kez seçmen yeter), sonra odanın listesine.
  Future<void> _addFiles() async {
    final picked = await LocalMusic.instance.pickToLibrary();
    if (picked.isEmpty || !mounted) return;
    setState(() => _progress = '1/${picked.length} yükleniyor…');
    final res = await LocalMusic.instance.addTracksToRoom(widget.roomId, picked, onProgress: (d, t) {
      if (mounted) setState(() => _progress = d >= t ? null : '${d + 1}/$t yükleniyor…');
    });
    if (!mounted) return;
    setState(() => _progress = null);
    if (res.added > 0 && res.skipped == 0) {
      toast(context, '${res.added} şarkı listeye eklendi ve Müziklerim\'e kaydedildi.');
    } else if (res.added > 0) {
      toast(context, '${res.added} şarkı eklendi, ${res.skipped} eklenemedi: ${res.error ?? ''}', error: true);
    } else {
      toast(context, res.error ?? 'Şarkı eklenemedi.', error: true);
    }
  }

  /// Müziklerim: telefondan bir kez seçilen şarkılar burada kalır; dokununca odanın listesine eklenir.
  Widget _library() {
    return ValueListenableBuilder<List<LocalTrack>>(
      valueListenable: LocalMusic.instance.tracks,
      builder: (context, list, _) {
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Henüz şarkın yok.\n"Ekle" ile telefonundan seç; bir kez seçtiğin şarkılar burada kalır.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
            ),
          );
        }
        final canAdd = widget.canManage || widget.canQueue;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) {
            final t = list[i];
            return Container(
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                dense: true,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: [Color(0xFFB146F5), Color(0xFFFF4F9A)])),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 20),
                ),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${t.artist.isEmpty ? 'Bilinmeyen sanatçı' : t.artist} · ${_mmss(t.durationMs)}', style: const TextStyle(color: Colors.white54)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (canAdd)
                    IconButton(
                      tooltip: 'Listeye ekle',
                      icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF40E3F2)),
                      onPressed: _progress != null
                          ? null
                          : () async {
                              setState(() => _progress = 'Yükleniyor…');
                              final r = await guard(context, () async {
                                await LocalMusic.instance.sendToRoom(widget.roomId, t, playNow: false);
                                return true;
                              });
                              if (!mounted) return;
                              setState(() => _progress = null);
                              if (r == true) toast(context, '"${t.title}" listeye eklendi.');
                            },
                    ),
                  IconButton(
                    tooltip: 'Müziklerim\'den kaldır',
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38),
                    onPressed: () async {
                      final ok = await confirm(context, '"${t.title}" Müziklerim\'den kaldırılsın mı?', action: 'Kaldır', destructive: true);
                      if (ok) await LocalMusic.instance.remove(t);
                    },
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}
