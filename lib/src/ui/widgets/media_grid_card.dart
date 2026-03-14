import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/models.dart';
import '../../core/library_folders.dart';
import 'media_grid_controls.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StaticGifImage
//
// Decodes and displays only the first frame of a GIF, so animated GIFs appear
// frozen in the grid when gifAutoplay is off. Uses an in-process cache keyed
// by file path to avoid re-decoding on every rebuild.
// ─────────────────────────────────────────────────────────────────────────────

class StaticGifImage extends StatefulWidget {
  final String filePath;
  final BoxFit fit;

  const StaticGifImage({
    super.key,
    required this.filePath,
    this.fit = BoxFit.cover,
  });

  @override
  State<StaticGifImage> createState() => _StaticGifImageState();
}

class _StaticGifImageState extends State<StaticGifImage> {
  ui.Image? _frame;
  bool _failed = false;

  static final Map<String, ui.Image> _cache = {};

  @override
  void initState() {
    super.initState();
    _loadFirstFrame();
  }

  @override
  void didUpdateWidget(covariant StaticGifImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _frame = null;
      _failed = false;
      _loadFirstFrame();
    }
  }

  Future<void> _loadFirstFrame() async {
    final cached = _cache[widget.filePath];
    if (cached != null) {
      if (mounted) setState(() => _frame = cached);
      return;
    }

    try {
      final bytes = await File(widget.filePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 320);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;
      codec.dispose();

      _cache[widget.filePath] = image;
      if (mounted) setState(() => _frame = image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const Center(child: Icon(Icons.image_not_supported, size: 48));
    if (_frame == null) {
      return const Center(
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return RawImage(
      image: _frame,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MediaGridCard
//
// Single card for a media grid. Used by LibraryScreen, SearchScreen, and any
// future screen that shows a media grid.
//
// The containing GridView.builder and its sizing (maxCrossAxisExtent etc.)
// stays in each screen — only the card itself is shared here.
// ─────────────────────────────────────────────────────────────────────────────

class MediaGridCard extends StatelessWidget {
  final MediaItem item;
  final Directory libraryFilesDir;
  final Directory thumbsDir;
  final bool gifAutoplay;

  /// True when this item is the single-selected item shown in the player panel.
  final bool isSelected;

  /// True when this item is part of a bulk selection.
  final bool isBulkSelected;

  final bool selectMode;
  final bool showTypeMarkers;
  final bool showUntaggedIndicator;
  final bool isUntagged;

  /// Show the favourite heart overlay. False for screens that don't support it.
  final bool showFavourite;
  final bool isFavourite;

  /// Cache-bust counter for thumbnails. Increment externally when thumbnail
  /// changes. Pass 0 (default) for screens that don't track thumb versions.
  final int thumbVersion;

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(BuildContext ctx, Offset globalPosition) onContextMenu;

  const MediaGridCard({
    super.key,
    required this.item,
    required this.libraryFilesDir,
    required this.thumbsDir,
    required this.gifAutoplay,
    required this.isSelected,
    required this.isBulkSelected,
    required this.selectMode,
    required this.onTap,
    required this.onLongPress,
    required this.onContextMenu,
    this.showTypeMarkers = true,
    this.showUntaggedIndicator = true,
    this.isUntagged = false,
    this.showFavourite = false,
    this.isFavourite = false,
    this.thumbVersion = 0,
  });

  @override
  Widget build(BuildContext context) {
    final filePath = LibraryFolders.absPath(libraryFilesDir, item.storedRelPath);
    final thumbFile = File(p.join(thumbsDir.path, '${item.id}.jpg'));
    final hasThumb = thumbFile.existsSync();
    final isGif = isGifPath(filePath);
    final needsThumbIndicator =
        (item.type == ItemType.video || (isGif && !gifAutoplay)) && !hasThumb;

    // ── Thumbnail widget ──────────────────────────────────────────────────────
    Widget thumb;

    if (isGif && gifAutoplay) {
      // Animated GIF — Flutter's Image.file animates GIFs natively
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(filePath),
          fit: BoxFit.cover,
          cacheWidth: 320,
          errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, size: 48),
        ),
      );
    } else if (hasThumb) {
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: Colors.black,
          child: Image(
            key: ValueKey('${item.id}_thumb_$thumbVersion'),
            image: ResizeImage(FileImage(thumbFile), width: 320),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 48, color: Colors.white),
          ),
        ),
      );
    } else if (item.type == ItemType.image) {
      if (isGif) {
        // GIF autoplay OFF, no thumbnail — show frozen first frame
        thumb = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: StaticGifImage(filePath: filePath, fit: BoxFit.cover),
        );
      } else {
        thumb = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(filePath),
            fit: BoxFit.cover,
            cacheWidth: 320,
            errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, size: 48),
          ),
        );
      }
    } else if (item.type == ItemType.video) {
      thumb = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.movie, size: 40),
            SizedBox(height: 4),
            Text('Video', style: TextStyle(fontSize: 11)),
          ]),
        ),
      );
    } else {
      thumb = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Center(child: Icon(Icons.insert_drive_file, size: 40)),
      );
    }

    // ── Card ─────────────────────────────────────────────────────────────────
    return GestureDetector(
      onSecondaryTapDown: (details) => onContextMenu(context, details.globalPosition),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              width: (isSelected || isBulkSelected) ? 2 : 1,
              color: isBulkSelected
                  ? Theme.of(context).colorScheme.primary
                  : isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).dividerColor,
            ),
            color: isBulkSelected
                ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                : Theme.of(context).colorScheme.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: thumb),

                    // ── Checkbox overlay (select mode) ──────────────────────
                    if (selectMode)
                      Positioned(
                        left: 8, top: 8,
                        child: Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isBulkSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.black.withOpacity(0.4),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: isBulkSelected
                              ? const Icon(Icons.check, size: 14, color: Colors.white)
                              : null,
                        ),
                      ),

                    // ── Untagged dot (top-left, offset in select mode) ──────
                    if (showUntaggedIndicator && isUntagged)
                      Positioned(
                        left: selectMode ? 36 : 8,
                        top: 8,
                        child: Container(
                          width: 10, height: 10,
                          decoration: BoxDecoration(
                            color: Colors.amber.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),

                    // ── Duplicate badge (top-right) ─────────────────────────
                    if (item.isDuplicate)
                      Positioned(
                        right: 8, top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('DUP',
                              style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ),

                    // ── Favourite heart (top-right, only when not duplicate) ─
                    if (showFavourite && !item.isDuplicate && !selectMode && isFavourite)
                      Positioned(
                        right: 8, top: 8,
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.45),
                          ),
                          child: const Icon(Icons.favorite, size: 16, color: Colors.redAccent),
                        ),
                      ),

                    // ── Type marker badge (bottom-right) ────────────────────
                    if (showTypeMarkers)
                      Positioned(
                        right: 8, bottom: 8,
                        child: TypeBadge(item: item, isGif: isGif, hasThumb: hasThumb),
                      ),

                    // ── No-thumbnail indicator (bottom-left) ────────────────
                    if (needsThumbIndicator)
                      Positioned(
                        left: 8, bottom: 8,
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.9),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text('!',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Filename ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  item.originalName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
