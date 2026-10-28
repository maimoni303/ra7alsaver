import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';

import '../services/cobalt.dart';
import '../state/saver_state.dart';
import '../theme.dart';
import 'shell.dart';
import 'widgets.dart';

class SavePage extends StatefulWidget {
  const SavePage({super.key});
  @override
  State<SavePage> createState() => _SavePageState();
}

class _SavePageState extends State<SavePage> {
  final _link = TextEditingController();
  String? _clip;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkClipboard();
  }

  Future<void> _checkClipboard() async {
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      final t = d?.text?.trim() ?? '';
      final m = RegExp(r'https?://\S+').firstMatch(t);
      if (m != null && mounted && m.group(0) != _link.text) setState(() => _clip = m.group(0));
    } catch (_) {}
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    final m = RegExp(r'https?://\S+').firstMatch(t);
    setState(() {
      _link.text = m?.group(0) ?? t;
      _clip = null;
    });
  }

  Future<void> _go() async {
    final s = context.read<SaverState>();
    final link = _link.text.trim();
    if (!link.startsWith('http')) {
      setState(() => _error = tx('الصق رابطاً صحيحاً يبدأ بـ http', 'Paste a valid link starting with http'));
      return;
    }
    if (s.server.isEmpty) {
      setState(() => _error = tx('أضف عنوان سيرفر التحميل من الإعدادات أولاً', 'Add the download server address in Settings first'));
      return;
    }
    setState(() => _error = null);
    try {
      final items = await s.resolve(link);
      if (!mounted) return;
      if (items.length == 1) {
        await s.download(items);
        _link.clear();
      } else {
        final chosen = await _pick(items);
        if (chosen != null && chosen.isNotEmpty) {
          await s.download(chosen);
          _link.clear();
        }
      }
    } on CobaltException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = tx('خطأ: $e', 'Error: $e'));
    }
  }

  Future<List<MediaItem>?> _pick(List<MediaItem> items) {
    final sel = <int>{for (var i = 0; i < items.length; i++) i};
    final c = context.c;
    return showModalBottomSheet<List<MediaItem>>(
      context: context,
      backgroundColor: c.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tx('اختر ما تريد حفظه (${items.length})', 'Choose what to save (${items.length})'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.5),
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 140, mainAxisSpacing: 10, crossAxisSpacing: 10),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[i];
                    final on = sel.contains(i);
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => set(() => on ? sel.remove(i) : sel.add(i)),
                      child: Stack(fit: StackFit.expand, children: [
                        it.thumb.isNotEmpty || it.type == 'photo'
                            ? NetImage(it.thumb.isNotEmpty ? it.thumb : it.url, radius: 12)
                            : Container(
                                decoration: BoxDecoration(color: c.placeholder, borderRadius: BorderRadius.circular(12)),
                                child: Icon(it.type == 'audio' ? Icons.audiotrack_rounded : Icons.movie_rounded, color: c.faint),
                              ),
                        PositionedDirectional(
                          top: 6,
                          end: 6,
                          child: Icon(on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              color: on ? c.accent : Colors.white70),
                        ),
                      ]),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: tx('حفظ المحدد (${sel.length})', 'Save selected (${sel.length})'),
                icon: Icons.download_rounded,
                onPressed: sel.isEmpty ? null : () => Navigator.pop(ctx, [for (final i in sel) items[i]]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SaverState>();
    final c = context.c;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pad = wide ? 36.0 : 20.0;
    return ListView(padding: EdgeInsets.fromLTRB(pad, wide ? 84 : 64, pad, 32), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tx('حفظ من رابط', 'Save from a link'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(tx('الصق رابط فيديو أو صورة أو منشور، واحفظه بأعلى جودة.', 'Paste a video, photo or post link and save it in top quality.'), style: TextStyle(color: c.muted)),
            const SizedBox(height: 20),
            if (s.server.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.card, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(Icons.dns_rounded, color: c.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tx('أضف عنوان سيرفر التحميل (cobalt) أولاً', 'Add your download server (cobalt) first'))),
                  TextButton(onPressed: () => Shell.go(context, 3), child: Text(tx('الإعدادات', 'Settings'))),
                ]),
              ),
            if (_clip != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ActionChip(
                  avatar: Icon(Icons.content_paste_rounded, size: 18, color: c.accent),
                  label: Text(tx('رابط في الحافظة: ', 'Link in clipboard: ') + '${_clip!.length > 40 ? '${_clip!.substring(0, 40)}…' : _clip!}'),
                  onPressed: () => setState(() {
                    _link.text = _clip!;
                    _clip = null;
                  }),
                ),
              ),
            TextField(
              controller: _link,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _go(),
              decoration: fieldDecoration(
                context,
                hint: 'https://…',
                prefix: const Icon(Icons.link_rounded),
                suffix: IconButton(tooltip: tx('لصق', 'Paste'), icon: const Icon(Icons.content_paste_rounded), onPressed: _paste),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<SaveMode>(
                segments: [
                  ButtonSegment(value: SaveMode.video, icon: const Icon(Icons.movie_rounded), label: Text(tx('فيديو', 'Video'))),
                  ButtonSegment(value: SaveMode.audio, icon: const Icon(Icons.audiotrack_rounded), label: Text(tx('صوت MP3', 'Audio MP3'))),
                  ButtonSegment(value: SaveMode.mute, icon: const Icon(Icons.volume_off_rounded), label: Text(tx('بدون صوت', 'No audio'))),
                ],
                selected: {s.mode},
                showSelectedIcon: false,
                onSelectionChanged: (v) => s.setMode(v.first),
              ),
              if (s.mode != SaveMode.audio)
                DropdownButton<String>(
                  value: s.quality,
                  underline: const SizedBox(),
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    DropdownMenuItem(value: 'max', child: Text(tx('أعلى جودة', 'Best'))),
                    const DropdownMenuItem(value: '2160', child: Text('4K')),
                    const DropdownMenuItem(value: '1440', child: Text('1440p')),
                    const DropdownMenuItem(value: '1080', child: Text('1080p')),
                    const DropdownMenuItem(value: '720', child: Text('720p')),
                    const DropdownMenuItem(value: '480', child: Text('480p')),
                    const DropdownMenuItem(value: '360', child: Text('360p')),
                  ],
                  onChanged: (v) {
                    if (v != null) s.setQuality(v);
                  },
                ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: c.live)),
            ],
            const SizedBox(height: 18),
            PrimaryButton(label: tx('حفظ', 'Save'), icon: Icons.download_rounded, busy: s.resolving, onPressed: _go),
            if (s.tasks.isNotEmpty) ...[
              const SizedBox(height: 32),
              Row(children: [
                Expanded(child: Text(tx('التحميلات', 'Downloads'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                TextButton(onPressed: s.clearFinished, child: Text(tx('مسح المنتهية', 'Clear finished'))),
              ]),
              const SizedBox(height: 8),
              for (final t in s.tasks) _TaskTile(t: t),
            ],
          ]),
        ),
      ),
    ]);
  }
}

class _TaskTile extends StatelessWidget {
  final DownloadTask t;
  const _TaskTile({required this.t});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final icon = switch (t.item.type) {
      'audio' => Icons.audiotrack_rounded,
      'photo' => Icons.image_rounded,
      'gif' => Icons.gif_box_rounded,
      _ => Icons.movie_rounded,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.card, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, color: c.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.item.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (t.error != null)
              Text(t.error!, style: TextStyle(color: c.live, fontSize: 12))
            else if (t.done)
              Text(t.savedToGallery ? tx('تم الحفظ في «ملفاتي» وفي الصور ✓', 'Saved to My files and Photos ✓') : tx('تم الحفظ في «ملفاتي» ✓', 'Saved to My files ✓'),
                  style: TextStyle(color: c.accent, fontSize: 12))
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: t.progress < 0 ? null : t.progress,
                  minHeight: 5,
                  color: c.accent,
                  backgroundColor: c.line,
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
