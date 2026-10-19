import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/fig.dart';
import 'family_screen.dart';
import 'user_screens.dart';

/// Zirve Listesi (Figma): Yayıncı · Destekçi · Yükleme · Ajans · Aile · CP × Günlük / Haftalık / Aylık.
/// Her sekmenin kendi rengi; ilk 3 kürsüde (taçlı çerçeve + sancak), devamı liste; altta kendi sıran.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _Tab {
  final String type;
  final String label;
  final Color tint;
  final Color row;
  final Color footer;
  const _Tab(this.type, this.label, this.tint, this.row, this.footer);
}

const _tabs = [
  _Tab('receivers', 'Yayıncı', Color(0xCC6A0F8E), Color(0xB38E1FB0), Color(0xFFC42BD8)),
  _Tab('senders', 'Destekçi', Color(0xCC0B3C8F), Color(0xB31352B8), Color(0xFF1E66D6)),
  _Tab('topups', 'Yükleme', Color(0xCC8E0B0B), Color(0xB3B71C1C), Color(0xFFD32626)),
  _Tab('agencies', 'Ajans', Color(0xCC0D6B1A), Color(0xB3179A2B), Color(0xFF1FB33A)),
  _Tab('families', 'Aile', Color(0xE6141414), Color(0xCC2A2A2A), Color(0xFF2E2E2E)),
  _Tab('cp', 'CP', Color(0xCC8E1458), Color(0xB3A8226E), Color(0xFFC2307F)),
];

const _periods = [('daily', 'Günlük'), ('weekly', 'Haftalık'), ('monthly', 'Aylık')];

/// Figma'daki gibi tutar gizlenir: ilk ve son rakam görünür (7*****5).
String maskAmount(dynamic v) {
  final s = '${v ?? 0}'.replaceAll(RegExp(r'[^0-9]'), '');
  if (s.length <= 2) return s.isEmpty ? '0' : s;
  return '${s[0]}${'*' * (s.length - 2)}${s[s.length - 1]}';
}

String _compact(dynamic v) {
  final n = num.tryParse('$v') ?? 0;
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '${n.toInt()}';
}

