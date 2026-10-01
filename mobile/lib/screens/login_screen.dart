import 'package:flutter/material.dart';
import '../services/auth_service.dart';
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
                const Icon(Icons.podcasts, size: 64, color: Colors.pinkAccent),
                const SizedBox(height: 8),
                Text('TR Live', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 24),
                TextField(
                  controller: _username,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Kullanıcı adı', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                if (_register) ...[
                  TextField(
                    controller: _displayName,
                    textInputAction: TextInputAction.next,
                    maxLength: 60,
                    decoration: const InputDecoration(labelText: 'Görünen ad', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 4),
                ],
                TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Şifre',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_register ? 'Kayıt ol' : 'Giriş yap'),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _register = !_register),
                  child: Text(_register ? 'Hesabım var, giriş yap' : 'Hesap oluştur'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
