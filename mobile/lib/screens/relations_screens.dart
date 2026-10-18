import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import '../widgets/fig.dart';

/// İlişki türü etiketi: cp · friend (En İyi Arkadaş) · kanka
String relLabel(String? kind) => switch (kind) { 'cp' => 'CP', 'friend' => 'En İyi Arkadaş', 'kanka' => 'Kanka', _ => '' };

String _short(String s, int n) => s.characters.length <= n ? s : '${s.characters.take(n)}...';

String _nameOf(Map<String, dynamic>? u) => (u?['displayName'] ?? '').toString();

void _openProfile(BuildContext context, Map<String, dynamic>? u, Widget Function(String id) profile) {
  final id = u?['id']?.toString();
  if (id == null || u?['isHidden'] == true) return;
  Navigator.push(context, MaterialPageRoute(builder: (_) => profile(id)));
}

/// Profilin "İlişkiler" sekmesi: İlişki Duvarı (CP, En İyi Arkadaş, Kanka).
class RelationWall extends StatefulWidget {
  final String userId;
  final String displayName;
  /// Profil sayfası (döngüsel içe aktarmayı önlemek için dışarıdan verilir).
  final Widget Function(String userId) profileBuilder;
  const RelationWall({super.key, required this.userId, required this.displayName, required this.profileBuilder});

  @override
  State<RelationWall> createState() => _RelationWallState();
}

class _RelationWallState extends State<RelationWall> {
  int _v = 0;
  bool get _self => widget.userId == Session.id;

  Future<void> _endCp(Map<String, dynamic> cp) async {
    final partner = mapOf(cp['user']);
    final ok = await showDialog<bool>(context: context, builder: (_) => CpCancelDialog(me: Session.me.value, partner: partner));
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.post('/api/cp/with/${partner?['id']}/end'));
    if (r != null && mounted) {
      toast(context, 'CP ilişkisi sonlandırıldı.');
      setState(() => _v++);
    }
  }

  Future<void> _build() async {
    await showIntimacySheet(context, widget.userId);
    if (mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Map<String, dynamic>>(
      version: _v,
      load: () => Api.get('/api/cp/wall/${widget.userId}'),
      builder: (context, d, reload) {
        final cp = mapOf(d['cp']);
        final friend = mapOf(d['friend']) ?? {};
        final kanka = mapOf(d['kanka']) ?? {};
        final owner = mapOf(d['owner']);
        final empty = cp == null && listOf(friend['items']).isEmpty && listOf(kanka['items']).isEmpty;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
          child: Column(children: [
            _WallFrame(
              child: empty
                  ? const _EmptyWall()
                  : Column(children: [
                      _CpStage(
                        left: owner,
                        right: mapOf(cp?['user']),
                        level: cp?['level'],
                        exp: cp?['exp'],
                        onTapUser: (u) => _openProfile(context, u, widget.profileBuilder),
                        onRemove: _self && cp != null ? () => _endCp(cp) : null,
                      ),
                      _RelSection(
                        kind: 'friend',
                        title: 'En iyi arkadaş',
                        data: friend,
                        onMore: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RelationListScreen(userId: widget.userId, kind: 'friend', profileBuilder: widget.profileBuilder))),
                        onTapUser: (u) => _openProfile(context, u, widget.profileBuilder),
                      ),
                      _RelSection(
                        kind: 'kanka',
                        title: 'Kanka',
                        data: kanka,
                        onMore: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RelationListScreen(userId: widget.userId, kind: 'kanka', profileBuilder: widget.profileBuilder))),
                        onTapUser: (u) => _openProfile(context, u, widget.profileBuilder),
                      ),
                      const SizedBox(height: 18),
                    ]),
            ),
            if (!_self) ...[
              const SizedBox(height: 22),
              SizedBox(width: 230, child: FigButton('İlişki Kur', onTap: _build, height: 46, color: FigPal.pink, fontSize: 19)),
            ],
          ]),
        );
      },
    );
  }
}

