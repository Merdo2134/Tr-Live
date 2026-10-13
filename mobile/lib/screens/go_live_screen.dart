import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/image_pick.dart';
import '../widgets/room_categories.dart';
import '../widgets/room_theme.dart';
import '../widgets/seat_picker.dart';
import '../widgets/video_grid.dart';

/// Yayın türü: Çoklu (görüntülü ızgara), Canlı (yayıncı tam ekran), Sesli (mikrofon koltukları).
enum LiveMode { multi, live, voice }

/// "Yayın başlat" ekranı (Figma). Kapak (varsayılan: profil fotoğrafı), başlık, yayın isim kartı (tür), sesli odada duyuru
/// ve mikrofon modu, çoklu yayında kişi sayısı. Ölçüler oda ekranıyla aynı sistemden (ekran genişliğine oranla) gelir.
/// Başarılı olursa açılan odanın bilgisini döndürür.
class GoLiveScreen extends StatefulWidget {
  final String initialType; // audio | video
  final Map<String, dynamic> profiles; // GET /api/rooms/mine → rooms {audio, video}
  const GoLiveScreen({super.key, required this.initialType, required this.profiles});

  @override
  State<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends State<GoLiveScreen> {
  static const _voiceModes = [2, 5, 8, 9, 12, 15, 20, 30];

  late LiveMode _mode;
  // Sesli ve görüntülü oda sunucuda ayrı kayıtlardır; bilgileri de ayrı tutulur.
  final _titleA = TextEditingController();
  final _titleV = TextEditingController();
  final _annA = TextEditingController();
  RoomCategory _catA = kRoomCategories.first;
  RoomCategory _catV = kRoomCategories.first;
  int _voiceSeats = 8;
  int _gridSeats = 9;
  String _themeA = 'default';
  String _themeV = 'default';
  PickedImage? _coverA;
  PickedImage? _coverV;
  String? _coverUrlA;
  String? _coverUrlV;
  bool _catOpen = false;
  bool _busy = false;

  lk.LocalVideoTrack? _cam;
  bool _camStarting = false;
  bool _camFailed = false;

  bool get _voice => _mode == LiveMode.voice;

  @override
  void initState() {
    super.initState();
    final a = mapOf(widget.profiles['audio']);
    final v = mapOf(widget.profiles['video']);
    if (a != null) {
      _titleA.text = (a['name'] ?? '').toString();
      _annA.text = (a['announcement'] ?? '').toString();
      _catA = _categoryOf(a['tags']);
      final n = (a['seatCount'] as num?)?.toInt();
      if (n != null && _voiceModes.contains(n)) _voiceSeats = n;
      _themeA = (a['theme'] ?? 'default').toString();
      _coverUrlA = a['coverUrl'] as String?;
    }
    if (v != null) {
      _titleV.text = (v['name'] ?? '').toString();
      _catV = _categoryOf(v['tags']);
      final n = (v['seatCount'] as num?)?.toInt();
      if (n != null && kVideoGridModes.contains(n)) _gridSeats = n;
      _themeV = (v['theme'] ?? 'default').toString();
      _coverUrlV = v['coverUrl'] as String?;
    }
    _mode = widget.initialType == 'audio' ? LiveMode.voice : (v?['layout'] == 'live' ? LiveMode.live : LiveMode.multi);
    if (!_voice) _startCam();
  }

  RoomCategory _categoryOf(dynamic tags) {
    if (tags is List && tags.isNotEmpty) return roomCategoryOf(tags.first?.toString()) ?? kRoomCategories.first;
    return kRoomCategories.first;
  }

  @override
  void dispose() {
    _titleA.dispose();
    _titleV.dispose();
    _annA.dispose();
    final t = _cam;
    _cam = null;
    if (t != null) _release(t);
    super.dispose();
  }

  // ---------- Kamera önizlemesi (Canlı / Çoklu) ----------
  Future<void> _startCam() async {
    if (_cam != null || _camStarting) return;
    _camStarting = true;
    if (_camFailed && mounted) setState(() => _camFailed = false);
    try {
      final t = await lk.LocalVideoTrack.createCameraTrack(const lk.CameraCaptureOptions(cameraPosition: lk.CameraPosition.front));
      if (!mounted || _voice || _cam != null) {
        await _release(t);
        return;
      }
      setState(() => _cam = t);
    } catch (_) {
      if (mounted) setState(() => _camFailed = true);
    } finally {
      _camStarting = false;
    }
  }

  static Future<void> _release(lk.LocalVideoTrack t) async {
    try {
      await t.stop();
      await t.dispose();
    } catch (_) {/* kamera zaten kapanmış olabilir */}
  }

  /// Kamera serbest bırakılır (oda açılınca aynı kamerayı oda kullanacak). Önce önizleme ekrandan kalkar,
  /// sonra kamera kapatılır (kapanan kamerayı gösteren bir görüntü kalmasın).
  Future<void> _stopCam() async {
    final t = _cam;
    if (t == null) return;
    if (mounted) {
      setState(() => _cam = null);
      await WidgetsBinding.instance.endOfFrame;
    } else {
      _cam = null;
    }
    await _release(t);
  }

  void _setMode(LiveMode m) {
    if (m == _mode || _busy) return;
    setState(() {
      _mode = m;
      _catOpen = false;
    });
    if (_voice) {
      _stopCam();
    } else {
      _startCam();
    }
  }

  // ---------- Eylemler ----------
  Future<void> _pickCover() async {
    final img = await pickImage(context, crop: CropSpec.roomCover);
    if (img == null || !mounted) return;
    setState(() {
      if (_voice) {
        _coverA = img;
      } else {
        _coverV = img;
      }
    });
  }

  Future<void> _pickTheme() async {
    var theme = _voice ? _themeA : _themeV;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Oda teması', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              ThemePicker(value: theme, onChanged: (v) => setS(() => theme = v)),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Uygula'))),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      if (_voice) {
        _themeA = theme;
      } else {
        _themeV = theme;
      }
    });
  }

  Future<void> _start() async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final voice = _voice;
    final title = (voice ? _titleA : _titleV).text.trim();
    if (title.length < 2) {
      toast(context, 'Yayın başlığı en az 2 karakter olmalı.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _catOpen = false;
    });
    final body = <String, dynamic>{
      'setup': true,
      'roomType': voice ? 'audio' : 'video',
      'name': title,
      'tags': [(voice ? _catA : _catV).tag],
      'theme': voice ? _themeA : _themeV,
      if (voice) 'seatCount': _voiceSeats,
      if (voice) 'announcement': _annA.text.trim(),
      if (!voice) 'layout': _mode == LiveMode.live ? 'live' : 'grid',
      if (_mode == LiveMode.multi) 'seatCount': _gridSeats,
    };
    final r = await guard(context, () => Api.post('/api/rooms', body));
    final room = mapOf(r?['room']);
    if (room == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final cover = voice ? _coverA : _coverV;
    if (cover != null) {
      try {
        final up = await Api.putBytes('/api/rooms/${room['id']}/cover', cover.bytes, cover.mime);
        room['coverUrl'] = up['url'];
      } catch (e) {
        if (mounted) toast(context, 'Oda açıldı ama fotoğraf yüklenemedi: ${errorText(e)}', error: true);
      }
    }
    await _stopCam();
    if (mounted) Navigator.of(context).pop(room);
  }

  // ---------- Arayüz ----------
  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      // Ölçüler sabit: telefonun yazı boyutu ayarı düzeni kaydırmasın (oda ekranı gibi).
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: const Color(0xFF0B1030),
        body: LayoutBuilder(builder: (context, box) => _body(box.maxWidth, box.maxHeight)),
      ),
    );
  }

  Widget _body(double w, double h) {
    final pad = MediaQuery.paddingOf(context);
    final m = homeMargin(w);
    // Ölçüler ekran genişliğine oranlı (oda ekranıyla aynı sistem), telefon boyutuna göre dp sınırlarıyla.
    final closeD = (w * 0.08).clamp(28.0, 40.0).toDouble();
    final coverS = (w * 0.205).clamp(66.0, 92.0).toDouble();
    final pillH = (w * 0.078).clamp(28.0, 36.0).toDouble();
    final pillGap = (w * 0.026).clamp(8.0, 12.0).toDouble();
    final infoTop = pad.top + 10 + closeD + (w * 0.03).clamp(8.0, 16.0).toDouble();
    final pillsLeft = m + coverS + (w * 0.03).clamp(8.0, 14.0).toDouble();
    // İki kutu kapağın ortasına hizalı (Figma).
    final pillsTop = infoTop + (coverS - (2 * pillH + pillGap)) / 2;
    final annTop = infoTop + coverS + (w * 0.03).clamp(8.0, 14.0).toDouble();
    final infoBottom = _voice ? annTop + pillH : infoTop + coverS;

    // Alttan yukarı: başlat satırı, tür düğmeleri, (çoklu) kişi sayısı.
    final bottomPad = pad.bottom + (w * 0.05).clamp(14.0, 24.0).toDouble();
    final startH = (w * 0.113).clamp(40.0, 52.0).toDouble();
    final startTop = h - bottomPad - startH;
    final modeD = (w * 0.112).clamp(40.0, 52.0).toDouble();
    final modeBlockH = modeD + 6 + 16;
    final modesTop = startTop - (w * 0.055).clamp(16.0, 24.0).toDouble() - modeBlockH;
    final chipH = (w * 0.07).clamp(24.0, 30.0).toDouble();
    final chipsTop = modesTop - (w * 0.04).clamp(12.0, 18.0).toDouble() - chipH;
    final contentTop = infoBottom + (w * 0.035).clamp(10.0, 16.0).toDouble();
    final contentBottom = (_mode == LiveMode.multi ? chipsTop : modesTop) - (w * 0.03).clamp(8.0, 14.0).toDouble();

    final camera = _mode == LiveMode.live;
    final cardBottom = pillsTop + pillH * 2 + pillGap;

    return Stack(fit: StackFit.expand, children: [
      // Zemin: canlı yayında kamera önizlemesi; diğerlerinde mor → lacivert → turkuaz geçiş ve iki yumuşak ışık.
      if (camera) Positioned.fill(child: _cameraBackdrop()) else ..._background(),
      if (camera) ...[
        const Positioned(left: 0, right: 0, top: 0, height: 230, child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: _topScrim)))),
        const Positioned(left: 0, right: 0, bottom: 0, height: 280, child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: _bottomScrim)))),
      ],
      // İçerik: sesli → mikrofon modları, çoklu → kişi ızgarası.
      if (_mode == LiveMode.voice)
        Positioned(left: m, right: m, top: contentTop, height: math.max(0.0, contentBottom - contentTop), child: _voiceModesGrid(w)),
      if (_mode == LiveMode.multi)
        Positioned(left: 0, right: 0, top: contentTop, height: math.max(0.0, contentBottom - contentTop), child: _gridPreview()),
      // Kapat
      Positioned(
        right: m,
        top: pad.top + 10,
        width: closeD,
        height: closeD,
        child: Material(
          color: const Color(0x73140A24),
          shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.14))),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _busy ? null : () => Navigator.of(context).pop(),
            child: Icon(Icons.close_rounded, color: Colors.white, size: closeD * 0.6),
          ),
        ),
      ),
      // Kapak + başlık + yayın isim kartı (+ sesli odada duyuru)
      Positioned(left: m, top: infoTop, width: coverS, height: coverS, child: _coverBox(coverS)),
      Positioned(left: pillsLeft, right: m, top: pillsTop, height: pillH, child: _fieldPill(pillH, _voice ? _titleA : _titleV, 'Yayın başlığı giriniz', 60)),
      Positioned(left: pillsLeft, right: m, top: pillsTop + pillH + pillGap, height: pillH, child: _cardPill(pillH)),
      if (_voice)
        Positioned(left: m, right: m, top: annTop, height: pillH, child: _fieldPill(pillH, _annA, 'Oda duyurusu (isteğe bağlı)', 200, icon: Icons.campaign_outlined)),
      // Çoklu: kişi sayısı
      if (_mode == LiveMode.multi) Positioned(left: 0, right: 0, top: chipsTop, height: chipH, child: _seatChips(chipH)),
      // Tür düğmeleri
      Positioned(left: 0, right: 0, top: modesTop, height: modeBlockH, child: _modeButtons(w, modeD)),
      // Güzellik · Başlat · Oda teması
      Positioned(left: m, right: m, top: startTop, height: startH, child: _startRow(startH, (w * 0.025).clamp(8.0, 12.0).toDouble())),
      // Yayın isim kartı listesi (açılır): dışına dokununca kapanır.
      if (_catOpen) ...[
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _catOpen = false))),
        Positioned(left: pillsLeft, right: m, top: cardBottom + 6, child: _categoryPanel(w)),
      ],
    ]);
  }

  /// Figma zemini: dikey renk geçişi + sağ üstte mor, sol altta turkuaz yumuşak ışık.
  List<Widget> _background() => const [
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: _bgGradient))),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: _glowTop))),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: _glowBottom))),
      ];

  static const _bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF6F1A93), Color(0xFF4F1C8C), Color(0xFF24308F), Color(0xFF0B5E9F), Color(0xFF0B9CAC)],
    stops: [0, 0.24, 0.52, 0.74, 1],
  );
  static const _glowTop = RadialGradient(center: Alignment(0.7, -0.84), radius: 0.9, colors: [Color(0x73BE3CE6), Color(0x00BE3CE6)]);
  static const _glowBottom = RadialGradient(center: Alignment(-0.8, 0.84), radius: 0.9, colors: [Color(0x5914D2DC), Color(0x0014D2DC)]);
  static const _topScrim = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x8C000000), Color(0x00000000)]);
  static const _bottomScrim = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xA6000000)]);

  Widget _cameraBackdrop() {
    final cam = _cam;
    if (cam != null) return lk.VideoTrackRenderer(cam, fit: lk.VideoViewFit.cover);
    return ColoredBox(
      color: const Color(0xFF0B1030),
      child: Center(
        child: _camFailed
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.videocam_off, color: Colors.white54, size: 48),
                const SizedBox(height: 10),
                const Text('Kamera açılamadı. Kamera iznini kontrol et.', style: TextStyle(color: Colors.white70)),
                TextButton(onPressed: _startCam, child: const Text('Tekrar dene')),
              ])
            : const CircularProgressIndicator(),
      ),
    );
  }

  /// Oda fotoğrafı: seçilmediyse kayıtlı kapak, o da yoksa profil fotoğrafı. Dokununca yeni fotoğraf seçilir (kırpılarak).
  Widget _coverBox(double s) {
    final picked = _voice ? _coverA : _coverV;
    final url = Api.absoluteUrl(_voice ? _coverUrlA : _coverUrlV) ?? Api.absoluteUrl(Session.me.value?['avatarUrl'] as String?);
    final Widget image = picked != null
        ? Image.memory(picked.bytes, fit: BoxFit.cover, gaplessPlayback: true)
        : url != null
            ? NetImg(url, box: Size.square(s), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _CoverPlaceholder())
            : const _CoverPlaceholder();
    final badge = s * 0.3;
    return GestureDetector(
      onTap: _busy ? null : _pickCover,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.5),
          child: Stack(fit: StackFit.expand, children: [
            image,
            Positioned(
              right: 4,
              bottom: 4,
              width: badge,
              height: badge,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFC04BF2), Color(0xFF5B6CFF)]),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Icon(Icons.photo_camera_rounded, color: Colors.white, size: badge * 0.55),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _pillBox(double h, Widget child, {VoidCallback? onTap}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: h,
          padding: EdgeInsets.only(left: h * 0.5, right: h * 0.3),
          decoration: BoxDecoration(
            color: const Color(0xCC1C0A33),
            borderRadius: BorderRadius.circular(h / 2),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3))],
          ),
          child: child,
        ),
      );

  Widget _fieldPill(double h, TextEditingController ctl, String hint, int max, {IconData? icon}) {
    final fs = h * 0.46;
    return _pillBox(
      h,
      Row(children: [
        if (icon != null) Padding(padding: const EdgeInsets.only(right: 6), child: Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: fs * 1.25)),
        Expanded(
          child: TextField(
          controller: ctl,
          maxLength: max,
          maxLines: 1,
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          style: TextStyle(color: Colors.white, fontSize: fs, fontWeight: FontWeight.w600),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            isDense: true,
            filled: false,
            counterText: '',
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: fs, fontWeight: FontWeight.w600),
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
          ),
        ),
        ),
      ]),
    );
  }

  Widget _cardPill(double h) {
    final cat = _voice ? _catA : _catV;
    return _pillBox(
      h,
      Row(children: [
        Expanded(
          child: Text('Yayın isim kartı', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: h * 0.46, fontWeight: FontWeight.w600)),
        ),
        CategoryChip(category: cat, height: h * 0.64),
        SizedBox(width: h * 0.12),
        Icon(_catOpen ? Icons.keyboard_arrow_down_rounded : Icons.chevron_right_rounded, color: Colors.white, size: h * 0.7),
      ]),
      onTap: _busy ? null : () => setState(() => _catOpen = !_catOpen),
    );
  }

  Widget _categoryPanel(double w) {
    final chipH = (w * 0.058).clamp(22.0, 28.0).toDouble();
    final sel = _voice ? _catA : _catV;
    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      final cw = (box.maxWidth - 16 - gap * 2) / 3;
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xE61C0A33),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Wrap(spacing: gap, runSpacing: gap, children: [
          for (final c in kRoomCategories)
            SizedBox(
              width: cw,
              child: CategoryChip(
                category: c,
                height: chipH,
                selected: c == sel,
                onTap: () => setState(() {
                  if (_voice) {
                    _catA = c;
                  } else {
                    _catV = c;
                  }
                  _catOpen = false;
                }),
              ),
            ),
        ]),
      );
    });
  }

  /// Sesli: mikrofon modları (3 sütun). Önizlemedeki yerleşim odadaki koltuk yerleşimiyle aynıdır.
  Widget _voiceModesGrid(double w) {
    final gap = (w * 0.016).clamp(5.0, 8.0).toDouble();
    final themeColors = _themeA == 'default' ? null : themeOf(_themeA).colors;
    return LayoutBuilder(builder: (context, box) {
      final rows = (_voiceModes.length / 3).ceil();
      final tile = math.max(0.0, math.min((box.maxWidth - gap * 2) / 3, (box.maxHeight - gap * (rows - 1)) / rows));
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: tile * 3 + gap * 2,
          child: Wrap(spacing: gap, runSpacing: gap, children: [
            for (final n in _voiceModes)
              GestureDetector(
                onTap: () => setState(() => _voiceSeats = n),
                child: Container(
                  width: tile,
                  height: tile,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: n == _voiceSeats ? const Color(0xFFFFE04B) : Colors.white.withValues(alpha: 0.12), width: n == _voiceSeats ? 2.4 : 1),
                    boxShadow: n == _voiceSeats ? const [BoxShadow(color: Color(0x73FFE04B), blurRadius: 12)] : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(n == _voiceSeats ? 9.6 : 11),
                    child: Stack(fit: StackFit.expand, children: [
                      SeatModeThumb(n, colors: themeColors),
                      // Kaç mikrofonlu olduğu sol altta küçük yazı; seçili olanda sağ üstte onay.
                      Positioned(
                        left: 6,
                        bottom: 4,
                        child: Text('$n', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: tile * 0.11, fontWeight: FontWeight.w800, shadows: const [Shadow(color: Colors.black54, blurRadius: 3)])),
                      ),
                      if (n == _voiceSeats)
                        Positioned(
                          right: 5,
                          top: 5,
                          child: Container(
                            width: tile * 0.17,
                            height: tile * 0.17,
                            decoration: const BoxDecoration(color: Color(0xFFFFE04B), shape: BoxShape.circle),
                            child: Icon(Icons.check_rounded, size: tile * 0.13, color: const Color(0xFF2B2100)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }

  /// Çoklu: odadaki görüntü ızgarasının önizlemesi; yayıncının hücresinde kamera.
  Widget _gridPreview() {
    final spec = videoGridFor(_gridSeats);
    return LayoutBuilder(builder: (context, box) {
      final gw = math.min(box.maxWidth, box.maxHeight / spec.aspect);
      final cam = _cam;
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: gw,
          height: gw * spec.aspect,
          child: Stack(children: [
            for (var i = 0; i < spec.cells.length; i++)
              Positioned(
                left: spec.cells[i].left * gw,
                top: spec.cells[i].top * gw,
                width: spec.cells[i].width * gw,
                height: spec.cells[i].height * gw,
                child: i == 0
                    ? Container(
                        decoration: BoxDecoration(color: kGridHostFill, border: Border.all(color: kGridLine, width: 0.5)),
                        child: cam != null
                            ? lk.VideoTrackRenderer(cam, fit: lk.VideoViewFit.cover)
                            : Center(child: _camFailed ? const Icon(Icons.videocam_off, color: Colors.white54) : const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    : Container(
                        decoration: BoxDecoration(color: kGridEmptyFill, border: Border.all(color: kGridLine, width: 0.5)),
                        child: Icon(kEmptySeatIcon, color: Colors.white.withValues(alpha: 0.8), size: math.min(spec.cells[i].width, spec.cells[i].height) * gw * 0.32),
                      ),
              ),
          ]),
        ),
      );
    });
  }

  /// Çoklu yayın kişi sayısı: yarı saydam bir şerit içinde 4 seçenek, seçili olan açık zeminli.
  Widget _seatChips(double h) {
    final cw = h * 2.3;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: const Color(0x38000000), borderRadius: BorderRadius.circular(h / 2)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final n in kVideoGridModes)
            GestureDetector(
              onTap: () => setState(() => _gridSeats = n),
              child: Container(
                width: cw,
                height: h - 4,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(color: n == _gridSeats ? Colors.white.withValues(alpha: 0.35) : Colors.transparent, borderRadius: BorderRadius.circular(h / 2)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.weekend_rounded, size: h * 0.56, color: Colors.white),
                  const SizedBox(width: 3),
                  Text('$n', style: TextStyle(color: Colors.white, fontSize: h * 0.52, fontWeight: FontWeight.w800, height: 1.0)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _modeButtons(double w, double d) {
    Widget item(LiveMode m, IconData icon, String label) {
      final sel = _mode == m;
      return SizedBox(
        width: w * 0.23,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _setMode(m),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: sel ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFC04BF2), Color(0xFF5B6CFF)]) : null,
                color: sel ? null : (_mode == LiveMode.live ? const Color(0x8C000000) : const Color(0xBF0E2A3A)),
                border: sel ? null : Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: sel ? const [BoxShadow(color: Color(0x99A050F0), blurRadius: 14)] : null,
              ),
              child: Icon(icon, color: Colors.white, size: d * 0.52),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 16,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(color: Colors.white.withValues(alpha: sel ? 1 : 0.85), fontSize: 12, fontWeight: sel ? FontWeight.w800 : FontWeight.w600, height: 1.2),
                ),
              ),
            ),
          ]),
        ),
      );
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      item(LiveMode.multi, Icons.groups_outlined, 'Çoklu Yayın'),
      item(LiveMode.live, Icons.video_camera_front_outlined, 'Canlı Yayın'),
      item(LiveMode.voice, Icons.mic_none, 'Sesli Yayın'),
    ]);
  }

  Widget _startRow(double h, double gap) {
    final label = switch (_mode) {
      LiveMode.multi => 'Çoklu yayına başla',
      LiveMode.live => 'Canlı yayına başla',
      LiveMode.voice => 'Sesli yayına başla',
    };
    Widget side(IconData icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: Material(
            color: const Color(0xCC0C2B36),
            shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
            child: InkWell(customBorder: const CircleBorder(), onTap: _busy ? null : onTap, child: SizedBox(width: h, height: h, child: Icon(icon, color: Colors.white, size: h * 0.52))),
          ),
        );
    return Row(children: [
      side(Icons.face_retouching_natural, 'Güzellik', () => toast(context, 'Güzellik filtresi yakında eklenecek.')),
      SizedBox(width: gap),
      Expanded(
        child: GestureDetector(
          onTap: _start,
          child: Container(
            height: h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(h / 2),
              gradient: const LinearGradient(colors: [Color(0xFFB47AF7), Color(0xFF7FB0F7), Color(0xFF40E3F2)]),
              boxShadow: const [BoxShadow(color: Color(0x5940E3F2), blurRadius: 14, offset: Offset(0, 4))],
            ),
            child: _busy
                ? SizedBox(width: h * 0.45, height: h * 0.45, child: const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(label, maxLines: 1, style: TextStyle(color: Colors.white, fontSize: h * 0.37, fontWeight: FontWeight.w800, letterSpacing: 0.3, shadows: const [Shadow(color: Color(0x40000000), blurRadius: 4)])),
          ),
        ),
      ),
      SizedBox(width: gap),
      side(Icons.auto_fix_high, 'Oda teması', _pickTheme),
    ]);
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Pal.surfaceHi, child: Center(child: Icon(Icons.person, color: Colors.white38, size: 36)));
}
