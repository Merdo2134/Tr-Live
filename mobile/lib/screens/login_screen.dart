import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// Giriş / kayıt: Google, Facebook, telefon numarası ya da kullanıcı adı + şifre.
enum _Mode { start, phone, username }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _id = TextEditingController(); // telefon ya da kullanıcı adı
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  _Mode _mode = _Mode.start;
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  Map<String, dynamic> _providers = const {'google': false, 'facebook': false, 'phone': true};
  bool _socialCancelled = false;

  @override
  void initState() {
    super.initState();
    AuthService.providers().then((p) {
      if (mounted) setState(() => _providers = p);
    });
  }

  @override
  void dispose() {
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

  Widget _bigButton({required Widget icon, required String text, required Color bg, required Color fg, required VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Container(
              height: 54,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(28)),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                SizedBox(width: 30, child: Center(child: icon)),
                Expanded(child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w800))),
                const SizedBox(width: 30),
              ]),
            ),
          ),
        ),
      );

  Widget _start() => Column(mainAxisSize: MainAxisSize.min, children: [
        if (_providers['google'] == true)
          _bigButton(
            icon: const Text('G', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF4285F4))),
            text: 'Google ile devam et',
            bg: Colors.white,
            fg: const Color(0xFF1F2937),
            onTap: _busy ? null : () => _social('google', 'Google'),
          ),
        if (_providers['facebook'] == true)
          _bigButton(
            icon: const Text('f', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
            text: 'Facebook ile devam et',
            bg: const Color(0xFF1877F2),
            fg: Colors.white,
            onTap: _busy ? null : () => _social('facebook', 'Facebook'),
          ),
        _bigButton(
          icon: const Icon(Icons.phone_iphone, color: Colors.white),
          text: 'Telefon numarası ile',
          bg: const Color(0xFF16A34A),
          fg: Colors.white,
          onTap: _busy ? null : () => _setMode(_Mode.phone),
        ),
        _bigButton(
          icon: const Icon(Icons.person_outline, color: Colors.white),
          text: 'Kullanıcı adı ile',
          bg: Pal.purple,
          fg: Colors.white,
          onTap: _busy ? null : () => _setMode(_Mode.username),
        ),
      ]);

  Widget _form() {
    final phone = _mode == _Mode.phone;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          padding: const EdgeInsets.all(4),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(24)),
          child: Row(children: [
            for (final reg in [false, true])
              Expanded(
                child: GestureDetector(
                  onTap: _busy ? null : () => setState(() => _register = reg),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _register == reg ? Pal.purple : Colors.transparent, borderRadius: BorderRadius.circular(20)),
                    child: Text(reg ? 'Kayıt ol' : 'Giriş yap', style: TextStyle(fontWeight: FontWeight.w800, color: _register == reg ? Colors.white : Pal.textDim)),
                  ),
                ),
              ),
          ]),
        ),
      TextField(
        controller: _id,
        autocorrect: false,
        keyboardType: phone ? TextInputType.phone : TextInputType.text,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: phone ? 'Telefon numarası' : 'Kullanıcı adı',
          hintText: phone ? '0555 123 45 67' : null,
          prefixIcon: Icon(phone ? Icons.phone_iphone : Icons.person_outline),
        ),
      ),
      const SizedBox(height: 12),
      if (_register) ...[
        TextField(
          controller: _displayName,
          textInputAction: TextInputAction.next,
          maxLength: 60,
          decoration: InputDecoration(labelText: phone ? 'Görünen ad' : 'Görünen ad (isteğe bağlı)', prefixIcon: const Icon(Icons.badge_outlined)),
        ),
        const SizedBox(height: 4),
      ],
      TextField(
        controller: _password,
        obscureText: !_showPassword,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: _register ? 'Şifre belirle' : 'Şifre',
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: _busy ? null : _submit,
          child: Ink(
            height: 54,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Pal.purple, Pal.pink]),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [BoxShadow(color: Pal.pink.withValues(alpha: 0.35), blurRadius: 14)],
            ),
            child: Center(
              child: _busy
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(_register ? 'Kayıt ol' : 'Giriş yap', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      TextButton.icon(
        onPressed: _busy ? null : () => _setMode(_Mode.start),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('Diğer giriş seçenekleri'),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _mode == _Mode.start,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _setMode(_Mode.start);
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Uygulama logosu (taç + TR Live + "Sınırları aşan anlara").
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/images/app_logo.webp', width: 220, height: 220, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _mode == _Mode.start ? 'Hoş geldin' : (_mode == _Mode.username ? (_register ? 'Kullanıcı adıyla kayıt' : 'Kullanıcı adıyla giriş') : (_register ? 'Telefonla kayıt' : 'Telefonla giriş')),
                    style: const TextStyle(fontSize: 18, color: Pal.textDim),
                  ),
                  const SizedBox(height: 28),
                  if (_mode == _Mode.start) _start() else _form(),
                  const SizedBox(height: 8),
                  const Text('Devam ederek Topluluk Kurallarımızı kabul etmiş olursun.', textAlign: TextAlign.center, style: TextStyle(color: Pal.textDim, fontSize: 12)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
