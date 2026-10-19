import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/room_dock.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import '../widgets/fig.dart';
import '../widgets/image_pick.dart';
import '../widgets/level_badge.dart';
import 'user_screens.dart';

/// Aile (Figma): Demir → Elmas seviyeleri, aile sayfası, üyeler, istekler, bilgileri düzenle, istek ayarları,
/// seviye sayfaları, Coins ödülü ve kurallar.
const _ink = Color(0xFF1C1C1E);
const _dim = Color(0xFF9A9AA0);
const _blue = Color(0xFF0A9BFF);
const _green = Color(0xFF16C35A);
const _tierNames = ['Demir', 'Bronz', 'Gümüş', 'Altın', 'Elmas'];

int _tierOf(dynamic level) => ((level is num ? level.toInt() : int.tryParse('$level') ?? 1).clamp(1, 5));

/// Seviyeye özel arka plan (Figma "Özel Arkaplan"): Demir yeşil, Bronz mavi, Gümüş mor, Altın mor-mavi, Elmas siyah-altın.
const _tierGradients = <List<Color>>[
  [Color(0xFF0BB36A), Color(0xFF2EDB9B)],
  [Color(0xFF0A78F0), Color(0xFF14B7FF)],
  [Color(0xFF8E2DE2), Color(0xFFC86DD7)],
  [Color(0xFFB12BDB), Color(0xFF3A63F5)],
  [Color(0xFF111111), Color(0xFF3A3A3A)],
];

ThemeData _light() => ThemeData.light(useMaterial3: true).copyWith(colorScheme: const ColorScheme.light(primary: _blue));

PreferredSizeWidget _appBar(BuildContext context, String title, {List<Widget> actions = const []}) => AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 20, color: _ink)),
      actions: actions,
    );

/// Aile girişi: aile varsa aile sayfası, yoksa aile listesi (ara, başvur, kur).
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _light(),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: AsyncBody<Map<String, dynamic>>(
          version: _v,
          load: () => Api.get('/api/families/mine'),
          shell: (context, child) => Scaffold(backgroundColor: Colors.white, appBar: _appBar(context, 'Aile'), body: child),
          builder: (context, d, reload) {
            final f = mapOf(d['family']);
            if (f != null) return FamilyPage(familyId: f['id'].toString(), onLeft: () => setState(() => _v++));
            return _FamilyBrowser(onChanged: () => setState(() => _v++));
          },
        ),
      ),
    );
  }
}

/// Aile listesi (aile yokken).
class _FamilyBrowser extends StatefulWidget {
  final VoidCallback onChanged;
  const _FamilyBrowser({required this.onChanged});

  @override
  State<_FamilyBrowser> createState() => _FamilyBrowserState();
}

