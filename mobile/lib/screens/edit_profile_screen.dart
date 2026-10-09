import 'dart:io' show File;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../widgets/common.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _bio;
  late final TextEditingController _country;
  late final TextEditingController _city;
  String? _gender;
  String? _birthDate;
  String _whoCanDm = 'everyone';
  bool _saving = false;
  bool _uploading = false;

  Map<String, dynamic> get _me => Session.me.value ?? {};

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: (_me['displayName'] ?? '').toString());
    _bio = TextEditingController(text: (_me['bio'] ?? '').toString());
    _country = TextEditingController(text: (_me['country'] ?? '').toString());
    _city = TextEditingController(text: (_me['city'] ?? '').toString());
    _gender = _me['gender'] as String?;
    _birthDate = _me['birthDate'] as String?;
    _whoCanDm = (_me['whoCanDm'] ?? 'everyone').toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _country.dispose();
    _city.dispose();
    super.dispose();
  }

  String? _mime(List<int> b) {
    if (b.length > 12 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    if (b.length > 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) return 'image/gif';
    return null;
  }

  Future<void> _upload(bool cover) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: cover ? 1600 : 1024, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final mime = _mime(bytes);
    if (!mounted) return;
    if (mime == null) return toast(context, 'Yalnızca png, jpeg veya webp yüklenebilir.', error: true);
    if (bytes.length > 3 * 1024 * 1024) return toast(context, 'Görsel 3 MB’tan küçük olmalı.', error: true);
    setState(() => _uploading = true);
    final r = await guard(context, () => Api.putBytes(cover ? '/api/me/cover' : '/api/me/avatar', bytes, mime));
    if (r != null) await guard(context, Session.refresh);
    if (mounted) setState(() => _uploading = false);
  }

  /// WIP 5: hareketli profil fotoğrafı. Dosya olduğu gibi gönderilir (yeniden sıkıştırılırsa hareket kaybolur).
  Future<void> _uploadAnimated() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['gif', 'webp']);
    final path = r?.files.first.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    final mime = _mime(bytes);
    if (!mounted) return;
    if (mime == null || (mime != 'image/gif' && mime != 'image/webp')) return toast(context, 'Hareketli fotoğraf için gif veya animasyonlu webp seçin.', error: true);
    if (bytes.length > 5 * 1024 * 1024) return toast(context, 'Hareketli fotoğraf 5 MB’tan küçük olmalı.', error: true);
    setState(() => _uploading = true);
    final res = await guard(context, () => Api.putBytes('/api/me/avatar', bytes, mime));
    if (res != null) await guard(context, Session.refresh);
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_birthDate ?? '') ?? DateTime(now.year - 20, 1, 1);
    final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year - 100), lastDate: DateTime(now.year - 13, now.month, now.day));
    if (d != null) {
      setState(() => _birthDate = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return toast(context, 'Görünen ad boş olamaz.', error: true);
    setState(() => _saving = true);
    final r = await guard(context, () async {
      await Api.patch('/api/me', {
        'displayName': _name.text.trim(),
        'bio': _bio.text.trim(),
        'country': _country.text.trim(),
        'city': _city.text.trim(),
        'gender': _gender,
        'birthDate': _birthDate,
        'whoCanDm': _whoCanDm,
      });
      await Session.refresh();
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (r == true) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profili düzenle'), actions: [
        TextButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Kaydet')),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: Session.me,
          builder: (_, me, __) => Row(children: [
            UserAvatar(user: me, radius: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: _uploading ? null : () => _upload(false), icon: const Icon(Icons.photo_camera), label: const Text('Fotoğraf')),
                OutlinedButton.icon(onPressed: _uploading ? null : () => _upload(true), icon: const Icon(Icons.panorama), label: const Text('Kapak')),
                OutlinedButton.icon(onPressed: _uploading ? null : _uploadAnimated, icon: const Icon(Icons.gif_box), label: const Text('Hareketli (WIP 5)')),
              ]),
            ),
          ]),
        ),
        if (_uploading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        const SizedBox(height: 16),
        TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(labelText: 'Görünen ad', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _bio, maxLength: 300, maxLines: 3, decoration: const InputDecoration(labelText: 'Hakkında', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _country, maxLength: 60, decoration: const InputDecoration(labelText: 'Ülke', border: OutlineInputBorder()))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _city, maxLength: 60, decoration: const InputDecoration(labelText: 'Şehir', border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 8),
        const Text('Cinsiyet'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in const {'male': 'Erkek', 'female': 'Kadın', 'other': 'Diğer'}.entries)
            ChoiceChip(label: Text(e.value), selected: _gender == e.key, onSelected: (_) => setState(() => _gender = e.key)),
          ChoiceChip(label: const Text('Belirtmek istemiyorum'), selected: _gender == null, onSelected: (_) => setState(() => _gender = null)),
        ]),
        const SizedBox(height: 12),
        const Text('Bana kimler özel mesaj gönderebilir?'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in const {'everyone': 'Herkes', 'following': 'Takip ettiklerim', 'nobody': 'Hiç kimse'}.entries)
            ChoiceChip(label: Text(e.value), selected: _whoCanDm == e.key, onSelected: (_) => setState(() => _whoCanDm = e.key)),
        ]),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cake),
          title: Text(_birthDate == null ? 'Doğum tarihi seç' : 'Doğum tarihi: $_birthDate'),
          trailing: _birthDate == null ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _birthDate = null)),
          onTap: _pickBirthDate,
        ),
      ]),
    );
  }
}
