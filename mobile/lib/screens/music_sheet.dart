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

class _MusicPanelState extends State<_MusicPanel> with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final AnimationController _disc = AnimationController(vsync: this, duration: const Duration(seconds: 10));
  Timer? _tick;
  final _phoneSearch = TextEditingController();
    double? _dragging; // ilerleme çubuğu sürüklenirken

  final Set<String> _sending = {}; // yüklenmekte olan dosya yolları

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
    LocalMusic.instance.stopPreview();
    _tick?.cancel();
    _tabs.dispose();
    _disc.dispose();
    _phoneSearch.dispose();
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
      TabBar(
        controller: _tabs,
        indicatorColor: Colors.pinkAccent,
        labelColor: Colors.pinkAccent,
        unselectedLabelColor: Colors.white60,
        tabs: const [Tab(text: 'Müziklerim'), Tab(text: 'Sıra')],
      ),
      Expanded(child: TabBarView(controller: _tabs, children: [_phone(), _nowPlaying()])),
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
                  Text((track?['artist'] ?? '').toString().isEmpty ? (playing ? 'Çalıyor' : 'Listeden bir şarkı seç') : track!['artist'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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

  Widget _nowPlaying() {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: MusicService.instance.state,
      builder: (context, s, _) {
        final queue = listOf(s?['queue']);
        if (queue.isEmpty) return const Center(child: Text('Sıra boş. Müziklerim sekmesinden şarkı ekle.', style: TextStyle(color: Colors.white54)));
        return ListView(children: [
          for (final q in queue)
            ListTile(
              dense: true,
              leading: const Icon(Icons.queue_music, color: Colors.pinkAccent),
              title: Text((mapOf(q['track'])?['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text((mapOf(q['track'])?['artist'] ?? '').toString()),
              trailing: (widget.canManage || q['addedBy'] == Session.id)
                  ? IconButton(icon: const Icon(Icons.close), onPressed: () => _call(() => Api.delete('$_base/queue/${q['id']}')))
                  : null,
            ),
        ]);
      },
    );
  }

  Future<void> _addFiles() async {
    try {
      final n = await LocalMusic.instance.pickAndAdd();
      if (mounted && n > 0) toast(context, '$n şarkı eklendi.');
    } catch (e) {
      if (mounted) toast(context, 'Dosyalar eklenemedi.');
    }
  }

  Future<void> _sendToRoom(LocalTrack t) async {
    if (_sending.contains(t.path)) return;
    setState(() => _sending.add(t.path));
    try {
      await LocalMusic.instance.sendToRoom(widget.roomId, t, playNow: widget.canManage);
      if (mounted) toast(context, widget.canManage ? 'Odada çalınıyor.' : 'Sıraya eklendi.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (_) {
      if (mounted) toast(context, 'Şarkı odaya gönderilemedi.');
    } finally {
      if (mounted) setState(() => _sending.remove(t.path));
    }
  }

  String _mb(int b) => '${(b / 1048576).toStringAsFixed(1)} MB';

  Widget _phone() {
    final canSend = widget.canManage || widget.canQueue;
    return ValueListenableBuilder<List<LocalTrack>>(
      valueListenable: LocalMusic.instance.tracks,
      builder: (context, list, _) {
        final q = _phoneSearch.text.trim().toLowerCase();
        final shown = q.isEmpty ? list : list.where((t) => t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q)).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _phoneSearch,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'Telefonumdaki şarkılarda ara', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: _addFiles, icon: const Icon(Icons.add), label: const Text('Ekle')),
            ]),
          ),
          if (!canSend)
            const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 0), child: Text('Şarkıyı odaya göndermek için mikrofonda olmalısınız. Telefonda dinleyebilirsiniz.', style: TextStyle(color: Colors.white54, fontSize: 12))),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.library_music, size: 56, color: Colors.white38),
                        const SizedBox(height: 12),
                        const Text('Telefonundaki şarkıları buradan seç.', textAlign: TextAlign.center),
                        const SizedBox(height: 4),
                        const Text('Seçtiğin şarkıyı odadakilerle birlikte dinleyebilirsin (en fazla 25 MB).', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 16),
                        FilledButton.icon(onPressed: _addFiles, icon: const Icon(Icons.folder_open), label: const Text('Şarkı seç')),
                      ]),
                    ),
                  )
                : ListView(children: [
                    for (final t in shown)
                      ListTile(
                        leading: ValueListenableBuilder<String?>(
                          valueListenable: LocalMusic.instance.previewing,
                          builder: (_, cur, __) => IconButton(
                            tooltip: cur == t.path ? 'Durdur' : 'Telefonda dinle',
                            icon: Icon(cur == t.path ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 32),
                            onPressed: () async {
                              try {
                                await LocalMusic.instance.togglePreview(t);
                              } catch (_) {
                                if (mounted) toast(context, 'Bu dosya çalınamadı.');
                              }
                            },
                          ),
                        ),
                        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${t.artist.isEmpty ? 'Bilinmeyen sanatçı' : t.artist} · ${_mmss(t.durationMs)} · ${_mb(t.sizeBytes)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (_sending.contains(t.path))
                            const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                          else if (canSend)
                            IconButton(
                              tooltip: widget.canManage ? 'Odada çal' : 'Sıraya ekle',
                              icon: Icon(widget.canManage ? Icons.cast : Icons.playlist_add),
                              onPressed: () => _sendToRoom(t),
                            ),
                          IconButton(tooltip: 'Listeden kaldır', icon: const Icon(Icons.close), onPressed: () => LocalMusic.instance.remove(t)),
                        ]),
                      ),
                  ]),
          ),
        ]);
      },
    );
  }
}
