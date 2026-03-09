import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/app_settings.dart';
import '../../core/models.dart';

/// A simple toggleable chip that avoids Flutter's mouse_tracker assertion bug
/// which occurs when FilterChip rebuilds inside GridView during mouse events.
class _TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chip = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withOpacity(0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? cs.onPrimary : cs.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.visible,
          softWrap: true,
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: chip);
    }
    return chip;
  }
}

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
    final simpleCols = app.settings.tagDialogSimpleCols;
    final customCols = app.settings.tagDialogCustomCols;

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
              allTags.isEmpty
                    ? const Text('No tags. Create them in the Tags tab.')
                    : _GroupedSimpleTagPicker(
                          groups: groups,
                          allTags: allTags,
                          selected: simpleSelected,
                          onChanged: onSimpleChanged,
                          cols: simpleCols,
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
              keys.isEmpty
                    ? const Text('No custom tags. Create them in the Tags tab.')
                    : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final k in keys) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 6, bottom: 2),
                                child: Row(
                                  children: [
                                    Text(
                                      k.key,
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (k.keyType == TagKeyType.search) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Theme.of(context).colorScheme.outline),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          'search',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            color: Theme.of(context).colorScheme.outline,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (k.keyType == TagKeyType.search)
                                _SearchKeyPicker(
                                  tagKey: k,
                                  allValues: app.valuesForKey(k.id),
                                  kvSelected: kvSelected,
                                  onKvChanged: onKvChanged,
                                  onCreateValue: (keyId, value) async {
                                    final a = context.read<AppState>();
                                    await a.tags!.createValue(keyId, value);
                                    await a.refreshAll();
                                  },
                                )
                              else
                                _SinglePickKeyValues(
                                  keyId: k.id,
                                  values: app.valuesForKey(k.id),
                                  kvSelected: kvSelected,
                                  onKvChanged: onKvChanged,
                                  cols: customCols,
                                ),
                            ],
                          ],
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
  final int cols;

  const _GroupedSimpleTagPicker({
    required this.groups,
    required this.allTags,
    required this.selected,
    required this.onChanged,
    required this.cols,
  });

  @override
  Widget build(BuildContext context) {
    final ungrouped = allTags.where((t) => t.groupId == null).toList();
    final hasAnyGroupedTags = groups.any((g) => allTags.any((t) => t.groupId == g.id));

    final children = <Widget>[];

    Widget chipGrid(List<Tag> tags) => Wrap(
      spacing: 0,
      runSpacing: 4,
      children: [
        for (final t in tags)
          FractionallySizedBox(
            widthFactor: 1 / cols,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _TagChip(
                label: t.name,
                selected: selected.contains(t.id),
                tooltip: t.description.isNotEmpty ? t.description : null,
                onTap: () => onChanged(t.id, !selected.contains(t.id)),
              ),
            ),
          ),
      ],
    );

    for (final g in groups) {
      final groupTags = allTags.where((t) => t.groupId == g.id).toList();
      if (groupTags.isEmpty) continue;
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(g.name, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
      ));
      children.add(chipGrid(groupTags));
    }

    if (ungrouped.isNotEmpty) {
      if (hasAnyGroupedTags) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text('Other', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
        ));
      }
      children.add(chipGrid(ungrouped));
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
  final int cols;

  const _SinglePickKeyValues({
    required this.keyId,
    required this.values,
    required this.kvSelected,
    required this.onKvChanged,
    required this.cols,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 0,
      runSpacing: 4,
      children: [
        for (final v in values)
          FractionallySizedBox(
            widthFactor: 1 / cols,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _TagChip(
                label: v.value,
                selected: kvSelected.contains(v.id),
                onTap: () {
                  if (!kvSelected.contains(v.id)) {
                    for (final other in values) {
                      if (other.id != v.id && kvSelected.contains(other.id)) {
                        onKvChanged(other.id, false);
                      }
                    }
                    onKvChanged(v.id, true);
                  } else {
                    onKvChanged(v.id, false);
                  }
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Searchable multi-pick picker for a search-type key.
// Sentinel value used to represent the "Create new" option in the Autocomplete list.
const _kCreateSentinel = '__create__';

class _SearchKeyPicker extends StatefulWidget {
  final TagKey tagKey;
  final List<TagKeyValue> allValues;
  final Set<String> kvSelected;
  final void Function(String id, bool selected) onKvChanged;
  final Future<void> Function(String keyId, String value) onCreateValue;

  const _SearchKeyPicker({
    required this.tagKey,
    required this.allValues,
    required this.kvSelected,
    required this.onKvChanged,
    required this.onCreateValue,
  });

  @override
  State<_SearchKeyPicker> createState() => _SearchKeyPickerState();
}

class _SearchKeyPickerState extends State<_SearchKeyPicker> {
  String _query = '';

  @override
  void dispose() {
    super.dispose();
  }

  bool get _hasExactMatch => widget.allValues
      .any((v) => v.value.toLowerCase() == _query.toLowerCase().trim());

  // Returns option strings for Autocomplete: matching unselected values + optional sentinel.
  Iterable<String> _optionsFor(TextEditingValue tv) {
    final q = tv.text.trim().toLowerCase();
    if (q.isEmpty) return [];
    final matches = widget.allValues
        .where((v) => !widget.kvSelected.contains(v.id))
        .where((v) => v.value.toLowerCase().contains(q))
        .map((v) => v.value)
        .take(8)
        .toList();
    final exact = widget.allValues.any((v) => v.value.toLowerCase() == q);
    if (!exact) matches.add(_kCreateSentinel);
    return matches;
  }

  Future<void> _onSelected(String option) async {
    if (option == _kCreateSentinel) {
      final val = _query.trim();
      if (val.isEmpty) return;
      await widget.onCreateValue(widget.tagKey.id, val);
      // allValues will update via refreshAll → setState from parent
    } else {
      final match = widget.allValues.firstWhere((v) => v.value == option);
      widget.onKvChanged(match.id, true);
    }
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.allValues
        .where((v) => widget.kvSelected.contains(v.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Autocomplete<String>(
          optionsBuilder: _optionsFor,
          onSelected: _onSelected,
          fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) {
            return TextFormField(
              controller: ctrl,
              focusNode: focusNode,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search or add...',
                hintStyle: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              onChanged: (v) => setState(() => _query = v),
            );
          },
          optionsViewBuilder: (ctx, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160, maxWidth: 300),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: options.map((option) {
                      if (option == _kCreateSentinel) {
                        return InkWell(
                          onTap: () => onSelected(option),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 14, color: Theme.of(ctx).colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Create "${_query.trim()}"',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: Theme.of(ctx).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      // Highlight matching portion
                      final q = _query.toLowerCase();
                      final lower = option.toLowerCase();
                      final idx = lower.indexOf(q);
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          child: idx == -1
                              ? Text(option, style: const TextStyle(fontSize: 12))
                              : RichText(
                                  text: TextSpan(
                                    style: TextStyle(fontSize: 12, color: Theme.of(ctx).textTheme.bodyMedium?.color),
                                    children: [
                                      TextSpan(text: option.substring(0, idx)),
                                      TextSpan(
                                        text: option.substring(idx, idx + q.length),
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.primary),
                                      ),
                                      TextSpan(text: option.substring(idx + q.length)),
                                    ],
                                  ),
                                ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            );
          },
        ),
        if (selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                for (final v in selected)
                  Chip(
                    label: Text(v.value, style: const TextStyle(fontSize: 11)),
                    deleteIcon: const Icon(Icons.close, size: 12),
                    onDeleted: () => widget.onKvChanged(v.id, false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  ),
              ],
            ),
          ),
      ],
    );
  }
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
          ctx.watch<AppState>(); // rebuild on tag changes

          return AlertDialog(
            title: const Text('Tags'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 600,
                maxWidth: 900,
                maxHeight: MediaQuery.of(ctx).size.height * 0.82,
              ),
              child: IntrinsicHeight(
                child: SingleChildScrollView(
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