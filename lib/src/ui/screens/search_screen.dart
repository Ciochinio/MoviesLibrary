import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/library_folders.dart';
import '../../core/models.dart';
import '../widgets/tag_manager_dialog.dart';
import '../widgets/tag_filter_panel.dart';
import '../widgets/media_grid_controls.dart';
import '../widgets/shared_player_panel.dart';

// Sort / Filter enums and helpers are in media_grid_controls.dart
typedef _SortField = SortField;
typedef _TypeFilter = TypeFilter;

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final Set<String> _simpleSelected = {};
  final Set<String> _kvSelected = {};
  final TextEditingController _filenameController = TextEditingController();

  bool _loading = false;
  bool _showFilterPanel = false;
  List<MediaItem> _results = const [];
  double _panelWidth = 300.0;
  MediaItem? _selected;
  int _tagMinMatch = 0; // 0 = all tags required

  // Sort & filter — session only
  _SortField _sortField = _SortField.dateAdded;
  bool _sortAscending = false;
  final Set<_TypeFilter> _typeFilters = {};
  int _shuffleSeed = 0;

  // Untagged indicator
  Set<String> _untaggedIds = {};

  @override
  void dispose() {
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final app = context.read<AppState>();
    if (!app.isReady) return;

    setState(() {
      _loading = true;
      _selected = null;
    });

    try {
      final res = await app.items!.searchItemsGlobal(
        simpleTagIds: _simpleSelected.toList(),
        keyValueIds: _kvSelected.toList(),
        filename: _filenameController.text.trim().isNotEmpty ? _filenameController.text.trim() : null,
        minTagMatch: _tagMinMatch,
      );
      if (!mounted) return;

      // Fetch untagged IDs in one bulk query
      Set<String> untagged = {};
      if (app.settings.showUntaggedIndicator && res.isNotEmpty) {
        untagged = await app.items!.listUntaggedItemIds(res.map((e) => e.id).toList());
      }

      setState(() {
        _results = res;
        _untaggedIds = untagged;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _simpleSelected.clear();
      _kvSelected.clear();
      _tagMinMatch = 0;
      _filenameController.clear();
      _results = const [];
      _selected = null;
      _untaggedIds = {};
      _sortField = _SortField.dateAdded;
      _sortAscending = false;
      _shuffleSeed = 0;
      _typeFilters.clear();
    });
  }

  Future<String?> _pickSubcategoryDialog() async {
    final app = context.read<AppState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Select target subcategory'),
          content: SizedBox(
            width: 520,
            height: 520,
            child: ListView(
              children: [
                for (final c in app.categoryList) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(c.name, style: Theme.of(ctx).textTheme.titleMedium),
                  ),
                  for (final s in app.subcategoriesFor(c.id))
                    ListTile(
                      title: Text('• ${s.name}'),
                      onTap: () => Navigator.pop(ctx, s.id),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ],
        );
      },
    );
  }

  String _uniquePath(String basePath) {
    if (!File(basePath).existsSync()) return basePath;
    final dir = p.dirname(basePath);
    final name = p.basenameWithoutExtension(basePath);
    final ext = p.extension(basePath);
    var i = 1;
    while (true) {
      final cand = p.join(dir, '$name ($i)$ext');
      if (!File(cand).existsSync()) return cand;
      i++;
    }
  }

  // ── Sort & Filter helpers ───────────────────────────────────────────────

  List<MediaItem> _applyFiltersAndSort(List<MediaItem> items) {
    return applyFiltersAndSort(
      items,
      sortField: _sortField,
      sortAscending: _sortAscending,
      typeFilters: _typeFilters,
      shuffleSeed: _shuffleSeed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final displayItems = _applyFiltersAndSort(_results);
    final filterLabel = _typeFilters.isEmpty ? 'All' : _typeFilters.map((f) => f.label).join(', ');
    final sortLabel = _sortField == _SortField.random
        ? 'Random'
        : '${_sortField.label} ${_sortAscending ? '↑' : '↓'}';

    return Row(
      children: [
        // Main content area
        Expanded(
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _filenameController,
                        decoration: InputDecoration(
                          hintText: 'Search by filename...',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          suffixIcon: _filenameController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _filenameController.clear();
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (value) => setState(() {}),
                        onSubmitted: (value) => _runSearch(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showFilterPanel = !_showFilterPanel;
                        });
                      },
                      icon: Icon(_showFilterPanel ? Icons.filter_alt : Icons.filter_alt_outlined),
                      label: Text(_showFilterPanel ? 'Hide Filters' : 'Filters'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: (_simpleSelected.isEmpty && _kvSelected.isEmpty && _filenameController.text.trim().isEmpty)
                          ? null
                          : _runSearch,
                      icon: const Icon(Icons.search),
                      label: const Text('Search'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: (_simpleSelected.isEmpty && _kvSelected.isEmpty && _results.isEmpty && _filenameController.text.isEmpty)
                          ? null
                          : _clearFilters,
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),

              // Active filters display
              if (_simpleSelected.isNotEmpty || _kvSelected.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      const Icon(Icons.filter_alt, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Active filters: ${_simpleSelected.length} tags, ${_kvSelected.length} custom tags',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),

              const Divider(height: 1),

              // Results
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Expanded(
                            child: _loading
                                ? const Center(child: CircularProgressIndicator())
                                : _ItemsGrid(
                                    items: displayItems,
                                    libraryFilesDir: app.paths!.filesDir,
                                    thumbsDir: app.paths!.thumbsDir,
                                    gifAutoplay: app.settings.gifAutoplay,
                                    selectedItemId: _selected?.id,
                                    showTypeMarkers: app.settings.showTypeMarkers,
                                    showUntaggedIndicator: app.settings.showUntaggedIndicator,
                                    untaggedIds: _untaggedIds,
                                    onSelect: (item) => setState(() => _selected = item),
                                  ),
                          ),
                          // ─── Sort / Filter bottom bar ───────────────────
                          if (_results.isNotEmpty) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text('${displayItems.length} result${displayItems.length == 1 ? '' : 's'}',
                                      style: Theme.of(context).textTheme.bodySmall),
                                  const Spacer(),
                                  // Sort dropdown
                                  SortButton(
                                    label: sortLabel,
                                    sortField: _sortField,
                                    sortAscending: _sortAscending,
                                    onChanged: (field, asc) => setState(() {
                                      _sortField = field;
                                      _sortAscending = asc;
                                    }),
                                  ),
                                  const SizedBox(width: 8),
                                  // Type filter dropdown
                                  TypeFilterButton(
                                    label: filterLabel,
                                    selected: _typeFilters,
                                    onChanged: (filters) => setState(() {
                                      _typeFilters.clear();
                                      _typeFilters.addAll(filters);
                                    }),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_selected != null) ...[
                      const VerticalDivider(width: 1),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        width: _panelWidth,
                        child: SharedPlayerPanel(
                          key: ValueKey(_selected!.id),
                          item: _selected!,
                          libraryFilesDir: app.paths!.filesDir,
                          thumbsDir: app.paths!.thumbsDir,
                          allItems: _applyFiltersAndSort(_results),
                          onTheatreChanged: (w) => setState(() => _panelWidth = w),
                          onOpen: () async {
                            final abs = LibraryFolders.absPath(app.paths!.filesDir, _selected!.storedRelPath);
                            await OpenFilex.open(abs);
                          },
                          loadTags: () => app.items!.listTagsForItem(_selected!.id),
                          loadKeyValues: () => app.items!.listKeyValuesForItem(_selected!.id),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // Tag filter side panel
        if (_showFilterPanel)
          TagFilterPanel(
            selectedSimpleTags: _simpleSelected,
            selectedKeyValues: _kvSelected,
            onApply: (minMatch) {
              setState(() => _tagMinMatch = minMatch);
              _runSearch();
            },
            onClear: () {
              setState(() {
                _simpleSelected.clear();
                _kvSelected.clear();
                _tagMinMatch = 0;
              });
            },
            onClose: () {
              setState(() {
                _showFilterPanel = false;
              });
            },
          ),
      ],
    );
  }
}


// ──────────────────────────────────────────────
// Items Grid
// ──────────────────────────────────────────────
class _ItemsGrid extends StatelessWidget {
  final List<MediaItem> items;
  final Directory libraryFilesDir;
  final Directory thumbsDir;
  final bool gifAutoplay;
  final String? selectedItemId;
  final bool showTypeMarkers;
  final bool showUntaggedIndicator;
  final Set<String> untaggedIds;
  final void Function(MediaItem item) onSelect;

  const _ItemsGrid({
    required this.items,
    required this.libraryFilesDir,
    required this.thumbsDir,
    required this.gifAutoplay,
    required this.selectedItemId,
    this.showTypeMarkers = true,
    this.showUntaggedIndicator = true,
    this.untaggedIds = const {},
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No results'));
    }

    return GridView.builder(
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
        final filePath = LibraryFolders.absPath(libraryFilesDir, it.storedRelPath);
        final isSelected = it.id == selectedItemId;

        final thumbFile = File(p.join(thumbsDir.path, '${it.id}.jpg'));
        final hasThumb = thumbFile.existsSync();
        final isGif = isGifPath(filePath);
        final needsThumbIndicator = (it.type == ItemType.video || (isGif && !gifAutoplay)) && !hasThumb;

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
                  child: Stack(
                    children: [
                      Positioned.fill(child: thumb),
                      // ── Type marker badge (bottom-right) ────────────────
                      if (showTypeMarkers)
                        Positioned(
                          right: 8, bottom: 8,
                          child: TypeBadge(item: it, isGif: isGif, hasThumb: hasThumb),
                        ),
                      // ! indicator for videos/GIFs without thumbnail
                      if (needsThumbIndicator)
                        Positioned(
                          left: 8, bottom: 8,
                          child: Container(
                            width: 22, height: 22,
                            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.9), shape: BoxShape.circle),
                            child: const Center(child: Text('!', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
                          ),
                        ),
                      // ── Untagged dot (top-left) ──────────────────────────
                      if (showUntaggedIndicator && untaggedIds.contains(it.id))
                        Positioned(
                          left: 8, top: 8,
                          child: Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: Colors.amber.shade600,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                      if (it.isDuplicate)
                        Positioned(
                          right: 8, top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(999)),
                            child: const Text('DUP', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
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