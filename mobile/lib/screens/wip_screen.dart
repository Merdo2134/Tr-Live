import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import '../widgets/entrance_strip.dart';

/// WIP ayrıcalıkları (Yoho VIP ekranı gibi): üstte kademe seçici (WIP 1–10 + SWIP), seçilen kademenin
/// önizlemesi (çerçeve, isim efekti, sohbet balonu, giriş aracı), ayrıcalık ızgarası ve paketler.
class WipScreen extends StatefulWidget {
  const WipScreen({super.key});

  @override
  State<WipScreen> createState() => _WipScreenState();
}

/// Sunucudaki özellik anahtarı → simge, başlık.
const List<(String, IconData, String)> _perks = [
  ('viewVisitors', Icons.visibility_outlined, 'Ziyaretçileri görme'),
  ('vipGifts', Icons.card_giftcard, 'Vip hediyeler'),
  ('muteImmunity', Icons.volume_up_outlined, 'Susturulamaz'),
  ('profileEffect', Icons.auto_awesome, 'Profil ışık efekti'),
  ('kickImmunity', Icons.shield_outlined, 'Odadan atılamaz'),
  ('customRoomTheme', Icons.wallpaper, 'Özel oda teması'),
  ('invisibleVisit', Icons.visibility_off_outlined, 'Gizli ziyaret'),
  ('animatedAvatar', Icons.gif_box_outlined, 'Hareketli profil fotoğrafı'),
  ('ghostMode', Icons.blur_on, 'Hayalet mod'),
];

class _WipScreenState extends State<WipScreen> {
  int _version = 0;
  int? _selected;

  Future<Map<String, dynamic>> _load() async {
    final tiers = await Api.get('/api/wip/tiers');
    final mine = await Api.get('/api/wip');
    return {'tiers': listOf(tiers['tiers']), 'current': mapOf(mine['wip'])};
  }

