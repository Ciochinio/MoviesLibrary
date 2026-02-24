import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/import_controller.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/tags_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/import_overlay_panel.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  ImportController? _importController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (app.isReady && _importController == null) {
      _importController = ImportController(app);
    }
  }

  @override
  void dispose() {
    _importController?.dispose();
    super.dispose();
  }

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
              const Text('No library detected (/Library).'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await context.read<AppState>().promptAndCreateOrOpenLibrary();
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Select/Create Library'),
              ),
              const SizedBox(height: 8),
              const Text('Tip: in portable mode, create a "Library" folder next to "/App".'),
            ],
          ),
        ),
      );
    }

    // Ensure controller is created when app becomes ready
    _importController ??= ImportController(app);

    final pages = [
      const LibraryScreen(),
      const SearchScreen(),
      const NotesScreen(),
      const TagsScreen(),
      const CategoriesScreen(),
      const SettingsScreen(),
    ];

    return ChangeNotifierProvider<ImportController>.value(
      value: _importController!,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Portable Media Library'),
        ),
        body: Stack(
          children: [
            Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (v) => setState(() => index = v),
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.video_library), label: Text('Library')),
                    NavigationRailDestination(icon: Icon(Icons.search), label: Text('Search')),
                    NavigationRailDestination(icon: Icon(Icons.note_alt), label: Text('Notes')),
                    NavigationRailDestination(icon: Icon(Icons.sell), label: Text('Tags')),
                    NavigationRailDestination(icon: Icon(Icons.folder), label: Text('Categories')),
                    NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Settings')),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages[index]),
              ],
            ),
            // ─── Import overlay (docked bottom-right) ───
            const ImportOverlayPanel(),
          ],
        ),
      ),
    );
  }
}
