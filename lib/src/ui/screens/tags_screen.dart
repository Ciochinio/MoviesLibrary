import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';

class TagsScreen extends StatelessWidget {
  const TagsScreen({super.key});

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
              Text('Tagi', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  final name = await _prompt(context, 'Nowy tag');
                  if (name == null || name.trim().isEmpty) return;
                  await context.read<AppState>().createTag(name.trim());
                },
                icon: const Icon(Icons.add),
                label: const Text('Dodaj'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: app.tagList.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final t = app.tagList[i];
                return ListTile(
                  title: Text(t.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Zmień nazwę',
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final name = await _prompt(context, 'Nowa nazwa', initial: t.name);
                          if (name == null || name.trim().isEmpty) return;
                          await context.read<AppState>().renameTag(t.id, name.trim());
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