  Future<void> _buy(Map<String, dynamic> tier, Map<String, dynamic> plan, Map<String, dynamic>? current) async {
    final price = fmtNumber(plan['priceCoins']);
    final extending = current != null && current['level'] == tier['level'];
    final msg = extending
        ? '${tier['name']} süreniz ${plan['durationDays']} gün uzatılacak. $price Coin harcanacak.'
        : '${tier['name']} satın alınacak (${plan['durationDays']} gün). $price Coin harcanacak.';
    if (!await confirm(context, msg, action: 'Satın al')) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.postOnce('/api/wip/purchase', {'planId': plan['id']}));
    if (r == null || !mounted) return;
    Session.setCoins((r['balance'] ?? Session.coins).toString());
    toast(context, '${wipLabel(wipLevelOf(tier['level']))} etkinleştirildi.');
    setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(title: const Text('WIP Ayrıcalıkları'), backgroundColor: const Color(0xFF0B1220)),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: _load,
        builder: (context, data, reload) {
          final tiers = listOf(data['tiers']).where((t) => WipStyle.of(wipLevelOf(t['level'])) != null).toList();
          if (tiers.isEmpty) return const Center(child: Text('WIP kademesi tanımlı değil.'));
          final current = mapOf(data['current']);
          final currentLevel = wipLevelOf(current?['level']);
          final levels = [for (final t in tiers) wipLevelOf(t['level'])!];
          var sel = _selected ?? currentLevel ?? levels.first;
          if (!levels.contains(sel)) sel = levels.first;
          final tier = tiers.firstWhere((t) => wipLevelOf(t['level']) == sel);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              _levelBar(levels, sel, currentLevel),
              _hero(tier, sel, current, currentLevel),
              _perkGrid(tiers, tier, sel),
              _plans(tier, sel, current, currentLevel),
              if (WipStyle.of(sel)!.isSwip) _ghostNote(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Ayrıcalıklar birikimlidir: üst kademe alttakilerin hepsini içerir. Takılı bir mağaza çerçeveniz varsa koltukta o görünür.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _levelBar(List<int> levels, int sel, int? currentLevel) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final l in levels)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => setState(() => _selected = l),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: l == sel ? LinearGradient(colors: WipStyle.of(l)!.gradient) : null,
                    color: l == sel ? null : Colors.white10,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: l == currentLevel ? Colors.white : Colors.transparent, width: 1.2),
                  ),
                  child: Text(
                    wipLabel(l),
                    style: TextStyle(color: Colors.white, fontWeight: l == sel ? FontWeight.w900 : FontWeight.w600, shadows: const [Shadow(color: Colors.black54, blurRadius: 2)]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hero(Map<String, dynamic> tier, int sel, Map<String, dynamic>? current, int? currentLevel) {
    final s = WipStyle.of(sel)!;
    final f = mapOf(tier['features']) ?? const <String, dynamic>{};
    final me =Session.me.value ?? const <String, dynamic>{};
    final myName = (me['displayName'] ?? 'Sen').toString();
    final nameColor = parseColor(f['nameColor'] as String?) ?? s.color;
    String status;
    if (currentLevel == sel) {
      final end = DateTime.tryParse('${current?['expiresAt']}')?.toLocal();
      status = end == null ? 'Aktif' : 'Aktif · bitiş ${end.day.toString().padLeft(2, '0')}.${end.month.toString().padLeft(2, '0')}.${end.year}';
    } else if (currentLevel != null && currentLevel > sel) {
      status = 'Daha yüksek bir kademedesiniz (${wipLabel(currentLevel)})';
    } else {
      status = 'Henüz sahip değilsiniz';
    }
    const avatarR = 30.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [for (final c in s.bubble) c.withValues(alpha: 0.95), const Color(0xFF0B1220)],
        ),
        border: Border.all(color: s.color.withValues(alpha: 0.6)),
        boxShadow: [BoxShadow(color: s.color.withValues(alpha: 0.25), blurRadius: 16)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          WipChip(level: sel),
          const SizedBox(width: 8),
          Expanded(child: Text('${tier['name'] ?? s.label}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
        ]),
        const SizedBox(height: 4),
        Text(status, style: TextStyle(color: currentLevel == sel ? Colors.greenAccent : Colors.white70, fontSize: 12.5)),
        const SizedBox(height: 14),
        // Önizleme: çerçeve + isim efekti
        Row(children: [
          SizedBox(
            width: avatarR * 2.8,
            height: avatarR * 2.8,
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              if (f['profileEffect'] == true) Positioned.fill(child: IgnorePointer(child: WipAura(level: sel))),
              UserAvatar(user: me, radius: avatarR),
              Positioned.fill(child: IgnorePointer(child: WipFrame(level: sel, avatarRadius: avatarR))),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: WipNameText(myName, level: sel, color: nameColor, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                WipChip(level: sel),
              ]),
              const SizedBox(height: 4),
              Text('${s.nameFxText} · ${s.animatedFrame ? 'hareketli çerçeve' : 'çerçeve'}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        // Önizleme: sohbet balonu
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          UserAvatar(user: me, radius: 14),
          const SizedBox(width: 8),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: WipBubble(
                level: sel,
                fallback: const Color(0x8C13285A),
                child: Text('Merhaba! Bu benim ${s.label} sohbet balonum ${s.emblem}'.trim(), style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // Önizleme: giriş aracı
        Text('Giriş aracı: ${s.vehicle} ${s.vehicleName}', style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 64,
            color: Colors.black26,
            alignment: Alignment.center,
            child: EntranceBanner(key: ValueKey('entrance-$sel'), user: {'displayName': myName, 'wipLevel': sel}, loop: true),
          ),
        ),
      ]),
    );
  }

  Widget _perkGrid(List<Map<String, dynamic>> tiers, Map<String, dynamic> tier, int sel) {
    final s = WipStyle.of(sel)!;
    final f = mapOf(tier['features']) ?? const <String, dynamic>{};
    // Her ayrıcalığın açıldığı ilk kademe (kilitli kutuda "WIP n" yazar).
    int? minLevel(String key) {
      for (final t in tiers) {
        if (mapOf(t['features'])?[key] == true) return wipLevelOf(t['level']);
      }
      return null;
    }

    final tiles = <Widget>[
      _perkTile(s, Icons.workspace_premium, '${s.label} rozeti', true, null),
      _perkTile(s, Icons.text_fields, s.nameFxText, true, null),
      _perkTile(s, Icons.chat_bubble_outline, 'Özel sohbet balonu', true, null),
      _perkTile(s, Icons.radio_button_checked, s.animatedFrame ? 'Hareketli çerçeve' : 'Avatar çerçevesi', true, null),
      _perkTile(s, Icons.directions_car_filled_outlined, 'Giriş aracı: ${s.vehicleName}', true, null),
      _perkTile(s, Icons.meeting_room_outlined, 'Aynı anda ${f['maxRooms'] ?? 1} oda', true, null),
      for (final p in _perks)
        if (minLevel(p.$1) != null) _perkTile(s, p.$2, p.$3, f[p.$1] == true, minLevel(p.$1)),
    ];
    final unlocked = 6 + _perks.where((p) => f[p.$1] == true).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Ayrıcalıklar  $unlocked/${tiles.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white)),
        ),
        LayoutBuilder(builder: (context, box) {
          const gap = 8.0;
          final w = (box.maxWidth - gap * 2) / 3;
          return Wrap(spacing: gap, runSpacing: gap, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
        }),
      ]),
    );
  }

  Widget _perkTile(WipStyle s, IconData icon, String title, bool on, int? from) {
    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: on ? s.color.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: on ? s.color.withValues(alpha: 0.45) : Colors.white12),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: on ? LinearGradient(colors: s.gradient) : null, color: on ? null : Colors.white12),
            child: Icon(icon, size: 20, color: on ? Colors.white : Colors.white38),
          ),
          if (!on) const Positioned(right: -4, bottom: -2, child: Icon(Icons.lock, size: 14, color: Colors.white54)),
        ]),
        const SizedBox(height: 6),
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, height: 1.15, color: on ? Colors.white : Colors.white54)),
        if (!on && from != null) Text(wipLabel(from), style: const TextStyle(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _plans(Map<String, dynamic> tier, int sel, Map<String, dynamic>? current, int? currentLevel) {
    final plans = listOf(tier['plans']);
    final s = WipStyle.of(sel)!;
    final lower = currentLevel != null && currentLevel > sel;
    if (plans.isEmpty) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('Bu kademe için satışta paket yok.', style: TextStyle(color: Colors.white54)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(children: [
        for (final plan in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: lower ? null : () => _buy(tier, plan, current),
              child: Opacity(
                opacity: lower ? 0.45 : 1,
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: s.gradient), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${plan['durationDays']} gün · ${fmtNumber(plan['priceCoins'])} Coin',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, shadows: [Shadow(color: Colors.black54, blurRadius: 3)]),
                      ),
                    ),
                    Text(
                      currentLevel == sel ? 'Uzat' : 'Satın al',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black54, blurRadius: 3)]),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _ghostNote() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1A1033), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x66C9B8FF))),
      child: const Text(
        '👻 Hayalet mod (yalnızca SWIP): Profil → Ayarlar → "Hayalet mod" ile açıp kapatırsınız. Açıkken odaya girişiniz duyurulmaz, '
        'dinleyici listesinde ve kişi sayısında görünmezsiniz, çevrimiçi görünmezsiniz, ziyaretleriniz iz bırakmaz. '
        'Mikrofona çıkınca, yazınca veya hediye gönderince görünürsünüz.',
        style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
      ),
    );
  }
}
