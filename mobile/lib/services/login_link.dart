import 'dart:async';
import 'package:flutter/widgets.dart';

/// Google/Facebook girişinden sonra tarayıcının uygulamaya döndürdüğü bağlantı (trlive://login/auth?state=…&code=…).
/// Android bağlantıyı Flutter'a "yeni sayfa" olarak iletir; burada yakalanır ve sayfa açılmaz.
class LoginLink with WidgetsBindingObserver {
  LoginLink._();
  static final LoginLink instance = LoginLink._();

  final StreamController<Map<String, String>> _links = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get links => _links.stream;
  bool _inited = false;

  void init() {
    if (_inited) return;
    _inited = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Bağlantı giriş dönüşüyse parametrelerini verir; değilse null.
  static Map<String, String>? parse(String? route) {
    if (route == null) return null;
    final uri = Uri.tryParse(route);
    if (uri == null || uri.path != '/auth' || !uri.queryParameters.containsKey('state')) return null;
    return uri.queryParameters;
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    // Uygulamada adlı sayfa yok: başka bağlantılar da yutulur (açılış ekranı ikinci kez açılmasın).
    final q = parse(routeInformation.uri.toString());
    if (q != null) _links.add(q);
    return true;
  }
}
