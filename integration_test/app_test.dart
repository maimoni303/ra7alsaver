// End-to-end test of RA7AL Files Downloader on a real device or simulator.
// It drives every page, tool and button like a person would, downloads real
// files, converts them with FFmpeg and checks the results (format, codecs,
// length, size). Run: flutter test integration_test -d <device>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:ra7alsaver/main.dart' as app;
import 'package:ra7alsaver/services/cobalt.dart';
import 'package:ra7alsaver/services/extractor.dart';
import 'package:ra7alsaver/services/files.dart';
import 'package:ra7alsaver/services/media_tools.dart';
import 'package:ra7alsaver/state/saver_state.dart';
import 'package:ra7alsaver/ui/browser_page.dart';
import 'package:ra7alsaver/ui/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _raw = 'https://raw.githubusercontent.com/maimoni303/ra7alsaver/main/test_assets';
const sampleUrl = '$_raw/sample.mp4'; // 50 s, H.264 + AAC
const hlsUrl = '$_raw/hls/index.m3u8'; // 12 s HLS stream

class _Report {
  final rows = <(String, bool, String, bool)>[]; // step, ok, detail, blocking
  void add(String step, bool ok, String detail, {bool blocking = true}) {
    rows.add((step, ok, detail, blocking));
    // ignore: avoid_print
    print('${ok ? 'PASS' : (blocking ? 'FAIL' : 'WARN')}  $step  $detail');
  }

  bool get failed => rows.any((r) => !r.$2 && r.$4);
  String summary() {
    final b = StringBuffer('\n===== RA7AL test report =====\n');
    for (final r in rows) {
      b.writeln('${r.$2 ? 'PASS' : (r.$4 ? 'FAIL' : 'WARN')} | ${r.$1} | ${r.$3}');
    }
    b.writeln('Passed ${rows.where((r) => r.$2).length} of ${rows.length}');
    return b.toString();
  }
}

final report = _Report();

Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

Future<void> waitFor(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 60), String? what}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out (${timeout.inSeconds}s) waiting for ${what ?? f.describeMatch(Plurality.one)}');
}

/// Scrolls the lists on screen until [f] is built (long lists only build what is visible).
Future<void> reveal(WidgetTester t, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    final lists = find.byType(Scrollable);
    if (lists.evaluate().isEmpty) break;
    await t.drag(lists.last, const Offset(0, -300), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 250));
  }
  if (f.evaluate().isEmpty) throw TestFailure('Not on screen: ${f.describeMatch(Plurality.one)}');
}

Future<void> tap(WidgetTester t, Finder f) async {
  await reveal(t, f);
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(f.first, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 400));
}

late WidgetTester _t;

Future<void> step(String name, Future<void> Function() body, {bool blocking = true}) async {
  try {
    await body();
    report.add(name, true, '', blocking: blocking);
  } catch (e, st) {
    report.add(name, false, e.toString().replaceAll('\n', ' '), blocking: blocking);
    // ignore: avoid_print
    print('---- $name\n$e\n$st');
    // Close any sheet, menu or dialog left open so the next step starts clean.
    try {
      for (final n in find.byType(Navigator).evaluate()) {
        final st = (n as StatefulElement).state;
        if (st is NavigatorState) st.popUntil((r) => r.isFirst);
      }
      await _t.pump(const Duration(milliseconds: 600));
    } catch (_) {}
  }
}

