import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/local_music.dart';
import '../services/music_service.dart';
import '../services/room_playlist.dart';
import '../widgets/common.dart';

// Müzik çalar (koyu tasarım + Yoho akışı): Müzik listesi, Telefondan Ekle (cihaz taraması), Şimdi Çalıyor
// ve odada alt çubuk. Renkler: neredeyse siyah zemin, turkuaz → pembe vurgu.
const _bg = Color(0xFF07070E);
const _card = Color(0xFF11111B);
const _cardLine = Color(0xFF242433);
const _cyan = Color(0xFF4FD8F5);
const _pink = Color(0xFFF05FA6);
const _dim = Color(0xFF8E8EA8);
const _grad = LinearGradient(colors: [_cyan, _pink]);

String _mmss(num ms) {
  final s = (ms / 1000).floor();
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

String _ext(String path) => path.contains('.') ? path.split('.').last.toLowerCase() : 'mp3';

/// Odadaki "Müzik" düğmesi: yetkiliye müzik listesi, diğerlerine şimdi çalıyor ekranı.
void openRoomMusic(BuildContext context, {required String roomId, required bool canManage}) {
  RoomPlaylist.instance.bind(roomId);
  if (canManage) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MusicLibraryPage(roomId: roomId)));
  } else {
    showNowPlaying(context, roomId: roomId, canManage: false);
  }
}

/// Yuvarlak koyu düğme (başlıktaki simgeler).
Widget _squareBtn(IconData icon, VoidCallback? onTap, {String? tip}) => Tooltip(
      message: tip ?? '',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _cardLine)),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );

Widget _header(BuildContext context, String title, String sub, List<Widget> actions) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(children: [
        _squareBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.maybePop(context), tip: 'Geri'),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            Text(sub, style: const TextStyle(color: _cyan, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
          ]),
        ),
        for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: a),
      ]),
    );

/// Parça kartındaki küçük simge kutusu.
Widget _trackIcon({bool active = false}) => Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? _pink : const Color(0xFF3A3550), width: 1.6),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A1A28), Color(0xFF0D0D16)]),
      ),
      child: Center(
        child: active
            ? const Icon(Icons.graphic_eq_rounded, color: _cyan, size: 22)
            : Container(width: 10, height: 10, decoration: const BoxDecoration(color: _cyan, shape: BoxShape.circle)),
      ),
    );

Widget _gradButton(String label, VoidCallback? onTap, {double height = 44, double fontSize = 15}) => Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(gradient: _grad, borderRadius: BorderRadius.circular(height / 2)),
          child: Text(label, style: TextStyle(color: const Color(0xFF0B0B14), fontWeight: FontWeight.w800, fontSize: fontSize)),
        ),
      ),
    );

// ======================================================================= Müzik listesi
/// "Müzik — N PARÇA": telefondan eklenen şarkılar. Dokununca odada çalar (liste sırayla devam eder).
class MusicLibraryPage extends StatefulWidget {
  final String roomId;
  const MusicLibraryPage({super.key, required this.roomId});