class _FamilyBrowserState extends State<_FamilyBrowser> {
  final _search = TextEditingController();
  int _v = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const FamilyEditPage()));
    if (ok == true) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _light(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _appBar(context, 'Aileler', actions: [
          IconButton(tooltip: 'Kurallar', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FamilyRulesPage())), icon: const Icon(Icons.help_outline)),
        ]),
        floatingActionButton: FloatingActionButton.extended(backgroundColor: _blue, foregroundColor: Colors.white, onPressed: _create, icon: const Icon(Icons.add), label: const Text('Aile kur')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => setState(() => _v++),
              style: const TextStyle(color: _ink),
              decoration: InputDecoration(
                hintText: 'Aile adı ya da ID ara',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFFF2F3F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: AsyncBody<List<Map<String, dynamic>>>(
              version: '$_v|${_search.text}',
              load: () async => listOf((await Api.get('/api/families', query: {'q': _search.text.trim()}))['families']),
              builder: (context, list, reload) => list.isEmpty
                  ? const Center(child: Text('Aile bulunamadı.', style: TextStyle(color: _dim)))
                  : RefreshIndicator(
                      onRefresh: reload,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 82, color: Color(0xFFEDEDED)),
                        itemBuilder: (_, i) {
                          final f = list[i];
                          return ListTile(
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => FamilyPage(familyId: f['id'].toString())));
                              widget.onChanged();
                            },
                            leading: FamilyLogo(family: f, size: 52),
                            title: Text('${f['name']}', style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                            subtitle: Text('${f['tier'] ?? ''} · ${f['memberCount']}/${f['capacity']} üye', style: const TextStyle(color: _dim, fontSize: 12)),
                            trailing: Fig('fam_tier_${_tierOf(f['level'])}', width: 36, height: 36),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Aile logosu (yuvarlak, seviye çerçevesiyle).
class FamilyLogo extends StatelessWidget {
  final Map<String, dynamic> family;
  final double size;
  final bool framed;
  const FamilyLogo({super.key, required this.family, this.size = 48, this.framed = false});

  @override
  Widget build(BuildContext context) {
    final url = Api.absoluteUrl(family['logoUrl'] as String?);
    final px = NetImage.px(size, MediaQuery.devicePixelRatioOf(context));
    final logo = CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFF7B2CFF),
      backgroundImage: url == null ? null : NetImage(url, targetW: px, targetH: px),
      onBackgroundImageError: url == null ? null : (_, __) {},
      child: url == null ? Icon(Icons.groups, color: Colors.white, size: size * 0.5) : null,
    );
    if (!framed) return logo;
    final tier = _tierOf(family['level']);
    return SizedBox(
      width: size * 1.77,
      height: size * 1.79,
      child: Stack(alignment: Alignment.center, children: [
        Padding(padding: EdgeInsets.only(bottom: size * 0.1), child: logo),
        Positioned.fill(child: IgnorePointer(child: Fig(tier >= 4 ? 'fam_frame_gold' : 'fam_frame_pink'))),
      ]),
    );
  }
}

/// Aile sayfası. [memberView]: başkan "Üye gözünden bak" ile üyelerin gördüğünü görür.
class FamilyPage extends StatefulWidget {
  final String familyId;
  final bool memberView;
  final VoidCallback? onLeft;
  const FamilyPage({super.key, required this.familyId, this.memberView = false, this.onLeft});

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  int _v = 0;

  String get _id => widget.familyId;

  void _reload() {
    if (mounted) setState(() => _v++);
  }

  Future<void> _push(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _reload();
  }

  Future<void> _settings(Map<String, dynamic> f) async {
    final role = f['myRole'];
    final a = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (key, label) in [
              ('edit', 'Bilgileri Düzenle'),
              ('requests', 'İstek Ayarları'),
              if (role == 'owner') ('disband', 'Aileyi Dağıt') else ('leave', 'Aileden Ayrıl'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    side: const BorderSide(color: Color(0xFFB9B9BE)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    foregroundColor: _ink,
                  ),
                  onPressed: () => Navigator.pop(c, key),
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19)),
                ),
              ),
          ]),
        ),
      ),
    );
    if (!mounted || a == null) return;
    if (a == 'edit') {
      await _push(FamilyEditPage(family: f));
    } else if (a == 'requests') {
      await _requestSettings(f);
    } else if (a == 'disband' || a == 'leave') {
      final disband = a == 'disband';
      final ok = await confirm(
        context,
        disband ? 'Aile dağıtılsın mı? Tüm üyeler ailesiz kalır.' : 'Aileden ayrılmak istiyor musunuz? Katkınız sıfırlanır.',
        action: disband ? 'Dağıt' : 'Ayrıl',
        destructive: true,
      );
      if (!ok || !mounted) return;
      final r = await guard(context, () => disband ? Api.delete('/api/families/$_id') : Api.post('/api/families/$_id/leave'));
      if (r != null && mounted) _left();
    }
  }

  void _left() {
    if (widget.onLeft != null) {
      widget.onLeft!();
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _requestSettings(Map<String, dynamic> f) async {
    var value = (f['joinMinLevel'] as num?)?.toInt() ?? 0;
    final ctl = FixedExtentScrollController(initialItem: value);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: 330,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(children: [
                const SizedBox(width: 60),
                const Expanded(child: Text('İstek Ayarları', textAlign: TextAlign.center, style: TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 21))),
                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Onayla', style: TextStyle(color: _green, fontWeight: FontWeight.w700, fontSize: 17))),
              ]),
            ),
            Expanded(
              child: ListWheelScrollView.useDelegate(
                controller: ctl,
                itemExtent: 40,
                diameterRatio: 1.4,
                perspective: 0.004,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) => value = i,
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: 201,
                  builder: (_, i) => Center(child: Text(i == 0 ? 'Sınır yok' : '$i', style: const TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.w600))),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 6, 28, 16),
              child: Text(
                'Bu kısımdan, aileye başvuracak kullanıcıların hangi zenginlik seviyesinde olacaklarının limitini belirleyebilirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFE6337A), fontSize: 13),
              ),
            ),
          ]),
        ),
      ),
    );
    // Sayfa kapanma animasyonu bitince bırakılır (tekerlek o sırada hâlâ ekranda).
    Future.delayed(const Duration(milliseconds: 600), ctl.dispose);
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.put('/api/families/$_id/settings', {'joinMinLevel': value}));
    if (r != null && mounted) {
      toast(context, value == 0 ? 'Başvuru seviye sınırı kaldırıldı.' : 'Başvuru için en az $value. zenginlik seviyesi gerekli.');
      _reload();
    }
  }

  Future<void> _join(Map<String, dynamic> f) async {
    final requested = f['requested'] == true;
    final r = await guard(context, () => requested ? Api.post('/api/families/$_id/join/cancel') : Api.post('/api/families/$_id/join'));
    if (r != null && mounted) {
      toast(context, requested ? 'Başvurun geri çekildi.' : 'Başvurun gönderildi. Aile yöneticisi onaylayınca aileye katılacaksın.');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _light(),
      child: AsyncBody<Map<String, dynamic>>(
        version: _v,
        load: () async => mapOf((await Api.get('/api/families/$_id'))['family']) ?? {},
        shell: (context, child) => Scaffold(backgroundColor: Colors.white, appBar: _appBar(context, 'Aile'), body: child),
        builder: (context, f, reload) {
          final role = widget.memberView ? 'member' : f['myRole']?.toString();
          final member = f['myRole'] != null;
          final admin = role == 'owner' || role == 'admin';
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: _appBar(context, '${f['name'] ?? ''}', actions: [
              if (admin) IconButton(tooltip: 'Ayarlar', onPressed: () => _settings(f), icon: const Icon(Icons.settings_outlined, size: 28)),
              IconButton(tooltip: 'Kurallar', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FamilyRulesPage())), icon: const Icon(Icons.help_outline, size: 28)),
            ]),
            body: Stack(children: [
              RefreshIndicator(
                onRefresh: reload,
                child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
                  _FamilyHeader(family: f, showProgress: member, onTier: () => _push(FamilyLevelsPage(initialTier: _tierOf(f['level']), family: f))),
                  const SizedBox(height: 40),
                  _section('Aile bildirimi'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15, 8, 15, 0),
                    child: Text(
                      (f['description'] ?? '').toString().isEmpty ? 'Henüz bir bildirim yok.' : '${f['description']}',
                      style: const TextStyle(color: _dim, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 18),
                  InkWell(
                    onTap: member ? () => _push(FamilyMembersPage(familyId: _id, myRole: role ?? 'member')) : null,
                    child: Row(children: [
                      Expanded(child: _section('Aile üyeleri')),
                      if (member) const Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.chevron_right, color: _dim, size: 30)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 66,
                    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                      for (final m in listOf(f['members']))
                        GestureDetector(
                          onTap: () {
                            final u = mapOf(m['user']);
                            if (u?['id'] != null && u?['isHidden'] != true) Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: u!['id'].toString())));
                          },
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _MemberAvatar(user: mapOf(m['user']), role: m['role']?.toString() ?? 'member')),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  _section('Aile odaları'),
                  const SizedBox(height: 14),
                  _rooms(listOf(f['rooms'])),
                  if (role == 'owner' && !widget.memberView)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () => _push(FamilyPage(familyId: _id, memberView: true)),
                          child: const Text('Üye gözünden bak', style: TextStyle(color: Color(0xFFE5121F), fontWeight: FontWeight.w700, fontSize: 16)),
                        ),
                      ),
                    ),
                ]),
              ),
              if (member)
                Positioned(
                  right: 14,
                  bottom: 24 + MediaQuery.paddingOf(context).bottom,
                  child: _RewardButton(onTap: () => _push(FamilyRewardsPage(familyId: _id, family: f))),
                ),
              if (!member)
                Positioned(
                  left: 40,
                  right: 40,
                  bottom: 20 + MediaQuery.paddingOf(context).bottom,
                  child: FigButton(
                    f['requested'] == true ? 'Başvuru gönderildi (geri çek)' : 'Aileye Katıl',
                    height: 50,
                    color: f['requested'] == true ? const Color(0xFF9AA4B2) : _blue,
                    onTap: () => _join(f),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Text(t, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 17)),
      );

  Widget _rooms(List<Map<String, dynamic>> rooms) {
    if (rooms.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(horizontal: 15), child: Text('Şu an açık aile odası yok.', style: TextStyle(color: _dim, fontSize: 13)));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rooms.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 193 / 230),
        itemBuilder: (_, i) {
          final r = rooms[i];
          final cover = Api.absoluteUrl(r['coverUrl'] as String?);
          final tag = (r['tag'] ?? (r['roomType'] == 'video' ? 'Parti' : 'Sohbet')).toString();
          final party = tag.toLowerCase().contains('part');
          return GestureDetector(
            onTap: () => RoomDock.open(RoomRequest(roomId: r['id'].toString(), name: (r['name'] ?? 'Oda').toString())),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(fit: StackFit.expand, children: [
                    cover == null ? Container(color: const Color(0xFFE9E9EE)) : NetImg(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFE9E9EE))),
                    Positioned(
                      left: 6,
                      bottom: 8,
                      child: Container(
                        width: 80,
                        height: 25,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: party ? const Color(0xFFFF2D9B) : const Color(0xFF29D3F5), borderRadius: BorderRadius.circular(13)),
                        child: Text(tag, maxLines: 1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white70, width: 0.8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.signal_cellular_alt, color: Colors.white, size: 10),
                          Text(' ${r['online'] ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text('${r['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ]),
          );
        },
      ),
    );
  }
}