/// Pembe çerçeveli duvar: üstte "İlişki Duvarı" başlığı, köşelerde altın süsler.
class _WallFrame extends StatelessWidget {
  final Widget child;
  const _WallFrame({required this.child});

  // Figma: 350 genişlik; çerçeve 22'den başlar, üst süs 84, başlık bandı 200x56 (y 9), alt süs 51.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final k = box.maxWidth / 350;
      return Stack(clipBehavior: Clip.none, children: [
        Container(
          margin: EdgeInsets.only(top: 22 * k, bottom: 14 * k),
          padding: EdgeInsets.all(5 * k),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF8CC8), Color(0xFFF2509F), Color(0xFFFF8CC8)]),
            borderRadius: BorderRadius.circular(8 * k),
            boxShadow: const [BoxShadow(color: Color(0x33FF4FA8), blurRadius: 10)],
          ),
          child: Container(
            decoration: BoxDecoration(color: const Color(0xFFFFF1F8), borderRadius: BorderRadius.circular(4 * k)),
            clipBehavior: Clip.antiAlias,
            child: Padding(padding: EdgeInsets.only(bottom: 26 * k), child: child),
          ),
        ),
        Positioned(left: 0, right: 0, top: 0, height: 84 * k, child: const IgnorePointer(child: Fig('rel_wall_top', fit: BoxFit.fill))),
        Positioned(left: 0, right: 0, bottom: 0, height: 51 * k, child: const IgnorePointer(child: Fig('rel_wall_bottom', fit: BoxFit.fill))),
        Positioned(
          top: 9 * k,
          left: 75 * k,
          width: 200 * k,
          height: 56 * k,
          child: Stack(alignment: Alignment.center, children: [
            const Positioned.fill(child: Fig('rel_title', fit: BoxFit.fill)),
            Padding(
              padding: EdgeInsets.only(bottom: 6 * k),
              child: Text('İlişki Duvarı', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16 * k, shadows: const [Shadow(color: Color(0x66A0005A), blurRadius: 2)])),
            ),
          ]),
        ),
      ]);
    });
  }
}

class _EmptyWall extends StatelessWidget {
  const _EmptyWall();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 250,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('Henüz bir ilişkisi yok', style: TextStyle(color: Color(0xFFFF7FBF), fontWeight: FontWeight.w700, fontSize: 17)),
        SizedBox(height: 26),
        Fig('love_heart', width: 64, height: 58),
      ]),
    );
  }
}

/// CP sahnesi: pembe şato arka planı, kanatlı iki avatar, ortada seviye kalbi ve yakınlık puanı.
class _CpStage extends StatelessWidget {
  final Map<String, dynamic>? left;
  final Map<String, dynamic>? right;
  final dynamic level;
  final dynamic exp;
  final void Function(Map<String, dynamic>? u) onTapUser;
  final VoidCallback? onRemove;
  const _CpStage({required this.left, required this.right, required this.level, required this.exp, required this.onTapUser, this.onRemove});

