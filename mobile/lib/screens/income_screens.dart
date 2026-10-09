import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import 'agency_screen.dart';
import 'misc_screens.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _dm(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return '-';
  return '${_two(d.day)} - ${_two(d.hour)}:${_two(d.minute)}';
}

String _span(num seconds) {
  final s = seconds.toInt();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  if (h > 0) return m > 0 ? '$h Sa $m Dk' : '$h Sa';
  if (m > 0) return '$m Dk';
  return '$s Sn';
}

/// Gelir Merkezi: mevcut elmas, son kazançlar, Elmas Bozdurma ve Para Çekme.
class IncomeCenterScreen extends StatefulWidget {
  const IncomeCenterScreen({super.key});

  @override
  State<IncomeCenterScreen> createState() => _IncomeCenterScreenState();
}

class _IncomeCenterScreenState extends State<IncomeCenterScreen> {
  int _version = 0;

  Future<Map<String, dynamic>> _load() async {
    final me = mapOf((await Api.get('/api/me'))['user']) ?? {};
    Session.me.value = me;
    final w = await Api.get('/api/me/wallet', query: {'limit': '60'});
    final recent = listOf(w['transactions']).where((t) => t['type'] == 'gift_received').take(8).toList();
    return {'me': me, 'recent': recent};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gelir Merkezi'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00A8FF), shape: const StadiumBorder()),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BroadcastSummaryScreen())),
              child: const Text('Canlı Kayıt'),
            ),
          ),
        ],
      ),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: _load,
        builder: (context, data, reload) {
          final me = mapOf(data['me']) ?? {};
          final recent = listOf(data['recent']);
          final diamonds = (me['diamonds'] ?? 0).toString();
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: const LinearGradient(colors: [Color(0xFF0B5FFF), Color(0xFF22D3EE)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Mevcut Elmas', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.diamond, color: Colors.white, size: 38),
                    const SizedBox(width: 10),
                    Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(fmtNumber(diamonds), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)))),
                  ]),
                  const SizedBox(height: 6),
                  const Text('Aldığın her hediyenin değerinde elmas kazanırsın. 5 Elmas = 1 Coin.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: _bigBtn('Elmas Bozdurma', const [Color(0xFF00A8FF), Color(0xFF7FE0FF)], () async {
                    await WalletScreen.exchange(context, diamonds, () async => setState(() => _version++));
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(child: _bigBtn('Para Çekme', const [Color(0xFF05C150), Color(0xFF22E85F)], () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WithdrawScreen())))),
              ]),
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(child: Text('Son kazançlar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())), child: const Text('Tüm hareketler')),
              ]),
              if (recent.isEmpty)
                const Padding(padding: EdgeInsets.all(12), child: Text('Henüz hediye almadın.', style: TextStyle(color: Pal.textDim)))
              else
                for (final t in recent)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(backgroundColor: Color(0x3322D3EE), child: Icon(Icons.card_giftcard, color: Pal.cyan)),
                    title: Text((t['description'] ?? 'Hediye').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_dm(t['createdAt']), style: const TextStyle(fontSize: 12)),
                    trailing: Text('+${fmtNumber(t['diamondAmount'])} 💎', style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.w800)),
                  ),
            ]),
          );
        },
      ),
    );
  }

  Widget _bigBtn(String label, List<Color> colors, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), gradient: LinearGradient(colors: colors)),
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      );
}

/// Yayın Özeti: aylık (ay seçilebilir) ve günlük kazanç / yayın süresi.
class BroadcastSummaryScreen extends StatefulWidget {
  const BroadcastSummaryScreen({super.key});

  @override
  State<BroadcastSummaryScreen> createState() => _BroadcastSummaryScreenState();
}

class _BroadcastSummaryScreenState extends State<BroadcastSummaryScreen> {
  String? _month; // YYYY-MM

  List<String> get _months {
    final now = DateTime.now();
    return [for (var i = 0; i < 12; i++) () {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${_two(d.month)}';
    }()];
  }

