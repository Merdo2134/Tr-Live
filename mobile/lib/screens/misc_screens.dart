import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/session.dart';
import '../services/error_log.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import 'user_screens.dart';

String _date(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  static const _types = {
    'gift_sent': 'Hediye gönderildi',
    'gift_received': 'Hediye alındı',
    'lucky_gift_win': 'Şanslı hediye kazancı',
    'wip_purchase': 'WIP satın alma',
    'dealer_credit': 'Bayi yüklemesi',
    'admin_adjustment': 'Yönetici düzenlemesi',
    'diamond_exchange': 'Elmas bozdurma',
    'lucky_bag_sent': 'Şanslı çanta gönderildi',
    'lucky_bag_received': 'Şanslı çanta kazancı',
    'lucky_bag_refund': 'Şanslı çanta iadesi',
    'daily_bonus': 'Günlük görev ödülü',
    'store_purchase': 'Mağaza alışverişi',
  };

  /// 5 Elmas = 1 Coin.
  static Future<void> exchange(BuildContext context, String diamonds, Future<void> Function() reload) async {
    final have = BigInt.tryParse(diamonds) ?? BigInt.zero;
    final ctl = TextEditingController();
    final amount = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final n = BigInt.tryParse(ctl.text.trim()) ?? BigInt.zero;
          final valid = n >= BigInt.from(5) && n % BigInt.from(5) == BigInt.zero && n <= have;
          return AlertDialog(
            title: const Text('Elmas Bozdur'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Elmasın: ${fmtNumber(diamonds)} 💎   •   Oran: 5 Elmas = 1 Coin'),
              const SizedBox(height: 8),
              TextField(
                controller: ctl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Bozdurulacak elmas (5 ve katları)'),
                onChanged: (_) => setS(() {}),
              ),
              const SizedBox(height: 8),
              Text(valid ? 'Alacağın: ${n ~/ BigInt.from(5)} Coin' : 'Geçerli bir miktar gir.', style: const TextStyle(color: Colors.white70)),
              Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setS(() => ctl.text = (have - have % BigInt.from(5)).toString()), child: const Text('Hepsi'))),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
              FilledButton(onPressed: valid ? () => Navigator.pop(c, n.toString()) : null, child: const Text('Bozdur')),
            ],
          );
        },
      ),
    );
    ctl.dispose();
    if (amount == null || !context.mounted) return;
    final r = await guard(context, () => Api.postOnce('/api/me/diamonds/exchange', {'diamonds': amount}));
    if (r == null || !context.mounted) return;
    toast(context, '${r['exchangedCoins']} Coin hesabına eklendi.');
    try {
      await Session.refresh(); // bakiye yenilenemese de işlem tamamlandı; ekran yine güncellensin
    } catch (_) {}
    await reload();
  }

  @override
  Widget build(BuildContext context) => const _WalletView();
}

/// Cüzdan / Coin geçmişi: bakiye, Elmas bozdurma, türe göre süzülen ve "daha fazla" ile geriye doğru yüklenen hareketler.
class _WalletView extends StatefulWidget {
  const _WalletView();

