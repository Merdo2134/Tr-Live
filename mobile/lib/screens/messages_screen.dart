import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import '../services/inbox_service.dart';
import '../services/presence_service.dart';
import '../services/session.dart';
import '../services/socket_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/image_pick.dart';
import '../widgets/presence_widgets.dart';
import '../widgets/safety_actions.dart';
import 'inbox_screens.dart';
import 'user_screens.dart';

/// Mesajlar sekmesi (Yoho düzeni): kategori kartları + sohbet listesi. İçerik [MessagesHome]'dadır; oda içindeki
/// "Sohbet" penceresi de aynı içeriği kullanır.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: MessagesHome());
}

/// Özel sohbet (Yoho düzeni): ortada ad, sağda karşı tarafın fotoğrafı; tarih ayraçları; gelen mesajlar solda gri,
/// giden mesajlar sağda yeşil baloncuk; altta fotoğraf · yazı kutusu · emoji · gönder.
class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> peer;
  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _mineColor = Color(0xFF22C55E);
  static const _emojis = ['😀', '😂', '🥰', '😍', '😎', '🤩', '😘', '😭', '😡', '👍', '👏', '🙏', '🔥', '💯', '🎉', '❤️', '💎', '🌹', '🎁', '👑', '🎤', '🎶', '😴', '🤔', '😅', '🥳', '😇', '🤗', '😜', '🙌', '💪', '✨'];

  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _hasText = false;
  String? _error;
  StreamSubscription? _sub;
  // "Yazıyor...": karşı taraf yazarken 4 sn gösterilir; ben yazarken en fazla 2,5 sn'de bir bildirilir.
  bool _peerTyping = false;
  Timer? _typingTimer;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  String get _peerId => widget.peer['id'].toString();

  void _onInput(String text) {
    final has = text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    if (!has) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) < const Duration(milliseconds: 2500)) return;
    _lastTypingSent = now;
    SocketService.instance.send({'type': 'typing', 'to': _peerId});
  }

  @override
  void initState() {
    super.initState();
    _load();
    PresenceService.watch([_peerId]);
    _sub = SocketService.instance.events.listen((e) {
      if (e['type'] == 'connected' && mounted) {
        _load(); // bağlantı koptuysa arada gelen mesajları al
        return;
      }
      // Karşı taraf mesajlarımı okudu: "Görüldü".
      if (e['type'] == 'dm_read' && e['userId']?.toString() == _peerId) {
        if (!mounted) return;
        final at = e['at'] ?? DateTime.now().toUtc().toIso8601String();
        setState(() {
          for (final m in _messages) {
            if (m['senderId'] == Session.id && m['readAt'] == null) m['readAt'] = at;
          }
        });
        return;
      }
      if (e['type'] == 'typing' && e['userId']?.toString() == _peerId) {
        if (!mounted) return;
        _typingTimer?.cancel();
        setState(() => _peerTyping = true);
        _typingTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _peerTyping = false);
        });
        return;
      }
      if (e['type'] != 'dm') return;
      final m = mapOf(e['message']);
      if (m == null || m['senderId'] != _peerId) return;
      // Mesaj geldi: "yazıyor" biter.
      _typingTimer?.cancel();
      if (_peerTyping && mounted) setState(() => _peerTyping = false);
      if (!mounted || _messages.any((x) => x['id'] == m['id'])) return; // aynı mesaj iki kez eklenmesin
      setState(() => _messages.add(m));
      _toEnd();
      Api.get('/api/messages/with/$_peerId').then((_) => Inbox.refresh()).catchError((_) => <String, dynamic>{}); // okundu işaretle
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _typingTimer?.cancel();
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/api/messages/with/$_peerId');
      if (!mounted) return;
      setState(() {
        _messages = listOf(r['messages']);
        _loading = false;
        _error = null;
      });
      _toEnd();
      Inbox.refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _post(Map<String, dynamic> body) async {
    final r = await guard(context, () => Api.post('/api/messages/with/$_peerId', body));
    final m = mapOf(r?['message']);
    if (m != null && mounted) {
      setState(() => _messages.add(m));
      _toEnd();
    }
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    await _post({'text': text});
    if (!mounted) return;
    _ctl.clear();
    setState(() {
      _sending = false;
      _hasText = false;
    });
  }

  /// Galeriden fotoğraf: önce yüklenir, sonra mesaj olarak gönderilir.
  Future<void> _sendImage() async {
    if (_sending) return;
    final img = await pickImage(context);
    if (img == null || !mounted) return;
    setState(() => _sending = true);
    final up = await guard(context, () => Api.putBytes('/api/messages/image', img.bytes, img.mime));
    final url = up?['url'] as String?;
    if (url != null && mounted) await _post({'imageUrl': url});
    if (mounted) setState(() => _sending = false);
  }

  void _emojiSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 8,
            children: [
              for (final e in _emojis)
                InkWell(
                  onTap: () {
                    Navigator.pop(c);
                    _ctl.text += e;
                    _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
                    _onInput(_ctl.text);
                  },
                  child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _messageMenu(Map<String, dynamic> m) {
    final mine = m['senderId'] == Session.id;
    final text = (m['text'] ?? '').toString();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (text.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Kopyala'),
              onTap: () {
                Navigator.pop(c);
                Clipboard.setData(ClipboardData(text: text));
                toast(context, 'Kopyalandı.');
              },
            ),
          if (!mine)
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Mesajı şikâyet et'),
              onTap: () {
                Navigator.pop(c);
                reportDialog(context, kind: 'dm', targetUserId: _peerId, messageId: m['id'] as String?);
              },
            ),
        ]),
      ),
    );
  }

  void _openImage(String url) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: Center(child: InteractiveViewer(maxScale: 5, child: Image.network(url, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38)))),
      ),
    ));
  }

  Widget _bubble(Map<String, dynamic> m, bool mine, double w) {
    final img = Api.absoluteUrl(m['imageUrl'] as String?);
    final text = (m['text'] ?? '').toString();
    if (img != null && text.isEmpty) {
      return GestureDetector(
        onTap: () => _openImage(img),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w * 0.5, maxHeight: w * 0.7, minWidth: 60, minHeight: 60),
            child: Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 120, height: 120, child: ColoredBox(color: Pal.surfaceHi, child: Icon(Icons.broken_image, color: Pal.textDim)))),
          ),
        ),
      );
    }
    return Container(
      constraints: BoxConstraints(maxWidth: w * 0.66),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: mine ? _mineColor : Pal.surfaceHi, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (img != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(onTap: () => _openImage(img), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(img, width: w * 0.5, fit: BoxFit.cover))),
          ),
        Text(text, style: TextStyle(fontSize: 15, height: 1.3, color: mine ? Colors.white : Pal.text)),
      ]),
    );
  }

  Widget _messageRow(int i, double w) {
    final m = _messages[i];
    final mine = m['senderId'] == Session.id;
    // "Görüldü" yalnızca okunan son mesajımın altında gösterilir.
    final seen = mine && m['readAt'] != null && !_messages.skip(i + 1).any((x) => x['senderId'] == Session.id && x['readAt'] != null);
    final avatar = UserAvatar(user: mine ? Session.me.value : widget.peer, radius: 17);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (i == 0 || needsStamp(_messages[i - 1]['createdAt'], m['createdAt'])) TimeStamp(m['createdAt']),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine) ...[
              GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: _peerId))), child: avatar),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                GestureDetector(onLongPress: () => _messageMenu(m), child: _bubble(m, mine, w)),
                if (seen) const Padding(padding: EdgeInsets.only(top: 3), child: Text('Görüldü', style: TextStyle(fontSize: 11, color: Pal.textDim))),
              ]),
            ),
            if (mine) ...[const SizedBox(width: 8), avatar],
          ],
        ),
      ),
    ]);
  }

  Widget _inputBar(double w) {
    Widget icon(IconData i, String tip, VoidCallback? onTap, {Color color = Pal.text}) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          icon: Icon(i, color: onTap == null ? Pal.textDim : color, size: 27),
        );
    return Container(
      decoration: const BoxDecoration(color: Pal.surface, border: Border(top: BorderSide(color: Color(0x1FFFFFFF), width: 0.8))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 6, 8),
          child: Row(children: [
            icon(Icons.image_outlined, 'Fotoğraf gönder', _sending ? null : _sendImage),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(left: 16, right: 4),
                decoration: BoxDecoration(color: Pal.surfaceHi, borderRadius: BorderRadius.circular(24)),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _ctl,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      onChanged: _onInput,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        counterText: '',
                        hintText: 'Bir şey söyle...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                  icon(Icons.sentiment_satisfied_alt_outlined, 'Emoji', _emojiSheet),
                ]),
              ),
            ),
            const SizedBox(width: 4),
            icon(Icons.send_rounded, 'Gönder', _hasText && !_sending ? _send : null, color: _mineColor),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    final w = MediaQuery.sizeOf(context).width;
    final nameColor = parseColor(peer['nameColor'] as String?);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          WipNameText(
            (peer['displayName'] ?? '').toString(),
            level: (peer['wipLevel'] as num?)?.toInt(),
            color: nameColor ?? const Color(0xFFFF4F6E),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          if (_peerTyping)
            const Text('yazıyor...', style: TextStyle(fontSize: 11, color: Pal.green, fontStyle: FontStyle.italic))
          else
            PresenceLine(userId: _peerId, fontSize: 11),
        ]),
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: _peerId))),
            child: PresenceAvatar(userId: _peerId, dotSize: 10, child: UserAvatar(user: peer, radius: 17)),
          ),
          PopupMenuButton<String>(
            tooltip: 'Diğer',
            onSelected: (a) async {
              if (a == 'block') {
                if (await blockUserDialog(context, _peerId, (peer['displayName'] ?? 'Kullanıcı').toString()) && context.mounted) Navigator.pop(context);
              }
              if (a == 'report' && _messages.isNotEmpty) {
                final last = _messages.lastWhere((m) => m['senderId'] == _peerId, orElse: () => _messages.last);
                if (context.mounted) reportDialog(context, kind: 'dm', targetUserId: _peerId, messageId: last['id'] as String?);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Şikâyet et')),
              PopupMenuItem(value: 'block', child: Text('Engelle')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? LoadError(message: _error!, onRetry: _load)
                  : _messages.isEmpty
                      ? const Center(child: Text('Sohbeti başlatmak için bir mesaj yaz.', style: TextStyle(color: Pal.textDim)))
                      : ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(homeMargin(w), 4, homeMargin(w), 12),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _messageRow(i, w),
                        ),
        ),
        _inputBar(w),
      ]),
    );
  }
}
