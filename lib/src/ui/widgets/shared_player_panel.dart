import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/library_folders.dart';
import '../../core/models.dart';
import 'media_player_widget.dart';
import '../screens/full_player_screen.dart';
import 'tag_manager_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SharedPlayerPanel
//
// Right-side player + details used by Library, Favourites, Search.
//
// Theatre mode: panel widens from 300 → 520px. The parent SizedBox width is
// controlled by the screen via [onTheatreChanged] callback.
// No autoplay timer here — that lives only in FullPlayerScreen.
// ─────────────────────────────────────────────────────────────────────────────

const double kPanelNormal = 300.0;
const double kPanelTheatre = 520.0;

class SharedPlayerPanel extends StatefulWidget {
  final MediaItem item;
  final Directory libraryFilesDir;
  final Directory thumbsDir;
  final List<MediaItem> allItems;

  /// Called when theatre mode toggles, passes new desired width.
  final void Function(double width)? onTheatreChanged;

  final VoidCallback onOpen;
  final Future<List<Tag>> Function() loadTags;
  final Future<List<TagKeyValue>> Function() loadKeyValues;
  final List<Widget> extraActions;

  final bool initialTheatreMode;

  const SharedPlayerPanel({
    super.key,
    required this.item,
    required this.libraryFilesDir,
    required this.thumbsDir,
    required this.allItems,
    this.onTheatreChanged,
    this.initialTheatreMode = false,
    required this.onOpen,
    required this.loadTags,
    required this.loadKeyValues,
    this.extraActions = const [],
  });

  @override
  State<SharedPlayerPanel> createState() => _SharedPlayerPanelState();
}

class _SharedPlayerPanelState extends State<SharedPlayerPanel> {
  late PmlPlayerController _controller;
  late bool _theatreMode;

  // Cached aspect ratio so playerH recalculates immediately on theatre toggle
  // without waiting for the ValueNotifier to re-emit.
  double? _lastAspect;

  StreamSubscription<bool>? _completedSub;

  @override
  void initState() {
    super.initState();
    _theatreMode = widget.initialTheatreMode;
    _controller = PmlPlayerController();
    _openCurrentItem();
  }

  @override
  void didUpdateWidget(covariant SharedPlayerPanel old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) {
      _openCurrentItem();
    }
  }

  @override
  void dispose() {
    _completedSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openCurrentItem() async {
    final filePath = LibraryFolders.absPath(widget.libraryFilesDir, widget.item.storedRelPath);
    final app = context.read<AppState>();

    // Cancel previous completion listener before opening a new item.
    await _completedSub?.cancel();
    _completedSub = null;

    await _controller.open(widget.item, filePath);

    // Re-apply session volume after open — media_kit can reset it internally.
    _controller.applySessionVolume();

    // Autostart video if setting enabled.
    if (!_controller.isStaticImage && !_controller.isGif && app.settings.videoAutostartInPanel) {
      _controller.player.play();
    }

    // Loop videos: seek to start and replay on completion.
    if (!_controller.isStaticImage && !_controller.isGif) {
      _completedSub = _controller.player.stream.completed.listen((completed) {
        if (!completed || !mounted) return;
        _controller.player.seek(Duration.zero);
        _controller.player.play();
      });
    }

    if (mounted) setState(() {});
  }

  void _toggleTheatre() {
    setState(() => _theatreMode = !_theatreMode);
    widget.onTheatreChanged?.call(_theatreMode ? kPanelTheatre : kPanelNormal);
  }

  void _openFullPlayer() {
    _controller.player.pause();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullPlayerScreen(
          initialItem: widget.item,
          allItems: widget.allItems,
          libraryFilesDir: widget.libraryFilesDir,
          thumbsDir: widget.thumbsDir,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filePath = LibraryFolders.absPath(widget.libraryFilesDir, widget.item.storedRelPath);
    final panelW = _theatreMode ? kPanelTheatre : kPanelNormal;

    // Available height = screen height minus title bar (~32) and app header (~52)
    final availableH = MediaQuery.of(context).size.height - 32 - 52;
    final metaReserve = (availableH * 0.35).clamp(240.0, 360.0);
    final maxPlayerH = availableH - metaReserve;

    return ValueListenableBuilder<double?>(
      valueListenable: _controller.aspectRatio,
      builder: (context, aspect, _) {
        // Cache the latest known aspect so theatre toggle (which only calls
        // setState, not the notifier) still recalculates playerH correctly.
        if (aspect != null) _lastAspect = aspect;
        final resolvedAspect = _lastAspect;

        double playerH;
        if (resolvedAspect != null) {
          playerH = (panelW / resolvedAspect).clamp(100.0, maxPlayerH);
        } else {
          playerH = panelW * 9 / 16;
        }

        return SizedBox(
          height: availableH,
          child: Column(
          children: [
        // ── Player ─────────────────────────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          height: playerH,
          color: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: MediaPlayerWidget(
                  key: ValueKey(widget.item.id),
                  item: widget.item,
                  filePath: filePath,
                  controller: _controller,
                  compact: true,
                  // No onExpand — full player accessible via icon button in meta
                  // No onTimerEnd — autoplay only in FullPlayerScreen
                ),
              ),
              // Theatre toggle — top-left overlay
              Positioned(
                top: 6, left: 6,
                child: _OverlayBtn(
                  icon: _theatreMode ? Icons.crop_landscape : Icons.crop_free,
                  tooltip: _theatreMode ? 'Exit theatre mode' : 'Theatre mode',
                  onTap: _toggleTheatre,
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // ── Meta + actions ─────────────────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Meta: filename + fileinfo row with icon actions ──────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.item.originalName,
                      style: Theme.of(context).textTheme.bodyLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_fmtBytes(widget.item.sizeBytes)}  •  ${widget.item.type.name.toUpperCase()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        _IconActionBtn(
                          icon: Icons.open_in_new,
                          tooltip: 'Open in system',
                          onTap: widget.onOpen,
                        ),
                        const SizedBox(width: 4),
                        _IconActionBtn(
                          icon: Icons.open_in_full,
                          tooltip: 'Full player view',
                          onTap: _openFullPlayer,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // ── Tags — fill remaining space, clip if too many ─────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: ClipRect(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FutureBuilder<List<Tag>>(
                          key: ValueKey('tags_${widget.item.id}'),
                          future: widget.loadTags(),
                          builder: (ctx, snap) {
                            final tags = snap.data ?? [];
                            if (tags.isEmpty) return const Text('No tags', style: TextStyle(fontSize: 12, color: Colors.grey));
                            return Wrap(spacing: 4, runSpacing: 4,
                                children: [for (final t in tags) Chip(label: Text(t.name), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)]);
                          },
                        ),
                        const SizedBox(height: 4),
                        FutureBuilder<List<TagKeyValue>>(
                          key: ValueKey('kv_${widget.item.id}'),
                          future: widget.loadKeyValues(),
                          builder: (ctx, snap) {
                            final kv = snap.data ?? [];
                            if (kv.isEmpty) return const SizedBox.shrink();
                            return Wrap(spacing: 4, runSpacing: 4,
                                children: [for (final v in kv) Chip(label: Text(formatKeyValueChip(v)), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)]);
                          },
                        ),
                        for (final w in widget.extraActions) ...[
                          const SizedBox(height: 6),
                          w,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
          ],
        ),
        );
      }, // builder
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _OverlayBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _OverlayBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
          child: Icon(icon, color: Colors.white70, size: 16),
        ),
      ),
    );
  }
}

class _IconActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconActionBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 15, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
        ),
      ),
    );
  }
}