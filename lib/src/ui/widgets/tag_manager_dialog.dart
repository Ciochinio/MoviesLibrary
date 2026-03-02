import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';

/// Reusable side-by-side tag picker body widget.
/// Simple tags on the left (grouped), custom (key:value) tags on the right.
/// Custom tags are single-pick per key.
class TagPickerBody extends StatelessWidget {
  final Set<String> simpleSelected;
  final Set<String> kvSelected;
  final void Function(String id, bool selected) onSimpleChanged;
  final void Function(String id, bool selected) onKvChanged;

  const TagPickerBody({
    super.key,
    required this.simpleSelected,
    required this.kvSelected,
    required this.onSimpleChanged,
    required this.onKvChanged,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final groups = app.tagGroupList;
    final allTags = app.tagList;
    final keys = app.tagKeyList;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Left: Simple Tags (grouped) ───
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Simple Tags', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Expanded(
                child: allTags.isEmpty
                    ? const Text('No tags. Create them in the Tags tab.')
                    : SingleChildScrollView(
                        child: _GroupedSimpleTagPicker(
                          groups: groups,
                          allTags: allTags,
                          selected: simpleSelected,
                          onChanged: onSimpleChanged,
                        ),
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 24),
        // ─── Right: Custom Tags (key:value) — single pick per key ───
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Custom Tags', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Expanded(
                child: keys.isEmpty
                    ? const Text('No custom tags. Create them in the Tags tab.')
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final k in keys) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 4),
                                child: Text(
                                  k.key,
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              _SinglePickKeyValues(
                                keyId: k.id,
                                values: app.valuesForKey(k.id),
                                kvSelected: kvSelected,
                                onKvChanged: onKvChanged,
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Grouped simple tag chips — groups rendered as headers with their chips,
/// ungrouped tags at the bottom under "Other".
class _GroupedSimpleTagPicker extends StatelessWidget {
  final List<TagGroup> groups;
  final List<Tag> allTags;
  final Set<String> selected;
  final void Function(String id, bool selected) onChanged;

  const _GroupedSimpleTagPicker({
    required this.groups,
    required this.allTags,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ungrouped = allTags.where((t) => t.groupId == null).toList();
    final hasAnyGroupedTags = groups.any((g) => allTags.any((t) => t.groupId == g.id));

    final children = <Widget>[];

    for (final g in groups) {
      final groupTags = allTags.where((t) => t.groupId == g.id).toList();
      if (groupTags.isEmpty) continue;

      children.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          g.name,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ));
      children.add(Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in groupTags)
            FilterChip(
              label: Text(t.name),
              tooltip: t.description.isNotEmpty ? t.description : null,
              selected: selected.contains(t.id),
              showCheckmark: false,
              onSelected: (v) => onChanged(t.id, v),
            ),
        ],
      ));
    }

    if (ungrouped.isNotEmpty) {
      if (hasAnyGroupedTags) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            'Other',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ));
      }
      children.add(Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in ungrouped)
            FilterChip(
              label: Text(t.name),
              tooltip: t.description.isNotEmpty ? t.description : null,
              selected: selected.contains(t.id),
              showCheckmark: false,
              onSelected: (v) => onChanged(t.id, v),
            ),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// Single-pick chip group for values within one key.
class _SinglePickKeyValues extends StatelessWidget {
  final String keyId;
  final List<TagKeyValue> values;
  final Set<String> kvSelected;
  final void Function(String id, bool selected) onKvChanged;

  const _SinglePickKeyValues({
    required this.keyId,
    required this.values,
    required this.kvSelected,
    required this.onKvChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final v in values)
          FilterChip(
            label: Text(v.value),
            selected: kvSelected.contains(v.id),
            showCheckmark: false,
            onSelected: (sel) {
              if (sel) {
                for (final other in values) {
                  if (other.id != v.id && kvSelected.contains(other.id)) {
                    onKvChanged(other.id, false);
                  }
                }
              }
              onKvChanged(v.id, sel);
            },
          ),
      ],
    );
  }
}

