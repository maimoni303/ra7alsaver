import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n.dart';
import '../services/cobalt.dart';
import '../state/saver_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// A media file spotted on the page being browsed.
class FoundMedia {
  final String url, kind, title;
  const FoundMedia(this.url, this.kind, this.title);

  bool get isStream => RegExp(r'\.(m3u8|mpd)(\?|#|$)', caseSensitive: false).hasMatch(url);

  String get type {
    final u = url.toLowerCase().split('?').first;
    if (kind == 'img') return u.endsWith('.gif') ? 'gif' : 'photo';
    if (kind == 'audio' || RegExp(r'\.(mp3|m4a|aac|wav|flac|ogg|opus)$').hasMatch(u)) return 'audio';
    return 'video';
  }
}

/// Watches what the page loads and reports media files: <video>/<audio>/<source> tags,
/// network requests (fetch/XHR and the browser's resource list) for video, audio and
/// streaming playlists, and large images.
const _sniffer = r'''
(function(){
  if (window.__ra7al) return; window.__ra7al = 1;
  var seen = {};
  var media = /\.(mp4|m4v|mov|webm|mkv|m3u8|mpd|mp3|m4a|aac|wav|flac|ogg|opus)(\?|#|$)/i;
  function add(u, kind){
    try {
      if (!u || typeof u !== 'string' || u.indexOf('blob:') === 0 || u.indexOf('data:') === 0) return;
      u = new URL(u, location.href).href;
      if (seen[u]) return; seen[u] = 1;
      Ra7al.postMessage(JSON.stringify({u: u, k: kind || '', t: document.title || ''}));
    } catch (e) {}
  }
  function test(u){ if (u && typeof u === 'string' && (media.test(u) || /mime=(video|audio)|\/manifest\/(hls|dash)/i.test(u))) add(u, ''); }
  function scan(){
    document.querySelectorAll('video,audio,source').forEach(function(e){
      add(e.currentSrc || e.src, e.tagName.toLowerCase() === 'audio' ? 'audio' : 'video');
    });
    document.querySelectorAll('img').forEach(function(i){
      if (i.naturalWidth >= 600 && i.naturalHeight >= 400) add(i.currentSrc || i.src, 'img');
    });
    try { performance.getEntriesByType('resource').forEach(function(r){ test(r.name); }); } catch (e) {}
  }
  var f = window.fetch;
  if (f) window.fetch = function(i){ try { test(typeof i === 'string' ? i : (i && i.url)); } catch (e) {} return f.apply(this, arguments); };
  var o = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(m, u){ try { test(String(u)); } catch (e) {} return o.apply(this, arguments); };
  scan(); setInterval(scan, 1500);
})();
''';

class _Browser {
  static WebViewController? controller;
  static final found = ValueNotifier<List<FoundMedia>>([]);
  static final url = ValueNotifier<String>('');
  static final progress = ValueNotifier<int>(100);
}

