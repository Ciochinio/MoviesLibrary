import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/library_folders.dart';
import '../../core/thumbnail_service.dart';
import '../../core/import_controller.dart';
import '../../core/vr_format.dart';

import '../widgets/tag_manager_dialog.dart';
import '../widgets/media_grid_controls.dart';
import '../widgets/media_grid_card.dart';
import '../widgets/shared_player_panel.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

// Sort / Filter enums and helpers are in media_grid_controls.dart
// Using type aliases for local readability
typedef _SortField = SortField;
typedef _TypeFilter = TypeFilter;

class _LibraryScreenState extends State<LibraryScreen> {
  MediaItem? selectedItem;
  double _panelWidth = 300.0;
  List<MediaItem> loaded = [];
  bool loading = false;
  bool _dragging = false;
  final ScrollController _gridScrollController = ScrollController();
  bool _selectMode = false;



  // Sort & filter — session only, reset on subcategory change
  _SortField _sortField = _SortField.dateAdded;
  bool _sortAscending = false;
  final Set<_TypeFilter> _typeFilters = {};
  int _shuffleSeed = 0; // stable random order within a session

  // Untagged indicator — set of item IDs with zero tags
  Set<String> _untaggedIds = {};
  Map<String, VrFormat> _vrFormats = {};

  // Thumbnail version counters — incremented when thumbnail changes to bust Flutter's image cache
  final Map<String, int> _thumbVersions = {};

  @override
  void dispose() {
    _gridScrollController.dispose();
    super.dispose();
  }

  // ── Item selection ─────────────────────────────────────────────────────────
  bool _theatreModeActive = false;