String _short(String s, int n) => s.characters.length <= n ? s : '${s.characters.take(n)}...';

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  int _tab = 0;
  String _period = 'weekly';

  _Tab get _t => _tabs[_tab];

  void _openUser(Map<String, dynamic>? u) {
    final id = u?['id']?.toString();
    if (id == null || u?['isHidden'] == true) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)));
  }

  void _openFamily(Map<String, dynamic>? f) {
    final id = f?['id']?.toString();
    if (id == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => FamilyPage(familyId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Theme(
      data: Theme.of(context),
      child: Scaffold(
        backgroundColor: Pal.bg,
        appBar: AppBar(
          backgroundColor: Pal.bg,
          foregroundColor: Pal.text,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: const Text('Zirve Listesi', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        ),
        body: Stack(children: [
          const Positioned.fill(child: Fig('rank_bg', fit: BoxFit.cover)),
          Positioned.fill(child: AnimatedContainer(duration: const Duration(milliseconds: 250), color: _t.tint)),
          Column(children: [
            // Sekmeler
            Container(
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _tab = i),
                      child: Container(
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: _tab == i ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_tabs[i].label, style: TextStyle(color: _tab == i ? Colors.black : Colors.white, fontWeight: _tab == i ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            Stack(clipBehavior: Clip.none, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final (key, label) in _periods)
                  GestureDetector(
                    onTap: () => setState(() => _period = key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Column(children: [
                        Text(label, style: TextStyle(color: _period == key ? Colors.white : Colors.white70, fontWeight: _period == key ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
                        const SizedBox(height: 4),
                        Container(width: 16, height: 2, color: _period == key ? Colors.white : Colors.transparent),
                      ]),
                    ),
                  ),
              ]),
            ]),
            Expanded(
              child: AsyncBody<Map<String, dynamic>>(
                version: '${_t.type}|$_period',
                load: () => Api.get('/api/leaderboards', query: {'type': _t.type, 'period': _period}),
                builder: (context, d, reload) {
                  final entries = listOf(d['entries']);
                  final top = entries.take(3).toList();
                  final rest = entries.skip(3).toList();
                  return Stack(children: [
                    RefreshIndicator(
                      onRefresh: reload,
                      child: ListView(padding: EdgeInsets.only(bottom: 90 + mq.padding.bottom), children: [
                        if (entries.isEmpty)
                          const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: Text('Bu dönemde henüz sıralama yok.', style: TextStyle(color: Colors.white70)))),
                        if (top.isNotEmpty) _t.type == 'cp' ? _cpPodium(top) : _podium(top),
                        for (final e in rest) _t.type == 'cp' ? _cpRow(e) : _row(e),
                      ]),
                    ),
                    Positioned(
                      right: 0,
                      top: 4,
                      child: GestureDetector(
                        onTap: () => _rules(context),
                        child: SizedBox(
                          width: 92,
                          height: 36,
                          child: Stack(alignment: Alignment.center, children: [
                            const Positioned.fill(child: Fig('btn_rules', fit: BoxFit.fill)),
                            const Padding(padding: EdgeInsets.only(left: 12), child: Text('Kurallar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
                          ]),
                        ),
                      ),
                    ),
                    if (mapOf(d['me']) != null && ['receivers', 'senders', 'topups'].contains(_t.type))
                      Positioned(left: 0, right: 0, bottom: 0, child: _meRow(mapOf(d['me'])!, mq.padding.bottom)),
                  ]);
                },
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ---------- Kürsü (ilk 3) ----------
  ({String name, String? avatar, dynamic total, Map<String, dynamic>? user, Map<String, dynamic>? family}) _who(Map<String, dynamic> e) {
    switch (_t.type) {
      case 'families':
        final f = mapOf(e['family']);
        return (name: '${f?['name'] ?? ''}', avatar: f?['logoUrl'] as String?, total: e['total'], user: null, family: f);
      case 'agencies':
        final a = mapOf(e['agency']);
        return (name: '${a?['name'] ?? ''}', avatar: a?['logoUrl'] as String?, total: e['total'], user: null, family: null);
      default:
        final u = mapOf(e['user']);
        return (name: '${u?['displayName'] ?? ''}', avatar: u?['avatarUrl'] as String?, total: e['total'], user: u, family: null);
    }
  }

  Widget _photo(String? url, double size, {Map<String, dynamic>? user}) {
    if (user != null) return UserAvatar(user: user, radius: size / 2);
    final u = Api.absoluteUrl(url);
    final px = NetImage.px(size, MediaQuery.devicePixelRatioOf(context));
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Colors.white24,
      backgroundImage: u == null ? null : NetImage(u, targetW: px, targetH: px),
      onBackgroundImageError: u == null ? null : (_, __) {},
      child: u == null ? Icon(_t.type == 'families' ? Icons.groups : Icons.business, color: Colors.white) : null,
    );
  }

  Widget _valueLine(dynamic total, double fs) {
    if (_t.type == 'families' || _t.type == 'agencies') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(9), border: Border.all(color: const Color(0xFFF2C14E))),
        child: Text('${_compact(total)}${_t.type == 'families' ? ' 🔥' : ''}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: fs)),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Fig('icon_diamond', width: fs, height: fs * 0.83),
      const SizedBox(width: 2),
      Text(maskAmount(total), style: TextStyle(color: const Color(0xFFFFD54F), fontWeight: FontWeight.w700, fontSize: fs)),
    ]);
  }

  Widget _podiumSlot(Map<String, dynamic>? e, int rank, double w) {
    if (e == null) return SizedBox(width: w);
    final who = _who(e);
    final first = rank == 1;
    final frame = first ? 'fam_frame_gold' : rank == 2 ? 'frame_rank2' : 'frame_rank3';
    final banner = first ? 'banner_red' : rank == 2 ? 'banner_blue' : 'banner_purple';
    final fw = first ? w * 1.05 : w * 0.98;
    return GestureDetector(
      onTap: () => who.family != null ? _openFamily(who.family) : _openUser(who.user),
      child: SizedBox(
        width: w,
        height: first ? w * 1.9 : w * 1.75,
        child: Stack(alignment: Alignment.topCenter, clipBehavior: Clip.none, children: [
          Positioned(top: fw * 0.62, child: Fig(banner, width: w * 0.86, height: first ? w * 1.25 : w * 1.1, fit: BoxFit.fill)),
          Positioned(
            top: 0,
            child: SizedBox(
              width: fw,
              height: fw,
              child: Stack(alignment: Alignment.center, children: [
                Padding(padding: EdgeInsets.only(bottom: fw * 0.04), child: _photo(who.avatar, fw * 0.5, user: who.user)),
                Positioned.fill(child: IgnorePointer(child: Fig(frame))),
              ]),
            ),
          ),
          Positioned(
            top: fw * 0.98,
            left: 4,
            right: 4,
            child: Column(children: [
              Text(_short(who.name, 10), maxLines: 1, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: first ? 13 : 12)),
              const SizedBox(height: 2),
              _valueLine(who.total, first ? 11 : 10),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _podium(List<Map<String, dynamic>> top) {
    final w = (MediaQuery.sizeOf(context).width - 40) / 3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 22, 10, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Padding(padding: EdgeInsets.only(top: w * 0.32), child: _podiumSlot(top.length > 1 ? top[1] : null, 2, w)),
        _podiumSlot(top[0], 1, w * 1.08),
        Padding(padding: EdgeInsets.only(top: w * 0.32), child: _podiumSlot(top.length > 2 ? top[2] : null, 3, w)),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> e) {
    final who = _who(e);
    return GestureDetector(
      onTap: () => who.family != null ? _openFamily(who.family) : _openUser(who.user),
      child: Container(
        height: 66,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: _t.row, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
        child: Row(children: [
          SizedBox(width: 28, child: Text('${e['rank']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
          Container(padding: const EdgeInsets.all(1.5), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: _photo(who.avatar, 46, user: who.user)),
          const SizedBox(width: 10),
          Expanded(child: Text(who.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
          _valueLine(who.total, 12),
        ]),
      ),
    );
  }

  Widget _meRow(Map<String, dynamic> me, double bottomPad) {
    final u = Session.me.value;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPad),
      decoration: BoxDecoration(color: _t.footer, borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), border: Border.all(color: Colors.white38)),
      child: Row(children: [
        SizedBox(width: 40, child: Text(me['rank'] == null ? '50+' : '${me['rank']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16))),
        UserAvatar(user: u, radius: 22),
        const SizedBox(width: 10),
        Expanded(child: Text('${u?['displayName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
        _valueLine(me['total'], 13),
      ]),
    );
  }

  // ---------- CP ----------
  Widget _cpPair(Map<String, dynamic> e, {required bool big}) {
    final a = mapOf(e['user']);
    final b = mapOf(e['partner']);
    final s = big ? 76.0 : 46.0;
    Widget side(Map<String, dynamic>? u, int rank) => GestureDetector(
          onTap: () => _openUser(u),
          child: big
              ? SizedBox(
                  width: s * 1.75,
                  height: s * 1.75,
                  child: Stack(alignment: Alignment.center, children: [
                    UserAvatar(user: u, radius: s / 2),
                    Positioned.fill(child: IgnorePointer(child: Fig(rank == 1 ? 'fam_frame_gold' : rank == 2 ? 'frame_rank2' : 'frame_rank3'))),
                  ]),
                )
              : Container(padding: const EdgeInsets.all(1.5), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: UserAvatar(user: u, radius: s / 2)),
        );
    if (!big) {
      return SizedBox(
        width: s * 1.75,
        height: s,
        child: Stack(alignment: Alignment.center, children: [
          Positioned(left: 0, child: side(a, 9)),
          Positioned(right: 0, child: side(b, 9)),
          const Fig('icon_heart', width: 20, height: 17),
        ]),
      );
    }
    final rank = (e['rank'] as num).toInt();
    return SizedBox(
      height: s * 1.75,
      child: Stack(alignment: Alignment.center, children: [
        Positioned(
          left: s * 0.7,
          right: s * 0.7,
          top: s * 0.55,
          child: Container(
            height: s * 0.85,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: rank == 1 ? const [Color(0xFFE5326F), Color(0xFFB0164E)] : rank == 2 ? const [Color(0xFF3B47D6), Color(0xFF2533A8)] : const [Color(0xFF9B2CC9), Color(0xFF6E1C9C)]),
              border: const Border.symmetric(horizontal: BorderSide(color: Color(0xFFF2C14E), width: 1.5)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_compact(e['total']), style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w900, fontSize: 22)),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                Text(_short('${a?['displayName'] ?? ''}', 7), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                Text(_short('${b?['displayName'] ?? ''}', 7), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
              ]),
            ]),
          ),
        ),
        Positioned(top: s * 0.12, child: const Fig('hearts_pair', width: 56, height: 32)),
        Positioned(left: 0, child: side(a, rank)),
        Positioned(right: 0, child: side(b, rank)),
      ]),
    );
  }

  Widget _cpPodium(List<Map<String, dynamic>> top) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 40, 14, 10),
        child: Column(children: [for (final e in top) Padding(padding: const EdgeInsets.only(bottom: 4), child: _cpPair(e, big: true))]),
      );

  Widget _cpRow(Map<String, dynamic> e) {
    final a = mapOf(e['user']);
    final b = mapOf(e['partner']);
    return Container(
      height: 74,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: _t.row, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
      child: Row(children: [
        SizedBox(width: 26, child: Text('${e['rank']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
        _cpPair(e, big: false),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a?['displayName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            Text('${b?['displayName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ),
        const Fig('icon_heart', width: 14, height: 12),
        const SizedBox(width: 3),
        Text(maskAmount(e['total']), style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }

  void _rules(BuildContext context) {
    const text = {
      'receivers': 'Yayıncı sıralaması, seçilen dönemde alınan hediyelerin Elmas değerine göre hesaplanır. Kendine gönderilen hediyeler sayılmaz.',
      'senders': 'Destekçi sıralaması, seçilen dönemde gönderilen hediyelerin Coin değerine göre hesaplanır. Kendine gönderilen hediyeler sayılmaz.',
      'topups': 'Yükleme sıralaması, seçilen dönemde bayiden yapılan Coin yüklemelerine göre hesaplanır.',
      'agencies': 'Ajans sıralaması, ajansa bağlı yayıncıların seçilen dönemde aldığı hediyelerin toplamına göre hesaplanır.',
      'families': 'Aile sıralaması, aile üyelerinin seçilen dönemde aldığı hediyelerin toplamına göre hesaplanır.',
      'cp': 'CP sıralaması, onaylı CP çiftlerinin toplam yakınlık puanına göre hesaplanır (dönemden bağımsız).',
    };
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${_t.label} sıralaması'),
        content: Text(
          '${text[_t.type]}\n\nGünlük sıralama her gün 00:00\'da, haftalık her Pazartesi 00:00\'da, aylık her ayın 1\'inde (İstanbul saati) yenilenir. Tutarlar gizlilik için kısmen gizlenir.',
          style: const TextStyle(color: Pal.textDim, height: 1.45),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
      ),
    );
  }
}
