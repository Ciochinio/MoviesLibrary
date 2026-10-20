import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/session_volume.dart';
import '../../core/vr_format.dart';

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

  /// For VR videos: true shows one eye zoomed in (drag to look around),
  /// false shows the raw side-by-side frame. Toggled by the player's VR button
  /// and the V key in the full player.
  final ValueNotifier<bool> vrView = ValueNotifier(true);

  PmlPlayerController() {
    _player = Player();
    _videoController = VideoController(_player);
    _applySessionVolume();
  }

  void applySessionVolume() => _applySessionVolume();

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
      // Resolve image/GIF aspect ratio here so it's ready before the
      // panel rebuilds — avoids the race where MediaPlayerWidget.initState
      // checks isGif before open() has finished.
      await _resolveImageAspect(filePath);
      return;
    }

    await _player.open(Media(filePath), play: false);
    // Apply immediately as best-effort, then again once media_kit has fully
    // initialised the track (first non-zero duration event). media_kit resets
    // volume internally during track loading, so the deferred call is the one
    // that actually sticks.
    _applySessionVolume();
    _player.stream.duration
        .firstWhere((d) => d > Duration.zero)
        .then((_) => _applySessionVolume())
        .ignore();
  }

  Future<void> _resolveImageAspect(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width.toDouble();
      final h = frame.image.height.toDouble();
      codec.dispose();
      if (w > 0 && h > 0) aspectRatio.value = w / h;
    } catch (_) {}
  }

  /// Notifies listeners when the aspect ratio (width/height) is resolved.
  /// null means not yet known.
  final ValueNotifier<double?> aspectRatio = ValueNotifier(null);

  Future<void> dispose() async {
    aspectRatio.dispose();
    vrView.dispose();
    await _player.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MediaPlayerWidget
//
// For images/GIFs: shows the image with no controls overlay.
// For videos: full player controls.
// ─────────────────────────────────────────────────────────────────────────────

class MediaPlayerWidget extends StatefulWidget {
  final MediaItem item;
  final String filePath;
  final PmlPlayerController controller;
  final VoidCallback? onExpand;
  final bool compact;

  /// When false, controls overlay fades out (fullscreen hide mode).
  final bool controlsVisible;

  // FullPlayerScreen props
  final bool loopEnabled;
  final bool autoplayNext;
  final VoidCallback? onLoopToggle;
  final VoidCallback? onAutoplayToggle;
  final VoidCallback? onFullscreen;

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
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> {
  // ── Video state ───────────────────────────────────────────────────────────
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _videoAspect;

  // ── Volume ────────────────────────────────────────────────────────────────
  double _volume = SessionVolume.instance.volume;
  bool _isMuted = SessionVolume.instance.muted;

  final List<StreamSubscription<dynamic>> _subs = [];

  // ── VR view ───────────────────────────────────────────────────────────────
  VrFormat? _vrFormat;
  double _vrZoom = _vrDefaultZoom;
  /// Offset of the eye's centre from the viewport centre, in logical pixels.
  Offset _vrPan = Offset.zero;
  static const _vrDefaultZoom = 1.6;

  bool get _isImageOrGif => widget.controller.isStaticImage || widget.controller.isGif;

  @override
  void initState() {
    super.initState();
    if (!_isImageOrGif) _subscribeToPlayer();
    widget.controller.vrView.addListener(_onVrViewChanged);
    _loadVrFormat();
  }

  void _onVrViewChanged() { if (mounted) setState(() {}); }

  Future<void> _loadVrFormat() async {
    final id = widget.item.id;
    if (widget.item.type != ItemType.video) return;
    final app = context.read<AppState>();
    if (!app.isReady) return;
    final formats = await app.items!.listVrFormats([id]);
    if (!mounted || widget.item.id != id) return;
    setState(() {
      _vrFormat = formats[id];
      _vrZoom = _vrDefaultZoom;
      _vrPan = Offset.zero;
    });
  }

  @override
  void didUpdateWidget(covariant MediaPlayerWidget old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) {
      for (final s in _subs) s.cancel();
      _subs.clear();
      setState(() {
        _position = Duration.zero;
        _duration = Duration.zero;
        _isPlaying = false;
        _videoAspect = null;
      });
      widget.controller.aspectRatio.value = null;
      if (!_isImageOrGif) _subscribeToPlayer();
      _vrFormat = null;
      _loadVrFormat();
    }
    if (old.controller != widget.controller) {
      old.controller.vrView.removeListener(_onVrViewChanged);
      widget.controller.vrView.addListener(_onVrViewChanged);
    }
    _volume = SessionVolume.instance.volume;
    _isMuted = SessionVolume.instance.muted;
  }

  void _subscribeToPlayer() {
    final player = widget.controller.player;
    _subs.add(player.stream.playing.listen((v) { if (mounted) setState(() => _isPlaying = v); }));
    _subs.add(player.stream.position.listen((v) { if (mounted) setState(() => _position = v); }));
    _subs.add(player.stream.duration.listen((v) { if (mounted) setState(() => _duration = v); }));
    _subs.add(player.stream.width.listen((v) {
      if (mounted && v != null && v > 1) {
        final h = widget.controller.player.state.height;
        if (h != null && h > 1) {
          setState(() => _videoAspect = v / h);
          widget.controller.aspectRatio.value = v / h;
        }
      }
    }));
    _subs.add(player.stream.height.listen((v) {
      if (mounted && v != null && v > 1) {
        final w = widget.controller.player.state.width;
        if (w != null && w > 1) setState(() => _videoAspect = w / v);
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    widget.controller.vrView.removeListener(_onVrViewChanged);
    super.dispose();
  }

  // ── Controls ───────────────────────────────────────────────────────────────

  void togglePlay() => widget.controller.player.playOrPause();

  void skipBack() {
    final t = _position - const Duration(seconds: 10);
    widget.controller.player.seek(t < Duration.zero ? Duration.zero : t);
  }

  void skipForward() => widget.controller.player.seek(_position + const Duration(seconds: 10));

  void seekTo(double fraction) {
    if (_duration == Duration.zero) return;
    widget.controller.player.seek(Duration(milliseconds: (_duration.inMilliseconds * fraction).round()));
  }

  void toggleMute() {
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

  void setVolume(double v) {
    final sv = SessionVolume.instance;
    sv.volume = v;
    sv.muted = v == 0;
    setState(() { _volume = v; _isMuted = v == 0; });
    widget.controller.player.setVolume(v * 100);
  }

  void adjustVolume(double delta) => setVolume((_volume + delta).clamp(0.0, 1.0));


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
    if (_isImageOrGif) return _buildImageViewer();
    return _buildVideoPlayer();
  }

  Widget _withAspectRatio({required double? aspect, required Widget child}) {
    if (aspect == null) return SizedBox.expand(child: child);
    return Center(child: AspectRatio(aspectRatio: aspect, child: child));
  }

  /// Images and GIFs: just the image, no controls overlay.
  /// Expand button shown as a small overlay top-right if onExpand is set.
  Widget _buildImageViewer() {
    return Image.file(
      File(widget.filePath),
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.white38)),
    );
  }

  Widget _buildVideoPlayer() {
    final cs = Theme.of(context).colorScheme;
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Stack(
        children: [
          Positioned.fill(
            child: _vrActive
                ? _buildVrView()
                : GestureDetector(
                    onTap: togglePlay,
                    behavior: HitTestBehavior.opaque,
                    child: _withAspectRatio(
                      aspect: widget.compact ? null : _videoAspect,
                      child: Video(
                        controller: widget.controller.videoController,
                        controls: NoVideoControls,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
          ),
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: widget.controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _buildControlsOverlay(cs, progress),
            ),
          ),
        ],
    );
  }

  bool get _vrActive => _vrFormat != null && widget.controller.vrView.value && _videoAspect != null;

  /// Width/height of one eye as it should be displayed.
  double get _eyeAspect {
    final frame = _videoAspect!;
    return switch (_vrFormat!) {
      VrFormat.sbs180 => 1.0,
      VrFormat.sbs360 || VrFormat.tb360 => 2.0,
      // Full-width 3D SBS keeps each eye's own shape; half-width SBS is squeezed 16:9
      VrFormat.flatSbs => frame >= 3 ? frame / 2 : 16 / 9,
    };
  }

  /// One eye of a VR video, zoomed in. Drag to look around, scroll to zoom,
  /// double-click to reset. A cropped view rather than a true reprojection
  /// (the bundled libmpv has no v360 filter): the centre looks natural, the
  /// edges keep some fisheye curve.
  Widget _buildVrView() {
    final topBottom = _vrFormat == VrFormat.tb360;
    final eyeAspect = _eyeAspect;

    return LayoutBuilder(builder: (ctx, c) {
      final vw = c.maxWidth, vh = c.maxHeight;
      // Eye fitted inside the viewport, then zoomed
      final fitW = (vh * eyeAspect).clamp(0.0, vw);
      final eyeW = fitW * _vrZoom;
      final eyeH = eyeW / eyeAspect;
      final maxX = ((eyeW - vw) / 2).clamp(0.0, double.infinity);
      final maxY = ((eyeH - vh) / 2).clamp(0.0, double.infinity);
      final pan = Offset(_vrPan.dx.clamp(-maxX, maxX), _vrPan.dy.clamp(-maxY, maxY));

      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            setState(() => _vrZoom = (_vrZoom * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(1.0, 5.0));
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: togglePlay,
          onDoubleTap: () => setState(() { _vrZoom = _vrDefaultZoom; _vrPan = Offset.zero; }),
          onPanUpdate: (d) => setState(() => _vrPan = pan + d.delta),
          child: ClipRect(
            child: Stack(children: [
              // Clipped to the eye itself so the other eye never shows,
              // even when the eye is smaller than the viewport
              Positioned(
                left: vw / 2 - eyeW / 2 + pan.dx,
                top: vh / 2 - eyeH / 2 + pan.dy,
                width: eyeW,
                height: eyeH,
                child: ClipRect(
                  // The left (or top) eye sits at the frame's top-left corner
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: topBottom ? eyeW : eyeW * 2,
                    maxWidth: topBottom ? eyeW : eyeW * 2,
                    minHeight: topBottom ? eyeH * 2 : eyeH,
                    maxHeight: topBottom ? eyeH * 2 : eyeH,
                    child: Video(
                      controller: widget.controller.videoController,
                      controls: NoVideoControls,
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _buildControlsOverlay(ColorScheme cs, double progress) {
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
                    onSeek: seekTo,
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
        _ControlButton(icon: Icons.replay_10, onTap: skipBack, size: iconSize, tooltip: '−10s (←)'),
        SizedBox(width: widget.compact ? 2 : 6),
        _ControlButton(
          icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: togglePlay,
          size: widget.compact ? 22 : 28,
          tooltip: 'Play/Pause (Space)',
        ),
        SizedBox(width: widget.compact ? 2 : 6),
        _ControlButton(icon: Icons.forward_10, onTap: skipForward, size: iconSize, tooltip: '+10s (→)'),
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

        _ControlButton(icon: volIcon, onTap: toggleMute, size: iconSize, tooltip: 'Mute (M)'),
        if (!widget.compact) ...[
          const SizedBox(width: 4),
          _VolumeSlider(value: _isMuted ? 0.0 : _volume, onChanged: setVolume),
        ],
        SizedBox(width: widget.compact ? 2 : 8),

        if (_vrFormat != null) ...[
          _ControlButton(
            icon: Icons.vrpano,
            onTap: () => widget.controller.vrView.value = !widget.controller.vrView.value,
            size: iconSize,
            tooltip: widget.controller.vrView.value
                ? 'VR view: drag to look, scroll to zoom, double-click to reset (V)'
                : 'Show VR view (V)',
            active: widget.controller.vrView.value,
            activeColor: cs.primary,
          ),
          SizedBox(width: widget.compact ? 2 : 4),
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
        if (_dragValue != null) { widget.onSeek(_dragValue!); setState(() => _dragValue = null); }
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
            Positioned(left: 0, top: (20 - trackH) / 2, height: trackH, width: value * widget.availableWidth,
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