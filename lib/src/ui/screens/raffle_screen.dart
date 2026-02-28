import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import 'wheel_screen.dart';
import 'quick_roll_screen.dart';

class RaffleScreen extends StatefulWidget {
  const RaffleScreen({super.key});

  @override
  State<RaffleScreen> createState() => _RaffleScreenState();
}

class _RaffleScreenState extends State<RaffleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.isReady) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.casino, size: 18), text: 'Wheel of Fortune'),
            Tab(icon: Icon(Icons.shuffle, size: 18), text: 'Quick Roll'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _WheelTab(),
              QuickRollScreen(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Wheel tab (was previously the entire RaffleScreen) ───────────────────────

class _WheelTab extends StatefulWidget {
  const _WheelTab();

  @override
  State<_WheelTab> createState() => _WheelTabState();
}

class _WheelTabState extends State<_WheelTab> {
  List<RafflePlaylist> _playlists = [];
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (!app.isReady) return;
    setState(() => _loading = true);
    final playlists = await app.raffle!.listPlaylists();
    if (mounted) setState(() { _playlists = playlists; _loading = false; });
  }

  Future<void> _createPlaylist() async {
    final name = await _promptName(context, title: 'New Playlist', hint: 'e.g. Weekend Watchlist');
    if (name == null || !mounted) return;
    final app = context.read<AppState>();
    final playlist = await app.raffle!.createPlaylist(name);
    await _load();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WheelScreen(playlist: playlist)),
    );
    await _load();
  }

  Future<void> _generatePlaylist() async {
    final app = context.read<AppState>();
    if (!app.isReady) return;

    // Load categories with counts
    final categories = await app.raffle!.listCategoriesWithCounts();
    if (!mounted) return;

    // Show category picker dialog
    final result = await showDialog<({String name, List<String> categoryIds, bool mixMode, int segmentCount, int categoriesPerSegment})>(
      context: context,
      builder: (ctx) => _GenerateDialog(categories: categories),
    );
    if (result == null || !mounted) return;

    final RafflePlaylist playlist;
    if (result.mixMode) {
      playlist = await app.raffle!.generateMixed(
        playlistName: result.name,
        categoryIds: result.categoryIds,
        segmentCount: result.segmentCount,
        categoriesPerSegment: result.categoriesPerSegment,
      );
    } else {
      playlist = await app.raffle!.generateFromSubcategories(
        playlistName: result.name,
        categoryIds: result.categoryIds,
      );
    }
    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Playlist generated!')),
    );

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WheelScreen(playlist: playlist)),
    );
    await _load();
  }

  Future<void> _renamePlaylist(RafflePlaylist playlist) async {
    final name = await _promptName(context,
        title: 'Rename Playlist', hint: playlist.name, initial: playlist.name);
    if (name == null || !mounted) return;
    final app = context.read<AppState>();
    await app.raffle!.renamePlaylist(playlist.id, name);
    await _load();
  }

  Future<void> _deletePlaylist(RafflePlaylist playlist) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text('"${playlist.name}" and all its segments will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final app = context.read<AppState>();
    await app.raffle!.deletePlaylist(playlist.id);
    await _load();
  }

  Future<void> _openPlaylist(RafflePlaylist playlist) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WheelScreen(playlist: playlist)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              Text('Playlists', style: theme.textTheme.titleMedium),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _generatePlaylist,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Generate'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _createPlaylist,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Playlist'),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _playlists.isEmpty
                  ? _buildEmpty(context)
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (ctx, i) {
                        final playlist = _playlists[i];
                        return _PlaylistCard(
                          playlist: playlist,
                          onTap: () => _openPlaylist(playlist),
                          onRename: () => _renamePlaylist(playlist),
                          onDelete: () => _deletePlaylist(playlist),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.casino_outlined, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text('No playlists yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Create a playlist, add segments with tag filters,\nthen spin the wheel to pick what to watch.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _generatePlaylist,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Generate from Library'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _createPlaylist,
                icon: const Icon(Icons.add),
                label: const Text('New Playlist'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Playlist card ─────────────────────────────────────────────────────────────

class _PlaylistCard extends StatelessWidget {
  final RafflePlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.casino, color: cs.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(playlist.name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text('Updated ${_formatDate(playlist.updatedAt)}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.outline),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                tooltip: 'Options',
                onSelected: (v) {
                  if (v == 'rename') onRename();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─── Shared name prompt ───────────────────────────────────────────────────────

Future<String?> _promptName(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.pop(ctx, v);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

// ─── Generate from Library dialog ─────────────────────────────────────────────────────

class _GenerateDialog extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  const _GenerateDialog({required this.categories});

  @override
  State<_GenerateDialog> createState() => _GenerateDialogState();
}

class _GenerateDialogState extends State<_GenerateDialog> {
  late final TextEditingController _nameController;
  late final Set<String> _selectedCategoryIds;
  bool _mixMode = false;
  int _segmentCount = 8;
  int _categoriesPerSegment = 2;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'My Wheel');
    _nameController.addListener(() => setState(() {}));
    _selectedCategoryIds = widget.categories
        .map((c) => c['categoryId'] as String)
        .toSet();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Qualifying subcategories from selected categories
  List<Map<String, dynamic>> get _qualifyingSubcategories {
    final result = <Map<String, dynamic>>[];
    for (final cat in widget.categories) {
      if (!_selectedCategoryIds.contains(cat['categoryId'] as String)) continue;
      final subs = cat['subcategories'] as List<Map<String, dynamic>>;
      result.addAll(subs.where((s) => (s['itemCount'] as int) >= 2));
    }
    return result;
  }

  int get _totalSingleSegments => _qualifyingSubcategories.length;

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      _selectedCategoryIds.isNotEmpty &&
      (_mixMode ? _qualifyingSubcategories.length >= _categoriesPerSegment : _totalSingleSegments > 0);

  void _save() {
    if (!_isValid) return;
    Navigator.pop(context, (
      name: _nameController.text.trim(),
      categoryIds: _selectedCategoryIds.toList(),
      mixMode: _mixMode,
      segmentCount: _segmentCount,
      categoriesPerSegment: _categoriesPerSegment,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final qualifying = _qualifyingSubcategories;

    return AlertDialog(
      title: const Text('Generate Wheel from Library'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Playlist name'),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 20),

              // Mode toggle
              Text('Segment mode', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      selected: !_mixMode,
                      icon: Icons.grid_view,
                      title: 'Single',
                      subtitle: 'One segment per subcategory',
                      onTap: () => setState(() => _mixMode = false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ModeCard(
                      selected: _mixMode,
                      icon: Icons.shuffle,
                      title: 'Mixed',
                      subtitle: 'Randomly combine subcategories',
                      onTap: () => setState(() => _mixMode = true),
                    ),
                  ),
                ],
              ),

              // Mix controls
              if (_mixMode) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Segments to generate', style: theme.textTheme.labelMedium),
                          const SizedBox(height: 4),
                          _StepperRow(
                            value: _segmentCount,
                            min: 2,
                            max: 30,
                            onChanged: (v) => setState(() => _segmentCount = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Mix per segment', style: theme.textTheme.labelMedium),
                          const SizedBox(height: 4),
                          _StepperRow(
                            value: _categoriesPerSegment,
                            min: 2,
                            max: qualifying.length.clamp(2, 6),
                            onChanged: (v) => setState(() => _categoriesPerSegment = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 20),

              // Category checklist
              Text('Include categories:', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...widget.categories.map((cat) {
                final catId = cat['categoryId'] as String;
                final catName = cat['categoryName'] as String;
                final subs = cat['subcategories'] as List<Map<String, dynamic>>;
                final qualifyingCount = subs.where((s) => (s['itemCount'] as int) >= 2).length;
                final isSelected = _selectedCategoryIds.contains(catId);

                return CheckboxListTile(
                  dense: true,
                  value: isSelected,
                  onChanged: qualifyingCount == 0
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              _selectedCategoryIds.add(catId);
                            } else {
                              _selectedCategoryIds.remove(catId);
                            }
                          }),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(catName, style: theme.textTheme.bodyMedium),
                  subtitle: qualifyingCount == 0
                      ? Text('No qualifying subcategories',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.outline))
                      : Text(
                          '$qualifyingCount subcategor${qualifyingCount == 1 ? 'y' : 'ies'} available',
                          style: theme.textTheme.bodySmall,
                        ),
                );
              }),

              const SizedBox(height: 16),

              // Summary box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.primary.withOpacity(0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _buildSummary(qualifying),
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _isValid ? _save : null,
          child: const Text('Generate'),
        ),
      ],
    );
  }

  String _buildSummary(List<Map<String, dynamic>> qualifying) {
    if (qualifying.isEmpty) return 'No qualifying subcategories. Select categories with at least 2 files.';
    if (_mixMode) {
      if (qualifying.length < _categoriesPerSegment) {
        return 'Not enough subcategories to mix — need at least $_categoriesPerSegment, found ${qualifying.length}.';
      }
      return '$_segmentCount mixed segments will be created, each combining $_categoriesPerSegment randomly picked subcategories from ${qualifying.length} available.\nSubcategories with fewer than 2 files are skipped.';
    } else {
      return '${qualifying.length} segment${qualifying.length == 1 ? '' : 's'} will be created (one per subcategory).\nSubcategories with fewer than 2 files are skipped.';
    }
  }
}

// ─── Mode card ────────────────────────────────────────────────────────────────

class _ModeCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withOpacity(0.3),
            width: selected ? 2 : 1,
          ),
          color: selected ? cs.primary.withOpacity(0.08) : cs.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: selected ? cs.primary : cs.onSurface),
            const SizedBox(height: 6),
            Text(title,
                style: theme.textTheme.titleSmall?.copyWith(
                    color: selected ? cs.primary : cs.onSurface)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// ─── Stepper row ──────────────────────────────────────────────────────────────

class _StepperRow extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final void Function(int) onChanged;

  const _StepperRow({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove, size: 16),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          style: IconButton.styleFrom(
              minimumSize: const Size(28, 28), padding: EdgeInsets.zero),
        ),
        SizedBox(
          width: 32,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 16),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          style: IconButton.styleFrom(
              minimumSize: const Size(28, 28), padding: EdgeInsets.zero),
        ),
      ],
    );
  }
}