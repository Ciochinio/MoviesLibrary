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
import 'screens/favourites_screen.dart';
import 'screens/raffle_screen.dart';
import 'widgets/import_overlay_panel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Nav item definitions — order here is the display order in the rail.
// 'key' is what gets stored in hiddenNavItems.
// always = true means the item cannot be hidden.
// ─────────────────────────────────────────────────────────────────────────────

class _NavItem {
  final String key;
  final IconData icon;
  final String label;
  final Widget page;
  final bool always;

  const _NavItem({
    required this.key,
    required this.icon,
    required this.label,
    required this.page,
    this.always = false,
  });
}

const _allNavItems = [
  _NavItem(key: 'library',    icon: Icons.video_library, label: 'Library',    page: LibraryScreen(),    always: true),
  _NavItem(key: 'favourites', icon: Icons.favorite,      label: 'Favourites', page: FavouritesScreen()),
  _NavItem(key: 'raffle',     icon: Icons.casino,        label: 'Raffle',     page: RaffleScreen()),
  _NavItem(key: 'search',     icon: Icons.search,        label: 'Search',     page: SearchScreen()),
  _NavItem(key: 'notes',      icon: Icons.note_alt,      label: 'Notes',      page: NotesScreen()),
  _NavItem(key: 'tags',       icon: Icons.sell,          label: 'Tags',       page: TagsScreen()),
  _NavItem(key: 'categories', icon: Icons.folder,        label: 'Categories', page: CategoriesScreen()),
  _NavItem(key: 'settings',   icon: Icons.settings,      label: 'Settings',   page: SettingsScreen(),   always: true),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Active key rather than index — survives items being hidden/shown.
  String _activeKey = 'library';
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

    _importController ??= ImportController(app);

    // Build the visible items list — always-visible items are never filtered.
    final hidden = app.settings.hiddenNavItems;
    final visible = _allNavItems
        .where((item) => item.always || !hidden.contains(item.key))
        .toList();

    // If the active key is no longer visible, fall back to library.
    if (!visible.any((item) => item.key == _activeKey)) {
      _activeKey = 'library';
    }

    final railIndex = visible.indexWhere((item) => item.key == _activeKey);
    final activePage = visible.firstWhere((item) => item.key == _activeKey).page;

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
                  selectedIndex: railIndex,
                  onDestinationSelected: (v) =>
                      setState(() => _activeKey = visible[v].key),
                  labelType: NavigationRailLabelType.none,
                  destinations: [
                    for (final item in visible)
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        label: Text(item.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: activePage),
              ],
            ),
            const ImportOverlayPanel(),
          ],
        ),
      ),
    );
  }
}