  Widget _block(String title, String right, Map<String, dynamic> b, {Widget? trailing}) {
    Widget line(String l, dynamic v, {bool dia = true, double size = 14, FontWeight w = FontWeight.w500}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [Expanded(child: Text(l, style: TextStyle(fontSize: size, fontWeight: w))), Text('${fmtNumber(v)}${dia ? ' 💎' : ''}', style: TextStyle(fontSize: size, fontWeight: w))]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Pal.outline)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (trailing != null) trailing else Text(right, style: const TextStyle(color: Pal.textDim, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        Text('Toplam Elmas: ${fmtNumber(b['totalDiamonds'])} 💎', style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Canlı Yayın Gelirleri', style: TextStyle(fontWeight: FontWeight.w700)),
        line('Video yayın', b['videoDiamonds']),
        line('Sesli yayın', b['audioDiamonds']),
        const Divider(height: 22),
        line('Geçerli Aktif Gün', '${b['activeDays']} Gün', dia: false, size: 15, w: FontWeight.w800),
        line('Geçerli Aktif Süre', '${b['activeMinutes']} Dakika', dia: false, size: 15, w: FontWeight.w800),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yayın Özeti')),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_month),
        load: () async => await Api.get('/api/me/earnings/summary', query: {if (_month != null) 'month': _month!}),
        builder: (context, d, reload) {
          final month = (d['month'] ?? '').toString();
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _block(
                'Aylık',
                month,
                mapOf(d['monthly']) ?? {},
                trailing: DropdownButton<String>(
                  value: _months.contains(month) ? month : null,
                  underline: const SizedBox.shrink(),
                  items: [for (final m in _months) DropdownMenuItem(value: m, child: Text('${m.substring(5)}/${m.substring(0, 4)}'))],
                  onChanged: (v) => setState(() => _month = v),
                ),
              ),
              _block('Günlük', (d['today'] ?? '').toString().split('-').reversed.join('.'), mapOf(d['daily']) ?? {}),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BroadcastHistoryScreen())),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Pal.outline)),
                  child: const Row(children: [Expanded(child: Text('Canlı yayın geçmişi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))), Icon(Icons.chevron_right)]),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

/// Canlı yayın geçmişi: Video ve Sesli sekmeleri, özet kutuları ve sayfalı tablo.
class BroadcastHistoryScreen extends StatefulWidget {
  const BroadcastHistoryScreen({super.key});

  @override
  State<BroadcastHistoryScreen> createState() => _BroadcastHistoryScreenState();
}

class _BroadcastHistoryScreenState extends State<BroadcastHistoryScreen> {
  String _type = 'video';
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    Widget tab(String t, String label) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() {
              _type = t;
              _offset = 0;
            }),
            child: Container(
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: _type == t ? const Color(0xFF0B5FFF) : Colors.white12),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Canlı Yayın Geçmişi')),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey('$_type-$_offset'),
        load: () async => await Api.get('/api/me/earnings/history', query: {'type': _type, 'offset': '$_offset'}),
        builder: (context, d, reload) {
          final totals = mapOf(d['totals']) ?? {};
          final sessions = listOf(d['sessions']);
          Widget stat(String l, String v) => Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: const Color(0x3322D3EE), borderRadius: BorderRadius.circular(6)),
                  child: Column(children: [Text(l, style: const TextStyle(fontSize: 11, color: Pal.textDim)), const SizedBox(height: 2), FittedBox(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w800)))]),
                ),
              );
          return ListView(padding: const EdgeInsets.all(14), children: [
            Row(children: [tab('video', 'Video Yayın'), const SizedBox(width: 8), tab('audio', 'Sesli Yayın')]),
            const SizedBox(height: 14),
            Text(_type == 'video' ? 'VİDEO CANLI YAYIN' : 'SESLİ CANLI YAYIN', style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Row(children: [
              stat('Aktif Gün', '${totals['activeDays'] ?? 0}'),
              stat('Yayın Süresi', '${totals['minutes'] ?? 0} dk'),
              stat('Toplam Elmas', fmtNumber(totals['diamonds'])),
            ]),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(border: Border.all(color: Pal.outline), borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  decoration: const BoxDecoration(color: Color(0xFF0B5FFF), borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
                  child: const Row(children: [
                    Expanded(child: Text('Başlama', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                    Expanded(child: Text('Bitirme', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                    Expanded(child: Text('Süre', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                    Expanded(child: Text('Elmas', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  ]),
                ),
                if (sessions.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Kayıt yok.', style: TextStyle(color: Pal.textDim))),
                for (final s in sessions)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Pal.outline, width: 0.6))),
                    child: Row(children: [
                      Expanded(child: Text(_dm(s['startedAt']), style: const TextStyle(fontSize: 12))),
                      Expanded(child: Text(s['endedAt'] == null ? 'Sürüyor' : _dm(s['endedAt']), style: const TextStyle(fontSize: 12))),
                      Expanded(child: Text(_span((s['seconds'] as num?) ?? 0), style: const TextStyle(fontSize: 12))),
                      Expanded(child: Text('${fmtNumber(s['diamonds'])} 💎', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12))),
                    ]),
                  ),
              ]),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(onPressed: _offset == 0 ? null : () => setState(() => _offset = (_offset - 10).clamp(0, 1 << 30)), icon: const Icon(Icons.chevron_left)),
              IconButton(onPressed: d['hasMore'] == true ? () => setState(() => _offset += 10) : null, icon: const Icon(Icons.chevron_right)),
            ]),
          ]);
        },
      ),
    );
  }
}

