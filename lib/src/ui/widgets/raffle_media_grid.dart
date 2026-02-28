import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/library_folders.dart';
import '../../core/models.dart';
import '../widgets/media_grid_controls.dart';

/// Shared thumbnail grid used by RaffleResultScreen and QuickRollResultScreen.
class RaffleMediaGrid extends StatelessWidget {
  final List<MediaItem> items;
  final MediaItem? selected;
  final Set<String> untaggedIds;
  final void Function(MediaItem) onSelect;
  final Widget Function(int index, Widget child)? animationWrapper;

  const RaffleMediaGrid({
    super.key,
    required this.items,
    required this.selected,
    required this.untaggedIds,
    required this.onSelect,
    this.animationWrapper,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final gifAutoplay = app.settings.gifAutoplay;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        final isSelected = selected?.id == item.id;
        final isUntagged = untaggedIds.contains(item.id);

        final absPath = app.isReady
            ? LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath)
            : '';
        final thumbFile = app.isReady
            ? File(p.join(app.paths!.thumbsDir.path, '${item.id}.jpg'))
            : null;
        final hasThumb = thumbFile?.existsSync() ?? false;
        final isGif = isGifPath(item.storedRelPath);

        Widget thumb;
        if (isGif && gifAutoplay) {
          // GIF autoplay ON — always show animated
          thumb = Image.file(
            File(absPath),
            fit: BoxFit.cover,
            cacheWidth: 320,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.image_not_supported, size: 36),
          );
        } else if (hasThumb) {
          thumb = Image(
            image: ResizeImage(FileImage(thumbFile!), width: 320),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 36),
          );
        } else if (item.type == ItemType.image) {
          if (isGif) {
            // GIF autoplay OFF — show static first frame
            thumb = _StaticGifImage(filePath: absPath, fit: BoxFit.cover);
          } else {
            // Static image
            thumb = Image.file(
              File(absPath),
              fit: BoxFit.cover,
              cacheWidth: 320,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.image_not_supported, size: 36),
            );
          }
        } else {
          // Video without thumbnail
          thumb = Container(
            color: cs.surfaceVariant,
            child: Icon(Icons.videocam_outlined,
                size: 36, color: cs.onSurfaceVariant),
          );
        }

        Widget card = GestureDetector(
          onTap: () => onSelect(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? cs.primary : cs.outline.withOpacity(0.2),
                width: isSelected ? 2 : 1,
              ),
              color: isSelected ? cs.primary.withOpacity(0.08) : cs.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(7)),
                    child: thumb,
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.originalName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      if (isUntagged && app.settings.showUntaggedIndicator)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        if (animationWrapper != null) {
          card = animationWrapper!(i, card);
        }

        return card;
      },
    );
  }
}

// ─── Static GIF first-frame widget ────────────────────────────────────────────

class _StaticGifImage extends StatefulWidget {
  final String filePath;
  final BoxFit fit;

  const _StaticGifImage({required this.filePath, this.fit = BoxFit.cover});

  @override
  State<_StaticGifImage> createState() => _StaticGifImageState();
}

class _StaticGifImageState extends State<_StaticGifImage> {
  ui.Image? _frame;
  bool _failed = false;

  static final Map<String, ui.Image> _cache = {};

  @override
  void initState() {
    super.initState();
    _loadFirstFrame();
  }

  @override
  void didUpdateWidget(covariant _StaticGifImage oldWidget) {
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
      final codec =
          await ui.instantiateImageCodec(bytes, targetWidth: 320);
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
    if (_failed) {
      return const Center(child: Icon(Icons.image_not_supported, size: 36));
    }
    if (_frame == null) {
      return const Center(
        child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return RawImage(image: _frame, fit: widget.fit);
  }
}