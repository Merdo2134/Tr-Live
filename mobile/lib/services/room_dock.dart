import 'package:flutter/foundation.dart';

class RoomRequest {
  final String roomId;
  final String name;
  final bool locked;
  final String? code;
  const RoomRequest({required this.roomId, this.name = 'Oda', this.locked = false, this.code});
}

/// Açık oda uygulama boyunca tek yerde yaşar; küçültülünce ses/görüntü kesilmeden arka planda kalır.
class RoomDock {
  RoomDock._();

  static final request = ValueNotifier<RoomRequest?>(null);
  static final minimized = ValueNotifier<bool>(false);

  /// Açık odadaki rolüm (oda sahibi başka odaya geçerken uyarmak için).
  static String myRole = 'user';

  /// RoomScreen'in kayıt ettiği "odadan ayrıl" işlemi (küçültülmüş çubuktaki X bunu çağırır).
  static VoidCallback? exitHandler;

  static int _serial = 0;
  static int get serial => _serial;

  static bool get isOpen => request.value != null;

  static void open(RoomRequest r) {
    if (request.value?.roomId == r.roomId) {
      minimized.value = false;
      return;
    }
    _serial++;
    request.value = r;
    minimized.value = false;
  }

  static void minimize() {
    if (isOpen) minimized.value = true;
  }

  static void expand() {
    if (isOpen) minimized.value = false;
  }

  static void close() {
    request.value = null;
    minimized.value = false;
    myRole = 'user';
    exitHandler = null;
  }
}
