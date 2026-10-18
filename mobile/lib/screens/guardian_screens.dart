import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import '../widgets/fig.dart';
import 'relations_screens.dart';

const _bg = Color(0xFFFFE1F3);

String _short(String s, int n) => s.characters.length <= n ? s : '${s.characters.take(n)}...';

/// Profildeki koruyucu rozeti: süslü çerçeve içinde en yüksek puanlı koruyucunun fotoğrafı (yoksa koltuk simgesi).
class GuardianBadge extends StatelessWidget {
  final String ownerId;
  final Map<String, dynamic>? guardian;
  final double size;
  final Widget Function(String userId) profileBuilder;
  const GuardianBadge({super.key, required this.ownerId, required this.guardian, required this.profileBuilder, this.size = 70});

  @override
  Widget build(BuildContext context) {
    final u = mapOf(guardian?['user']);
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GuardiansScreen(ownerId: ownerId, profileBuilder: profileBuilder))),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            width: size * 0.54,
            height: size * 0.54,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: FigPal.pink),
            child: u == null
                ? Icon(Icons.chair_outlined, color: Colors.white, size: size * 0.3)
                : ClipOval(child: UserAvatar(user: u, radius: size * 0.27)),
          ),
          Positioned.fill(child: IgnorePointer(child: Fig('guard_badge', width: size, height: size))),
        ]),
      ),
    );
  }
}

/// Koltuk simgeli pembe daire (koruyucu yok).
class _ChairCircle extends StatelessWidget {
  final double radius;
  const _ChairCircle({required this.radius});

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: FigPal.pink,
        child: Container(
          width: radius * 1.3,
          height: radius * 1.3,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
          child: Icon(Icons.chair_outlined, color: Colors.white, size: radius * 0.8),
        ),
      );
}

/// Bir kişinin koruyucuları: puan, "Koruyucu Ol" ve koruyucu sıralaması.
class GuardiansScreen extends StatefulWidget {
  final String ownerId;
  final Widget Function(String userId) profileBuilder;
  const GuardiansScreen({super.key, required this.ownerId, required this.profileBuilder});

  @override
  State<GuardiansScreen> createState() => _GuardiansScreenState();
}

class _GuardiansScreenState extends State<GuardiansScreen> {
  int _v = 0;

  Future<void> _join(Map<String, dynamic> d) async {
    final owner = mapOf(d['owner']);
    final cost = '${mapOf(d['rules'])?['cost'] ?? 3000}';
    final ok = await showDialog<bool>(context: context, builder: (_) => GuardianJoinDialog(owner: owner, cost: cost));
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.post('/api/guardians/of/${widget.ownerId}/join'));
    if (r != null && mounted) {
      if (r['coins'] != null) Session.setCoins('${r['coins']}');
      toast(context, 'Artık koruyucususun! 🛡️');
      setState(() => _v++);
    }
  }

  Future<void> _leave() async {
    if (!await confirm(context, 'Koruyuculuğun sonlandırılsın mı? Koruyucu puanın silinir.', action: 'Sonlandır', destructive: true) || !mounted) return;
    final r = await guard(context, () => Api.post('/api/guardians/of/${widget.ownerId}/leave'));
    if (r != null && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(useMaterial3: true),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          title: const Text('Koruyucular', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 19)),
          actions: [IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GuardianRulesScreen())), icon: const Icon(Icons.help_outline))],
        ),
        body: AsyncBody<Map<String, dynamic>>(
          version: _v,
          load: () => Api.get('/api/guardians/of/${widget.ownerId}'),
          builder: (context, d, reload) {
            final owner = mapOf(d['owner']);
            final top = mapOf(d['top']);
            final list = listOf(d['guardians']);
            final isSelf = d['isSelf'] == true;
            final enabled = d['enabled'] != false;
            final mine = d['myPoints'];
            return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
              Center(
                child: PairAvatars(
                  left: owner,
                  right: mapOf(top?['user']),
                  rightChild: top == null ? const _ChairCircle(radius: 48) : null,
                  size: 96,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0x00FFB7DE), Color(0xFFFFC2E2), Color(0x00FFB7DE)]),
                  border: Border.symmetric(horizontal: BorderSide(color: Color(0xFFFF8FCB), width: 1.2)),
                ),
                child: Text('Koruyucu Puanları: ${fmtNumber(top?['points'] ?? 0)}', textAlign: TextAlign.center, style: const TextStyle(color: FigPal.pinkText, fontWeight: FontWeight.w700, fontSize: 19)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(36, 16, 36, 0),
                child: Text(
                  'Bu bölüm en çok koruyucu puanına sahip kullanıcı içindir. Profil sahibi dilerse değiştirebilir.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFF0479E), fontSize: 13, height: 1.6),
                ),
              ),
              const SizedBox(height: 22),
              if (!enabled && !isSelf)
                const Center(child: Text('Bu kullanıcı koruyucu kabul etmiyor.', style: TextStyle(color: FigPal.grey)))
              else if (!isSelf)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60),
                  child: mine == null
                      ? FigButton('Koruyucu Ol', height: 48, gradient: const LinearGradient(colors: [Color(0xFFFF8AD8), Color(0xFFF54BE0)], begin: Alignment.topCenter, end: Alignment.bottomCenter), onTap: () => _join(d))
                      : Column(children: [
                          Text('Koruyucu puanın: ${fmtNumber(mine)}', style: const TextStyle(color: FigPal.pinkText, fontWeight: FontWeight.w700, fontSize: 15)),
                          TextButton(onPressed: _leave, child: const Text('Koruyuculuğu sonlandır', style: TextStyle(color: FigPal.grey))),
                        ]),
                ),
              const SizedBox(height: 26),
              _RankingBoard(title: 'Koruyucu Sıralaması', list: list, onTap: (u) {
                final id = u?['id']?.toString();
                if (id != null && u?['isHidden'] != true) Navigator.push(context, MaterialPageRoute(builder: (_) => widget.profileBuilder(id)));
              }),
            ]);
          },
        ),
      ),
    );
  }
}