  @override
  State<_WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<_WalletView> {
  static const _groups = [(null, 'Tümü'), ('gift', 'Hediye'), ('topup', 'Yükleme'), ('exchange', 'Bozdurma'), ('shop', 'Mağaza/WIP'), ('bag', 'Çanta')];
  String? _group;
  Map<String, dynamic> _me = {};
  final List<Map<String, dynamic>> _items = [];
  String? _nextBefore;
  bool _loading = true;
  bool _more = false;
  String? _error;
  int _gen = 0; // süzgeç hızlı değişince eski isteğin yanıtı yeni listeye karışmasın

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<Map<String, dynamic>> _page(String? before) => Api.get('/api/me/wallet', query: {
        'limit': '40',
        if (_group != null) 'group': _group!,
        if (before != null) 'before': before,
      });

  Future<void> _reload() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
      _more = false;
    });
    try {
      final results = await Future.wait([_page(null), Api.get('/api/me')]);
      if (!mounted || gen != _gen) return;
      setState(() {
        _items
          ..clear()
          ..addAll(listOf(results[0]['transactions']));
        _nextBefore = results[0]['nextBefore']?.toString();
        _me = mapOf(results[1]['user']) ?? {};
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
      if (_me.isNotEmpty) toast(context, errorText(e), error: true); // ekranda eski liste varken hata sessiz kalmasın
    }
  }

  Future<void> _loadMore() async {
    final before = _nextBefore;
    if (before == null || _more || _loading) return;
    final gen = _gen;
    setState(() => _more = true);
    try {
      final r = await _page(before);
      if (!mounted || gen != _gen) return;
      setState(() {
        _items.addAll(listOf(r['transactions']));
        _nextBefore = r['nextBefore']?.toString();
      });
    } catch (e) {
      if (mounted && gen == _gen) toast(context, errorText(e), error: true);
    } finally {
      if (mounted && gen == _gen) setState(() => _more = false);
    }
  }

  void _pick(String? g) {
    if (g == _group) return;
    _group = g;
    _reload();
  }

  Widget _row(Map<String, dynamic> t) {
    final diamond = t['diamondAmount'].toString() != '0' && t['type'] != 'diamond_exchange';
    final amount = t['type'] == 'diamond_exchange'
        ? '+${fmtNumber(t['coinAmount'])} Coin'
        : (diamond ? '${t['diamondAmount'].toString().startsWith('-') ? '' : '+'}${fmtNumber(t['diamondAmount'])} 💎' : '${t['coinAmount'].toString().startsWith('-') ? '' : '+'}${fmtNumber(t['coinAmount'])} Coin');
    final negative = amount.startsWith('-');
    return ListTile(
      leading: Icon(diamond ? Icons.diamond : Icons.monetization_on, color: diamond ? Colors.cyanAccent : Colors.amber),
      title: Text(WalletScreen._types[t['type']] ?? t['type'].toString()),
      subtitle: Text('${t['description'] ?? ''}\n${_date(t['createdAt'])}'),
      isThreeLine: true,
      trailing: Text(amount, style: TextStyle(color: negative ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBroadcaster = _me['broadcasterStatus'] == 'approved';
    return Scaffold(
      appBar: AppBar(title: const Text('Cüzdan ve Coin geçmişi')),
      body: _loading && _items.isEmpty && _me.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _me.isEmpty
              ? LoadError(message: _error!, onRetry: _reload)
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(children: [
                    Card(
                      margin: const EdgeInsets.all(12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(children: [
                          Row(children: [
                            Expanded(child: Column(children: [const Text('Coin'), Text(fmtNumber(_me['coins'] ?? '0'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.amber))])),
                            Expanded(child: Column(children: [const Text('Elmas'), Text('${fmtNumber(_me['diamonds'] ?? '0')} 💎', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.cyanAccent))])),
                          ]),
                          const SizedBox(height: 10),
                          if (isBroadcaster)
                            const Text('Onaylı yayıncı: elmaslar maaş sistemiyle ödenir, bozdurulamaz.', style: TextStyle(color: Colors.white60, fontSize: 12))
                          else
                            FilledButton.icon(
                              onPressed: () => WalletScreen.exchange(context, (_me['diamonds'] ?? '0').toString(), _reload),
                              icon: const Icon(Icons.swap_horiz),
                              label: const Text('Elmas Bozdur (5 💎 = 1 Coin)'),
                            ),
                        ]),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(children: [
                        for (final g in _groups)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(label: Text(g.$2), selected: _group == g.$1, onSelected: (_) => _pick(g.$1)),
                          ),
                      ]),
                    ),
                    if (_loading) const LinearProgressIndicator(minHeight: 2),
                    if (!_loading && _items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Bu türde işlem yok.'))),
                    for (final t in _items) _row(t),
                    if (_nextBefore != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: _more
                              ? const CircularProgressIndicator()
                              : OutlinedButton(onPressed: _loadMore, child: const Text('Daha fazla göster')),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ]),
                ),
    );
  }
}

class VisitorsScreen extends StatelessWidget {
  const VisitorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil ziyaretçileri')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        load: () async => listOf((await Api.get('/api/me/visitors'))['visitors']),
        builder: (context, items, reload) => items.isEmpty
            ? const Center(child: Text('Henüz ziyaretçi yok.'))
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView(children: [
                  for (final v in items)
                    ListTile(
                      leading: UserAvatar(user: mapOf(v['user'])),
                      title: UserName(user: mapOf(v['user'])),
                      subtitle: Text('${v['visitCount']} ziyaret · ${_date(v['lastVisitedAt'])}'),
                      onTap: () {
                        final id = mapOf(v['user'])?['id'];
                        if (id is String) Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)));
                      },
                    ),
                ]),
              ),
      ),
    );
  }
}

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Engellenen kullanıcılar')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_version),
        load: () async => listOf((await Api.get('/api/blocks'))['users']),
        builder: (context, users, reload) => users.isEmpty
            ? const Center(child: Text('Engellediğiniz kimse yok.'))
            : ListView(children: [
                for (final u in users)
                  ListTile(
                    leading: UserAvatar(user: u),
                    title: Text((u['displayName'] ?? '').toString()),
                    subtitle: Text('@${u['username']}'),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final r = await guard<bool>(context, () async {
                          await Api.delete('/api/blocks/${u['id']}');
                          return true;
                        });
                        if (r == true && mounted) setState(() => _version++);
                      },
                      child: const Text('Engeli kaldır'),
                    ),
                  ),
              ]),
      ),
    );
  }
}


