import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../core/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PmlPlayerController
// ─────────────────────────────────────────────────────────────────────────────

class PmlPlayerController {
  late final Player _player;
  late final VideoController _videoController;

  Player get player => _player;
  VideoController get videoController => _videoController;

  bool get isStaticImage => _isStaticImage;
  bool _isStaticImage = false;

  bool get isGif => _isGif;
  bool _isGif = false;

  String? currentFilePath;

  PmlPlayerController() {
    _player = Player();
    _videoController = VideoController(_player);
  }

  Future<void> open(MediaItem item, String filePath) async {
    currentFilePath = filePath;
    final ext = p.extension(filePath).toLowerCase();
    _isGif = ext == '.gif';
    _isStaticImage = item.type == ItemType.image && !_isGif;

    if (_isStaticImage || _isGif) {
      await _player.stop();
      return;
    }

    await _player.open(Media(filePath));
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MediaPlayerWidget
// ─────────────────────────────────────────────────────────────────────────────

class MediaPlayerWidget extends StatefulWidget {
  final MediaItem item;
  final String filePath;
  final PmlPlayerController controller;
  final VoidCallback? onExpand;
  final bool compact;

  const MediaPlayerWidget({
    super.key,
    required this.item,
    required this.filePath,
    required this.controller,
    this.onExpand,
    this.compact = false,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> {
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  bool _isMuted = false;
  double _volumeBeforeMute = 1.0;

  final List<dynamic> _subs = [];
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _subscribeToPlayer();
  }

  @override
  void didUpdateWidget(covariant MediaPlayerWidget old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) {
      setState(() {
        _position = Duration.zero;
        _duration = Duration.zero;
        _isPlaying = false;
      });
    }
  }

  void _subscribeToPlayer() {
    final player = widget.controller.player;
    _subs.add(player.stream.playing.listen((v) { if (mounted) setState(() => _isPlaying = v); }));
    _subs.add(player.stream.position.listen((v) { if (mounted) setState(() => _position = v); }));
    _subs.add(player.stream.duration.listen((v) { if (mounted) setState(() => _duration = v); }));
  }

  @override
  void dispose() {
    for (final s in _subs) { s.cancel(); }
    _focusNode.dispose();
    super.dispose();
  }

  void _togglePlay() => widget.controller.player.playOrPause();

  void _skipBack() {
    final t = _position - const Duration(seconds: 10);
    widget.controller.player.seek(t < Duration.zero ? Duration.zero : t);
  }

  void _skipForward() => widget.controller.player.seek(_position + const Duration(seconds: 10));

  void _seekTo(double fraction) {
    if (_duration == Duration.zero) return;
    widget.controller.player.seek(Duration(milliseconds: (_duration.inMilliseconds * fraction).round()));
  }

  void _toggleMute() {
    if (_isMuted) {
      setState(() { _isMuted = false; _volume = _volumeBeforeMute; });
      widget.controller.player.setVolume(_volumeBeforeMute * 100);
    } else {
      setState(() { _volumeBeforeMute = _volume; _isMuted = true; });
      widget.controller.player.setVolume(0);
    }
  }

  void _setVolume(double v) {
    setState(() { _volume = v; _isMuted = v == 0; });
    widget.controller.player.setVolume(v * 100);
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (widget.controller.isStaticImage || widget.controller.isGif) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space: _togglePlay(); break;
      case LogicalKeyboardKey.arrowLeft: _skipBack(); break;
      case LogicalKeyboardKey.arrowRight: _skipForward(); break;
      case LogicalKeyboardKey.keyM: _toggleMute(); break;
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.isStaticImage) return _buildImageViewer();
    if (widget.controller.isGif) return _buildGifViewer();
    return _buildVideoPlayer();
  }

  Widget _buildImageViewer() {
    return Stack(children: [
      Positioned.fill(
        child: InteractiveViewer(
          minScale: 0.5, maxScale: 8.0,
          child: Image.file(File(widget.filePath), fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.white38)),
          ),
        ),
      ),
      if (widget.onExpand != null)
        Positioned(top: 8, right: 8,
          child: _ControlButton(icon: Icons.open_in_full, onTap: widget.onExpand!, tooltip: 'Open in player view'),
        ),
    ]);
  }

