import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  MediaItem? selectedItem;
  List<MediaItem> loaded = [];
  bool loading = false;

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
    // keep selection if possible
    if (selectedItem != null) {
      selectedItem = loaded.where((e) => e.id == selectedItem!.id).cast<MediaItem?>().firstOrNull;
    }
    setState(() => loading = false);
  }

  Future<void> _import() async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null || res.files.isEmpty) return;

    for (final f in res.files) {
      try {
      if (f.path == null) continue;
      final file = File(f.path!);

      // Choose target: if no selection, stash
      final target = app.selectedSubcategoryId ?? app.stashSubcategoryId!;

      // duplicate check: ask user
      // We do a pre-check by attempting with "do not add duplicates" and see if it returns existing.
      final pre = await app.importSingleWithDuplicateDecision(
        source: file,
        targetSubcategoryId: target,
        addDuplicateAsSeparateFile: false,
      );

      if (pre.existingDuplicate != null && pre.inserted == null) {
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
        }
      } else {
        // inserted already
      }
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Błąd importu: $e')));
      }
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
    final src = File(p.join(app.paths!.filesDir.path, item.storedRelPath));
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Row(
      children: [
        SizedBox(
          width: 280,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Kategorie',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Odśwież',
                      onPressed: () async => _reload(),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    for (final c in app.categoryList)
                      ExpansionTile(
                        title: Text(c.name),
                        initiallyExpanded: app.selectedCategoryId == c.id,
                        children: [
                          for (final s in app.subcategoriesFor(c.id))
                            ListTile(
                              title: Text(s.name),
                              selected: app.selectedSubcategoryId == s.id,
                              onTap: () async {
                                await app.selectSubcategory(c.id, s.id);
                                selectedItem = null;
                                await _reload();
                              },
                            ),
                          ListTile(
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
                  ],
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              _TopBar(
                onImport: _import,
                onBulk: app.selectedItemIds.isEmpty ? null : _bulkActions,
                onSearch: () async {
                  final tags = await _pickTagsForGlobalSearchDialog();
                  if (tags == null) return;
                  await app.setGlobalTagSearch(tags);
                  selectedItem = null;
                  await _reload();
                },
                  onClearSearch: app.globalSearchActive
      ? () async {
          app.clearGlobalTagSearch();
          selectedItem = null;
          await _reload();
        }
      : null,
),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : _ItemsGrid(
                        items: loaded,
                        libraryFilesDir: app.paths!.filesDir,
                        selectedItemId: selectedItem?.id,
                        selectedIds: app.selectedItemIds,
                        onSelect: (item) => setState(() => selectedItem = item),
                        onToggleBulk: (id) => app.toggleItemSelection(id),
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 360,
          child: selectedItem == null
              ? const Center(child: Text('Wybierz element'))
              : _DetailsPanel(
                  item: selectedItem!,
                  libraryFilesDir: app.paths!.filesDir,
                  onOpen: () async {
                    final filePath = p.join(app.paths!.filesDir.path, selectedItem!.storedRelPath);
                    await OpenFilex.open(filePath);
                  },
                  onExport: () async {
                    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Wybierz folder docelowy');
                    if (dir == null) return;
                    final src = File(p.join(app.paths!.filesDir.path, selectedItem!.storedRelPath));
                    if (!await src.exists()) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plik nie istnieje.')));
                      return;
                    }
                    final dest = _uniquePath(p.join(dir, selectedItem!.originalName));
                    await src.copy(dest);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wyeksportowano plik.')));
                  },
                  onMove: () async {
                    final subId = await _pickSubcategoryDialog();
                    if (subId == null) return;
                    await app.items!.setItemSubcategory(selectedItem!.id, subId);
                    await _reload();
                  },
                  onTags: () async {
                    final chosen = await _pickTagsMultiDialog();
                    if (chosen == null) return;
                    // set difference updates
                    final current = await app.items!.listTagsForItem(selectedItem!.id);
                    final currentIds = current.map((e) => e.id).toSet();
                    final newIds = chosen.toSet();

                    for (final add in newIds.difference(currentIds)) {
                      await app.items!.addTagToItem(selectedItem!.id, add);
                    }
                    for (final rem in currentIds.difference(newIds)) {
                      await app.items!.removeTagFromItem(selectedItem!.id, rem);
                    }
                    await _reload();
                  },
                  onDelete: () async {
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

  final existed = File(p.join(app.paths!.filesDir.path, selectedItem!.storedRelPath)).existsSync();

  try {
    final res = await app.deleteOneItem(selectedItem!);
    if (res.failed.isNotEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Nie udało się usunąć pliku (może być używany przez inny program).')));
      return;
    }
    selectedItem = null;
    await _reload();
    if (!existed) {
      messenger.showSnackBar(const SnackBar(content: Text('Plik nie istnieje — usunięto wpis z biblioteki.')));
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('Usunięto element.')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Błąd usuwania: $e')));
  }
},
loadTags: () => app.items!.listTagsForItem(selectedItem!.id),
                ),
        ),
      ],
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
                      if (v == true) {
                        selected.add(t.id);
                      } else {
                        selected.remove(t.id);
                      }
                    });
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, selected.toList()),
            child: const Text('Szukaj'),
          ),
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
                        if (v == true) {
                          selected.add(t.id);
                        } else {
                          selected.remove(t.id);
                        }
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
  final VoidCallback onSearch;
  final VoidCallback? onClearSearch;

  const _TopBar({
    required this.onImport,
    required this.onBulk,
    required this.onSearch,
    required this.onClearSearch,
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
          OutlinedButton.icon(
            onPressed: onBulk,
            icon: const Icon(Icons.select_all),
            label: Text('Operacje masowe (${app.selectedItemIds.length})'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.manage_search),
            label: const Text('Szukaj po tagach'),
          ),
          if (onClearSearch != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onClearSearch,
              icon: const Icon(Icons.clear),
              label: const Text('Wyczyść'),
            ),
          ],
          const Spacer(),
          if (app.globalSearchActive)
            Chip(label: Text('Wyniki globalne (${app.globalSearchTagIds.length} tagi)')),
        ],
      ),
    );
  }
}


class _ItemsGrid extends StatelessWidget {
  final List<MediaItem> items;
  final Directory libraryFilesDir;
  final String? selectedItemId;
  final Set<String> selectedIds;
  final void Function(MediaItem item) onSelect;
  final void Function(String id) onToggleBulk;

  const _ItemsGrid({
    required this.items,
    required this.libraryFilesDir,
    required this.selectedItemId,
    required this.selectedIds,
    required this.onSelect,
    required this.onToggleBulk,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('Brak elementów'));

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
        final filePath = p.join(libraryFilesDir.path, it.storedRelPath);
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

        return InkWell(
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
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('DUP', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ),
                  if (isBulk)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                    ),
                ])),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    it.originalName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
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

  const _DetailsPanel({
    required this.item,
    required this.libraryFilesDir,
    required this.onOpen,
    required this.onExport,
    required this.onMove,
    required this.onTags,
    required this.onDelete,
    required this.loadTags,
  });

  @override
  Widget build(BuildContext context) {
    final filePath = p.join(libraryFilesDir.path, item.storedRelPath);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Szczegóły', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (item.type == ItemType.image)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(filePath), fit: BoxFit.contain),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Icon(item.type == ItemType.video ? Icons.movie : Icons.insert_drive_file, size: 72),
              ),
            ),
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
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in tags) Chip(label: Text(t.name)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