  // Figma (iç genişlik 340): şato 340x200; avatarlar 59x60 (x 58 / 223, y 81); kanatlar 110x109 (y 47);
  // kalp 50x42 (x 145, y 90); puan hapı 58x18 (x 141, y 156); isimler y 158.
  Widget _avatar(Map<String, dynamic>? u, double k) => GestureDetector(
        onTap: u == null ? null : () => onTapUser(u),
        child: Container(
          width: 60 * k,
          height: 60 * k,
          padding: EdgeInsets.all(2.5 * k),
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 5)]),
          child: u == null
              ? CircleAvatar(backgroundColor: const Color(0xFFFFD1E8), child: Icon(Icons.favorite_border, color: Colors.white, size: 24 * k))
              : UserAvatar(user: u, radius: 27.5 * k),
        ),
      );

  Widget _name(Map<String, dynamic>? u, double k) => SizedBox(
        width: 96 * k,
        child: Text(u == null ? 'CP yok' : _short(_nameOf(u), 11), maxLines: 1, overflow: TextOverflow.clip, textAlign: TextAlign.center, style: TextStyle(color: FigPal.ink, fontWeight: FontWeight.w600, fontSize: 12.5 * k)),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final k = box.maxWidth / 340;
      return SizedBox(
        height: 200 * k,
        child: Stack(clipBehavior: Clip.none, children: [
          const Positioned.fill(child: Fig('rel_castle', fit: BoxFit.cover)),
          Positioned(left: 4 * k, top: 47 * k, child: Fig('wing', width: 110 * k, height: 109 * k)),
          Positioned(right: 4 * k, top: 47 * k, child: Fig('wing', width: 110 * k, height: 109 * k, flipX: true)),
          Positioned(left: 58 * k, top: 81 * k, child: _avatar(left, k)),
          Positioned(left: 223 * k, top: 81 * k, child: _avatar(right, k)),
          Positioned(
            left: 145 * k,
            top: 90 * k,
            width: 50 * k,
            height: 42 * k,
            child: Stack(alignment: Alignment.center, children: [
              const Positioned.fill(child: Fig('heart_lv')),
              Text('Lv.${level ?? 0}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12 * k)),
            ]),
          ),
          Positioned(
            left: 141 * k,
            top: 156 * k,
            width: 58 * k,
            height: 18 * k,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9 * k)),
              child: FittedBox(child: Text(fmtNumber(exp ?? 0), style: TextStyle(color: FigPal.ink, fontWeight: FontWeight.w800, fontSize: 14 * k))),
            ),
          ),
          Positioned(left: 40 * k, top: 158 * k, child: _name(left, k)),
          Positioned(left: 205 * k, top: 158 * k, child: _name(right, k)),
          if (onRemove != null)
            Positioned(
              right: 12 * k,
              top: 30 * k,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8 * k, vertical: 2 * k),
                  decoration: BoxDecoration(color: const Color(0xFFFFA9D6), borderRadius: BorderRadius.circular(10)),
                  child: Text('Kaldır', style: TextStyle(color: Colors.white, fontSize: 10.5 * k, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

class _RelSection extends StatelessWidget {
  final String kind;
  final String title;
  final Map<String, dynamic> data;
  final VoidCallback onMore;
  final void Function(Map<String, dynamic>? u) onTapUser;
  const _RelSection({required this.kind, required this.title, required this.data, required this.onMore, required this.onTapUser});

  @override
  Widget build(BuildContext context) {
    final items = listOf(data['items']);
    final count = (data['count'] as num?)?.toInt() ?? items.length;
    final color = kind == 'kanka' ? FigPal.blueText : FigPal.purpleText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
          const Spacer(),
          if (count > 3)
            InkWell(
              onTap: onMore,
              child: const Row(children: [
                Text('Diğerleri', style: TextStyle(color: FigPal.grey, fontSize: 11)),
                Icon(Icons.chevron_right, size: 15, color: FigPal.grey),
              ]),
            ),
        ]),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('Henüz $title yok', style: const TextStyle(color: FigPal.grey, fontSize: 13)))
        else
          Row(children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: i < items.length ? RelCard(kind: kind, item: items[i], onTap: () => onTapUser(mapOf(items[i]['user']))) : const SizedBox()),
            ],
          ]),
      ]),
    );
  }
}

