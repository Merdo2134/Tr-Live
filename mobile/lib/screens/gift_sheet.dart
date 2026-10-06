import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import 'misc_screens.dart';

/// Hediye gönderme penceresi (Figma): üstte alıcı avatarları, sekmeler, 4'lü hediye ızgarası, adet ve Gönder.
/// Tek kişi, birden çok kişi (her birine tam adet), "Tüm Koltuk" ve "Tüm Oda" seçilebilir.
Future<void> showGiftSheet(
  BuildContext context, {
  required String roomId,
  required List<Map<String, dynamic>> members,
  String? recipientId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) => _GiftSheet(roomId: roomId, members: members, recipientId: recipientId),
  );
}

class _GiftSheet extends StatefulWidget {
  final String roomId;
  final List<Map<String, dynamic>> members;
  final String? recipientId;
  const _GiftSheet({required this.roomId, required this.members, this.recipientId});

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  static const _tabs = [('event', 'Etkinlik'), ('popular', 'Popüler'), ('private', 'Kişiye Özel'), ('vip', 'Vip')];
  static const _quantities = [1, 5, 10, 20, 50, 100, 500, 1000];
  static const _perPage = 8;

  List<Map<String, dynamic>> _gifts = [];
  BigInt _globalMin = BigInt.from(1000);
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _gift;
  int _quantity = 1;
  String _tab = 'popular';
  int _page = 0;
  String? _scope; // null | 'mic' | 'room'
  bool _expanded = false;
  final Set<String> _picked = {};
  bool _sending = false;
  final _pages = PageController();

  @override
  void initState() {
    super.initState();
    final first = widget.recipientId ?? (_onMic.isNotEmpty ? _onMic.first['userId'] as String : (widget.members.isNotEmpty ? widget.members.first['userId'] as String : null));
    if (first != null) _picked.add(first);
    _expanded = first != null && !_onMic.any((m) => m['userId'] == first);
    _load();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.get('/api/gifts');
      if (!mounted) return;
      setState(() {
        _gifts = listOf(r['gifts']);
        _globalMin = BigInt.tryParse((r['globalMinCoins'] ?? '1000').toString()) ?? BigInt.from(1000);
        final shown = _tabGifts;
        if (shown.isEmpty) {
          // Boş sekmede takılı kalmamak için dolu ilk sekmeye geç.
          for (final t in _tabs) {
            if (_gifts.any((g) => (g['category'] ?? 'popular') == t.$1)) {
              _tab = t.$1;
              break;
            }
          }
        }
        _gift = _tabGifts.isNotEmpty ? _tabGifts.first : null;
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

  List<Map<String, dynamic>> get _tabGifts => _gifts.where((g) => (g['category'] ?? 'popular') == _tab).toList();

  List<Map<String, dynamic>> get _onMic {
    final l = widget.members.where((m) => m['microphone'] == true && m['seatIndex'] != null).toList();
    l.sort((a, b) => ((a['seatIndex'] as num).toInt()).compareTo((b['seatIndex'] as num).toInt()));
    return l;
  }

  /// Hediyeyi alacak kişilerin kimlikleri (seçime göre).
  List<String> get _targets {
    if (_scope == 'mic') return [for (final m in _onMic) if (m['userId'] != Session.id) m['userId'] as String];
    if (_scope == 'room') return [for (final m in widget.members) if (m['userId'] != Session.id) m['userId'] as String];
    return _picked.where((id) => widget.members.any((m) => m['userId'] == id)).toList();
  }

  BigInt get _total {
    final price = BigInt.tryParse((_gift?['coinPrice'] ?? '0').toString()) ?? BigInt.zero;
    return price * BigInt.from(_quantity) * BigInt.from(_targets.length);
  }

  Future<void> _send() async {
    final gift = _gift;
    if (gift == null || _sending) return;
    final targets = _targets;
    if (targets.isEmpty) return toast(context, _scope == null ? 'Alıcı seçin.' : 'Bu seçimde başka kimse yok.', error: true);
    setState(() => _sending = true);
    final String dist = _scope == 'mic' ? 'all_mic' : (_scope == 'room' ? 'all_room' : (targets.length == 1 ? 'single' : 'each'));
    final r = await guard(context, () => Api.post('/api/rooms/${widget.roomId}/gifts/send', {
          'giftId': gift['id'],
          'quantity': _quantity,
          'distribution': dist,
          if (dist == 'single') 'recipientId': targets.first,
          if (dist == 'each') 'recipientIds': targets,
        }));
    if (!mounted) return;
    setState(() => _sending = false);
    if (r == null) return;
    Session.setCoins((r['balance'] ?? Session.coins).toString());
    Navigator.pop(context);
    toast(context, '${gift['name']} x$_quantity gönderildi.');
  }

  void _togglePerson(String id) {
    setState(() {
      if (_scope != null) {
        // Toplu seçimden tek tek seçime geçerken seçili kişilerden başla.
        _picked
          ..clear()
          ..addAll(_targets);
        _scope = null;
      }
      if (!_picked.add(id)) _picked.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.82),
        padding: EdgeInsets.fromLTRB(12, 14, 12, 10 + mq.viewInsets.bottom),
        decoration: const BoxDecoration(color: Color(0xFF0D1626), borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        child: _loading
            ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? SizedBox(height: 220, child: LoadError(message: _error!, onRetry: _load))
                : _body(),
      ),
    );
  }

  Widget _body() {
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _recipientRow(),
        const SizedBox(height: 10),
        _tabRow(),
        const SizedBox(height: 8),
        _giftPages(),
        const SizedBox(height: 6),
        _bottomRow(),
      ]),
    );
  }

