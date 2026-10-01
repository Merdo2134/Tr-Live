import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/common.dart';

/// Hediye gönderme penceresi. Kendine hediye dahil, odadaki herkes alıcı olabilir.
Future<void> showGiftSheet(
  BuildContext context, {
  required String roomId,
  required List<Map<String, dynamic>> members,
  String? recipientId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
  List<Map<String, dynamic>> _gifts = [];
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _gift;
  int _quantity = 1;
  String _mode = 'single';
  String? _recipient;
  final Set<String> _selected = {};
  bool _sending = false;

  static const _modes = {
    'single': 'Seçili kişi',
    'equal': 'Mikrofondakilere eşit',
    'random': 'Rastgele',
    'selected': 'Seçtiklerime',
  };

  @override
  void initState() {
    super.initState();
    _recipient = widget.recipientId ?? (widget.members.isNotEmpty ? widget.members.first['userId'] as String : null);
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/api/gifts');
      if (!mounted) return;
      setState(() {
        _gifts = listOf(r['gifts']);
        _gift = _gifts.isNotEmpty ? _gifts.first : null;
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

  List<Map<String, dynamic>> get _onMic => widget.members.where((m) => m['microphone'] == true).toList();

  BigInt get _total {
    final price = BigInt.tryParse((_gift?['coinPrice'] ?? '0').toString()) ?? BigInt.zero;
    return price * BigInt.from(_quantity);
  }

  Future<void> _send() async {
    final gift = _gift;
    if (gift == null || _sending) return;
    if (_mode == 'single' && _recipient == null) return toast(context, 'Alıcı seçin.', error: true);
    if (_mode == 'selected' && _selected.isEmpty) return toast(context, 'Mikrofondan en az bir kişi seçin.', error: true);
    if ((_mode == 'equal' || _mode == 'random') && _onMic.isEmpty) return toast(context, 'Mikrofonda kimse yok.', error: true);
    setState(() => _sending = true);
    final r = await guard(context, () => Api.post('/api/rooms/${widget.roomId}/gifts/send', {
          'giftId': gift['id'],
          'quantity': _quantity,
          'distribution': _mode,
          if (_mode == 'single') 'recipientId': _recipient,
          if (_mode == 'selected') 'selectedUserIds': _selected.toList(),
        }));
    if (!mounted) return;
    setState(() => _sending = false);
    if (r == null) return;
    Session.setCoins((r['balance'] ?? Session.coins).toString());
    Navigator.pop(context);
    toast(context, '${gift['name']} x$_quantity gönderildi.');
  }

  String _name(Map<String, dynamic> m) {
    final u = mapOf(m['user']);
    final self = m['userId'] == Session.id ? ' (Ben)' : '';
    return '${u?['displayName'] ?? ''}$self';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: _loading
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : _error != null
              ? SizedBox(height: 200, child: LoadError(message: _error!, onRetry: _load))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Hediye gönder', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: Session.me,
            builder: (_, me, __) => Text('Bakiye: ${fmtNumber(me?['coins'])} Coin'),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final g in _gifts)
              GestureDetector(
                onTap: () => setState(() => _gift = g),
                child: Container(
                  width: 84,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _gift?['id'] == g['id'] ? Colors.pinkAccent : Colors.white24, width: 2),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (Api.absoluteUrl(g['iconUrl'] as String?) != null)
                      Image.network(Api.absoluteUrl(g['iconUrl'] as String?)!, width: 36, height: 36, errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard))
                    else
                      const Icon(Icons.card_giftcard, size: 32),
                    const SizedBox(height: 4),
                    Text((g['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    Text(fmtNumber(g['coinPrice']), style: const TextStyle(fontSize: 11, color: Colors.amber)),
                  ]),
                ),
              ),
          ]),
        ),
        if (_gifts.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Henüz hediye tanımlı değil.')),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Adet'),
          IconButton(onPressed: _quantity > 1 ? () => setState(() => _quantity -= 1) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('$_quantity', style: Theme.of(context).textTheme.titleMedium),
          IconButton(onPressed: _quantity < 10000 ? () => setState(() => _quantity += 1) : null, icon: const Icon(Icons.add_circle_outline)),
          const Spacer(),
          for (final n in const [10, 50, 100])
            Padding(padding: const EdgeInsets.only(left: 4), child: ActionChip(label: Text('$n'), onPressed: () => setState(() => _quantity = n))),
        ]),
        Wrap(spacing: 8, children: [
          for (final e in _modes.entries)
            ChoiceChip(label: Text(e.value), selected: _mode == e.key, onSelected: (_) => setState(() => _mode = e.key)),
        ]),
        const SizedBox(height: 8),
        if (_mode == 'single')
          Row(children: [
            const Text('Alıcı'),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: widget.members.any((m) => m['userId'] == _recipient) ? _recipient : null,
                hint: const Text('Kişi seçin'),
                items: [for (final m in widget.members) DropdownMenuItem(value: m['userId'] as String, child: Text(_name(m), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _recipient = v),
              ),
            ),
          ]),
        if (_mode == 'selected')
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView(shrinkWrap: true, children: [
              if (_onMic.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Mikrofonda kimse yok.')),
              for (final m in _onMic)
                CheckboxListTile(
                  dense: true,
                  value: _selected.contains(m['userId']),
                  title: Text(_name(m)),
                  onChanged: (v) => setState(() => v == true ? _selected.add(m['userId'] as String) : _selected.remove(m['userId'])),
                ),
            ]),
          ),
        if (_mode == 'equal' || _mode == 'random')
          Text('${_onMic.length} kişi mikrofonda. Hediye yalnızca mikrofondakilere dağıtılır.', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_sending || _gift == null) ? null : _send,
            icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
            label: Text('Gönder · ${fmtNumber(_total.toString())} Coin'),
          ),
        ),
      ]),
    );
  }
}
