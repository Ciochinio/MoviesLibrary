import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/library_folders.dart';
import '../../core/models.dart';
import '../../core/session_volume.dart';
import '../widgets/media_player_widget.dart';
import '../widgets/tag_manager_dialog.dart';

class FullPlayerScreen extends StatefulWidget {
  final MediaItem initialItem;
  final List<MediaItem> allItems;
  final Directory libraryFilesDir;
  final Directory thumbsDir;

  const FullPlayerScreen({
    super.key,
    required this.initialItem,
    required this.allItems,
    required this.libraryFilesDir,
    required this.thumbsDir,
  });

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  late PmlPlayerController _playerController;
  late MediaItem _current;

  bool _detailsVisible = true;
  bool _isFullscreen = false;
  bool _loopEnabled = false;
  bool _autoplayNext = false;

  // Hover-to-show chrome in fullscreen
  bool _chromeVisible = true;
  Timer? _hideTimer;

  StreamSubscription<void>? _completedSub;
  final ScrollController _filmstripScroll = ScrollController();
  final FocusNode _rootFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _current = widget.initialItem;
    _playerController = PmlPlayerController();
    _subscribeToCompletion();
    _openItem(_current);
  }

  @override
  void dispose() {
    _completedSub?.cancel();
    _hideTimer?.cancel();
    // Restore window chrome when leaving screen in fullscreen
    if (_isFullscreen) {
      windowManager.setFullScreen(false);
      windowManager.setTitleBarStyle(TitleBarStyle.normal);
    }
    _playerController.dispose();
    _filmstripScroll.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  void _subscribeToCompletion() {
    _completedSub = _playerController.player.stream.completed.listen((completed) {
      if (!completed || !mounted) return;
      if (_loopEnabled) {
        _playerController.player.seek(Duration.zero);
        _playerController.player.play();
      } else if (_autoplayNext) {
        _navigateToItem(1);
      }
    });
  }

  Future<void> _openItem(MediaItem item) async {
    final filePath = LibraryFolders.absPath(widget.libraryFilesDir, item.storedRelPath);
    await _playerController.open(item, filePath);
    // Autoplay in full player for video
    if (!_playerController.isStaticImage && !_playerController.isGif) {
      _playerController.player.play();
    }
    if (mounted) setState(() => _current = item);
    _scrollFilmstripToItem(item);
    _rootFocus.requestFocus();
  }

  void _scrollFilmstripToItem(MediaItem item) {
    final index = widget.allItems.indexWhere((e) => e.id == item.id);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_filmstripScroll.hasClients) return;
      const itemW = 126.0;
      final offset = (index * itemW) - (_filmstripScroll.position.viewportDimension / 2) + itemW / 2;
      _filmstripScroll.animateTo(
        offset.clamp(0.0, _filmstripScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _navigateToItem(int delta) {
    final index = widget.allItems.indexWhere((e) => e.id == _current.id);
    if (index < 0) return;
    final newIndex = (index + delta).clamp(0, widget.allItems.length - 1);
    if (newIndex == index) return;
    _openItem(widget.allItems[newIndex]);
  }


  void _toggleDetails() => setState(() => _detailsVisible = !_detailsVisible);

  Rect? _windowRectBeforeFullscreen;

  Future<void> _toggleFullscreen() async {
    final entering = !_isFullscreen;
    if (entering) {
      // Save current position/size then go borderless-maximized
      _windowRectBeforeFullscreen = await windowManager.getBounds();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setFullScreen(true);
    } else {
      // Restore window
      await windowManager.setFullScreen(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      if (_windowRectBeforeFullscreen != null) {
        await windowManager.setBounds(_windowRectBeforeFullscreen!);
      }
    }
    if (!mounted) return;
    setState(() {
      _isFullscreen = entering;
      if (!entering) {
        _chromeVisible = true;
        _hideTimer?.cancel();
      }
    });
    if (entering) _scheduleChromeHide();
  }

  void _onMouseMove() {
    if (!_isFullscreen) return;
    _hideTimer?.cancel();
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _scheduleChromeHide();
  }

  void _scheduleChromeHide() {
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isFullscreen) setState(() => _chromeVisible = false);
    });
  }

  void _adjustVolume(double delta) {
    final sv = SessionVolume.instance;
    sv.volume = (sv.volume + delta).clamp(0.0, 1.0);
    if (sv.muted && delta > 0) sv.muted = false;
    _playerController.player.setVolume(sv.muted ? 0 : sv.volume * 100);
    setState(() {}); // refresh volume slider in MediaPlayerWidget via SessionVolume
  }

  void _toggleMute() {
    final sv = SessionVolume.instance;
    sv.muted = !sv.muted;
    _playerController.player.setVolume(sv.muted ? 0 : sv.volume * 100);
    setState(() {});
  }

  void _skipBack() {
    final pos = _playerController.player.state.position;
    final t = pos - const Duration(seconds: 10);
    _playerController.player.seek(t < Duration.zero ? Duration.zero : t);
  }

  void _skipForward() {
    _playerController.player.seek(
      _playerController.player.state.position + const Duration(seconds: 10),
    );
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    // Flash chrome on any keypress in fullscreen (same as mouse move)
    if (_isFullscreen) _onMouseMove();
    final isDown = event is KeyDownEvent;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        if (isDown && !_playerController.isStaticImage && !_playerController.isGif)
          _playerController.player.playOrPause();
        break;
      case LogicalKeyboardKey.arrowLeft:
        if (!_playerController.isStaticImage && !_playerController.isGif) _skipBack();
        break;
      case LogicalKeyboardKey.arrowRight:
        if (!_playerController.isStaticImage && !_playerController.isGif) _skipForward();
        break;
      case LogicalKeyboardKey.arrowUp:
        _adjustVolume(0.05);
        break;
      case LogicalKeyboardKey.arrowDown:
        _adjustVolume(-0.05);
        break;
      case LogicalKeyboardKey.keyM:
        if (isDown) _toggleMute();
        break;
      case LogicalKeyboardKey.comma:
        if (isDown) _navigateToItem(-1);
        break;
      case LogicalKeyboardKey.period:
        if (isDown) _navigateToItem(1);
        break;
      case LogicalKeyboardKey.escape:
        if (isDown) {
          if (_isFullscreen) _toggleFullscreen();
          else Navigator.of(context).pop();
        }
        break;
      case LogicalKeyboardKey.f11:
      case LogicalKeyboardKey.keyF:
        if (isDown) _toggleFullscreen();
        break;
      case LogicalKeyboardKey.keyL:
        if (isDown) setState(() {
          _loopEnabled = !_loopEnabled;
          if (_loopEnabled) _autoplayNext = false;
        });
        break;
      case LogicalKeyboardKey.keyV:
        if (isDown) _playerController.vrView.value = !_playerController.vrView.value;
        break;
      case LogicalKeyboardKey.keyN:
        if (isDown) setState(() {
          _autoplayNext = !_autoplayNext;
          if (_autoplayNext) _loopEnabled = false;
        });
        break;
    }
  }

  Future<void> _showTagsForItem(MediaItem item) async {
    final app = context.read<AppState>();
    final curSimple = await app.items!.listTagIdsForItem(item.id);
    final curKv = await app.items!.listKeyValueIdsForItem(item.id);
    final picked = await showTagManagerDialog(context,
        initialSimpleTagIds: curSimple, initialKeyValueIds: curKv);
    if (picked == null) return;
    await app.setTagsForItem(
        itemId: item.id, simpleTagIds: picked.simpleTagIds, keyValueIds: picked.keyValueIds);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _onMouseMove(),
          child: Column(
            children: [
              // Top bar — hidden when fullscreen + chrome hidden
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: (!_isFullscreen || _chromeVisible) ? 44 : 0,
                child: _buildTopBar(),
              ),

              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildVideoArea()),
                    if (_detailsVisible && !_isFullscreen) _buildDetailsPanel(),
                  ],
                ),
              ),

              // Filmstrip — hidden in fullscreen
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: (!_isFullscreen || _chromeVisible) ? 110 : 0,
                child: _buildFilmstrip(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 44,
      color: const Color(0xFF0D0D0D),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Text(_current.originalName,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          // Details toggle — hidden in fullscreen (no details panel there)
          if (!_isFullscreen)
            Tooltip(
              message: _detailsVisible ? 'Hide details' : 'Show details',
              child: IconButton(
                onPressed: _toggleDetails,
                icon: Icon(_detailsVisible ? Icons.info : Icons.info_outline,
                    color: _detailsVisible
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white54),
              ),
            ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20, color: Colors.white70),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  // ── Video area ─────────────────────────────────────────────────────────────

  Widget _buildVideoArea() {
    final filePath = LibraryFolders.absPath(widget.libraryFilesDir, _current.storedRelPath);

    return Stack(
      children: [
        // Player — loop/autoplay/fullscreen buttons are INSIDE the controls bar
        Positioned.fill(
          child: MediaPlayerWidget(
            key: ValueKey(_current.id),
            item: _current,
            filePath: filePath,
            controller: _playerController,
            compact: false,
            controlsVisible: !_isFullscreen || _chromeVisible,
            loopEnabled: _loopEnabled,
            autoplayNext: _autoplayNext,
            onLoopToggle: () => setState(() {
              _loopEnabled = !_loopEnabled;
              if (_loopEnabled) _autoplayNext = false;
            }),
            onAutoplayToggle: () => setState(() {
              _autoplayNext = !_autoplayNext;
              if (_autoplayNext) _loopEnabled = false;
            }),
            onFullscreen: _toggleFullscreen,
          ),
        ),

        // Prev/Next side arrows — 72px bottom offset so they never cover the controls bar
        Positioned(
          left: 0,
          top: _isFullscreen ? 0 : 44,
          bottom: 72,
          child: _SideNavButton(
            icon: Icons.chevron_left,
            onTap: () => _navigateToItem(-1),
            enabled: widget.allItems.first.id != _current.id,
          ),
        ),
        Positioned(
          right: 0,
          top: _isFullscreen ? 0 : 44,
          bottom: 72,
          child: _SideNavButton(
            icon: Icons.chevron_right,
            onTap: () => _navigateToItem(1),
            enabled: widget.allItems.last.id != _current.id,
          ),
        ),
      ],
    );
  }

  // ── Details panel ──────────────────────────────────────────────────────────

  Widget _buildDetailsPanel() {
    final app = context.read<AppState>();
    return Container(
      width: 260,
      color: const Color(0xFF111111),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A)))),
            child: Row(children: [
              const Text('Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              InkWell(onTap: _toggleDetails,
                  child: const Icon(Icons.close, size: 16, color: Colors.white54)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _DetailRow('Name', _current.originalName),
                _DetailRow('Type', _current.type.name),
                _DetailRow('Size', _fmtBytes(_current.sizeBytes)),
                _DetailRow('Added', _fmtDate(_current.createdAt)),
                const SizedBox(height: 12),
                const Text('Tags', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                FutureBuilder<List<Tag>>(
                  future: app.items!.listTagsForItem(_current.id),
                  builder: (ctx, snap) {
                    final tags = snap.data ?? [];
                    if (tags.isEmpty) return const Text('No tags', style: TextStyle(color: Colors.white38, fontSize: 12));
                    return Wrap(spacing: 6, runSpacing: 6,
                        children: [for (final t in tags) _TagChip(label: t.name)]);
                  },
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<TagKeyValue>>(
                  future: app.items!.listKeyValuesForItem(_current.id),
                  builder: (ctx, snap) {
                    final kv = snap.data ?? [];
                    if (kv.isEmpty) return const SizedBox.shrink();
                    return Wrap(spacing: 6, runSpacing: 6,
                        children: [for (final v in kv) _TagChip(label: formatKeyValueChip(v))]);
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _showTagsForItem(_current),
                  icon: const Icon(Icons.sell, size: 16),
                  label: const Text('Edit tags'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filmstrip ──────────────────────────────────────────────────────────────

  Widget _buildFilmstrip() {
    return Container(
      color: const Color(0xFF0D0D0D),
      child: ListView.builder(
        controller: _filmstripScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: widget.allItems.length,
        itemBuilder: (ctx, i) {
          final item = widget.allItems[i];
          final isActive = item.id == _current.id;
          final filePath = LibraryFolders.absPath(widget.libraryFilesDir, item.storedRelPath);
          final thumbFile = File(p.join(widget.thumbsDir.path, '${item.id}.jpg'));
          final hasThumb = thumbFile.existsSync();

          Widget thumb;
          if (hasThumb) {
            thumb = Image.file(thumbFile, fit: BoxFit.cover);
          } else if (item.type == ItemType.image) {
            thumb = Image.file(File(filePath), fit: BoxFit.cover, cacheWidth: 160,
                errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white30, size: 28));
          } else {
            thumb = const Center(child: Icon(Icons.movie, color: Colors.white30, size: 28));
          }

          return GestureDetector(
            onTap: () => _openItem(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 120,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Stack(fit: StackFit.expand, children: [
                  thumb,
                  if (isActive)
                    Container(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                      child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 24)),
                    ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  String _fmtDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 54, child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11))),
        Expanded(child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11))),
      ]),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11)),
    );
  }
}

class _SideNavButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  const _SideNavButton({required this.icon, required this.onTap, this.enabled = true});
  @override
  State<_SideNavButton> createState() => _SideNavButtonState();
}

class _SideNavButtonState extends State<_SideNavButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedOpacity(
          opacity: !widget.enabled ? 0.0 : _hovered ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: 48, color: Colors.black45,
            child: Center(child: Icon(widget.icon, color: Colors.white, size: 32)),
          ),
        ),
      ),
    );
  }
}