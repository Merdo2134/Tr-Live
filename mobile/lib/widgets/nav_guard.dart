import 'package:flutter/material.dart';

/// Aynı sayfa ya da aynı tür alt pencere art arda iki kez açılırsa (düğmeye çift dokunma, yavaş yanıt sırasında
/// tekrar dokunma) ikincisi hemen kapatılır; kullanıcı aynı sayfayı üst üste görmez.
class DuplicateRouteGuard extends NavigatorObserver {
  Route<dynamic>? _last;
  Object? _lastSig;
  DateTime _lastAt = DateTime(2000);

  /// Sayfanın türü: MaterialPageRoute'ta oluşturulan ekranın sınıfı, alt pencerede rota türü.
  Object? _sig(Route<dynamic> r) {
    if (r is MaterialPageRoute) {
      final ctx = navigator?.context;
      if (ctx == null) return null;
      try {
        return r.builder(ctx).runtimeType;
      } catch (_) {
        return null;
      }
    }
    if (r is ModalBottomSheetRoute) return r.runtimeType;
    return null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final now = DateTime.now();
    final sig = _sig(route);
    final windowMs = route is ModalBottomSheetRoute ? 700 : 1500;
    final last = _last;
    final duplicate = sig != null &&
        sig == _lastSig &&
        last != null &&
        identical(previousRoute, last) &&
        last.isActive &&
        now.difference(_lastAt).inMilliseconds < windowMs;
    if (duplicate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) navigator?.removeRoute(route);
      });
      return;
    }
    _last = route;
    _lastSig = sig;
    _lastAt = now;
  }
}
