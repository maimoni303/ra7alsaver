import 'dart:io';

import 'package:flutter/services.dart';

/// Copies the video and/or audio tracks of downloaded files into one MP4/M4A,
/// without re-encoding. Available on iPhone and Android.
class Ra7alMuxer {
  static const _ch = MethodChannel('ra7al_muxer');

  static bool get supported => Platform.isIOS || Platform.isAndroid;

  /// Takes the video track from the first input that has one and the audio track
  /// from the first input that has one, and writes them to [output].
  static Future<void> remux({required List<String> inputs, required String output, bool video = true, bool audio = true}) async {
    if (!supported) throw UnsupportedError('Not available on this device');
    await _ch.invokeMethod<void>('remux', {'inputs': inputs, 'output': output, 'video': video, 'audio': audio});
  }
}