/// Kanatlı, kalpli başlık bandı ("Koruyucu Sıralaması" / "Koruyucu Olduklarım").
class _WingBanner extends StatelessWidget {
  final String title;
  const _WingBanner(this.title);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        const Positioned(left: -6, top: 14, child: Fig('guard_rank_wing', width: 130, height: 66)),
        const Positioned(right: -6, top: 14, child: Fig('guard_rank_wing', width: 130, height: 66, flipX: true)),
        const Positioned(
          top: 2,
          left: 0,
          right: 0,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Fig('heart_wings', width: 64, height: 28), SizedBox(width: 18), Fig('heart_wings', width: 64, height: 28)]),
        ),
        Positioned(
          top: 30,
          child: Container(
            width: 250,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFC3A0), Color(0xFFFF6FD0)]),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0x33FF4FA8), blurRadius: 6, offset: Offset(0, 3))],
            ),
            child: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
      ]),
    );
  }
}

/// Pembe sıralama tablosu. [trailing]: düzenleme modunda satırın sağ üstündeki etiket (Seç / Sonlandır),
/// [leadingTag]: satırın sol altındaki etiket (Kaldır).
class _RankingBoard extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> list;
  final void Function(Map<String, dynamic>? u) onTap;
  final Widget? Function(Map<String, dynamic> g)? corner;
  final Widget? Function(Map<String, dynamic> g)? tag;
  final String empty;
  const _RankingBoard({required this.title, required this.list, required this.onTap, this.corner, this.tag, this.empty = 'Henüz koruyucu yok'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(children: [
        _WingBanner(title),
        Container(
          margin: const EdgeInsets.only(top: 0),
          padding: const EdgeInsets.only(top: 10, bottom: 34),
          decoration: const BoxDecoration(color: Color(0xFFFFA3DA), borderRadius: BorderRadius.vertical(bottom: Radius.circular(36))),
          child: list.isEmpty
              ? Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))
              : Column(children: [
                  for (var i = 0; i < list.length; i++) _row(list[i], i + 1),
                ]),
        ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> g, int rank) {
    final c = corner?.call(g);
    final t = tag?.call(g);
    return InkWell(
      onTap: () => onTap(mapOf(g['user'])),
      child: Container(
        height: 66,
        color: rank.isOdd ? const Color(0xFFFF84CE) : const Color(0xFFFFA0D8),
        child: Stack(children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                SizedBox(
                  width: 34,
                  child: rank <= 3
                      ? Fig('rank_$rank', width: 32, height: 29)
                      : Text('$rank', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19)),
                ),
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: UserAvatar(user: mapOf(g['user']), radius: 23)),
                const SizedBox(width: 8),
                Expanded(child: Text(_short((mapOf(g['user'])?['displayName'] ?? '').toString(), 13), maxLines: 1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFF21FA0), borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(fmtNumber(g['points']), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(width: 3),
                    const Icon(Icons.favorite, color: Color(0xFFFFC7E6), size: 18),
                  ]),
                ),
              ]),
            ),
          ),
          if (c != null) Positioned(right: 0, top: 0, child: c),
          if (t != null) Positioned(left: 0, bottom: 0, child: t),
        ]),
      ),
    );
  }
}

