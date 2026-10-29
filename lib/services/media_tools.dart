import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../l10n.dart';

/// Output formats the user can pick.
class Formats {
  static const video = ['mp4', 'mkv', 'mov', 'webm', 'avi', 'gif'];
  static const audio = ['m4a', 'mp3', 'wav', 'flac', 'opus', 'aac', 'ogg'];
  static const image = ['jpg', 'png', 'webp', 'bmp', 'gif'];

  /// What a file of [ext] can be turned into.
  static List<String> targetsFor(String ext) {
    final e = ext.toLowerCase();
    if (image.contains(e) && e != 'gif') return image;
    if (audio.contains(e) || const ['mp3', 'wma', 'aiff', 'amr'].contains(e)) return audio;
    if (e == 'gif') return [...image, 'mp4', 'webm'];
    return [...video, ...audio, 'jpg'];
  }
}

/// FFmpeg on the device (all platforms): joins video and audio, downloads live/HLS/DASH
/// streams, and converts any media file to another format.
class MediaTools {
  static Future<void> _run(List<String> args) async {
    final s = await FFmpegKit.executeWithArguments(['-hide_banner', '-nostdin', '-y', ...args]);
    final rc = await s.getReturnCode();
    if (ReturnCode.isSuccess(rc)) return;
    final log = (await s.getAllLogsAsString()) ?? '';
    final lines = log.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    throw MediaToolsException(lines.isEmpty ? 'FFmpeg failed' : lines.sublist(lines.length > 3 ? lines.length - 3 : 0).join(' | '));
  }

  /// Saves a streamed video (m3u8 / mpd / any URL FFmpeg can read) to [out].
  static Future<void> grabStream(String url, String out, {Map<String, String> headers = const {}}) async {
    final h = headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join();
    await _run([
      if (h.isNotEmpty) ...['-headers', h],
      '-i', url,
      '-map', '0:v?', '-map', '0:a?',
      '-c', 'copy',
      out,
    ]);
  }

  /// Writes [out] (format from its extension) from [inputs]: video from the first input that
  /// has it, audio from the last. Copies streams when the format allows; re-encodes otherwise.
  static Future<void> process(List<String> inputs, String out, {bool video = true, bool audio = true}) async {
    final ext = out.split('.').last.toLowerCase();
    final isAudioOut = Formats.audio.contains(ext);
    final isImageOut = Formats.image.contains(ext) && ext != 'gif';
    final keepVideo = video && !isAudioOut;
    final keepAudio = audio && !isImageOut && ext != 'gif';
    final ins = [for (final i in inputs) ...['-i', i]];
    final maps = [
      if (keepVideo) ...['-map', '0:v:0?'],
      if (keepAudio) ...['-map', '${inputs.length - 1}:a:0?'],
      if (!keepVideo) '-vn',
      if (!keepAudio) '-an',
    ];
    final tail = [if (ext == 'mp4' || ext == 'mov' || ext == 'm4a') ...['-movflags', '+faststart'], out];

    if (isImageOut) {
      await _run([...ins, '-map', '0:v:0', '-frames:v', '1', if (ext == 'jpg') ...['-q:v', '2'], out]);
      return;
    }
    if (ext == 'gif') {
      await _run([
        ...ins, '-map', '0:v:0', '-an',
        '-vf', 'fps=12,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse',
        out,
      ]);
      return;
    }
    // 1) Copy without re-encoding when the container accepts the codecs (fast, no quality loss).
    if (_copyable(ext)) {
      try {
        await _run([...ins, ...maps, '-c', 'copy', ...tail]);
        return;
      } catch (_) {
        try {
          await File(out).delete();
        } catch (_) {}
      }
    }
    // 2) Re-encode to codecs that play everywhere for that format.
    await _run([...ins, ...maps, ..._encode(ext, keepVideo, keepAudio), ...tail]);
  }

  /// Length of a media file in seconds (0 when unknown).
  static Future<double> duration(String path) async {
    try {
      final s = await FFprobeKit.getMediaInformation(path);
      return double.tryParse(s.getMediaInformation()?.getDuration() ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Cuts [length] seconds from [start] into a ringtone.
  /// iPhone: AAC in an .m4r (MPEG-4) file, 44.1 kHz stereo, at most 40 s — the format iOS
  /// requires for ringtones (about 0.8 MB). Android: MP3, 44.1 kHz.
  static Future<void> ringtone(String input, String out,
      {required double start, required double length, required bool iphone, bool fade = true}) async {
    final len = iphone ? length.clamp(1, 40).toDouble() : length.clamp(1, 60).toDouble();
    final fadeLen = len >= 6 ? 1.0 : 0.3;
    await _run([
      '-ss', start.toStringAsFixed(2),
      '-t', len.toStringAsFixed(2),
      '-i', input,
      '-vn', '-map', '0:a:0',
      '-ac', '2', '-ar', '44100',
      if (fade) ...['-af', 'afade=t=in:st=0:d=$fadeLen,afade=t=out:st=${(len - fadeLen).toStringAsFixed(2)}:d=$fadeLen'],
      if (iphone) ...['-c:a', 'aac', '-b:a', '160k', '-f', 'ipod', '-movflags', '+faststart']
      else ...['-c:a', 'libmp3lame', '-b:a', '192k', '-f', 'mp3'],
      out,
    ]);
  }

  static bool _copyable(String ext) => const ['mp4', 'mkv', 'mov', 'webm', 'm4a', 'aac', 'avi'].contains(ext);

  static List<String> _encode(String ext, bool v, bool a) {
    List<String> vc() {
      if (!v) return const [];
      if (ext == 'webm') return ['-c:v', 'libvpx-vp9', '-crf', '33', '-b:v', '0', '-deadline', 'realtime', '-cpu-used', '8'];
      if (ext == 'avi') return ['-c:v', 'mpeg4', '-q:v', '3'];
      return ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '21', '-pix_fmt', 'yuv420p'];
    }

    List<String> ac() {
      if (!a) return const [];
      return switch (ext) {
        'mp3' => ['-c:a', 'libmp3lame', '-q:a', '2'],
        'wav' => ['-c:a', 'pcm_s16le'],
        'flac' => ['-c:a', 'flac'],
        'opus' => ['-c:a', 'libopus', '-b:a', '160k'],
        'ogg' => ['-c:a', 'libvorbis', '-q:a', '6'],
        'webm' => ['-c:a', 'libopus', '-b:a', '128k'],
        'avi' => ['-c:a', 'libmp3lame', '-q:a', '2'],
        _ => ['-c:a', 'aac', '-b:a', '192k'],
      };
    }

    return [...vc(), ...ac()];
  }
}

class MediaToolsException implements Exception {
  final String message;
  MediaToolsException(this.message);
  @override
  String toString() => tx('تعذّر تحويل الملف: $message', 'Could not convert the file: $message');
}
