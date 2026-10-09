import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../services/socket_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';

String _tl(dynamic cents) {
  final c = BigInt.tryParse('$cents') ?? BigInt.zero;
  final whole = c ~/ BigInt.from(100);
  final frac = (c % BigInt.from(100)).toInt().toString().padLeft(2, '0');
  return '${fmtNumber(whole.toString())},$frac₺';
}

const _methods = ['GPay Kredi Kartı', 'ininal', 'BKM Express', 'Papara', 'Payguru Banka Transferi', 'Google Wallet'];

/// Yükleme Merkezi: bakiye, coin paketleri ve ödeme yöntemleri.
class CoinsCenterScreen extends StatefulWidget {
  const CoinsCenterScreen({super.key});

  @override
  State<CoinsCenterScreen> createState() => _CoinsCenterScreenState();
}

class _CoinsCenterScreenState extends State<CoinsCenterScreen> {
  int _v = 0;

  void _openPayment(Map<String, dynamic> pkg) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text('${fmtNumber(pkg['coins'])} Coin · ${_tl(pkg['priceCents'])}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final m in _methods)
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(m),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(c);
                showDialog<void>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text(m),
                    content: const Text('Bu ödeme yöntemi henüz bağlı değil. Coin yüklemek için Müşteri Hizmetleri\'ne yazabilir veya bayilerimizden yükleme isteyebilirsin.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d), child: const Text('Tamam')),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(d);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerServiceScreen()));
                        },
                        child: const Text('Müşteri Hizmetleri'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Yükleme Merkezi'),
        actions: [IconButton(tooltip: 'Müşteri hizmetleri', icon: const Icon(Icons.headset_mic_outlined, color: Color(0xFFFFEB3B)), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerServiceScreen())))],
      ),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_v),
        load: () async {
          try {
            await Session.refresh();
          } catch (_) {/* bakiye eski görünse de paketler açılsın */}
          final r = await Api.get('/api/store/coin-packages');
          return {'packages': listOf(r['packages'])};
        },
        builder: (context, d, reload) {
          final pkgs = listOf(d['packages']);
          return RefreshIndicator(
            onRefresh: () async => setState(() => _v++),
            child: ListView(padding: EdgeInsets.zero, children: [
              Container(
                padding: const EdgeInsets.only(top: 14, bottom: 26),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A3A3A), Color(0xFF111111)])),
                child: Column(children: [
                  const Text('Coins', style: TextStyle(color: Color(0xFFFFEB3B), fontSize: 17, fontWeight: FontWeight.w800)),
                  Container(margin: const EdgeInsets.only(top: 4), height: 2, width: 40, color: const Color(0xFFFFEB3B)),
                  const SizedBox(height: 22),
                  ValueListenableBuilder<Map<String, dynamic>?>(
                    valueListenable: Session.me,
                    builder: (_, __, ___) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.monetization_on, color: Colors.amber, size: 46),
                      const SizedBox(width: 10),
                      Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(fmtNumber(Session.coins), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800)))),
                    ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: pkgs.isEmpty
                    ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Şu an satışta paket yok.', style: TextStyle(color: Pal.textDim))))
                    : GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.78,
                        children: [
                          for (final p in pkgs)
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _openPayment(p),
                              child: Container(
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFEB3B), width: 1), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A3A3A), Colors.black])),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  const Icon(Icons.monetization_on, color: Colors.amber, size: 52),
                                  const SizedBox(height: 8),
                                  FittedBox(child: Text(fmtNumber(p['coins']), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                                  const SizedBox(height: 2),
                                  Text(_tl(p['priceCents']), style: const TextStyle(color: Pal.textDim, fontSize: 12)),
                                ]),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              Center(child: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerServiceScreen())), child: const Text('Müşteri Hizmetleri Merkezi  ›', style: TextStyle(color: Pal.textDim, fontSize: 12)))),
              Center(child: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportChatScreen(category: 'Diğer'))), child: const Text('Ödeme sonrası coins alamazsam ne yapmalıyım?  ›', style: TextStyle(color: Pal.textDim, fontSize: 12)))),
              const SizedBox(height: 24),
            ]),
          );
        },
      ),
    );
  }
}

/// Müşteri Hizmetleri Merkezi: konu kutuları ve çevrimiçi destek.
class CustomerServiceScreen extends StatelessWidget {
  const CustomerServiceScreen({super.key});

