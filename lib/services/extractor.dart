import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../l10n.dart';
import 'cobalt.dart';

/// Finds the downloadable media behind a public link, on the device itself
/// (no server): YouTube, TikTok, Instagram, X/Twitter, Facebook, Snapchat,
/// Pinterest and any page that publishes its video (og:video / JSON-LD),
/// plus direct links to media files.
class Extractor {
  static const _desktopUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';

  static final _yt = YoutubeExplode();

  static Future<List<MediaItem>> resolve(String link, {SaveMode mode = SaveMode.video, String quality = '1080'}) async {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !uri.hasScheme) throw CobaltException(tx('الرابط غير صحيح', 'Invalid link'));
    try {
      final items = await _dispatch(uri, mode, quality, 0);
      if (items.isEmpty) throw CobaltException(tx('لم أجد فيديو أو صورة في هذا الرابط', 'No video or photo found at this link'));
      return items.map((i) => _applyMode(i, mode)).toList();
    } on CobaltException {
      rethrow;
    } on SocketException {
      throw CobaltException(tx('لا يوجد اتصال بالإنترنت', 'No internet connection'), unreachable: true);
    } on TimeoutException {
      throw CobaltException(tx('الموقع تأخر في الرد، أعد المحاولة', 'The site took too long, try again'), unreachable: true);
    } on VideoUnplayableException catch (e) {
      throw CobaltException(tx('الفيديو غير متاح أو خاص أو مقيّد', 'The video is unavailable, private or restricted') + ' (${e.message})');
    } catch (e) {
      throw CobaltException(tx('تعذّر قراءة الرابط: $e', 'Could not read the link: $e'));
    }
  }

  static bool _known(String host) =>
      host.contains('youtube.com') ||
      host == 'youtu.be' ||
      host.contains('tiktok.com') ||
      host.contains('instagram.com') ||
      host == 'x.com' ||
      host.endsWith('.x.com') ||
      host.contains('twitter.com') ||
      host.contains('linkedin.com');

  static Future<List<MediaItem>> _dispatch(Uri uri, SaveMode mode, String quality, int depth) async {
    final host = uri.host.toLowerCase();
    if (_isStreamUrl(uri.toString())) return [_streamItem(uri.toString(), const {})];
    if (_isDirect(uri.path)) {
      return [MediaItem(url: uri.toString(), filename: uri.pathSegments.isEmpty ? 'ra7al.mp4' : Uri.decodeComponent(uri.pathSegments.last), type: _typeOf(uri.path))];
    }
    if (host.contains('youtube.com') || host == 'youtu.be') return _youtube(uri.toString(), mode, quality);
    if (host.contains('tiktok.com')) return _tiktok(uri);
    if (host.contains('instagram.com')) return _instagram(uri);
    if (host == 'x.com' || host.endsWith('.x.com') || host.contains('twitter.com')) return _x(uri);
    if (host.contains('linkedin.com')) return _linkedin(uri);

    // Short links (lnkd.in, t.co, bit.ly, fb.watch, pin.it…): follow them, then read the real page.
    final r = await _get(uri, ua: _desktopUa);
    if (r.isFile) return [_fileItem(r)];
    if (depth < 3) {
      final dest = r.finalUri;
      if (_known(dest.host.toLowerCase())) return _dispatch(dest, mode, quality, depth + 1);
      // lnkd.in and similar show a "you are leaving" page with the real link instead of redirecting.
      final out = RegExp(r'''<a[^>]+(?:external_url_click|data-tracking-control-name="external_url_click")[^>]*href="([^"]+)"''').firstMatch(r.body) ??
          RegExp(r'''<a[^>]+href="([^"]+)"[^>]*data-tracking-control-name="external_url_click"''').firstMatch(r.body);
      final next = out == null ? null : Uri.tryParse(_html(out.group(1)!));
      if (next != null && next.hasScheme && next.host != uri.host) return _dispatch(next, mode, quality, depth + 1);
    }
    return _generic(r);
  }

  /// Audio-only and muted saves: the file is reduced on the device after download.
  static MediaItem _applyMode(MediaItem i, SaveMode mode) {
    if (i.type != 'video' || i.post != PostProcess.none) return i;
    if (mode == SaveMode.audio) return i.copyWith(post: PostProcess.audioOnly, type: 'audio');
    if (mode == SaveMode.mute) return i.copyWith(post: PostProcess.videoOnly);
    return i;
  }

  // ---------------------------------------------------------------- YouTube
  static Future<List<MediaItem>> _youtube(String link, SaveMode mode, String quality) async {
    final id = VideoId(link);
    var manifest = await _yt.videos.streams.getManifest(id);
    if (manifest.streams.isEmpty) {
      manifest = await _yt.videos.streams.getManifest(id, ytClients: [YoutubeApiClient.ios, YoutubeApiClient.androidVr]);
    }
    var title = id.value;
    try {
      title = (await _yt.videos.get(id)).title;
    } catch (_) {}

    MediaItem item(StreamInfo s, String ext, String type) => MediaItem(
          url: s.url.toString(),
          filename: '$title.$ext',
          type: type,
          size: s.size.totalBytes,
          open: () => _yt.videos.streams.get(s),
        );

    final m4a = manifest.audioOnly.where((s) => s.container == StreamContainer.mp4);
    if (mode == SaveMode.audio) {
      if (m4a.isEmpty) throw CobaltException(tx('لا يوجد صوت متوافق لهذا الفيديو', 'No compatible audio for this video'));
      return [item(m4a.withHighestBitrate(), 'm4a', 'audio')];
    }

    final maxH = int.tryParse(quality) ?? 99999;
    // H.264 plays everywhere; above 1080p YouTube only offers AV1, which recent phones play too.
    final candidates = manifest.videoOnly.where((s) =>
        s.container == StreamContainer.mp4 &&
        s.videoResolution.height <= maxH &&
        (s.videoCodec.startsWith('avc1') || (s.videoResolution.height > 1080 && s.videoCodec.startsWith('av01'))));
    if (candidates.isNotEmpty && (m4a.isNotEmpty || mode == SaveMode.mute)) {
      final v = candidates.bestQuality;
      final muxed = manifest.muxed.isEmpty ? null : manifest.muxed.bestQuality;
      if (muxed == null || v.videoResolution.height > muxed.videoResolution.height || mode == SaveMode.mute) {
        final video = item(v, 'mp4', 'video');
        if (mode == SaveMode.mute) return [video];
        return [video.copyWith(post: PostProcess.merge, extra: item(m4a.withHighestBitrate(), 'm4a', 'audio'))];
      }
    }
    if (manifest.muxed.isEmpty) throw CobaltException(tx('لا توجد نسخة قابلة للتحميل من هذا الفيديو', 'No downloadable version of this video'));
    return [item(manifest.muxed.bestQuality, 'mp4', 'video')];
  }

  // ---------------------------------------------------------------- TikTok
  static Future<List<MediaItem>> _tiktok(Uri uri) async {
    var page = uri;
    var m = RegExp(r'/(?:video|photo)/(\d+)').firstMatch(page.path);
    if (m == null) {
      // Short links (vm.tiktok.com / vt.tiktok.com) redirect to the full one.
      page = (await _get(uri, ua: _desktopUa)).finalUri;
      m = RegExp(r'/(?:video|photo)/(\d+)').firstMatch(page.path);
      if (m == null) throw CobaltException(tx('رابط تيك توك غير مدعوم', 'Unsupported TikTok link'));
    }
    final id = m.group(1)!;
    final r = await _get(Uri.parse('https://www.tiktok.com/@i/video/$id'), ua: _desktopUa);
    final data = RegExp(r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>', dotAll: true).firstMatch(r.body);
    if (data == null) throw CobaltException(tx('تعذّر قراءة منشور تيك توك', 'Could not read the TikTok post'));
    final j = jsonDecode(data.group(1)!);
    final detail = j['__DEFAULT_SCOPE__']?['webapp.video-detail'];
    final post = detail?['itemInfo']?['itemStruct'];
    if (post is! Map) {
      throw CobaltException(detail?['statusCode'] == 10204
          ? tx('المحتوى خاص أو محذوف', 'The post is private or deleted')
          : tx('تعذّر قراءة منشور تيك توك', 'Could not read the TikTok post'));
    }
    final headers = {
      'User-Agent': _desktopUa,
      'Referer': 'https://www.tiktok.com/',
      if (r.cookies.isNotEmpty) 'Cookie': r.cookies,
    };
    final images = post['imagePost']?['images'];
    if (images is List && images.isNotEmpty) {
      var i = 0;
      final items = <MediaItem>[];
      for (final img in images) {
        final urls = img['imageURL']?['urlList'];
        if (urls is List && urls.isNotEmpty) {
          i++;
          items.add(MediaItem(url: urls.first.toString(), filename: 'TikTok_${id}_$i.jpg', type: 'photo', headers: headers));
        }
      }
      final music = post['music']?['playUrl']?.toString() ?? '';
      if (music.isNotEmpty) items.add(MediaItem(url: music, filename: 'TikTok_$id.mp3', type: 'audio', headers: headers));
      return items;
    }
    final v = post['video'] as Map? ?? const {};
    String url = (v['playAddr'] ?? '').toString();
    final br = v['bitrateInfo'];
    if (br is List && br.isNotEmpty) {
      final list = br[0]['PlayAddr']?['UrlList'];
      if (list is List && list.isNotEmpty) url = list.last.toString();
    }
    if (url.isEmpty) url = (v['downloadAddr'] ?? '').toString();
    if (url.isEmpty) throw CobaltException(tx('لم أجد فيديو في هذا المنشور', 'No video in this post'));
    return [MediaItem(url: url, filename: 'TikTok_$id.mp4', type: 'video', headers: headers)];
  }

  // ---------------------------------------------------------------- Instagram
  static Future<List<MediaItem>> _instagram(Uri uri) async {
    var page = uri;
    if (page.path.startsWith('/share/')) page = (await _get(uri, ua: _desktopUa)).finalUri;
    final m = RegExp(r'/(?:p|reels?|tv)/([A-Za-z0-9_-]+)').firstMatch(page.path);
    if (m == null) throw CobaltException(tx('رابط إنستقرام غير مدعوم (القصص تحتاج تسجيل دخول)', 'Unsupported Instagram link (stories need a login)'));
    final code = m.group(1)!;
    try {
      final items = await _instagramGraphql(code);
      if (items.isNotEmpty) return items;
    } catch (_) {}
    return _instagramEmbed(code);
  }

  static Future<List<MediaItem>> _instagramGraphql(String code) async {
    const lsd = 'AVqbxe3J_YA';
    final body = 'av=0&__d=www&__user=0&__a=1&lsd=$lsd&fb_api_req_friendly_name=PolarisPostActionLoadPostQueryQuery'
        '&variables=${Uri.encodeQueryComponent(jsonEncode({'shortcode': code, 'fetch_tagged_user_count': null, 'hoisted_comment_id': null, 'hoisted_reply_id': null}))}'
        '&server_timestamps=true&doc_id=8845758582119845';
    final r = await _post(Uri.parse('https://www.instagram.com/graphql/query'), body, headers: {
      'User-Agent': _desktopUa,
      'Content-Type': 'application/x-www-form-urlencoded',
      'X-IG-App-ID': '936619743392459',
      'X-FB-LSD': lsd,
      'X-ASBD-ID': '129477',
      'X-FB-Friendly-Name': 'PolarisPostActionLoadPostQueryQuery',
      'Origin': 'https://www.instagram.com',
      'Referer': 'https://www.instagram.com/p/$code/',
      'Sec-Fetch-Site': 'same-origin',
    });
    final media = jsonDecode(r)['data']?['xdt_shortcode_media'];
    if (media is! Map) return [];
    final out = <MediaItem>[];
    void add(Map n, int i) {
      final suffix = i == 0 ? '' : '_$i';
      if (n['is_video'] == true && (n['video_url'] ?? '').toString().isNotEmpty) {
        out.add(MediaItem(url: n['video_url'].toString(), filename: 'Instagram_$code$suffix.mp4', type: 'video', thumb: (n['display_url'] ?? '').toString()));
      } else if ((n['display_url'] ?? '').toString().isNotEmpty) {
        out.add(MediaItem(url: n['display_url'].toString(), filename: 'Instagram_$code$suffix.jpg', type: 'photo'));
      }
    }
    final edges = media['edge_sidecar_to_children']?['edges'];
    if (edges is List && edges.isNotEmpty) {
      for (var i = 0; i < edges.length; i++) {
        final n = edges[i]['node'];
        if (n is Map) add(n, i + 1);
      }
    } else {
      add(media, 0);
    }
    return out;
  }

  static Future<List<MediaItem>> _instagramEmbed(String code) async {
    final r = await _get(Uri.parse('https://www.instagram.com/p/$code/embed/captioned/'), ua: _desktopUa);
    final html = r.body;
    final out = <MediaItem>[];
    final seen = <String>{};
    for (final m in RegExp(r'\\?"video_url\\?":\\?"(.*?)\\?"').allMatches(html)) {
      final u = _unescape(m.group(1)!);
      if (u.startsWith('http') && seen.add(u)) {
        out.add(MediaItem(url: u, filename: 'Instagram_${code}_${out.length + 1}.mp4', type: 'video'));
      }
    }
    if (out.isNotEmpty) return out;
    for (final m in RegExp(r'class="EmbeddedMediaImage"[^>]*src="([^"]+)"').allMatches(html)) {
      final u = _html(m.group(1)!);
      if (seen.add(u)) out.add(MediaItem(url: u, filename: 'Instagram_${code}_${out.length + 1}.jpg', type: 'photo'));
    }
    if (out.isEmpty) {
      throw CobaltException(tx('تعذّر قراءة منشور إنستقرام (قد يكون الحساب خاصاً)', 'Could not read the Instagram post (the account may be private)'));
    }
    return out;
  }

  // ---------------------------------------------------------------- X / Twitter
  static Future<List<MediaItem>> _x(Uri uri) async {
    final m = RegExp(r'/status(?:es)?/(\d+)').firstMatch(uri.path);
    if (m == null) throw CobaltException(tx('رابط X غير مدعوم', 'Unsupported X link'));
    final id = m.group(1)!;
    final r = await _get(Uri.parse('https://cdn.syndication.twimg.com/tweet-result?id=$id&lang=en&token=${_xToken(id)}'), ua: _desktopUa);
    if (r.status == 404) throw CobaltException(tx('التغريدة غير متاحة أو محذوفة', 'The post is unavailable or deleted'));
    final j = jsonDecode(r.body);
    final media = (j['mediaDetails'] as List?) ?? (j['quoted_tweet']?['mediaDetails'] as List?) ?? const [];
    final out = <MediaItem>[];
    for (final md in media) {
      final n = out.length + 1;
      final type = md['type'];
      if (type == 'photo') {
        out.add(MediaItem(url: '${md['media_url_https']}?name=orig', filename: 'X_${id}_$n.jpg', type: 'photo'));
      } else {
        final variants = ((md['video_info']?['variants'] as List?) ?? const [])
            .where((v) => v['content_type'] == 'video/mp4')
            .toList()
          ..sort((a, b) => ((b['bitrate'] ?? 0) as num).compareTo((a['bitrate'] ?? 0) as num));
        if (variants.isNotEmpty) {
          out.add(MediaItem(url: variants.first['url'].toString(), filename: 'X_${id}_$n.mp4', type: type == 'animated_gif' ? 'gif' : 'video', thumb: (md['media_url_https'] ?? '').toString()));
        }
      }
    }
    if (out.isEmpty) throw CobaltException(tx('لا توجد صور أو فيديو في هذه التغريدة', 'No photos or video in this post'));
    return out.length == 1 ? [out.first.copyWith(filename: out.first.filename.replaceFirst('_1.', '.'))] : out;
  }

  /// Token the X embed endpoint expects: (id / 1e15 * π) in base 36, without zeros and the dot.
  static String _xToken(String id) {
    final n = double.parse(id) / 1e15 * math.pi;
    final whole = n.floor();
    var frac = n - whole;
    final b = StringBuffer(whole.toRadixString(36));
    for (var i = 0; i < 10; i++) {
      frac *= 36;
      final d = frac.floor();
      b.write(d.toRadixString(36));
      frac -= d;
    }
    return b.toString().replaceAll('0', '');
  }

  // ---------------------------------------------------------------- LinkedIn
  static Future<List<MediaItem>> _linkedin(Uri uri) async {
    final r = await _get(uri, ua: _desktopUa);
    final html = r.body;
    final id = RegExp(r'(\d{15,})').firstMatch(uri.toString())?.group(1) ?? '${DateTime.now().millisecondsSinceEpoch}';
    // Public posts list their video files in a data-sources attribute (several bitrates).
    for (final m in RegExp(r'data-sources="([^"]+)"').allMatches(html)) {
      try {
        final list = (jsonDecode(_html(m.group(1)!)) as List).whereType<Map>().where((e) => (e['src'] ?? '').toString().startsWith('http')).toList()
          ..sort((a, b) => ((b['data-bitrate'] ?? 0) as num).compareTo((a['data-bitrate'] ?? 0) as num));
        if (list.isNotEmpty) {
          final poster = RegExp(r'data-poster-url="([^"]+)"').firstMatch(html)?.group(1);
          return [MediaItem(url: list.first['src'].toString(), filename: 'LinkedIn_$id.mp4', type: 'video', thumb: poster == null ? '' : _html(poster))];
        }
      } catch (_) {}
    }
    final images = <String>{};
    for (final m in RegExp(r'<img[^>]+class="[^"]*feed-images__image[^"]*"[^>]*>').allMatches(html)) {
      final src = RegExp(r'(?:data-delayed-url|src)="(https://media\.licdn\.com/[^"]+)"').firstMatch(m.group(0)!);
      if (src != null) images.add(_html(src.group(1)!));
    }
    if (images.isNotEmpty) {
      var i = 0;
      return images.map((u) => MediaItem(url: u, filename: 'LinkedIn_${id}_${++i}.jpg', type: 'photo')).toList();
    }
    if (r.finalUri.path.contains('authwall') || r.finalUri.path.contains('login')) {
      throw CobaltException(tx('لينكدإن يطلب تسجيل دخول لهذا المنشور', 'LinkedIn requires a login for this post'));
    }
    return _generic(r);
  }

  // ---------------------------------------------------------------- Any other page
  static Future<List<MediaItem>> _generic(_Page r) async {
    final html = r.body;
    String name(String ext) => '${r.finalUri.host.replaceFirst('www.', '').split('.').first}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    // Facebook publishes its HD/SD files in the page data.
    for (final key in ['browser_native_hd_url', 'playable_url_quality_hd', 'browser_native_sd_url', 'playable_url', 'hd_src', 'sd_src']) {
      final m = RegExp('"$key":"(https:[^"]+)"').firstMatch(html);
      if (m != null) return [MediaItem(url: _unescape(m.group(1)!), filename: name('mp4'), type: 'video')];
    }
    String? meta(String prop) {
      final a = RegExp('<meta[^>]+(?:property|name)=["\']$prop["\'][^>]*content=["\']([^"\']+)["\']', caseSensitive: false).firstMatch(html);
      final b = RegExp('<meta[^>]+content=["\']([^"\']+)["\'][^>]*(?:property|name)=["\']$prop["\']', caseSensitive: false).firstMatch(html);
      final v = (a ?? b)?.group(1);
      return v == null ? null : _html(v);
    }

    for (final p in ['og:video:secure_url', 'og:video:url', 'og:video', 'twitter:player:stream']) {
      final v = meta(p);
      if (v != null && v.startsWith('http') && !v.contains('/embed')) {
        if (_isStreamUrl(v)) return [_streamItem(v, {'Referer': r.finalUri.toString(), 'User-Agent': _desktopUa})];
        return [MediaItem(url: v, filename: name('mp4'), type: 'video', headers: {'Referer': r.finalUri.toString()})];
      }
    }
    // Streaming playlists written anywhere in the page (most video players).
    final hls = RegExp(r'''(https?:(?:\\?/){2}[^"'\s<>]+?\.(?:m3u8|mpd)[^"'\s<>]*)''').firstMatch(html);
    if (hls != null) {
      return [_streamItem(_unescape(hls.group(1)!.replaceAll(r'\/', '/')), {'Referer': r.finalUri.toString(), 'User-Agent': _desktopUa})];
    }
    // Plain <video>/<source> tags.
    final tag = RegExp(r'''<(?:video|source)[^>]+src=["']([^"']+\.(?:mp4|webm|mov|m4v)[^"']*)["']''', caseSensitive: false).firstMatch(html);
    if (tag != null) {
      final u = r.finalUri.resolve(_html(tag.group(1)!)).toString();
      return [MediaItem(url: u, filename: name('mp4'), type: 'video', headers: {'Referer': r.finalUri.toString()})];
    }
    // JSON-LD VideoObject (Snapchat, Pinterest, many news sites).
    final cu = RegExp(r'"contentUrl"\s*:\s*"(https?:[^"]+)"').firstMatch(html);
    if (cu != null) {
      final u = _unescape(cu.group(1)!);
      return [MediaItem(url: u, filename: name(_typeOf(u) == 'photo' ? 'jpg' : 'mp4'), type: _typeOf(u) == 'photo' ? 'photo' : 'video')];
    }
    final img = meta('og:image');
    if (img != null && img.startsWith('http')) return [MediaItem(url: img, filename: name('jpg'), type: 'photo')];
    throw CobaltException(tx('هذا الموقع غير مدعوم أو المحتوى يتطلب تسجيل دخول', 'This site is not supported or the content needs a login'));
  }

  // ---------------------------------------------------------------- helpers
  static bool _isStreamUrl(String u) => RegExp(r'\.(m3u8|mpd)(\?|#|$)', caseSensitive: false).hasMatch(u);

  static MediaItem _streamItem(String url, Map<String, String> headers, {String name = ''}) => MediaItem(
        url: url,
        filename: '${name.isEmpty ? 'stream_${DateTime.now().millisecondsSinceEpoch}' : name}.mp4',
        type: 'video',
        headers: headers,
        stream: true,
      );

  /// Any downloadable file (PDF, ZIP, APK, documents, media…) — named from the server's
  /// Content-Disposition, the link, or its type.
  static MediaItem _fileItem(_Page r) {
    if (r.mime.contains('mpegurl') || r.mime.contains('dash+xml')) return _streamItem(r.finalUri.toString(), const {});
    var name = '';
    final d = RegExp(r'''filename\*=(?:UTF-8'')?([^;]+)|filename="?([^";]+)"?''', caseSensitive: false).firstMatch(r.disposition);
    if (d != null) name = Uri.decodeComponent((d.group(1) ?? d.group(2) ?? '').trim());
    if (name.isEmpty && r.finalUri.pathSegments.isNotEmpty) name = Uri.decodeComponent(r.finalUri.pathSegments.last);
    if (!name.contains('.')) {
      final ext = _extFor(r.mime);
      name = '${name.isEmpty ? 'file_${DateTime.now().millisecondsSinceEpoch}' : name}${ext.isEmpty ? '' : '.$ext'}';
    }
    final kind = r.mime.startsWith('video/') ? 'video' : r.mime.startsWith('audio/') ? 'audio' : r.mime.startsWith('image/') ? (r.mime.contains('gif') ? 'gif' : 'photo') : 'other';
    return MediaItem(url: r.finalUri.toString(), filename: name, type: kind, size: r.length > 0 ? r.length : 0);
  }

  static String _extFor(String mime) => switch (mime) {
        'video/mp4' => 'mp4',
        'video/webm' => 'webm',
        'video/quicktime' => 'mov',
        'audio/mpeg' => 'mp3',
        'audio/mp4' => 'm4a',
        'audio/wav' || 'audio/x-wav' => 'wav',
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
        'application/pdf' => 'pdf',
        'application/zip' => 'zip',
        'application/vnd.android.package-archive' => 'apk',
        _ => mime.contains('/') ? mime.split('/').last.replaceAll(RegExp(r'[^a-z0-9]'), '') : '',
      };

  static bool _isDirect(String path) => RegExp(r'\.(mp4|mov|m4v|webm|mkv|mp3|m4a|aac|wav|flac|jpg|jpeg|png|webp|gif)$', caseSensitive: false).hasMatch(path);

  static String _typeOf(String path) {
    final p = path.toLowerCase().split('?').first;
    if (RegExp(r'\.(mp3|m4a|aac|wav|flac|opus|ogg)$').hasMatch(p)) return 'audio';
    if (RegExp(r'\.(jpg|jpeg|png|webp|heic)$').hasMatch(p)) return 'photo';
    if (p.endsWith('.gif')) return 'gif';
    return 'video';
  }

  static String _unescape(String s) {
    try {
      return jsonDecode('"$s"') as String;
    } catch (_) {
      return s.replaceAll(r'\/', '/').replaceAll(r'\u0026', '&');
    }
  }

  static String _html(String s) => s.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'");

  static HttpClient _client() => HttpClient()..connectionTimeout = const Duration(seconds: 15);

  static Future<_Page> _get(Uri uri, {required String ua}) async {
    final c = _client();
    try {
      final req = await c.getUrl(uri).timeout(const Duration(seconds: 20));
      req.headers
        ..set(HttpHeaders.userAgentHeader, ua)
        ..set(HttpHeaders.acceptHeader, 'text/html,application/json;q=0.9,*/*;q=0.8')
        ..set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');
      final res = await req.close().timeout(const Duration(seconds: 30));
      final finalUri = res.redirects.isEmpty ? uri : uri.resolveUri(res.redirects.last.location);
      final mime = res.headers.contentType?.mimeType.toLowerCase() ?? '';
      final textual = mime.isEmpty || mime.startsWith('text/') || mime.contains('json') || mime.contains('xml') && !mime.contains('dash');
      if (!textual || mime.contains('mpegurl')) {
        // A file, not a web page: don't read it here, it is downloaded later.
        return _Page('', res.statusCode, finalUri, '', mime: mime, disposition: res.headers.value('content-disposition') ?? '', length: res.contentLength);
      }
      final body = await res.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(const Duration(seconds: 30));
      var cookies = '';
      try {
        cookies = res.cookies.map((k) => '${k.name}=${k.value}').join('; ');
      } catch (_) {}
      return _Page(body, res.statusCode, finalUri, cookies);
    } finally {
      c.close(force: true);
    }
  }

  static Future<String> _post(Uri uri, String body, {required Map<String, String> headers}) async {
    final c = _client();
    try {
      final req = await c.postUrl(uri).timeout(const Duration(seconds: 20));
      headers.forEach(req.headers.set);
      req.write(body);
      final res = await req.close().timeout(const Duration(seconds: 30));
      return await res.transform(const Utf8Decoder(allowMalformed: true)).join();
    } finally {
      c.close(force: true);
    }
  }
}

class _Page {
  final String body;
  final int status;
  final Uri finalUri;
  final String cookies;
  final String mime, disposition;
  final int length;
  _Page(this.body, this.status, this.finalUri, this.cookies, {this.mime = 'text/html', this.disposition = '', this.length = -1});
  bool get isFile => body.isEmpty && !mime.startsWith('text/') && mime.isNotEmpty;
}
