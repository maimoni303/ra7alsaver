import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../l10n.dart';

/// Client for a self-hosted cobalt instance (https://github.com/imputnet/cobalt).
/// The app sends a public link; cobalt answers with a direct file URL, or a
/// list of items (picker) for posts with several photos/videos.
class CobaltException implements Exception {
  final String message;

  /// True when the server could not be reached at all (wrong network, offline,
  /// timeout). The app uses this to fall back to the backup server.
  final bool unreachable;
  CobaltException(this.message, {this.unreachable = false});
  @override
  String toString() => message;
}

/// What happens to a file after it is downloaded (on iPhone/Android).
enum PostProcess { none, merge, audioOnly, videoOnly }

class MediaItem {
  final String url, filename, type, thumb; // type: video | photo | gif | audio
  /// Headers the site needs for the file request (cookies, referer).
  final Map<String, String> headers;

  /// Expected size in bytes (0 = unknown).
  final int size;

  /// Custom byte source (YouTube streams are fetched in chunks by their own client).
  final Stream<List<int>> Function()? open;
  final PostProcess post;

  /// Second stream to merge with this one (YouTube HD audio).
  final MediaItem? extra;
  const MediaItem({
    required this.url,
    required this.filename,
    required this.type,
    this.thumb = '',
    this.headers = const {},
    this.size = 0,
    this.open,
    this.post = PostProcess.none,
    this.extra,
  });

  MediaItem copyWith({String? filename, String? type, PostProcess? post, MediaItem? extra}) => MediaItem(
        url: url,
        filename: filename ?? this.filename,
        type: type ?? this.type,
        thumb: thumb,
        headers: headers,
        size: size,
        open: open,
        post: post ?? this.post,
        extra: extra ?? this.extra,
      );
}

class CobaltResult {
  final List<MediaItem> items;
  const CobaltResult(this.items);
}

enum SaveMode { video, audio, mute }

class Cobalt {
  final String server;
  final String apiKey;

  /// How long to wait for the TCP connection. Kept short when a backup server
  /// exists, so a home-only address fails fast when you are away.
  final Duration connectTimeout;
  Cobalt(this.server, {this.apiKey = '', this.connectTimeout = const Duration(seconds: 15)});

  String get _base {
    var s = server.trim();
    if (s.isEmpty) throw CobaltException(tx('أضف عنوان سيرفر التحميل من الإعدادات أولاً', 'Add the download server address in Settings first'));
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  HttpClient _client() => HttpClient()
    ..connectionTimeout = connectTimeout
    ..badCertificateCallback = (c, h, p) => true;

  /// Checks the server is a reachable cobalt instance; returns its version.
  Future<String> ping() async {
    final c = _client();
    try {
      final req = await c.getUrl(Uri.parse('$_base/')).timeout(connectTimeout + const Duration(seconds: 2));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body);
      final v = j is Map && j['cobalt'] is Map ? (j['cobalt']['version'] ?? '').toString() : '';
      if (v.isEmpty) throw CobaltException(tx('العنوان يعمل لكنه ليس سيرفر cobalt', 'The address works but is not a cobalt server'));
      return v;
    } on SocketException {
      throw CobaltException(tx('تعذّر الوصول إلى السيرفر. تأكد من العنوان وأنك على نفس الشبكة', 'Cannot reach the server. Check the address and that you are on the same network'), unreachable: true);
    } on TimeoutException {
      throw CobaltException(tx('انتهت مهلة الاتصال بالسيرفر', 'Connection to the server timed out'), unreachable: true);
    } on FormatException {
      throw CobaltException(tx('العنوان يعمل لكنه ليس سيرفر cobalt', 'The address works but is not a cobalt server'));
    } finally {
      c.close(force: true);
    }
  }