/// Yakalanan hataların kaydı: çökme olursa buradan kopyalayıp gönderebilirsiniz.
class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({super.key});

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  List<String> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await ErrorLog.load();
    if (mounted) setState(() {
      _items = l;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hata kaydı'), actions: [
        IconButton(
          tooltip: 'Tümünü kopyala',
          icon: const Icon(Icons.copy),
          onPressed: _items.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: _items.join('\n\n')));
                  toast(context, 'Kopyalandı.');
                },
        ),
        IconButton(
          tooltip: 'Temizle',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            await ErrorLog.clear();
            _load();
          },
        ),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Kayıtlı hata yok.', style: TextStyle(color: Colors.white54)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) => SelectableText(_items[i], style: const TextStyle(fontSize: 12)),
                ),
    );
  }
}

/// Oturumlarım: hesabın açık olduğu cihazlar, uzaktan çıkış.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  int _v = 0;

  Future<List<Map<String, dynamic>>> _load() async => listOf((await Api.get('/api/me/sessions'))['sessions']);

  Future<void> _revoke(Map<String, dynamic> s) async {
    final name = (s['deviceName'] ?? 'Bu cihaz').toString();
    if (!await confirm(context, '"$name" oturumu kapatılsın mı? O cihazda yeniden giriş yapmak gerekir.', action: 'Çıkış yap', destructive: true)) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.delete('/api/me/sessions/${s['id']}'));
    if (r == null || !mounted) return;
    toast(context, 'Oturum kapatıldı.');
    setState(() => _v++);
  }

  Future<void> _revokeOthers() async {
    if (!await confirm(context, 'Bu telefon dışındaki tüm cihazlardan (eski uygulama sürümleri dahil) çıkış yapılsın mı?', action: 'Hepsinden çık', destructive: true)) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.post('/api/me/sessions/revoke-others'));
    if (r == null || !mounted) return;
    if (r['token'] is String) {
      // Token sürümü arttı: bu cihaz sunucunun verdiği yeni erişim token'ıyla devam eder.
      Api.setTokens(r);
      await AuthService.persistTokens();
    }
    if (!mounted) return;
    toast(context, 'Diğer cihazlardan çıkış yapıldı.');
    setState(() => _v++);
  }

  String _subtitle(Map<String, dynamic> s) {
    final parts = <String>[
      if (s['appVersion'] != null) 'v${s['appVersion']}',
      if (s['ip'] != null) 'IP ${s['ip']}',
      'Son etkinlik: ${_date(s['lastUsedAt'])}',
      if (s['emulator'] == true) 'Emülatör',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Oturumlarım')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_v),
        load: _load,
        builder: (context, list, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(Gap.m), children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, Gap.m),
              child: Text(
                'Hesabınızın açık olduğu cihazlar. Tanımadığınız bir cihaz görürseniz oturumunu kapatın ve şifrenizi değiştirin.',
                style: TextStyle(color: Pal.textDim, height: 1.35),
              ),
            ),
            for (final s in list)
              Card(
                child: ListTile(
                  leading: Icon(Icons.phone_android, color: s['current'] == true ? Pal.cyan : Pal.textDim),
                  title: Text((s['deviceName'] ?? 'Bilinmeyen cihaz').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_subtitle(s), style: const TextStyle(fontSize: 12)),
                  trailing: s['current'] == true
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Pal.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                          child: const Text('Bu cihaz', style: TextStyle(color: Pal.cyan, fontSize: 12, fontWeight: FontWeight.w600)),
                        )
                      : TextButton(onPressed: () => _revoke(s), child: const Text('Çıkış', style: TextStyle(color: Pal.red))),
                ),
              ),
            const SizedBox(height: Gap.l),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Pal.red, side: const BorderSide(color: Pal.red)),
              onPressed: _revokeOthers,
              icon: const Icon(Icons.logout),
              label: const Text('Diğer tüm cihazlardan çıkış yap'),
            ),
          ]),
        ),
      ),
    );
  }
}
