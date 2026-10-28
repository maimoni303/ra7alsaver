import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../theme.dart';
import 'widgets.dart';

/// Extra tools. First one: WhatsApp a number without saving it.
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});
  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final _phone = TextEditingController();
  final _msg = TextEditingController();
  String _cc = '966';
  String? _error;

  /// 05xxxxxxxx -> 9665xxxxxxxx; strips +, 00 and spaces.
  String? _normalize() {
    var n = _phone.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (n.startsWith('+')) n = n.substring(1);
    if (n.startsWith('00')) n = n.substring(2);
    if (n.startsWith('0')) n = '$_cc${n.substring(1)}';
    if (!n.startsWith(_cc) && n.length <= 10) n = '$_cc$n';
    return n.length >= 9 ? n : null;
  }

  Future<void> _open() async {
    final n = _normalize();
    if (n == null) {
      setState(() => _error = tx('رقم غير صحيح', 'Invalid number'));
      return;
    }
    setState(() => _error = null);
    final text = _msg.text.trim();
    final uri = Uri.parse('https://wa.me/$n${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      setState(() => _error = tx('تعذّر فتح واتساب', 'Could not open WhatsApp'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(padding: EdgeInsets.fromLTRB(wide ? 36 : 20, wide ? 84 : 64, wide ? 36 : 20, 32), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tx('أدوات', 'Tools'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: c.card, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(Icons.chat_rounded, color: c.accent),
                  const SizedBox(width: 10),
                  Text(tx('واتساب مباشر', 'Direct WhatsApp'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 4),
                Text(tx('راسل أي رقم بدون ما تحفظه في جهات الاتصال.', 'Message any number without saving it to contacts.'),
                    style: TextStyle(color: c.muted)),
                const SizedBox(height: 16),
                Row(textDirection: TextDirection.ltr, children: [
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      value: _cc,
                      decoration: fieldDecoration(context),
                      items: const [
                        DropdownMenuItem(value: '966', child: Text('+966')),
                        DropdownMenuItem(value: '971', child: Text('+971')),
                        DropdownMenuItem(value: '965', child: Text('+965')),
                        DropdownMenuItem(value: '973', child: Text('+973')),
                        DropdownMenuItem(value: '974', child: Text('+974')),
                        DropdownMenuItem(value: '968', child: Text('+968')),
                        DropdownMenuItem(value: '20', child: Text('+20')),
                        DropdownMenuItem(value: '962', child: Text('+962')),
                      ],
                      onChanged: (v) => setState(() => _cc = v ?? '966'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      decoration: fieldDecoration(context, hint: '05xxxxxxxx'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _msg,
                  minLines: 2,
                  maxLines: 5,
                  decoration: fieldDecoration(context, hint: tx('رسالة (اختياري)', 'Message (optional)')),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: c.live)),
                ],
                const SizedBox(height: 16),
                PrimaryButton(label: tx('فتح المحادثة', 'Open chat'), icon: Icons.open_in_new_rounded, onPressed: _open),
              ]),
            ),
            const SizedBox(height: 16),
            Text(
                tx('أدوات قادمة: قص المقاطع، استخراج الصوت، تحويل الكلام إلى نص.',
                    'Coming next: trim clips, extract audio, speech to text.'),
                style: TextStyle(color: c.faint, fontSize: 13)),
          ]),
        ),
      ),
    ]);
  }
}
