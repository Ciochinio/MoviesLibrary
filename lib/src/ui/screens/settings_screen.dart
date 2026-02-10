import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lib = app.paths?.libraryDir.path ?? '(brak)';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ustawienia', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Ścieżka biblioteki (Library)'),
              subtitle: Text(lib),
              trailing: FilledButton.icon(
                onPressed: () async {
                  await context.read<AppState>().promptAndCreateOrOpenLibrary();
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Zmień'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Portable tip:\n'
            '• Skopiuj build aplikacji do /App\n'
            '• Utwórz /Library obok /App\n'
            '• Uruchom aplikację z /App — automatycznie wykryje /Library\n',
          ),
        ],
      ),
    );
  }
}
