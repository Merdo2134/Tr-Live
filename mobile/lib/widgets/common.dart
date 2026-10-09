import 'package:flutter/material.dart';
import '../services/api.dart';

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Colors.red.shade700 : null,
    behavior: SnackBarBehavior.floating,
  ));
}

String errorText(Object e) => e is ApiException ? e.message : e.toString().replaceFirst('Exception: ', '');

/// Hata olursa kullanıcıya gösterir ve null döner.
Future<T?> guard<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } catch (e) {
    if (context.mounted) toast(context, errorText(e), error: true);
    return null;
  }
}

Future<bool> confirm(BuildContext context, String message, {String action = 'Onayla'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
      ],
    ),
  );
  return r == true;
}

Future<String?> askText(BuildContext context, String title, {String? hint, bool obscure = false, TextInputType? keyboard, String? initial}) async {
  final controller = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: obscure,
        keyboardType: keyboard,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text('Tamam')),
      ],
    ),
  );
  controller.dispose();
  return (r == null || r.isEmpty) ? null : r;
}

Color? parseColor(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

String fmtNumber(dynamic v) {
  final s = (v ?? 0).toString();
  final neg = s.startsWith('-');
  final digits = neg ? s.substring(1) : s;
  if (!RegExp(r'^\d+$').hasMatch(digits)) return s;
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${neg ? '-' : ''}$buf';
}

/// Kuruş cinsinden tutarı "12,50 USD" biçiminde gösterir.
String fmtMoney(dynamic cents, [String currency = 'USD']) {
  final v = BigInt.tryParse((cents ?? 0).toString()) ?? BigInt.zero;
  final whole = v ~/ BigInt.from(100);
  final frac = (v % BigInt.from(100)).toInt().toString().padLeft(2, '0');
  return '${fmtNumber(whole.toString())},$frac $currency';
}

String fmtDuration(num seconds) {
  final s = seconds.toInt();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return h > 0 ? '$h sa $m dk' : '$m dk';
}

class UserAvatar extends StatelessWidget {
  final Map<String, dynamic>? user;
  final double radius;
  final bool speaking;
  const UserAvatar({super.key, this.user, this.radius = 22, this.speaking = false});

  @override
  Widget build(BuildContext context) {
    final url = Api.absoluteUrl(user?['avatarUrl'] as String?);
    final name = (user?['displayName'] ?? '?').toString();
    final avatar = CircleAvatar(
      radius: radius,
      backgroundImage: url == null ? null : NetworkImage(url),
      onBackgroundImageError: url == null ? null : (_, __) {},
      child: url == null ? Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()) : null,
    );
    if (!speaking) return avatar;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.greenAccent, width: 2.5)),
      child: avatar,
    );
  }
}

class WipChip extends StatelessWidget {
  final dynamic level;
  final String? colorHex;
  const WipChip({super.key, required this.level, this.colorHex});

  @override
  Widget build(BuildContext context) {
    if (level == null) return const SizedBox.shrink();
    final color = parseColor(colorHex) ?? Colors.amber;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), border: Border.all(color: color), borderRadius: BorderRadius.circular(8)),
      child: Text('WIP $level', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }
}


/// WIP adı: 5. seviye ateşli git-gel, 4. seviye mavi buzlu parıltı; diğerleri düz renk.
class WipNameText extends StatefulWidget {
  final String text;
  final int? level;
  final Color? color;
  final TextStyle? style;
  final int maxLines;
  const WipNameText(this.text, {super.key, this.level, this.color, this.style, this.maxLines = 1});

  @override
  State<WipNameText> createState() => _WipNameTextState();
}

