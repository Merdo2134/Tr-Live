import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'common.dart';

class PickedImage {
  final Uint8List bytes;
  final String mime;
  const PickedImage(this.bytes, this.mime);
}

String? sniffImageMime(Uint8List b) {
  if (b.length > 12 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
  if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
  return null;
}

/// Galeriden görsel seçer; biçim ve boyut denetimini yapar. İptal veya hata durumunda null döner.
Future<PickedImage?> pickImage(BuildContext context, {double maxWidth = 1600}) async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: maxWidth, imageQuality: 85);
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  final mime = sniffImageMime(bytes);
  if (!context.mounted) return null;
  if (mime == null) {
    toast(context, 'Yalnızca png, jpeg veya webp yüklenebilir.', error: true);
    return null;
  }
  if (bytes.length > 3 * 1024 * 1024) {
    toast(context, 'Görsel 3 MB’tan küçük olmalı.', error: true);
    return null;
  }
  return PickedImage(bytes, mime);
}
