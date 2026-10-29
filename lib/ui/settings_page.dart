import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../services/cobalt.dart';
import '../state/saver_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// Set by CI for each build (1.2.<build number>), so every release shows a new version.
const kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.2.0');

const kCobaltCompose = '''services:
  cobalt:
    image: ghcr.io/imputnet/cobalt:10
    restart: unless-stopped
    ports:
      - "9000:9000"
    environment:
      API_URL: "http://YOUR-SERVER-IP:9000/"''';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _server = TextEditingController(text: context.read<SaverState>().server);
  late final _key = TextEditingController(text: context.read<SaverState>().apiKey);
  String? _status;
  bool _ok = false, _testing = false;
  bool _picking = false;
  String? _folderError;

  Future<void> _setLocation(Future<String?> Function() change) async {
    setState(() {
      _picking = true;
      _folderError = null;
    });
    final err = await change();
    if (mounted) {
      setState(() {
        _picking = false;
        _folderError = err;
      });
    }
  }

  Widget _locationCard(SaverState s, Ra7al c) {
    Widget option(SaveLocation l, IconData icon, String title, String sub, {VoidCallback? onTap}) {
      final on = s.saveLocation == l;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _picking ? null : (onTap ?? () => _setLocation(() => s.setSaveLocation(l))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: on ? c.accent : c.faint),
            const SizedBox(width: 10),
            Icon(icon, color: on ? c.accent : c.muted, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                Text(sub, style: TextStyle(color: c.faint, fontSize: 12)),
              ]),
            ),
          ]),
        ),
      );
    }

    final showPath = s.saveLocation != SaveLocation.ask && s.saveFolder.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tx('موقع حفظ الملفات', 'Where files are saved'), style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      option(
        SaveLocation.app,
        Icons.lock_outline_rounded,
        tx('داخل التطبيق', 'Inside the app'),
        s.canPickFolder
            ? tx('مجلد خاص بالتطبيق (الافتراضي)', 'The app’s private folder (default)')
            : tx('تجدها أيضاً في تطبيق «الملفات» ← على الـ iPhone ← RA7AL SAVER', 'Also in the Files app → On My iPhone → RA7AL SAVER'),
      ),
      if (s.canPickFolder) ...[
        option(SaveLocation.downloads, Icons.download_rounded, tx('مجلد التنزيلات', 'Downloads folder'),
            tx('مجلد «RA7AL» داخل التنزيلات', 'A “RA7AL” folder inside Downloads')),
        option(
          SaveLocation.custom,
          Icons.folder_open_rounded,
          tx('مجلد أختاره بنفسي…', 'A folder I choose…'),
          s.customPath.isEmpty ? tx('اضغط لاختيار المجلد', 'Tap to choose the folder') : s.customPath,
          onTap: () => _setLocation(s.pickSaveFolder),
        ),
      ] else
        option(SaveLocation.ask, Icons.drive_folder_upload_rounded, tx('اسألني أين أحفظ بعد كل تحميل', 'Ask me where to save after each download'),
            tx('تختار المجلد في «الملفات» أو iCloud، وتبقى نسخة في «ملفاتي»', 'Pick a folder in Files or iCloud; a copy stays in My files')),
      if (_picking) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator(minHeight: 3)),
      if (showPath) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: c.input, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(Icons.folder_rounded, size: 18, color: c.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(s.saveFolder,
                  textDirection: TextDirection.ltr, style: TextStyle(color: c.muted, fontSize: 12, fontFamily: 'monospace')),
            ),
            if (s.saveLocation == SaveLocation.custom)
              TextButton(onPressed: _picking ? null : () => _setLocation(s.pickSaveFolder), child: Text(tx('تغيير', 'Change'))),
          ]),
        ),
      ],
      if (_folderError != null || s.locationWarning != null) ...[
        const SizedBox(height: 8),
        Text(_folderError ?? s.locationWarning!, style: TextStyle(color: c.live, fontSize: 12, height: 1.5)),
      ],
      Divider(height: 24, color: c.line),
    ]);
  }

  Future<void> _test() async {
    final s = context.read<SaverState>();
    setState(() {
      _testing = true;
      _status = null;
    });
    await s.setServer(_server.text, _key.text);
    try {
      final v = await Cobalt(s.server, apiKey: s.apiKey).ping();
      setState(() {
        _ok = true;
        _status = tx('متصل ✓ (cobalt $v)', 'Connected ✓ (cobalt $v)');
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _status = e.toString();
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SaverState>();
    final c = context.c;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    Widget card(List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.card, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );
    Widget head(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(t, style: TextStyle(color: c.muted, fontWeight: FontWeight.w600)),
        );

    return ListView(padding: EdgeInsets.fromLTRB(wide ? 36 : 20, wide ? 84 : 64, wide ? 36 : 20, 32), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tx('الإعدادات', 'Settings'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            head(tx('اللغة والمظهر', 'Language & appearance')),
            card([
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('العربية')),
                  ButtonSegment(value: true, label: Text('English')),
                ],
                selected: {s.english},
                showSelectedIcon: false,
                onSelectionChanged: (v) => s.setEnglish(v.first),
              ),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_outlined), label: Text(tx('داكن', 'Dark'))),
                  ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_outlined), label: Text(tx('فاتح', 'Light'))),
                  ButtonSegment(
                      value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_outlined), label: Text(tx('تلقائي', 'Auto'))),
                ],
                selected: {s.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (v) => s.setTheme(v.first),
              ),
            ]),
            head(tx('سيرفر احتياطي (اختياري)', 'Backup server (optional)')),
            card([
              Text(
                  tx('التطبيق يحمّل مباشرة من جوالك بدون أي سيرفر. أضف سيرفر cobalt هنا فقط إذا أردت محاولة ثانية عند تعذّر رابط ما.',
                      'The app downloads straight from your device with no server. Add a cobalt server only if you want a second try when a link fails.'),
                  style: TextStyle(color: c.muted, fontSize: 13, height: 1.5)),
              const SizedBox(height: 12),
              TextField(
                controller: _server,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                decoration: fieldDecoration(context, hint: 'http://192.168.1.10:9000', prefix: const Icon(Icons.dns_rounded)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _key,
                textDirection: TextDirection.ltr,
                obscureText: true,
                decoration: fieldDecoration(context, hint: tx('مفتاح API (اختياري)', 'API key (optional)'), prefix: const Icon(Icons.key_rounded)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                PrimaryButton(label: tx('حفظ واختبار', 'Save & test'), icon: Icons.wifi_tethering_rounded, busy: _testing, onPressed: _test),
                const SizedBox(width: 12),
                if (_status != null)
                  Expanded(child: Text(_status!, style: TextStyle(color: _ok ? c.accent : c.live))),
              ]),
              const SizedBox(height: 14),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(tx('كيف أشغّل cobalt على سيرفري؟', 'How do I run cobalt on my server?')),
                children: [
                  Text(
                      tx('في ZimaOS أو أي جهاز فيه Docker: أنشئ تطبيقاً مخصصاً (Custom/Compose) بهذا المحتوى، وغيّر YOUR-SERVER-IP لعنوان السيرفر، ثم ضع العنوان أعلاه.',
                          'On ZimaOS or any Docker host: create a custom (Compose) app with this content, replace YOUR-SERVER-IP with the server address, then enter that address above.'),
                      style: TextStyle(color: c.muted, height: 1.6)),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.input, borderRadius: BorderRadius.circular(10)),
                    child: SelectableText(kCobaltCompose,
                        textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => Clipboard.setData(const ClipboardData(text: kCobaltCompose)),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(tx('نسخ', 'Copy')),
                    ),
                  ),
                ],
              ),
            ]),
            head(tx('الحفظ', 'Saving')),
            card([
              _locationCard(s, c),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.autoGallery,
                onChanged: s.setAutoGallery,
                title: Text(tx('حفظ تلقائي في ألبوم الصور', 'Also save to Photos automatically')),
                subtitle: Text(tx('الفيديو والصور تُحفظ أيضاً في ألبوم «RA7AL»', 'Videos and photos also go to the “RA7AL” album'),
                    style: TextStyle(color: c.faint, fontSize: 12)),
              ),
            ]),
            head(tx('الخصوصية', 'Privacy')),
            card([
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.lockFiles,
                onChanged: (v) => s.setLock(v),
                title: Text(tx('قفل «ملفاتي» بالبصمة أو الوجه', 'Lock “My files” with Face ID / fingerprint')),
                subtitle: Text(tx('يُقفل تلقائياً عند الخروج من التطبيق', 'Locks again when you leave the app'),
                    style: TextStyle(color: c.faint, fontSize: 12)),
              ),
            ]),
            head(tx('حول التطبيق', 'About')),
            card([
              const ListTile(contentPadding: EdgeInsets.zero, leading: Ra7alLogo(size: 36), title: Text('RA7AL AL3OMR SAVER'), subtitle: Text('v$kAppVersion · GPL-3.0')),
              Text(
                  tx('أداة شخصية مفتوحة المصدر. احترم حقوق أصحاب المحتوى وشروط المنصات، ولا تعيد نشر محتوى الآخرين بدون إذنهم.',
                      'A personal, open-source tool. Respect creators’ rights and platform terms; do not republish others’ content without permission.'),
                  style: TextStyle(color: c.faint, fontSize: 13, height: 1.6)),
            ]),
          ]),
        ),
      ),
    ]);
  }
}