  Widget _buildGifViewer() {
    return Stack(children: [
      Positioned.fill(
        child: InteractiveViewer(
          minScale: 0.5, maxScale: 8.0,
          // No cacheWidth — necessary for animated GIF to render all frames
          child: Image.file(File(widget.filePath), fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.white38)),
          ),
        ),
      ),
      if (widget.onExpand != null)
        Positioned(top: 8, right: 8,
          child: _ControlButton(icon: Icons.open_in_full, onTap: widget.onExpand!, tooltip: 'Open in player view'),
        ),
    ]);
  }

  Widget _buildVideoPlayer() {
    final cs = Theme.of(context).colorScheme;
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Stack(
        children: [
          // 1. Video surface — tap-to-pause gesture wraps it
          Positioned.fill(
            child: GestureDetector(
              onTap: _togglePlay,
              behavior: HitTestBehavior.opaque,
              child: Video(
                controller: widget.controller.videoController,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // 2. Controls overlay — absorbs its own taps so they don't reach video
          Positioned.fill(
            child: _buildControlsOverlay(cs, progress),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay(ColorScheme cs, double progress) {
    return Column(
      children: [
        // Top-right expand button
        if (widget.onExpand != null)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _ControlButton(icon: Icons.open_in_full, onTap: widget.onExpand!, tooltip: 'Open in player view'),
            ),
          )
        else
          const SizedBox(height: 8),

        const Spacer(),

        // Bottom controls: absorb taps so they don't toggle play/pause
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // absorb
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 8 : 12,
              widget.compact ? 18 : 28,
              widget.compact ? 8 : 12,
              widget.compact ? 6 : 10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (ctx, constraints) => _SeekBar(
                    progress: progress,
                    onSeek: _seekTo,
                    accentColor: cs.primary,
                    compact: widget.compact,
                    availableWidth: constraints.maxWidth,
                  ),
                ),
                SizedBox(height: widget.compact ? 4 : 8),
                _buildControlRow(cs),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlRow(ColorScheme cs) {
    final iconSize = widget.compact ? 18.0 : 22.0;
    final volIcon = (_isMuted || _volume == 0) ? Icons.volume_off : Icons.volume_up;

    return Row(
      children: [
        _ControlButton(icon: Icons.replay_10, onTap: _skipBack, size: iconSize, tooltip: '−10s (←)'),
        SizedBox(width: widget.compact ? 2 : 6),
        _ControlButton(
          icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: _togglePlay,
          size: widget.compact ? 22 : 28,
          tooltip: 'Play/Pause (Space)',
        ),
        SizedBox(width: widget.compact ? 2 : 6),
        _ControlButton(icon: Icons.forward_10, onTap: _skipForward, size: iconSize, tooltip: '+10s (→)'),
        SizedBox(width: widget.compact ? 4 : 10),

        Text(
          '${_fmt(_position)} / ${_fmt(_duration)}',
          style: TextStyle(
            color: Colors.white70,
            fontSize: widget.compact ? 10 : 12,
            fontFamily: 'monospace',
          ),
        ),

        const Spacer(),

        _ControlButton(icon: volIcon, onTap: _toggleMute, size: iconSize, tooltip: 'Mute/Unmute (M)'),
        if (!widget.compact) ...[
          SizedBox(
            width: 80,
            child: Slider(
              value: _isMuted ? 0.0 : _volume,
              onChanged: _setVolume,
              activeColor: Colors.white70,
              inactiveColor: Colors.white24,
            ),
          ),
        ],
        SizedBox(width: widget.compact ? 2 : 4),

        // In compact mode the expand button appears in bottom row (not duplicated at top)
        if (widget.onExpand != null && widget.compact)
          _ControlButton(icon: Icons.open_in_full, onTap: widget.onExpand!, size: iconSize, tooltip: 'Player view'),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seek bar — thumb position uses availableWidth from LayoutBuilder
// ─────────────────────────────────────────────────────────────────────────────

class _SeekBar extends StatefulWidget {
  final double progress;
  final void Function(double) onSeek;
  final Color accentColor;
  final bool compact;
  final double availableWidth;

  const _SeekBar({
    required this.progress,
    required this.onSeek,
    required this.accentColor,
    required this.availableWidth,
    this.compact = false,
  });

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  double _fractionFromGlobal(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    return (box.globalToLocal(globalPos).dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final value = _dragValue ?? widget.progress;
    final trackH = widget.compact ? 3.0 : 4.0;
    final thumbD = widget.compact ? 10.0 : 13.0; // diameter
    // Keep thumb inside bar bounds
    final thumbLeft = (value * (widget.availableWidth - thumbD)).clamp(0.0, widget.availableWidth - thumbD);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) => setState(() => _dragValue = _fractionFromGlobal(d.globalPosition)),
      onHorizontalDragUpdate: (d) => setState(() => _dragValue = _fractionFromGlobal(d.globalPosition)),
      onHorizontalDragEnd: (_) {
        if (_dragValue != null) {
          widget.onSeek(_dragValue!);
          setState(() => _dragValue = null);
        }
      },
      onTapDown: (d) => widget.onSeek(_fractionFromGlobal(d.globalPosition)),
      child: SizedBox(
        height: 20,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.none,
          children: [
            // Track
            Positioned(
              left: 0, right: 0,
              top: (20 - trackH) / 2, height: trackH,
              child: Container(
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(trackH)),
              ),
            ),
            // Fill
            Positioned(
              left: 0,
              top: (20 - trackH) / 2, height: trackH,
              width: value * widget.availableWidth,
              child: Container(
                decoration: BoxDecoration(color: widget.accentColor, borderRadius: BorderRadius.circular(trackH)),
              ),
            ),
            // Thumb
            Positioned(
              left: thumbLeft,
              top: (20 - thumbD) / 2,
              child: Container(
                width: thumbD, height: thumbD,
                decoration: BoxDecoration(
                  color: widget.accentColor,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Control button
// ─────────────────────────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final String? tooltip;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.size = 20,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: size, color: Colors.white),
        ),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}