  void _selectItemForPlayback(MediaItem item) {
    setState(() => selectedItem = item);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  // ─── Sort & Filter helpers ────────────────────────────────────────────

  List<MediaItem> _applyFiltersAndSort(List<MediaItem> items) {
    return applyFiltersAndSort(
      items,
      sortField: _sortField,
      sortAscending: _sortAscending,
      typeFilters: _typeFilters,
      shuffleSeed: _shuffleSeed,
    );
  }

  // Track last loaded subcategory so we know when to reset sort/filter
  String? _lastLoadedSubcategoryId;

  Future<void> _reload() async {
    final app = context.read<AppState>();
    if (!app.isReady) return;

    // Reset sort/filter when the subcategory changes
    final currentSubId = app.globalSearchActive ? '__search__' : app.selectedSubcategoryId;
    if (currentSubId != _lastLoadedSubcategoryId) {
      _sortField = _SortField.dateAdded;
      _sortAscending = false;
      _typeFilters.clear();
      _lastLoadedSubcategoryId = currentSubId;
    }

    // Preserve scroll position so tag operations don't jump to top.
    final scrollOffset = _gridScrollController.hasClients ? _gridScrollController.offset : 0.0;
    setState(() => loading = true);
    loaded = await app.loadCurrentItems();
    if (selectedItem != null) {
      selectedItem = loaded.where((e) => e.id == selectedItem!.id).cast<MediaItem?>().firstOrNull;
    }
    // Fetch untagged IDs in one bulk query
    if (app.settings.showUntaggedIndicator && loaded.isNotEmpty) {
      _untaggedIds = await app.items!.listUntaggedItemIds(loaded.map((e) => e.id).toList());
    } else {
      _untaggedIds = {};
    }
    _vrFormats = loaded.isEmpty ? {} : await app.items!.listVrFormats(loaded.map((e) => e.id).toList());
    setState(() => loading = false);
    // Restore scroll position after rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_gridScrollController.hasClients && scrollOffset > 0) {
        _gridScrollController.jumpTo(
          scrollOffset.clamp(0.0, _gridScrollController.position.maxScrollExtent),
        );
      }
    });
  }

  Future<void> _refreshFromDisk() async {
    final app = context.read<AppState>();
    if (!app.isReady) return;
    await _runWithProgress(
      title: 'Refreshing library…',
      task: () async { await app.refreshFromDiskAndMigrate(); },
    );
    await _reload();
  }

  Future<void> _exportFolder() async {
    final app = context.read<AppState>();
    if (!app.isReady || app.selectedCategoryId == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.folder), title: const Text('Export current subcategory'), onTap: () => Navigator.pop(ctx, 'sub')),
          ListTile(leading: const Icon(Icons.folder_copy), title: const Text('Export entire category'), onTap: () => Navigator.pop(ctx, 'cat')),
        ]),
      ),
    );
    if (choice == null) return;
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select directory');
    if (dir == null) return;
    int count = 0;
    await _runWithProgress(
      title: 'Exporting…',
      task: () async {
        if (choice == 'cat') {
          count = await app.exportCategoryToFolder(categoryId: app.selectedCategoryId!, destRoot: dir);
        } else {
          count = await app.exportCurrentSubcategoryToFolder(dir);
        }
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported $count files.')));
  }

  Future<void> _runWithProgress({required String title, required Future<void> Function() task}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Future.microtask(() async {
          try { await task(); } finally { if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop(); }
        });
        return AlertDialog(title: Text(title), content: const SizedBox(height: 70, child: Center(child: CircularProgressIndicator())));
      },
    );
  }

  // ─── Import ────────────────────────────────

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null || res.files.isEmpty) return;
    final files = res.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
    await _importFiles(files);
  }

  Future<void> _onDropDone(DropDoneDetails details) async {
    final files = <File>[];
    for (final xFile in details.files) {
      final path = xFile.path;
      if (await FileSystemEntity.isFile(path)) {
        files.add(File(path));
      } else if (await FileSystemEntity.isDirectory(path)) {
        await for (final entity in Directory(path).list(recursive: true)) {
          if (entity is File) files.add(entity);
        }
      }
    }
    if (files.isNotEmpty) await _importFiles(files);
  }

  Future<void> _importFiles(List<File> files) async {
    if (files.isEmpty) return;
    final ctrl = context.read<ImportController>();

    // Set up duplicate handler
    ctrl.onDuplicateDetected = (file, existingName) async {
      if (!mounted) return false;
      final add = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Duplicate!'),
          content: Text('${p.basename(file.path)} is a duplicate of:\n$existingName'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Skip')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add to Stash anyway')),
          ],
        ),
      );
      return add ?? false;
    };

    // Set up completion handler
    ctrl.onImportComplete = () {
      if (mounted) _reload();
    };

    // Start background import
    ctrl.startImport(files);
  }

  String _uniquePath(String desiredPath) {
    if (!File(desiredPath).existsSync()) return desiredPath;
    final dir = p.dirname(desiredPath);
    final base = p.basenameWithoutExtension(desiredPath);
    final ext = p.extension(desiredPath);
    int i = 1;
    while (true) {
      final candidate = p.join(dir, '$base ($i)$ext');
      if (!File(candidate).existsSync()) return candidate;
      i++;
    }
  }

  // ─── Bulk actions ──────────────────────────

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
    if (choice == null) return;

    if (choice == 'addTag' || choice == 'removeTag') {
      final tagId = await _pickTagDialog();
      if (tagId == null) return;
      if (choice == 'addTag') { await app.bulkAddTagToSelected(tagId); } else { await app.bulkRemoveTagFromSelected(tagId); }
      await _reload();
      return;
    }
    if (choice == 'move') {
      final subId = await _pickSubcategoryDialog();
      if (subId == null) return;
      await app.moveSelectedItems(subId);
      await _reload();
      return;
    }
    if (choice == 'export') {
      final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select directory');
      if (dir == null) return;
      final toExport = loaded.where((i) => app.selectedItemIds.contains(i.id)).toList();
      int okCount = 0;
      for (final item in toExport) {
        final src = File(LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath));
        if (!await src.exists()) continue;
        await src.copy(_uniquePath(p.join(dir, item.originalName)));
        okCount++;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported $okCount files.')));
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
      if (ok == true) {
        final res = await app.deleteSelectedItems(loaded);
        await _reload();
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
        content: SizedBox(width: 420, height: 300, child: ListView(children: [for (final t in app.tagList) ListTile(title: Text(t.name), onTap: () => Navigator.pop(ctx, t.id))])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<String?> _pickSubcategoryDialog() async {
    final app = context.read<AppState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select subcategory'),
        content: SizedBox(
          width: 520, height: 420,
          child: ListView(children: [
            for (final c in app.categoryList) ...[
              Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(c.name, style: Theme.of(context).textTheme.titleMedium)),
              for (final s in app.subcategoriesFor(c.id))
                ListTile(dense: true, title: Text('• ${s.name}'), onTap: () => Navigator.pop(ctx, s.id)),
            ]
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  // ─── Right-click context menu ──────────────

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
    if (success) await _reload();
  }

  Future<void> _showTagsForItem(MediaItem item) async {
    final app = context.read<AppState>();
    final curSimple = await app.items!.listTagIdsForItem(item.id);
    final curKv = await app.items!.listKeyValueIdsForItem(item.id);
    final picked = await showTagManagerDialog(context, initialSimpleTagIds: curSimple, initialKeyValueIds: curKv);
    if (picked == null) return;
    await app.setTagsForItem(itemId: item.id, simpleTagIds: picked.simpleTagIds, keyValueIds: picked.keyValueIds);
    await _reload();
  }

  Future<void> _moveItem(MediaItem item) async {
    final subId = await _pickSubcategoryDialog();
    if (subId == null) return;
    final app = context.read<AppState>();
    final list = await app.items!.listItemsByIds([item.id]);
    await app.items!.moveItemsToSubcategory(list, subId);
    await app.applyAutoTagsToItem(item.id, subId);
    await app.refreshFromDiskAndMigrate();
    await _reload();
  }

  Future<void> _exportItem(MediaItem item) async {
    final app = context.read<AppState>();
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select directory');
    if (dir == null) return;
    final src = File(LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath));
    if (!await src.exists()) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plik nie istnieje.'))); return; }
    await src.copy(_uniquePath(p.join(dir, item.originalName)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File exported.')));
  }

  Future<void> _deleteItem(MediaItem item) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    bool proceed = true;
    bool dontAskAgain = false;
    if (app.settings.confirmDelete) {
      proceed = (await showDialog<bool>(
        context: context,
        builder: (ctx) {
          bool localDontAsk = false;
          return StatefulBuilder(
            builder: (ctx, setStateSB) => AlertDialog(
              title: const Text('Delete item?'),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('This will delete records and files from /Library/files.'),
                const SizedBox(height: 12),
                CheckboxListTile(contentPadding: EdgeInsets.zero, value: localDontAsk, title: const Text("Don't ask again"), onChanged: (v) => setStateSB(() => localDontAsk = v ?? false)),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () { dontAskAgain = localDontAsk; Navigator.pop(ctx, true); }, child: const Text('Delete')),
              ],
            ),
          );
        },
      )) ?? false;
      if (dontAskAgain) await app.setConfirmDelete(false);
    }
    if (!proceed) return;
    try {
      final res = await app.deleteOneItem(item);
      if (res.failed.isNotEmpty) { messenger.showSnackBar(const SnackBar(content: Text('Failed to delete file.'))); return; }
      if (selectedItem?.id == item.id) selectedItem = null;
      await _reload();
      messenger.showSnackBar(const SnackBar(content: Text('Item deleted.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete error: $e')));
    }
  }

  Future<void> _openInFolder(MediaItem item) async {
    final app = context.read<AppState>();
    final filePath = LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath);
    if (Platform.isWindows) { await Process.run('explorer', ['/select,', filePath]); }
    else if (Platform.isMacOS) { await Process.run('open', ['-R', filePath]); }
    else if (Platform.isLinux) { await Process.run('xdg-open', [p.dirname(filePath)]); }
  }

  // ─── Thumbnail picker (3x3 Netflix grid) ───

  Future<void> _showThumbnailPicker(MediaItem item) async {
    final app = context.read<AppState>();
    final thumbService = ThumbnailService(app.paths!.thumbsDir);
    final filePath = LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath);

    // Check ffmpeg availability
    final hasFfmpeg = await ThumbnailService.isFfmpegAvailable();
    if (!hasFfmpeg) {
      if (!mounted) return;
      final shouldDownload = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ffmpeg required'),
          content: Text(
            'Thumbnails require ffmpeg, which was not found.\n\n'
            '${ThumbnailService.isAutoDownloadSupported
                ? 'Would you like to download it automatically? (~90MB, one-time download)\n\nIt will be stored next to the app for portable use.'
                : 'Please install ffmpeg manually:\n  Linux: sudo apt install ffmpeg\n  Or download from ffmpeg.org'}'
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            if (ThumbnailService.isAutoDownloadSupported)
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Download ffmpeg')),
          ],
        ),
      );

      if (shouldDownload != true || !mounted) return;

      bool downloadSuccess = false;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          String statusText = 'Starting download...';
          return StatefulBuilder(
            builder: (ctx, setStateSB) {
              if (statusText == 'Starting download...') {
                Future.microtask(() async {
                  downloadSuccess = await ThumbnailService.downloadFfmpeg(
                    onProgress: (status) { if (ctx.mounted) setStateSB(() => statusText = status); },
                  );
                  await Future.delayed(const Duration(milliseconds: 800));
                  if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                });
              }
              return AlertDialog(
                title: const Text('Downloading ffmpeg'),
                content: SizedBox(height: 100, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (!statusText.startsWith('Done')) const CircularProgressIndicator(),
                  if (statusText.startsWith('Done')) const Icon(Icons.check_circle, color: Colors.green, size: 40),
                  const SizedBox(height: 12),
                  Text(statusText, textAlign: TextAlign.center),
                ])),
              );
            },
          );
        },
      );

      if (!downloadSuccess || !mounted) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ffmpeg download failed.')));
        return;
      }
      if (!await ThumbnailService.isFfmpegAvailable()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ffmpeg could not be executed. Check antivirus settings.')));
        return;
      }
    }

    // ─── Extract frames and show picker (works for both video AND GIF) ───
    if (!mounted) return;

    final sessionId = DateTime.now().millisecondsSinceEpoch;
    final tempDir = Directory(p.join(Directory.systemTemp.path, 'libthumb_${item.id}_$sessionId'));
    await tempDir.create(recursive: true);

    List<({String path, String? cropFilter})>? frames;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Future.microtask(() async {
          frames = await thumbService.extract9Frames(videoPath: filePath, tempDir: tempDir.path);
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        });
        return const AlertDialog(
          title: Text('Extracting frames...'),
          content: SizedBox(height: 70, child: Center(child: CircularProgressIndicator())),
        );
      },
    );

    if (frames == null || frames!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not extract frames.')));
      _cleanupTempDir(tempDir);
      return;
    }

    if (!mounted) return;

    // Detect orientation from the first extracted frame to size cells appropriately
    double cellAspectRatio = 16 / 9; // default: landscape
    double dialogWidth = 660;
    try {
      final firstBytes = await File(frames!.first.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(firstBytes);
      final frameInfo = await codec.getNextFrame();
      final fw = frameInfo.image.width;
      final fh = frameInfo.image.height;
      codec.dispose();
      if (fh > fw) {
        // Vertical content — portrait cells, narrower dialog
        cellAspectRatio = fw / fh;
        dialogWidth = 400;
      }
    } catch (_) {}

    if (!mounted) return;

    // Show 3x3 grid picker — no fixed height, dialog sizes to content (no scroll)
    final chosenIndex = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose thumbnail'),
        content: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Click a frame to set it as thumbnail'),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8,
                  childAspectRatio: cellAspectRatio,
                ),
                itemCount: frames!.length,
                itemBuilder: (_, i) => InkWell(
                  onTap: () => Navigator.pop(ctx, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(frames![i].path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, -2), child: const Text('Pick from file...')),
          TextButton(onPressed: () => Navigator.pop(ctx, -1), child: const Text('Refresh frames')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );

    if (chosenIndex == -1) { _cleanupTempDir(tempDir); await _showThumbnailPicker(item); return; }
    if (chosenIndex == -2) { _cleanupTempDir(tempDir); await _pickThumbnailFromFile(item, thumbService); return; }

    if (chosenIndex != null && chosenIndex >= 0) {
      final chosen = frames![chosenIndex];
      final ok = await thumbService.setThumbnail(itemId: item.id, sourceFramePath: chosen.path);
      if (!mounted) return;
      if (ok) {
        // Bust Flutter's image cache for this specific thumbnail by evicting
        // AND incrementing the version counter (forces a new cache key in the grid)
        final thumbPath = p.join(app.paths!.thumbsDir.path, '${item.id}.jpg');
        await FileImage(File(thumbPath)).evict();
        imageCache.clear();
        imageCache.clearLiveImages();
        setState(() => _thumbVersions[item.id] = (_thumbVersions[item.id] ?? 0) + 1);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Thumbnail set' : 'Failed to set thumbnail')));
    }

    _cleanupTempDir(tempDir);
  }

  /// Pick an image file and set it as thumbnail.
  Future<void> _pickThumbnailFromFile(MediaItem item, ThumbnailService thumbService) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
      dialogTitle: 'Pick thumbnail image',
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    final ok = await thumbService.setThumbnail(itemId: item.id, sourceFramePath: result.files.first.path!);
    if (!mounted) return;
    if (ok) {
      // Bust Flutter's image cache for this specific thumbnail
      final appState = context.read<AppState>();
      final thumbPath = p.join(appState.paths!.thumbsDir.path, '${item.id}.jpg');
      await FileImage(File(thumbPath)).evict();
      imageCache.clear();
      imageCache.clearLiveImages();
      setState(() => _thumbVersions[item.id] = (_thumbVersions[item.id] ?? 0) + 1);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Thumbnail set' : 'Failed to set thumbnail')));
  }

  void _cleanupTempDir(Directory dir) {
    try { if (dir.existsSync()) dir.deleteSync(recursive: true); } catch (_) {}
  }

  void _handleContextMenu(BuildContext gridContext, MediaItem item, Offset globalPosition) {
    final isVideo = item.type == ItemType.video;
    final filePath = LibraryFolders.absPath(context.read<AppState>().paths!.filesDir, item.storedRelPath);
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
        if (isVideo)
          const PopupMenuItem(value: 'vr', child: Row(children: [Icon(Icons.vrpano, size: 20), SizedBox(width: 12), Text('VR format...')])),
        const PopupMenuItem(value: 'move', child: Row(children: [Icon(Icons.drive_file_move, size: 20), SizedBox(width: 12), Text('Move to...')])),
        const PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.download, size: 20), SizedBox(width: 12), Text('Export...')])),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'open_folder', child: Row(children: [Icon(Icons.folder_open, size: 20), SizedBox(width: 12), Text('Show in folder')])),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 20, color: Colors.red), SizedBox(width: 12), Text('Delete', style: TextStyle(color: Colors.red))])),
      ],
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case 'rename':    await _showRenameDialog(item); break;
        case 'tags':      await _showTagsForItem(item); break;
        case 'thumbnail': await _showThumbnailPicker(item); break;
        case 'vr':        await _showVrFormatDialog(item); break;
        case 'move':      await _moveItem(item); break;
        case 'export':    await _exportItem(item); break;
        case 'open_folder': await _openInFolder(item); break;
        case 'delete':    await _deleteItem(item); break;
      }
    });
  }

  Future<void> _showVrFormatDialog(MediaItem item) async {
    final app = context.read<AppState>();
    final current = _vrFormats[item.id];
    // Wrapped so "Not VR" (null) is distinguishable from dismissing the dialog
    final picked = await showDialog<({VrFormat? format})>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('VR format'),
        children: [
          for (final f in [null, ...VrFormat.values])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, (format: f)),
              child: Row(children: [
                Icon(f == current ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                const SizedBox(width: 12),
                Text(f?.label ?? 'Not VR'),
              ]),
            ),
        ],
      ),
    );
    if (picked == null || picked.format == current) return;
    await setVrFormat(app, item.id, picked.format);
    await _reload();
  }

  // ─── Edit subcategory description ──────────

  Future<void> _editSubcategoryDescription() async {
    final app = context.read<AppState>();
    if (app.selectedSubcategoryId == null) return;

    // Find current subcategory
    Subcategory? currentSub;
    for (final c in app.categoryList) {
      for (final s in app.subcategoriesFor(c.id)) {
        if (s.id == app.selectedSubcategoryId) { currentSub = s; break; }
      }
      if (currentSub != null) break;
    }
    if (currentSub == null) return;

    final ctrl = TextEditingController(text: currentSub.description);
    final newDesc = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit description'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()), maxLines: 3, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (newDesc == null) return;
    await app.categories!.updateSubcategoryDescription(currentSub.id, newDesc);
    await app.refreshAll();
  }

  // ─── Helper: get current category & subcategory names ───

  ({String categoryName, String subcategoryName, String subcategoryDescription}) _getCurrentNames(AppState app) {
    String catName = '';
    String subName = '';
    String subDesc = '';
    for (final c in app.categoryList) {
      if (c.id == app.selectedCategoryId) catName = c.name;
      for (final s in app.subcategoriesFor(c.id)) {
        if (s.id == app.selectedSubcategoryId) { subName = s.name; subDesc = s.description; }
      }
    }
    return (categoryName: catName, subcategoryName: subName, subcategoryDescription: subDesc);
  }

  // ─── Build ─────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Row(
      children: [
        // ─── Sidebar ─────────────────
        SizedBox(
          width: 240,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(child: Text('Categories', style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(tooltip: 'Refresh', onPressed: () async => _refreshFromDisk(), icon: const Icon(Icons.refresh)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _buildSidebar(app)),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // ─── Main content area ───────
        Expanded(
          child: Column(
            children: [
              // ─── Discord-style header ───
              _buildHeader(app),
              const Divider(height: 1),
              // ─── Grid with drag & drop ──
              Expanded(
                child: DropTarget(
                  onDragEntered: (_) => setState(() => _dragging = true),
                  onDragExited: (_) => setState(() => _dragging = false),
                  onDragDone: (details) { setState(() => _dragging = false); _onDropDone(details); },
                  child: Stack(
                    children: [
                      loading
                          ? const Center(child: CircularProgressIndicator())
                          : _ItemsGrid(
                              items: _applyFiltersAndSort(loaded),
                              libraryFilesDir: app.paths!.filesDir,
                              thumbsDir: app.paths!.thumbsDir,
                              selectedItemId: selectedItem?.id,
                              selectedIds: app.selectedItemIds,
                              gifAutoplay: app.settings.gifAutoplay,
                              scrollController: _gridScrollController,
                              selectMode: _selectMode,
                              showTypeMarkers: app.settings.showTypeMarkers,
                              showUntaggedIndicator: app.settings.showUntaggedIndicator,
                              untaggedIds: _untaggedIds,
                              vrFormats: _vrFormats,
                              thumbVersions: _thumbVersions,
                              onSelect: (item) {
                                if (_selectMode) {
                                  app.toggleItemSelection(item.id);
                                  // Auto-exit select mode when last item deselected
                                  if (app.selectedItemIds.isEmpty) setState(() => _selectMode = false);
                                } else {
                                  _selectItemForPlayback(item);
                                }
                              },
                              onToggleBulk: (id) {
                                app.toggleItemSelection(id);
                                if (!_selectMode) setState(() => _selectMode = true);
                                if (app.selectedItemIds.isEmpty) setState(() => _selectMode = false);
                              },
                              onToggleFavourite: (id, value) async {
                                // Optimistic local update — no full reload, no flash
                                final idx = loaded.indexWhere((e) => e.id == id);
                                if (idx != -1) {
                                  setState(() => loaded[idx] = loaded[idx].copyWith(isFavourite: value));
                                }
                                await app.toggleFavourite(id, value);
                              },
                              onLongPress: (item) async {
                                final newVal = !item.isFavourite;
                                final idx = loaded.indexWhere((e) => e.id == item.id);
                                if (idx != -1) {
                                  setState(() => loaded[idx] = loaded[idx].copyWith(isFavourite: newVal));
                                }
                                await app.toggleFavourite(item.id, newVal);
                              },
                              onContextMenu: (gridCtx, item, pos) => _handleContextMenu(gridCtx, item, pos),
                            ),
                      if (_dragging)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.all(8),
                            child: Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.file_upload, size: 48, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(height: 8),
                                Text('Drop files to import', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                              ]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // ─── Bottom toolbar ─────────
              const Divider(height: 1),
              _BottomBar(
                onImport: _import,
                onBulk: app.selectedItemIds.isEmpty ? null : _bulkActions,
                onExportFolder: app.selectedSubcategoryId == null ? null : _exportFolder,
                selectMode: _selectMode,
                onToggleSelectMode: () {
                  setState(() {
                    _selectMode = !_selectMode;
                    if (!_selectMode) app.clearItemSelection();
                  });
                },
                sortField: _sortField,
                sortAscending: _sortAscending,
                typeFilters: _typeFilters,
                onSortChanged: (field, ascending) {
                  setState(() {
                    _sortField = field;
                    _sortAscending = ascending;
                    // New seed every time random is (re)selected → new shuffle
                    if (field == _SortField.random) {
                      _shuffleSeed = DateTime.now().millisecondsSinceEpoch;
                    }
                  });
                },
                onTypeFilterChanged: (filters) {
                  setState(() {
                    _typeFilters.clear();
                    _typeFilters.addAll(filters);
                  });
                },
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // ─── Player + Details panel ───────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: (() {
            final maxW = (MediaQuery.of(context).size.width - 240 - 350).clamp(200.0, double.infinity);
            return _panelWidth.clamp(0.0, maxW);
          })(),
          child: selectedItem == null
              ? const Center(child: Text('Select an item'))
              : SharedPlayerPanel(
                  key: ValueKey(selectedItem!.id),
                  initialTheatreMode: _theatreModeActive,
                  item: selectedItem!,
                  libraryFilesDir: app.paths!.filesDir,
                  thumbsDir: app.paths!.thumbsDir,
                  allItems: _applyFiltersAndSort(loaded),
                  onTheatreChanged: (w) => setState(() {
                      _panelWidth = w;
                      _theatreModeActive = w > kPanelNormal;
                    }),
                  onOpen: () async {
                    final filePath = LibraryFolders.absPath(app.paths!.filesDir, selectedItem!.storedRelPath);
                    await OpenFilex.open(filePath);
                  },
                  loadTags: () => app.items!.listTagsForItem(selectedItem!.id),
                  loadKeyValues: () => app.items!.listKeyValuesForItem(selectedItem!.id),
                ),
        ),
      ],
    );
  }

  // ─── Discord-style header ──────────────────

  Widget _buildHeader(AppState app) {
    if (app.selectedSubcategoryId == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text('Select a subcategory', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).hintColor)),
      );
    }

    final names = _getCurrentNames(app);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.tag, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${names.categoryName}  >  ${names.subcategoryName}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const Spacer(),
          if (names.subcategoryDescription.isNotEmpty)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  names.subcategoryDescription,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Edit description',
            icon: const Icon(Icons.edit, size: 18),
            onPressed: _editSubcategoryDescription,
          ),
        ],
      ),
    );
  }

  // ─── Sidebar with drag-and-drop reorder ────

  Widget _buildSidebar(AppState app) {
    return ReorderableListView(
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) async {
        if (newIndex > oldIndex) newIndex--;
        final ids = app.categoryList.map((c) => c.id).toList();
        if (oldIndex >= ids.length || newIndex >= ids.length) return;
        final movedId = ids.removeAt(oldIndex);
        ids.insert(newIndex, movedId);
        await app.reorderCategories(ids);
      },
      children: [
        for (int ci = 0; ci < app.categoryList.length; ci++)
          _buildCategoryTile(app, app.categoryList[ci], ci),
      ],
    );
  }

  Widget _buildCategoryTile(AppState app, Category c, int categoryIndex) {
    final subs = app.subcategoriesFor(c.id);
    return Theme(
      key: ValueKey('cat_${c.id}'),
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: ReorderableDragStartListener(index: categoryIndex, child: const Icon(Icons.drag_handle, size: 20)),
        title: Text(c.name),
        initiallyExpanded: app.selectedCategoryId == c.id,
        children: [
          ...List.generate(subs.length, (si) {
            final s = subs[si];
            return ListTile(
              key: ValueKey('sub_${s.id}'),
              contentPadding: const EdgeInsets.only(left: 56, right: 8),
              title: Row(children: [
                Expanded(child: Text(s.name)),
                FutureBuilder<int>(
                  future: app.items!.countUntaggedItems(s.id),
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    if (count == 0) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
                      child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    );
                  },
                ),
              ]),
              selected: app.selectedSubcategoryId == s.id,
              onTap: () async { await app.selectSubcategory(c.id, s.id); selectedItem = null; await _reload(); },
            );
          }),
          if (subs.length > 1)
            Padding(
              padding: const EdgeInsets.only(left: 56, right: 8, bottom: 4),
              child: Wrap(spacing: 4, children: [
                for (int si = 0; si < subs.length; si++)
                  if (app.selectedSubcategoryId == subs[si].id) ...[
                    IconButton(icon: const Icon(Icons.arrow_upward, size: 16), tooltip: 'Move subcategory up', onPressed: si == 0 ? null : () async {
                      final ids = subs.map((s) => s.id).toList(); final moved = ids.removeAt(si); ids.insert(si - 1, moved); await app.reorderSubcategories(c.id, ids);
                    }),
                    IconButton(icon: const Icon(Icons.arrow_downward, size: 16), tooltip: 'Move subcategory down', onPressed: si == subs.length - 1 ? null : () async {
                      final ids = subs.map((s) => s.id).toList(); final moved = ids.removeAt(si); ids.insert(si + 1, moved); await app.reorderSubcategories(c.id, ids);
                    }),
                  ],
              ]),
            ),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 56),
            leading: const Icon(Icons.add),
            title: const Text('Add subcategory'),
            onTap: () async {
              final name = await _promptText('Subcategory name');
              if (name == null || name.trim().isEmpty) return;
              await app.createSubcategory(c.id, name.trim());
              await _reload();
            },
          ),
        ],
      ),
    );
  }

  Future<String?> _promptText(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder()), onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK'))],
      ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ──────────────────────────────────────────────
