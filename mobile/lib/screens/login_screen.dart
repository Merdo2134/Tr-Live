import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  String? _validate() {
    final u = _username.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(u)) {
      return 'Kullanıcı adı 3-30 karakter olmalı; yalnızca harf, rakam, nokta ve alt çizgi.';
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
      final u = _username.text.trim().toLowerCase();
      if (_register) {
        final name = _displayName.text.trim();
        await AuthService.register(u, _password.text, name.isEmpty ? u : name);
      } else {
        await AuthService.login(u, _password.text);
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.workspace_premium, size: 84, color: Pal.amber),
                const SizedBox(height: 4),
                const Text('TR LIVE', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: 4, color: Pal.text, fontFamily: 'serif')),
                const SizedBox(height: 8),
                Text(_register ? 'Kaydol' : 'Hoş geldin', style: const TextStyle(fontSize: 18, color: Pal.textDim)),
                const SizedBox(height: 28),
                TextField(
                  controller: _username,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Kullanıcı adı', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 12),
                if (_register) ...[
                  TextField(
                    controller: _displayName,
                    textInputAction: TextInputAction.next,
                    maxLength: 60,
                    decoration: const InputDecoration(labelText: 'Görünen ad', prefixIcon: Icon(Icons.badge_outlined)),
                  ),
                  const SizedBox(height: 4),
                ],
                TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Şifre',
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
                            : Text(_register ? 'Kaydol' : 'Giriş Yap', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _register = !_register),
                  child: Text(_register ? 'Hesabım var, giriş yap' : 'Hesap oluştur'),
                ),
                const SizedBox(height: 8),
                const Text('Bağlantıyı gerçekleştirerek Topluluk Politikamızı kabul etmiş olursunuz.', textAlign: TextAlign.center, style: TextStyle(color: Pal.textDim, fontSize: 12)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