  Future<CobaltResult> resolve(String link, {SaveMode mode = SaveMode.video, String quality = '1080'}) async {
    final c = _client();
    var connected = false; // a slow reply after connecting is not "unreachable"
    try {
      final req = await c.postUrl(Uri.parse('$_base/')).timeout(connectTimeout + const Duration(seconds: 5));
      connected = true;
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.contentTypeHeader, 'application/json');
      if (apiKey.isNotEmpty) req.headers.set(HttpHeaders.authorizationHeader, 'Api-Key $apiKey');
      req.write(jsonEncode({
        'url': link.trim(),
        'videoQuality': quality,
        'downloadMode': mode == SaveMode.audio ? 'audio' : mode == SaveMode.mute ? 'mute' : 'auto',
        'audioFormat': 'mp3',
        'filenameStyle': 'pretty',
      }));
      final res = await req.close().timeout(const Duration(seconds: 60));
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      switch (j['status']) {
        case 'tunnel':
        case 'redirect':
          final name = (j['filename'] ?? 'ra7al_${DateTime.now().millisecondsSinceEpoch}').toString();
          return CobaltResult([
            MediaItem(url: _rebase(j['url'].toString()), filename: name, type: mode == SaveMode.audio ? 'audio' : _typeOf(name)),
          ]);
        case 'picker':
          final list = (j['picker'] as List? ?? const []).whereType<Map>().toList();
          var i = 0;
          final items = list.map((m) {
            i++;
            final t = (m['type'] ?? 'photo').toString();
            final ext = t == 'video' ? 'mp4' : t == 'gif' ? 'gif' : 'jpg';
            return MediaItem(
              url: _rebase(m['url'].toString()),
              filename: 'ra7al_${DateTime.now().millisecondsSinceEpoch}_$i.$ext',
              type: t,
              thumb: (m['thumb'] ?? '').toString(),
            );
          }).toList();
          if (j['audio'] != null) {
            items.add(MediaItem(
              url: _rebase(j['audio'].toString()),
              filename: (j['audioFilename'] ?? 'ra7al_audio.mp3').toString(),
              type: 'audio',
            ));
          }
          return CobaltResult(items);
        case 'error':
          throw CobaltException(_errorText(j['error'] is Map ? (j['error']['code'] ?? '').toString() : ''));
        default:
          throw CobaltException(tx('استجابة غير متوقعة من السيرفر', 'Unexpected response from the server'));
      }
    } on SocketException {
      throw CobaltException(tx('تعذّر الوصول إلى السيرفر. تأكد من العنوان وأنك على نفس الشبكة', 'Cannot reach the server. Check the address and that you are on the same network'), unreachable: true);
    } on TimeoutException {
      throw CobaltException(tx('السيرفر تأخر في الرد، أعد المحاولة', 'The server took too long, try again'), unreachable: !connected);
    } on FormatException {
      throw CobaltException(tx('استجابة غير مفهومة من السيرفر', 'Unreadable response from the server'));
    } finally {
      c.close(force: true);
    }
  }

  /// cobalt builds its own download links ("tunnel" URLs) from its API_URL
  /// setting, e.g. http://192.168.100.70:9000/tunnel?... When the app reaches
  /// the same server through another address (Tailscale, a domain), that
  /// home IP is unreachable, so point tunnel links at the address we used.
  /// Links to other hosts (direct CDN redirects) are left untouched.
  String _rebase(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.path.endsWith('/tunnel')) return url;
    final b = Uri.parse(_base);
    if (u.scheme == b.scheme && u.host == b.host && u.port == b.port) return url;
    final basePath = b.path.endsWith('/') ? b.path.substring(0, b.path.length - 1) : b.path;
    return u.replace(scheme: b.scheme, host: b.host, port: b.port, path: '$basePath/tunnel').toString();
  }

  static String _typeOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.mp3') || n.endsWith('.m4a') || n.endsWith('.opus') || n.endsWith('.ogg') || n.endsWith('.wav')) {
      return 'audio';
    }
    if (n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') || n.endsWith('.webp')) return 'photo';
    if (n.endsWith('.gif')) return 'gif';
    return 'video';
  }

  static String _errorText(String code) {
    if (code.contains('link.unsupported') || code.contains('service.unsupported')) return tx('هذا الموقع أو الرابط غير مدعوم', 'This site or link is not supported');
    if (code.contains('link.invalid')) return tx('الرابط غير صحيح', 'Invalid link');
    if (code.contains('content.video.unavailable') || code.contains('content.post.unavailable')) {
      return tx('المحتوى غير متاح أو محذوف', 'Content unavailable or deleted');
    }
    if (code.contains('private')) return tx('المحتوى خاص ولا يمكن تحميله', 'Content is private and cannot be saved');
    if (code.contains('age')) return tx('المحتوى مقيّد بالعمر', 'Content is age-restricted');
    if (code.contains('region')) return tx('المحتوى غير متاح في منطقة السيرفر', 'Content is not available in the server’s region');
    if (code.contains('rate') || code.contains('limit')) return tx('طلبات كثيرة، انتظر قليلاً', 'Too many requests, wait a moment');
    if (code.contains('auth')) return tx('السيرفر يتطلب مفتاح API صحيح', 'The server needs a valid API key');
    return tx('تعذّر التحميل ($code)', 'Could not save ($code)');
  }
}
