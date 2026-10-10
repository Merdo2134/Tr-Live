import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../version.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';

String _dt(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return '-';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

String _uptime(dynamic seconds) {
  final s = (seconds is num ? seconds : num.tryParse('$seconds') ?? 0).toInt();
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  if (d > 0) return '$d gün $h sa';
  if (h > 0) return '$h sa $m dk';
  return '$m dk';
}

Map<String, dynamic> _m(dynamic v) => mapOf(v) ?? <String, dynamic>{};

/// Yönetim paneli > Panel: canlı sunucu durumu, bugünün sayıları ve yönetim kısayolları. 10 sn'de bir yenilenir.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  Map<String, dynamic>? _d;
  String? _error;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    try {
      final d = await Api.get('/api/admin/dashboard');
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      _busy = false;
    }
  }

  void _open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Widget _tile(String label, String value, {String? sub, IconData? icon, Color color = Pal.text, VoidCallback? onTap}) {
    return Material(
      color: Pal.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.md), side: const BorderSide(color: Pal.outline, width: 0.8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(Rad.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 16, color: Pal.textDim), const SizedBox(width: 6)],
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.textDim, fontSize: 12))),
            ]),
            const SizedBox(height: 6),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.textDim, fontSize: 11.5)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _grid(List<Widget> tiles) => LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - Gap.s) / 2;
        return Wrap(spacing: Gap.s, runSpacing: Gap.s, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
      });

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, Gap.l, 2, Gap.s),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      if (_error != null) return LoadError(message: _error!, onRetry: _load);
      return const Center(child: CircularProgressIndicator());
    }
    final server = _m(d['server']);
    final mem = _m(server['memory']);
    final rt = _m(d['realtime']);
    final db = _m(d['db']);
    final pool = _m(db['pool']);
    final lk = _m(d['livekit']);
    final live = _m(d['live']);
    final today = _m(d['today']);
    final alerts = _m(d['alerts']);
    final totals = _m(d['totals']);
    final lkOk = lk['ok'] == true;
    final lkText = lk['configured'] != true ? 'Ayarlı değil' : (lkOk ? 'Çalışıyor' : 'Ulaşılamıyor');
    final errors = (alerts['errors24h'] as num? ?? 0).toInt();
    final reports = (alerts['openReports'] as num? ?? 0).toInt();
    final dbMs = (db['latencyMs'] as num? ?? 0).toInt();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.xl), children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: _error == null ? Pal.green : Pal.red, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(_error == null ? 'Canlı · son güncelleme ${_dt(d['time'])}' : 'Bağlantı sorunu: $_error',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.textDim, fontSize: 12)),
          ),
        ]),
        _title('Şu an'),
        _grid([
          _tile('Çevrimiçi kullanıcı', fmtNumber(rt['onlineUsers']), icon: Icons.circle, color: Pal.green, sub: '${fmtNumber(rt['sockets'])} açık bağlantı'),
          _tile('Aktif oda', fmtNumber(live['activeRooms']), icon: Icons.meeting_room, sub: '${live['audioRooms'] ?? 0} sesli · ${live['videoRooms'] ?? 0} görüntülü'),
          _tile('Odalardaki kişi', fmtNumber(live['roomMembers']), icon: Icons.groups, sub: '${live['onMic'] ?? 0} mikrofonda'),
          _tile('Açık cihaz oturumu', fmtNumber(live['sessions']), icon: Icons.devices, sub: 'Toplam kullanıcı: ${fmtNumber(totals['users'])}'),
        ]),
        _title('Bugün'),
        _grid([
          _tile('Yeni kayıt', fmtNumber(today['newUsers']), icon: Icons.person_add_alt),
          _tile('Aktif kullanıcı', fmtNumber(today['activeUsers']), icon: Icons.how_to_reg),
          _tile('Hediye', fmtNumber(today['gifts']), icon: Icons.card_giftcard, sub: '${fmtNumber(today['giftCoins'])} Coin', color: Pal.gold),
          _tile('Mesaj', fmtNumber(today['roomMessages']), icon: Icons.chat_bubble_outline, sub: 'Özel: ${fmtNumber(today['directMessages'])}'),
          _tile('Kural ihlali', fmtNumber(today['strikes']), icon: Icons.report_gmailerrorred, sub: '${today['autoMutes'] ?? 0} otomatik kısıt', onTap: () => _open(const StrikesScreen())),
          _tile('Uygulama hatası (24 sa)', fmtNumber(errors), icon: Icons.bug_report_outlined, color: errors > 0 ? Pal.orange : Pal.text, onTap: () => _open(const ClientErrorsScreen())),
        ]),
        _title('Sistem'),
        _grid([
          _tile('Sunucu', 'v${server['version'] ?? '?'}', icon: Icons.dns, sub: 'Açık: ${_uptime(server['uptimeSec'])} · Node ${server['node'] ?? ''}'),
          _tile('CPU', '%${server['cpuPercent'] ?? 0}', icon: Icons.speed, sub: '${server['cores'] ?? '?'} çekirdek · yük ${(server['loadAvg'] is List && (server['loadAvg'] as List).isNotEmpty) ? (server['loadAvg'] as List).first : '-'}'),
          _tile('Bellek', '${mem['rssMb'] ?? 0} MB', icon: Icons.memory, sub: 'Heap ${mem['heapUsedMb'] ?? 0}/${mem['heapTotalMb'] ?? 0} MB'),
          _tile('Veritabanı', '$dbMs ms', icon: Icons.storage, color: dbMs > 300 ? Pal.orange : Pal.text,
              sub: '${db['sizeMb'] ?? 0} MB (medya ${db['mediaMb'] ?? 0}) · bağlantı ${pool['total'] ?? 0}/${pool['max'] ?? 10}, bekleyen ${pool['waiting'] ?? 0}'),
          _tile('LiveKit', lkText, icon: Icons.graphic_eq, color: lkOk ? Pal.green : Pal.orange,
              sub: lkOk ? '${lk['rooms'] ?? 0} oda · ${lk['participants'] ?? 0} katılımcı · ${lk['latencyMs'] ?? 0} ms' : (lk['error']?.toString() ?? '')),
          _tile('Açık şikâyet', fmtNumber(reports), icon: Icons.flag_outlined, color: reports > 0 ? Pal.orange : Pal.text, sub: 'Şikâyetler sekmesinden incelenir'),
        ]),
        _title('Yönetim'),
        Card(
          child: Column(children: [
            ListTile(leading: const Icon(Icons.bug_report_outlined), title: const Text('Uygulama hata kayıtları'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const ClientErrorsScreen())),
            ListTile(leading: const Icon(Icons.history), title: const Text('İşlem kaydı'), subtitle: const Text('Yetkili işlemleri ve para hareketleri'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const ActionsLogScreen())),
            ListTile(leading: const Icon(Icons.shield_outlined), title: const Text('Otomatik moderasyon'), subtitle: const Text('Link/telefon/küfür ihlalleri ve kısıtlar'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const StrikesScreen())),
            ListTile(leading: const Icon(Icons.tune), title: const Text('Uygulama ayarları'), subtitle: const Text('Zorunlu güncelleme, moderasyon kuralları'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const AppConfigScreen())),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Hata kayıtları
class ClientErrorsScreen extends StatefulWidget {
  const ClientErrorsScreen({super.key});

  @override
  State<ClientErrorsScreen> createState() => _ClientErrorsScreenState();
}

class _ClientErrorsScreenState extends State<ClientErrorsScreen> {
  int _v = 0;

  Future<void> _clear() async {
    if (!await confirm(context, 'Tüm uygulama hata kayıtları silinsin mi?', action: 'Sil', destructive: true)) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.delete('/api/admin/client-errors'));
    if (r != null && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Uygulama hata kayıtları'), actions: [
        IconButton(tooltip: 'Tümünü sil', onPressed: _clear, icon: const Icon(Icons.delete_sweep_outlined)),
      ]),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_v),
        load: () => Api.get('/api/admin/client-errors', query: {'limit': '150'}),
        builder: (context, data, reload) {
          final top = listOf(data['top']);
          final errors = listOf(data['errors']);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(Gap.m), children: [
              if (errors.isEmpty) const EmptyState(icon: Icons.check_circle_outline, text: 'Kayıtlı hata yok.'),
              if (top.isNotEmpty) ...[
                const Text('En sık (son 7 gün)', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: Gap.s),
                for (final t in top)
                  Card(
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(radius: 16, backgroundColor: Pal.orange.withValues(alpha: 0.2), child: Text('${t['count']}', style: const TextStyle(fontSize: 12, color: Pal.orange))),
                      title: Text('${t['message']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${t['source']} · ${t['users']} kişi · son ${_dt(t['lastAt'])}'),
                    ),
                  ),
                const SizedBox(height: Gap.m),
                const Text('Son kayıtlar', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: Gap.s),
              ],
              for (final e in errors)
                Card(
                  child: ExpansionTile(
                    title: Text('${e['message']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(
                      '${e['source']} · v${e['appVersion'] ?? '?'} · ${e['device'] ?? '-'}\n'
                      '${mapOf(e['user'])?['displayName'] ?? 'Giriş yapılmamış'} · ${_dt(e['createdAt'])}',
                      style: const TextStyle(fontSize: 11.5, color: Pal.textDim),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.m),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText('${e['message']}\n\n${e['stack'] ?? ''}', style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
                      ),
                    ],
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ İşlem kaydı
const _actionLabels = {
  'account_ban': 'Ban',
  'account_unban': 'Ban kaldırıldı',
  'profile_display_name': 'Nick değiştirildi',
  'profile_avatar': 'Profil fotoğrafı',
  'staff_role': 'Yetki değişikliği',
  'admin_coin_adjustment': 'Coin düzeltme',
  'admin_wip_grant': 'WIP verildi',
  'admin_wip_revoke': 'WIP alındı',
  'admin_inventory_grant': 'Öğe verildi',
  'dealer_credit': 'Bayiye Coin yüklendi',
  'dealer_sale': 'Bayi satışı',
  'agency_status': 'Ajans durumu',
  'broadcaster_status': 'Yayıncı durumu',
  'agency_config_update': 'Ajans ayarları',
  'agency_commission_override': 'Ajans komisyonu',
  'payout_period_close': 'Dönem kapatıldı',
  'host_salary_paid': 'Yayıncı maaşı ödendi',
  'agency_commission_paid': 'Ajans komisyonu ödendi',
  'kyc_status': 'Kimlik doğrulama',
  'banner_add': 'Banner eklendi',
  'banner_delete': 'Banner silindi',
  'announcement_add': 'Duyuru eklendi',
  'app_config_update': 'Uygulama ayarları',
  'chat_restriction': 'Sohbet kısıtı',
  'sessions_revoke': 'Oturumlar kapatıldı',
  'store_purchase': 'Mağaza alışverişi',
  'wip_purchase': 'WIP satın alma',
};

class ActionsLogScreen extends StatefulWidget {
  const ActionsLogScreen({super.key});

  @override
  State<ActionsLogScreen> createState() => _ActionsLogScreenState();
}

class _ActionsLogScreenState extends State<ActionsLogScreen> {
  String? _scope = 'staff';

  String _details(Map<String, dynamic> a) {
    final parts = <String>[];
    final coins = a['amountCoins']?.toString();
    if (coins != null && coins != '0') parts.add('$coins Coin');
    final before = a['balanceBefore'];
    final after = a['balanceAfter'];
    if (before != null && after != null) parts.add('bakiye ${fmtNumber(before)} → ${fmtNumber(after)}');
    final meta = mapOf(a['metadata']);
    if (meta != null) {
      for (final k in const ['reason', 'minutes', 'until', 'role', 'status', 'removed', 'after']) {
        final v = meta[k];
        if (v != null && '$v'.isNotEmpty) parts.add('$k: $v');
      }
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String? value) => Padding(
          padding: const EdgeInsets.only(right: Gap.s),
          child: ChoiceChip(label: Text(label), selected: _scope == value, onSelected: (_) => setState(() => _scope = value)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('İşlem kaydı')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.s),
          child: Row(children: [chip('Yetkili işlemleri', 'staff'), chip('Kullanıcı hareketleri', 'user'), chip('Tümü', null)]),
        ),
        Expanded(
          child: AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey(_scope),
            load: () async => listOf((await Api.get('/api/admin/actions', query: {'limit': '200', if (_scope != null) 'scope': _scope!}))['actions']),
            builder: (context, list, reload) => list.isEmpty
                ? const EmptyState(icon: Icons.history, text: 'Kayıt yok.')
                : RefreshIndicator(
                    onRefresh: reload,
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: Gap.xl),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = list[i];
                        final actor = mapOf(a['actor']);
                        final target = mapOf(a['target']);
                        final details = _details(a);
                        final label = _actionLabels[a['action']] ?? '${a['action']}';
                        return ListTile(
                          dense: true,
                          title: Text(target == null ? label : '$label · ${target['displayName'] ?? target['username']}'),
                          subtitle: Text(
                            '${actor == null ? 'Kullanıcı / sistem' : '${actor['displayName'] ?? actor['username']} (${actor['role'] ?? ''})'} · ${_dt(a['createdAt'])}'
                            '${details.isEmpty ? '' : '\n$details'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Otomatik moderasyon
const _strikeKinds = {'link': 'Link', 'phone': 'Telefon', 'profanity': 'Küfür', 'flood': 'Spam', 'auto_mute': 'Otomatik kısıt'};
const _strikePlaces = {'room_chat': 'Oda sohbeti', 'dm': 'Özel mesaj', 'post': 'Gönderi', 'comment': 'Yorum', 'bag_note': 'Çanta notu'};

class StrikesScreen extends StatefulWidget {
  const StrikesScreen({super.key});

  @override
  State<StrikesScreen> createState() => _StrikesScreenState();
}

class _StrikesScreenState extends State<StrikesScreen> {
  int _v = 0;

  Future<void> _restrict(Map<String, dynamic> user, int minutes) async {
    final r = await guard(context, () => Api.post('/api/admin/users/${user['id']}/chat-restriction', {'minutes': minutes}));
    if (r == null || !mounted) return;
    toast(context, minutes == 0 ? 'Kısıt kaldırıldı.' : '$minutes dakika kısıtlandı.');
    setState(() => _v++);
  }

  Future<void> _actions(Map<String, dynamic> s) async {
    final user = mapOf(s['user']);
    if (user == null) return;
    final restricted = s['restrictedUntil'] != null;
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('${user['displayName']} (@${user['username']})', style: const TextStyle(fontWeight: FontWeight.w700))),
          if (restricted) ListTile(leading: const Icon(Icons.lock_open), title: const Text('Kısıtı kaldır'), onTap: () => Navigator.pop(c, 0)),
          ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('1 saat sohbet kısıtı'), onTap: () => Navigator.pop(c, 60)),
          ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('24 saat sohbet kısıtı'), onTap: () => Navigator.pop(c, 1440)),
          ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('7 gün sohbet kısıtı'), onTap: () => Navigator.pop(c, 10080)),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    await _restrict(user, choice);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Otomatik moderasyon')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_v),
        load: () async => listOf((await Api.get('/api/admin/moderation/strikes', query: {'limit': '200'}))['strikes']),
        builder: (context, list, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.only(bottom: Gap.xl), children: [
            const Padding(
              padding: EdgeInsets.all(Gap.m),
              child: Text(
                'Link, telefon numarası, küfür veya spam içeren mesajlar gönderilmez ve buraya kaydedilir. Kısa sürede tekrarlayan '
                'kişi otomatik olarak süreli sohbet kısıtı alır. Kurallar "Uygulama ayarları"ndan değiştirilir.',
                style: TextStyle(color: Pal.textDim, fontSize: 12.5, height: 1.35),
              ),
            ),
            if (list.isEmpty) const EmptyState(icon: Icons.verified_user_outlined, text: 'Kayıtlı ihlal yok.'),
            for (final s in list)
              ListTile(
                dense: true,
                onTap: () => _actions(s),
                leading: Icon(s['kind'] == 'auto_mute' ? Icons.timer_off_outlined : Icons.report_gmailerrorred, color: s['kind'] == 'auto_mute' ? Pal.red : Pal.orange),
                title: Text('${mapOf(s['user'])?['displayName'] ?? '-'} · ${_strikeKinds[s['kind']] ?? s['kind']}'),
                subtitle: Text(
                  '${_strikePlaces[s['context']] ?? s['context']} · ${_dt(s['createdAt'])}'
                  '${s['sample'] == null ? '' : '\n"${s['sample']}"'}'
                  '${s['restrictedUntil'] == null ? '' : '\nKısıtlı: ${_dt(s['restrictedUntil'])} kadar'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Uygulama ayarları
class AppConfigScreen extends StatefulWidget {
  const AppConfigScreen({super.key});

  @override
  State<AppConfigScreen> createState() => _AppConfigScreenState();
}

class _AppConfigScreenState extends State<AppConfigScreen> {
  final _text = <String, TextEditingController>{
    'minAppVersion': TextEditingController(),
    'latestAppVersion': TextEditingController(),
    'updateUrl': TextEditingController(),
    'updateMessage': TextEditingController(),
    'strikeLimit': TextEditingController(),
    'strikeWindowMin': TextEditingController(),
    'muteMinutes': TextEditingController(),
    'maxMuteMinutes': TextEditingController(),
    'luckyRtpPct': TextEditingController(),
    'luckyReceiverPct': TextEditingController(),
    'luckyMaxWin': TextEditingController(),
    'luckyAnnounceMultiplier': TextEditingController(),
  };
  bool _blockLinks = true;
  bool _blockPhones = true;
  bool _luckyEnabled = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _ints = ['strikeLimit', 'strikeWindowMin', 'muteMinutes', 'maxMuteMinutes', 'luckyMaxWin', 'luckyAnnounceMultiplier'];

  /// Sunucu baz puan tutar (7000 = %70); panelde yüzde gösterilir.
  static String _pct(dynamic bps) {
    final n = (bps is num) ? bps : (num.tryParse('$bps') ?? 0);
    final p = n / 100;
    return p == p.roundToDouble() ? p.toInt().toString() : p.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.get('/api/admin/app-config');
      final c = mapOf(r['config']) ?? {};
      if (!mounted) return;
      setState(() {
        for (final e in _text.entries) {
          e.value.text = (c[e.key] ?? '').toString();
        }
        _blockLinks = c['blockLinks'] != false;
        _blockPhones = c['blockPhones'] != false;
        _luckyEnabled = c['luckyEnabled'] != false;
        _text['luckyRtpPct']!.text = _pct(c['luckyRtpBps'] ?? 7000);
        _text['luckyReceiverPct']!.text = _pct(c['luckyReceiverBps'] ?? 1000);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = errorText(e);
        });
      }
    }
  }

  Future<void> _save() async {
    final body = <String, dynamic>{
      'minAppVersion': _text['minAppVersion']!.text.trim(),
      'latestAppVersion': _text['latestAppVersion']!.text.trim(),
      'updateUrl': _text['updateUrl']!.text.trim(),
      'updateMessage': _text['updateMessage']!.text.trim(),
      'blockLinks': _blockLinks,
      'blockPhones': _blockPhones,
      'luckyEnabled': _luckyEnabled,
    };
    for (final k in _ints) {
      final n = int.tryParse(_text[k]!.text.trim());
      if (n == null) {
        toast(context, 'Sayı alanları boş bırakılamaz.', error: true);
        return;
      }
      body[k] = n;
    }
    final rtp = double.tryParse(_text['luckyRtpPct']!.text.trim().replaceAll(',', '.'));
    final share = double.tryParse(_text['luckyReceiverPct']!.text.trim().replaceAll(',', '.'));
    if (rtp == null || share == null) {
      toast(context, 'Şanslı hediye yüzdeleri sayı olmalı.', error: true);
      return;
    }
    if (rtp + share > 95) {
      toast(context, 'Geri dönüş + alıcı payı en fazla %95 olabilir.', error: true);
      return;
    }
    body['luckyRtpBps'] = (rtp * 100).round();
    body['luckyReceiverBps'] = (share * 100).round();
    final min = body['minAppVersion'] as String;
    if (min != '0.0.0' &&
        !await confirm(context, 'En düşük sürüm $min olacak. Bu sürümün altındaki uygulamalar "Güncelleme gerekli" ekranı görür ve kullanılamaz. Devam edilsin mi?',
            action: 'Kaydet', destructive: true)) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final r = await guard(context, () => Api.put('/api/admin/app-config', body));
    if (!mounted) return;
    setState(() => _saving = false);
    if (r != null) toast(context, 'Ayarlar kaydedildi.');
  }

  Widget _field(String key, String label, {String? hint, bool number = false, int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: TextField(
          controller: _text[key],
          keyboardType: number ? TextInputType.number : TextInputType.text,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Uygulama ayarları')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(message: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(Gap.l), children: [
                  const Text('Güncelleme', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text(
                    'En düşük sürümün altındaki uygulamalar kullanılamaz (0.0.0 = kapalı). Güncel sürüm daha yüksekse kullanıcılara bir kez "yeni sürüm var" denir.',
                    style: TextStyle(color: Pal.textDim, fontSize: 12.5, height: 1.35),
                  ),
                  const SizedBox(height: Gap.m),
                  _field('minAppVersion', 'En düşük sürüm', hint: '0.0.0'),
                  _field('latestAppVersion', 'Güncel sürüm', hint: 'Bu telefondaki: $kAppVersion'),
                  _field('updateUrl', 'İndirme bağlantısı (https)', hint: 'https://...'),
                  _field('updateMessage', 'Güncelleme mesajı', maxLines: 3),
                  const Divider(height: Gap.xl),
                  const Text('Otomatik moderasyon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Link ve site adreslerini engelle'),
                    subtitle: const Text('Oda sohbeti, özel mesaj, gönderi ve yorumlarda'),
                    value: _blockLinks,
                    onChanged: (v) => setState(() => _blockLinks = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Telefon numaralarını engelle'),
                    subtitle: const Text('Herkese açık alanlarda (özel mesaj hariç)'),
                    value: _blockPhones,
                    onChanged: (v) => setState(() => _blockPhones = v),
                  ),
                  const SizedBox(height: Gap.s),
                  _field('strikeLimit', 'Kaç ihlalde kısıtlansın (1-20)', number: true),
                  _field('strikeWindowMin', 'Kaç dakika içinde (1-1440)', number: true),
                  _field('muteMinutes', 'İlk kısıt süresi, dakika (1-1440)', number: true),
                  _field('maxMuteMinutes', 'En uzun kısıt, dakika (1-10080)', number: true),
                  const Divider(height: Gap.xl),
                  const Text('Şanslı hediye', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text(
                    'Gönderen her adet için x2–x500 kazanma şansı yakalar. Geri dönüş oranı uzun vadede gönderilen Coin\'in ne kadarının '
                    'çekilişle geri döndüğüdür; alıcı payı hediye değerinin alıcıya Elmas olarak geçen kısmıdır. İkisinin toplamı en fazla %95.',
                    style: TextStyle(color: Pal.textDim, fontSize: 12.5, height: 1.35),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Şanslı hediyeler açık'),
                    value: _luckyEnabled,
                    onChanged: (v) => setState(() => _luckyEnabled = v),
                  ),
                  _field('luckyRtpPct', 'Geri dönüş oranı % (0-90)', number: true),
                  _field('luckyReceiverPct', 'Alıcı payı % (0-50)', number: true),
                  _field('luckyMaxWin', 'Tek gönderimde en fazla kazanç (Coin)', number: true),
                  _field('luckyAnnounceMultiplier', 'Tüm uygulamaya duyurulacak en düşük çarpan (10-500)', number: true),
                  const SizedBox(height: Gap.s),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                    label: const Text('Kaydet'),
                  ),
                ]),
    );
  }
}

// ------------------------------------------------------------------ Kullanıcının cihazları
class UserDevicesScreen extends StatelessWidget {
  final Map<String, dynamic> user;
  const UserDevicesScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Cihazlar · ${user['displayName'] ?? ''}')),
      body: AsyncBody<Map<String, dynamic>>(
        load: () => Api.get('/api/admin/users/${user['id']}/devices'),
        builder: (context, data, reload) {
          final sessions = listOf(data['sessions']);
          final linked = listOf(data['linkedAccounts']);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(Gap.m), children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: data['online'] == true ? Pal.green : Pal.textDim, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(data['online'] == true ? 'Şu an çevrimiçi' : 'Şu an çevrimdışı', style: const TextStyle(color: Pal.textDim)),
              ]),
              const SizedBox(height: Gap.m),
              const Text('Oturumlar', style: TextStyle(fontWeight: FontWeight.w800)),
              if (sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Gap.m),
                  child: Text('Kayıtlı cihaz oturumu yok (eski uygulama sürümüyle giriş yapmış olabilir).', style: TextStyle(color: Pal.textDim)),
                ),
              for (final s in sessions)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.phone_android, color: s['revokedAt'] == null ? Pal.cyan : Pal.textDim),
                    title: Text('${s['deviceName'] ?? 'Bilinmeyen cihaz'}${s['emulator'] == true ? ' · EMÜLATÖR' : ''}'),
                    subtitle: Text(
                      'v${s['appVersion'] ?? '?'} · IP ${s['ip'] ?? '-'}\n'
                      'Açılış ${_dt(s['createdAt'])} · son ${_dt(s['lastUsedAt'])}'
                      '${s['revokedAt'] == null ? '' : '\nKapatıldı ${_dt(s['revokedAt'])} (${s['revokeReason'] ?? ''})'}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              const SizedBox(height: Gap.m),
              Text('Aynı cihazı kullanan diğer hesaplar (${linked.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Çoklu hesap ve hile tespiti içindir; aynı telefonu paylaşan aile üyeleri de burada görünebilir.', style: TextStyle(color: Pal.textDim, fontSize: 12)),
              for (final u in linked)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline),
                  title: Text('${u['displayName']} (@${u['username']})'),
                  subtitle: Text('ID ${u['publicId'] ?? '-'} · ${u['accountStatus']} · son ${_dt(u['lastUsedAt'])}'),
                ),
            ]),
          );
        },
      ),
    );
  }
}
