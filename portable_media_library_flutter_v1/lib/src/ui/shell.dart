\
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import 'screens/library_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/tags_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (!app.isReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('Portable Media Library')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Nie wykryto biblioteki (/Library).'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await context.read<AppState>().promptAndCreateOrOpenLibrary();
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Wybierz/Utwórz Library'),
              ),
              const SizedBox(height: 8),
              const Text('Tip: w trybie portable utwórz folder "Library" obok "/App".'),
            ],
          ),
        ),
      );
    }

    final pages = [
      const LibraryScreen(),
      const NotesScreen(),
      const TagsScreen(),
      const CategoriesScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portable Media Library'),
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (v) => setState(() => index = v),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.video_library), label: Text('Biblioteka')),
              NavigationRailDestination(icon: Icon(Icons.note_alt), label: Text('Notatki')),
              NavigationRailDestination(icon: Icon(Icons.sell), label: Text('Tagi')),
              NavigationRailDestination(icon: Icon(Icons.folder), label: Text('Kategorie')),
              NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Ustawienia')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[index]),
        ],
      ),
    );
  }
}