// Bottom toolbar (was _TopBar, now at bottom)
// ──────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback? onBulk;
  final VoidCallback? onExportFolder;
  final bool selectMode;
  final VoidCallback onToggleSelectMode;
  final _SortField sortField;
  final bool sortAscending;
  final Set<_TypeFilter> typeFilters;
  final void Function(_SortField field, bool ascending) onSortChanged;
  final void Function(Set<_TypeFilter> filters) onTypeFilterChanged;

  const _BottomBar({
    required this.onImport,
    required this.onBulk,
    required this.onExportFolder,
    required this.selectMode,
    required this.onToggleSelectMode,
    required this.sortField,
    required this.sortAscending,
    required this.typeFilters,
    required this.onSortChanged,
    required this.onTypeFilterChanged,
  });
@override
Widget build(BuildContext context) {
  final app = context.watch<AppState>();
  final filterLabel = typeFilters.isEmpty
      ? 'All'
      : typeFilters.map((f) => f.label).join(', ');
  final sortLabel = sortField == _SortField.random
      ? 'Random'
      : '${sortField.label} ${sortAscending ? '↑' : '↓'}';

return LayoutBuilder(
  builder: (context, constraints) {
    final narrow = constraints.maxWidth < 580;

    if (!narrow) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.file_upload), label: const Text('Import')),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onToggleSelectMode,
                icon: Icon(selectMode ? Icons.check_box : Icons.check_box_outline_blank),
                label: Text(selectMode ? 'Select (${app.selectedItemIds.length})' : 'Select'),
                style: selectMode ? OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary) : null,
              ),
              if (selectMode && app.selectedItemIds.isNotEmpty) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: onBulk, icon: const Icon(Icons.more_horiz), label: const Text('Actions')),
              ],
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: app.globalSearchActive ? null : onExportFolder, icon: const Icon(Icons.folder_open), label: const Text('Export folder')),
            ]),
            const SizedBox(width: 16),
            Row(mainAxisSize: MainAxisSize.min, children: [
              SortButton(label: sortLabel, sortField: sortField, sortAscending: sortAscending, onChanged: onSortChanged),
              const SizedBox(width: 8),
              TypeFilterButton(label: filterLabel, selected: typeFilters, onChanged: onTypeFilterChanged),
            ]),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.file_upload), label: const Text('Import')),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onToggleSelectMode,
                  icon: Icon(selectMode ? Icons.check_box : Icons.check_box_outline_blank),
                  label: Text(selectMode ? 'Select (${app.selectedItemIds.length})' : 'Select'),
                  style: selectMode ? OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary) : null,
                ),
                if (selectMode && app.selectedItemIds.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(onPressed: onBulk, icon: const Icon(Icons.more_horiz), label: const Text('Actions')),
                ],
              ]),
              const SizedBox(height: 4),
              OutlinedButton.icon(onPressed: app.globalSearchActive ? null : onExportFolder, icon: const Icon(Icons.folder_open), label: const Text('Export folder')),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              SortButton(label: sortLabel, sortField: sortField, sortAscending: sortAscending, onChanged: onSortChanged),
              const SizedBox(height: 4),
              TypeFilterButton(label: filterLabel, selected: typeFilters, onChanged: onTypeFilterChanged),
            ],
          ),
        ],
      ),
    );
  },
);
}
}