/// Aile başlığı: seviye arka planı, çerçeveli logo, ad, ID, seviye çubuğu (üyelere) ve sağ altta seviye rozeti.
class _FamilyHeader extends StatelessWidget {
  final Map<String, dynamic> family;
  final bool showProgress;
  final VoidCallback onTier;
  const _FamilyHeader({required this.family, required this.showProgress, required this.onTier});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final k = w / 430;
    final tier = _tierOf(family['level']);
    final total = double.tryParse('${family['totalPoints']}') ?? 0;
    final next = double.tryParse('${family['nextPoints']}') ?? 1;
    final progress = (total / (next <= 0 ? 1 : next)).clamp(0.0, 1.0);
    return SizedBox(
      height: 287 * k + 34 * k,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 287 * k,
          child: tier == 5
              ? const Fig('fam_dark_bg', fit: BoxFit.cover)
              : DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _tierGradients[tier - 1]))),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 22 * k,
          child: Column(children: [
            FamilyLogo(family: family, size: 81 * k, framed: true),
            Text('${family['name'] ?? ''}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22 * k)),
            const SizedBox(height: 2),
            Text('ID:${family['publicId'] ?? '-'}', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 11 * k)),
            if (showProgress) ...[
              SizedBox(height: 12 * k),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 48 * k),
                child: Row(children: [
                  Fig('fam_tier_$tier', width: 20 * k, height: 20 * k),
                  SizedBox(width: 6 * k),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(value: progress, minHeight: 8 * k, backgroundColor: const Color(0xFFD9E4F5), valueColor: const AlwaysStoppedAnimation(Color(0xFFF7D21B))),
                    ),
                  ),
                  SizedBox(width: 6 * k),
                  Fig('fam_tier_${(tier + 1).clamp(1, 5)}', width: 20 * k, height: 20 * k),
                ]),
              ),
              SizedBox(height: 4 * k),
              Text('${fmtNumber(family['totalPoints'])} / ${fmtNumber(family['nextPoints'])} 🔥', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11 * k)),
            ],
          ]),
        ),
        Positioned(
          right: 10 * k,
          top: 250 * k,
          child: GestureDetector(onTap: onTier, child: Fig('fam_tier_$tier', width: 74 * k, height: 72 * k)),
        ),
      ]),
    );
  }
}

/// Üye fotoğrafı ve altında rol etiketi (yönetici mavi, üye bej).
class _MemberAvatar extends StatelessWidget {
  final Map<String, dynamic>? user;
  final String role;
  static const double size = 50;
  const _MemberAvatar({required this.user, required this.role});

  @override
  Widget build(BuildContext context) {
    final admin = role == 'owner' || role == 'admin';
    return SizedBox(
      width: size,
      height: size + 8,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Container(
          padding: const EdgeInsets.all(1.5),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDADADA)),
          child: UserAvatar(user: user, radius: size / 2 - 1.5),
        ),
        Positioned(bottom: 0, child: RoleTag(role: role, admin: admin)),
      ]),
    );
  }
}

