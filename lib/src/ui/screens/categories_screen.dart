import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../widgets/tag_manager_dialog.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Categories', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  final name = await _prompt(context, 'New category');
                  if (name == null || name.trim().isEmpty) return;
                  await context.read<AppState>().createCategory(name.trim());
                },
                icon: const Icon(Icons.add),
                label: const Text('Add category'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final c in app.categoryList) ...[
                  _CategoryCard(category: c),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<String?> _prompt(BuildContext context, String title, {String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final Category category;
  const _CategoryCard({required this.category});

  void _showSubcategoryContextMenu(BuildContext context, Offset position, String subcategoryId, String subcategoryName) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(position & const Size(40, 40), Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(value: 'tag_all', child: Row(children: [Icon(Icons.sell), SizedBox(width: 12), Text('Tag All Items...')])),
        PopupMenuItem(value: 'auto_tags', child: Row(children: [Icon(Icons.auto_fix_high), SizedBox(width: 12), Text('Auto-Tags Settings...')])),
      ],
    ).then((value) async {
      if (value == 'tag_all') {
        await _showBulkTagDialog(context, subcategoryId, subcategoryName);
      } else if (value == 'auto_tags') {
        await _showAutoTagDialog(context, subcategoryId, subcategoryName);
      }
    });
  }

  // ─── Bulk Tag Dialog (side-by-side chips) ──

  Future<void> _showBulkTagDialog(BuildContext context, String subcategoryId, String subcategoryName) async {
    final app = context.read<AppState>();
    final items = await app.items!.listItemsInSubcategory(subcategoryId);
    if (items.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No items in this subcategory')));
      return;
    }

    final selectedTags = <String>{};
    final selectedKeyValues = <String>{};
    bool alsoAutoTag = false;

    final currentAutoTags = await app.categories!.getAutoTagIds(subcategoryId);
    final currentAutoKv = await app.categories!.getAutoKeyValueIds(subcategoryId);

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Tag All Items in "$subcategoryName"'),
          content: SizedBox(
            width: 700,
            height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('This will add tags to ${items.length} items.', style: Theme.of(ctx).textTheme.bodyLarge),
                const SizedBox(height: 12),
                Expanded(
                  child: TagPickerBody(
                    simpleSelected: selectedTags,
                    kvSelected: selectedKeyValues,
                    onSimpleChanged: (id, v) => setState(() {
                      if (v) { selectedTags.add(id); } else { selectedTags.remove(id); }
                    }),
                    onKvChanged: (id, v) => setState(() {
                      if (v) { selectedKeyValues.add(id); } else { selectedKeyValues.remove(id); }
                    }),
                  ),
                ),
                const Divider(),
                CheckboxListTile(
                  value: alsoAutoTag,
                  title: const Text('Also apply to future imports'),
                  subtitle: const Text('New files added to this folder will get these tags automatically'),
                  onChanged: (v) => setState(() => alsoAutoTag = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: (selectedTags.isEmpty && selectedKeyValues.isEmpty) ? null : () => Navigator.pop(ctx, true),
              child: const Text('Apply Tags'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      int taggedCount = 0;
      for (final tagId in selectedTags) {
        final count = await app.items!.bulkAddTagToSubcategory(subcategoryId, tagId);
        taggedCount = count;
      }
      for (final kvId in selectedKeyValues) {
        await app.items!.bulkAddKeyValueToSubcategory(subcategoryId, kvId);
      }
      if (alsoAutoTag) {
        final mergedTags = {...currentAutoTags, ...selectedTags};
        final mergedKv = {...currentAutoKv, ...selectedKeyValues};
        await app.categories!.setAutoTags(subcategoryId, mergedTags, mergedKv);
      }
      final autoMsg = alsoAutoTag ? ' (+ auto-tag enabled)' : '';
      messenger.showSnackBar(SnackBar(content: Text('Tagged $taggedCount items with ${selectedTags.length} tags and ${selectedKeyValues.length} custom tags$autoMsg')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ─── Auto-Tag Settings Dialog ──────────────

  Future<void> _showAutoTagDialog(BuildContext context, String subcategoryId, String subcategoryName) async {
    final app = context.read<AppState>();
    final editTags = (await app.categories!.getAutoTagIds(subcategoryId)).toSet();
    final editKv = (await app.categories!.getAutoKeyValueIds(subcategoryId)).toSet();

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Auto-Tags for "$subcategoryName"'),
          content: SizedBox(
            width: 700,
            height: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Files imported or moved into this folder will automatically get these tags.',
                  style: Theme.of(ctx).textTheme.bodyMedium),
                const SizedBox(height: 12),
                Expanded(
                  child: TagPickerBody(
                    simpleSelected: editTags,
                    kvSelected: editKv,
                    onSimpleChanged: (id, v) => setState(() {
                      if (v) { editTags.add(id); } else { editTags.remove(id); }
                    }),
                    onKvChanged: (id, v) => setState(() {
                      if (v) { editKv.add(id); } else { editKv.remove(id); }
                    }),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (editTags.isNotEmpty || editKv.isNotEmpty)
              TextButton(
                onPressed: () => setState(() { editTags.clear(); editKv.clear(); }),
                child: const Text('Clear All'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    await app.categories!.setAutoTags(subcategoryId, editTags, editKv);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      editTags.isEmpty && editKv.isEmpty
          ? 'Auto-tags cleared for "$subcategoryName"'
          : 'Auto-tags saved: ${editTags.length} tags, ${editKv.length} custom tags',
    )));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final subs = app.subcategoriesFor(category.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(category.name, style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    final name = await CategoriesScreen._prompt(context, 'New name', initial: category.name);
                    if (name == null || name.trim().isEmpty) return;
                    await context.read<AppState>().renameCategory(category.id, name.trim());
                  },
                ),
                IconButton(
                  tooltip: 'Delete (move to Stash)',
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Delete category?'),
                        content: const Text('Items will be moved to Stash.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await context.read<AppState>().deleteCategoryMoveToStash(category.id);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Subcategories:', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 6),
            // ── Reorderable subcategory list ─────────────────────────────
            if (subs.isNotEmpty) ...[
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: (subs.length * 56.0).clamp(0.0, 600.0)),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: subs.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex--;
                    final ids = subs.map((s) => s.id).toList();
                    final movedId = ids.removeAt(oldIndex);
                    ids.insert(newIndex, movedId);
                    await context.read<AppState>().reorderSubcategories(category.id, ids);
                  },
                  itemBuilder: (ctx, si) {
                    final s = subs[si];
                    return GestureDetector(
                      key: ValueKey(s.id),
                      onSecondaryTapDown: (details) {
                        _showSubcategoryContextMenu(context, details.globalPosition, s.id, s.name);
                      },
                      child: ListTile(
                        dense: true,
                        leading: ReorderableDragStartListener(
                          index: si,
                          child: const Icon(Icons.drag_handle, size: 18),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(s.name)),
                            FutureBuilder<bool>(
                              future: app.categories!.hasAutoTags(s.id),
                              builder: (context, snapshot) {
                                if (snapshot.data != true) return const SizedBox.shrink();
                                return Tooltip(
                                  message: 'Auto-tags enabled — right-click to configure',
                                  child: Icon(Icons.auto_fix_high, size: 16, color: Theme.of(context).colorScheme.primary),
                                );
                              },
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Rename',
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                final name = await CategoriesScreen._prompt(context, 'New name', initial: s.name);
                                if (name == null || name.trim().isEmpty) return;
                                await context.read<AppState>().renameSubcategory(s.id, name.trim());
                              },
                            ),
                            IconButton(
                              tooltip: 'Delete (move to Stash)',
                              icon: const Icon(Icons.delete),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Delete subcategory?'),
                                    content: const Text('Items will be moved to Stash.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await context.read<AppState>().deleteSubcategoryMoveToStash(s.id);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
            ],
            OutlinedButton.icon(
              onPressed: () async {
                final name = await CategoriesScreen._prompt(context, 'Subcategory name');
                if (name == null || name.trim().isEmpty) return;
                await context.read<AppState>().createSubcategory(category.id, name.trim());
              },
              icon: const Icon(Icons.add),
              label: const Text('Add subcategory'),
            ),
          ],
        ),
      ),
    );
  }
}