  @override
  State<MusicLibraryPage> createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends State<MusicLibraryPage> {
  bool _search = false;
  final _q = TextEditingController();
  bool _edit = false;

  @override
  void initState() {
    super.initState();
    LocalMusic.instance.load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _openDevice() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceAudioPage()));
    if (mounted) setState(() {});
  }

  Future<void> _play(LocalTrack t) async {
    final r = await guard(context, () async {
      await RoomPlaylist.instance.playTrack(t);
      return true;
    });
    if (r == true && mounted) toast(context, '"${t.title}" odada çalıyor.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: ValueListenableBuilder<List<LocalTrack>>(
          valueListenable: LocalMusic.instance.tracks,
          builder: (context, all, _) {
            final q = _q.text.trim().toLowerCase();
            final list = q.isEmpty ? all : all.where((t) => '${t.title} ${t.artist}'.toLowerCase().contains(q)).toList();
            return Column(children: [
              _header(context, 'Müzik', '${all.length} PARÇA', [
                _squareBtn(Icons.search_rounded, () => setState(() => _search = !_search), tip: 'Ara'),
                _squareBtn(_edit ? Icons.check_rounded : Icons.edit_note_rounded, all.isEmpty ? null : () => setState(() => _edit = !_edit), tip: 'Düzenle'),
                _squareBtn(Icons.folder_open_rounded, _openDevice, tip: 'Telefondan ekle'),
              ]),
              if (_search)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: TextField(
                    controller: _q,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Şarkı ya da sanatçı ara',
                      hintStyle: const TextStyle(color: _dim),
                      prefixIcon: const Icon(Icons.search, color: _dim),
                      filled: true,
                      fillColor: _card,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _cardLine)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _cardLine)),
                    ),
                  ),
                ),
              Expanded(
                child: all.isEmpty
                    ? _empty()
                    : ValueListenableBuilder<String?>(
                        valueListenable: RoomPlaylist.instance.currentPath,
                        builder: (context, cur, _) => ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 110),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _row(list[i], cur == list[i].path),
                        ),
                      ),
              ),
            ]);
          },
        ),
      ),
      bottomSheet: const _LibraryMiniPlayer(),
    );
  }

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _card, border: Border.all(color: const Color(0xFF1F4A55))),
            child: const Icon(Icons.music_note_rounded, color: _cyan, size: 54),
          ),
          const SizedBox(height: 22),
          const Text('Henüz müzik dosyası yok', style: TextStyle(color: _dim, fontSize: 16)),
          const SizedBox(height: 22),
          _gradButton('Telefonunuzdan tara ve ekle', _openDevice, height: 52, fontSize: 16),
        ]),
      );

  Widget _row(LocalTrack t, bool active) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18), border: Border.all(color: active ? _pink.withValues(alpha: 0.6) : _cardLine)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _edit ? null : () => _play(t),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: Row(children: [
            _trackIcon(active: active),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? _cyan : Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                const SizedBox(height: 3),
                Text('${_mmss(t.durationMs)} · ${_ext(t.path)}${t.artist.isEmpty ? '' : ' · ${t.artist}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _dim, fontSize: 12.5)),
              ]),
            ),
            if (_edit)
              IconButton(
                tooltip: 'Listeden kaldır',
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                onPressed: () => LocalMusic.instance.remove(t),
              )
            else
              IconButton(
                tooltip: 'Odada çal',
                icon: Icon(active ? Icons.equalizer_rounded : Icons.play_circle_fill_rounded, color: active ? _pink : _cyan, size: 30),
                onPressed: () => _play(t),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Liste sayfasının altında küçük çalar (çalıyorsa).
class _LibraryMiniPlayer extends StatelessWidget {
  const _LibraryMiniPlayer();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: MusicService.instance.state,
      builder: (context, s, _) {
        final track = mapOf(s?['track']);
        if (track == null) return const SizedBox.shrink();
        return Container(
          color: _bg,
          padding: EdgeInsets.fromLTRB(10, 6, 10, 6 + MediaQuery.paddingOf(context).bottom),
          child: RoomMusicBar(canManage: true, onMinimize: null, onOpen: () => showNowPlaying(context, roomId: null, canManage: true, fromLibrary: true)),
        );
      },
    );
  }
}

// ======================================================================= Telefondan Ekle
/// "Telefondan Ekle — CİHAZ DOSYALARI": telefondaki ses dosyaları taranır, "Ekle" ile Müzik listesine girer.
class DeviceAudioPage extends StatefulWidget {
  const DeviceAudioPage({super.key});

  @override
  State<DeviceAudioPage> createState() => _DeviceAudioPageState();
}

