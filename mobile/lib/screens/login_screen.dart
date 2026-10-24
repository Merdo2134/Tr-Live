import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// Giriş / kayıt: Google, Facebook, telefon numarası ya da kullanıcı adı + şifre.
enum _Mode { start, phone, username }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _id = TextEditingController(); // telefon ya da kullanıcı adı
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  _Mode _mode = _Mode.start;
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  Map<String, dynamic> _providers = const {'google': false, 'facebook': false, 'phone': true};
  bool _socialCancelled = false;

  // Arka plandaki ağır ağır süzülen altın tozları ve açılış animasyonu.
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();

  @override
  void initState() {
    super.initState();
    AuthService.providers().then((p) {
      if (mounted) setState(() => _providers = p);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _id.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  void _goHome() => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);

  void _setMode(_Mode m, {bool register = false}) {
    setState(() {
      _mode = m;
      _register = register;
      _id.clear();
      _password.clear();
      _displayName.clear();
    });
  }

  String? _validate() {
    final id = _id.text.trim();
    if (_mode == _Mode.phone) {
      final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 10) return 'Telefon numaranızı girin (ör. 0555 123 45 67).';
      if (_register && _displayName.text.trim().isEmpty) return 'Görünen adınızı yazın.';
    } else {
      if (id.length < 3) return 'Kullanıcı adınızı girin.';
      if (_register && !RegExp(r'^[a-zA-Z0-9._]{3,30}$').hasMatch(id)) {
        return 'Kullanıcı adı 3-30 karakter olmalı; yalnızca harf, rakam, nokta ve alt çizgi kullanılabilir.';
      }
    }
    if (_password.text.length < 6) return 'Şifre en az 6 karakter olmalı.';
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final problem = _validate();
    if (problem != null) {
      toast(context, problem, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final id = _id.text.trim();
      if (_mode == _Mode.phone && _register) {
        await AuthService.registerPhone(id, _password.text, _displayName.text.trim());
      } else if (_mode == _Mode.username && _register) {
        final name = _displayName.text.trim();
        await AuthService.register(id.toLowerCase(), _password.text, name.isEmpty ? id : name);
      } else {
        // Sunucu girilen değerin telefon mu kullanıcı adı mı olduğunu kendisi ayırır.
        await AuthService.login(_mode == _Mode.username ? id.replaceAll('İ', 'i').toLowerCase() : id, _password.text);
      }
      if (!mounted) return;
      _goHome();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, errorText(e), error: true);
    }
  }

  Future<void> _social(String provider, String label) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _socialCancelled = false;
    });
    // Bekleme penceresi: kullanıcı tarayıcıda onay verip dönünce kendiliğinden kapanır.
    var dialogOpen = true;
    final hint = ValueNotifier<String>('$label ile girişi tarayıcıda tamamlayın.\nOnay verdikten sonra uygulamaya dönün.');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      // Geri tuşu pencereyi kapatmasın (kapatma yalnızca "Vazgeç" ile; bekleme de onunla biter).
      builder: (d) => PopScope(
        canPop: false,
        child: AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 6),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          ValueListenableBuilder<String>(valueListenable: hint, builder: (_, t, __) => Text(t, textAlign: TextAlign.center)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              _socialCancelled = true;
              dialogOpen = false;
              Navigator.pop(d);
            },
            child: const Text('Vazgeç'),
          ),
        ],
      ),
      ),
    ).whenComplete(() => dialogOpen = false);
    try {
      await AuthService.social(
        provider,
        cancelled: () => _socialCancelled || !mounted,
        onWaitingApp: () => hint.value = 'Onay alındı. Tarayıcıya dönüp "TR Live\'a dön" düğmesine dokunun.',
      );
      if (!mounted) return;
      if (dialogOpen) Navigator.of(context).pop();
      if (_socialCancelled) {
        setState(() => _busy = false);
        return;
      }
      _goHome();
    } catch (e) {
      if (!mounted) return;
      if (dialogOpen) Navigator.of(context).pop();
      setState(() => _busy = false);
      toast(context, errorText(e), error: true);
    }
  }

  // ---------------- Görünüm: logo ile aynı siyah-altın tema ----------------

  Widget _goldButton({required IconData icon, required String text, required VoidCallback? onTap, bool busy = false}) => _Pressable(
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_Gold.light, _Gold.mid, _Gold.deep, _Gold.mid],
              stops: [0, 0.38, 0.78, 1],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: _Gold.mid.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 6))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: busy
              ? const Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: _Gold.ink)))
              : Row(children: [
                  Icon(icon, color: _Gold.ink, size: 22),
                  Expanded(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: _Gold.ink, fontSize: 16.5, fontWeight: FontWeight.w800, letterSpacing: 0.3))),
                  const SizedBox(width: 22),
                ]),
        ),
      );

  Widget _outlineButton({required Widget leading, required String text, required VoidCallback? onTap, Color fill = const Color(0xCC0B0906), Color fg = _Gold.light}) => _Pressable(
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _Gold.mid.withValues(alpha: 0.75), width: 1.3),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            SizedBox(width: 24, child: Center(child: leading)),
            Expanded(child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3))),
            const SizedBox(width: 24),
          ]),
        ),
      );

  Widget _start() => Column(key: const ValueKey('start'), mainAxisSize: MainAxisSize.min, children: [
        _goldButton(icon: Icons.phone_iphone_rounded, text: 'Telefon numarası ile', onTap: _busy ? null : () => _setMode(_Mode.phone)),
        const SizedBox(height: 14),
        _outlineButton(
          leading: const Icon(Icons.person_rounded, color: _Gold.light, size: 22),
          text: 'Kullanıcı adı ile',
          onTap: _busy ? null : () => _setMode(_Mode.username),
        ),
        if (_providers['google'] == true || _providers['facebook'] == true) ...[
          const SizedBox(height: 22),
          const _OrDivider(),
          const SizedBox(height: 18),
        ],
        if (_providers['google'] == true) ...[
          _outlineButton(
            leading: const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF4285F4))),
            text: 'Google ile devam et',
            fill: Colors.white,
            fg: const Color(0xFF1F2937),
            onTap: _busy ? null : () => _social('google', 'Google'),
          ),
          const SizedBox(height: 12),
        ],
        if (_providers['facebook'] == true)
          _outlineButton(
            leading: const Text('f', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
            text: 'Facebook ile devam et',
            fill: const Color(0xFF1877F2),
            fg: Colors.white,
            onTap: _busy ? null : () => _social('facebook', 'Facebook'),
          ),
      ]);

  InputDecoration _field(String label, IconData icon, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        labelStyle: const TextStyle(color: Color(0xFFB9A57A)),
        floatingLabelStyle: const TextStyle(color: _Gold.light, fontWeight: FontWeight.w700),
        hintStyle: const TextStyle(color: Color(0xFF6E6250)),
        prefixIcon: Icon(icon, color: _Gold.mid),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xE6100D08),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _Gold.mid.withValues(alpha: 0.28))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _Gold.mid, width: 1.6)),
      );

  Widget _form() {
    final phone = _mode == _Mode.phone;
    return Column(key: ValueKey('form-$phone'), mainAxisSize: MainAxisSize.min, children: [
      // Giriş yap / Kayıt ol
      Container(
        padding: const EdgeInsets.all(4),
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: const Color(0xCC0B0906),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _Gold.mid.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          for (final reg in [false, true])
            Expanded(
              child: GestureDetector(
                onTap: _busy ? null : () => setState(() => _register = reg),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: _register == reg ? const LinearGradient(colors: [_Gold.light, _Gold.mid, _Gold.deep]) : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(reg ? 'Kayıt ol' : 'Giriş yap',
                      style: TextStyle(fontWeight: FontWeight.w800, color: _register == reg ? _Gold.ink : const Color(0xFFB9A57A))),
                ),
              ),
            ),
        ]),
      ),
      TextField(
        controller: _id,
        autocorrect: false,
        cursorColor: _Gold.mid,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        keyboardType: phone ? TextInputType.phone : TextInputType.text,
        textInputAction: TextInputAction.next,
        decoration: _field(phone ? 'Telefon numarası' : 'Kullanıcı adı', phone ? Icons.phone_iphone_rounded : Icons.person_rounded, hint: phone ? '0555 123 45 67' : null),
      ),
      const SizedBox(height: 12),
      if (_register) ...[
        TextField(
          controller: _displayName,
          cursorColor: _Gold.mid,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          textInputAction: TextInputAction.next,
          maxLength: 60,
          decoration: _field(phone ? 'Görünen ad' : 'Görünen ad (isteğe bağlı)', Icons.badge_outlined),
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _password,
        obscureText: !_showPassword,
        cursorColor: _Gold.mid,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        onSubmitted: (_) => _submit(),
        decoration: _field(
          _register ? 'Şifre belirle' : 'Şifre',
          Icons.lock_rounded,
          suffix: IconButton(
            icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: const Color(0xFFB9A57A)),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
      ),
      const SizedBox(height: 22),
      _goldButton(icon: _register ? Icons.how_to_reg_rounded : Icons.login_rounded, text: _register ? 'Kayıt ol' : 'Giriş yap', onTap: _busy ? null : _submit, busy: _busy),
      const SizedBox(height: 8),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: const Color(0xFFB9A57A)),
        onPressed: _busy ? null : () => _setMode(_Mode.start),
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        label: const Text('Diğer giriş seçenekleri'),
      ),
    ]);
  }

  String get _subtitle => _mode == _Mode.start
      ? 'Hoş geldin'
      : (_mode == _Mode.username ? (_register ? 'Kullanıcı adıyla kayıt' : 'Kullanıcı adıyla giriş') : (_register ? 'Telefonla kayıt' : 'Telefonla giriş'));

  @override
  Widget build(BuildContext context) {
    final compact = _mode != _Mode.start || MediaQuery.of(context).viewInsets.bottom > 0;
    return PopScope(
      canPop: _mode == _Mode.start,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _setMode(_Mode.start);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          // Zemin: logonun siyahıyla birleşen koyu zemin, logonun arkasında altın ışıma, aşağıda sıcak koyu ton.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.black, Color(0xFF120C04)], stops: [0, 0.55, 1]),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => CustomPaint(painter: _GoldDust(_anim.value)),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // Logo: kenarları zemine yumuşakça karışır (kutu görünmez), arkasında altın ışıma.
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, child) => Opacity(opacity: v, child: Transform.scale(scale: 0.9 + 0.1 * v, child: child)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        width: compact ? 190 : 280,
                        height: compact ? 190 : 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: _Gold.mid.withValues(alpha: 0.22), blurRadius: 90, spreadRadius: 6)],
                        ),
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          // Yalnızca köşeler yumuşakça kaybolur; yazı ve taç kesilmez.
                          shaderCallback: (r) => const RadialGradient(radius: 0.71, colors: [Colors.white, Colors.white, Colors.transparent], stops: [0, 0.66, 1.0]).createShader(r),
                          child: Image.asset('assets/images/app_logo.webp', fit: BoxFit.cover, filterQuality: FilterQuality.medium),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ShaderMask(
                      shaderCallback: (r) => const LinearGradient(colors: [_Gold.light, _Gold.mid, _Gold.light]).createShader(r),
                      child: Text(_subtitle, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                    ),
                    const SizedBox(height: 6),
                    Container(width: 70, height: 2, decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, _Gold.mid.withValues(alpha: 0.9), Colors.transparent]))),
                    const SizedBox(height: 26),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a), child: child),
                      ),
                      child: _mode == _Mode.start ? _start() : _form(),
                    ),
                    const SizedBox(height: 18),
                    const Text('Devam ederek Topluluk Kurallarımızı kabul etmiş olursun.',
                        textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8C7F66), fontSize: 12)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Logodaki altın tonları.
