import 'package:flutter/material.dart';
import '../services/api.dart';
import 'common.dart';

const reportReasons = {
  'spam': 'Spam / reklam',
  'harassment': 'Taciz veya zorbalık',
  'nudity': 'Uygunsuz / müstehcen içerik',
  'hate': 'Nefret söylemi',
  'scam': 'Dolandırıcılık',
  'underage': 'Reşit olmayan kullanıcı',
  'violence': 'Şiddet veya tehdit',
  'other': 'Diğer',
};

/// kind: user | room | room_message | dm
Future<void> reportDialog(BuildContext context, {required String kind, String? targetUserId, String? roomId, String? messageId}) async {
  final reason = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Şikâyet nedeni'),
      children: [for (final e in reportReasons.entries) SimpleDialogOption(onPressed: () => Navigator.pop(c, e.key), child: Text(e.value))],
    ),
  );
  if (reason == null || !context.mounted) return;
  final r = await guard(context, () => Api.post('/api/reports', {
        'kind': kind,
        'reason': reason,
        if (targetUserId != null) 'targetUserId': targetUserId,
        if (roomId != null) 'roomId': roomId,
        if (messageId != null) 'messageId': messageId,
      }));
  if (r != null && context.mounted) toast(context, 'Şikâyetiniz alındı. İnceleyeceğiz, teşekkürler.');
}

/// Engelleme: karşılıklı takip kaldırılır, mesajlaşma ve aramada görünmezsiniz.
Future<bool> blockUserDialog(BuildContext context, String userId, String name) async {
  if (!await confirm(context, '$name engellensin mi? Birbirinizi takip etmezsiniz ve mesajlaşamazsınız.', action: 'Engelle')) return false;
  if (!context.mounted) return false;
  final r = await guard(context, () => Api.post('/api/blocks/$userId'));
  if (r != null && context.mounted) toast(context, 'Kullanıcı engellendi.');
  return r != null;
}