/// Satır köşesindeki küçük etiket (Seç / Sonlandır / Kaldır).
Widget _cornerTag(String text, VoidCallback onTap, {bool dark = false, bool left = false}) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 2, 10, 2),
        decoration: BoxDecoration(
          color: dark ? Colors.black : Colors.white,
          borderRadius: left ? const BorderRadius.only(topRight: Radius.circular(12)) : const BorderRadius.only(bottomLeft: Radius.circular(12)),
        ),
        child: Text(text, style: TextStyle(color: dark ? Colors.white : FigPal.pinkText, fontWeight: FontWeight.w800, fontSize: 12)),
      ),
    );

/// "Koruyucu Ol" onay penceresi.
class GuardianJoinDialog extends StatelessWidget {
  final Map<String, dynamic>? owner;
  final String cost;
  const GuardianJoinDialog({super.key, this.owner, required this.cost});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close, color: Colors.black, size: 30))),
          SizedBox(
            height: 130,
            child: Stack(alignment: Alignment.center, children: [
              const Positioned(left: 0, top: 0, child: Fig('wing', width: 130, height: 120)),
              const Positioned(right: 0, top: 0, child: Fig('wing', width: 130, height: 120, flipX: true)),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFF21FC6), width: 3)),
                child: UserAvatar(user: owner, radius: 48),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          const Text('Koruyucu Ol', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 26)),
          const SizedBox(height: 10),
          const Text(
            'Koruyucu kartı alarak bu kullanıcının koruyucusu olmak istediğinizden emin misiniz?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF444444), fontSize: 15, height: 1.3),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 190,
              height: 102,
              child: Stack(alignment: Alignment.center, children: [
                const Positioned.fill(child: Fig('rel_stage_cp', fit: BoxFit.cover)),
                const Positioned(left: 8, top: 6, child: Fig('wing', width: 86, height: 74)),
                const Positioned(right: 8, top: 6, child: Fig('wing', width: 86, height: 74, flipX: true)),
                const _ChairCircle(radius: 30),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Text('${fmtNumber(cost)} Coins', style: const TextStyle(color: Color(0xFF444444), fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 22),
          FigButton('Koruyucu Ol', height: 56, color: const Color(0xFFFF4FBF), fontSize: 26, onTap: () => Navigator.pop(context, true)),
        ]),
      ),
    );
  }
}

/// Koruyuculuk kuralları.
class GuardianRulesScreen extends StatelessWidget {
  const GuardianRulesScreen({super.key});