  static const _topics = [
    ['Aile', Icons.groups], ['ACM ve Yayıncı Konuları', Icons.podcasts], ['Oyunlar', Icons.casino], ['Etkinlikler', Icons.event],
    ['Onaylamalar', Icons.verified_outlined], ['Özelden yapılan küfür ve hakaret', Icons.report_gmailerrorred], ['VIP', Icons.workspace_premium], ['BCM', Icons.business_center_outlined],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Müşteri Hizmetleri Merkezi')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            for (final t in _topics)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SupportChatScreen(category: t[0] as String))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: const Color(0xFF26262A), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)), child: Icon(t[1] as IconData, color: const Color(0xFFFFEB3B), size: 22)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(t[0] as String, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.15))),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 40),
        Center(
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF26262A), foregroundColor: Colors.white, shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportChatScreen())),
            child: const Text('Çevrimiçi müşteri hizmetleri', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
      ]),
    );
  }
}

/// Müşteri hizmetleri sohbeti (yetkililer yanıtlar).
class SupportChatScreen extends StatefulWidget {
  final String? category;
  const SupportChatScreen({super.key, this.category});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _msgs = [];
  Timer? _poll;
  StreamSubscription? _sub;
  bool _sending = false;
  bool _first = true;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
    _sub = SocketService.instance.events.listen((e) {
      if (e['type'] == 'support_message') _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sub?.cancel();
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/api/support/messages');
      if (!mounted) return;
      final list = listOf(r['messages']);
      final changed = list.length != _msgs.length;
      setState(() => _msgs = list);
      if (changed || _first) _toEnd();
      _first = false;
    } catch (_) {/* sessiz */}
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Future<void> _send() async {
    final t = _ctl.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    final r = await guard(context, () => Api.post('/api/support/messages', {'text': t, if (widget.category != null) 'category': widget.category}));
    if (!mounted) return;
    setState(() => _sending = false);
    if (r != null) {
      _ctl.clear();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category == null ? 'Müşteri Hizmetleri Merkezi' : widget.category!, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Column(children: [
        Expanded(
          child: ListView(controller: _scroll, padding: const EdgeInsets.all(12), children: [
            for (final m in _msgs)
              Align(
                alignment: m['fromStaff'] == true ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                  decoration: BoxDecoration(color: m['fromStaff'] == true ? const Color(0xFF26262A) : Pal.cyan.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (m['fromStaff'] == true) const Text('Müşteri Hizmetleri', style: TextStyle(fontSize: 10, color: Color(0xFFFFEB3B), fontWeight: FontWeight.w800)),
                    if (m['category'] != null && m['fromStaff'] != true) Text('[${m['category']}]', style: const TextStyle(fontSize: 10, color: Color(0xFF00212A), fontWeight: FontWeight.w800)),
                    Text((m['text'] ?? '').toString(), style: TextStyle(color: m['fromStaff'] == true ? Colors.white : const Color(0xFF00212A))),
                  ]),
                ),
              ),
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF3B0), borderRadius: BorderRadius.circular(14)),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.campaign, color: Color(0xFFE6A700)),
                SizedBox(width: 8),
                Expanded(child: Text('Merhaba, müşteri hizmetleri ile iletişime geçtiğiniz için teşekkür ediyoruz. Çalışma saatlerimiz her gün saat 09:00\'dan saat 01:00\'a kadardır. Lütfen sorununuzu detaylı bir şekilde bize iletiniz.', style: TextStyle(color: Color(0xFF8A5A00), height: 1.35))),
              ]),
            ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(hintText: 'Mesajınızı yazın...', filled: true, fillColor: Colors.white, hintStyle: const TextStyle(color: Colors.black38), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                  style: const TextStyle(color: Colors.black),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(style: IconButton.styleFrom(backgroundColor: const Color(0xFFFFC107), foregroundColor: Colors.black), onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Yönetici / yardımcı admin: kullanıcıların müşteri hizmetleri yazışmaları.
class SupportAdminTab extends StatefulWidget {
  const SupportAdminTab({super.key});

  @override
  State<SupportAdminTab> createState() => _SupportAdminTabState();
}

class _SupportAdminTabState extends State<SupportAdminTab> {
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<Map<String, dynamic>>>(
      key: ValueKey(_v),
      load: () async => listOf((await Api.get('/api/admin/support/threads'))['threads']),
      builder: (context, th, reload) => RefreshIndicator(
        onRefresh: () async => setState(() => _v++),
        child: th.isEmpty
            ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Henüz destek mesajı yok.')))])
            : ListView(children: [
                for (final t in th)
                  ListTile(
                    leading: CircleAvatar(backgroundImage: (t['avatarUrl'] as String?) == null ? null : NetworkImage(Api.absoluteUrl(t['avatarUrl'] as String)!), child: (t['avatarUrl'] as String?) == null ? const Icon(Icons.person) : null),
                    title: Text('${t['displayName'] ?? t['username']}  ·  ID ${t['publicId'] ?? '-'}'),
                    subtitle: Text('${t['lastFromStaff'] == true ? 'Sen: ' : ''}${t['lastMessage']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: (t['waiting'] as num? ?? 0) > 0 ? Badge(label: Text('${t['waiting']}'), backgroundColor: Colors.red) : null,
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => _SupportThreadPage(user: t)));
                      if (mounted) setState(() => _v++);
                    },
                  ),
              ]),
      ),
    );
  }
}

class _SupportThreadPage extends StatefulWidget {
  final Map<String, dynamic> user;
  const _SupportThreadPage({required this.user});