/// Calculates the appropriate dialog size based on tag/group content.
/// Grows to fit content, clamped between min and 85% of screen height.
Size _calculateDialogSize(BuildContext context, AppState app) {
  const double chipHeight = 36;
  const double chipSpacing = 6;
  const double groupHeaderHeight = 28;
  const double sectionTitleHeight = 32;
  const double padding = 48;
  const double minWidth = 600;
  const double maxWidth = 900;
  const double minHeight = 300;

  final screenHeight = MediaQuery.of(context).size.height;
  final maxHeight = screenHeight * 0.85;

  // ── Left column: simple tags ──
  double leftHeight = sectionTitleHeight;
  final groups = app.tagGroupList;
  final allTags = app.tagList;

  for (final g in groups) {
    final groupTags = allTags.where((t) => t.groupId == g.id).toList();
    if (groupTags.isEmpty) continue;
    leftHeight += groupHeaderHeight;
    // Estimate chip rows (assume ~3 chips per row on average)
    final rows = (groupTags.length / 3).ceil();
    leftHeight += rows * (chipHeight + chipSpacing);
    leftHeight += 8; // spacing between groups
  }

  final ungrouped = allTags.where((t) => t.groupId == null).toList();
  if (ungrouped.isNotEmpty) {
    if (groups.isNotEmpty) leftHeight += groupHeaderHeight;
    final rows = (ungrouped.length / 3).ceil();
    leftHeight += rows * (chipHeight + chipSpacing);
  }

  // ── Right column: custom tags ──
  double rightHeight = sectionTitleHeight;
  for (final k in app.tagKeyList) {
    rightHeight += groupHeaderHeight;
    final values = app.valuesForKey(k.id);
    final rows = (values.length / 3).ceil().clamp(1, 100);
    rightHeight += rows * (chipHeight + chipSpacing) + 8;
  }

  final contentHeight = [leftHeight, rightHeight].reduce((a, b) => a > b ? a : b);
  final dialogHeight = (contentHeight + padding).clamp(minHeight, maxHeight);

  // Width grows slightly if there are many groups/keys
  final totalSections = groups.length + app.tagKeyList.length;
  final dialogWidth = totalSections > 8
      ? maxWidth
      : totalSections > 4
          ? 760.0
          : minWidth;

  return Size(dialogWidth, dialogHeight);
}

/// Dialog to manage both kinds of tags for a single item.
Future<({Set<String> simpleTagIds, Set<String> keyValueIds})?> showTagManagerDialog(
  BuildContext context, {
  required Set<String> initialSimpleTagIds,
  required Set<String> initialKeyValueIds,
}) async {
  final simpleSelected = initialSimpleTagIds.toSet();
  final kvSelected = initialKeyValueIds.toSet();

  return showDialog<({Set<String> simpleTagIds, Set<String> keyValueIds})>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          final app = ctx.watch<AppState>();
          final size = _calculateDialogSize(ctx, app);

          return AlertDialog(
            title: const Text('Tags'),
            content: SizedBox(
              width: size.width,
              height: size.height,
              child: TagPickerBody(
                simpleSelected: simpleSelected,
                kvSelected: kvSelected,
                onSimpleChanged: (id, v) => setState(() {
                  if (v) { simpleSelected.add(id); } else { simpleSelected.remove(id); }
                }),
                onKvChanged: (id, v) => setState(() {
                  if (v) { kvSelected.add(id); } else { kvSelected.remove(id); }
                }),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () => setState(() { simpleSelected.clear(); kvSelected.clear(); }),
                child: const Text('Clear'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, (simpleTagIds: simpleSelected, keyValueIds: kvSelected)),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

String formatKeyValueChip(TagKeyValue kv) => '${kv.key}:${kv.value}';