/// Para Çekme: yayıncı maaşı (tahmini) ve ödeme koşulları. Ödeme, kimlik doğrulaması sonrası yönetim/ajans tarafından yapılır.
class WithdrawScreen extends StatelessWidget {
  const WithdrawScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Para Çekme')),
      body: AsyncBody<Map<String, dynamic>>(
        load: () async => await Api.get('/api/broadcaster/me'),
        builder: (context, d, reload) {
          final b = mapOf(d['broadcaster']);
          if (b == null || b['status'] != 'approved') {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Para çekme yalnızca onaylı yayıncılar içindir. Yayıncı Merkezi\'nden başvurabilirsin.\n\nElmaslarını Gelir Merkezi\'ndeki "Elmas Bozdurma" ile coin\'e çevirebilirsin.', textAlign: TextAlign.center, style: TextStyle(color: Pal.textDim, height: 1.4))));
          }
          final p = mapOf(b['progress']) ?? {};
          final cur = (p['currency'] ?? 'USD').toString();
          final kyc = (b['kycStatus'] ?? 'none').toString();
          const kycText = {'none': 'Doğrulanmadı', 'pending': 'İnceleniyor', 'approved': 'Onaylı', 'rejected': 'Reddedildi'};
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: _card('Bu dönem tahmini maaş', fmtMoney(p['estimatedCents'] ?? 0, cur), const [Color(0xFF00A8FF), Color(0xFF7FE0FF)])),
              const SizedBox(width: 12),
              Expanded(child: _card('Toplam elmas', fmtNumber(b['totalDiamonds']), const [Color(0xFF7C4DFF), Color(0xFFB388FF)])),
            ]),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Pal.outline)),
              leading: Icon(Icons.verified_user_outlined, color: kyc == 'approved' ? Colors.greenAccent : Colors.amber),
              title: const Text('Kimlik doğrulama'),
              subtitle: Text(kycText[kyc] ?? kyc),
              trailing: kyc == 'none' || kyc == 'rejected'
                  ? TextButton(
                      onPressed: () async {
                        final r = await guard(context, () => Api.post('/api/me/kyc/request'));
                        if (r != null && context.mounted) {
                          toast(context, 'Başvurunuz alındı.');
                          await reload();
                        }
                      },
                      child: const Text('Başvur'))
                  : null,
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Pal.outline)),
              leading: const Icon(Icons.receipt_long, color: Pal.cyan),
              title: const Text('Maaş özetlerim'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HostStatementsScreen())),
            ),
            const SizedBox(height: 16),
            const Text('Maaşlar dönem kapanınca hesaplanır ve kimlik doğrulaman onaylıysa ödenir. Ödeme durumunu "Maaş özetlerim" sayfasından görebilirsin.', style: TextStyle(color: Pal.textDim, fontSize: 12, height: 1.4)),
          ]);
        },
      ),
    );
  }

  Widget _card(String label, String value, List<Color> colors) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(colors: colors)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))),
        ]),
      );
}
