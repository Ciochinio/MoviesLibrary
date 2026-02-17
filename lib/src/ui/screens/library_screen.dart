import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/library_folders.dart';

import '../widgets/tag_manager_dialog.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  MediaItem? selectedItem;
  List<MediaItem> loaded = [];
  bool loading = false;
  bool _dragging = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  Future<void> _reload() async {
    final app = context.read<AppState>();
    if (!app.isReady) return;
    setState(() => loading = true);
    loaded = await app.loadCurrentItems();
    if (selectedItem != null) {
      selectedItem = loaded.where((e) => e.id == selectedItem!.id).cast<MediaItem?>().firstOrNull;
    }
    setState(() => loading = false);
  }

  Future<void> _refreshFromDisk() async {
    final app = context.read<AppState>();
    if (!app.isReady) return;

    await _runWithProgress(
      title: 'Odświeżanie biblioteki…',
      task: () async {
        await app.refreshFromDiskAndMigrate();
      },
    );

    await _reload();
  }

  Future<void> _exportFolder() async {
    final app = context.read<AppState>();
    if (!app.isReady || app.selectedCategoryId == null) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Eksportuj aktualną subkategorię'),
              onTap: () => Navigator.pop(ctx, 'sub'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_copy),
              title: const Text('Eksportuj całą kategorię'),
              onTap: () => Navigator.pop(ctx, 'cat'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Wybierz folder docelowy');
    if (dir == null) return;

    int count = 0;
    await _runWithProgress(
      title: 'Eksportowanie…',
      task: () async {
        if (choice == 'cat') {
          count = await app.exportCategoryToFolder(categoryId: app.selectedCategoryId!, destRoot: dir);
        } else {
          count = await app.exportCurrentSubcategoryToFolder(dir);
        }
      },
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Wyeksportowano $count plików.')));
  }

  Future<void> _runWithProgress({
    required String title,
    required Future<void> Function() task,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Future.microtask(() async {
          try {
            await task();
          } finally {
            if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          }
        });

        return AlertDialog(
          title: Text(title),
          content: const SizedBox(
            height: 70,
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      },
    );
  }

  // ─── Import (file picker) ──────────────────

  Future<void> _import() async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null || res.files.isEmpty) return;

    final files = res.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
    await _importFiles(files);
  }

  // ─── Import (drag & drop) ─────────────────

  Future<void> _onDropDone(DropDoneDetails details) async {
    final files = <File>[];
    for (final xFile in details.files) {
      final path = xFile.path;
      if (await FileSystemEntity.isFile(path)) {
        files.add(File(path));
      } else if (await FileSystemEntity.isDirectory(path)) {
        // Recursively collect files from dropped folders
        await for (final entity in Directory(path).list(recursive: true)) {
          if (entity is File) files.add(entity);
        }
      }
    }
    if (files.isNotEmpty) await _importFiles(files);
  }

  Future<void> _importFiles(List<File> files) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);

    int imported = 0;
    int skipped = 0;

    for (final file in files) {
      try {
        final target = app.selectedSubcategoryId ?? app.stashSubcategoryId!;

        final pre = await app.importSingleWithDuplicateDecision(
          source: file,
          targetSubcategoryId: target,
          addDuplicateAsSeparateFile: false,
        );

        if (pre.existingDuplicate != null && pre.inserted == null) {
          if (!mounted) return;
          final add = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Duplikat wykryty'),
              content: Text(
                'Ten plik wygląda na duplikat istniejącego elementu:\n'
                '${pre.existingDuplicate!.originalName}\n\n'
                'Co chcesz zrobić?',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nie dodawaj')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dodaj jako osobny do Stash')),
              ],
            ),
          );

          if (add == true) {
            await app.importSingleWithDuplicateDecision(
              source: file,
              targetSubcategoryId: target,
              addDuplicateAsSeparateFile: true,
              precomputedSha256: pre.sha256,
              preexistingDuplicate: pre.existingDuplicate,
            );
            imported++;
          } else {
            skipped++;
          }
        } else {
          imported++;
        }
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Błąd importu: $e')));
      }
    }

    if (imported > 0 || skipped > 0) {
      messenger.showSnackBar(SnackBar(
        content: Text('Zaimportowano $imported plików${skipped > 0 ? ', pominięto $skipped duplikatów' : ''}'),
      ));
    }

    await _reload();
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

  Future<void> _bulkActions() async {
    final app = context.read<AppState>();
    if (app.selectedItemIds.isEmpty) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sell),
              title: const Text('Masowo dodaj tag'),
              onTap: () => Navigator.pop(ctx, 'addTag'),
            ),
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: const Text('Masowo usuń tag'),
              onTap: () => Navigator.pop(ctx, 'removeTag'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move),
              title: const Text('Przenieś do subkategorii'),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Eksportuj na dysk'),
              onTap: () => Navigator.pop(ctx, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Usuń (fizycznie)'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    if (choice == 'addTag' || choice == 'removeTag') {
      final tagId = await _pickTagDialog();
      if (tagId == null) return;
      if (choice == 'addTag') {
        await app.bulkAddTagToSelected(tagId);
      } else {
        await app.bulkRemoveTagFromSelected(tagId);
      }
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
      final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Wybierz folder docelowy');
      if (dir == null) return;

      final toExport = loaded.where((i) => app.selectedItemIds.contains(i.id)).toList();
      int okCount = 0;

      for (final item in toExport) {
        final src = File(LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath));
        if (!await src.exists()) continue;

        final destPath = _uniquePath(p.join(dir, item.originalName));
        await src.copy(destPath);
        okCount++;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Wyeksportowano $okCount plików.')));
      return;
    }

    if (choice == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Usunąć zaznaczone?'),
          content: const Text('To usunie rekordy i fizyczne pliki z /Library/files.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
          ],
        ),
      );
      if (ok == true) {
        final res = await app.deleteSelectedItems(loaded);
        await _reload();
        if (res.failed.isNotEmpty) {
          final names = res.failed.map((e) => e.originalName).take(3).join(', ');
          final more = res.failed.length > 3 ? ' (+${res.failed.length - 3})' : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Nie udało się usunąć ${res.failed.length} plików: $names$more')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Usunięto ${res.deleted.length} elementów.')),
          );
        }
      }
    }
  }

  Future<String?> _pickTagDialog() async {
    final app = context.read<AppState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wybierz tag'),
        content: SizedBox(
          width: 420,
          height: 300,
          child: ListView(
            children: [
              for (final t in app.tagList)
                ListTile(
                  title: Text(t.name),
                  onTap: () => Navigator.pop(ctx, t.id),
                )
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zamknij')),
        ],
      ),
    );
  }

  Future<String?> _pickSubcategoryDialog() async {
    final app = context.read<AppState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wybierz subkategorię'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: ListView(
            children: [
              for (final c in app.categoryList) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(c.name, style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final s in app.subcategoriesFor(c.id))
                  ListTile(
                    dense: true,
                    title: Text('• ${s.name}'),
                    onTap: () => Navigator.pop(ctx, s.id),
                  )
              ]
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zamknij')),
        ],
      ),
    );
  }

  // ─── Right-click context menu actions ──────────────────

  Future<void> _showRenameDialog(MediaItem item) async {
    final ctrl = TextEditingController(text: item.originalName);
    final dotIndex = item.originalName.lastIndexOf('.');
    if (dotIndex > 0) {
      ctrl.selection = TextSelection(baseOffset: 0, extentOffset: dotIndex);
    }

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Zmień nazwę'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Nowa nazwa pliku',
            border: OutlineInputBorder(),
            helperText: 'Tagi i metadane zostaną zachowane',
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(dialogCtx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(dialogCtx, ctrl.text), child: const Text('Zmień nazwę')),
        ],
      ),
    );

    if (newName == null || newName.trim().isEmpty || newName.trim() == item.originalName) return;

    final app = context.read<AppState>();
    final success = await app.items!.renameItem(item, newName.trim());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? 'Zmieniono nazwę' : 'Nie udało się zmienić nazwy')),
    );
    if (success) await _reload();
  }

  Future<void> _showTagsForItem(MediaItem item) async {
    final app = context.read<AppState>();
    final curSimple = await app.items!.listTagIdsForItem(item.id);
    final curKv = await app.items!.listKeyValueIdsForItem(item.id);
    final picked = await showTagManagerDialog(
      context,
      initialSimpleTagIds: curSimple,
      initialKeyValueIds: curKv,
    );
    if (picked == null) return;
    await app.setTagsForItem(
      itemId: item.id,
      simpleTagIds: picked.simpleTagIds,
      keyValueIds: picked.keyValueIds,
    );
    await _reload();
  }

  Future<void> _moveItem(MediaItem item) async {
    final subId = await _pickSubcategoryDialog();
    if (subId == null) return;
    final app = context.read<AppState>();
    final list = await app.items!.listItemsByIds([item.id]);
    await app.items!.moveItemsToSubcategory(list, subId);
    // Apply auto-tags for the destination subcategory
    await app.applyAutoTagsToItem(item.id, subId);
    await app.refreshFromDiskAndMigrate();
    await _reload();
  }

  Future<void> _exportItem(MediaItem item) async {
    final app = context.read<AppState>();
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Wybierz folder docelowy');
    if (dir == null) return;
    final src = File(LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath));
    if (!await src.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plik nie istnieje.')));
      return;
    }
    final dest = _uniquePath(p.join(dir, item.originalName));
    await src.copy(dest);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wyeksportowano plik.')));
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
                  title: const Text('Usunąć element?'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('To usunie element oraz fizyczny plik z /Library/files.'),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: localDontAsk,
                        title: const Text('Nie pytaj więcej'),
                        onChanged: (v) => setStateSB(() => localDontAsk = v ?? false),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
                    FilledButton(
                      onPressed: () {
                        dontAskAgain = localDontAsk;
                        Navigator.pop(ctx, true);
                      },
                      child: const Text('Usuń'),
                    ),
                  ],
                ),
              );
            },
          )) ??
          false;

      if (dontAskAgain) {
        await app.setConfirmDelete(false);
      }
    }

    if (!proceed) return;

    final existed = File(LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath)).existsSync();

    try {
      final res = await app.deleteOneItem(item);
      if (res.failed.isNotEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Nie udało się usunąć pliku (może być używany przez inny program).')));
        return;
      }
      if (selectedItem?.id == item.id) selectedItem = null;
      await _reload();
      if (!existed) {
        messenger.showSnackBar(const SnackBar(content: Text('Plik nie istnieje — usunięto wpis z biblioteki.')));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Usunięto element.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Błąd usuwania: $e')));
    }
  }

  Future<void> _openInFolder(MediaItem item) async {
    final app = context.read<AppState>();
    final filePath = LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath);
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [p.dirname(filePath)]);
    }
  }

  void _handleContextMenu(BuildContext gridContext, MediaItem item, Offset globalPosition) {
    showMenu<String>(
      context: gridContext,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit, size: 20), SizedBox(width: 12), Text('Zmień nazwę...')])),
        PopupMenuItem(value: 'tags', child: Row(children: [Icon(Icons.sell, size: 20), SizedBox(width: 12), Text('Tagi...')])),
        PopupMenuItem(value: 'move', child: Row(children: [Icon(Icons.drive_file_move, size: 20), SizedBox(width: 12), Text('Przenieś do...')])),
        PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.download, size: 20), SizedBox(width: 12), Text('Eksportuj...')])),
        PopupMenuDivider(),
        PopupMenuItem(value: 'open_folder', child: Row(children: [Icon(Icons.folder_open, size: 20), SizedBox(width: 12), Text('Otwórz w folderze')])),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 20, color: Colors.red), SizedBox(width: 12), Text('Usuń', style: TextStyle(color: Colors.red))])),
      ],
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case 'rename':   await _showRenameDialog(item); break;
        case 'tags':     await _showTagsForItem(item); break;
        case 'move':     await _moveItem(item); break;
        case 'export':   await _exportItem(item); break;
        case 'open_folder': await _openInFolder(item); break;
        case 'delete':   await _deleteItem(item); break;
      }
    });
  }

  // ─── Build ─────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Row(
      children: [
        // ─── Sidebar ─────────────────
        SizedBox(
          width: 280,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(child: Text('Kategorie', style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(
                      tooltip: 'Odśwież',
                      onPressed: () async => _refreshFromDisk(),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _buildSidebar(app)),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // ─── Main grid area with drag & drop ─────
        Expanded(
          child: Column(
            children: [
              _TopBar(
                onImport: _import,
                onBulk: app.selectedItemIds.isEmpty ? null : _bulkActions,
                onExportFolder: app.selectedSubcategoryId == null ? null : _exportFolder,
              ),
              Expanded(
                child: DropTarget(
                  onDragEntered: (_) => setState(() => _dragging = true),
                  onDragExited: (_) => setState(() => _dragging = false),
                  onDragDone: (details) {
                    setState(() => _dragging = false);
                    _onDropDone(details);
                  },
                  child: Stack(
                    children: [
                      loading
                          ? const Center(child: CircularProgressIndicator())
                          : _ItemsGrid(
                              items: loaded,
                              libraryFilesDir: app.paths!.filesDir,
                              selectedItemId: selectedItem?.id,
                              selectedIds: app.selectedItemIds,
                              onSelect: (item) => setState(() => selectedItem = item),
                              onToggleBulk: (id) => app.toggleItemSelection(id),
                              onContextMenu: (gridCtx, item, pos) => _handleContextMenu(gridCtx, item, pos),
                            ),
                      if (_dragging)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.all(8),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.file_upload, size: 48, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Upuść pliki, aby zaimportować',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // ─── Details panel ───────────
        SizedBox(
          width: 360,
          child: selectedItem == null
              ? const Center(child: Text('Wybierz element'))
              : _DetailsPanel(
                  item: selectedItem!,
                  libraryFilesDir: app.paths!.filesDir,
                  onOpen: () async {
                    final filePath = LibraryFolders.absPath(app.paths!.filesDir, selectedItem!.storedRelPath);
                    await OpenFilex.open(filePath);
                  },
                  onExport: () => _exportItem(selectedItem!),
                  onMove: () => _moveItem(selectedItem!),
                  onTags: () => _showTagsForItem(selectedItem!),
                  onDelete: () => _deleteItem(selectedItem!),
                  loadTags: () => app.items!.listTagsForItem(selectedItem!.id),
                  loadKeyValues: () => app.items!.listKeyValuesForItem(selectedItem!.id),
                ),
        ),
      ],
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
        leading: ReorderableDragStartListener(
          index: categoryIndex,
          child: const Icon(Icons.drag_handle, size: 20),
        ),
        title: Text(c.name),
        initiallyExpanded: app.selectedCategoryId == c.id,
        children: [
          // Subcategories - reorderable within this category
          ...List.generate(subs.length, (si) {
            final s = subs[si];
            return ListTile(
              key: ValueKey('sub_${s.id}'),
              contentPadding: const EdgeInsets.only(left: 56, right: 8),
              title: Row(
                children: [
                  Expanded(child: Text(s.name)),
                  // Untagged badge on every subcategory
                  FutureBuilder<int>(
                    future: app.items!.countUntaggedItems(s.id),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      if (count == 0) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                  ),
                ],
              ),
              selected: app.selectedSubcategoryId == s.id,
              onTap: () async {
                await app.selectSubcategory(c.id, s.id);
                selectedItem = null;
                await _reload();
              },
            );
          }),
          // Move subcategory up/down buttons (simple for now)
          if (subs.length > 1)
            Padding(
              padding: const EdgeInsets.only(left: 56, right: 8, bottom: 4),
              child: Wrap(
                spacing: 4,
                children: [
                  for (int si = 0; si < subs.length; si++)
                    if (app.selectedSubcategoryId == subs[si].id) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, size: 16),
                        tooltip: 'Move subcategory up',
                        onPressed: si == 0 ? null : () async {
                          final ids = subs.map((s) => s.id).toList();
                          final moved = ids.removeAt(si);
                          ids.insert(si - 1, moved);
                          await app.reorderSubcategories(c.id, ids);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_downward, size: 16),
                        tooltip: 'Move subcategory down',
                        onPressed: si == subs.length - 1 ? null : () async {
                          final ids = subs.map((s) => s.id).toList();
                          final moved = ids.removeAt(si);
                          ids.insert(si + 1, moved);
                          await app.reorderSubcategories(c.id, ids);
                        },
                      ),
                    ],
                ],
              ),
            ),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 56),
            leading: const Icon(Icons.add),
            title: const Text('Dodaj subkategorię'),
            onTap: () async {
              final name = await _promptText('Nazwa subkategorii');
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
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<List<String>?> _pickTagsForGlobalSearchDialog() async {
    final app = context.read<AppState>();
    final selected = <String>{};
    selected.addAll(app.globalSearchTagIds);

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateSB) => AlertDialog(
          title: const Text('Szukaj po tagach (globalnie)'),
          content: SizedBox(
            width: 420,
            height: 420,
            child: ListView(
              children: [
                if (app.tagList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Brak tagów. Dodaj tagi w zakładce "Tagi".'),
                  ),
                for (final t in app.tagList)
                  CheckboxListTile(
                    value: selected.contains(t.id),
                    title: Text(t.name),
                    onChanged: (v) {
                      setStateSB(() {
                        if (v == true) { selected.add(t.id); } else { selected.remove(t.id); }
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
            FilledButton(onPressed: () => Navigator.pop(ctx, selected.toList()), child: const Text('Szukaj')),
          ],
        ),
      ),
    );
  }

  Future<List<String>?> _pickTagsMultiDialog() async {
    final app = context.read<AppState>();
    final selected = <String>{};
    final current = selectedItem == null ? <String>{} : (await app.items!.listTagsForItem(selectedItem!.id)).map((e) => e.id).toSet();
    selected.addAll(current);

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateSB) => AlertDialog(
          title: const Text('Tagi'),
          content: SizedBox(
            width: 420,
            height: 420,
            child: ListView(
              children: [
                for (final t in app.tagList)
                  CheckboxListTile(
                    value: selected.contains(t.id),
                    title: Text(t.name),
                    onChanged: (v) {
                      setStateSB(() {
                        if (v == true) { selected.add(t.id); } else { selected.remove(t.id); }
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
            FilledButton(onPressed: () => Navigator.pop(ctx, selected.toList()), child: const Text('Zapisz')),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _TopBar extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback? onBulk;
  final VoidCallback? onExportFolder;

  const _TopBar({
    required this.onImport,
    required this.onBulk,
    required this.onExportFolder,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.file_upload),
            label: const Text('Importuj'),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Long-press files to select for bulk operations',
            child: OutlinedButton.icon(
              onPressed: onBulk,
              icon: const Icon(Icons.select_all),
              label: Text('Operacje masowe (${app.selectedItemIds.length})'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: app.globalSearchActive ? null : onExportFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Eksportuj folder'),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Items Grid with right-click and drag & drop
// ──────────────────────────────────────────────
class _ItemsGrid extends StatelessWidget {
  final List<MediaItem> items;
  final Directory libraryFilesDir;
  final String? selectedItemId;
  final Set<String> selectedIds;
  final void Function(MediaItem item) onSelect;
  final void Function(String id) onToggleBulk;
  final void Function(BuildContext ctx, MediaItem item, Offset globalPosition) onContextMenu;

  const _ItemsGrid({
    required this.items,
    required this.libraryFilesDir,
    required this.selectedItemId,
    required this.selectedIds,
    required this.onSelect,
    required this.onToggleBulk,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('Brak elementów — zaimportuj pliki lub przeciągnij je tutaj'));

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
        final isBulk = selectedIds.contains(it.id);

        Widget thumb;
        if (it.type == ItemType.image) {
          thumb = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(filePath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, size: 48)),
          );
        } else if (it.type == ItemType.video) {
          thumb = const Center(child: Icon(Icons.movie, size: 56));
        } else {
          thumb = const Center(child: Icon(Icons.insert_drive_file, size: 56));
        }

        return GestureDetector(
          onSecondaryTapDown: (details) {
            onContextMenu(ctx, it, details.globalPosition);
          },
          child: InkWell(
            onTap: () => onSelect(it),
            onLongPress: () => onToggleBulk(it.id),
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
                  Expanded(child: Stack(children: [
                    Positioned.fill(child: thumb),
                    if (it.isDuplicate)
                      Positioned(
                        right: 8, top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(999)),
                          child: const Text('DUP', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ),
                    if (isBulk)
                      Positioned(
                        left: 8, top: 8,
                        child: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                      ),
                  ])),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(it.originalName, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  final MediaItem item;
  final Directory libraryFilesDir;
  final VoidCallback onOpen;
  final VoidCallback onExport;
  final VoidCallback onMove;
  final VoidCallback onTags;
  final VoidCallback onDelete;
  final Future<List<Tag>> Function() loadTags;
  final Future<List<TagKeyValue>> Function() loadKeyValues;

  const _DetailsPanel({
    required this.item,
    required this.libraryFilesDir,
    required this.onOpen,
    required this.onExport,
    required this.onMove,
    required this.onTags,
    required this.onDelete,
    required this.loadTags,
    required this.loadKeyValues,
  });

  @override
  Widget build(BuildContext context) {
    final filePath = LibraryFolders.absPath(libraryFilesDir, item.storedRelPath);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Szczegóły', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (item.type == ItemType.image)
            Expanded(
              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(filePath), fit: BoxFit.contain)),
            )
          else
            Expanded(child: Center(child: Icon(item.type == ItemType.video ? Icons.movie : Icons.insert_drive_file, size: 72))),
          const SizedBox(height: 12),
          Text(item.originalName, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 6),
          Text('SHA256: ${item.sha256.substring(0, 12)}…'),
          if (item.isDuplicate) Text('Duplikat (powiązany: ${item.duplicateOfId ?? "?"})'),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.open_in_new), label: const Text('Otwórz w systemie')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: onExport, icon: const Icon(Icons.download), label: const Text('Eksportuj na dysk')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: onMove, icon: const Icon(Icons.drive_file_move), label: const Text('Przenieś')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: onTags, icon: const Icon(Icons.sell), label: const Text('Tagi')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: onDelete, icon: const Icon(Icons.delete), label: const Text('Usuń')),
          const SizedBox(height: 10),
          FutureBuilder<List<Tag>>(
            future: loadTags(),
            builder: (ctx, snap) {
              final tags = snap.data ?? const <Tag>[];
              if (tags.isEmpty) return const Text('Brak tagów');
              return Wrap(spacing: 6, runSpacing: 6, children: [for (final t in tags) Chip(label: Text(t.name))]);
            },
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<TagKeyValue>>(
            future: loadKeyValues(),
            builder: (ctx, snap) {
              final kv = snap.data ?? const <TagKeyValue>[];
              if (kv.isEmpty) return const SizedBox.shrink();
              return Wrap(spacing: 6, runSpacing: 6, children: [for (final v in kv) Chip(label: Text(formatKeyValueChip(v)))]);
            },
          ),
        ],
      ),
    );
  }
}
