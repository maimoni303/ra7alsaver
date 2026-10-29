import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import '../services/files.dart';
import '../services/media_tools.dart';
import '../state/saver_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// Turns any video or audio clip into a ringtone made to each phone's rules:
/// iPhone — AAC in an .m4r file, 40 seconds at most (iOS ignores longer tones);
/// Android — MP3, placed in the Ringtones folder so it shows in Sound settings.
class RingtonePage extends StatefulWidget {
  final File? source;
  const RingtonePage({super.key, this.source});

  static Future<void> open(BuildContext context, {File? source}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RingtonePage(source: source)));

  @override
  State<RingtonePage> createState() => _RingtonePageState();
}

class _RingtonePageState extends State<RingtonePage> {
  File? _src;
  File? _temp;
  double _total = 0;
  RangeValues _range = const RangeValues(0, 30);
  bool _iphone = Platform.isIOS || Platform.isMacOS;
  bool _fade = true;
  bool _busy = false, _loading = false;

  // Listening: the selected part of the clip before making the tone, or the finished tone before saving it.
  final _player = Player();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playSub;
  String? _playing; // 'part' | 'tone' | null
  Duration _pos = Duration.zero;
  String? _msg;
  bool _ok = false;
  File? _result;

  double get _max => _iphone ? 40 : 60;

  @override
  void initState() {
    super.initState();
    if (widget.source != null) _load(widget.source!);
    _posSub = _player.stream.position.listen((p) {
      if (!mounted || _playing == null) return;
      // The part preview stops at the chosen end point.
      if (_playing == 'part' && p.inMilliseconds >= (_range.end * 1000).round()) {
        _stop();
        return;
      }
      setState(() => _pos = p);
    });
    _playSub = _player.stream.completed.listen((done) {
      if (done && mounted) setState(() => _playing = null);
    });
  }

  Future<void> _stop() async {
    await _player.pause();
    if (mounted) setState(() => _playing = null);
  }

