import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
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
    showDragHandle: true,
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
  late final TabController _tabs = TabController(length: 2, vsync: this);
  Timer? _tick;
  final _search = TextEditingController();
  int _libVersion = 0;
  double? _dragging; // ilerleme çubuğu sürüklenirken

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
    _tabs.dispose();
    _search.dispose();
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
      TabBar(controller: _tabs, tabs: const [Tab(text: 'Çalan ve sıra'), Tab(text: 'Kütüphane')]),
      Expanded(child: TabBarView(controller: _tabs, children: [_nowPlaying(), _library()])),
    ]);
  }

  Widget _nowPlaying() {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: MusicService.instance.state,
      builder: (context, s, _) {
        final track = mapOf(s?['track']);
        final status = (s?['status'] ?? 'stopped').toString();
        final queue = listOf(s?['queue']);
        final duration = ((track?['durationMs'] as num?) ?? 0).toDouble();
        final position = (_dragging ?? MusicService.instance.currentPositionMs().toDouble()).clamp(0, duration > 0 ? duration : 1).toDouble();
        final cover = Api.absoluteUrl(track?['coverUrl'] as String?);
        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: cover != null
                  ? Image.network(cover, width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 72, child: Icon(Icons.music_note, size: 32)))
                  : const SizedBox(width: 72, height: 72, child: Icon(Icons.music_note, size: 32)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(track?['title']?.toString() ?? 'Şu an müzik çalmıyor', style: Theme.of(context).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                if ((track?['artist'] ?? '').toString().isNotEmpty) Text(track!['artist'].toString(), style: const TextStyle(color: Colors.white60)),
                Text(status == 'playing' ? 'Çalıyor' : status == 'paused' ? 'Duraklatıldı' : 'Durdu', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),
          ]),
          if (track != null) ...[
            Slider(
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
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_mmss(position)), Text(_mmss(duration))]),
          ],
          if (widget.canManage)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filled(
                iconSize: 32,
                onPressed: () => _call(() => status == 'playing' ? Api.post('$_base/pause') : Api.post('$_base/play')),
                icon: Icon(status == 'playing' ? Icons.pause : Icons.play_arrow),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(tooltip: 'Sonraki', onPressed: () => _call(() => Api.post('$_base/next')), icon: const Icon(Icons.skip_next)),
              const SizedBox(width: 12),
              IconButton.filledTonal(tooltip: 'Durdur', onPressed: track == null ? null : () => _call(() => Api.post('$_base/stop')), icon: const Icon(Icons.stop)),
            ])
          else
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Müziği oda yetkilileri yönetir. Siz yalnızca kendi ses seviyenizi ayarlayabilirsiniz.', style: TextStyle(color: Colors.white54, fontSize: 12))),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: MusicService.instance.muted,
            builder: (_, muted, __) => ValueListenableBuilder<double>(
              valueListenable: MusicService.instance.volume,
              builder: (_, vol, __) => Row(children: [
                IconButton(onPressed: () => MusicService.instance.setMuted(!muted), icon: Icon(muted ? Icons.volume_off : Icons.volume_up)),
                Expanded(child: Slider(value: vol, onChanged: (v) => MusicService.instance.setVolume(v))),
              ]),
            ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: MusicService.instance.error,
            builder: (_, e, __) => e == null ? const SizedBox.shrink() : Text(e, style: const TextStyle(color: Colors.redAccent)),
          ),
          const Divider(),
          Text('Sıradakiler (${queue.length})', style: Theme.of(context).textTheme.titleSmall),
          if (queue.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Sıra boş. Kütüphane sekmesinden şarkı ekleyin.')),
          for (final q in queue)
            ListTile(
              dense: true,
              leading: const Icon(Icons.queue_music),
              title: Text((mapOf(q['track'])?['title'] ?? '').toString()),
              subtitle: Text((mapOf(q['track'])?['artist'] ?? '').toString()),
              trailing: (widget.canManage || q['addedBy'] == Session.id)
                  ? IconButton(icon: const Icon(Icons.close), onPressed: () => _call(() => Api.delete('$_base/queue/${q['id']}')))
                  : null,
            ),
        ]);
      },
    );
  }

  Widget _library() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => setState(() => _libVersion++),
          decoration: InputDecoration(
            hintText: 'Şarkı veya sanatçı ara',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => setState(() => _libVersion++)),
          ),
        ),
      ),
      if (!widget.canQueue && !widget.canManage)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Şarkı eklemek için mikrofonda olmalısınız.', style: TextStyle(color: Colors.white54))),
      Expanded(
        child: AsyncBody<List<Map<String, dynamic>>>(
          key: ValueKey('$_libVersion'),
          load: () async => listOf((await Api.get('/api/music/tracks', query: {'q': _search.text.trim()}))['tracks']),
          builder: (context, tracks, reload) => tracks.isEmpty
              ? const Center(child: Text('Kütüphanede şarkı yok.'))
              : ListView(children: [
                  for (final t in tracks)
                    ListTile(
                      leading: const Icon(Icons.music_note),
                      title: Text((t['title'] ?? '').toString()),
                      subtitle: Text('${t['artist'] ?? ''} · ${_mmss((t['durationMs'] as num?) ?? 0)}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (widget.canManage) IconButton(tooltip: 'Hemen çal', icon: const Icon(Icons.play_circle_outline), onPressed: () => _call(() => Api.post('$_base/play', {'trackId': t['id']}))),
                        if (widget.canManage || widget.canQueue)
                          IconButton(tooltip: 'Sıraya ekle', icon: const Icon(Icons.playlist_add), onPressed: () => _call(() => Api.post('$_base/queue', {'trackId': t['id']}), done: 'Sıraya eklendi.')),
                      ]),
                    ),
                ]),
        ),
      ),
    ]);
  }
}
