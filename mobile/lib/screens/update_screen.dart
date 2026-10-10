import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api.dart';
import '../version.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';

/// Sunucu bu sürümü artık kabul etmiyor (yönetim paneli > Uygulama ayarları > En düşük sürüm).
class UpdateRequiredScreen extends StatelessWidget {
  final String message;
  final String? url;
  final VoidCallback onRetry;
  const UpdateRequiredScreen({super.key, required this.message, this.url, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final link = url ?? '';
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.system_update, size: 64, color: Pal.cyan),
                const SizedBox(height: Gap.l),
                const Text('Güncelleme gerekli', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: Gap.m),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Pal.textDim, height: 1.4)),
                const SizedBox(height: Gap.s),
                Text('Yüklü sürüm: $kAppVersion', style: const TextStyle(color: Pal.textDim, fontSize: 12)),
                const SizedBox(height: Gap.xl),
                if (link.isNotEmpty) ...[
                  SelectableText(link, textAlign: TextAlign.center, style: const TextStyle(color: Pal.cyan)),
                  const SizedBox(height: Gap.m),
                  FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      if (context.mounted) toast(context, 'İndirme bağlantısı kopyalandı. Tarayıcıya yapıştırın.');
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('İndirme bağlantısını kopyala'),
                  ),
                  const SizedBox(height: Gap.s),
                ],
                OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Tekrar dene')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Zorunlu olmayan güncelleme: yeni sürüm yayınlandıysa her sürüm için bir kez haber verir.
Future<void> checkOptionalUpdate(BuildContext context) async {
  try {
    final c = await Api.get('/api/app/config');
    final latest = c['latestAppVersion']?.toString() ?? '0.0.0';
    if (_compare(latest, kAppVersion) <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('update_notified') == latest) return;
    await prefs.setString('update_notified', latest);
    if (!context.mounted) return;
    final url = c['updateUrl'] is String ? c['updateUrl'] as String : '';
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Yeni sürüm var'),
        content: Text('TR Live $latest yayında (sizdeki: $kAppVersion). Yenilikler ve düzeltmeler için güncellemenizi öneririz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Sonra')),
          if (url.isNotEmpty)
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (d.mounted) Navigator.pop(d);
                if (context.mounted) toast(context, 'İndirme bağlantısı kopyalandı. Tarayıcıya yapıştırın.');
              },
              child: const Text('Bağlantıyı kopyala'),
            ),
        ],
      ),
    );
  } catch (_) {/* sürüm bilgisi alınamazsa sessizce geçilir */}
}

int _compare(String a, String b) {
  List<int> parts(String v) {
    final p = v.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    while (p.length < 3) {
      p.add(0);
    }
    return p;
  }

  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}