  Future<void> _listenPart() async {
    if (_playing == 'part') return _stop();
    final src = _src;
    if (src == null) return;
    setState(() {
      _playing = 'part';
      _pos = Duration(milliseconds: (_range.start * 1000).round());
    });
    try {
      await _player.open(Media(src.uri.toString()), play: false).timeout(const Duration(seconds: 8));
    } catch (_) {
      if (mounted) setState(() => _playing = null);
      return;
    }
    // Wait until the file is ready, then jump to the start of the selection.
    for (var i = 0; i < 40 && _player.state.duration == Duration.zero; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await _player.seek(Duration(milliseconds: (_range.start * 1000).round()));
    if (_playing == 'part') await _player.play();
  }

  Future<void> _listenTone() async {
    if (_playing == 'tone') return _stop();
    final r = _result;
    if (r == null) return;
    setState(() {
      _playing = 'tone';
      _pos = Duration.zero;
    });
    try {
      // Play a copy with a plain name: some players won't open ".m4r" or names with brackets.
      final ext = r.path.toLowerCase().endsWith('.m4r') ? 'm4a' : r.path.split('.').last;
      final copy = await r.copy('${Directory.systemTemp.path}/ra7al_tone_preview.$ext');
      await _player.open(Media(copy.uri.toString())).timeout(const Duration(seconds: 8));
    } catch (_) {
      if (mounted) {
        setState(() => _playing = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tx('تعذّر تشغيل النغمة', 'Could not play the ringtone'))));
      }
    }
  }

  Widget _listenButton({required bool on, required String label, required VoidCallback onTap, String? time}) {
    final c = context.c;
    return OutlinedButton.icon(
      onPressed: _busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: on ? c.onAccent : c.accent,
        backgroundColor: on ? c.accent : null,
        side: BorderSide(color: c.accent),
      ),
      icon: Icon(on ? Icons.stop_rounded : Icons.play_arrow_rounded),
      label: Text(on && time != null ? '$label · $time' : label),
    );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playSub?.cancel();
    _player.dispose();
    _temp?.delete().catchError((_) => File(''));
    super.dispose();
  }

  Future<void> _load(File f) async {
    setState(() {
      _loading = true;
      _src = f;
      _msg = null;
      _result = null;
    });
    final d = await MediaTools.duration(f.path);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _total = d;
      _range = RangeValues(0, (d <= 0 ? 30.0 : d).clamp(1, _iphone ? 30.0 : 30.0).toDouble());
    });
  }

  Future<void> _fromDevice() async {
    final pf = await FilePicker.pickFile(
        dialogTitle: tx('اختر مقطعاً', 'Choose a clip'), type: FileType.media);
    if (pf == null) return;
    if (pf.path != null) return _load(File(pf.path!));
    final tmp = await FileStore.reserve('.tone_${DateTime.now().millisecondsSinceEpoch}_${FileStore.safeName(pf.name)}');
    final sink = tmp.openWrite();
    await sink.addStream(pf.readAsByteStream());
    await sink.close();
    _temp = tmp;
    await _load(tmp);
  }

  Future<void> _fromMyFiles() async {
    final s = context.read<SaverState>();
    await s.refreshFiles();
    if (!mounted) return;
    final c = context.c;
    final list = s.files.where((f) => f.type == 'video' || f.type == 'audio').toList();
    final f = await showModalBottomSheet<File>(
      context: context,
      backgroundColor: c.card,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: list.isEmpty
            ? Padding(padding: const EdgeInsets.all(24), child: Text(tx('لا توجد مقاطع في «ملفاتي»', 'No clips in My files')))
            : ListView(shrinkWrap: true, children: [
                for (final sf in list)
                  ListTile(
                    leading: Icon(sf.type == 'audio' ? Icons.audiotrack_rounded : Icons.movie_rounded),
                    title: Text(sf.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(ctx, sf.file),
                  ),
              ]),
      ),
    );
    if (f != null) await _load(f);
  }

  void _setPhone(bool iphone) {
    setState(() {
      _iphone = iphone;
      final maxLen = iphone ? 40.0 : 60.0;
      if (_range.end - _range.start > maxLen) _range = RangeValues(_range.start, _range.start + maxLen);
      _result = null;
    });
  }

  void _onRange(RangeValues v) {
    if (_playing != null) _stop();
    var r = v;
    if (r.end - r.start > _max) {
      // Keep the moved handle where the finger is and pull the other one along.
      r = (r.start != _range.start) ? RangeValues(r.start, r.start + _max) : RangeValues(r.end - _max, r.end);
    }
    if (r.end - r.start < 1) return;
    setState(() {
      _range = r;
      _result = null;
    });
  }

  static String _t(double s) {
    final m = s ~/ 60, sec = (s % 60).floor();
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _make() async {
    final src = _src;
    if (src == null) return;
    await _stop();
    final s = context.read<SaverState>();
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final base = src.uri.pathSegments.last.replaceFirst(RegExp(r'^\.tone_\d+_'), '');
      final dot = base.lastIndexOf('.');
      final name = '${dot > 0 ? base.substring(0, dot) : base} (${_iphone ? 'iPhone' : 'Android'}).${_iphone ? 'm4r' : 'mp3'}';
      final out = await FileStore.reserve(name);
      await MediaTools.ringtone(src.path, out.path,
          start: _range.start, length: _range.end - _range.start, iphone: _iphone, fade: _fade);
      File result = out;
      var where = tx('في «ملفاتي»', 'in My files');
      if (!_iphone && Platform.isAndroid) {
        // The system ringtone list reads the Ringtones folder.
        try {
          final dir = Directory('/storage/emulated/0/Ringtones');
          if (!await dir.exists()) await dir.create(recursive: true);
          result = await out.copy('${dir.path}/${out.uri.pathSegments.last}');
          await out.delete();
          where = tx('في مجلد Ringtones', 'in the Ringtones folder');
        } catch (_) {}
      }
      await s.refreshFiles();
      final kb = (await result.length()) / 1024;
      setState(() {
        _result = result;
        _ok = true;
        _msg = tx('النغمة جاهزة ✓ ${_t(_range.end - _range.start)} · ${kb.toStringAsFixed(0)} KB — محفوظة $where',
            'Ringtone ready ✓ ${_t(_range.end - _range.start)} · ${kb.toStringAsFixed(0)} KB — saved $where');
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
  Widget build(BuildContext context) {
    final c = context.c;
    final s = context.read<SaverState>();
    // A Material surface (not a plain coloured box) so list tiles inside show their tap ripple.
    Widget card(List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Material(
            color: c.card,
            shape: RoundedRectangleBorder(side: BorderSide(color: c.line), borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        );
    final len = _range.end - _range.start;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(backgroundColor: c.bg, title: Text(tx('صانع النغمات', 'Ringtone maker'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        card([
          Text(tx('١. المقطع', '1. The clip'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(onPressed: _busy ? null : _fromMyFiles, icon: const Icon(Icons.folder_rounded), label: Text(tx('من «ملفاتي»', 'From My files'))),
            OutlinedButton.icon(onPressed: _busy ? null : _fromDevice, icon: const Icon(Icons.upload_file_rounded), label: Text(tx('من الجهاز', 'From this device'))),
          ]),
          if (_src != null) ...[
            const SizedBox(height: 10),
            Text(_src!.uri.pathSegments.last.replaceFirst(RegExp(r'^\.tone_\d+_'), ''),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 3)),
          ],
        ]),
        card([
          Text(tx('٢. نوع الجوال', '2. Phone'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, icon: Icon(Icons.phone_iphone_rounded), label: Text('iPhone')),
              ButtonSegment(value: false, icon: Icon(Icons.phone_android_rounded), label: Text('Android')),
            ],
            selected: {_iphone},
            showSelectedIcon: false,
            onSelectionChanged: (v) => _setPhone(v.first),
          ),
          const SizedBox(height: 8),
          Text(
              _iphone
                  ? tx('آيفون: ملف M4R بصيغة AAC، ستيريو 44.1 كيلوهرتز، 40 ثانية كحد أقصى (أطول من ذلك لا يقبله iOS)، والحجم أقل من 1 ميغا.',
                      'iPhone: M4R file, AAC, 44.1 kHz stereo, 40 seconds max (iOS rejects longer), under 1 MB.')
                  : tx('أندرويد: ملف MP3 بجودة 192 كيلوبت، حتى 60 ثانية، يُحفظ في مجلد Ringtones.',
                      'Android: 192 kbps MP3, up to 60 seconds, saved in the Ringtones folder.'),
              style: TextStyle(color: c.muted, fontSize: 13, height: 1.5)),
        ]),
        if (_src != null && !_loading)
          card([
            Text(tx('٣. الجزء المطلوب', '3. The part you want'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (_total > 0) ...[
              RangeSlider(
                values: RangeValues(_range.start.clamp(0, _total).toDouble(), _range.end.clamp(0, _total).toDouble()),
                min: 0,
                max: _total,
                activeColor: c.accent,
                onChanged: _busy ? null : _onRange,
              ),
              Row(textDirection: TextDirection.ltr, children: [
                Text(_t(_range.start)),
                const Spacer(),
                Text(tx('المدة ${_t(len)} (الحد ${_t(_max)})', 'Length ${_t(len)} (max ${_t(_max)})'),
                    style: TextStyle(color: len > _max ? c.live : c.accent, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(_t(_range.end)),
              ]),
            ] else
              Text(tx('لم أتمكن من قراءة طول المقطع؛ سيُؤخذ أول ${_t(_max)}.', 'Couldn’t read the clip length; the first ${_t(_max)} will be used.'),
                  style: TextStyle(color: c.muted)),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _listenButton(
                on: _playing == 'part',
                label: _playing == 'part' ? tx('إيقاف', 'Stop') : tx('استمع للجزء المحدد', 'Listen to the selection'),
                time: _t(_pos.inMilliseconds / 1000),
                onTap: _listenPart,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _fade,
              onChanged: (v) => setState(() => _fade = v),
              title: Text(tx('تلاشٍ ناعم في البداية والنهاية', 'Smooth fade in and out')),
            ),
            const SizedBox(height: 6),
            PrimaryButton(label: tx('اصنع النغمة', 'Make ringtone'), icon: Icons.music_note_rounded, busy: _busy, onPressed: _make),
            if (_msg != null) ...[
              const SizedBox(height: 10),
              Text(_msg!, style: TextStyle(color: _ok ? c.accent : c.live, fontSize: 13)),
            ],
          ]),
        if (_result != null)
          card([
            Text(tx('٤. استمع إليها ثم احفظها نغمة رنين', '4. Listen, then set it as your ringtone'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _listenButton(
                on: _playing == 'tone',
                label: _playing == 'tone' ? tx('إيقاف', 'Stop') : tx('استمع للنغمة', 'Play the ringtone'),
                time: _t(_pos.inMilliseconds / 1000),
                onTap: _listenTone,
              ),
              if (Platform.isIOS)
                OutlinedButton.icon(
                  onPressed: () => s.exportFile(_result!),
                  icon: const Icon(Icons.drive_folder_upload_rounded),
                  label: Text(tx('حفظ في «الملفات»', 'Save to Files')),
                ),
              OutlinedButton.icon(
                onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(_result!.path)])),
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(tx('مشاركة', 'Share')),
              ),
            ]),
            const SizedBox(height: 12),
            Text(
                _iphone
                    ? tx(
                        'على الآيفون (أبل لا تسمح للتطبيقات بتعيين النغمة مباشرة):\n'
                            '• الطريقة الأسهل: احفظ الملف في «الملفات»، ثم افتح GarageBand ← مشروع جديد (مسجّل الصوت) ← زر الحلقات ← «الملفات» واسحب النغمة للمسار ← «أغنياتي» ← اضغط مطولاً على المشروع ← مشاركة ← نغمة رنين ← استخدام الصوت كنغمة رنين.\n'
                            '• أو من الكمبيوتر: وصّل الآيفون، وفي Finder (ماك) أو iTunes (ويندوز) اسحب ملف ‎.m4r‎ إلى الجهاز، فيظهر في الإعدادات ← الأصوات ← نغمة الرنين.',
                        'On iPhone (Apple doesn’t let apps set ringtones directly):\n'
                            '• Easiest: save the file to Files, open GarageBand → new Audio Recorder project → Loops button → Files, drag the tone onto the track → My Songs → long-press the project → Share → Ringtone → Use sound as Standard Ringtone.\n'
                            '• Or from a computer: connect the iPhone and drag the .m4r file onto it in Finder (Mac) or iTunes (Windows); it appears in Settings → Sounds → Ringtone.')
                    : tx('على أندرويد: الإعدادات ← الصوت ← نغمة رنين الهاتف، واختر النغمة من القائمة (أو «إضافة» واختر الملف من مجلد Ringtones).',
                        'On Android: Settings → Sound → Phone ringtone, and pick it from the list (or “Add” and choose it from the Ringtones folder).'),
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.7)),
          ]),
      ]),
    );
  }
}
