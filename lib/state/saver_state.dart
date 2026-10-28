import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n.dart';

import '../services/cobalt.dart';
import '../services/files.dart';

class DownloadTask {
  final MediaItem item;
  double progress = 0; // -1 = unknown size
  String? error;
  File? file;
  bool savedToGallery = false;
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
  Future<List<MediaItem>> resolve(String link) async {
    resolving = true;
    notifyListeners();
    try {
      return (await Cobalt(server, apiKey: apiKey).resolve(link, mode: mode, quality: quality)).items;
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
          t.file = await FileStore.download(it.url, it.filename, (p) {
            t.progress = p;
            notifyListeners();
          });
          t.progress = 1;
          if (autoGallery && (it.type == 'video' || it.type == 'photo' || it.type == 'gif')) {
            t.savedToGallery = await saveToGallery(t.file!);
          }
          await refreshFiles();
        } catch (e) {
          t.error = tx('فشل التحميل: $e', 'Download failed: $e');
        }
        notifyListeners();
      }();
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

  Future<void> deleteFile(SavedFile f) async {
    try {
      await f.file.delete();
    } catch (_) {}
    await refreshFiles();
  }

  Future<void> renameFile(SavedFile f, String newName) async {
    final dir = f.file.parent.path;
    final dot = f.name.lastIndexOf('.');
    final ext = dot > 0 ? f.name.substring(dot) : '';
    var n = FileStore.safeName(newName);
    if (!n.contains('.')) n = '$n$ext';
    try {
      await f.file.rename('$dir${Platform.pathSeparator}$n');
    } catch (_) {}
    await refreshFiles();
  }
}