/// Rol etiketi: yönetici / sahip mavi (dişli), üye bej.
class RoleTag extends StatelessWidget {
  final String role;
  final bool admin;
  const RoleTag({super.key, required this.role, required this.admin});

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 14,
        decoration: BoxDecoration(color: admin ? const Color(0xFF4C9CFF) : const Color(0xFFE3CC9A), borderRadius: BorderRadius.circular(7)),
        child: Icon(admin ? Icons.manage_accounts : Icons.person, size: 11, color: Colors.white),
      );
}

/// Sağ altta sandık düğmesi ve "Coins ödüllerini görmek için tıklayın" balonu.
class _RewardButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RewardButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 210,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFFF5BAA), borderRadius: BorderRadius.circular(10)),
          child: const Text('Coins ödüllerini görmek için tıklayın', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14)),
        ),
        const Padding(padding: EdgeInsets.only(right: 22), child: Icon(Icons.arrow_drop_down, color: Color(0xFFFF5BAA), size: 22)),
        Container(
          width: 60,
          height: 60,
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF9C2DD9)),
          child: const Fig('fam_chest'),
        ),
      ]),
    );
  }
}

/// Aile üyeleri: "Yeni istek" (yöneticiler), rol, zenginlik seviyesi ve bu haftaki katkı.
class FamilyMembersPage extends StatefulWidget {
  final String familyId;
  final String myRole;
  const FamilyMembersPage({super.key, required this.familyId, required this.myRole});

  @override
  State<FamilyMembersPage> createState() => _FamilyMembersPageState();
}

class _FamilyMembersPageState extends State<FamilyMembersPage> {
  int _v = 0;
  bool get _admin => widget.myRole == 'owner' || widget.myRole == 'admin';

  Future<void> _act(String msg, Future<Map<String, dynamic>> Function() call) async {
    if (!await confirm(context, msg) || !mounted) return;
    final r = await guard(context, call);
    if (r != null && mounted) setState(() => _v++);
  }

  void _menu(Map<String, dynamic> m) {
    final id = m['userId'].toString();
    final role = (m['role'] ?? 'member').toString();
    final me = widget.myRole;
    final canKick = (me == 'owner' && role != 'owner') || (me == 'admin' && role == 'member');
    final f = widget.familyId;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.person_outline, color: _ink), title: const Text('Profili gör', style: TextStyle(color: _ink)), onTap: () {
            Navigator.pop(c);
            if (mapOf(m['user'])?['isHidden'] == true) return;
            Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)));
          }),
          if (me == 'owner' && role == 'member')
            ListTile(leading: const Icon(Icons.manage_accounts, color: _blue), title: const Text('Yönetici yap', style: TextStyle(color: _ink)), onTap: () {
              Navigator.pop(c);
              _act('Bu üye yönetici yapılsın mı?', () => Api.post('/api/families/$f/members/$id/role', {'role': 'admin'}));
            }),
          if (me == 'owner' && role == 'admin')
            ListTile(leading: const Icon(Icons.person, color: _ink), title: const Text('Yöneticiliği al', style: TextStyle(color: _ink)), onTap: () {
              Navigator.pop(c);
              _act('Yöneticilik alınsın mı?', () => Api.post('/api/families/$f/members/$id/role', {'role': 'member'}));
            }),
          if (me == 'owner' && role != 'owner')
            ListTile(leading: const Icon(Icons.workspace_premium, color: Colors.orange), title: const Text('Başkanlığı devret', style: TextStyle(color: _ink)), onTap: () {
              Navigator.pop(c);
              _act('Aile başkanlığı bu kişiye devredilsin mi? Siz yönetici olarak kalırsınız.', () => Api.post('/api/families/$f/transfer', {'userId': id}));
            }),
          if (canKick)
            ListTile(leading: const Icon(Icons.person_remove, color: Colors.red), title: const Text('Aileden çıkar', style: TextStyle(color: Colors.red)), onTap: () {
              Navigator.pop(c);
              _act('Bu üye aileden çıkarılsın mı?', () => Api.post('/api/families/$f/members/$id/kick'));
            }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _light(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _appBar(context, 'Aile üyeleri'),
        body: AsyncBody<Map<String, dynamic>>(
          version: _v,
          load: () async {
            final r = await Future.wait([
              Api.get('/api/families/${widget.familyId}/members'),
              if (_admin) Api.get('/api/families/${widget.familyId}/requests'),
            ]);
            return {'members': r[0]['members'], 'requests': _admin ? r[1]['requests'] : const []};
          },
          builder: (context, d, reload) {
            final members = listOf(d['members']);
            final pending = listOf(d['requests']).length;
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(children: [
                const Divider(height: 1, color: Color(0xFFEDEDED)),
                if (_admin) ...[
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => FamilyRequestsPage(familyId: widget.familyId)));
                      if (mounted) setState(() => _v++);
                    },
                    leading: Stack(clipBehavior: Clip.none, children: [
                      const CircleAvatar(radius: 31, backgroundColor: _blue, child: Icon(Icons.people, color: Colors.white, size: 32)),
                      if (pending > 0) Positioned(right: 0, bottom: 2, child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))),
                    ]),
                    title: Text(pending > 0 ? 'Yeni istek ($pending)' : 'Yeni istek', style: const TextStyle(color: _blue, fontSize: 22, fontWeight: FontWeight.w500)),
                  ),
                  const Divider(height: 1, color: Color(0xFFEDEDED)),
                ],
                for (final m in members) ...[
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                    onTap: () {
                      if (_admin || m['userId'] == Session.id) {
                        _menu(m);
                      } else if (mapOf(m['user'])?['isHidden'] != true) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: m['userId'].toString())));
                      }
                    },
                    leading: UserAvatar(user: mapOf(m['user']), radius: 31),
                    title: Text('${mapOf(m['user'])?['displayName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF5B6475), fontSize: 20, fontWeight: FontWeight.w500)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        RoleTag(role: '${m['role']}', admin: m['role'] == 'owner' || m['role'] == 'admin'),
                        const SizedBox(width: 4),
                        LevelPill(level: mapOf(m['user'])?['coinLevel'] ?? 1, send: true, height: 16),
                      ]),
                    ),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('Bu haftaki katkısı', style: TextStyle(color: Color(0xFF5B6475), fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('${_compact(m['weekPoints'])} 🔥', style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 14)),
                    ]),
                  ),
                  const Divider(height: 1, color: Color(0xFFEDEDED)),
                ],
              ]),
            );
          },
        ),
      ),
    );
  }
}