  @override
  State<_SupportThreadPage> createState() => _SupportThreadPageState();
}

class _SupportThreadPageState extends State<_SupportThreadPage> {
  final _ctl = TextEditingController();
  List<Map<String, dynamic>> _msgs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await guard(context, () => Api.get('/api/admin/support/${widget.user['userId']}'));
    if (r != null && mounted) setState(() => _msgs = listOf(r['messages']));
  }

  Future<void> _reply() async {
    final t = _ctl.text.trim();
    if (t.isEmpty) return;
    final r = await guard(context, () => Api.post('/api/admin/support/${widget.user['userId']}/reply', {'text': t}));
    if (r != null) {
      _ctl.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.user['displayName'] ?? widget.user['username']}  ·  ID ${widget.user['publicId'] ?? '-'}')),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            for (final m in _msgs)
              Align(
                alignment: m['fromStaff'] == true ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                  decoration: BoxDecoration(color: m['fromStaff'] == true ? Pal.cyan.withValues(alpha: 0.9) : const Color(0xFF26262A), borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (m['category'] != null) Text('[${m['category']}]', style: const TextStyle(fontSize: 10, color: Color(0xFFFFEB3B), fontWeight: FontWeight.w800)),
                    Text((m['text'] ?? '').toString(), style: TextStyle(color: m['fromStaff'] == true ? const Color(0xFF00212A) : Colors.white)),
                  ]),
                ),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(child: TextField(controller: _ctl, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Yanıt yaz...', isDense: true, border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _reply, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Yönetici: coin paketlerini ekle / aç-kapat.
class CoinPackagesPage extends StatefulWidget {
  const CoinPackagesPage({super.key});

  @override
  State<CoinPackagesPage> createState() => _CoinPackagesPageState();
}

class _CoinPackagesPageState extends State<CoinPackagesPage> {
  int _v = 0;

  Future<void> _add() async {
    final coins = TextEditingController();
    final price = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Coin paketi ekle'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: coins, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Coin miktarı (örn. 7000)')),
          TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fiyat ₺ (örn. 42.99)')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ekle'))],
      ),
    );
    final cText = coins.text.trim();
    final pText = price.text.trim().replaceAll(',', '.');
    coins.dispose();
    price.dispose();
    if (ok != true || !mounted) return;
    final cents = ((double.tryParse(pText) ?? 0) * 100).round();
    final r = await guard(context, () => Api.post('/api/admin/coin-packages', {'coins': cText, 'priceCents': '$cents'}));
    if (r != null && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coin paketleri')),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_v),
        load: () async => listOf((await Api.get('/api/admin/coin-packages'))['packages']),
        builder: (context, pk, reload) => ListView(children: [
          for (final p in pk)
            SwitchListTile(
              title: Text('${fmtNumber(p['coins'])} coin'),
              subtitle: Text(_tl(p['priceCents'])),
              value: p['isActive'] == true,
              onChanged: (v) async {
                final r = await guard(context, () => Api.post('/api/admin/coin-packages/${p['id']}/active', {'isActive': v}));
                if (r != null && mounted) setState(() => _v++);
              },
            ),
        ]),
      ),
    );
  }
}
