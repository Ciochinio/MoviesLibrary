import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';

class TagsScreen extends StatelessWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Tags', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            const TabBar(
              tabs: [
                Tab(text: 'Tags'),
                Tab(text: 'Custom Tags'),
                Tab(text: 'Name Order'),
              ],
            ),
            const SizedBox(height: 12),
            const Expanded(
              child: TabBarView(
                children: [
                  _SimpleTagsTab(),
                  _KeyValueTagsTab(),
                  _NameOrderTab(),
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
    String title, {
    String? initialName,
    String? initialDescription,
  }) async {
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
                hintText: 'e.g., "Films by "',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
// Simple Tags Tab
// ──────────────────────────────────────────────
class _SimpleTagsTab extends StatelessWidget {
  const _SimpleTagsTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final groups = app.tagGroupList;
    final allTags = app.tagList;
    final ungrouped = allTags.where((t) => t.groupId == null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Use arrows to reorder within groups',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () async {
                final result = await TagsScreen._promptWithDescription(context, 'New group');
                if (result == null || result.name.trim().isEmpty) return;
                await context.read<AppState>().createTagGroup(result.name.trim());
              },
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('Add group'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () async {
                final result = await TagsScreen._promptWithDescription(context, 'New tag');
                if (result == null || result.name.trim().isEmpty) return;
                final a = context.read<AppState>();
                await a.tags!.createTag(result.name.trim(), description: result.description);
                await a.refreshAll();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add tag'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              if (groups.isEmpty && ungrouped.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No tags yet. Add the first one above.'),
                ),
              for (int gi = 0; gi < groups.length; gi++)
                _GroupTile(
                  key: ValueKey(groups[gi].id),
                  group: groups[gi],
                  tags: allTags.where((t) => t.groupId == groups[gi].id).toList(),
                  groupIndex: gi,
                  groupCount: groups.length,
                ),
              if (ungrouped.isNotEmpty)
                _UngroupedTile(tags: ungrouped),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Group tile ────────────────────────────────────────────────────────────────
class _GroupTile extends StatelessWidget {
  final TagGroup group;
  final List<Tag> tags;
  final int groupIndex;
  final int groupCount;

  const _GroupTile({
    super.key,
    required this.group,
    required this.tags,
    required this.groupIndex,
    required this.groupCount,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: PageStorageKey(group.id),
      title: Text(group.name, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text('${tags.length} tag${tags.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Rename group',
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () async {
              final result = await TagsScreen._promptWithDescription(
                context, 'Rename group',
                initialName: group.name,
              );
              if (result == null || result.name.trim().isEmpty) return;
              await context.read<AppState>().renameTagGroup(group.id, result.name.trim());
            },
          ),
          IconButton(
            tooltip: 'Delete group',
            icon: const Icon(Icons.delete, size: 18),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Delete group?'),
                  content: Text(
                    tags.isEmpty
                        ? 'Group "${group.name}" will be deleted.'
                        : 'Group "${group.name}" will be deleted. Its ${tags.length} tag${tags.length == 1 ? '' : 's'} will move to Other.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) {
                await context.read<AppState>().deleteTagGroup(group.id);
              }
            },
          ),
        ],
      ),
      children: [
        if (tags.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No tags in this group.', style: TextStyle(fontSize: 12)),
          )
        else
          _TagList(groupId: group.id, tags: tags),
        ListTile(
          dense: true,
          leading: const Icon(Icons.add, size: 18),
          title: const Text('Add tag to group'),
          onTap: () async {
            final result = await TagsScreen._promptWithDescription(context, 'New tag');
            if (result == null || result.name.trim().isEmpty) return;
            final a = context.read<AppState>();
            final tag = await a.tags!.createTag(result.name.trim(), description: result.description);
            await a.tags!.setTagGroup(tag.id, group.id);
            await a.refreshAll();
          },
        ),
      ],
    );
  }
}

// ── Tag list within a group (no ReorderableListView) ─────────────────────────
class _TagList extends StatelessWidget {
  final String? groupId;
  final List<Tag> tags;

  const _TagList({required this.groupId, required this.tags});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < tags.length; i++)
          _TagListTile(
            key: ValueKey(tags[i].id),
            tag: tags[i],
            groupId: groupId,
            onMoveUp: i == 0
                ? null
                : () async {
                    final ids = tags.map((t) => t.id).toList();
                    final id = ids.removeAt(i);
                    ids.insert(i - 1, id);
                    await context.read<AppState>().reorderTags(ids);
                  },
            onMoveDown: i == tags.length - 1
                ? null
                : () async {
                    final ids = tags.map((t) => t.id).toList();
                    final id = ids.removeAt(i);
                    ids.insert(i + 1, id);
                    await context.read<AppState>().reorderTags(ids);
                  },
          ),
      ],
    );
  }
}

