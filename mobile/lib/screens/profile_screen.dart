import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import 'admin_screen.dart';
import 'agency_screen.dart';
import 'dealer_screen.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import 'misc_screens.dart';
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

  Future<void> _toggleHidden(bool v) async {
    await guard(context, () => Api.patch('/api/me', {'isHidden': v}));
    if (mounted) _reload();
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

  void _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Map<String, dynamic>>(
      key: ValueKey(_version),
      load: _load,
      builder: (context, data, reload) {
        final p = mapOf(data['profile']) ?? {};
        final isDealer = data['dealer'] == true;
        final agencyOwned = mapOf(p['agencyOwned']);
        final broadcasterStatus = p['broadcasterStatus'];
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(children: [
            ProfileHeader(
              p: p,
              onFollowers: () => _open(UserListScreen(title: 'Takipçiler', path: '/api/users/${p['id']}/followers')),
              onFollowing: () => _open(UserListScreen(title: 'Takip edilenler', path: '/api/users/${p['id']}/following')),
              onVisitors: () => _open(const VisitorsScreen()),
              actions: [
                FilledButton.tonalIcon(onPressed: () => _open(const EditProfileScreen()), icon: const Icon(Icons.edit, size: 16), label: const Text('Düzenle')),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: _Balance(icon: Icons.monetization_on, color: Colors.amber, label: 'Coin', value: p['coins'])),
                const SizedBox(width: 12),
                Expanded(child: _Balance(icon: Icons.diamond, color: Colors.cyanAccent, label: 'Diamond', value: p['diamonds'])),
              ]),
            ),
            ListTile(leading: const Icon(Icons.workspace_premium), title: const Text('WIP üyelik'), subtitle: Text(p['wip'] == null ? 'Aktif üyelik yok' : (mapOf(p['wip'])?['name'] ?? '').toString()), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const WipScreen())),
            ListTile(leading: const Icon(Icons.inventory_2_outlined), title: const Text('Envanter'), subtitle: const Text('Çerçeve, giriş efekti ve rozetler'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const InventoryScreen())),
            ListTile(leading: const Icon(Icons.block), title: const Text('Engellenen kullanıcılar'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const BlockedUsersScreen())),
            ListTile(leading: const Icon(Icons.receipt_long), title: const Text('Cüzdan geçmişi'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const WalletScreen())),
            ListTile(
              leading: const Icon(Icons.podcasts),
              title: const Text('Ajans ve yayıncı'),
              subtitle: Text(agencyOwned != null ? 'Ajans sahibi · ${agencyOwned['status']}' : (broadcasterStatus != null ? 'Yayıncı başvurusu: $broadcasterStatus' : 'Yayıncı ol veya ajans kur')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(const AgencyScreen()),
            ),
            if (isDealer) ListTile(leading: const Icon(Icons.storefront), title: const Text('Bayi paneli'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const DealerScreen())),
            if (Session.isStaff) ListTile(leading: const Icon(Icons.admin_panel_settings), title: Text(Session.isAdmin ? 'Yönetim paneli' : 'Yardımcı admin paneli'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(const AdminScreen())),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off),
              title: const Text('Gizli kullanıcı modu'),
              subtitle: const Text('Odalarda adınız ve fotoğrafınız gizlenir, aramada çıkmazsınız.'),
              value: p['isHidden'] == true,
              onChanged: _toggleHidden,
            ),
            const Divider(),
            ListTile(leading: const Icon(Icons.lock_reset), title: const Text('Şifre değiştir'), onTap: _changePassword),
            ListTile(leading: const Icon(Icons.logout), title: const Text('Çıkış yap'), onTap: _goLogin),
            ListTile(leading: const Icon(Icons.delete_forever, color: Colors.redAccent), title: const Text('Hesabı sil', style: TextStyle(color: Colors.redAccent)), onTap: _deleteAccount),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }
}

class _Balance extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final dynamic value;
  const _Balance({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                Text(fmtNumber(value), style: Theme.of(context).textTheme.titleMedium),
              ]),
            ),
          ]),
        ),
      );
}
