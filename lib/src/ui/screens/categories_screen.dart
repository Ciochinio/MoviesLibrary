import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';

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
              Text('Kategorie', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  final name = await _prompt(context, 'Nowa kategoria');
                  if (name == null || name.trim().isEmpty) return;
                  await context.read<AppState>().createCategory(name.trim());
                },
                icon: const Icon(Icons.add),
                label: const Text('Dodaj kategorię'),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
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
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'tag_all',
          child: Row(
            children: [
              Icon(Icons.sell),
              SizedBox(width: 12),
              Text('Tag All Items...'),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == 'tag_all') {
        await _showBulkTagDialog(context, subcategoryId, subcategoryName);
      }
    });
  }

  Future<void> _showBulkTagDialog(BuildContext context, String subcategoryId, String subcategoryName) async {
    final app = context.read<AppState>();
    
    // Get count of items in subcategory
    final items = await app.items!.listItemsInSubcategory(subcategoryId);
    if (items.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in this subcategory')),
      );
      return;
    }

    // Show tag selection dialog
    final selectedTags = <String>{};
    final selectedKeyValues = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Tag All Items in "$subcategoryName"'),
          content: SizedBox(
            width: 500,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('This will add tags to ${items.length} items.', 
                  style: Theme.of(ctx).textTheme.bodyLarge),
                const SizedBox(height: 16),
                Text('Simple Tags:', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (app.tagList.isEmpty)
                  const Text('No tags available. Create some in Tags screen.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: app.tagList.map((tag) => FilterChip(
                      label: Text(tag.name),
                      selected: selectedTags.contains(tag.id),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            selectedTags.add(tag.id);
                          } else {
                            selectedTags.remove(tag.id);
                          }
                        });
                      },
                    )).toList(),
                  ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text('Custom Tags:', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (app.tagKeyList.isEmpty)
                  const Text('No custom tags available.')
                else
                  Expanded(
                    child: ListView(
                      children: app.tagKeyList.map((key) {
                        final values = app.valuesForKey(key.id);
                        return ExpansionTile(
                          title: Text(key.key),
                          children: values.map((v) => CheckboxListTile(
                            dense: true,
                            value: selectedKeyValues.contains(v.id),
                            title: Text(v.value),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  selectedKeyValues.add(v.id);
                                } else {
                                  selectedKeyValues.remove(v.id);
                                }
                              });
                            },
                          )).toList(),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: (selectedTags.isEmpty && selectedKeyValues.isEmpty)
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Apply Tags'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    // Apply tags
    final messenger = ScaffoldMessenger.of(context);
    
    try {
      int taggedCount = 0;
      for (final tagId in selectedTags) {
        final count = await app.items!.bulkAddTagToSubcategory(subcategoryId, tagId);
        taggedCount = count; // All items get tagged
      }
      
      for (final kvId in selectedKeyValues) {
        await app.items!.bulkAddKeyValueToSubcategory(subcategoryId, kvId);
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Tagged $taggedCount items with ${selectedTags.length} tags and ${selectedKeyValues.length} custom tags')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
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
                  tooltip: 'Zmień nazwę',
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    final name = await CategoriesScreen._prompt(context, 'Nowa nazwa', initial: category.name);
                    if (name == null || name.trim().isEmpty) return;
                    await context.read<AppState>().renameCategory(category.id, name.trim());
                  },
                ),
                IconButton(
                  tooltip: 'Usuń (przenieś do Stash)',
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Usunąć kategorię?'),
                        content: const Text('Elementy zostaną przeniesione do Stash.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
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
            Text('Subkategorie (poziom 2 — wymagany):', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 6),
            for (final s in subs)
              GestureDetector(
                onSecondaryTapDown: (details) {
                  _showSubcategoryContextMenu(context, details.globalPosition, s.id, s.name);
                },
                child: ListTile(
                  dense: true,
                  title: Text(s.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Zmień nazwę',
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final name = await CategoriesScreen._prompt(context, 'Nowa nazwa', initial: s.name);
                          if (name == null || name.trim().isEmpty) return;
                          await context.read<AppState>().renameSubcategory(s.id, name.trim());
                        },
                      ),
                      IconButton(
                        tooltip: 'Usuń (przenieś do Stash)',
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Usunąć subkategorię?'),
                              content: const Text('Elementy zostaną przeniesione do Stash.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
                                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
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
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () async {
                final name = await CategoriesScreen._prompt(context, 'Nazwa subkategorii');
                if (name == null || name.trim().isEmpty) return;
                await context.read<AppState>().createSubcategory(category.id, name.trim());
              },
              icon: const Icon(Icons.add),
              label: const Text('Dodaj subkategorię'),
            ),
          ],
        ),
      ),
    );
  }
}