class _DeviceAudioPageState extends State<DeviceAudioPage> with WidgetsBindingObserver {
  List<DeviceAudio>? _files;
  bool _scanning = false;
  bool _needPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalMusic.instance.load();
    _scan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// İzin penceresinden dönünce yeniden taranır.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _needPermission && !_scanning) _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final r = await LocalMusic.scanDevice();
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _needPermission = r == null;
      _files = r ?? const [];
    });
  }

  Future<void> _pickManually() async {
    final added = await LocalMusic.instance.pickToLibrary();
    if (!mounted) return;
    if (added.isNotEmpty) toast(context, '${added.length} şarkı eklendi.');
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _header(context, 'Telefondan Ekle', 'CİHAZ DOSYALARI', [
            _squareBtn(Icons.refresh_rounded, _scanning ? null : _scan, tip: 'Yeniden tara'),
          ]),
          if (files != null && files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
              child: Row(children: [
                Text('${files.length} ses dosyası bulundu', style: const TextStyle(color: _cyan, fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final n = await LocalMusic.instance.addDevice(files);
                    if (context.mounted) toast(context, n == 0 ? 'Hepsi zaten ekli.' : '$n şarkı eklendi.');
                  },
                  child: const Text('Tümünü ekle', style: TextStyle(color: _pink, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          Expanded(child: _body(files)),
        ]),
      ),
    );
  }

  Widget _body(List<DeviceAudio>? files) {
    if (_scanning || files == null) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: _cyan),
        SizedBox(height: 14),
        Text('Telefonundaki müzik dosyaları taranıyor...', style: TextStyle(color: _dim)),
      ]));
    }
    if (_needPermission || files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.library_music_rounded, color: _cyan, size: 56),
            const SizedBox(height: 14),
            Text(
              _needPermission
                  ? 'Müzik dosyalarını görebilmek için açılan pencerede "İzin ver"e dokun.'
                  : (LocalMusic.scanUnsupported ? 'Bu sürümde otomatik tarama yok; dosyaları elle seçebilirsin.' : 'Telefonunda müzik dosyası bulunamadı.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _dim, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 18),
            if (_needPermission) _gradButton('Yeniden tara', _scan),
            const SizedBox(height: 10),
            TextButton(onPressed: _pickManually, child: const Text('Dosyaları elle seç', style: TextStyle(color: _cyan))),
          ]),
        ),
      );
    }
    return ValueListenableBuilder<List<LocalTrack>>(
      valueListenable: LocalMusic.instance.tracks,
      builder: (context, lib, _) {
        final have = {for (final t in lib) t.path};
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
          itemCount: files.length,
          itemBuilder: (_, i) {
            final f = files[i];
            final added = have.contains(f.path);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18), border: Border.all(color: _cardLine)),
              child: Row(children: [
                _trackIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                    const SizedBox(height: 3),
                    Text('${_mmss(f.durationMs)} · ${f.ext}', style: const TextStyle(color: _dim, fontSize: 12.5)),
                  ]),
                ),
                const SizedBox(width: 8),
                if (added)
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: const Color(0xFF181824), borderRadius: BorderRadius.circular(20), border: Border.all(color: _cardLine)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_rounded, color: _cyan, size: 18),
                      SizedBox(width: 6),
                      Text('Eklendi', style: TextStyle(color: _dim, fontWeight: FontWeight.w700)),
                    ]),
                  )
                else
                  _gradButton('Ekle', () => LocalMusic.instance.addDevice([f]), height: 40),
              ]),
            );
          },
        );
      },
    );
  }
}

// ======================================================================= Odadaki alt çubuk
/// Odada çalan şarkı: plak, ad, "Şimdi çalıyor", sonraki, oynat/duraklat, ses. Dokununca Şimdi Çalıyor açılır.
class RoomMusicBar extends StatelessWidget {
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback? onMinimize;
  const RoomMusicBar({super.key, required this.canManage, required this.onOpen, this.onMinimize});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: MusicService.instance.state,
      builder: (context, s, _) {
        final track = mapOf(s?['track']);
        if (track == null) return const SizedBox.shrink();
        final playing = s?['status'] == 'playing';
        return GestureDetector(
          onTap: onOpen,
          onVerticalDragEnd: onMinimize == null ? null : (d) {
            if ((d.primaryVelocity ?? 0) > 200) onMinimize!();
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xEE0F0F1E),
              border: Border.all(color: const Color(0x334FD8F5)),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 4))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                SpinningDisc(size: 52, playing: playing),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((track['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: playing ? _cyan : _dim, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(playing ? 'Şimdi çalıyor' : 'Duraklatıldı', style: TextStyle(color: playing ? _cyan : _dim, fontSize: 12.5)),
                    ]),
                  ]),
                ),
                if (canManage)
                  IconButton(
                    tooltip: 'Sonraki',
                    onPressed: () => guard(context, () async {
                      await RoomPlaylist.instance.next();
                      return true;
                    }),
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 30),
                  ),
                if (canManage) _PlayButton(playing: playing, size: 50),
                if (onMinimize != null)
                  IconButton(tooltip: 'Küçült', onPressed: onMinimize, icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _dim, size: 26)),
              ]),
              const _VolumeRow(color: _cyan, compact: true),
            ]),
          ),
        );
      },
    );
  }
}