// ── Single tag tile ───────────────────────────────────────────────────────────
class _TagListTile extends StatelessWidget {
  final Tag tag;
  final String? groupId;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _TagListTile({
    super.key,
    required this.tag,
    required this.groupId,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();

    return ListTile(
      title: Text(tag.name),
      subtitle: tag.description.isNotEmpty
          ? Text(tag.description, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            tooltip: 'Move up',
            onPressed: onMoveUp,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 18),
            tooltip: 'Move down',
            onPressed: onMoveDown,
          ),
          _GroupPickerButton(tag: tag),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final result = await TagsScreen._promptWithDescription(
                context, 'Edit tag',
                initialName: tag.name,
                initialDescription: tag.description,
              );
              if (result == null || result.name.trim().isEmpty) return;
              final a = context.read<AppState>();
              await a.tags!.renameTag(tag.id, result.name.trim());
              await a.tags!.updateTagDescription(tag.id, result.description);
              await a.refreshAll();
            },
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final usage = await app.countTagUsage(tag.id);
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Delete tag?'),
                  content: Text('Tag will be removed from $usage items.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) {
                await context.read<AppState>().deleteTag(tag.id);
              }
            },
          ),
        ],
      ),
    );
  }
}

// ── Group picker button ───────────────────────────────────────────────────────
class _GroupPickerButton extends StatelessWidget {
  final Tag tag;
  const _GroupPickerButton({required this.tag});

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<AppState>().tagGroupList;