String _compact(dynamic v) {
  final n = num.tryParse('$v') ?? 0;
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
  return '${n.toInt()}';
}

/// İstekler: başvuranlar (X reddet, ✓ kabul).
class FamilyRequestsPage extends StatefulWidget {
  final String familyId;
  const FamilyRequestsPage({super.key, required this.familyId});

  @override
  State<FamilyRequestsPage> createState() => _FamilyRequestsPageState();
}

class _FamilyRequestsPageState extends State<FamilyRequestsPage> {
  int _v = 0;

  Future<void> _answer(String userId, bool accept) async {
    final r = await guard(context, () => Api.post('/api/families/${widget.familyId}/requests/$userId/${accept ? 'accept' : 'reject'}'));
    if (r != null && mounted) {
      toast(context, accept ? 'Aileye kabul edildi.' : 'Başvuru reddedildi.');
      setState(() => _v++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _light(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _appBar(context, 'İstekler'),
        body: AsyncBody<List<Map<String, dynamic>>>(
          version: _v,
          load: () async => listOf((await Api.get('/api/families/${widget.familyId}/requests'))['requests']),
          builder: (context, list, reload) => list.isEmpty
              ? const Center(child: Text('Bekleyen istek yok.', style: TextStyle(color: _dim)))
              : ListView(children: [
                  const Divider(height: 1, color: Color(0xFFEDEDED)),
                  for (final r in list) ...[
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                      leading: UserAvatar(user: mapOf(r['user']), radius: 31),
                      title: Text('${mapOf(r['user'])?['displayName'] ?? ''}', style: const TextStyle(color: Color(0xFF5B6475), fontSize: 20, fontWeight: FontWeight.w500)),
                      subtitle: Align(alignment: Alignment.centerLeft, child: LevelPill(level: mapOf(r['user'])?['coinLevel'] ?? 1, send: true, height: 16)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(onPressed: () => _answer('${mapOf(r['user'])?['id']}', false), icon: const Icon(Icons.close, color: Color(0xFFE53935), size: 36)),
                        IconButton(onPressed: () => _answer('${mapOf(r['user'])?['id']}', true), icon: const Icon(Icons.check, color: Color(0xFF19B33C), size: 36)),
                      ]),
                    ),
                    const Divider(height: 1, color: Color(0xFFEDEDED)),
                  ],
                ]),
        ),
      ),
    );
  }
}

/// Bilgileri Düzenle (ya da yeni aile kur): kapak resmi, aile ismi (12), aile bildirimi (100).
class FamilyEditPage extends StatefulWidget {
  final Map<String, dynamic>? family;
  const FamilyEditPage({super.key, this.family});

  @override
  State<FamilyEditPage> createState() => _FamilyEditPageState();
}

class _FamilyEditPageState extends State<FamilyEditPage> {
  late final _name = TextEditingController(text: (widget.family?['name'] ?? '').toString());
  late final _notice = TextEditingController(text: (widget.family?['description'] ?? '').toString());
  PickedImage? _img;
  bool _busy = false;
  String? _createdId;

  bool get _create => widget.family == null;