/// En İyi Arkadaş (mor) / Kanka (mavi) kartı.
class RelCard extends StatelessWidget {
  final String kind;
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  const RelCard({super.key, required this.kind, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final blue = kind == 'kanka';
    final c1 = blue ? FigPal.blueCard1 : FigPal.purpleCard1;
    final c2 = blue ? FigPal.blueCard2 : FigPal.purpleCard2;
    final border = blue ? FigPal.blueBorder : FigPal.purpleBorder;
    final text = blue ? FigPal.blueText : FigPal.purpleText;
    final u = mapOf(item['user']);
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 101 / 150,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: border, width: 2)),
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c1, c2])),
            child: LayoutBuilder(builder: (context, box) {
              final s = box.maxWidth / 94;
              return Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                FittedBox(fit: BoxFit.scaleDown, child: Text(relLabel(kind), style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 13 * s))),
                Text('Lv.${item['level'] ?? 0}', style: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 10.5 * s)),
                Container(
                  padding: EdgeInsets.all(2 * s),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: UserAvatar(user: u, radius: 21 * s),
                ),
                Text(_short(_nameOf(u), 8), maxLines: 1, style: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 12.5 * s)),
                Text('${item['days'] ?? 0} Gün', style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 12.5 * s)),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

/// "En iyi arkadaşlar" / "Kankalar" tam liste (3'lü ızgara). Kendi listende kalemle düzenle: X ile ilişkiyi bitir.
class RelationListScreen extends StatefulWidget {
  final String userId;
  final String kind;
  final Widget Function(String userId) profileBuilder;
  const RelationListScreen({super.key, required this.userId, required this.kind, required this.profileBuilder});

  @override
  State<RelationListScreen> createState() => _RelationListScreenState();
}

class _RelationListScreenState extends State<RelationListScreen> {
  int _v = 0;
  bool _edit = false;
  bool get _self => widget.userId == Session.id;

  Future<void> _end(Map<String, dynamic>? u) async {
    final id = u?['id'];
    if (id == null) return;
    if (!await confirm(context, '${_nameOf(u)} ile ${relLabel(widget.kind)} ilişkiniz sonlandırılsın mı?', action: 'Sonlandır', destructive: true) || !mounted) return;
    final r = await guard(context, () => Api.post('/api/cp/with/$id/end'));
    if (r != null && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: FigPal.ink,
          elevation: 0,
          titleSpacing: 0,
          title: Text(widget.kind == 'kanka' ? 'Kankalar' : 'En iyi arkadaşlar', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          actions: [if (_self) IconButton(tooltip: 'Düzenle', onPressed: () => setState(() => _edit = !_edit), icon: Icon(_edit ? Icons.check : Icons.edit))],
        ),
        body: AsyncBody<List<Map<String, dynamic>>>(
          version: _v,
          load: () async => listOf((await Api.get('/api/cp/wall/${widget.userId}/${widget.kind}'))['items']),
          builder: (context, items, reload) => items.isEmpty
              ? const Center(child: Text('Liste boş.', style: TextStyle(color: FigPal.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 16, crossAxisSpacing: 12, childAspectRatio: 101 / 150),
                  itemCount: items.length,
                  itemBuilder: (_, i) => Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(child: RelCard(kind: widget.kind, item: items[i], onTap: () => _openProfile(context, mapOf(items[i]['user']), widget.profileBuilder))),
                    if (_edit)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: GestureDetector(
                          onTap: () => _end(mapOf(items[i]['user'])),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(color: Color(0xFF6E6E73), shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                  ]),
                ),
        ),
      ),
    );
  }
}

/// CP İptali onay penceresi.
class CpCancelDialog extends StatelessWidget {
  final Map<String, dynamic>? me;
  final Map<String, dynamic>? partner;
  const CpCancelDialog({super.key, this.me, this.partner});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close, color: Colors.black))),
          PairAvatars(left: me, right: partner, size: 84),
          const SizedBox(height: 12),
          const Text('CP İptali', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 22)),
          const SizedBox(height: 10),
          const Text('Bu kullanıcı ile olan CP ilişkinizi sonlandırmak istediğinizden emin misiniz?', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF333333), fontSize: 13.5)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: FigButton('İptal', height: 40, color: Colors.black, fontSize: 18, onTap: () => Navigator.pop(context, false))),
            const SizedBox(width: 10),
            Expanded(child: FigButton('Onayla', height: 40, color: FigPal.pink, fontSize: 18, onTap: () => Navigator.pop(context, true))),
          ]),
        ]),
      ),
    );
  }
}