  static const _text = <(String, String)>[
    ('1. Koruyuculuk Nedir?', '-Koruyuculuk, kullanıcılar arasındaki yakınlığı yansıtan yepyeni bir etkileşimli özelliktir. Bir kullanıcı, gerçek sevgi koruyucu kartı hediye ederek başka bir kullanıcının koruyucusu olabilir.'),
    ('2. Koruyucu puanlar nelerdir? Onları nasıl arttırırım?', '-Koruyucu olduktan sonra koruyuculuk puanlarınızı artırmak için koruyuculuk partnerinize hediyeler gönderebilirsiniz. 1 Coins = 1 koruyucu puan'),
    ('3. Koruyucu puanı düşüşü',
        '1. Bir haftayı temel alır (her Pazartesi 00:00 ile her Pazar 23:59 arası).\n'
        '2. Bu hafta içinde hiç hediye gönderilmediyse, takip eden Pazartesi günü 00:00\'da koruyucu puanları düşecektir.\n'
        '3. Koruyucu puan >= 250 olduğunda, koruyucu puanların %20\'si azaltılacaktır.\n'
        '4. Koruyucu puanları 250\'den az olduğunda, sıfıra ulaşana kadar her seferinde 50 puan azaltılır, ardından koruyuculuk ilişkisi feshedilir.\n'
        '5. İlk hafta için koruyuculuk açan ve herhangi bir hediye göndermeyen kullanıcılar muafiyet haklarından yararlanabilir ve bir sonraki Pazartesi 00:00\'da koruyucu puanları düşürülmez.'),
    ('4. Koruyuculuk ayrıcalıkları nedir?', 'Profil resminiz, koruyuculuk ortağınızın mini profil kartında ve kişisel profil sayfasında gösterilecektir.'),
    ('5. Koruyucumu gizleyebilir miyim?',
        'Koruyuculuğum sayfasındaki "Koruyucu kabul et" seçeneğini kapatarak koruyucunuzu gizleyebilirsiniz. Koruyucu kapatıldığında, diğer kullanıcılar sizin koruyucunuz olamaz ve koruyuculuk bilgileriniz Koruyucu Sıralamasında gösterilmez.'),
    ('6. Koruyuculuğumu nasıl sonlandırabilirim?',
        'Koruyuculuğum sayfasına gidin ve sağ üst köşedeki Düzenle düğmesine dokunun. Buradan koruyucunuzu çıkarabilir ya da koruduğunuz kişiyle olan koruyuculuğunuzu sonlandırabilirsiniz.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
        body: ListView(padding: const EdgeInsets.fromLTRB(22, 8, 22, 30), children: [
          for (final (t, b) in _text) ...[
            Text(t, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 16, height: 1.5)),
            Text(b, style: const TextStyle(color: Colors.black, fontSize: 15, height: 1.55)),
            const SizedBox(height: 22),
          ],
        ]),
      ),
    );
  }
}

/// Koruyuculuğum: "Koruyucum" (koruyucularım, profilde görünecek olanı seç / çıkar) ve "Koruduğum" (koruyucusu
/// olduklarım, sonlandır). Sağ üstteki kalemle düzenleme açılır.
class MyGuardianScreen extends StatefulWidget {
  final Widget Function(String userId) profileBuilder;
  const MyGuardianScreen({super.key, required this.profileBuilder});

  @override
  State<MyGuardianScreen> createState() => _MyGuardianScreenState();
}

class _MyGuardianScreenState extends State<MyGuardianScreen> {
  int _v = 0;
  int _tab = 0;
  bool _edit = false;

  Future<void> _remove(Map<String, dynamic> u) async {
    final name = (u['displayName'] ?? '').toString();
    final mine = _tab == 0;
    if (!await confirm(context, mine ? '$name koruyucularından çıkarılsın mı?' : '$name için koruyuculuğun sonlandırılsın mı?', action: mine ? 'Kaldır' : 'Sonlandır', destructive: true) || !mounted) return;
    final r = await guard(context, () => mine ? Api.post('/api/guardians/remove/${u['id']}') : Api.post('/api/guardians/of/${u['id']}/leave'));
    if (r != null && mounted) setState(() => _v++);
  }

  Future<void> _show(Map<String, dynamic> u) async {
    final r = await guard(context, () => Api.post('/api/guardians/show/${u['id']}'));
    if (r != null && mounted) {
      toast(context, 'Profilinde artık ${u['displayName'] ?? ''} görünecek.');
      setState(() => _v++);
    }
  }

  Future<void> _toggle(bool on) async {
    final r = await guard(context, () => Api.put('/api/guardians/settings', {'enabled': on}));
    if (r != null && mounted) setState(() => _v++);
  }

  void _open(Map<String, dynamic>? u) {
    final id = u?['id']?.toString();
    if (id != null && u?['isHidden'] != true) Navigator.push(context, MaterialPageRoute(builder: (_) => widget.profileBuilder(id)));
  }

