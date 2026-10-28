import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../services/cobalt.dart';
import '../state/saver_state.dart';
import '../theme.dart';
import 'widgets.dart';

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
            head(tx('سيرفر التحميل (cobalt)', 'Download server (cobalt)')),
            card([
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
              const ListTile(contentPadding: EdgeInsets.zero, leading: Ra7alLogo(size: 36), title: Text('RA7AL AL3OMR SAVER'), subtitle: Text('v1.0.0 · GPL-3.0')),
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
