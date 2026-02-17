import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';

class TagsScreen extends StatelessWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Tagi', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            const TabBar(
              tabs: [
                Tab(text: 'Proste'),
                Tab(text: 'Custom Tags'),
              ],
            ),
            const SizedBox(height: 12),
            const Expanded(
              child: TabBarView(
                children: [
                  _SimpleTagsTab(),
                  _KeyValueTagsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<({String name, String description})?> _promptWithDescription(
    BuildContext context, 
    String title, 
    {String? initialName, String? initialDescription}
  ) async {
    final nameCtrl = TextEditingController(text: initialName ?? '');
    final descCtrl = TextEditingController(text: initialDescription ?? '');
    return showDialog<({String name, String description})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
                hintText: 'e.g., "Films by Criterion Collection"',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, (name: nameCtrl.text, description: descCtrl.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Simple Tags Tab — drag-and-drop reordering
// ──────────────────────────────────────────────
class _SimpleTagsTab extends StatelessWidget {
  const _SimpleTagsTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Drag to reorder',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () async {
                final result = await TagsScreen._promptWithDescription(context, 'Nowy tag');
                if (result == null || result.name.trim().isEmpty) return;
                final a = context.read<AppState>();
                await a.tags!.createTag(result.name.trim(), description: result.description);
                await a.refreshAll();
              },
              icon: const Icon(Icons.add),
              label: const Text('Dodaj'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: app.tagList.length,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex--;
              final ids = app.tagList.map((t) => t.id).toList();
              final movedId = ids.removeAt(oldIndex);
              ids.insert(newIndex, movedId);
              await context.read<AppState>().reorderTags(ids);
            },
            itemBuilder: (ctx, i) {
              final t = app.tagList[i];
              return ListTile(
                key: ValueKey(t.id),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const Icon(Icons.drag_handle),
                ),
                title: Text(t.name),
                subtitle: t.description.isNotEmpty ? Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Zmień nazwę',
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final result = await TagsScreen._promptWithDescription(
                          context, 
                          'Edytuj tag',
                          initialName: t.name,
                          initialDescription: t.description,
                        );
                        if (result == null || result.name.trim().isEmpty) return;
                        final a = context.read<AppState>();
                        await a.tags!.renameTag(t.id, result.name.trim());
                        await a.tags!.updateTagDescription(t.id, result.description);
                        await a.refreshAll();
                      },
                    ),
                    IconButton(
                      tooltip: 'Usuń',
                      icon: const Icon(Icons.delete),
                      onPressed: () async {
                        final usage = await context.read<AppState>().countTagUsage(t.id);
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Usunąć tag?'),
                            content: Text('Tag zostanie usunięty z $usage elementów.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
                              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await context.read<AppState>().deleteTag(t.id);
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// Custom Tags (Key:Value) Tab — drag-and-drop
// reordering for keys
// ──────────────────────────────────────────────
class _KeyValueTagsTab extends StatelessWidget {
  const _KeyValueTagsTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Drag to reorder keys',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () async {
                final result = await TagsScreen._promptWithDescription(context, 'Nowy klucz');
                if (result == null || result.name.trim().isEmpty) return;
                final a = context.read<AppState>();
                await a.tags!.createTagKey(result.name.trim(), description: result.description);
                await a.refreshAll();
              },
              icon: const Icon(Icons.add),
              label: const Text('Dodaj klucz'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ReorderableListView(
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex--;
              // Filter out the "empty" placeholder if present
              final keyIds = app.tagKeyList.map((k) => k.id).toList();
              if (oldIndex >= keyIds.length || newIndex >= keyIds.length) return;
              final movedId = keyIds.removeAt(oldIndex);
              keyIds.insert(newIndex, movedId);
              await context.read<AppState>().reorderTagKeys(keyIds);
            },
            children: [
              for (int ki = 0; ki < app.tagKeyList.length; ki++)
                _buildKeyTile(context, app, app.tagKeyList[ki], ki),
              if (app.tagKeyList.isEmpty)
                const Padding(
                  key: ValueKey('__empty__'),
                  padding: EdgeInsets.all(16),
                  child: Text('Brak kluczy. Dodaj pierwszy klucz przyciskiem powyżej.'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeyTile(BuildContext context, AppState app, dynamic k, int index) {
    return ExpansionTile(
      key: ValueKey(k.id),
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle),
      ),
      title: Text(k.key),
      subtitle: k.description.isNotEmpty ? Text(k.description, style: const TextStyle(fontSize: 12)) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zmień nazwę',
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final result = await TagsScreen._promptWithDescription(
                context, 
                'Edytuj klucz',
                initialName: k.key,
                initialDescription: k.description,
              );
              if (result == null || result.name.trim().isEmpty) return;
              final a = context.read<AppState>();
              await a.tags!.renameTagKey(k.id, result.name.trim());
              await a.tags!.updateTagKeyDescription(k.id, result.description);
              await a.refreshAll();
            },
          ),
          IconButton(
            tooltip: 'Usuń',
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final usage = await context.read<AppState>().countTagKeyUsage(k.id);
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Usunąć klucz?'),
                  content: Text('Klucz i wszystkie jego wartości zostaną usunięte z $usage przypisań.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
                  ],
                ),
              );
              if (ok == true) {
                await context.read<AppState>().deleteTagKey(k.id);
              }
            },
          ),
        ],
      ),
      children: [
        for (final v in app.valuesForKey(k.id))
          ListTile(
            title: Text(v.value),
            subtitle: v.description.isNotEmpty ? Text(v.description, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Zmień nazwę',
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    final result = await TagsScreen._promptWithDescription(
                      context,
                      'Edytuj wartość',
                      initialName: v.value,
                      initialDescription: v.description,
                    );
                    if (result == null || result.name.trim().isEmpty) return;
                    final a = context.read<AppState>();
                    await a.tags!.renameValue(v.id, result.name.trim());
                    await a.tags!.updateValueDescription(v.id, result.description);
                    await a.refreshAll();
                  },
                ),
                IconButton(
                  tooltip: 'Usuń',
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    final usage = await context.read<AppState>().countTagKeyValueUsage(v.id);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Usunąć wartość?'),
                        content: Text('Wartość zostanie usunięta z $usage elementów.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await context.read<AppState>().deleteTagKeyValue(v.id);
                    }
                  },
                ),
              ],
            ),
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Dodaj wartość'),
          onTap: () async {
            final result = await TagsScreen._promptWithDescription(context, 'Nowa wartość');
            if (result == null || result.name.trim().isEmpty) return;
            final a = context.read<AppState>();
            await a.tags!.createValue(k.id, result.name.trim(), description: result.description);
            await a.refreshAll();
          },
        ),
      ],
    );
  }
}