  @override
  void dispose() {
    _name.dispose();
    _notice.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final img = await pickImage(context, crop: CropSpec.avatar);
    if (img != null && mounted) setState(() => _img = img);
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.length < 2) {
      toast(context, 'Aile ismi en az 2 karakter olmalı.', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await guard<bool>(context, () async {
      String id;
      if (_create && _createdId == null) {
        final r = await Api.post('/api/families', {'name': name, 'description': _notice.text.trim()});
        id = mapOf(r['family'])!['id'].toString();
        _createdId = id; // logo yüklemesi başarısız olursa tekrar denemede aile yeniden açılmaya çalışılmasın
      } else if (_createdId != null) {
        id = _createdId!;
      } else {
        id = widget.family!['id'].toString();
        final body = <String, dynamic>{'description': _notice.text.trim()};
        if (widget.family!['myRole'] == 'owner' && name != widget.family!['name']) body['name'] = name;
        await Api.patch('/api/families/$id', body);
      }
      if (_img != null) await Api.putBytes('/api/families/$id/logo', _img!.bytes, _img!.mime);
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) Navigator.pop(context, true);
  }

  Widget _field(String label, TextEditingController c, int max, {bool enabled = true}) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: c,
            builder: (_, v, __) => Row(children: [
              Text(label, style: const TextStyle(color: Color(0xFF9A9AA6), fontSize: 15)),
              const Spacer(),
              Text('${v.text.characters.length}/$max', style: const TextStyle(color: Color(0xFF9A9AA6), fontSize: 15)),
            ]),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            enabled: enabled,
            maxLength: max,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w600, fontSize: 15),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final url = Api.absoluteUrl(widget.family?['logoUrl'] as String?);
    final canName = _create || widget.family?['myRole'] == 'owner';
    return Theme(
      data: _light(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _appBar(context, _create ? 'Aile Kur' : 'Bilgileri Düzenle'),
        body: ListView(padding: EdgeInsets.only(bottom: 30 + MediaQuery.paddingOf(context).bottom), children: [
          const SizedBox(height: 30),
          Center(
            child: GestureDetector(
              onTap: _pick,
              child: SizedBox(
                width: 150,
                height: 150,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  CircleAvatar(
                    radius: 75,
                    backgroundColor: const Color(0xFFE9E9EE),
                    backgroundImage: _img != null ? MemoryImage(_img!.bytes) : (url != null ? NetImage(url, targetW: 450, targetH: 450) : null),
                    child: _img == null && url == null ? const Icon(Icons.groups, color: Colors.white, size: 60) : null,
                  ),
                  Positioned(
                    bottom: -10,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(color: const Color(0xFF00A3FF), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 26),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Center(child: Text('Lütfen bir kapak resmi yükle', style: TextStyle(color: Color(0xFF5B6475), fontSize: 15))),
          const SizedBox(height: 26),
          _field('Aile ismi', _name, 12, enabled: canName),
          _field('Aile bildirimi', _notice, 100),
          const SizedBox(height: 60),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 46),
            child: FigButton(_busy ? 'Kaydediliyor...' : 'Onayla', height: 56, color: const Color(0xFF009FFF), fontSize: 22, onTap: _busy ? null : _save),
          ),
        ]),
      ),
    );
  }
}

/// Seviye sayfaları: Demir · Bronz · Gümüş · Altın · Elmas; ayrıcalıklar ve "Hızlı bir şekilde nasıl yükseltilir?".
class FamilyLevelsPage extends StatefulWidget {
  final int initialTier;
  final Map<String, dynamic>? family;
  const FamilyLevelsPage({super.key, this.initialTier = 1, this.family});

  @override
  State<FamilyLevelsPage> createState() => _FamilyLevelsPageState();
}

class _FamilyLevelsPageState extends State<FamilyLevelsPage> {
  late int _tier = widget.initialTier.clamp(1, 5);

  static const _bars = <List<Color>>[
    [Color(0xFF13C97C), Color(0xFF06A35F)],
    [Color(0xFF1C8BFF), Color(0xFF0A3E9E)],
    [Color(0xFFD13BF2), Color(0xFF7A1AC9)],
    [Color(0xFFB52BD9), Color(0xFF2B5CE8)],
    [Color(0xFF555555), Color(0xFF111111)],
  ];

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final k = w / 430;
    return Theme(
      data: _light(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5F7),
        appBar: _appBar(context, '${widget.family?['name'] ?? 'Aile seviyeleri'}'),
        body: AsyncBody<Map<String, dynamic>>(
          load: () => Api.get('/api/families/rules'),
          builder: (context, rules, reload) {
            final tiers = listOf(rules['tiers']);
            final t = tiers.length >= _tier ? tiers[_tier - 1] : <String, dynamic>{};
            return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
              SizedBox(
                height: 252 * k,
                child: Stack(children: [
                  const Positioned.fill(child: Fig('fam_dark_bg', fit: BoxFit.cover)),
                  Positioned(
                    top: 18 * k,
                    left: 0,
                    right: 0,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var i = 1; i <= 5; i++)
                        GestureDetector(
                          onTap: () => setState(() => _tier = i),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10 * k),
                            child: Text(_tierNames[i - 1], style: TextStyle(color: _tier == i ? Colors.white : const Color(0xFF8E8E93), fontWeight: FontWeight.w700, fontSize: 15 * k)),
                          ),
                        ),
                    ]),
                  ),
                  Positioned(top: 70 * k, left: 0, right: 0, child: Center(child: Fig('fam_tier_$_tier', width: 120 * k, height: 120 * k))),
                ]),
              ),
              const Padding(padding: EdgeInsets.fromLTRB(14, 28, 14, 14), child: Text('Ayrıcalıklar', style: TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 15))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 170 / 168,
                  children: [
                    _card(Fig('fam_tier_$_tier', width: 92, height: 92), 'Rütbe Madalyası'),
                    _card(const Icon(Icons.groups_2, color: Color(0xFF14C9A0), size: 84), '${t['capacity'] ?? '-'} Üye'),
                    _card(const Icon(Icons.manage_accounts, color: Color(0xFF14B8F5), size: 84), '${t['admins'] ?? '-'} Yönetici'),
                    _card(
                      SizedBox(
                        width: 150,
                        height: 60,
                        child: Stack(alignment: Alignment.centerLeft, children: [
                          Positioned(
                            left: 24,
                            right: 0,
                            child: Container(height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(colors: _bars[_tier - 1]), border: _tier == 5 ? Border.all(color: const Color(0xFFE2B33C), width: 1.5) : null)),
                          ),
                          Fig('fam_tier_$_tier', width: 56, height: 56),
                        ]),
                      ),
                      'Özel Arkaplan',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: FigButton('Hızlı bir şekilde nasıl yükseltilir?', height: 48, color: _green, fontSize: 18, onTap: () => _howTo(context, rules)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Text(
                  _tier == 1 ? 'Başlangıç seviyesi.' : '${_tierNames[_tier - 1]} için gereken katkı: ${fmtNumber(t['minPoints'] ?? 0)} 🔥',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _dim, fontSize: 13),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _card(Widget icon, String label) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(height: 96, child: Center(child: icon)),
          const SizedBox(height: 14),
          Text(label, style: const TextStyle(color: Color(0xFF5B6475), fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      );
}

/// Görev tablosu sayfası ("Hızlı bir şekilde nasıl yükseltilir?").
void _howTo(BuildContext context, Map<String, dynamic> rules) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🔥', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 10),
          const Text('Aşağıdaki görevleri tamamlayarak ailenizin seviye atlama sürecini hızlandırabilirsiniz.', textAlign: TextAlign.center, style: TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 18),
          FamilyTaskTable(tasks: listOf(rules['tasks'])),
        ]),
      ),
    ),
  );
}

