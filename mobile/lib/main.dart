import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api.dart';
import 'services/auth_service.dart';
import 'services/session.dart';
import 'services/socket_service.dart';
import 'widgets/app_theme.dart';
import 'widgets/common.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool _loggingOut = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.restore();
  // Oturum sona erdiğinde (401, yasaklı hesap, şifre değişimi) giriş ekranına dön.
  Api.onUnauthorized = () async {
    if (_loggingOut) return;
    _loggingOut = true;
    await AuthService.logout();
    navigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    _loggingOut = false;
  };
  runApp(const TRLiveApp());
}

class TRLiveApp extends StatelessWidget {
  const TRLiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'TR Live',
      theme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      builder: appFrame,
      home: const _Boot(),
    );
  }
}

/// Kayıtlı oturum varsa sunucuda doğrular, yoksa giriş ekranını açar.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (Api.token == null) {
      _go(const LoginScreen());
      return;
    }
    setState(() => _error = null);
    try {
      await Session.refresh();
      SocketService.instance.start();
      _go(const HomeScreen());
    } catch (e) {
      if (!mounted) return;
      // 401 ise onUnauthorized zaten giriş ekranına yönlendirir.
      if (Api.token != null) setState(() => _error = errorText(e));
    }
  }

  void _go(Widget page) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(body: LoadError(message: _error!, onRetry: _start));
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
