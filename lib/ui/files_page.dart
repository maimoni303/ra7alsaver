import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';

import '../services/files.dart';
import '../state/saver_state.dart';
import '../theme.dart';
import 'viewer.dart';
import 'widgets.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({super.key});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  String _filter = '*';

  @override
  void initState() {
    super.initState();
    context.read<SaverState>().refreshFiles();
  }

  IconData _icon(String t) => switch (t) {
        'audio' => Icons.audiotrack_rounded,
        'photo' => Icons.image_rounded,
        'gif' => Icons.gif_box_rounded,
        'video' => Icons.movie_rounded,
        _ => Icons.insert_drive_file_rounded,
      };

  Future<void> _menu(SavedFile f) async {
    final s = context.read<SaverState>();
    final c = context.c;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.card,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          ListTile(leading: const Icon(Icons.play_arrow_rounded), title: Text(tx('فتح', 'Open')), onTap: () => Navigator.pop(ctx, 'open')),
          ListTile(leading: const Icon(Icons.share_rounded), title: Text(tx('مشاركة', 'Share')), onTap: () => Navigator.pop(ctx, 'share')),
          if (f.type == 'video' || f.type == 'photo' || f.type == 'gif')
            ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(tx('حفظ في الصور', 'Save to Photos')),
                onTap: () => Navigator.pop(ctx, 'gallery')),
          ListTile(leading: const Icon(Icons.edit_rounded), title: Text(tx('إعادة تسمية', 'Rename')), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(
              leading: Icon(Icons.delete_rounded, color: c.live),
              title: Text(tx('حذف', 'Delete'), style: TextStyle(color: c.live)),
              onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open':
        _open(f);
      case 'share':
        await Share.shareXFiles([XFile(f.file.path)]);
      case 'gallery':
        final ok = await s.saveToGallery(f.file);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(ok ? tx('تم الحفظ في الصور', 'Saved to Photos') : tx('تعذّر الحفظ في الصور', 'Could not save to Photos'))));
        }
      case 'rename':
        final ctl = TextEditingController(text: f.name);
        final name = await showDialog<String>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(tx('إعادة تسمية', 'Rename')),
            content: TextField(controller: ctl, autofocus: true, decoration: fieldDecoration(context)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: Text(tx('إلغاء', 'Cancel'))),
              TextButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tx('حفظ', 'Save'))),
            ],
          ),
        );
        if (name != null && name.trim().isNotEmpty) await s.renameFile(f, name);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(tx('حذف الملف؟', 'Delete file?')),
            content: Text(f.name),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tx('إلغاء', 'Cancel'))),
              TextButton(onPressed: () => Navigator.pop(d, true), child: Text(tx('حذف', 'Delete'))),
            ],
          ),
        );
        if (ok == true) await s.deleteFile(f);
    }
  }

  void _open(SavedFile f) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Viewer(file: f)));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SaverState>();
    final c = context.c;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pad = wide ? 36.0 : 16.0;

    if (s.lockFiles && !s.filesUnlocked) {
      return EmptyState(
        icon: Icons.lock_rounded,
        text: tx('«ملفاتي» مقفلة', '“My files” is locked'),
        action: PrimaryButton(label: tx('فتح بالبصمة', 'Unlock'), icon: Icons.fingerprint_rounded, onPressed: s.authenticate),
      );
    }

    final list = _filter == '*' ? s.files : s.files.where((f) => f.type == _filter).toList();
    final total = s.files.fold<int>(0, (a, f) => a + f.size);

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, wide ? 84 : 64, pad, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(tx('ملفاتي', 'My files'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
          Text(tx('${s.files.length} ملف', '${s.files.length} files') + ' · ${FileStore.human(total)}', style: TextStyle(color: c.muted)),
          if (s.lockFiles) IconButton(tooltip: tx('قفل الآن', 'Lock now'), onPressed: s.relock, icon: const Icon(Icons.lock_open_rounded)),
        ]),
        const SizedBox(height: 12),
        CategoryChips(
          items: [
            MapEntry('*', tx('الكل', 'All')),
            MapEntry('video', tx('فيديو', 'Video')),
            MapEntry('audio', tx('صوت', 'Audio')),
            MapEntry('photo', tx('صور', 'Photos')),
            const MapEntry('gif', 'GIF'),
          ],
          selected: _filter,
          onSelect: (v) => setState(() => _filter = v),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: list.isEmpty
              ? EmptyState(icon: Icons.folder_open_rounded, text: tx('لا توجد ملفات بعد. احفظ أول مقطع من صفحة «حفظ».', 'No files yet. Save your first clip from “Save”.'))
              : RefreshIndicator(
                  onRefresh: s.refreshFiles,
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => Divider(color: c.line, height: 1),
                    itemBuilder: (_, i) {
                      final f = list[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: c.placeholder, borderRadius: BorderRadius.circular(10)),
                          clipBehavior: Clip.antiAlias,
                          child: f.type == 'photo' || f.type == 'gif'
                              ? Image.file(f.file, fit: BoxFit.cover, cacheWidth: 120, errorBuilder: (_, __, ___) => Icon(_icon(f.type)))
                              : Icon(_icon(f.type), color: c.accent),
                        ),
                        title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${FileStore.human(f.size)} · ${_date(f.modified)}',
                            style: TextStyle(color: c.muted, fontSize: 12)),
                        onTap: () => _open(f),
                        onLongPress: () => _menu(f),
                        trailing: IconButton(tooltip: tx('خيارات', 'Options'), icon: const Icon(Icons.more_vert_rounded), onPressed: () => _menu(f)),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }

  static String _date(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