/// Kanatların önünde yan yana iki avatar ve altta iki kalp (CP / koruyucu).
class PairAvatars extends StatelessWidget {
  final Map<String, dynamic>? left;
  final Map<String, dynamic>? right;
  final Widget? rightChild;
  final double size;
  const PairAvatars({super.key, this.left, this.right, this.rightChild, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final r = size / 2;
    return SizedBox(
      width: size * 3.1,
      height: size * 1.45,
      child: Stack(alignment: Alignment.center, children: [
        Positioned(left: 0, top: 0, child: Fig('wing', width: size * 1.55, height: size * 1.4)),
        Positioned(right: 0, top: 0, child: Fig('wing', width: size * 1.55, height: size * 1.4, flipX: true)),
        Positioned(
          top: size * 0.22,
          child: SizedBox(
            width: size * 1.85,
            height: size + 6,
            child: Stack(children: [
              Positioned(left: 0, child: _ring(left == null ? null : UserAvatar(user: left, radius: r))),
              Positioned(right: 0, child: _ring(rightChild ?? (right == null ? null : UserAvatar(user: right, radius: r)))),
            ]),
          ),
        ),
        Positioned(top: size * 0.98, child: Fig('hearts_pair', width: size * 0.62, height: size * 0.42)),
      ]),
    );
  }

  Widget _ring(Widget? child) => Container(
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 6)]),
        child: child ?? CircleAvatar(radius: size / 2, backgroundColor: const Color(0xFFFFD1E8)),
      );
}

/// Yakınlık penceresini (alttan açılan) gösterir: özel mesajdaki kalp ve profildeki "İlişki Kur".
Future<void> showIntimacySheet(BuildContext context, String userId) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IntimacyScreen(userId: userId),
    );

/// Bir kişiyle yakınlık penceresi: seviye kalpleri, yakınlık görevleri ve ilişki daveti.
class IntimacyScreen extends StatefulWidget {
  final String userId;
  const IntimacyScreen({super.key, required this.userId});

  @override
  State<IntimacyScreen> createState() => _IntimacyScreenState();
}

class _IntimacyScreenState extends State<IntimacyScreen> {
  int _v = 0;

  Future<Map<String, dynamic>> _load() async {
    final r = await Future.wait([
      Api.get('/api/cp/with/${widget.userId}'),
      Api.get('/api/users/${widget.userId}'),
    ]);
    return {'s': r[0], 'p': mapOf(r[1]['profile']) ?? {}};
  }

  Future<void> _answer(bool accept) async {
    final r = await guard(context, () => Api.post('/api/cp/with/${widget.userId}/${accept ? 'accept' : 'decline'}'));
    if (r != null && mounted) {
      toast(context, accept ? 'İlişki kuruldu! ❤' : 'Davet reddedildi.');
      setState(() => _v++);
    }
  }

  Future<void> _cancel() async {
    if (!await confirm(context, 'Davet geri çekilsin mi? Coin iade edilir.', action: 'Geri çek') || !mounted) return;
    final r = await guard(context, () => Api.post('/api/cp/with/${widget.userId}/decline'));
    if (r != null && mounted) {
      await Session.refresh().catchError((_) {});
      if (mounted) setState(() => _v++);
    }
  }

