import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';

/// Reusable side-by-side tag picker body widget.
/// Simple tags on the left, custom (key:value) tags on the right.
/// Both displayed as FilterChip Wraps.
/// Custom tags are single-pick per key (selecting a new value deselects the old one).
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
    final tags = app.tagList;
    final keys = app.tagKeyList;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Left: Simple Tags ───
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Simple Tags', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Expanded(
                child: tags.isEmpty
                    ? const Text('No tags. Create them in the Tags tab.')
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final t in tags)
                              FilterChip(
                                label: Text(t.name),
                                tooltip: t.description.isNotEmpty ? t.description : null,
                                selected: simpleSelected.contains(t.id),
                                onSelected: (v) => onSimpleChanged(t.id, v),
                              ),
                          ],
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

/// Single-pick chip group for values within one key.
/// Selecting a value deselects any other value in the same key.
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
            onSelected: (sel) {
              if (sel) {
                // Deselect any other value in the same key first
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
          return AlertDialog(
            title: const Text('Tagi'),
            content: SizedBox(
              width: 900,
              height: 545,
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
              TextButton(
                onPressed: () => setState(() { simpleSelected.clear(); kvSelected.clear(); }),
                child: const Text('Wyczyść'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, (simpleTagIds: simpleSelected, keyValueIds: kvSelected)),
                child: const Text('Zapisz'),
              ),
            ],
          );
        },
      );
    },
  );
}

String formatKeyValueChip(TagKeyValue kv) => '${kv.key}:${kv.value}';