/// Görev / Katkı Değeri tablosu.
class FamilyTaskTable extends StatelessWidget {
  final List<Map<String, dynamic>> tasks;
  const FamilyTaskTable({super.key, required this.tasks});

  @override
  Widget build(BuildContext context) {
    Widget cell(String t, {bool head = false, bool left = true}) => Container(
          height: head ? 56 : 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            t,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: head ? (left ? const Color(0xFF16B33C) : const Color(0xFF5B6475)) : (left ? const Color(0xFF16B33C) : const Color(0xFF5B6475)),
              fontWeight: head ? FontWeight.w700 : FontWeight.w600,
              fontSize: head ? 16 : 13,
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDADDE2)), borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: const TableBorder(horizontalInside: BorderSide(color: Color(0xFFDADDE2)), verticalInside: BorderSide(color: Color(0xFFDADDE2))),
        children: [
          TableRow(children: [cell('Görev', head: true), cell('Katkı Değeri', head: true, left: false)]),
          for (final t in tasks) TableRow(children: [cell('${t['name']}'), cell('${t['value']} 🔥', left: false)]),
        ],
      ),
    );
  }
}

/// Coins ödülü: haftalık katkı kademeleri (başkan alır) ve aile başkanı indirimi.
class FamilyRewardsPage extends StatefulWidget {
  final String familyId;
  final Map<String, dynamic> family;
  const FamilyRewardsPage({super.key, required this.familyId, required this.family});

  @override
  State<FamilyRewardsPage> createState() => _FamilyRewardsPageState();
}

class _FamilyRewardsPageState extends State<FamilyRewardsPage> {
  int _v = 0;

  Future<void> _claim(int tier) async {
    final r = await guard(context, () => Api.post('/api/families/${widget.familyId}/rewards/$tier/claim'));
    if (r != null && mounted) {
      if (r['coins'] != null) Session.setCoins('${r['coins']}');
      toast(context, 'Ödül alındı! 🎉');
      setState(() => _v++);
    }
  }

  Future<void> _cashback() async {
    final r = await guard(context, () => Api.post('/api/families/${widget.familyId}/cashback/claim'));
    if (r != null && mounted) {
      if (r['coins'] != null) Session.setCoins('${r['coins']}');
      toast(context, '${fmtNumber(r['amount'])} Coin indirim alındı.');
      setState(() => _v++);
    }
  }

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _light(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _appBar(context, 'Coins ödülü'),
        body: AsyncBody<Map<String, dynamic>>(
          version: _v,
          load: () async {
            final r = await Future.wait([Api.get('/api/families/${widget.familyId}/rewards'), Api.get('/api/families/rules')]);
            return {...r[0], 'rules': r[1]};
          },
          builder: (context, d, reload) {
            final tiers = listOf(d['tiers']);
            final total = num.tryParse('${d['weekTotal']}') ?? 0;
            final canClaim = d['canClaim'] == true;
            final next = tiers.where((t) => t['reached'] != true).toList();
            final cash = mapOf(d['cashback']) ?? {};
            final maxNeed = tiers.isEmpty ? 1 : (num.tryParse('${tiers.last['need']}') ?? 1);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 30), children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)])),
                child: Column(children: [
                  const Text('Bu hafta için katkı', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('${fmtNumber(d['weekTotal'])} 🔥', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28)),
                  const SizedBox(height: 4),
                  Text('Bu hafta: ${_date(d['weekStart'] as String?)} - ${_date(d['weekEnd'] as String?)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: (total / maxNeed).clamp(0.0, 1.0).toDouble(), minHeight: 10, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD43B))),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    for (final t in tiers)
                      Expanded(
                        child: Column(children: [
                          const Fig('coin_crown', width: 40, height: 40),
                          const SizedBox(height: 4),
                          Text(_compact(t['coins']), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                          Text('${_compact(t['need'])} 🔥', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 30,
                            child: t['claimed'] == true
                                ? const Text('Alındı ✓', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
                                : FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFD43B), foregroundColor: _ink, padding: const EdgeInsets.symmetric(horizontal: 14), minimumSize: const Size(0, 30)),
                                    onPressed: canClaim && t['reached'] == true ? () => _claim((t['tier'] as num).toInt()) : null,
                                    child: const Text('Al', style: TextStyle(fontWeight: FontWeight.w800)),
                                  ),
                          ),
                        ]),
                      ),
                  ]),
                  if (next.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${_compact(next.first['coins'])} coins talep etmek için hâlâ ${_compact((num.tryParse('${next.first['need']}') ?? 0) - total)} katkıya ihtiyacınız var',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  if (!canClaim) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Ödülleri aile başkanı alır.', style: TextStyle(color: Colors.white70, fontSize: 11))),
                ]),
              ),
              const SizedBox(height: 22),
              const Text('Ödül Kuralları', style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              const Text(
                '1- Katkı değeri bu hafta için belirli bir sayıya ulaştığında, ilgili coins ödüllerini talep edebilirsiniz. Zaman aşımından önce talep etmezseniz ödüller silinecektir.',
                style: TextStyle(color: Color(0xFF444444), fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 14),
              const Text('Katkı değerini artıracak durumlar', style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              FamilyTaskTable(tasks: listOf(mapOf(d['rules'])?['tasks'])),
              const SizedBox(height: 26),
              // Aile başkanı indirimi
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFFD54F))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Fig('coin_crown', width: 34, height: 34),
                    const SizedBox(width: 8),
                    const Text('Toplam Coins', style: TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 15)),
                    const Spacer(),
                    Text(fmtNumber(cash['amount'] ?? 0), style: const TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 20)),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF9800)),
                      onPressed: canClaim && (num.tryParse('${cash['amount']}') ?? 0) > 0 ? _cashback : null,
                      child: const Text('Alın'),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    '1- Ailenin başkanı, kişisel coin tüketimi karşılığında bir yüzde indirim alabilir.\n'
                    '2- Toplam harcama, indirimden önce en az ${_compact(cash['minSpend'] ?? 10000)} olmalıdır (şu an ${fmtNumber(cash['spent'] ?? 0)}).\n'
                    '3- Hediyeler, WIP satın alımları, mağaza ürünleri (araç, çerçeve vb.) kişisel tüketime dahildir.\n'
                    '4- Her tüketim orana göre gerçek zamanlı olarak hesaplanır ve biriktirilir.',
                    style: const TextStyle(color: Color(0xFF444444), fontSize: 12.5, height: 1.45),
                  ),
                  const SizedBox(height: 10),
                  Table(
                    border: TableBorder.all(color: const Color(0xFFFFD54F)),
                    children: [
                      const TableRow(children: [
                        Padding(padding: EdgeInsets.all(8), child: Text('Aile seviyesi', textAlign: TextAlign.center, style: TextStyle(color: _ink, fontWeight: FontWeight.w700))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Yüzde', textAlign: TextAlign.center, style: TextStyle(color: _ink, fontWeight: FontWeight.w700))),
                      ]),
                      for (final t in listOf(cash['tiers']))
                        TableRow(children: [
                          Padding(padding: const EdgeInsets.all(8), child: Text('${t['name']}', textAlign: TextAlign.center, style: const TextStyle(color: _ink))),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text((t['bps'] as num? ?? 0) == 0 ? '-' : '%${((t['bps'] as num) / 100).toStringAsFixed(2)}', textAlign: TextAlign.center, style: const TextStyle(color: _ink)),
                          ),
                        ]),
                    ],
                  ),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// Aile kuralları (sorular ve cevaplar) ve katkı tablosu.