  Future<void> _invite(Map<String, dynamic> p, Map<String, dynamic> s) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RelationPickSheet(other: p, costs: mapOf(s['costs']) ?? {}),
    );
    if (sent == true && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(useMaterial3: true),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.86,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(color: Color(0xFFFFF4FA), borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        child: Material(color: Colors.transparent, child: AsyncBody<Map<String, dynamic>>(
          version: _v,
          load: _load,
          builder: (context, d, reload) {
            final s = mapOf(d['s']) ?? {};
            final p = mapOf(d['p']) ?? {};
            final level = (s['level'] as num?)?.toInt() ?? 0;
            final steps = s['steps'] is List ? s['steps'] as List : const <dynamic>[];
            final exp = s['exp'] ?? '0';
            final next = s['nextLevelExp'];
            final req = mapOf(s['request']);
            final relation = (s['relation'] ?? 'none').toString();
            final rules = mapOf(s['rules']) ?? {};
            final need = BigInt.tryParse('$next') != null && BigInt.tryParse('$exp') != null ? BigInt.parse('$next') - BigInt.parse('$exp') : null;
            return ListView(padding: EdgeInsets.zero, children: [
              Container(
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF8CCB), Color(0xFFFFC6E5), Color(0xFFFFF4FA)])),
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Column(children: [
                  Row(children: [
                    IconButton(onPressed: () => _rules(context, rules), icon: const Icon(Icons.help_outline, color: Colors.white)),
                    const Expanded(child: Fig('sheet_crown', height: 34)),
                    IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.close, color: Colors.white)),
                  ]),
                  SizedBox(
                    height: 150,
                    child: Stack(alignment: Alignment.center, children: [
                      Positioned(left: 4, top: 0, child: Fig('wing', width: 150, height: 130)),
                      Positioned(right: 4, top: 0, child: Fig('wing', width: 150, height: 130, flipX: true)),
                      Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          _person(Session.me.value),
                          Column(children: [
                            const SizedBox(height: 8),
                            const Fig('heart_lv', width: 64, height: 56),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
                              decoration: BoxDecoration(color: FigPal.pink, borderRadius: BorderRadius.circular(12)),
                              child: Text(fmtNumber(exp), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                            ),
                          ]),
                          _person(p),
                        ]),
                      ),
                    ]),
                  ),
                ]),
              ),
              _HeartBox(
                child: Column(children: [
                  Text(
                    level >= steps.length && steps.isNotEmpty ? 'En yüksek yakınlık seviyesindesiniz!' : '${fmtNumber(need ?? 0)} yakınlık gerekli, Lv${level + 1} seviyesine yükselt',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: FigPal.ink, fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    for (var i = 0; i < (steps.isEmpty ? 5 : steps.length); i++)
                      Column(children: [
                        Opacity(
                          opacity: i < level ? 1 : 0.55,
                          child: SizedBox(
                            width: 52,
                            height: 46,
                            child: Stack(alignment: Alignment.center, children: [
                              const Positioned.fill(child: Fig('heart_lv')),
                              Text('Lv.${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(color: const Color(0xFFFF9ED0), borderRadius: BorderRadius.circular(8)),
                          child: Text(steps.isEmpty ? '${i + 1}' : _compact('${steps[i]}'), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                  ]),
                ]),
              ),
              _HeartBox(
                child: Column(children: [
                  const Text('Yakınlık Seviyesi Görevleri', style: TextStyle(color: FigPal.ink, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  _task(Icons.chat_bubble_outline, 'Sohbet - Özel Mesajlar', '+${rules['messageExp'] ?? 10}/Mesaj', ' Günlük ilk ${rules['messagesPerDay'] ?? 10} mesaj'),
                  const Divider(height: 18, color: Color(0xFFF6D3E6)),
                  _task(Icons.card_giftcard, 'Hediyeler - Oda ve özel sohbet hediyeleri', '1 Coin = 1 puan', ' · CP hediyeleri x${rules['cpGiftMultiplier'] ?? 1.5}'),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
                child: widget.userId == Session.id
                    ? const SizedBox()
                    : req != null && req['fromMe'] != true
                        ? Column(children: [
                            Text('${relLabel(req['kind'] as String?)} davetin var', style: const TextStyle(color: FigPal.pinkText, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: FigButton('Reddet', height: 46, color: Colors.black, onTap: () => _answer(false))),
                              const SizedBox(width: 10),
                              Expanded(child: FigButton('Kabul et', height: 46, onTap: () => _answer(true))),
                            ]),
                          ])
                        : req != null
                            ? Column(children: [
                                Text('${relLabel(req['kind'] as String?)} daveti gönderildi, yanıt bekleniyor', textAlign: TextAlign.center, style: const TextStyle(color: FigPal.pinkText, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 10),
                                FigButton('Daveti geri çek', height: 48, color: const Color(0xFFFFB3D9), onTap: _cancel),
                              ])
                            : Column(children: [
                                if (relation != 'none')
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text('Şu an ${relLabel(relation)}siniz', style: const TextStyle(color: FigPal.pinkText, fontWeight: FontWeight.w700)),
                                  ),
                                FigButton('İlişki kurmak için davet et', height: 52, gradient: const LinearGradient(colors: [Color(0xFFFF8AD0), Color(0xFFFF6FC3)]), onTap: () => _invite(p, s)),
                              ]),
              ),
            ]);
          },
        )),
      ),
    );
  }

  static String _compact(String v) {
    final n = int.tryParse(v) ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return '$n';
  }

  Widget _person(Map<String, dynamic>? u) => SizedBox(
        width: 110,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: UserAvatar(user: u, radius: 38),
          ),
          const SizedBox(height: 4),
          Text(_short(_nameOf(u), 10), maxLines: 1, style: const TextStyle(color: FigPal.ink, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      );

  Widget _task(IconData icon, String title, String strong, String rest) => Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(color: Color(0xFFFFE6F2), shape: BoxShape.circle),
          child: Icon(icon, color: FigPal.pink, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: FigPal.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text.rich(TextSpan(children: [
              TextSpan(text: strong, style: const TextStyle(color: FigPal.pinkText, fontWeight: FontWeight.w700)),
              TextSpan(text: rest, style: const TextStyle(color: Color(0xFF555555))),
            ]), style: const TextStyle(fontSize: 11.5)),
          ]),
        ),
      ]);

  void _rules(BuildContext context, Map<String, dynamic> rules) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Yakınlık nasıl artar?', style: TextStyle(color: Colors.black)),
        content: Text(
          '• Özel mesaj: her mesaj +${rules['messageExp'] ?? 10} puan (günde ilk ${rules['messagesPerDay'] ?? 10} mesaj).\n'
          '• Hediye: aranızdaki hediyelerde 1 Coin = 1 puan, CP hediyelerinde ${rules['cpGiftMultiplier'] ?? 1.5} kat.\n'
          '• İlişki daveti Coin ile gönderilir. Karşı taraf 24 saat içinde kabul etmezse Coin iade edilir.\n'
          '• Herkesin tek CP\'si olur; En İyi Arkadaş ve Kanka birden çok olabilir.',
          style: const TextStyle(color: Color(0xFF333333), height: 1.45),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
      ),
    );
  }
}

