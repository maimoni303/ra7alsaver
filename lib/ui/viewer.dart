import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';

import '../services/files.dart';
import '../theme.dart';
import 'brand_overlay.dart';

/// Plays a saved video/audio file, or shows a photo with pinch-zoom.
class Viewer extends StatefulWidget {
  final SavedFile file;
  const Viewer({super.key, required this.file});
  @override
  State<Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<Viewer> {
  Player? _player;
  VideoController? _video;

  bool get _media => widget.file.type == 'video' || widget.file.type == 'audio';

  @override
  void initState() {
    super.initState();
    // Change the shared logo state after this frame, never while widgets are being built.
    WidgetsBinding.instance.addPostFrameCallback((_) => BrandBus.hidden.value = true);
    if (_media) {
      _player = Player();
      _video = VideoController(_player!);
      _player!.open(Media(widget.file.file.uri.toString()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => BrandBus.hidden.value = false);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Ra7al.dark.accent;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: tx('مشاركة', 'Share'),
            icon: const Icon(Icons.share_rounded),
            onPressed: () => Share.shareXFiles([XFile(widget.file.file.path)]),
          ),
        ],
      ),
      body: _media
          ? Stack(fit: StackFit.expand, children: [
              if (widget.file.type == 'audio')
                Center(child: Icon(Icons.audiotrack_rounded, size: 120, color: accent.withValues(alpha: 0.5))),
              MaterialVideoControlsTheme(
                normal: MaterialVideoControlsThemeData(seekBarPositionColor: accent, seekBarThumbColor: accent),
                fullscreen: MaterialVideoControlsThemeData(seekBarPositionColor: accent, seekBarThumbColor: accent),
                child: MaterialDesktopVideoControlsTheme(
                  normal: MaterialDesktopVideoControlsThemeData(seekBarPositionColor: accent, seekBarThumbColor: accent),
                  fullscreen: MaterialDesktopVideoControlsThemeData(seekBarPositionColor: accent, seekBarThumbColor: accent),
                  child: Video(controller: _video!, fill: Colors.transparent),
                ),
              ),
            ])
          : InteractiveViewer(
              maxScale: 6,
              child: Center(child: Image.file(widget.file.file, fit: BoxFit.contain)),
            ),
    );
  }
}
