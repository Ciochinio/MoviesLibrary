import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/library_folders.dart';
import '../widgets/shared_player_panel.dart';

class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  List<MediaItem> _items = [];
  MediaItem? _selected;
  double _panelWidth = 300.0;
  bool _theatreModeActive = false;
  bool _loading = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final app = context.read<AppState>();
    if (!app.isReady) return;
    setState(() => _loading = true);
    _items = await app.loadFavourites();
    if (_selected != null) {
      _selected = _items.where((e) => e.id == _selected!.id).cast<MediaItem?>().firstOrNull;
    }
    setState(() => _loading = false);
  }

  Future<void> _toggleFavourite(String itemId, bool value) async {
    final app = context.read<AppState>();
    await app.toggleFavourite(itemId, value);
    await _reload();
  }


  String _uniquePath(String basePath) {
    if (!File(basePath).existsSync()) return basePath;
    final dir = p.dirname(basePath);
    final name = p.basenameWithoutExtension(basePath);
    final ext = p.extension(basePath);
    int i = 1;
    while (true) {
      final cand = p.join(dir, '$name ($i)$ext');
      if (!File(cand).existsSync()) return cand;
      i++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.isReady) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.favorite, color: Colors.redAccent, size: 22),
              const SizedBox(width: 8),
              Text('Favourites', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(width: 8),
              Text('(${_items.length})', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor)),
              const Spacer(),
              IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _reload),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              // Grid
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                        ? const Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.favorite_border, size: 48, color: Colors.grey),
                              SizedBox(height: 12),
                              Text('No favourites.\nLong-press a file to add.', textAlign: TextAlign.center),
                            ]),
                          )
                        : _FavouritesGrid(
                            items: _items,
                            filesDir: app.paths!.filesDir,
                            thumbsDir: app.paths!.thumbsDir,
                            gifAutoplay: app.settings.gifAutoplay,
                            selectedItemId: _selected?.id,
                            scrollController: _scrollController,
                            onSelect: (item) => setState(() => _selected = item),
                            onToggleFavourite: _toggleFavourite,
                          ),
              ),
              // Details panel
              if (_selected != null) ...[
                const VerticalDivider(width: 1),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  width: _panelWidth,
                  child: SharedPlayerPanel(
                    key: ValueKey(_selected!.id),
                  initialTheatreMode: _theatreModeActive,
                    item: _selected!,
                    libraryFilesDir: app.paths!.filesDir,
                    thumbsDir: app.paths!.thumbsDir,
                    allItems: _items,
                    onTheatreChanged: (w) => setState(() {
                      _panelWidth = w;
                      _theatreModeActive = w > kPanelNormal;
                    }),
                    onOpen: () async {
                      final abs = LibraryFolders.absPath(app.paths!.filesDir, _selected!.storedRelPath);
                      await OpenFilex.open(abs);
                    },
                    loadTags: () => app.items!.listTagsForItem(_selected!.id),
                    loadKeyValues: () => app.items!.listKeyValuesForItem(_selected!.id),
                    extraActions: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _toggleFavourite(_selected!.id, false);
                          setState(() => _selected = null);
                        },
                        icon: const Icon(Icons.heart_broken, size: 16, color: Colors.redAccent),
                        label: const Text('Remove from favourites', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// Grid
// ──────────────────────────────────────────────
class _FavouritesGrid extends StatelessWidget {
  final List<MediaItem> items;
  final Directory filesDir;
  final Directory thumbsDir;
  final bool gifAutoplay;
  final String? selectedItemId;
  final ScrollController scrollController;
  final void Function(MediaItem item) onSelect;
  final void Function(String id, bool value) onToggleFavourite;

  const _FavouritesGrid({
    required this.items,
    required this.filesDir,
    required this.thumbsDir,
    required this.gifAutoplay,
    required this.selectedItemId,
    required this.scrollController,
    required this.onSelect,
    required this.onToggleFavourite,
  });

  bool _isGif(String path) => p.extension(path).toLowerCase() == '.gif';

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 190,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final it = items[i];
        final filePath = LibraryFolders.absPath(filesDir, it.storedRelPath);
        final thumbFile = File(p.join(thumbsDir.path, '${it.id}.jpg'));
        final hasThumb = thumbFile.existsSync();
        final isGif = _isGif(filePath);
        final isSelected = it.id == selectedItemId;

        Widget thumb;
        if (isGif && gifAutoplay) {
          thumb = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(filePath), fit: BoxFit.cover, cacheWidth: 320,
                errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, size: 48)),
          );
        } else if (hasThumb) {
          thumb = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(thumbFile, fit: BoxFit.cover, cacheWidth: 320,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48)),
          );
        } else if (it.type == ItemType.image) {
          thumb = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(filePath), fit: BoxFit.cover, cacheWidth: 320,
                errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, size: 48)),
          );
        } else if (it.type == ItemType.video) {
          thumb = Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const Center(child: Icon(Icons.movie, size: 56)),
          );
        } else {
          thumb = Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const Center(child: Icon(Icons.insert_drive_file, size: 56)),
          );
        }

        return InkWell(
          onTap: () => onSelect(it),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                width: isSelected ? 2 : 1,
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
              ),
              color: Theme.of(context).colorScheme.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(children: [
                    Positioned.fill(child: thumb),
                    // Video badge
                    if (it.type == ItemType.video && hasThumb)
                      Positioned(
                        right: 8, bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.play_arrow, size: 14, color: Colors.white),
                            SizedBox(width: 2),
                            Text('Video', style: TextStyle(color: Colors.white, fontSize: 10)),
                          ]),
                        ),
                      ),
                    // GIF badge
                    if (isGif && hasThumb)
                      Positioned(
                        right: 8, bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
                          child: const Text('GIF', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    // Heart button — tap to unfavourite
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
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(it.originalName, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────
// Details panel
// ──────────────────────────────────────────────