  Widget _tabBtn(String label, int i) {
    final sel = _tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _tab = i;
          _edit = false;
        }),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: sel ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF8AD8), Color(0xFFF54BC8)]) : null,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(label, style: TextStyle(color: sel ? Colors.white : FigPal.pinkText, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    );
  }

  Widget _empty(String text, String button, String hint) => Column(children: [
        const SizedBox(height: 50),
        const Fig('love_heart', width: 110, height: 100),
        const SizedBox(height: 14),
        Text(text, style: const TextStyle(color: FigPal.pinkText, fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 30),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 70),
          child: FigButton(button, height: 46, fontSize: 16, gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF8AD8), Color(0xFFF54BC8)]), onTap: () => toast(context, hint)),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(useMaterial3: true),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          title: const Text('Koruyuculuğum', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 19)),
          actions: [
            IconButton(tooltip: 'Düzenle', onPressed: () => setState(() => _edit = !_edit), icon: Icon(_edit ? Icons.check : Icons.edit)),
            IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GuardianRulesScreen())), icon: const Icon(Icons.help_outline)),
          ],
        ),
        body: AsyncBody<Map<String, dynamic>>(
          version: _v,
          load: () => Api.get('/api/guardians/mine'),
          builder: (context, d, reload) {
            final guardians = listOf(d['guardians']);
            final guarding = listOf(d['guarding']);
            final top = mapOf(d['top']);
            final shownId = d['shownId']?.toString();
            final enabled = d['enabled'] != false;
            return ListView(padding: const EdgeInsets.fromLTRB(0, 6, 0, 30), children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 34),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: const Color(0xFFFFD0EA), borderRadius: BorderRadius.circular(21), boxShadow: const [BoxShadow(color: Color(0x22FF4FA8), blurRadius: 6, offset: Offset(0, 3))]),
                child: Row(children: [_tabBtn('Koruyucum', 0), _tabBtn('Koruduğum', 1)]),
              ),
              const SizedBox(height: 14),
              if (_tab == 0) ...[
                Center(child: PairAvatars(left: Session.me.value, right: mapOf(top?['user']), rightChild: top == null ? const _ChairCircle(radius: 44) : null, size: 88)),
                if (guardians.isEmpty)
                  _empty('Şu anda hiç koruyucunuz yok', 'Bir Koruyucu Davet Et', 'Arkadaşların profilindeki koruyucu rozetine dokunup "Koruyucu Ol" diyerek koruyucun olabilir.')
                else ...[
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0x00FFB7DE), Color(0xFFFFC2E2), Color(0x00FFB7DE)]),
                      border: Border.symmetric(horizontal: BorderSide(color: Color(0xFFFF8FCB), width: 1.2)),
                    ),
                    child: Text('Koruyucu Puanları: ${fmtNumber(top?['points'] ?? 0)}', textAlign: TextAlign.center, style: const TextStyle(color: FigPal.pinkText, fontWeight: FontWeight.w700, fontSize: 18)),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(36, 14, 36, 18),
                    child: Text('Bu bölüm en çok koruyucu puanına sahip kullanıcı içindir. Profil sahibi dilerse değiştirebilir.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFF0479E), fontSize: 12.5, height: 1.6)),
                  ),
                  _RankingBoard(
                    title: 'Koruyucu Sıralaması',
                    list: guardians,
                    onTap: _open,
                    corner: _edit ? (g) => mapOf(g['user'])?['id']?.toString() == shownId ? null : _cornerTag('Seç', () => _show(mapOf(g['user']) ?? {})) : null,
                    tag: _edit ? (g) => _cornerTag('Kaldır', () => _remove(mapOf(g['user']) ?? {}), dark: true, left: true) : null,
                  ),
                ],
                const SizedBox(height: 18),
                SwitchListTile(
                  value: enabled,
                  activeThumbColor: FigPal.pink,
                  onChanged: _toggle,
                  title: const Text('Koruyucu kabul et', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Kapalıyken kimse koruyucun olamaz ve koruyucuların gizlenir.', style: TextStyle(color: FigPal.grey, fontSize: 12)),
                ),
              ] else ...[
                if (guarding.isEmpty)
                  _empty('Şu anda kimseyi korumuyorsunuz', 'Birinin Koruyucusu Ol', 'Bir kullanıcının profilindeki koruyucu rozetine dokunup "Koruyucu Ol" de.')
                else ...[
                  const SizedBox(height: 16),
                  _RankingBoard(
                    title: 'Koruyucu Olduklarım',
                    list: guarding,
                    onTap: _open,
                    empty: 'Henüz kimseyi korumuyorsun',
                    corner: _edit ? (g) => _cornerTag('Sonlandır', () => _remove(mapOf(g['user']) ?? {})) : null,
                  ),
                ],
              ],
            ]);
          },
        ),
      ),
    );
  }
}
