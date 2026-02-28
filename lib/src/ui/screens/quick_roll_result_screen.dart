import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/library_folders.dart';
import '../../core/models.dart';
import '../widgets/shared_player_panel.dart';
import '../widgets/tag_manager_dialog.dart';
import '../widgets/raffle_media_grid.dart';

class QuickRollResultScreen extends StatefulWidget {
  final String presetName;
  final List<MediaItem> items;
  final int totalMatched;
  final VoidCallback onRollAgain;

  const QuickRollResultScreen({
    super.key,
    required this.presetName,
    required this.items,
    required this.totalMatched,
    required this.onRollAgain,
  });

  @override
  State<QuickRollResultScreen> createState() => _QuickRollResultScreenState();
}

class _QuickRollResultScreenState extends State<QuickRollResultScreen>
    with TickerProviderStateMixin {
  MediaItem? _selected;
  double _panelWidth = kPanelNormal;
  Set<String> _untaggedIds = {};

  late List<AnimationController> _animControllers;
  late List<Animation<double>> _fadeAnims;
  late List<Animation<Offset>> _slideAnims;

  @override
  void initState() {
    super.initState();
    _buildAnimations();
    _startAnimations();
  }

  void _buildAnimations() {
    _animControllers = List.generate(
      widget.items.length,
      (_) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 350)),
    );
    _fadeAnims = _animControllers
        .map((c) => Tween<double>(begin: 0.0, end: 1.0)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeOut)))
        .toList();
    _slideAnims = _animControllers
        .map((c) => Tween<Offset>(
                  begin: const Offset(0, 0.15), end: Offset.zero)
              .animate(CurvedAnimation(parent: c, curve: Curves.easeOut)))
        .toList();
  }

  Future<void> _startAnimations() async {
    for (int i = 0; i < _animControllers.length; i++) {
      await Future.delayed(Duration(milliseconds: 40 * i));
      if (mounted) _animControllers[i].forward();
    }
  }

  @override
  void dispose() {
    for (final c in _animControllers) { c.dispose(); }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadUntagged();
  }

  Future<void> _loadUntagged() async {
    final app = context.read<AppState>();
    if (!app.isReady || widget.items.isEmpty) return;
    final ids = await app.items!
        .listUntaggedItemIds(widget.items.map((e) => e.id).toList());
    if (mounted) setState(() => _untaggedIds = ids);
  }

  Future<void> _showTags(MediaItem item) async {
    final app = context.read<AppState>();
    final curSimple = await app.items!.listTagIdsForItem(item.id);
    final curKv = await app.items!.listKeyValueIdsForItem(item.id);
    final picked = await showTagManagerDialog(context,
        initialSimpleTagIds: curSimple, initialKeyValueIds: curKv);
    if (picked == null || !mounted) return;
    await app.setTagsForItem(
        itemId: item.id,
        simpleTagIds: picked.simpleTagIds,
        keyValueIds: picked.keyValueIds);
    await _loadUntagged();
  }

  Future<void> _exportItem(MediaItem item) async {
    final app = context.read<AppState>();
    final dir =
        await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select directory');
    if (dir == null) return;
    final src =
        File(LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath));
    if (!await src.exists()) return;
    final dest = _uniquePath(p.join(dir, item.originalName));
    await src.copy(dest);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Exported.')));
  }

  String _uniquePath(String basePath) {
    if (!File(basePath).existsSync()) return basePath;
    final dir = p.dirname(basePath);
    final name = p.basenameWithoutExtension(basePath);
    final ext = p.extension(basePath);
    var i = 1;
    while (true) {
      final cand = p.join(dir, '$name ($i)$ext');
      if (!File(cand).existsSync()) return cand;
      i++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final showingCount = widget.items.length;
    final isPartial = showingCount < widget.totalMatched;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.shuffle, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(widget.presetName, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
            Text(
              isPartial
                  ? '$showingCount of ${widget.totalMatched} matches'
                  : '$showingCount item${showingCount == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            onPressed: widget.onRollAgain,
            icon: const Icon(Icons.shuffle, size: 16),
            label: const Text('Roll Again'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: widget.items.isEmpty
          ? _buildEmpty(context)
          : Column(
              children: [
                // Warning banner if pool was smaller than sample size
                if (!isPartial && widget.totalMatched < 10)
                  Material(
                    color: cs.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: cs.onTertiaryContainer),
                          const SizedBox(width: 8),
                          Text(
                            'Only ${widget.totalMatched} item${widget.totalMatched == 1 ? '' : 's'} matched your filters.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onTertiaryContainer),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: RaffleMediaGrid(
                          items: widget.items,
                          selected: _selected,
                          untaggedIds: _untaggedIds,
                          onSelect: (item) => setState(() => _selected = item),
                          animationWrapper: (i, child) => FadeTransition(
                            opacity: i < _fadeAnims.length
                                ? _fadeAnims[i]
                                : const AlwaysStoppedAnimation(1.0),
                            child: SlideTransition(
                              position: i < _slideAnims.length
                                  ? _slideAnims[i]
                                  : const AlwaysStoppedAnimation(Offset.zero),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                      if (_selected != null && app.isReady) ...[
                        const VerticalDivider(width: 1),
                        GestureDetector(
                          onHorizontalDragUpdate: (d) => setState(() {
                            _panelWidth = (_panelWidth - d.delta.dx)
                                .clamp(220.0, 600.0);
                          }),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child:
                                Container(width: 4, color: Colors.transparent),
                          ),
                        ),
                        SizedBox(
                          width: _panelWidth,
                          child: SharedPlayerPanel(
                            key: ValueKey(_selected!.id),
                            item: _selected!,
                            libraryFilesDir: app.paths!.filesDir,
                            thumbsDir: app.paths!.thumbsDir,
                            allItems: widget.items,
                            onTheatreChanged: (w) =>
                                setState(() => _panelWidth = w),
                            onOpen: () async {
                              final abs = LibraryFolders.absPath(
                                  app.paths!.filesDir,
                                  _selected!.storedRelPath);
                              await OpenFilex.open(abs);
                            },
                            onExport: () => _exportItem(_selected!),
                            onTags: () => _showTags(_selected!),
                            onDelete: () async {
                              final confirm = app.settings.confirmDelete
                                  ? await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete item?'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Cancel')),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('Delete')),
                                        ],
                                      ),
                                    )
                                  : true;
                              if (confirm != true || !mounted) return;
                              await app.deleteOneItem(_selected!);
                              setState(() => _selected = null);
                            },
                            loadTags: () =>
                                app.items!.listTagsForItem(_selected!.id),
                            loadKeyValues: () =>
                                app.items!.listKeyValuesForItem(_selected!.id),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: cs.outline),
          const SizedBox(height: 16),
          const Text('No items matched your filters.'),
          const SizedBox(height: 8),
          Text('Try removing some filters or increasing your library.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: widget.onRollAgain,
            icon: const Icon(Icons.shuffle),
            label: const Text('Roll Again'),
          ),
        ],
      ),
    );
  }
}