Finder nav(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<File> newest(String ext) async {
  final d = await FileStore.dir();
  final files = d.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.$ext')).toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  if (files.isEmpty) throw TestFailure('No .$ext file in ${d.path}');
  return files.first;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final p = await SharedPreferences.getInstance();
    await p.clear();
    await p.setBool('english', true);
    await p.setInt('saveLocation', SaveLocation.app.index); // no Photos permission dialogs during the run
    final d = await FileStore.appDir();
    if (await d.exists()) await d.delete(recursive: true);
  });

  testWidgets('RA7AL Files Downloader — every page, tool and button', (t) async {
    _t = t;
    app.main();
    await waitFor(t, find.text('Save from a link'), timeout: const Duration(seconds: 40), what: 'the Save page');
    SaverState state() => Provider.of<SaverState>(t.element(find.byType(MaterialApp)), listen: false);
    var saved = 0;

    Future<void> saveLink(String url) async {
      await t.enterText(find.byType(TextField).first, url);
      await t.pump(const Duration(milliseconds: 300));
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump(const Duration(milliseconds: 300));
      final before = state().tasks.length;
      await tap(t, find.widgetWithText(PrimaryButton, 'Save'));
      final started = DateTime.now().add(const Duration(seconds: 30));
      while (state().tasks.length == before && DateTime.now().isBefore(started)) {
        await t.pump(const Duration(milliseconds: 250));
      }
      if (state().tasks.length == before) {
        throw TestFailure('Tapping Save did not start a download (resolving=${state().resolving}, '
            'message on screen: ${find.textContaining(RegExp('Error|failed|valid|server')).evaluate().map((e) => (e.widget as Text).data).join(' / ')})');
      }
      saved++;
      final task = state().tasks.first;
      final end = DateTime.now().add(const Duration(seconds: 180));
      while (DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 300));
        if (task.error != null) throw TestFailure(task.error!);
        if (task.done) return;
      }
      throw TestFailure('Download did not finish in 3 minutes (progress ${task.progress}, file ${task.item.filename}, '
          'stream ${task.item.stream}, post ${task.item.post})');
    }

    // ---------------- Save page
    await step('Save page: plain MP4 download', () async {
      await saveLink(sampleUrl);
      final f = await newest('mp4');
      final p = await MediaTools.probe(f.path);
      if (!p.streams.contains('video:h264') || !p.streams.contains('audio:aac')) throw TestFailure('streams ${p.streams}');
      await waitFor(t, find.textContaining('Saved to My files'), what: 'the done label');
    });

    await step('Save page: format MKV', () async {
      await tap(t, find.text('MP4'));
      await tap(t, find.text('MKV').last);
      await saveLink(sampleUrl);
      final p = await MediaTools.probe((await newest('mkv')).path);
      if (!p.format.contains('matroska')) throw TestFailure('format ${p.format}');
      await tap(t, find.text('MKV'));
      await tap(t, find.text('MP4').last);
    });

    await step('Save page: "Audio only" as MP3', () async {
      await tap(t, find.text('Audio only'));
      await tap(t, find.text('M4A'));
      await tap(t, find.text('MP3').last);
      await saveLink(sampleUrl);
      final p = await MediaTools.probe((await newest('mp3')).path);
      if (p.streams.join() != 'audio:mp3') throw TestFailure('streams ${p.streams}');
      if ((p.duration - 50).abs() > 1.5) throw TestFailure('duration ${p.duration}');
    });

    await step('Save page: "Audio only" as M4A (no re-encode)', () async {
      await tap(t, find.text('MP3'));
      await tap(t, find.text('M4A').last);
      await saveLink(sampleUrl);
      final p = await MediaTools.probe((await newest('m4a')).path);
      if (p.streams.join() != 'audio:aac') throw TestFailure('streams ${p.streams}');
    });

    await step('Save page: "No audio"', () async {
      await tap(t, find.text('No audio'));
      await saveLink(sampleUrl);
      final p = await MediaTools.probe((await newest('mp4')).path);
      if (p.streams.any((s) => s.startsWith('audio'))) throw TestFailure('still has audio: ${p.streams}');
      await tap(t, find.text('Video'));
    });

    await step('Save page: HLS stream link saved as one MP4', () async {
      await saveLink(hlsUrl);
      final p = await MediaTools.probe((await newest('mp4')).path);
      if ((p.duration - 12).abs() > 2) throw TestFailure('duration ${p.duration}');
    });

    await step('Save page: quality menu opens and changes', () async {
      await tap(t, find.text('1080p'));
      await tap(t, find.text('720p').last);
      if (state().quality != '720') throw TestFailure('quality ${state().quality}');
      await tap(t, find.text('720p'));
      await tap(t, find.text('1080p').last);
    });

    await step('Save page: bad link shows a message', () async {
      await t.enterText(find.byType(TextField).first, 'not a link');
      await tap(t, find.widgetWithText(PrimaryButton, 'Save'));
      await waitFor(t, find.textContaining('valid link'), timeout: const Duration(seconds: 10));
    });

    await step('Save page: "Clear finished"', () async {
      await tap(t, find.text('Clear finished'));
      if (state().tasks.isNotEmpty) throw TestFailure('${state().tasks.length} left');
      saved = 0;
    });

    // ---------------- Converter (every target format)
    final mp4 = await newest('mp4');
    for (final ext in ['mov', 'webm', 'avi', 'gif', 'mkv', 'wav', 'flac', 'opus', 'ogg', 'aac', 'mp3', 'm4a', 'jpg']) {
      await step('Converter: MP4 → ${ext.toUpperCase()}', () async {
        final out = await state().convertFile(mp4, ext);
        final p = await MediaTools.probe(out.path);
        if (await out.length() == 0 || p.streams.isEmpty) throw TestFailure('empty result');
      });
    }
    for (final ext in ['png', 'webp', 'bmp']) {
      await step('Converter: JPG → ${ext.toUpperCase()}', () async {
        final out = await state().convertFile(await newest('jpg'), ext);
        if (await out.length() == 0) throw TestFailure('empty result');
      });
    }
    await step('Converter: MP3 → WAV', () async {
      final out = await state().convertFile(await newest('mp3'), 'wav');
      final p = await MediaTools.probe(out.path);
      if (!p.streams.join().contains('pcm_s16le')) throw TestFailure('streams ${p.streams}');
    });

    // ---------------- Ringtone rules
    await step('Ringtone: iPhone .m4r is AAC, ≤ 40 s, < 1 MB even from a 50 s clip', () async {
      final out = await FileStore.reserve('tone_test.m4r');
      await MediaTools.ringtone(mp4.path, out.path, start: 0, length: 50, iphone: true);
      final p = await MediaTools.probe(out.path);
      if (p.streams.join() != 'audio:aac') throw TestFailure('streams ${p.streams}');
      if (p.duration > 40.2) throw TestFailure('duration ${p.duration}');
      if (!p.format.contains('mp4') && !p.format.contains('ipod') && !p.format.contains('mov')) throw TestFailure('format ${p.format}');
      final kb = await out.length() / 1024;
      if (kb >= 1024) throw TestFailure('size ${kb.toStringAsFixed(0)} KB');
    });
    await step('Ringtone: Android .mp3 ≤ 60 s', () async {
      final out = await FileStore.reserve('tone_test.mp3');
      await MediaTools.ringtone(mp4.path, out.path, start: 5, length: 20, iphone: false);
      final p = await MediaTools.probe(out.path);
      if (p.streams.join() != 'audio:mp3' || (p.duration - 20).abs() > 0.6) throw TestFailure('${p.streams} ${p.duration}');
    });

    // ---------------- My files page
    await step('My files: list, filters and refresh', () async {
      await tap(t, nav('My files'));
      await waitFor(t, find.byTooltip('Options'), what: 'saved files');
      for (final f in ['Video', 'Audio', 'Photos', 'GIF', 'All']) {
        await tap(t, find.text(f).last);
      }
    });

    Finder optionsOf(String name) =>
        find.descendant(of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)), matching: find.byTooltip('Options'));

    await step('My files: open a video in the player', () async {
      await state().refreshFiles();
      await t.pump(const Duration(milliseconds: 500));
      final name = mp4.uri.pathSegments.last;
      await tap(t, find.text(name));
      await pumpFor(t, const Duration(seconds: 3));
      await t.pageBack();
      await pumpFor(t, const Duration(seconds: 1));
    });

    await step('My files: "Make a ringtone" — listen to the part, make iPhone and Android tones, play the result', () async {
      await tap(t, optionsOf(mp4.uri.pathSegments.last));
      await tap(t, find.text('Make a ringtone'));
      await waitFor(t, find.text('Make ringtone'), what: 'the ringtone page');
      await tap(t, find.text('Listen to the selection'));
      await waitFor(t, find.textContaining('Stop'), timeout: const Duration(seconds: 10), what: 'the selection preview');
      await pumpFor(t, const Duration(seconds: 2));
      await tap(t, find.textContaining('Stop'));
      await waitFor(t, find.text('Listen to the selection'), timeout: const Duration(seconds: 5));
      await tap(t, find.text('iPhone'));
      await tap(t, find.text('Make ringtone'));
      await waitFor(t, find.textContaining('Ringtone ready'), timeout: const Duration(seconds: 90));
      await tap(t, find.text('Play the ringtone'));
      await waitFor(t, find.textContaining('Stop'), timeout: const Duration(seconds: 10), what: 'the ringtone playing');
      await pumpFor(t, const Duration(seconds: 2));
      await tap(t, find.textContaining('Stop'));
      await waitFor(t, find.text('Play the ringtone'), timeout: const Duration(seconds: 5));
      await tap(t, find.text('Android'));
      await tap(t, find.text('Make ringtone'));
      await waitFor(t, find.textContaining('Ringtone ready'), timeout: const Duration(seconds: 90));
      await t.pageBack();
      await pumpFor(t, const Duration(seconds: 1));
    });

    await step('My files: rename', () async {
      await state().refreshFiles();
      await t.pump(const Duration(milliseconds: 500));
      final f = state().files.firstWhere((x) => x.name.endsWith('.wav'));
      await tap(t, optionsOf(f.name));
      await tap(t, find.text('Rename'));
      await t.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'renamed_by_test');
      await tap(t, find.descendant(of: find.byType(AlertDialog), matching: find.text('Save')));
      await waitFor(t, find.text('renamed_by_test.wav'), timeout: const Duration(seconds: 10));
    });

    await step('My files: delete', () async {
      await tap(t, optionsOf('renamed_by_test.wav'));
      await tap(t, find.text('Delete'));
      await tap(t, find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));
      await pumpFor(t, const Duration(seconds: 1));
      if (find.text('renamed_by_test.wav').evaluate().isNotEmpty) throw TestFailure('still listed');
    });

    // ---------------- Tools page
    await step('Tools: ringtone maker opens and returns', () async {
      await tap(t, nav('Tools'));
      await tap(t, find.text('Ringtone maker'));
      await waitFor(t, find.text('From My files'));
      await t.pageBack();
      await pumpFor(t, const Duration(seconds: 1));
    });

    await step('Tools: converter "From My files" picks a file and converts', () async {
      await tap(t, find.text('From My files').first);
      await tap(t, find.text(mp4.uri.pathSegments.last).last);
      await waitFor(t, find.text('Convert'));
      await tap(t, find.text('Convert'));
      await waitFor(t, find.textContaining('Converted ✓'), timeout: const Duration(seconds: 120));
    });

    await step('Tools: WhatsApp rejects a bad number', () async {
      await t.enterText(find.widgetWithText(TextField, '05xxxxxxxx'), '12');
      await tap(t, find.text('Open chat'));
      await waitFor(t, find.text('Invalid number'), timeout: const Duration(seconds: 5));
    });

    // ---------------- Settings page
    await step('Settings: theme buttons', () async {
      await tap(t, nav('Settings'));
      for (final m in ['Dark', 'Light', 'Auto', 'Dark']) {
        await tap(t, find.text(m));
      }
    });

    await step('Settings: every save location', () async {
      final s = state();
      final options = <String, SaveLocation>{
        'Photos': SaveLocation.photos,
        if (Platform.isIOS) 'Files app — pick the folder each time': SaveLocation.ask,
        if (!Platform.isIOS) 'Downloads folder': SaveLocation.downloads,
        'Inside the app only (My files)': SaveLocation.app,
      };
      for (final e in options.entries) {
        await tap(t, find.text(e.key));
        await pumpFor(t, const Duration(seconds: 1));
        if (s.saveLocation != e.value) throw TestFailure('${e.key} → ${s.saveLocation}');
      }
    });

    await step('Settings: backup server test reports an unreachable address', () async {
      await t.enterText(find.widgetWithText(TextField, 'http://192.168.1.10:9000'), 'http://10.255.255.1:9');
      await tap(t, find.text('Save & test'));
      await waitFor(t, find.textContaining(RegExp('Cannot reach|timed out|not a cobalt|Unexpected')), timeout: const Duration(seconds: 40));
      await state().setServer('', '');
    });

    await step('Settings: language switch to Arabic and back', () async {
      await tap(t, find.text('العربية'));
      await waitFor(t, find.descendant(of: find.byType(NavigationBar), matching: find.text('الإعدادات')), timeout: const Duration(seconds: 5));
      await tap(t, find.descendant(of: find.byType(NavigationBar), matching: find.text('الإعدادات')));
      await tap(t, find.text('English'));
      await tap(t, nav('Settings'));
      await waitFor(t, find.text('Settings'), timeout: const Duration(seconds: 5));
    });

    // ---------------- Browser
    if (BrowserPage.supported) {
      await step('Browser: finds the video on a page and downloads it', () async {
        await tap(t, nav('Browser'));
        await pumpFor(t, const Duration(seconds: 4));
        await BrowserPage.debugLoadHtml(
            '<html><head><title>RA7AL test</title><meta name="viewport" content="width=device-width"></head>'
            '<body><h1>Test</h1><video controls muted playsinline src="$sampleUrl"></video></body></html>');
        await waitFor(t, find.text('Save (1)'), timeout: const Duration(seconds: 30), what: 'the detected video');
        await tap(t, find.text('Save (1)'));
        await tap(t, find.textContaining('sample.mp4'));
        final end = DateTime.now().add(const Duration(seconds: 120));
        while (DateTime.now().isBefore(end) && !state().tasks.any((x) => x.done && x.item.url == sampleUrl)) {
          await t.pump(const Duration(milliseconds: 300));
        }
        if (!state().tasks.any((x) => x.done && x.item.url == sampleUrl)) throw TestFailure('download from the browser did not finish');
      });
    }

    // ---------------- Link readers against live sites (reported, not blocking: sites change and may block test machines)
    final live = <String, String>{
      'YouTube': 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
      'YouTube Shorts link': 'https://youtu.be/jNQXAC9IVRw',
    };
    for (final e in live.entries) {
      await step('Live site: ${e.key}', () async {
        final items = await Extractor.resolve(e.value).timeout(const Duration(seconds: 60));
        if (items.isEmpty || items.first.url.isEmpty) throw TestFailure('nothing found');
      }, blocking: false);
    }
    await step('Any file link (PDF) is read as a file and downloaded', () async {
      final items = await Extractor.resolve('$_raw/sample.pdf');
      if (items.isEmpty || items.first.type != 'other' || !items.first.filename.endsWith('.pdf')) {
        throw TestFailure(items.isEmpty ? 'nothing' : '${items.first.type} ${items.first.filename}');
      }
      await state().download(items);
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(end) && !state().tasks.any((x) => x.done && x.item.filename.endsWith('.pdf'))) {
        await t.pump(const Duration(milliseconds: 300));
      }
      final f = await newest('pdf');
      if (!(await f.readAsString()).startsWith('%PDF')) throw TestFailure('not a PDF');
    });
    await step('Link reader: direct file and stream links', () async {
      final a = await Extractor.resolve(sampleUrl);
      final b = await Extractor.resolve(hlsUrl);
      if (a.single.type != 'video' || !b.single.stream) throw TestFailure('${a.single.type} / ${b.single.stream}');
    });
    await step('Link reader: unsupported page gives a clear message', () async {
      try {
        await Extractor.resolve('https://example.com/');
        throw TestFailure('no error');
      } on CobaltException catch (e) {
        if (e.message.isEmpty) throw TestFailure('empty message');
      }
    });

    // ignore: avoid_print
    print(report.summary());
    expect(report.failed, isFalse, reason: report.summary());
  }, timeout: const Timeout(Duration(minutes: 40)));
}