/// Browse any site (and sign in where needed); every video, audio, stream or large image
/// the page loads can be saved.
class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});
  static bool get supported => Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

  /// Loads a page from text (used by the app's own tests).
  static Future<void> debugLoadHtml(String html, {String baseUrl = 'https://ra7al.test/'}) async =>
      _Browser.controller?.loadHtmlString(html, baseUrl: baseUrl);
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final _field = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (BrowserPage.supported) _Browser.controller ??= _create();
    _field.text = _Browser.url.value;
    _Browser.url.addListener(_syncField);
  }

  void _syncField() {
    if (!mounted) return;
    _field.text = _Browser.url.value;
  }

  @override
  void dispose() {
    _Browser.url.removeListener(_syncField);
    super.dispose();
  }

  WebViewController _create() {
    final c = WebViewController();
    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('Ra7al', onMessageReceived: (m) {
        try {
          final j = jsonDecode(m.message) as Map<String, dynamic>;
          final u = (j['u'] ?? '').toString();
          final list = _Browser.found.value;
          if (u.isEmpty || list.any((f) => f.url == u)) return;
          _Browser.found.value = [...list, FoundMedia(u, (j['k'] ?? '').toString(), (j['t'] ?? '').toString())];
        } catch (_) {}
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (u) {
          _Browser.found.value = [];
          _Browser.url.value = u;
        },
        onPageFinished: (u) {
          _Browser.url.value = u;
          c.runJavaScript(_sniffer).catchError((_) {});
        },
        onUrlChange: (ch) {
          if (ch.url != null) _Browser.url.value = ch.url!;
          c.runJavaScript(_sniffer).catchError((_) {});
        },
        onProgress: (p) => _Browser.progress.value = p,
      ))
      ..loadRequest(Uri.parse('https://www.google.com/'));
    return c;
  }

  void _go(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final looksLikeUrl = RegExp(r'^(https?://)?[^\s]+\.[a-z]{2,}(/\S*)?$', caseSensitive: false).hasMatch(t);
    final uri = looksLikeUrl
        ? Uri.parse(t.startsWith('http') ? t : 'https://$t')
        : Uri.https('www.google.com', '/search', {'q': t});
    _Browser.controller?.loadRequest(uri);
    FocusScope.of(context).unfocus();
  }

  Future<void> _savePage() async {
    final s = context.read<SaverState>();
    final messenger = ScaffoldMessenger.of(context);
    final page = await _Browser.controller?.currentUrl() ?? _Browser.url.value;
    if (page.isEmpty) return;
    try {
      final items = await s.resolve(page);
      await s.download(items);
      messenger.showSnackBar(SnackBar(content: Text(tx('بدأ التحميل (${items.length})', 'Download started (${items.length})'))));
    } on CobaltException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _saveFound(FoundMedia f) async {
    final s = context.read<SaverState>();
    final page = _Browser.url.value;
    final seg = Uri.tryParse(f.url)?.pathSegments.where((e) => e.isNotEmpty).lastOrNull ?? '';
    final ext = switch (f.type) { 'audio' => 'mp3', 'photo' => 'jpg', 'gif' => 'gif', _ => 'mp4' };
    final base = f.title.trim().isEmpty ? 'RA7AL_${DateTime.now().millisecondsSinceEpoch}' : f.title.trim();
    final name = !f.isStream && RegExp(r'\.[A-Za-z0-9]{2,4}$').hasMatch(seg) ? Uri.decodeComponent(seg) : '$base.$ext';
    await s.download([
      MediaItem(
        url: f.url,
        filename: f.isStream ? '$base.mp4' : name,
        type: f.type,
        stream: f.isStream,
        headers: {
          if (page.isNotEmpty) 'Referer': page,
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1',
        },
      ),
    ]);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tx('بدأ التحميل — تابعه في صفحة «حفظ»', 'Download started — follow it on the Save page'))));
    }
  }

  void _sheet() {
    final c = context.c;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ValueListenableBuilder<List<FoundMedia>>(
            valueListenable: _Browser.found,
            builder: (ctx, list, _) => ListView(shrinkWrap: true, children: [
              ListTile(
                leading: Icon(Icons.auto_awesome_rounded, color: c.accent),
                title: Text(tx('حفظ هذه الصفحة بأفضل جودة', 'Save this page in best quality')),
                subtitle: Text(tx('يوتيوب وتيك توك وإنستقرام وغيرها', 'YouTube, TikTok, Instagram and more')),
                onTap: () {
                  Navigator.pop(ctx);
                  _savePage();
                },
              ),
              const Divider(height: 1),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(tx('شغّل الفيديو في الصفحة وسيظهر هنا.', 'Play the video on the page and it will show up here.'),
                      style: TextStyle(color: c.muted)),
                ),
              for (final f in list.reversed)
                ListTile(
                  leading: Icon(switch (f.type) {
                    'audio' => Icons.audiotrack_rounded,
                    'photo' || 'gif' => Icons.image_rounded,
                    _ => f.isStream ? Icons.live_tv_rounded : Icons.movie_rounded,
                  }),
                  title: Text(f.url, maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(f.isStream ? tx('بث (يُحفظ كملف واحد)', 'Stream (saved as one file)') : f.type),
                  trailing: Icon(Icons.download_rounded, color: c.accent),
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveFound(f);
                  },
                ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (!BrowserPage.supported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tx('المتصفح متاح على الآيفون وأندرويد والماك.', 'The browser is available on iPhone, Android and Mac.'),
              textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
        ),
      );
    }
    final ctl = _Browser.controller!;
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 56, 8, 6),
          child: Row(children: [
            IconButton(
                tooltip: tx('رجوع', 'Back'),
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () async {
                  if (await ctl.canGoBack()) ctl.goBack();
                }),
            IconButton(
                tooltip: tx('تقدّم', 'Forward'),
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: () async {
                  if (await ctl.canGoForward()) ctl.goForward();
                }),
            Expanded(
              child: TextField(
                controller: _field,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: _go,
                decoration: fieldDecoration(context, hint: tx('ابحث أو اكتب عنوان موقع', 'Search or type a site address')),
              ),
            ),
            IconButton(tooltip: tx('تحديث', 'Reload'), icon: const Icon(Icons.refresh_rounded), onPressed: ctl.reload),
          ]),
        ),
        ValueListenableBuilder<int>(
          valueListenable: _Browser.progress,
          builder: (_, p, __) => p >= 100 ? const SizedBox(height: 3) : LinearProgressIndicator(value: p / 100, minHeight: 3, color: c.accent),
        ),
        Expanded(child: WebViewWidget(controller: ctl)),
      ]),
      floatingActionButton: ValueListenableBuilder<List<FoundMedia>>(
        valueListenable: _Browser.found,
        builder: (_, list, __) => FloatingActionButton.extended(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          onPressed: _sheet,
          icon: const Icon(Icons.download_rounded),
          label: Text(list.isEmpty ? tx('حفظ', 'Save') : tx('حفظ (${list.length})', 'Save (${list.length})')),
        ),
      ),
    );
  }
}
