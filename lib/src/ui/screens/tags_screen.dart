import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';

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
                Text('Tags', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            const TabBar(
              tabs: [
                Tab(text: 'Tags'),
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
// Simple Tags Tab — groups with drag-to-reorder
// ──────────────────────────────────────────────
class _SimpleTagsTab extends StatelessWidget {
  const _SimpleTagsTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final groups = app.tagGroupList;
    final allTags = app.tagList;

    // Partition tags by group
    final ungrouped = allTags.where((t) => t.groupId == null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Drag to reorder within groups',
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
              // ── One ExpansionTile per group ──
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

              // ── "Other" catch-all for ungrouped tags ──
              if (ungrouped.isNotEmpty)
                _UngroupedTile(tags: ungrouped),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Group tile (ExpansionTile + reorderable tags inside) ──────────────────────
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
          // Expand icon handled by ExpansionTile itself
        ],
      ),
      children: [
        if (tags.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No tags in this group.', style: TextStyle(fontSize: 12)),
          )
        else
          _ReorderableTagList(groupId: group.id, tags: tags),
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

// ── Reorderable tag list within a group ───────────────────────────────────────
class _ReorderableTagList extends StatefulWidget {
  final String? groupId;
  final List<Tag> tags;

  const _ReorderableTagList({required this.groupId, required this.tags});

  @override
  State<_ReorderableTagList> createState() => _ReorderableTagListState();
}

class _ReorderableTagListState extends State<_ReorderableTagList> {
  late List<Tag> _tags;

  @override
  void initState() {
    super.initState();
    _tags = List.of(widget.tags);
  }

  @override
  void didUpdateWidget(_ReorderableTagList old) {
    super.didUpdateWidget(old);
    _tags = List.of(widget.tags);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < _tags.length; i++)
          _TagListTile(
            key: ValueKey(_tags[i].id),
            tag: _tags[i],
            index: i,
            groupId: widget.groupId,
            totalCount: _tags.length,
            onMoveUp: i == 0 ? null : () => _move(i, i - 1),
            onMoveDown: i == _tags.length - 1 ? null : () => _move(i, i + 1),
          ),
      ],
    );
  }

  void _move(int from, int to) async {
    final ids = _tags.map((t) => t.id).toList();
    final movedId = ids.removeAt(from);
    ids.insert(to, movedId);
    setState(() {
      final tag = _tags.removeAt(from);
      _tags.insert(to, tag);
    });
    await context.read<AppState>().reorderTags(ids);
  }
}

// ── Single tag list tile ──────────────────────────────────────────────────────
class _TagListTile extends StatelessWidget {
  final Tag tag;
  final int index;
  final String? groupId;
  final int totalCount;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _TagListTile({
    super.key,
    required this.tag,
    required this.index,
    required this.groupId,
    required this.totalCount,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();

    return ListTile(
      dense: true,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onMoveUp,
            tooltip: 'Move up',
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onMoveDown,
            tooltip: 'Move down',
          ),
        ],
      ),
      title: Text(tag.name),
      subtitle: tag.description.isNotEmpty
          ? Text(tag.description, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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

// ── Group picker dropdown button ──────────────────────────────────────────────
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
          PopupMenuItem<String>(
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
        _ReorderableTagList(groupId: null, tags: tags),
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
                final result = await TagsScreen._promptWithDescription(context, 'New key');
                if (result == null || result.name.trim().isEmpty) return;
                final a = context.read<AppState>();
                await a.tags!.createTagKey(result.name.trim(), description: result.description);
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
      subtitle: k.description.isNotEmpty ? Text(k.description, style: const TextStyle(fontSize: 12)) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Rename',
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
        // ── Reorderable values list ──────────────────────────────────────
        Builder(
          builder: (context) {
            final values = app.valuesForKey(k.id);
            if (values.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('No values. Add the first one below.',
                    style: TextStyle(fontSize: 12)),
              );
            }
            // Cap height so the tile doesn't overflow; grows up to 400px.
            final listHeight = (values.length * 56.0).clamp(0.0, 400.0);
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: listHeight),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: values.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex--;
                  final ids = values.map((v) => v.id).toList();
                  final movedId = ids.removeAt(oldIndex);
                  ids.insert(newIndex, movedId);
                  await context.read<AppState>().reorderTagKeyValues(ids);
                },
                itemBuilder: (ctx, vi) {
                  final v = values[vi];
                  return ListTile(
                    key: ValueKey(v.id),
                    dense: true,
                    leading: ReorderableDragStartListener(
                      index: vi,
                      child: const Icon(Icons.drag_handle, size: 18),
                    ),
                    title: Text(v.value),
                    subtitle: v.description.isNotEmpty
                        ? Text(v.description, maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Rename',
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final result = await TagsScreen._promptWithDescription(
                              context,
                              'Edit value',
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
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            final usage = await context.read<AppState>().countTagKeyValueUsage(v.id);
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
                              await context.read<AppState>().deleteTagKeyValue(v.id);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
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