  // ---------- Alıcılar ----------
  Widget _person(Map<String, dynamic> m) {
    final id = m['userId'] as String;
    final selected = _scope == 'mic'
        ? (m['microphone'] == true && id != Session.id)
        : _scope == 'room'
            ? id != Session.id
            : _picked.contains(id);
    final seat = m['seatIndex'] == null ? null : (m['seatIndex'] as num).toInt() + 1;
    final name = (mapOf(m['user'])?['displayName'] ?? '').toString();
    return GestureDetector(
      onTap: () => _togglePerson(id),
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: SizedBox(
          width: 52,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? Pal.pink : Colors.transparent, width: 2.5)),
              child: UserAvatar(user: mapOf(m['user']), radius: 20),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              constraints: const BoxConstraints(maxWidth: 52),
              decoration: BoxDecoration(color: selected ? Pal.pink : Colors.white24, borderRadius: BorderRadius.circular(8)),
              child: Text(seat != null ? '$seat' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _recipientRow() {
    final list = _expanded ? widget.members : _onMic;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: list.isEmpty
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Mikrofonda kimse yok. Ok ile odadakileri göster.', style: TextStyle(color: Colors.white54)))
            : _expanded
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: SingleChildScrollView(child: Wrap(runSpacing: 8, children: [for (final m in list) _person(m)])),
                  )
                : SizedBox(height: 74, child: ListView(scrollDirection: Axis.horizontal, children: [for (final m in list) _person(m)])),
      ),
      const SizedBox(width: 4),
      InkWell(
        customBorder: const CircleBorder(),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Pal.pink, width: 1.6)),
          child: Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white),
        ),
      ),
    ]);
  }

  // ---------- Sekmeler ----------
  Widget _tabRow() {
    return Row(children: [
      for (final t in _tabs)
        Expanded(
          child: InkWell(
            onTap: () {
              setState(() {
                _tab = t.$1;
                _page = 0;
                _gift = _tabGifts.isNotEmpty ? _tabGifts.first : null;
              });
              if (_pages.hasClients) _pages.jumpToPage(0);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == t.$1 ? Pal.pink : Colors.transparent, width: 2))),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(t.$2, style: TextStyle(fontWeight: _tab == t.$1 ? FontWeight.w800 : FontWeight.w500, color: _tab == t.$1 ? Pal.pink : Colors.white70, fontSize: 14)),
              ),
            ),
          ),
        ),
      PopupMenuButton<String?>(
        tooltip: 'Toplu seçim',
        onSelected: (v) => setState(() => _scope = v == _scope ? null : v),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'mic', child: Text('Tüm Koltuk')),
          PopupMenuItem(value: 'room', child: Text('Tüm Oda')),
        ],
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(border: Border.all(color: _scope == null ? Colors.white30 : Pal.pink), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_scope == 'mic' ? 'Tüm Koltuk' : (_scope == 'room' ? 'Tüm Oda' : 'Listele'), style: TextStyle(fontSize: 12, color: _scope == null ? Colors.white70 : Pal.pink)),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white70),
          ]),
        ),
      ),
    ]);
  }

  // ---------- Hediye ızgarası ----------
  Widget _giftPages() {
    final gifts = _tabGifts;
    if (gifts.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('Bu sekmede hediye yok.', style: TextStyle(color: Colors.white54))));
    }
    final pageCount = (gifts.length / _perPage).ceil();
    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      final tileW = (box.maxWidth - gap * 3) / 4;
      final tileH = tileW * 1.05;
      return Column(children: [
        SizedBox(
          height: tileH * 2 + gap,
          child: PageView.builder(
            controller: _pages,
            itemCount: pageCount,
            onPageChanged: (p) => setState(() => _page = p),
            itemBuilder: (_, p) {
              final slice = gifts.skip(p * _perPage).take(_perPage).toList();
              return Wrap(spacing: gap, runSpacing: gap, children: [for (final g in slice) SizedBox(width: tileW, height: tileH, child: _giftTile(g))]);
            },
          ),
        ),
        if (pageCount > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < pageCount; i++)
                Container(margin: const EdgeInsets.symmetric(horizontal: 2.5), width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? Colors.white : Colors.white30)),
            ]),
          ),
      ]);
    });
  }

  Widget _giftTile(Map<String, dynamic> g) {
    final selected = _gift?['id'] == g['id'];
    final price = BigInt.tryParse((g['coinPrice'] ?? '0').toString()) ?? BigInt.zero;
    final icon = Api.absoluteUrl(g['iconUrl'] as String?);
    final animated = (g['animationUrl'] ?? '').toString().isNotEmpty;
    return Semantics(
      button: true,
      selected: selected,
      label: '${g['name']} ${g['coinPrice']} Coin',
      child: GestureDetector(
        onTap: () => setState(() => _gift = g),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF16233A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? Pal.pink : Colors.transparent, width: 2),
          ),
          child: Stack(children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 22),
                child: icon != null
                    ? Image.network(icon, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.white54, size: 34))
                    : const Icon(Icons.card_giftcard, color: Colors.white54, size: 34),
              ),
            ),
            Positioned(
              left: 5,
              top: 5,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (animated) _badge(Icons.auto_awesome, const Color(0xFF1FA2FF)),
                if (price >= _globalMin) ...[const SizedBox(height: 3), _badge(Icons.public, Pal.pink)],
              ]),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 4,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const CircleAvatar(radius: 5.5, backgroundColor: Pal.amber),
                const SizedBox(width: 3),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(_short(price), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _badge(IconData icon, Color c) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(5)),
        child: Icon(icon, size: 11, color: Colors.white),
      );

  String _short(BigInt v) {
    final million = BigInt.from(1000000);
    if (v >= million && v % million == BigInt.zero) return '${v ~/ million}M';
    return v.toString();
  }

  // ---------- Alt satır ----------
  Widget _bottomRow() {
    final n = _targets.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (n > 1 || _quantity > 1)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text('Toplam ${fmtNumber(_total.toString())} Coin · $n kişi × $_quantity adet', style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ),
      Row(children: [
        Expanded(
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
            child: ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: Session.me,
              builder: (_, me, __) => Row(children: [
                const CircleAvatar(radius: 14, backgroundColor: Pal.amber, child: Icon(Icons.star, size: 16, color: Colors.white)),
                const SizedBox(width: 8),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('${fmtNumber(me?['coins'])}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)))),
                const Icon(Icons.chevron_right),
              ]),
            ),
          ),
        ),
        Container(
          height: 40,
          decoration: BoxDecoration(border: Border.all(color: Pal.pink, width: 1.4), borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            PopupMenuButton<int>(
              tooltip: 'Adet',
              onSelected: (v) => setState(() => _quantity = v),
              itemBuilder: (_) => [for (final q in _quantities) PopupMenuItem(value: q, child: Text('$q'))],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.w700)), const Icon(Icons.keyboard_arrow_down, size: 18)]),
              ),
            ),
            InkWell(
              onTap: (_sending || _gift == null) ? null : _send,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Pal.purple, Pal.pink]),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(9)),
                ),
                child: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Gönder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ]),
    ]);
  }
}