class _Gold {
  static const light = Color(0xFFFFE9A3);
  static const mid = Color(0xFFE6B13A);
  static const deep = Color(0xFFA9760F);
  static const ink = Color(0xFF1C1405); // altın zemin üstündeki yazı
}

/// Basınca hafifçe küçülen düğme.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedOpacity(opacity: enabled ? 1 : 0.6, duration: const Duration(milliseconds: 150), child: widget.child),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    Widget line(bool left) => Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: left ? [Colors.transparent, const Color(0x80E6B13A)] : [const Color(0x80E6B13A), Colors.transparent]),
            ),
          ),
        );
    return Row(children: [
      line(true),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('veya', style: TextStyle(color: Color(0xFFB9A57A), fontSize: 13))),
      line(false),
    ]);
  }
}

/// Ağır ağır yükselen, parıldayan altın tozları (logonun ışıltısı gibi).
class _GoldDust extends CustomPainter {
  final double t;
  _GoldDust(this.t);

  static final List<List<double>> _seeds = () {
    final r = math.Random(7);
    return List.generate(38, (_) => [r.nextDouble(), r.nextDouble(), 0.6 + r.nextDouble() * 1.9, r.nextDouble(), 0.3 + r.nextDouble() * 0.7]);
  }();

  @override
  void paint(Canvas canvas, Size size) {
    // logonun arkasındaki sıcak ışıma
    final glow = Paint()
      ..shader = RadialGradient(colors: [const Color(0x33E6B13A), const Color(0x00E6B13A)]).createShader(
        Rect.fromCircle(center: Offset(size.width / 2, size.height * 0.3), radius: size.width * 0.75),
      );
    canvas.drawRect(Offset.zero & size, glow);
    final p = Paint();
    for (final s in _seeds) {
      final y = (s[1] - t * s[4]) % 1.0;
      final x = s[0] + math.sin((t * 2 * math.pi) + s[3] * 6) * 0.02;
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 2 * math.pi * 3 + s[3] * 10));
      p.color = const Color(0xFFFFD978).withValues(alpha: 0.55 * tw);
      p.maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);
      canvas.drawCircle(Offset(x * size.width, y * size.height), s[2], p);
    }
  }

  @override
  bool shouldRepaint(_GoldDust old) => old.t != t;
}
