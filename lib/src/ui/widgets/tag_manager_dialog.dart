import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';

/// Dialog to manage both kinds of tags for a single item:
/// - simple tags (value)
/// - keyed tags (key:value)
///
/// Uses layout B: keyed tags are grouped as ExpansionTiles (key -> values).
Future<({Set<String> simpleTagIds, Set<String> keyValueIds})?> showTagManagerDialog(
  BuildContext context, {
  required Set<String> initialSimpleTagIds,
  required Set<String> initialKeyValueIds,
}) async {
  final app = context.read<AppState>();
  final simpleSelected = initialSimpleTagIds.toSet();
  final kvSelected = initialKeyValueIds.toSet();

  return showDialog<({Set<String> simpleTagIds, Set<String> keyValueIds})>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          final tags = app.tagList;
          final keys = app.tagKeyList;

          return AlertDialog(
            title: const Text('Tagi'),
            content: SizedBox(
              width: 560,
              height: 560,
              child: ListView(
                children: [
                  Text('Tagi', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (tags.isEmpty)
                    const Text('Brak tagów. Dodaj je w zakładce „Tagi”.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in tags)
                          FilterChip(
                            label: Text(t.name),
                            selected: simpleSelected.contains(t.id),
                            onSelected: (v) => setState(() {
                              if (v) {
                                simpleSelected.add(t.id);
                              } else {
                                simpleSelected.remove(t.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Text('Key:Value', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (keys.isEmpty)
                    const Text('Brak kluczy. Dodaj je w zakładce „Tagi” → „Key:Value”.')
                  else
                    ...keys.map((k) {
                      final values = app.valuesForKey(k.id);
                      return ExpansionTile(
                        title: Text(k.key),
                        children: [
                          if (values.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Text('Brak wartości. Dodaj je w zakładce „Tagi”.'),
                            ),
                          for (final v in values)
                            CheckboxListTile(
                              value: kvSelected.contains(v.id),
                              title: Text(v.value),
                              onChanged: (checked) => setState(() {
                                if (checked == true) {
                                  kvSelected.add(v.id);
                                } else {
                                  kvSelected.remove(v.id);
                                }
                              }),
                            ),
                        ],
                      );
                    }).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
              TextButton(
                onPressed: () => setState(() {
                  simpleSelected.clear();
                  kvSelected.clear();
                }),
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