class FamilyRulesPage extends StatelessWidget {
  const FamilyRulesPage({super.key});

  static const _faq = <(String, String)>[
    ('1- Aile nedir?', 'Aile, kullanıcıların kendi başlarına oluşturduğu bir kuruluştur. Kullanıcılar aileye katılmak için başvurur ve ailenin büyümesini sürdürmek için benzer düşünen ortaklarla birlikte çalışır.'),
    ('2- Aile nasıl oluşturulur?/Nasıl katılınır?', 'Bir aile oluşturun: Aile adı, kapak resmi ve duyuruyu girerek ailenizi kurabilir ve yönetmeye başlayabilirsiniz. Bir aileye katılın: Aile sayfasında "Aileye Katıl" düğmesine dokunarak başvurun; aile yöneticisi onaylayınca aileye katılırsınız.'),
    ('3- Birden fazla aileye katılabilir miyim?', 'Kullanıcılar yalnızca tek bir aileye katılabilir ve yalnızca tek bir aile oluşturabilirler.'),
    ('4- Bir aileye kaç kişi girebilir?', 'Bu aile düzeyine bağlı bir durumdur. Başlangıç sayısı 150\'dir. Aile seviyesi ne kadar yükselirse üye kabul sayısı da belirli oranla artar.'),
    ('5- Bir ailede kaç yönetici olabilir?', 'Başlangıçta en fazla 5 yönetici olabilir. Aile seviyesi yükseldikçe yönetici sınırı artar (Bronz 8, Gümüş 14, Altın 23, Elmas 35).'),
    ('6- Aile listesi neye göre sıralanır?', 'Aile üyelerinin toplam katkı değerlerine göre sıralanır.'),
    ('7- Aile seviyesi nedir?', 'Aile hiyerarşisi, ailenin gücünü temsil eder. Aile ne kadar güçlüyse seviyesi de o kadar yüksek olur. Aile seviyeleri: Demir - Bronz - Gümüş - Altın - Elmas.'),
    ('8- Aile düzeyi yükseltmesi ne getirir?', 'Seviye yükseldikçe üyelerin üst limiti ve yöneticilerin üst limiti artmaya devam eder. Aynı zamanda seviye yükseldikçe aile rozetlerinin ve arka planların stili de değişir.'),
    ('9- Aile seviyesi nasıl geliştirilir?', 'Aile üyelerinin katkı değerlerinin toplamı hesaplanır. Katkı değeri ne kadar yüksekse seviye de o kadar yüksek olur.'),
    ('10- Katkı değeri nasıl hesaplanır?', 'Aşağıdaki tablodaki görevlerle katkı kazanılır. Kullanıcı aileden ayrılırsa aile seviyesi aynı kalır fakat kişinin katkısı sıfırlanır. Aileye yeni katılanların katkısı 0\'dan başlar.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _light(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _appBar(context, 'Aile kuralları'),
        body: AsyncBody<Map<String, dynamic>>(
          load: () => Api.get('/api/families/rules'),
          builder: (context, rules, reload) => ListView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 30), children: [
            for (final (q, a) in _faq)
              ExpansionTile(
                title: Text(q, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 15)),
                iconColor: _ink,
                collapsedIconColor: _ink,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(a, style: const TextStyle(color: Color(0xFF555555), fontSize: 13.5, height: 1.5))],
              ),
            Padding(padding: const EdgeInsets.fromLTRB(8, 14, 8, 0), child: FamilyTaskTable(tasks: listOf(rules['tasks']))),
          ]),
        ),
      ),
    );
  }
}