// Items Grid
// ──────────────────────────────────────────────
class _ItemsGrid extends StatelessWidget {
  final List<MediaItem> items;
  final Directory libraryFilesDir;
  final Directory thumbsDir;
  final String? selectedItemId;
  final Set<String> selectedIds;
  final bool gifAutoplay;
  final ScrollController? scrollController;
  final bool selectMode;
  final bool showTypeMarkers;
  final bool showUntaggedIndicator;
  final Set<String> untaggedIds;
  final Map<String, VrFormat> vrFormats;
  final Map<String, int> thumbVersions;
  final void Function(MediaItem item) onSelect;
  final void Function(String id) onToggleBulk;
  final void Function(String id, bool value) onToggleFavourite;
  final void Function(MediaItem item) onLongPress;
  final void Function(BuildContext ctx, MediaItem item, Offset globalPosition) onContextMenu;

  const _ItemsGrid({
    required this.items,
    required this.libraryFilesDir,
    required this.thumbsDir,
    required this.selectedItemId,
    required this.selectedIds,
    required this.gifAutoplay,
    this.scrollController,
    this.selectMode = false,
    this.showTypeMarkers = true,
    this.showUntaggedIndicator = true,
    this.untaggedIds = const {},
    this.vrFormats = const {},
    this.thumbVersions = const {},
    required this.onSelect,
    required this.onToggleBulk,
    required this.onToggleFavourite,
    required this.onLongPress,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('No items — import files or drag them here'));

    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisExtent: 175,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final it = items[i];
        final filePath = LibraryFolders.absPath(libraryFilesDir, it.storedRelPath);
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
          showFavourite: true,
          isFavourite: it.isFavourite,
          thumbVersion: thumbVersions[it.id] ?? 0,
          vrFormat: vrFormats[it.id],
          onTap: () => onSelect(it),
          onLongPress: () => onLongPress(it),
          onContextMenu: (cardCtx, pos) => onContextMenu(cardCtx, it, pos),
        );
      },
    );
  }
}