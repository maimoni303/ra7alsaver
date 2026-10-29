import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n.dart';

import 'package:ra7al_muxer/ra7al_muxer.dart';

import '../services/cobalt.dart';
import '../services/extractor.dart';
import '../services/files.dart';

/// Where downloads go: the app's folder, the device Downloads folder, a folder the user
/// picked, or (iPhone) ask for a destination in the Files app after each download.
enum SaveLocation { app, downloads, custom, ask }

class DownloadTask {
  final MediaItem item;
  double progress = 0; // -1 = unknown size
  String? error;
  File? file;
  bool savedToGallery = false;
  bool exported = false;
  DownloadTask(this.item);
  bool get done => file != null;
}

class SaverState extends ChangeNotifier {
  late SharedPreferences _p;
  bool ready = false;

  ThemeMode themeMode = ThemeMode.dark;
  String server = '';
  String apiKey = '';
  String quality = '1080';
  SaveMode mode = SaveMode.video;
  bool autoGallery = true;
  bool lockFiles = false;
  bool filesUnlocked = false;
  bool english = false;
  SaveLocation saveLocation = SaveLocation.app;
  String customPath = '';

  /// Shown in Settings when the saved folder could not be used at start-up.
  String? locationWarning;

  /// Folder downloads currently go to (for display).
  String saveFolder = '';

