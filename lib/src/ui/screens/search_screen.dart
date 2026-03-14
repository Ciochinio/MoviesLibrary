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
import '../widgets/media_grid_card.dart';
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
  double _panelWidth = kPanelNormal;
  bool _theatreModeActive = false;
  MediaItem? _selected;
  bool _selectMode = false;
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
      _selectMode = false;
    });
    context.read<AppState>().clearItemSelection();

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
      _selectMode = false;
      _untaggedIds = {};
      _sortField = _SortField.dateAdded;
      _sortAscending = false;
      _shuffleSeed = 0;
      _typeFilters.clear();
    });
    context.read<AppState>().clearItemSelection();
  }

  Future<void> _bulkActions() async {
    final app = context.read<AppState>();
    if (app.selectedItemIds.isEmpty) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.sell), title: const Text('Bulk add tag'), onTap: () => Navigator.pop(ctx, 'addTag')),
          ListTile(leading: const Icon(Icons.sell_outlined), title: const Text('Bulk remove tag'), onTap: () => Navigator.pop(ctx, 'removeTag')),
          ListTile(leading: const Icon(Icons.drive_file_move), title: const Text('Move to subcategory'), onTap: () => Navigator.pop(ctx, 'move')),
          ListTile(leading: const Icon(Icons.download), title: const Text('Export to disk'), onTap: () => Navigator.pop(ctx, 'export')),
          ListTile(leading: const Icon(Icons.delete), title: const Text('Delete (permanently)'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'addTag' || choice == 'removeTag') {
      final tagId = await _pickTagDialog();
      if (tagId == null) return;
      if (choice == 'addTag') {
        await app.bulkAddTagToSelected(tagId);
      } else {
        await app.bulkRemoveTagFromSelected(tagId);
      }
      return;
    }
    if (choice == 'move') {
      final subId = await _pickSubcategoryDialog();
      if (subId == null) return;
      await app.moveSelectedItems(subId);
      return;
    }
    if (choice == 'export') {
      final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select directory');
      if (dir == null || !mounted) return;
      final toExport = _applyFiltersAndSort(_results)
          .where((i) => app.selectedItemIds.contains(i.id))
          .toList();
      int okCount = 0;
      for (final item in toExport) {
        final src = File(LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath));
        if (!await src.exists()) continue;
        await src.copy(_uniquePath(p.join(dir, item.originalName)));
        okCount++;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported $okCount file${okCount == 1 ? '' : 's'}.')),
      );
      return;
    }
    if (choice == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete selected?'),
          content: const Text('This will delete records and files from /Library/files.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok == true && mounted) {
        final res = await app.deleteSelectedItems(_applyFiltersAndSort(_results));
        setState(() {
          _results = _results.where((i) => !res.deleted.any((d) => d.id == i.id)).toList();
          _selected = null;
          _selectMode = false;
        });
        if (res.failed.isNotEmpty) {
          final names = res.failed.map((e) => e.originalName).take(3).join(', ');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $names')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${res.deleted.length} items.')));
        }
      }
    }
  }

  Future<String?> _pickTagDialog() async {
    final app = context.read<AppState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select tag'),
        content: SizedBox(
          width: 420,
          height: 300,
          child: ListView(children: [
            for (final t in app.tagList)
              ListTile(title: Text(t.name), onTap: () => Navigator.pop(ctx, t.id)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
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

  // ── Context menu ────────────────────────────────────────────────────────

  void _handleContextMenu(BuildContext gridContext, MediaItem item, Offset globalPosition) {
    final app = context.read<AppState>();
    final filePath = LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath);
    final isVideo = item.type == ItemType.video;
    final isGif = item.type == ItemType.image && p.extension(filePath).toLowerCase() == '.gif';
    final showThumbOption = isVideo || isGif;
    showMenu<String>(
      context: gridContext,
      position: RelativeRect.fromLTRB(globalPosition.dx, globalPosition.dy, globalPosition.dx, globalPosition.dy),
      items: [
        const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit, size: 20), SizedBox(width: 12), Text('Rename...')])),
        const PopupMenuItem(value: 'tags', child: Row(children: [Icon(Icons.sell, size: 20), SizedBox(width: 12), Text('Tagi...')])),
        if (showThumbOption)
          const PopupMenuItem(value: 'thumbnail', child: Row(children: [Icon(Icons.photo_camera, size: 20), SizedBox(width: 12), Text('Set Thumbnail...')])),
        const PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.download, size: 20), SizedBox(width: 12), Text('Export...')])),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'open_folder', child: Row(children: [Icon(Icons.folder_open, size: 20), SizedBox(width: 12), Text('Show in folder')])),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 20, color: Colors.red), SizedBox(width: 12), Text('Delete', style: TextStyle(color: Colors.red))])),
      ],
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case 'rename':     await _showRenameDialog(item); break;
        case 'tags':       await _showTagsForItem(item); break;
        case 'thumbnail':  await _showThumbnailPicker(item); break;
        case 'export':     await _exportItem(item); break;
        case 'open_folder': await _openInFolder(item); break;
        case 'delete':     await _deleteItem(item); break;
      }
    });
  }

  Future<void> _showRenameDialog(MediaItem item) async {
    final app = context.read<AppState>();
    final ctrl = TextEditingController(text: item.originalName);
    final dotIndex = item.originalName.lastIndexOf('.');
    if (dotIndex > 0) ctrl.selection = TextSelection(baseOffset: 0, extentOffset: dotIndex);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setState) => AlertDialog(
          title: const Text('Rename'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'New file name',
                  border: OutlineInputBorder(),
                  helperText: 'Tags and metadata will be preserved',
                ),
                autofocus: true,
                onSubmitted: (v) => Navigator.pop(dialogCtx, v),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Suggest from tags'),
                  onPressed: () async {
                    final suggested = await app.suggestName(item.id, item.originalName);
                    ctrl.text = suggested;
                    final dot = suggested.lastIndexOf('.');
                    ctrl.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: dot > 0 ? dot : suggested.length,
                    );
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogCtx, ctrl.text), child: const Text('Rename')),
          ],
        ),
      ),
    );
    if (newName == null || newName.trim().isEmpty || newName.trim() == item.originalName) return;
    final success = await app.items!.renameItem(item, newName.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? 'Renamed' : 'Failed to rename')));
    if (success) await _runSearch();
  }

  Future<void> _showTagsForItem(MediaItem item) async {
    final app = context.read<AppState>();
    final curSimple = await app.items!.listTagIdsForItem(item.id);
    final curKv = await app.items!.listKeyValueIdsForItem(item.id);
    final picked = await showTagManagerDialog(context, initialSimpleTagIds: curSimple, initialKeyValueIds: curKv);
    if (picked == null) return;
    await app.setTagsForItem(itemId: item.id, simpleTagIds: picked.simpleTagIds, keyValueIds: picked.keyValueIds);
    await _runSearch();
  }

  Future<void> _exportItem(MediaItem item) async {
    final app = context.read<AppState>();
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select directory');
    if (dir == null) return;
    final src = File(LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath));
    if (!await src.exists()) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File not found.'))); return; }
    await src.copy(_uniquePath(p.join(dir, item.originalName)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File exported.')));
  }

  Future<void> _deleteItem(MediaItem item) async {
    final app = context.read<AppState>();
    if (app.settings.confirmDelete) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete item?'),
          content: const Text('This will delete records and files from /Library/files.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (proceed != true) return;
    }
    try {
      final res = await app.deleteOneItem(item);
      if (!mounted) return;
      if (res.failed.isNotEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete file.'))); return; }
      if (_selected?.id == item.id) setState(() => _selected = null);
      await _runSearch();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete error: $e')));
    }
  }

  Future<void> _openInFolder(MediaItem item) async {
    final app = context.read<AppState>();
    final filePath = LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath);
    if (Platform.isWindows) { await Process.run('explorer', ['/select,', filePath]); }
    else if (Platform.isMacOS) { await Process.run('open', ['-R', filePath]); }
    else if (Platform.isLinux) { await Process.run('xdg-open', [p.dirname(filePath)]); }
  }

  Future<void> _showThumbnailPicker(MediaItem item) async {
    // Thumbnail picking requires video frame extraction — not available in search screen
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set thumbnail via Library screen.')));
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
                    const SizedBox(width: 8),
                    if (_results.isNotEmpty) ...[
                      OutlinedButton.icon(
                        onPressed: _results.isEmpty ? null : () {
                          setState(() => _selectMode = !_selectMode);
                          if (!_selectMode) context.read<AppState>().clearItemSelection();
                        },
                        icon: Icon(_selectMode ? Icons.check_box : Icons.check_box_outline_blank),
                        label: Text(_selectMode
                            ? 'Select (${context.watch<AppState>().selectedItemIds.length})'
                            : 'Select'),
                        style: _selectMode
                            ? OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary)
                            : null,
                      ),
                      if (_selectMode) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            final app = context.read<AppState>();
                            final displayIds = _applyFiltersAndSort(_results).map((i) => i.id).toSet();
                            final allSelected = displayIds.every((id) => app.selectedItemIds.contains(id));
                            if (allSelected) {
                              app.clearItemSelection();
                            } else {
                              for (final id in displayIds) app.selectedItemIds.add(id);
                              app.notifyListeners();
                            }
                            setState(() {});
                          },
                          icon: const Icon(Icons.select_all),
                          label: const Text('All'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: context.watch<AppState>().selectedItemIds.isEmpty ? null : _bulkActions,
                          icon: const Icon(Icons.more_horiz),
                          label: const Text('Actions'),
                        ),
                      ],
                    ],
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
                                    onSelect: (item) {
                                      if (_selectMode) {
                                        app.toggleItemSelection(item.id);
                                        if (app.selectedItemIds.isEmpty) setState(() => _selectMode = false);
                                      } else {
                                        setState(() => _selected = item);
                                      }
                                    },
                                    onLongPress: (item) {
                                      app.toggleItemSelection(item.id);
                                      if (!_selectMode) setState(() => _selectMode = true);
                                      if (app.selectedItemIds.isEmpty) setState(() => _selectMode = false);
                                    },
                                    selectedIds: app.selectedItemIds,
                                    selectMode: _selectMode,
                                    onContextMenu: (gridCtx, item, pos) => _handleContextMenu(gridCtx, item, pos),
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
                          onTheatreChanged: (w) => setState(() {
                            _panelWidth = w;
                            _theatreModeActive = w > kPanelNormal;
                          }),
                          initialTheatreMode: _theatreModeActive,
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
  final Set<String> selectedIds;
  final bool selectMode;
  final void Function(MediaItem item) onSelect;
  final void Function(MediaItem item) onLongPress;
  final void Function(BuildContext ctx, MediaItem item, Offset pos) onContextMenu;

  const _ItemsGrid({
    required this.items,
    required this.libraryFilesDir,
    required this.thumbsDir,
    required this.gifAutoplay,
    required this.selectedItemId,
    this.showTypeMarkers = true,
    this.showUntaggedIndicator = true,
    this.untaggedIds = const {},
    this.selectedIds = const {},
    this.selectMode = false,
    required this.onSelect,
    required this.onLongPress,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('No results'));

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
        return MediaGridCard(
          key: ValueKey(it.id),
          item: it,
          libraryFilesDir: libraryFilesDir,
          thumbsDir: thumbsDir,
          gifAutoplay: gifAutoplay,
          isSelected: it.id == selectedItemId,
          isBulkSelected: selectedIds.contains(it.id),
          selectMode: selectMode,
          showTypeMarkers: showTypeMarkers,
          showUntaggedIndicator: showUntaggedIndicator,
          isUntagged: untaggedIds.contains(it.id),
          showFavourite: false,
          onTap: () => onSelect(it),
          onLongPress: () => onLongPress(it),
          onContextMenu: (cardCtx, pos) => onContextMenu(cardCtx, it, pos),
        );
      },
    );
  }
}