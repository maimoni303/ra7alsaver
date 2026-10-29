import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../services/files.dart';
import '../services/media_tools.dart';
import '../state/saver_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// Converts any video, audio or image file to another format with FFmpeg on the device.
class ConverterCard extends StatefulWidget {
  const ConverterCard({super.key});
  @override
  State<ConverterCard> createState() => _ConverterCardState();
}

class _ConverterCardState extends State<ConverterCard> {
  File? _src;
  bool _temp = false; // _src is our own copy of a picked file, deleted afterwards
  String? _target;
  bool _busy = false;
  String? _msg;
  bool _ok = false;

  String get _ext => _src == null ? '' : _src!.path.split('.').last.toLowerCase();

  Future<void> _set(File f, {bool temp = false}) async {
    await _dropTemp();
    final targets = Formats.targetsFor(f.path.split('.').last).where((e) => e != f.path.split('.').last.toLowerCase()).toList();
    setState(() {
      _src = f;
      _temp = temp;
      _target = targets.isEmpty ? null : targets.first;
      _msg = null;
    });
  }

  Future<void> _dropTemp() async {
    if (_temp && _src != null) {
      try {
        await _src!.delete();
      } catch (_) {}
    }
    _temp = false;
  }

  Future<void> _fromDevice() async {
    final pf = await FilePicker.pickFile(dialogTitle: tx('اختر ملفاً للتحويل', 'Choose a file to convert'));
    if (pf == null) return;
    if (pf.path != null) return _set(File(pf.path!));
    // Not a plain path (e.g. an Android content link): copy it in first.
    final tmp = await FileStore.reserve('.convert_${DateTime.now().millisecondsSinceEpoch}_${FileStore.safeName(pf.name)}');
    final sink = tmp.openWrite();
    await sink.addStream(pf.readAsByteStream());
    await sink.close();
    await _set(tmp, temp: true);
  }

  Future<void> _fromMyFiles() async {
    final s = context.read<SaverState>();
    await s.refreshFiles();
    if (!mounted) return;
    final c = context.c;
    final f = await showModalBottomSheet<File>(
      context: context,
      backgroundColor: c.card,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: s.files.isEmpty
            ? Padding(padding: const EdgeInsets.all(24), child: Text(tx('لا توجد ملفات في «ملفاتي»', 'No files in My files')))
            : ListView(shrinkWrap: true, children: [
                for (final sf in s.files)
                  ListTile(
                    leading: Icon(switch (sf.type) {
                      'audio' => Icons.audiotrack_rounded,
                      'photo' => Icons.image_rounded,
                      'video' => Icons.movie_rounded,
                      _ => Icons.insert_drive_file_rounded,
                    }),
                    title: Text(sf.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(FileStore.human(sf.size)),
                    onTap: () => Navigator.pop(ctx, sf.file),
                  ),
              ]),
      ),
    );
    if (f != null) await _set(f);
  }

  Future<void> _convert() async {
    final src = _src, target = _target;
    if (src == null || target == null) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final out = await context.read<SaverState>().convertFile(src, target);
      await _dropTemp();
      setState(() {
        _ok = true;
        _msg = tx('تم التحويل ✓  ${out.uri.pathSegments.last}', 'Converted ✓  ${out.uri.pathSegments.last}');
        _src = null;
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _msg = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _dropTemp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final targets = _src == null ? const <String>[] : Formats.targetsFor(_ext).where((e) => e != _ext).toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: c.card, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.transform_rounded, color: c.accent),
          const SizedBox(width: 10),
          Text(tx('تحويل الصيغ', 'Convert formats'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Text(
            tx('حوّل أي فيديو أو صوت أو صورة إلى صيغة أخرى: MP4 · MKV · MOV · WEBM · AVI · GIF · MP3 · M4A · WAV · FLAC · OPUS · JPG · PNG · WEBP',
                'Turn any video, audio or image into another format: MP4 · MKV · MOV · WEBM · AVI · GIF · MP3 · M4A · WAV · FLAC · OPUS · JPG · PNG · WEBP'),
            style: TextStyle(color: c.muted, height: 1.5)),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
              onPressed: _busy ? null : _fromMyFiles, icon: const Icon(Icons.folder_rounded), label: Text(tx('من «ملفاتي»', 'From My files'))),
          OutlinedButton.icon(
              onPressed: _busy ? null : _fromDevice, icon: const Icon(Icons.upload_file_rounded), label: Text(tx('من الجهاز', 'From this device'))),
        ]),
        if (_src != null) ...[
          const SizedBox(height: 14),
          Text(_src!.uri.pathSegments.last.replaceFirst(RegExp(r'^\.convert_\d+_'), ''),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Text(tx('حوّل إلى: ', 'Convert to: '), style: TextStyle(color: c.muted)),
            DropdownButton<String>(
              value: targets.contains(_target) ? _target : (targets.isEmpty ? null : targets.first),
              underline: const SizedBox(),
              borderRadius: BorderRadius.circular(12),
              items: [for (final t in targets) DropdownMenuItem(value: t, child: Text(t.toUpperCase()))],
              onChanged: _busy ? null : (v) => setState(() => _target = v),
            ),
          ]),
          const SizedBox(height: 10),
          PrimaryButton(label: tx('تحويل', 'Convert'), icon: Icons.autorenew_rounded, busy: _busy, onPressed: _convert),
        ],
        if (_msg != null) ...[
          const SizedBox(height: 10),
          Text(_msg!, style: TextStyle(color: _ok ? c.accent : c.live, fontSize: 13)),
        ],
        const SizedBox(height: 8),
        Text(
            tx('المستندات (Word وPDF وExcel) لا تتحول داخل الجوال؛ هذا للوسائط والصور.',
                'Documents (Word, PDF, Excel) can’t be converted on the device; this is for media and images.'),
            style: TextStyle(color: c.faint, fontSize: 12)),
      ]),
    );
  }
}