class _WipNameTextState extends State<WipNameText> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  bool get _fx => (widget.level ?? 0) >= 4;

  @override
  void initState() {
    super.initState();
    if (_fx) _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.level == 5 ? 1600 : 2400))..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(WipNameText old) {
    super.didUpdateWidget(old);
    if (_fx && _c == null) {
      _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.level == 5 ? 1600 : 2400))..repeat(reverse: true);
    } else if (!_fx && _c != null) {
      _c!.dispose();
      _c = null;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = (widget.style ?? const TextStyle()).copyWith(color: widget.color ?? widget.style?.color, fontWeight: _fx ? FontWeight.w800 : widget.style?.fontWeight);
    if (!_fx || _c == null) return Text(widget.text, maxLines: widget.maxLines, overflow: TextOverflow.ellipsis, style: base);
    final fire = widget.level == 5;
    final colors = fire
        ? const [Color(0xFFFFF176), Color(0xFFFF9800), Color(0xFFFF1744), Color(0xFFFF9800), Color(0xFFFFF176)]
        : const [Color(0xFF80D8FF), Color(0xFFFFFFFF), Color(0xFF2979FF), Color(0xFFFFFFFF), Color(0xFF80D8FF)];
    return AnimatedBuilder(
      animation: _c!,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_c!.value);
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(begin: Alignment(-1.0 - 1.0 + 2.0 * t, 0), end: Alignment(1.0 + 2.0 * t - 2.0, 0), colors: colors, tileMode: TileMode.mirror).createShader(r),
          child: child,
        );
      },
      child: Text(widget.text, maxLines: widget.maxLines, overflow: TextOverflow.ellipsis, style: base.copyWith(color: Colors.white, shadows: [Shadow(color: fire ? const Color(0xAAFF5722) : const Color(0xAA40C4FF), blurRadius: 6)])),
    );
  }
}

/// Kullanıcı adı (WIP renginde) + WIP rozeti.
class UserName extends StatelessWidget {
  final Map<String, dynamic>? user;
  final TextStyle? style;
  const UserName({super.key, this.user, this.style});

  @override
  Widget build(BuildContext context) {
    final color = parseColor(user?['nameColor'] as String?);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: WipNameText((user?['displayName'] ?? '').toString(), level: (user?['wipLevel'] as num?)?.toInt(), color: color, style: style),
        ),
        WipChip(level: user?['wipLevel'], colorHex: user?['nameColor'] as String?),
      ],
    );
  }
}

class LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const LoadError({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ]),
        ),
      );
}

/// Yükleme / hata / içerik durumlarını yöneten basit ekran gövdesi.
class AsyncBody<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  const AsyncBody({super.key, required this.load, required this.builder});

  @override
  State<AsyncBody<T>> createState() => _AsyncBodyState<T>();
}

class _AsyncBodyState<T> extends State<AsyncBody<T>> {
  T? _data;
  bool _loaded = false; // T null olabilir (ör. "ailem yok"), bu yüzden ayrı bayrak tutulur
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (!_loaded) setState(() => _loading = true);
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loaded = true;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_loaded) return LoadError(message: _error ?? 'Yüklenemedi.', onRetry: _reload);
    return widget.builder(context, _data as T, _reload);
  }
}

/// Kullanıcı adına göre kullanıcı seçtiren arama penceresi.
Future<Map<String, dynamic>?> pickUser(BuildContext context, {bool admin = false}) async {
  final controller = TextEditingController();
  List<Map<String, dynamic>> results = [];
  String? error;
  final r = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: const Text('Kullanıcı ara'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(hintText: admin ? 'ID, kullanıcı adı veya ad' : 'Kullanıcı adı (en az 2 harf)'),
              onChanged: (v) async {
                if (v.trim().length < 2) return;
                try {
                  final res = await Api.get(admin ? '/api/admin/users' : '/api/users/search', query: {'q': v.trim()});
                  if (!c.mounted) return;
                  setS(() {
                    results = listOf(res['users']);
                    error = null;
                  });
                } catch (e) {
                  if (!c.mounted) return;
                  setS(() => error = errorText(e));
                }
              },
            ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final u in results)
                  ListTile(
                    leading: UserAvatar(user: u, radius: 16),
                    title: Text((u['displayName'] ?? '').toString()),
                    subtitle: Text(u['publicId'] != null ? 'ID: ${u['publicId']} · @${u['username']}' : '@${u['username']}'),
                    onTap: () => Navigator.pop(c, u),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
      ),
    ),
  );
  controller.dispose();
  return r;
}

/// Birden fazla alanlı basit form penceresi; {etiket: değer} döner.
Future<Map<String, String>?> formDialog(BuildContext context, String title, List<String> labels, {Map<String, String> initial = const {}}) async {
  final controllers = {for (final l in labels) l: TextEditingController(text: initial[l] ?? '')};
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final l in labels) TextField(controller: controllers[l], decoration: InputDecoration(labelText: l)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tamam')),
      ],
    ),
  );
  final values = {for (final l in labels) l: controllers[l]!.text.trim()};
  for (final c in controllers.values) {
    c.dispose();
  }
  return ok == true ? values : null;
}
