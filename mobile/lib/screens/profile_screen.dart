import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api.dart';
import '../services/background_service.dart';
import '../services/auth_service.dart';
import '../services/session.dart';
import '../services/inbox_service.dart';
import '../widgets/anim_asset.dart';
import '../widgets/app_theme.dart';
import '../widgets/lucky_bag.dart';
import '../widgets/common.dart';
import 'admin_screen.dart';
import 'agency_screen.dart';
import 'dealer_screen.dart';
import 'edit_profile_screen.dart';
import 'family_screen.dart';
import 'social_screens.dart';
import 'store_screens.dart';
import 'income_screens.dart';
import 'login_screen.dart';
import 'misc_screens.dart';
import 'support_screens.dart';
import 'user_screens.dart';
import 'wip_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _version = 0;

  void _reload() => setState(() => _version++);

  Future<Map<String, dynamic>> _load() async {
    final r = await Api.get('/api/me');
    final profile = mapOf(r['user']) ?? {};
    Session.me.value = profile;
    Inbox.refreshBadges();
    bool dealer = false;
    try {
      await Api.get('/api/dealer/me');
      dealer = true;
    } catch (_) {/* bayi değil */}
    return {'profile': profile, 'dealer': dealer};
  }

  Future<void> _goLogin() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _changePassword() async {
    final current = await askText(context, 'Mevcut şifre', obscure: true);
    if (current == null || !mounted) return;
    final next = await askText(context, 'Yeni şifre (en az 6 karakter)', obscure: true);
    if (next == null || !mounted) return;
    final r = await guard(context, () => Api.post('/api/me/password', {'currentPassword': current, 'newPassword': next}));
    if (r != null) {
      if (mounted) toast(context, 'Şifre değişti. Lütfen yeniden giriş yapın.');
      await _goLogin();
    }
  }

  Future<void> _deleteAccount() async {
    if (!await confirm(context, 'Hesabınız ve kişisel verileriniz kalıcı olarak silinir. Bu işlem geri alınamaz.', action: 'Devam')) return;
    if (!mounted) return;
    final password = await askText(context, 'Onay için şifrenizi girin', obscure: true);
    if (password == null || !mounted) return;
    final r = await guard(context, () => Api.delete('/api/me', {'password': password}));
    if (r != null) await _goLogin();
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _reload();
  }

  Future<void> _openSettings(Map<String, dynamic> p, bool isDealer) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setLocal) => Scaffold(
            appBar: AppBar(title: const Text('Ayarlar')),
            body: ListView(children: [
              ListTile(leading: const Icon(Icons.edit), title: const Text('Profili düzenle'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const EditProfileScreen())),
              ListTile(leading: const Icon(Icons.block), title: const Text('Engellenen kullanıcılar'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const BlockedUsersScreen())),
              ListTile(leading: const Icon(Icons.receipt_long), title: const Text('Cüzdan ve Elmas Bozdurma'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const WalletScreen())),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_off),
                title: const Text('Gizli kullanıcı modu'),
                subtitle: const Text('Odalarda adınız ve fotoğrafınız gizlenir, aramada çıkmazsınız.'),
                value: p['isHidden'] == true,
                onChanged: (v) async {
                  await guard(context, () => Api.patch('/api/me', {'isHidden': v}));
                  p['isHidden'] = v;
                  setLocal(() {});
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('Arka plan ve balon izinleri'),
                subtitle: const Text('Oda arka planda açık kalsın, diğer uygulamaların üzerinde balon görünsün'),
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('asked_battery');
                  await prefs.remove('asked_overlay');
                  if (!context.mounted) return;
                  await BackgroundService.instance.ensurePermissions((msg, action) => confirm(context, msg, action: action));
                },
              ),
              ListTile(leading: const Icon(Icons.bug_report_outlined), title: const Text('Hata kaydı'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const ErrorLogScreen())),
              ListTile(leading: const Icon(Icons.lock_reset), title: const Text('Şifre değiştir'), onTap: _changePassword),
              ListTile(leading: const Icon(Icons.logout), title: const Text('Çıkış yap'), onTap: _goLogin),
              ListTile(leading: const Icon(Icons.delete_forever, color: Colors.redAccent), title: const Text('Hesabı sil', style: TextStyle(color: Colors.redAccent)), onTap: _deleteAccount),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _copyId(Map<String, dynamic> p) async {
    await Clipboard.setData(ClipboardData(text: '${p['publicId'] ?? ''}'));
    if (mounted) toast(context, 'ID kopyalandı.');
  }

  String? _frameOf(Map<String, dynamic> p) {
    final items = p['equipped'];
    if (items is! List) return null;
    for (final i in items) {
      if (i is Map && i['itemType'] == 'frame') return Api.absoluteUrl(i['assetUrl'] as String?);
    }
    return null;
  }

  Widget _header(Map<String, dynamic> p) {
    final frame = _frameOf(p);
    final wip = mapOf(p['wip']);
    final features = mapOf(wip?['features']);
    return Column(children: [
      SizedBox(
        height: 190,
        child: Stack(alignment: Alignment.center, children: [
          Positioned(
            top: 18,
            child: Stack(alignment: Alignment.center, children: [
              UserAvatar(user: p, radius: 54),
              if (frame != null) IgnorePointer(child: SizedBox(width: 190, height: 190, child: AnimAsset(url: frame, repeat: true, cache: false))),
            ]),
          ),
        ]),
      ),
      UserName(
        user: {'displayName': p['displayName'], 'wipLevel': wip?['level'], 'nameColor': features?['nameColor']},
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      InkWell(
        onTap: () => _copyId(p),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('ID: ${p['publicId'] ?? '-'}', style: const TextStyle(color: Pal.textDim, fontSize: 15)),
            const SizedBox(width: 6),
            const Icon(Icons.copy, size: 14, color: Pal.textDim),
          ]),
        ),
      ),
    ]);
  }

  Widget _statsRow(Map<String, dynamic> p) {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: Inbox.badges,
      builder: (context, b, _) {
        Widget stat(String label, dynamic value, int badge, VoidCallback onTap) => Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(children: [
                    FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3))),
                    const SizedBox(height: 4),
                    Badge(
                      label: Text('$badge'),
                      isLabelVisible: badge > 0,
                      alignment: Alignment.topRight,
                      offset: const Offset(10, -8),
                      child: Text(fmtNumber(value), style: const TextStyle(color: Pal.cyan, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
              ),
            );
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Pal.outline)),
          child: Row(children: [
            stat('TAKİP EDİLEN', p['following'], 0, () => _open(UserListScreen(title: 'Takip edilenler', path: '/api/users/${p['id']}/following'))),
            stat('FANLAR', p['followers'], b['followers'] ?? 0, () async {
              await _open(UserListScreen(title: 'Fanlar', path: '/api/users/${p['id']}/followers'));
              Inbox.markSeen('followers');
            }),
            stat('ZİYARETÇİLER', p['visitorCount'], b['visitors'] ?? 0, () async {
              await _open(const VisitorsScreen());
              Inbox.markSeen('visitors');
            }),
            stat('ARKADAŞLAR', p['friends'], b['friends'] ?? 0, () => _open(const FriendsScreen())),
          ]),
        );
      },
    );
  }

  Widget _moneyCards(Map<String, dynamic> p) {
    Widget card(List<Color> colors, Widget icon, dynamic value, String label, Color textColor, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              height: 62,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(colors: colors)),
              child: Row(children: [
                icon,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FittedBox(fit: BoxFit.scaleDown, child: Text(fmtNumber(value), style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w900))),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: TextStyle(color: textColor, fontSize: 12.5, fontWeight: FontWeight.w600))),
                  ]),
                ),
                Icon(Icons.chevron_right, color: textColor),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Row(children: [
        card(const [Color(0xFFFFE259), Color(0xFFFFC107)], const Icon(Icons.monetization_on, color: Color(0xFFB26A00), size: 34), p['coins'], 'Coins Yükleme', const Color(0xFF3B2A00), () => _open(const CoinsCenterScreen())),
        const SizedBox(width: 10),
        card(const [Color(0xFF5E6B8C), Color(0xFF8A94AD)], const Icon(Icons.diamond, color: Colors.cyanAccent, size: 32), p['diamonds'], 'Gelir Merkezi', Colors.white, () => _open(const IncomeCenterScreen())),
      ]),
    );
  }

  Widget _quickTiles(Map<String, dynamic> p) {
    final wip = mapOf(p['wip']);
    Widget tile(IconData icon, Color color, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.08)])),
                  child: Icon(icon, size: 32, color: color),
                ),
                const SizedBox(height: 6),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(children: [
        tile(Icons.military_tech, Colors.amber, 'Leveller', () => _open(const LevelsScreen())),
        tile(Icons.groups, Colors.orangeAccent, 'Aile', () => _open(Scaffold(appBar: AppBar(title: const Text('Aile')), body: const FamilyScreen()))),
        tile(Icons.workspace_premium, Colors.lightBlueAccent, wip == null ? 'WIP' : 'WIP ${wip['level']}', () => _open(const WipScreen())),
        tile(Icons.checkroom, Colors.pinkAccent, 'Görünüm', () => _open(const AppearanceScreen())),
      ]),
    );
  }

  Widget _menu(Map<String, dynamic> p, bool isDealer) {
    final agencyOwned = mapOf(p['agencyOwned']);
    final broadcasterStatus = p['broadcasterStatus']?.toString();
    final isBroadcaster = broadcasterStatus == 'approved' || broadcasterStatus == 'pending';
    Widget row(IconData icon, Color color, String title, VoidCallback onTap, {String? sub}) => ListTile(
          leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Pal.outline)),
      child: Column(children: [
        row(Icons.storefront, Colors.orangeAccent, 'Mağaza', () => _open(const StoreScreen())),
        // Yayıncı Merkezi: ajans sahibi dışındaki herkeste (yayıncılar ve başvuracaklar)
        if (agencyOwned == null)
          row(Icons.podcasts, Colors.pinkAccent, isBroadcaster ? 'Yayıncı Merkezi' : 'Yayıncı Ol', () => _open(const AgencyScreen(mode: 'broadcaster')),
              sub: isBroadcaster ? (broadcasterStatus == 'pending' ? 'Başvurunuz inceleniyor' : null) : 'Başvur veya ajans kur'),
        // Ajans Merkezi: yalnızca ajans sahibi
        if (agencyOwned != null) row(Icons.business, Colors.lightBlueAccent, 'Ajans Merkezi', () => _open(const AgencyScreen(mode: 'agency')), sub: '${agencyOwned['name']} · ${agencyOwned['status']}'),
        row(Icons.task_alt, Colors.greenAccent, 'Günlük Görevler', () => showDailySheet(context)),
        if (isDealer) row(Icons.store_mall_directory, Colors.tealAccent, 'Bayi paneli', () => _open(const DealerScreen())),
        if (Session.isStaff) row(Icons.admin_panel_settings, Colors.redAccent, Session.isAdmin ? 'Yönetim paneli' : 'Yardımcı admin paneli', () => _open(const AdminScreen())),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Map<String, dynamic>>(
      key: ValueKey(_version),
      load: _load,
      builder: (context, data, reload) {
        final p = mapOf(data['profile']) ?? {};
        final isDealer = data['dealer'] == true;
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  IconButton(tooltip: 'Müşteri hizmetleri', icon: const Icon(Icons.headset_mic_outlined), onPressed: () => _open(const CustomerServiceScreen())),
                  IconButton(tooltip: 'Profili düzenle', icon: const Icon(Icons.edit_outlined), onPressed: () => _open(const EditProfileScreen())),
                ]),
              ),
            ),
            _header(p),
            _statsRow(p),
            _moneyCards(p),
            _quickTiles(p),
            _menu(p, isDealer),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Pal.outline)),
              child: ListTile(
                leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: Pal.cyan.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.settings, color: Pal.cyan)),
                title: const Text('Ayarlar', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openSettings(p, isDealer),
              ),
            ),
          ]),
        );
      },
    );
  }
}
