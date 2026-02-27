import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/library_folders.dart';
import '../../core/models.dart';
import '../widgets/media_player_widget.dart';
import '../widgets/tag_manager_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FullPlayerScreen — Option C
// Layout: [VideoArea | Details?] / [Filmstrip]
// Fixes vs v1:
//   - Side nav arrows have top offset so they don't cover the top bar
//   - Back button always accessible via top bar (not hidden behind arrows)
//   - Loop + autoplay next toggles
//   - Keyboard: left/right = ±10s on video, not prev/next item
//     (prev/next item = , / . keys, or filmstrip click)
//   - Fullscreen = hide top bar + filmstrip for immersive in-window view
//   - GIF display works (handled by MediaPlayerWidget)
// ─────────────────────────────────────────────────────────────────────────────

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
    _playerController.dispose();
    _filmstripScroll.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  void _subscribeToCompletion() {
    _completedSub = _playerController.player.stream.completed.listen((completed) {
      if (!completed) return;
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
    if (mounted) setState(() => _current = item);
    _scrollFilmstripToItem(item);
    // Re-focus so keyboard shortcuts keep working
    _rootFocus.requestFocus();
  }

  void _scrollFilmstripToItem(MediaItem item) {
    final index = widget.allItems.indexWhere((e) => e.id == item.id);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_filmstripScroll.hasClients) return;
      const itemW = 126.0; // thumb width + margin
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

  void _toggleFullscreen() => setState(() => _isFullscreen = !_isFullscreen);

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    switch (event.logicalKey) {
      // Prev/next item
      case LogicalKeyboardKey.comma:
        _navigateToItem(-1);
        break;
      case LogicalKeyboardKey.period:
        _navigateToItem(1);
        break;
      case LogicalKeyboardKey.escape:
        if (_isFullscreen) _toggleFullscreen();
        break;
    }
    // Note: space / ← / → / M are handled inside MediaPlayerWidget
  }

  Future<void> _showTagsForItem(MediaItem item) async {
    final app = context.read<AppState>();
    final curSimple = await app.items!.listTagIdsForItem(item.id);
    final curKv = await app.items!.listKeyValueIdsForItem(item.id);
    final picked = await showTagManagerDialog(context,
        initialSimpleTagIds: curSimple, initialKeyValueIds: curKv);
    if (picked == null) return;
    await app.setTagsForItem(
        itemId: item.id,
        simpleTagIds: picked.simpleTagIds,
        keyValueIds: picked.keyValueIds);
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
        body: Column(
          children: [
            if (!_isFullscreen) _buildTopBar(),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildVideoArea()),
                  if (_detailsVisible && !_isFullscreen) _buildDetailsPanel(),
                ],
              ),
            ),
            if (!_isFullscreen) _buildFilmstrip(),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      color: const Color(0xFF0D0D0D),
      child: Row(
        children: [
          // Back — always on left, never covered
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Library'),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
          const SizedBox(width: 8),

          // Item name
          Expanded(
            child: Text(
              _current.originalName,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Loop
          Tooltip(
            message: _loopEnabled ? 'Loop: on' : 'Loop: off',
            child: IconButton(
              onPressed: () => setState(() {
                _loopEnabled = !_loopEnabled;
                if (_loopEnabled) _autoplayNext = false;
              }),
              icon: Icon(Icons.repeat, color: _loopEnabled ? cs.primary : Colors.white38),
            ),
          ),

          // Autoplay next
          Tooltip(
            message: _autoplayNext ? 'Autoplay next: on' : 'Autoplay next: off',
            child: IconButton(
              onPressed: () => setState(() {
                _autoplayNext = !_autoplayNext;
                if (_autoplayNext) _loopEnabled = false;
              }),
              icon: Icon(Icons.skip_next, color: _autoplayNext ? cs.primary : Colors.white38),
            ),
          ),

          // Details toggle
          Tooltip(
            message: _detailsVisible ? 'Hide details' : 'Show details',
            child: IconButton(
              onPressed: _toggleDetails,
              icon: Icon(
                _detailsVisible ? Icons.info : Icons.info_outline,
                color: _detailsVisible ? cs.primary : Colors.white54,
              ),
            ),
          ),

          // Fullscreen
          Tooltip(
            message: _isFullscreen ? 'Exit fullscreen (Esc)' : 'Fullscreen',
            child: IconButton(
              onPressed: _toggleFullscreen,
              icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  // ── Video area ─────────────────────────────────────────────────────────────

  Widget _buildVideoArea() {
    final filePath = LibraryFolders.absPath(widget.libraryFilesDir, _current.storedRelPath);
    // Top bar height — used to offset nav arrows so they don't cover the top bar
    const topBarH = 44.0;
    // Bottom filmstrip height
    const filmstripH = 110.0;

    return Stack(
      children: [
        // Player
        Positioned.fill(
          child: MediaPlayerWidget(
            key: ValueKey(_current.id),
            item: _current,
            filePath: filePath,
            controller: _playerController,
            compact: false,
          ),
        ),

        // Fullscreen overlay buttons (top-right) — only when fullscreen
        if (_isFullscreen)
          Positioned(
            top: 8, right: 8,
            child: Row(
              children: [
                _IconOverlay(icon: Icons.info_outline, onTap: _toggleDetails),
                const SizedBox(width: 4),
                _IconOverlay(icon: Icons.repeat, onTap: () => setState(() => _loopEnabled = !_loopEnabled)),
                const SizedBox(width: 4),
                _IconOverlay(icon: Icons.fullscreen_exit, onTap: _toggleFullscreen),
                const SizedBox(width: 4),
                _IconOverlay(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),

        // Prev arrow — offset from top so it doesn't cover the top bar
        // When fullscreen the top bar is hidden so offset is 0
        Positioned(
          left: 0,
          top: _isFullscreen ? 0 : topBarH,
          bottom: _isFullscreen ? 0 : filmstripH,
          child: _SideNavButton(
            icon: Icons.chevron_left,
            onTap: () => _navigateToItem(-1),
            enabled: widget.allItems.first.id != _current.id,
          ),
        ),

        // Next arrow — same offsets
        Positioned(
          right: 0,
          top: _isFullscreen ? 0 : topBarH,
          bottom: _isFullscreen ? 0 : filmstripH,
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
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
            ),
            child: Row(
              children: [
                const Text('Details',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                InkWell(onTap: _toggleDetails,
                    child: const Icon(Icons.close, size: 16, color: Colors.white54)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow('Name', _current.originalName),
                  _DetailRow('Type', _current.type.name),
                  _DetailRow('Size', _formatBytes(_current.sizeBytes)),
                  _DetailRow('Added', _formatDate(_current.createdAt)),
                  const SizedBox(height: 12),
                  const Text('Tags',
                      style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  FutureBuilder<List<Tag>>(
                    future: app.items!.listTagsForItem(_current.id),
                    builder: (ctx, snap) {
                      final tags = snap.data ?? [];
                      if (tags.isEmpty) {
                        return const Text('No tags',
                            style: TextStyle(color: Colors.white38, fontSize: 12));
                      }
                      return Wrap(
                        spacing: 6, runSpacing: 6,
                        children: [for (final t in tags) _TagChip(label: t.name)],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<TagKeyValue>>(
                    future: app.items!.listKeyValuesForItem(_current.id),
                    builder: (ctx, snap) {
                      final kv = snap.data ?? [];
                      if (kv.isEmpty) return const SizedBox.shrink();
                      return Wrap(
                        spacing: 6, runSpacing: 6,
                        children: [for (final v in kv) _TagChip(label: formatKeyValueChip(v))],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _showTagsForItem(_current),
                    icon: const Icon(Icons.sell, size: 16),
                    label: const Text('Edit tags'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filmstrip ──────────────────────────────────────────────────────────────

  Widget _buildFilmstrip() {
    return Container(
      height: 110,
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
            thumb = Image.file(File(filePath), fit: BoxFit.cover,
              cacheWidth: 160,
              errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white30, size: 28),
            );
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    thumb,
                    if (isActive)
                      Container(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                        child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 24)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime dt) =>
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 54,
            child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11))),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11))),
        ],
      ),
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
      child: Text(label,
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11)),
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
            width: 48,
            color: Colors.black45,
            child: Center(child: Icon(widget.icon, color: Colors.white, size: 32)),
          ),
        ),
      ),
    );
  }
}

class _IconOverlay extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconOverlay({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
