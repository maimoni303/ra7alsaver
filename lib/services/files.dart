import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../l10n.dart';

class SavedFile {
  final File file;
  final String type; // video | audio | photo | gif | other
  final int size;
  final DateTime modified;
  SavedFile(this.file, this.type, this.size, this.modified);
  String get name => file.uri.pathSegments.last;
}

/// Private download folder ("ملفاتي") inside the app's own storage.
class FileStore {
  static Future<Directory> dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}RA7AL Saver');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String typeOf(String name) {
    final n = name.toLowerCase();
    if (RegExp(r'\.(mp3|m4a|aac|opus|ogg|wav|flac)$').hasMatch(n)) return 'audio';
    if (RegExp(r'\.(jpg|jpeg|png|webp|heic)$').hasMatch(n)) return 'photo';
    if (n.endsWith('.gif')) return 'gif';
    if (RegExp(r'\.(mp4|mov|mkv|webm|m4v|avi)$').hasMatch(n)) return 'video';
    return 'other';
  }

  static Future<List<SavedFile>> list() async {
    final d = await dir();
    final out = <SavedFile>[];
    await for (final e in d.list()) {
      if (e is File && !e.path.endsWith('.part')) {
        final st = await e.stat();
        out.add(SavedFile(e, typeOf(e.path), st.size, st.modified));
      }
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  static String safeName(String name) {
    var n = name.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
    if (n.isEmpty) n = 'ra7al_${DateTime.now().millisecondsSinceEpoch}';
    if (n.length > 120) {
      final dot = n.lastIndexOf('.');
      final ext = dot > 0 ? n.substring(dot) : '';
      n = n.substring(0, 110) + ext;
    }
    return n;
  }

  /// Streams [url] to the private folder, reporting progress 0..1 (or -1 when unknown).
  static Future<File> download(String url, String filename, void Function(double) onProgress) async {
    final d = await dir();
    var name = safeName(filename);
    var target = File('${d.path}${Platform.pathSeparator}$name');
    var n = 1;
    while (await target.exists()) {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      target = File('${d.path}${Platform.pathSeparator}$stem ($n)$ext');
      n++;
    }
    final part = File('${target.path}.part');
    final client = HttpClient()..badCertificateCallback = (c, h, p) => true;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 30));
      final res = await req.close().timeout(const Duration(seconds: 60));
      if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      var got = 0;
      final sink = part.openWrite();
      await for (final chunk in res.timeout(const Duration(seconds: 90))) {
        sink.add(chunk);
        got += chunk.length;
        onProgress(total > 0 ? got / total : -1);
      }
      await sink.flush();
      await sink.close();
      if (got == 0) throw HttpException(tx('الملف فارغ', 'Empty file'));
      return await part.rename(target.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<File> importFile(File src) async {
    final d = await dir();
    final dest = File('${d.path}${Platform.pathSeparator}${safeName(src.uri.pathSegments.last)}');
    return src.copy(dest.path);
  }

  static String human(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
