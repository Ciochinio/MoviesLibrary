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

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final Set<String> _simpleSelected = {};
  final Set<String> _kvSelected = {};

  bool _loading = false;
  List<MediaItem> _results = const [];
  MediaItem? _selected;

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
      );
      if (!mounted) return;
      setState(() {
        _results = res;
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
      _results = const [];
      _selected = null;
    });
  }

  Future<String?> _pickSubcategoryDialog() async {
    final app = context.read<AppState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Wybierz docelową subkategorię'),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Row(
      children: [
        SizedBox(
          width: 320,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Szukaj', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: (_simpleSelected.isEmpty && _kvSelected.isEmpty) ? null : _runSearch,
                      icon: const Icon(Icons.search),
                      label: const Text('Szukaj'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: (_simpleSelected.isEmpty && _kvSelected.isEmpty && _results.isEmpty) ? null : _clearFilters,
                      icon: const Icon(Icons.clear),
                      label: const Text('Wyczyść'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: [
                      Text('Tagi', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      if (app.tagList.isEmpty)
                        const Text('Brak tagów. Dodaj je w zakładce „Tagi”.')
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final t in app.tagList)
                              FilterChip(
                                label: Text(t.name),
                                selected: _simpleSelected.contains(t.id),
                                onSelected: (v) => setState(() {
                                  if (v) {
                                    _simpleSelected.add(t.id);
                                  } else {
                                    _simpleSelected.remove(t.id);
                                  }
                                }),
                              ),
                          ],
                        ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      Text('Key:Value', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      if (app.tagKeyList.isEmpty)
                        const Text('Brak kluczy. Dodaj je w zakładce „Tagi” → „Key:Value”.')
                      else
                        ...app.tagKeyList.map((k) {
                          final values = app.valuesForKey(k.id);
                          return ExpansionTile(
                            title: Text(k.key),
                            children: [
                              if (values.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Text('Brak wartości.'),
                                ),
                              for (final v in values)
                                CheckboxListTile(
                                  value: _kvSelected.contains(v.id),
                                  title: Text(v.value),
                                  onChanged: (checked) => setState(() {
                                    if (checked == true) {
                                      _kvSelected.add(v.id);
                                    } else {
                                      _kvSelected.remove(v.id);
                                    }
                                  }),
                                ),
                            ],
                          );
                        }),
                      const SizedBox(height: 8),
                      Text(
                        'Zaznaczone: ${_simpleSelected.length} tagów, ${_kvSelected.length} key:value',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Text('Wyniki', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (_loading) const Padding(padding: EdgeInsets.only(right: 12), child: CircularProgressIndicator()),
                    if (!_loading) Text('${_results.length}'),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _ItemsGrid(
                        items: _results,
                        libraryFilesDir: app.paths!.filesDir,
                        selectedItemId: _selected?.id,
                        onSelect: (it) => setState(() => _selected = it),
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 360,
          child: _selected == null
              ? const Center(child: Text('Wybierz element'))
              : _DetailsPanel(
                  item: _selected!,
                  libraryFilesDir: app.paths!.filesDir,
                  onOpen: () async {
                    final filePath = LibraryFolders.absPath(app.paths!.filesDir, _selected!.storedRelPath);
                    await OpenFilex.open(filePath);
                  },
                  onExport: () async {
                    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Wybierz folder docelowy');
                    if (dir == null) return;
                    final src = File(LibraryFolders.absPath(app.paths!.filesDir, _selected!.storedRelPath));
                    if (!await src.exists()) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plik nie istnieje.')));
                      return;
                    }
                    final dest = _uniquePath(p.join(dir, _selected!.originalName));
                    await src.copy(dest);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wyeksportowano plik.')));
                  },
                  onMove: () async {
                    final subId = await _pickSubcategoryDialog();
                    if (subId == null) return;
                    final list = await app.items!.listItemsByIds([_selected!.id]);
                    await app.items!.moveItemsToSubcategory(list, subId);
                    await app.refreshFromDiskAndMigrate();
                    await _runSearch();
                  },
                  onTags: () async {
                    final curSimple = await app.items!.listTagIdsForItem(_selected!.id);
                    final curKv = await app.items!.listKeyValueIdsForItem(_selected!.id);
                    final picked = await showTagManagerDialog(
                      context,
                      initialSimpleTagIds: curSimple,
                      initialKeyValueIds: curKv,
                    );
                    if (picked == null) return;
                    await app.setTagsForItem(
                      itemId: _selected!.id,
                      simpleTagIds: picked.simpleTagIds,
                      keyValueIds: picked.keyValueIds,
                    );
                    await _runSearch();
                  },
                  onDelete: () async {
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
                    }

                    if (!proceed) return;

                    if (dontAskAgain) {
                      await app.setConfirmDelete(false);
                      messenger.showSnackBar(const SnackBar(content: Text('Wyłączono potwierdzanie usuwania.')));
                    }

                    final res = await app.deleteOneItem(_selected!);
                    if (res.deleted.isNotEmpty) {
                      messenger.showSnackBar(const SnackBar(content: Text('Usunięto.')));
                      setState(() => _selected = null);
                      await _runSearch();
                    } else {
                      messenger.showSnackBar(const SnackBar(content: Text('Nie udało się usunąć pliku (np. brak uprawnień).')));
                    }
                  },
                ),
        ),
      ],
    );
  }
}

class _ItemsGrid extends StatelessWidget {
  final List<MediaItem> items;
  final Directory libraryFilesDir;
  final String? selectedItemId;
  final void Function(MediaItem item) onSelect;

  const _ItemsGrid({
    required this.items,
    required this.libraryFilesDir,
    required this.selectedItemId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('Brak wyników'));
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

        Widget thumb;
        if (it.type == ItemType.image) {
          thumb = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(filePath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, size: 48),
            ),
          );
        } else if (it.type == ItemType.video) {
          thumb = const Center(child: Icon(Icons.movie, size: 56));
        } else {
          thumb = const Center(child: Icon(Icons.insert_drive_file, size: 56));
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
                    ],
                  ),
                ),
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

  const _DetailsPanel({
    required this.item,
    required this.libraryFilesDir,
    required this.onOpen,
    required this.onExport,
    required this.onMove,
    required this.onTags,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
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
            future: app.items!.listTagsForItem(item.id),
            builder: (ctx, snap) {
              final tags = snap.data ?? const <Tag>[];
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in tags) Chip(label: Text(t.name)),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<TagKeyValue>>(
            future: app.items!.listKeyValuesForItem(item.id),
            builder: (ctx, snap) {
              final kv = snap.data ?? const <TagKeyValue>[];
              if (kv.isEmpty) return const SizedBox.shrink();
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in kv) Chip(label: Text(formatKeyValueChip(v))),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
