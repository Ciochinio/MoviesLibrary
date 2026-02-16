import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';

class TagsScreen extends StatelessWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

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
            Expanded(
              child: TabBarView(
                children: [
                  _SimpleTagsTab(app: app),
                  _KeyValueTagsTab(app: app),
                ],
              ),
            ),
          ],
        ),
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

class _SimpleTagsTab extends StatelessWidget {
  final AppState app;
  const _SimpleTagsTab({required this.app});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Spacer(),
            FilledButton.icon(
              onPressed: () async {
                final name = await TagsScreen._prompt(context, 'Nowy tag');
                if (name == null || name.trim().isEmpty) return;
                await context.read<AppState>().createTag(name.trim());
              },
              icon: const Icon(Icons.add),
              label: const Text('Dodaj'),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
                        final name = await TagsScreen._prompt(context, 'Nowa nazwa', initial: t.name);
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
    );
  }
}

class _KeyValueTagsTab extends StatelessWidget {
  final AppState app;
  const _KeyValueTagsTab({required this.app});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Spacer(),
            FilledButton.icon(
              onPressed: () async {
                final key = await TagsScreen._prompt(context, 'Nowy klucz');
                if (key == null || key.trim().isEmpty) return;
                await context.read<AppState>().createTagKey(key.trim());
              },
              icon: const Icon(Icons.add),
              label: const Text('Dodaj klucz'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              for (final k in app.tagKeyList)
                ExpansionTile(
                  title: Text(k.key),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Zmień nazwę',
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final name = await TagsScreen._prompt(context, 'Nowa nazwa klucza', initial: k.key);
                          if (name == null || name.trim().isEmpty) return;
                          await context.read<AppState>().renameTagKey(k.id, name.trim());
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Zmień nazwę',
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                final name = await TagsScreen._prompt(context, 'Nowa wartość', initial: v.value);
                                if (name == null || name.trim().isEmpty) return;
                                await context.read<AppState>().renameTagKeyValue(v.id, name.trim());
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
                        final value = await TagsScreen._prompt(context, 'Nowa wartość');
                        if (value == null || value.trim().isEmpty) return;
                        await context.read<AppState>().createTagKeyValue(k.id, value.trim());
                      },
                    ),
                  ],
                ),
              if (app.tagKeyList.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Brak kluczy. Dodaj pierwszy klucz przyciskiem powyżej.'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
