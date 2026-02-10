\
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
              ListTile(
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