  final List<DownloadTask> tasks = [];
  List<SavedFile> files = [];
  bool resolving = false;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    final t = _p.getString('theme') ?? 'dark';
    themeMode = t == 'light' ? ThemeMode.light : t == 'system' ? ThemeMode.system : ThemeMode.dark;
    server = _p.getString('server') ?? '';
    apiKey = _p.getString('apiKey') ?? '';
    quality = _p.getString('quality') ?? '1080';
    mode = SaveMode.values[(_p.getInt('mode') ?? 0).clamp(0, 2)];
    autoGallery = _p.getBool('autoGallery') ?? true;
    lockFiles = _p.getBool('lockFiles') ?? false;
    english = _p.getBool('english') ?? false;
    kEn = english;
    saveLocation = SaveLocation.values[(_p.getInt('saveLocation') ?? 0).clamp(0, SaveLocation.values.length - 1)];
    customPath = _p.getString('customPath') ?? '';
    if (Platform.isMacOS) {
      try {
        await FilePicker.skipEntitlementsChecks(); // the macOS build runs outside the App Sandbox
      } catch (_) {}
    }
    await _applyLocation(startup: true);
    await refreshFiles();
    ready = true;
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _p.setString('theme', m == ThemeMode.light ? 'light' : m == ThemeMode.system ? 'system' : 'dark');
    notifyListeners();
  }

  void setEnglish(bool v) {
    english = v;
    kEn = v;
    _p.setBool('english', v);
    notifyListeners();
  }

  void toggleTheme(Brightness b) => setTheme(b == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  Future<void> setServer(String s, String key) async {
    server = s.trim();
    apiKey = key.trim();
    await _p.setString('server', server);
    await _p.setString('apiKey', apiKey);
    notifyListeners();
  }

  void setQuality(String q) {
    quality = q;
    _p.setString('quality', q);
    notifyListeners();
  }

  void setMode(SaveMode m) {
    mode = m;
    _p.setInt('mode', m.index);
    notifyListeners();
  }

  void setAutoGallery(bool v) {
    autoGallery = v;
    _p.setBool('autoGallery', v);
    notifyListeners();
  }

  // ---- save location ----
  /// Whether this device can save straight into a folder outside the app.
  bool get canPickFolder => !Platform.isIOS;

  Future<String?> _pathFor(SaveLocation l) async => switch (l) {
        SaveLocation.downloads => await FileStore.downloadsDir(),
        SaveLocation.custom => customPath.isEmpty ? null : customPath,
        _ => null,
      };

  Future<void> _applyLocation({bool startup = false}) async {
    if ((saveLocation == SaveLocation.ask && canPickFolder) ||
        (saveLocation != SaveLocation.app && saveLocation != SaveLocation.ask && !canPickFolder)) {
      saveLocation = SaveLocation.app;
    }
    final path = await _pathFor(saveLocation);
    if (path != null) {
      final err = await FileStore.checkWritable(path);
      if (err != null) {
        if (startup) {
          locationWarning = tx('تعذّر الوصول إلى المجلد «$path»، فرجعنا للحفظ داخل التطبيق. اختر المجلد من جديد.',
              'Could not reach “$path”, so saving went back to the app folder. Choose the folder again.');
        }
        saveLocation = SaveLocation.app;
      }
    }
    FileStore.customDir = saveLocation == SaveLocation.app || saveLocation == SaveLocation.ask ? '' : (path ?? '');
    saveFolder = (await FileStore.dir()).path;
  }

  /// Switches to [l] (for [SaveLocation.custom], to [path]). Returns null on success, otherwise why not.
  Future<String?> setSaveLocation(SaveLocation l, {String? path}) async {
    final target = l == SaveLocation.custom ? (path ?? customPath) : await _pathFor(l);
    if (l != SaveLocation.app && l != SaveLocation.ask) {
      if (target == null || target.isEmpty) return tx('لا يوجد مجلد', 'No folder');
      final err = await FileStore.checkWritable(target);
      if (err != null) {
        return tx('لا يمكن الحفظ في هذا المجلد ($err). جرّب مجلد التنزيلات أو مجلداً داخله.',
            'Cannot save in this folder ($err). Try the Downloads folder or a folder inside it.');
      }
    }
    if (l == SaveLocation.custom) {
      customPath = target!;
      await _p.setString('customPath', customPath);
    }
    saveLocation = l;
    locationWarning = null;
    await _p.setInt('saveLocation', l.index);
    await _applyLocation();
    await refreshFiles();
    return null;
  }

  /// Opens the system folder picker and switches to the chosen folder.
  /// Returns null on success or when cancelled, otherwise why it failed.
  Future<String?> pickSaveFolder() async {
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: tx('اختر مجلد الحفظ', 'Choose the download folder'),
      initialDirectory: saveFolder.isEmpty ? null : saveFolder,
    );
    if (picked == null || picked.isEmpty) return null;
    return setSaveLocation(SaveLocation.custom, path: picked);
  }

  Future<void> _exports = Future.value();

  /// iPhone "ask every time": lets the user pick a destination in the Files app.
  /// Runs one at a time, so several finished downloads don't open several pickers at once.
  Future<bool> exportFile(File f) {
    final done = _exports.then((_) => _exportNow(f));
    _exports = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<bool> _exportNow(File f) async {
    try {
      final name = f.uri.pathSegments.last;
      // The document picker needs the whole file in memory; very large files go through the share sheet ("Save to Files").
      if (await f.length() <= 300 * 1024 * 1024) {
        final uri = await FilePicker.saveFile(fileName: name, bytes: await f.readAsBytes(), mimeType: _mime(name));
        return uri != null;
      }
      final r = await Share.shareXFiles([XFile(f.path)]);
      return r.status == ShareResultStatus.success;
    } catch (_) {
      return false;
    }
  }

  static String _mime(String name) => switch (FileStore.typeOf(name)) {
        'video' => 'video/mp4',
        'audio' => 'audio/mpeg',
        'photo' => 'image/jpeg',
        'gif' => 'image/gif',
        _ => 'application/octet-stream',
      };

  // ---- lock ----
  final _auth = LocalAuthentication();

  Future<bool> canLock() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      final ok = await _auth.authenticate(localizedReason: tx('افتح «ملفاتي» في RA7AL SAVER', 'Unlock “My files” in RA7AL SAVER'));
      if (ok) {
        filesUnlocked = true;
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> setLock(bool v) async {
    if (v && !await authenticate()) return;
    lockFiles = v;
    filesUnlocked = true;
    await _p.setBool('lockFiles', v);
    notifyListeners();
  }

  void relock() {
    if (lockFiles) {
      filesUnlocked = false;
      notifyListeners();
    }
  }

  // ---- downloads ----
  /// Reads the link on the device; your own cobalt server (optional, in Settings) is the fallback.
  Future<List<MediaItem>> resolve(String link) async {
    resolving = true;
    notifyListeners();
    try {
      try {
        return await Extractor.resolve(link, mode: mode, quality: quality);
      } on CobaltException {
        if (server.trim().isEmpty) rethrow;
        return (await Cobalt(server, apiKey: apiKey).resolve(link, mode: mode, quality: quality)).items;
      }
    } finally {
      resolving = false;
      notifyListeners();
    }
  }

  Future<void> download(List<MediaItem> items) async {
    for (final it in items) {
      final t = DownloadTask(it);
      tasks.insert(0, t);
      notifyListeners();
      () async {
        try {
          t.file = await _fetch(it, (p) {
            t.progress = p;
            notifyListeners();
          });
          t.progress = 1;
          if (autoGallery && (it.type == 'video' || it.type == 'photo' || it.type == 'gif')) {
            t.savedToGallery = await saveToGallery(t.file!);
          }
          await refreshFiles();
          if (saveLocation == SaveLocation.ask) {
            notifyListeners();
            t.exported = await exportFile(t.file!);
          }
        } catch (e) {
          t.error = tx('فشل التحميل: $e', 'Download failed: $e');
        }
        notifyListeners();
      }();
    }
  }

  /// Downloads [it] and applies its post-processing (merge HD video with audio,
  /// keep only the audio, or drop the audio). Temporary parts are hidden dot-files.
  Future<File> _fetch(MediaItem it, void Function(double) progress) async {
    if (it.post == PostProcess.none) {
      return FileStore.download(it.url, it.filename, progress, headers: it.headers, open: it.open, size: it.size);
    }
    final parts = <File>[];
    try {
      final extra = it.extra;
      final share = extra == null ? 1.0 : (it.size > 0 && extra.size > 0 ? it.size / (it.size + extra.size) : 0.85);
      final ext = it.filename.split('.').last;
      parts.add(await FileStore.download(it.url, 'part_${DateTime.now().microsecondsSinceEpoch}.$ext', (p) => progress(p < 0 ? -1 : p * share * 0.98),
          headers: it.headers, open: it.open, size: it.size, hidden: true));
      if (extra != null) {
        final e2 = extra.filename.split('.').last;
        parts.add(await FileStore.download(extra.url, 'part_${DateTime.now().microsecondsSinceEpoch}.$e2',
            (p) => progress(p < 0 ? -1 : (share + p * (1 - share)) * 0.98),
            headers: extra.headers, open: extra.open, size: extra.size, hidden: true));
      }
      final out = await FileStore.reserve(it.filename);
      try {
        await Ra7alMuxer.remux(
          inputs: parts.map((f) => f.path).toList(),
          output: out.path,
          video: it.post != PostProcess.audioOnly,
          audio: it.post != PostProcess.videoOnly,
        );
      } catch (_) {
        if (await out.exists()) await out.delete();
        rethrow;
      }
      return out;
    } finally {
      for (final f in parts) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  void clearFinished() {
    tasks.removeWhere((t) => t.done || t.error != null);
    notifyListeners();
  }

  Future<bool> saveToGallery(File f) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        if (!await Gal.requestAccess(toAlbum: true)) return false;
      }
      final t = FileStore.typeOf(f.path);
      if (t == 'video') {
        await Gal.putVideo(f.path, album: 'RA7AL');
      } else {
        await Gal.putImage(f.path, album: 'RA7AL');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> refreshFiles() async {
    try {
      files = await FileStore.list();
    } catch (_) {
      files = [];
    }
    notifyListeners();
  }

  /// Returns false when the file could not be deleted (e.g. open in another app).
  Future<bool> deleteFile(SavedFile f) async {
    var ok = true;
    try {
      await f.file.delete();
    } catch (_) {
      ok = false;
    }
    await refreshFiles();
    return ok;
  }

  /// Returns false when the rename failed (the file list is refreshed either way).
  Future<bool> renameFile(SavedFile f, String newName) async {
    var ok = true;
    try {
      await FileStore.rename(f.file, newName);
    } catch (_) {
      ok = false;
    }
    await refreshFiles();
    return ok;
  }
}