    return PopupMenuButton<String?>(
      tooltip: 'Move to group',
      icon: const Icon(Icons.label_outline, size: 18),
      onSelected: (groupId) async {
        await context.read<AppState>().setTagGroup(tag.id, groupId);
      },
      itemBuilder: (_) => [
        const PopupMenuItem<String?>(
          value: null,
          child: Text('Other (no group)'),
        ),
        const PopupMenuDivider(),
        for (final g in groups)
          PopupMenuItem<String?>(
            value: g.id,
            child: Row(
              children: [
                if (tag.groupId == g.id)
                  const Icon(Icons.check, size: 16)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(g.name),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Ungrouped "Other" tile ────────────────────────────────────────────────────
class _UngroupedTile extends StatelessWidget {
  final List<Tag> tags;
  const _UngroupedTile({required this.tags});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const PageStorageKey('__ungrouped__'),
      title: Text('Other', style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text('${tags.length} ungrouped tag${tags.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodySmall),
      children: [
        _TagList(groupId: null, tags: tags),
      ],
    );
  }
}


// ── New key dialog with type selection ───────────────────────────────────────
Future<({String name, String description, TagKeyType keyType})?> _promptNewKey(BuildContext context) async {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  TagKeyType selectedType = TagKeyType.chips;

  return showDialog<({String name, String description, TagKeyType keyType})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('New custom tag key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Text('Type', style: ctx.findAncestorWidgetOfExactType<AlertDialog>() != null
                ? Theme.of(ctx).textTheme.labelLarge
                : Theme.of(ctx).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<TagKeyType>(
              segments: const [
                ButtonSegment(
                  value: TagKeyType.chips,
                  icon: Icon(Icons.grid_view, size: 16),
                  label: Text('Chips'),
                ),
                ButtonSegment(
                  value: TagKeyType.search,
                  icon: Icon(Icons.search, size: 16),
                  label: Text('Searchable'),
                ),
              ],
              selected: {selectedType},
              onSelectionChanged: (v) => setState(() => selectedType = v.first),
            ),
            const SizedBox(height: 8),
            Text(
              selectedType == TagKeyType.chips
                  ? 'Predefined values shown as chips. Single pick.'
                  : 'Type to search or create values. Multi-pick.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).hintColor),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, (
              name: nameCtrl.text,
              description: descCtrl.text,
              keyType: selectedType,
            )),
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

// ──────────────────────────────────────────────
// Custom Tags (Key:Value) Tab
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
                final result = await _promptNewKey(context);
                if (result == null || result.name.trim().isEmpty) return;
                final a = context.read<AppState>();
                await a.tags!.createTagKey(
                  result.name.trim(),
                  description: result.description,
                  keyType: result.keyType,
                );
                await a.refreshAll();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add key'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ReorderableListView(
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex--;
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
                  child: Text('No keys. Add the first one above.'),
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
      subtitle: k.description.isNotEmpty
          ? Text(k.description, style: const TextStyle(fontSize: 12))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final result = await TagsScreen._promptWithDescription(
                context, 'Edit key',
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
            tooltip: 'Delete',
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final usage = await context.read<AppState>().countTagKeyUsage(k.id);
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Delete key?'),
                  content: Text('Key and all its values will be removed from $usage assignments.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
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
        Builder(
          builder: (context) {
            final values = app.valuesForKey(k.id);
            if (values.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('No values. Add the first one below.', style: TextStyle(fontSize: 12)),
              );
            }
            // Use Column + arrow buttons instead of ReorderableListView to avoid nested scroll crash
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int vi = 0; vi < values.length; vi++)
                  ListTile(
                    key: ValueKey(values[vi].id),
                    dense: true,
                    title: Text(values[vi].value),
                    subtitle: values[vi].description.isNotEmpty
                        ? Text(values[vi].description, maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          tooltip: 'Move up',
                          onPressed: vi == 0
                              ? null
                              : () async {
                                  final ids = values.map((v) => v.id).toList();
                                  final id = ids.removeAt(vi);
                                  ids.insert(vi - 1, id);
                                  await context.read<AppState>().reorderTagKeyValues(ids);
                                },
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          tooltip: 'Move down',
                          onPressed: vi == values.length - 1
                              ? null
                              : () async {
                                  final ids = values.map((v) => v.id).toList();
                                  final id = ids.removeAt(vi);
                                  ids.insert(vi + 1, id);
                                  await context.read<AppState>().reorderTagKeyValues(ids);
                                },
                        ),
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final result = await TagsScreen._promptWithDescription(
                              context, 'Edit value',
                              initialName: values[vi].value,
                              initialDescription: values[vi].description,
                            );
                            if (result == null || result.name.trim().isEmpty) return;
                            final a = context.read<AppState>();
                            await a.tags!.renameValue(values[vi].id, result.name.trim());
                            await a.tags!.updateValueDescription(values[vi].id, result.description);
                            await a.refreshAll();
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            final usage = await context.read<AppState>().countTagKeyValueUsage(values[vi].id);
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete value?'),
                                content: Text('Value will be removed from $usage items.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await context.read<AppState>().deleteTagKeyValue(values[vi].id);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Add value'),
          onTap: () async {
            final result = await TagsScreen._promptWithDescription(context, 'New value');
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

// ──────────────────────────────────────────────
// Name Order Tab
// ──────────────────────────────────────────────

class _NameOrderTab extends StatelessWidget {
  const _NameOrderTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final order = app.nameOrderList;
    final groups = { for (final g in app.tagGroupList) g.id: g };
    final keys = { for (final k in app.tagKeyList) k.id: k };

    String labelFor(NameOrderEntry e) {
      if (e.type == NameOrderEntryType.tagGroup) {
        return groups[e.id]?.name ?? '(deleted group)';
      } else {
        return keys[e.id]?.key ?? '(deleted key)';
      }
    }

    IconData iconFor(NameOrderEntry e) =>
        e.type == NameOrderEntryType.tagGroup ? Icons.label_outline : Icons.tune;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Drag to set the order tags appear in suggested filenames.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
          ),
        ),
        Expanded(
          child: order.isEmpty
              ? const Center(child: Text('No tag groups or custom keys yet.'))
              : ReorderableListView(
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex--;
                    final updated = [...order];
                    final item = updated.removeAt(oldIndex);
                    updated.insert(newIndex, item);
                    await context.read<AppState>().saveNameOrder(updated);
                  },
                  children: [
                    for (int i = 0; i < order.length; i++)
                      ListTile(
                        key: ValueKey(order[i].id),
                        leading: Icon(iconFor(order[i]), size: 18),
                        title: Text(labelFor(order[i])),
                        subtitle: Text(
                          order[i].type == NameOrderEntryType.tagGroup ? 'Simple tag group' : 'Custom tag key',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_upward, size: 18),
                              onPressed: i == 0 ? null : () async {
                                final updated = [...order];
                                final item = updated.removeAt(i);
                                updated.insert(i - 1, item);
                                await context.read<AppState>().saveNameOrder(updated);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_downward, size: 18),
                              onPressed: i == order.length - 1 ? null : () async {
                                final updated = [...order];
                                final item = updated.removeAt(i);
                                updated.insert(i + 1, item);
                                await context.read<AppState>().saveNameOrder(updated);
                              },
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: const Icon(Icons.drag_handle),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}