/// Oynat / duraklat (yetkili): turkuaz → pembe yuvarlak.
class _PlayButton extends StatelessWidget {
  final bool playing;
  final double size;
  const _PlayButton({required this.playing, required this.size});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final room = MusicService.instance.roomId;
        if (room == null) return;
        guard(context, () => Api.post('/api/rooms/$room/music/${playing ? 'pause' : 'play'}'));
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_cyan, _pink]),
          boxShadow: [BoxShadow(color: _pink.withValues(alpha: 0.35), blurRadius: 14)],
        ),
        child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: const Color(0xFF0B0B14), size: size * 0.55),
      ),
    );
  }
}

/// Ses düzeyi (yalnızca bu telefonda).
class _VolumeRow extends StatelessWidget {
  final Color color;
  final bool compact;
  const _VolumeRow({required this.color, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MusicService.instance.muted,
      builder: (_, muted, __) => Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => MusicService.instance.setMuted(!muted),
          icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white70, size: compact ? 20 : 24),
        ),
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: MusicService.instance.volume,
            builder: (_, v, __) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: color,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: compact ? 8 : 10),
              ),
              child: Slider(value: muted ? 0 : v, onChanged: (x) {
                if (muted) MusicService.instance.setMuted(false);
                MusicService.instance.setVolume(x);
              }),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }
}

/// Dönen plak (çalarken döner).
class SpinningDisc extends StatefulWidget {
  final double size;
  final bool playing;
  const SpinningDisc({super.key, required this.size, required this.playing});

  @override
  State<SpinningDisc> createState() => _SpinningDiscState();
}

class _SpinningDiscState extends State<SpinningDisc> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant SpinningDisc old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return RotationTransition(
      turns: _c,
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(colors: [_cyan, Color(0xFF7F7BFF), _pink, _cyan]),
          boxShadow: [BoxShadow(color: _cyan.withValues(alpha: 0.25), blurRadius: s * 0.25)],
        ),
        padding: EdgeInsets.all(s * 0.06),
        child: Container(
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0C0C16)),
          child: Stack(alignment: Alignment.center, children: [
            for (final f in const [0.82, 0.62])
              Container(
                width: s * f,
                height: s * f,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white10, width: 1)),
              ),
            Container(
              width: s * 0.36,
              height: s * 0.36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF141428), border: Border.all(color: _cyan.withValues(alpha: 0.6), width: 1.4)),
              child: Icon(Icons.music_note_rounded, color: _cyan, size: s * 0.2),
            ),
          ]),
        ),
      ),
    );
  }
}

// ======================================================================= Şimdi çalıyor
/// "ŞİMDİ ÇALIYOR": büyük plak, ad, "Odaya yayınlanıyor", ilerleme, önceki/oynat/sonraki,
/// Karıştır / Tümü (tekrar) / Tek / Liste ve ses düzeyi. Soldaki güç düğmesi müziği durdurur.
Future<void> showNowPlaying(BuildContext context, {required String? roomId, required bool canManage, bool fromLibrary = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) => _NowPlaying(canManage: canManage, roomId: roomId ?? MusicService.instance.roomId, fromLibrary: fromLibrary),
  );
}