/// Köşelerinde kalp olan pembe çerçeveli kutu.
class _HeartBox extends StatelessWidget {
  final Widget child;
  const _HeartBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFF59AD0), width: 2)),
          child: child,
        ),
        for (final a in const [Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight])
          Positioned.fill(
            child: Align(
              alignment: a,
              child: Transform.translate(
                offset: Offset(a.x * 8, a.y * 8),
                child: const Icon(Icons.favorite, color: Color(0xFFE6007E), size: 20),
              ),
            ),
          ),
      ]),
    );
  }
}

/// "İlişki Türünü Seç": CP / En İyi Arkadaş / Kanka, Coin bedeli ve davet.
class RelationPickSheet extends StatefulWidget {
  final Map<String, dynamic> other;
  final Map<String, dynamic> costs;
  const RelationPickSheet({super.key, required this.other, required this.costs});

  @override
  State<RelationPickSheet> createState() => _RelationPickSheetState();
}

class _RelationPickSheetState extends State<RelationPickSheet> {
  String _kind = 'cp';
  bool _busy = false;

  String get _cost => '${widget.costs[_kind] ?? ''}';

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    final id = widget.other['id'];
    final r = await guard(context, () => Api.post('/api/cp/with/$id/request', {'kind': _kind}));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      await Session.refresh().catchError((_) {});
      if (!mounted) return;
      toast(context, '${relLabel(_kind)} daveti gönderildi.');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final purple = _kind == 'friend';
    final blue = _kind == 'kanka';
    final stageColors = blue
        ? const [Color(0xFFBFD8FF), Color(0xFFDDEBFF)]
        : purple
            ? const [Color(0xFFB98CFF), Color(0xFFE2CCFF)]
            : const [Color(0xFFFF9ED6), Color(0xFFFFD3EC)];
    return Theme(
      data: ThemeData.light(useMaterial3: true),
      child: Container(
        height: mq.size.height * 0.72,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        child: Column(children: [
          Container(
            decoration: const BoxDecoration(color: Color(0xFFFFDCF0), borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
            child: Column(children: [
              SizedBox(
                height: 56,
                child: Row(children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black)),
                  const Expanded(child: Text('İlişki Türünü Seç', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 19))),
                  const SizedBox(width: 48),
                ]),
              ),
              const Divider(height: 1, color: Color(0xFFF2B5D6)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(children: [
                  for (final k in const ['cp', 'friend', 'kanka'])
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => setState(() => _kind = k),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(color: _kind == k ? Colors.white : const Color(0xFFF3C3DE), borderRadius: BorderRadius.circular(16)),
                          child: Text(relLabel(k), style: TextStyle(color: _kind == k ? Colors.black : const Color(0xFFB98BA6), fontSize: 15)),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: stageColors),
                  image: DecorationImage(
                    image: Fig.provider(_kind == 'cp' ? 'rel_stage_cp' : 'rel_stage_friend'),
                    fit: BoxFit.cover,
                    opacity: 0.55,
                    colorFilter: _kind == 'friend' ? const ColorFilter.mode(Color(0xFFB98CFF), BlendMode.modulate) : null,
                    onError: (_, __) {},
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
                child: Column(children: [
                  if (_kind == 'cp')
                    PairAvatars(left: Session.me.value, right: widget.other, size: 70)
                  else
                    SizedBox(height: 160, child: Stack(alignment: Alignment.center, children: [
                      const Positioned(left: 0, child: Fig('wing', width: 130, height: 120)),
                      const Positioned(right: 0, child: Fig('wing', width: 130, height: 120, flipX: true)),
                      SizedBox(width: 150, child: RelCard(kind: _kind, item: {'user': widget.other, 'level': 1, 'days': 0})),
                    ])),
                  const SizedBox(height: 6),
                  if (_kind == 'cp')
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_short(_nameOf(Session.me.value), 10), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 14),
                      Text(_short(_nameOf(widget.other), 10), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                    ]),
                  const SizedBox(height: 10),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text('${relLabel(_kind)} Coins $_cost', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 18))),
                            const SizedBox(width: 4),
                            const CircleAvatar(radius: 9, backgroundColor: Color(0xFFFFD43B)),
                          ]),
                          const SizedBox(height: 6),
                          const Text('Coins gönder ve ilişkiyi başlat', style: TextStyle(color: Color(0xFF333333), fontSize: 12)),
                        ]),
                      ),
                      Fig('rel_icon_$_kind', width: 64, height: 64),
                    ]),
                  ),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 14, 8, 0),
                child: Text(
                  'Eğer diğer kullanıcı daveti 24 saat içinde kabul etmezse, davet süresi dolar ve harcanan coins otomatik olarak iade edilir',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF333333), fontSize: 12, height: 1.6),
                ),
              ),
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + mq.padding.bottom),
            child: FigButton(_busy ? 'Gönderiliyor...' : 'İlişki kurmak için davet et', height: 54, gradient: const LinearGradient(colors: [Color(0xFFFF8AD0), Color(0xFFFF6FC3)]), onTap: _busy ? null : _send),
          ),
        ]),
      ),
    );
  }
}
