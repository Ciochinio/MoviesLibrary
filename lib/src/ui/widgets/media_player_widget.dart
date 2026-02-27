import 'dart:async';
import 'dart:io';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;



import '../../core/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SessionVolume — app-wide singleton so all players share the same volume
// ─────────────────────────────────────────────────────────────────────────────

class SessionVolume {
  SessionVolume._();
  static final SessionVolume instance = SessionVolume._();

  double volume = 1.0;
  bool muted = false;

  void initFromSettings(bool startMuted) {
    muted = startMuted;
  }
}

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
    _applySessionVolume();
  }

  void _applySessionVolume() {
    final sv = SessionVolume.instance;
    _player.setVolume(sv.muted ? 0 : sv.volume * 100);
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

    await _player.open(Media(filePath), play: false);
    _applySessionVolume();
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

  /// When false, controls overlay fades out (used in fullscreen hide mode).
  final bool controlsVisible;

  // FullPlayerScreen props
  final bool loopEnabled;
  final bool autoplayNext;
  final VoidCallback? onLoopToggle;
  final VoidCallback? onAutoplayToggle;
  final VoidCallback? onFullscreen;
  final VoidCallback? onTimerEnd;
  final bool autoStartTimer;

  const MediaPlayerWidget({
    super.key,
    required this.item,
    required this.filePath,
    required this.controller,
    this.onExpand,
    this.compact = false,
    this.controlsVisible = true,
    this.loopEnabled = false,
    this.autoplayNext = false,
    this.onLoopToggle,
    this.onAutoplayToggle,
    this.onFullscreen,
    this.onTimerEnd,
    this.autoStartTimer = false,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> {
  // ── Video state ───────────────────────────────────────────────────────────
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _videoAspect; // null until we know it

  // ── Volume ────────────────────────────────────────────────────────────────
  double _volume = SessionVolume.instance.volume;
  bool _isMuted = SessionVolume.instance.muted;

  // ── Image/GIF timer ───────────────────────────────────────────────────────
  static const _timerDuration = Duration(seconds: 10);
  Timer? _imgTimer;
  Duration _imgPosition = Duration.zero;
  bool _imgPlaying = false;

  // ── Image aspect ratio ────────────────────────────────────────────────────
  double? _imageAspect; // null until loaded

  final List<StreamSubscription<dynamic>> _subs = [];
  final FocusNode _focusNode = FocusNode();

  bool get _isImageOrGif => widget.controller.isStaticImage || widget.controller.isGif;

  @override
  void initState() {
    super.initState();
    if (!_isImageOrGif) _subscribeToPlayer();
    if (_isImageOrGif) _resolveImageAspect();
    if (_isImageOrGif && widget.autoStartTimer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _imgStart());
    }
  }

  @override
  void didUpdateWidget(covariant MediaPlayerWidget old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) {
      _stopImgTimer();
      for (final s in _subs) s.cancel();
      _subs.clear();
      setState(() {
        _position = Duration.zero;
        _duration = Duration.zero;
        _isPlaying = false;
        _imgPosition = Duration.zero;
        _imgPlaying = false;
        _videoAspect = null;
        _imageAspect = null;
      });
      if (!_isImageOrGif) _subscribeToPlayer();
      if (_isImageOrGif) _resolveImageAspect();
      if (_isImageOrGif && widget.autoStartTimer) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _imgStart());
      }
    }
    _volume = SessionVolume.instance.volume;
    _isMuted = SessionVolume.instance.muted;
  }

  void _subscribeToPlayer() {
    final player = widget.controller.player;
    _subs.add(player.stream.playing.listen((v) { if (mounted) setState(() => _isPlaying = v); }));
    _subs.add(player.stream.position.listen((v) { if (mounted) setState(() => _position = v); }));
    _subs.add(player.stream.duration.listen((v) { if (mounted) setState(() => _duration = v); }));
    // Track video dimensions for aspect ratio
    _subs.add(player.stream.width.listen((v) {
      if (mounted && v != null && v > 1) {  // ignore 1x1 placeholder
        final h = widget.controller.player.state.height;
        if (h != null && h > 1) setState(() => _videoAspect = v / h);
      }
    }));
    _subs.add(player.stream.height.listen((v) {
      if (mounted && v != null && v > 1) {  // ignore 1x1 placeholder
        final w = widget.controller.player.state.width;
        if (w != null && w > 1) setState(() => _videoAspect = w / v);
      }
    }));
  }

  /// Reads image/GIF dimensions to compute aspect ratio
  void _resolveImageAspect() {
    final file = File(widget.filePath);
    if (!file.existsSync()) return;
    final image = Image.file(file);
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        if (!mounted) return;
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w > 0 && h > 0) setState(() => _imageAspect = w / h);
      }),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _stopImgTimer();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Image/GIF timer ────────────────────────────────────────────────────────

  void _imgStart() {
    if (!mounted) return;
    if (_imgPosition >= _timerDuration) setState(() => _imgPosition = Duration.zero);
    setState(() => _imgPlaying = true);
    _stopImgTimer();
    _imgTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final next = _imgPosition + const Duration(milliseconds: 100);
      if (next >= _timerDuration) {
        _stopImgTimer();
        setState(() { _imgPosition = _timerDuration; _imgPlaying = false; });
        widget.onTimerEnd?.call();
      } else {
        setState(() => _imgPosition = next);
      }
    });
  }

  void _stopImgTimer() {
    _imgTimer?.cancel();
    _imgTimer = null;
  }

  void _imgTogglePlay() {
    if (_imgPlaying) { _stopImgTimer(); setState(() => _imgPlaying = false); }
    else { _imgStart(); }
  }

  void _imgSkipBack() {
    final t = _imgPosition - const Duration(seconds: 10);
    setState(() => _imgPosition = t < Duration.zero ? Duration.zero : t);
    if (_imgPlaying) { _stopImgTimer(); _imgStart(); }
  }

  void _imgSkipForward() {
    final t = _imgPosition + const Duration(seconds: 10);
    if (t >= _timerDuration) {
      _stopImgTimer();
      setState(() { _imgPosition = _timerDuration; _imgPlaying = false; });
      widget.onTimerEnd?.call();
    } else {
      setState(() => _imgPosition = t);
      if (_imgPlaying) { _stopImgTimer(); _imgStart(); }
    }
  }

  void _imgSeekTo(double fraction) {
    final t = Duration(milliseconds: (_timerDuration.inMilliseconds * fraction).round());
    setState(() => _imgPosition = t);
    if (_imgPlaying) { _stopImgTimer(); _imgStart(); }
  }

  // ── Unified controls ───────────────────────────────────────────────────────

  void _togglePlay() {
    if (_isImageOrGif) { _imgTogglePlay(); return; }
    widget.controller.player.playOrPause();
  }

  void _skipBack() {
    if (_isImageOrGif) { _imgSkipBack(); return; }
    final t = _position - const Duration(seconds: 10);
    widget.controller.player.seek(t < Duration.zero ? Duration.zero : t);
  }

  void _skipForward() {
    if (_isImageOrGif) { _imgSkipForward(); return; }
    widget.controller.player.seek(_position + const Duration(seconds: 10));
  }

  void _seekTo(double fraction) {
    if (_isImageOrGif) { _imgSeekTo(fraction); return; }
    if (_duration == Duration.zero) return;
    widget.controller.player.seek(Duration(milliseconds: (_duration.inMilliseconds * fraction).round()));
  }

  void _toggleMute() {
    final sv = SessionVolume.instance;
    if (_isMuted) {
      sv.muted = false;
      setState(() => _isMuted = false);
      widget.controller.player.setVolume(sv.volume * 100);
    } else {
      sv.muted = true;
      setState(() => _isMuted = true);
      widget.controller.player.setVolume(0);
    }
  }

  void _setVolume(double v) {
    final sv = SessionVolume.instance;
    sv.volume = v;
    sv.muted = v == 0;
    setState(() { _volume = v; _isMuted = v == 0; });
    widget.controller.player.setVolume(v * 100);
  }

  void _adjustVolume(double delta) {
    final newVol = (_volume + delta).clamp(0.0, 1.0);
    _setVolume(newVol);
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        if (event is KeyDownEvent) _togglePlay();
        break;
      case LogicalKeyboardKey.arrowLeft:
        _skipBack();
        break;
      case LogicalKeyboardKey.arrowRight:
        _skipForward();
        break;
      case LogicalKeyboardKey.arrowUp:
        _adjustVolume(0.05);
        break;
      case LogicalKeyboardKey.arrowDown:
        _adjustVolume(-0.05);
        break;
      case LogicalKeyboardKey.keyM:
        if (event is KeyDownEvent) _toggleMute();
        break;
      case LogicalKeyboardKey.keyF:
        if (event is KeyDownEvent) widget.onFullscreen?.call();
        break;
      case LogicalKeyboardKey.keyL:
        if (event is KeyDownEvent) widget.onLoopToggle?.call();
        break;
      case LogicalKeyboardKey.keyN:
        if (event is KeyDownEvent) widget.onAutoplayToggle?.call();
        break;
    }
  }

  String _fmt(Duration d) {
    if (d == Duration.zero) return '--:--';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isImageOrGif) return _buildImageGifPlayer();
    return _buildVideoPlayer();
  }

  /// Wraps content in an AspectRatio if we know the dimensions,
  /// otherwise fills available space. This eliminates black bars.
  Widget _withAspectRatio({required double? aspect, required Widget child}) {
    if (aspect == null) {
      return SizedBox.expand(child: child);
    }
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: child,
      ),
    );
  }

  Widget _buildImageGifPlayer() {
    final cs = Theme.of(context).colorScheme;
    final progress = _imgPosition.inMilliseconds / _timerDuration.inMilliseconds;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Stack(
        children: [
          // Image/GIF with correct aspect ratio
          Positioned.fill(
            child: GestureDetector(
              onTap: _togglePlay,
              behavior: HitTestBehavior.opaque,
              child: _withAspectRatio(
                aspect: _imageAspect,
                child: Image.file(
                  File(widget.filePath),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.white38)),
                ),
              ),
            ),
          ),
          // Controls — fade out when hidden
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: widget.controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _buildControlsOverlay(cs, progress.clamp(0.0, 1.0), _imgPlaying, showVolume: false),
            ),
          ),
        ],
      ),
    );
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
          // Video with correct aspect ratio
          Positioned.fill(
            child: GestureDetector(
              onTap: _togglePlay,
              behavior: HitTestBehavior.opaque,
              child: _withAspectRatio(
                aspect: _videoAspect,
                child: Video(
                  controller: widget.controller.videoController,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          // Controls — fade out when hidden
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: widget.controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _buildControlsOverlay(cs, progress, _isPlaying, showVolume: true),
            ),
          ),
        ],
      ),
    );
  }

  // ── Controls overlay ───────────────────────────────────────────────────────

  Widget _buildControlsOverlay(ColorScheme cs, double progress, bool isPlaying, {required bool showVolume}) {
    return Column(
      children: [
        const Spacer(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
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
                _buildControlRow(cs, isPlaying, showVolume: showVolume),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlRow(ColorScheme cs, bool isPlaying, {required bool showVolume}) {
    final iconSize = widget.compact ? 18.0 : 22.0;
    final pos = _isImageOrGif ? _imgPosition : _position;
    final dur = _isImageOrGif ? _timerDuration : _duration;
    final volIcon = (_isMuted || _volume == 0) ? Icons.volume_off : Icons.volume_up;

    return Row(
      children: [
        _ControlButton(icon: Icons.replay_10, onTap: _skipBack, size: iconSize, tooltip: '−10s (←)'),
        SizedBox(width: widget.compact ? 2 : 6),
        _ControlButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: _togglePlay,
          size: widget.compact ? 22 : 28,
          tooltip: 'Play/Pause (Space)',
        ),
        SizedBox(width: widget.compact ? 2 : 6),
        _ControlButton(icon: Icons.forward_10, onTap: _skipForward, size: iconSize, tooltip: '+10s (→)'),
        SizedBox(width: widget.compact ? 4 : 10),
        Text(
          '${_fmt(pos)} / ${_fmt(dur)}',
          style: TextStyle(
            color: Colors.white70,
            fontSize: widget.compact ? 10 : 12,
            fontFamily: 'monospace',
          ),
        ),
        const Spacer(),

        if (showVolume) ...[
          _ControlButton(icon: volIcon, onTap: _toggleMute, size: iconSize, tooltip: 'Mute (M)'),
          if (!widget.compact) ...[
            const SizedBox(width: 4),
            _VolumeSlider(value: _isMuted ? 0.0 : _volume, onChanged: _setVolume),
          ],
          SizedBox(width: widget.compact ? 2 : 8),
        ],

        if (widget.onLoopToggle != null)
          _ControlButton(
            icon: Icons.repeat,
            onTap: widget.onLoopToggle!,
            size: iconSize,
            tooltip: 'Loop (L)',
            active: widget.loopEnabled,
            activeColor: cs.primary,
          ),

        if (widget.onAutoplayToggle != null) ...[
          SizedBox(width: widget.compact ? 2 : 4),
          _ControlButton(
            icon: Icons.skip_next,
            onTap: widget.onAutoplayToggle!,
            size: iconSize,
            tooltip: 'Autoplay next (N)',
            active: widget.autoplayNext,
            activeColor: cs.primary,
          ),
        ],

        if (widget.onFullscreen != null) ...[
          SizedBox(width: widget.compact ? 2 : 4),
          _ControlButton(
            icon: Icons.fullscreen,
            onTap: widget.onFullscreen!,
            size: iconSize,
            tooltip: 'Fullscreen (F)',
          ),
        ],

        if (widget.onExpand != null) ...[
          SizedBox(width: widget.compact ? 2 : 4),
          _ControlButton(
            icon: Icons.open_in_full,
            onTap: widget.onExpand!,
            size: iconSize,
            tooltip: 'Open in player view',
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seek bar
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
    final thumbD = widget.compact ? 10.0 : 13.0;
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
        height: 20, width: double.infinity,
        child: Stack(
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.none,
          children: [
            Positioned(left: 0, right: 0, top: (20 - trackH) / 2, height: trackH,
              child: Container(decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(trackH)))),
            Positioned(left: 0, top: (20 - trackH) / 2, height: trackH,
              width: value * widget.availableWidth,
              child: Container(decoration: BoxDecoration(color: widget.accentColor, borderRadius: BorderRadius.circular(trackH)))),
            Positioned(left: thumbLeft, top: (20 - thumbD) / 2,
              child: Container(
                width: thumbD, height: thumbD,
                decoration: BoxDecoration(
                  color: widget.accentColor, shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
                ),
              )),
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
  final bool active;
  final Color? activeColor;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.size = 20,
    this.tooltip,
    this.active = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? (activeColor ?? Colors.white) : Colors.white;
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Volume slider
// ─────────────────────────────────────────────────────────────────────────────

class _VolumeSlider extends StatefulWidget {
  final double value;
  final void Function(double) onChanged;
  const _VolumeSlider({required this.value, required this.onChanged});

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  double? _drag;

  double _fromGlobal(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return widget.value;
    return (box.globalToLocal(global).dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final v = _drag ?? widget.value;
    const trackH = 3.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) => setState(() => _drag = _fromGlobal(d.globalPosition)),
      onHorizontalDragUpdate: (d) {
        final val = _fromGlobal(d.globalPosition);
        setState(() => _drag = val);
        widget.onChanged(val);
      },
      onHorizontalDragEnd: (_) {
        if (_drag != null) { widget.onChanged(_drag!); setState(() => _drag = null); }
      },
      onTapDown: (d) => widget.onChanged(_fromGlobal(d.globalPosition)),
      child: SizedBox(
        width: 100, height: 28,
        child: Center(
          child: LayoutBuilder(builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            return Stack(alignment: Alignment.centerLeft, children: [
              Container(height: trackH, width: w,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(trackH))),
              Container(height: trackH, width: v * w,
                decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(trackH))),
            ]);
          }),
        ),
      ),
    );
  }
}