class _NowPlaying extends StatefulWidget {
  final bool canManage;
  final String? roomId;
  final bool fromLibrary; // liste sayfasından açıldı: "Liste" yalnızca kapatır
  const _NowPlaying({required this.canManage, required this.roomId, required this.fromLibrary});

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> with SingleTickerProviderStateMixin {
  Timer? _tick;
  double? _drag;
  late final AnimationController _bars;

  @override
  void initState() {
    super.initState();
    _bars = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _drag == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _bars.dispose();
    super.dispose();
  }

  Future<void> _do(Future<void> Function() f) async {
    await guard(context, () async {
      await f();
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      height: mq.size.height * 0.82,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xF2201D3A), Color(0xF20D0C1C)]),
        border: Border.all(color: Colors.white10),
      ),
      child: ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: MusicService.instance.state,
        builder: (context, s, _) {
          final track = mapOf(s?['track']);
          final playing = s?['status'] == 'playing';
          final duration = ((track?['durationMs'] as num?) ?? 0).toDouble();
          final pos = (_drag ?? MusicService.instance.currentPositionMs().toDouble()).clamp(0, duration > 0 ? duration : 1).toDouble();
          final room = widget.roomId;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 14 + mq.padding.bottom),
            child: Column(children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Row(children: [
                if (widget.canManage)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: track == null ? null : () => _do(RoomPlaylist.instance.stop),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(color: const Color(0x33F05FA6), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x55F05FA6))),
                      child: const Icon(Icons.power_settings_new_rounded, color: _pink),
                    ),
                  )
                else
                  const SizedBox(width: 46),
                Expanded(
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 7, height: 7, decoration: const BoxDecoration(color: _cyan, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(track == null ? 'MÜZİK' : 'ŞİMDİ ÇALIYOR', style: const TextStyle(color: _cyan, fontWeight: FontWeight.w800, letterSpacing: 2.4, fontSize: 14)),
                  ]),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.maybePop(context),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                  ),
                ),
              ]),
              const Spacer(),
              SpinningDisc(size: math.min(mq.size.width * 0.58, 260), playing: playing),
              const SizedBox(height: 22),
              Text(track == null ? 'Şu an müzik çalmıyor' : (track['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(track == null ? (widget.canManage ? 'Listeden bir şarkı seç' : 'Müziği oda yetkilileri açar') : (playing ? 'Odaya yayınlanıyor' : 'Duraklatıldı'),
                  style: const TextStyle(color: _dim, fontSize: 15)),
              const SizedBox(height: 14),
              SizedBox(height: 16, child: playing ? _visualizer() : const SizedBox.shrink()),
              const Spacer(),
              if (track != null) ...[
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: _cyan,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Colors.white,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                  ),
                  child: Slider(
                    value: pos,
                    max: duration > 0 ? duration : 1,
                    onChanged: widget.canManage ? (v) => setState(() => _drag = v) : null,
                    onChangeEnd: widget.canManage && room != null
                        ? (v) async {
                            setState(() => _drag = null);
                            await guard(context, () => Api.post('/api/rooms/$room/music/seek', {'positionMs': v.round()}));
                          }
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Text(_mmss(pos), style: const TextStyle(color: _dim)),
                  const Spacer(),
                  Text(_mmss(duration), style: const TextStyle(color: _dim)),
                ]),
              ],
              const SizedBox(height: 14),
              if (widget.canManage)
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(iconSize: 44, onPressed: () => _do(RoomPlaylist.instance.previous), icon: const Icon(Icons.skip_previous_rounded, color: Colors.white)),
                  const SizedBox(width: 26),
                  _PlayButton(playing: playing, size: 76),
                  const SizedBox(width: 26),
                  IconButton(iconSize: 44, onPressed: () => _do(RoomPlaylist.instance.next), icon: const Icon(Icons.skip_next_rounded, color: Colors.white)),
                ]),
              const SizedBox(height: 12),
              const Divider(color: Colors.white12),
              if (widget.canManage)
                ValueListenableBuilder<PlayMode>(
                  valueListenable: RoomPlaylist.instance.mode,
                  builder: (_, m, __) => Row(children: [
                    _modeBtn(Icons.shuffle_rounded, 'Karıştır', m == PlayMode.shuffle, () => RoomPlaylist.instance.mode.value = PlayMode.shuffle),
                    _modeBtn(Icons.repeat_rounded, 'Tümü', m == PlayMode.all, () => RoomPlaylist.instance.mode.value = PlayMode.all),
                    _modeBtn(Icons.repeat_one_rounded, 'Tek', m == PlayMode.one, () => RoomPlaylist.instance.mode.value = PlayMode.one),
                    _modeBtn(Icons.queue_music_rounded, 'Liste', false, () {
                      final r = room;
                      final nav = Navigator.of(context);
                      nav.pop();
                      if (r != null && !widget.fromLibrary) nav.push(MaterialPageRoute(builder: (_) => MusicLibraryPage(roomId: r)));
                    }),
                  ]),
                ),
              const SizedBox(height: 6),
              const _VolumeRow(color: _pink),
            ]),
          );
        },
      ),
    );
  }

  Widget _modeBtn(IconData icon, String label, bool on, VoidCallback onTap) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Icon(icon, color: on ? _cyan : Colors.white70, size: 26),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: on ? _cyan : Colors.white70, fontSize: 13)),
            ]),
          ),
        ),
      );

  /// Küçük ses çubukları (çalarken oynar).
  Widget _visualizer() => AnimatedBuilder(
        animation: _bars,
        builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 5,
              height: 4 + 10 * (0.5 + 0.5 * math.sin((_bars.value * 2 * math.pi) + i * 1.3)).abs(),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(color: i.isEven ? _cyan : _pink, borderRadius: BorderRadius.circular(2)),
            ),
        ]),
      );
}
