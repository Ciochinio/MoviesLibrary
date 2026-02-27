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
  final VoidCallback onExport;
  final VoidCallback? onMove;
  final VoidCallback onTags;
  final VoidCallback onDelete;
  final Future<List<Tag>> Function() loadTags;
  final Future<List<TagKeyValue>> Function() loadKeyValues;
  final List<Widget> extraActions;

  const SharedPlayerPanel({
    super.key,
    required this.item,
    required this.libraryFilesDir,
    required this.thumbsDir,
    required this.allItems,
    this.onTheatreChanged,
    required this.onOpen,
    required this.onExport,
    this.onMove,
    required this.onTags,
    required this.onDelete,
    required this.loadTags,
    required this.loadKeyValues,
    this.extraActions = const [],
  });

  @override
  State<SharedPlayerPanel> createState() => _SharedPlayerPanelState();
}

class _SharedPlayerPanelState extends State<SharedPlayerPanel> {
  late PmlPlayerController _controller;
  bool _theatreMode = false;

  @override
  void initState() {
    super.initState();
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
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openCurrentItem() async {
    final filePath = LibraryFolders.absPath(widget.libraryFilesDir, widget.item.storedRelPath);
    // Init session volume from settings on first open
    final app = context.read<AppState>();
    SessionVolume.instance.initFromSettings(app.settings.startMuted);
    await _controller.open(widget.item, filePath);
    // Autostart video only if setting enabled
    if (!_controller.isStaticImage && !_controller.isGif && app.settings.videoAutostartInPanel) {
      _controller.player.play();
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
    // Player height stays at 16:9 of the panel's normal width
    // In theatre mode the panel is wider so we scale height accordingly
    final playerH = _theatreMode ? (kPanelTheatre * 9 / 16) : (kPanelNormal * 9 / 16);

    return Column(
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
                  onExpand: _openFullPlayer,
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.item.originalName,
                  style: Theme.of(context).textTheme.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmtBytes(widget.item.sizeBytes)}  •  ${widget.item.type.name.toUpperCase()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),

                FutureBuilder<List<Tag>>(
                  key: ValueKey('tags_${widget.item.id}'),
                  future: widget.loadTags(),
                  builder: (ctx, snap) {
                    final tags = snap.data ?? [];
                    if (tags.isEmpty) return const Text('No tags', style: TextStyle(fontSize: 12));
                    return Wrap(spacing: 6, runSpacing: 6,
                        children: [for (final t in tags) Chip(label: Text(t.name))]);
                  },
                ),
                const SizedBox(height: 4),
                FutureBuilder<List<TagKeyValue>>(
                  key: ValueKey('kv_${widget.item.id}'),
                  future: widget.loadKeyValues(),
                  builder: (ctx, snap) {
                    final kv = snap.data ?? [];
                    if (kv.isEmpty) return const SizedBox.shrink();
                    return Wrap(spacing: 6, runSpacing: 6,
                        children: [for (final v in kv) Chip(label: Text(formatKeyValueChip(v)))]);
                  },
                ),

                const Divider(height: 20),

                _ActionBtn(icon: Icons.open_in_new,    label: 'Open in system',   onTap: widget.onOpen),
                _ActionBtn(icon: Icons.open_in_full,   label: 'Full player view', onTap: _openFullPlayer),
                _ActionBtn(icon: Icons.download,       label: 'Export to disk',   onTap: widget.onExport),
                if (widget.onMove != null)
                  _ActionBtn(icon: Icons.drive_file_move, label: 'Move',          onTap: widget.onMove!),
                _ActionBtn(icon: Icons.sell,           label: 'Tags',             onTap: widget.onTags),
                _ActionBtn(icon: Icons.delete,         label: 'Delete',           onTap: widget.onDelete, destructive: true),

                for (final w in widget.extraActions) ...[
                  const SizedBox(height: 6),
                  w,
                ],
              ],
            ),
          ),
        ),
      ],
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

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const _ActionBtn({required this.icon, required this.label, required this.onTap, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label, style: color != null ? TextStyle(color: color) : null),
      ),
    );
  }
}
