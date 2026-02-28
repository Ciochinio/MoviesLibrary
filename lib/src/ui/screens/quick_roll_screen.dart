import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../widgets/raffle_segment_editor.dart';
import '../widgets/tag_manager_dialog.dart';
import 'quick_roll_result_screen.dart';

class QuickRollScreen extends StatefulWidget {
  const QuickRollScreen({super.key});

  @override
  State<QuickRollScreen> createState() => _QuickRollScreenState();
}

class _QuickRollScreenState extends State<QuickRollScreen> {
  List<QuickRollPreset> _presets = [];
  bool _loading = true;
  bool _rolling = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (!app.isReady) return;
    setState(() => _loading = true);
    final presets = await app.quickRoll!.listPresets();
    if (mounted) setState(() { _presets = presets; _loading = false; });
  }

  Future<void> _createPreset() async {
    final result = await _showPresetEditor(context);
    if (result == null || !mounted) return;
    final app = context.read<AppState>();
    await app.quickRoll!.createPreset(
      name: result.name,
      sampleSize: result.sampleSize,
      simpleTagIds: result.simpleTagIds.toList(),
      keyValueIds: result.keyValueIds.toList(),
      categories: result.categories,
    );
    await _load();
  }

  Future<void> _editPreset(QuickRollPreset preset) async {
    final result = await _showPresetEditor(context, existing: preset);
    if (result == null || !mounted) return;
    final app = context.read<AppState>();
    await app.quickRoll!.updatePreset(
      id: preset.id,
      name: result.name,
      sampleSize: result.sampleSize,
      simpleTagIds: result.simpleTagIds.toList(),
      keyValueIds: result.keyValueIds.toList(),
      categories: result.categories,
    );
    await _load();
  }

  Future<void> _deletePreset(QuickRollPreset preset) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete preset?'),
        content: Text('"${preset.name}" will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final app = context.read<AppState>();
    await app.quickRoll!.deletePreset(preset.id);
    await _load();
  }

  Future<void> _roll(QuickRollPreset preset) async {
    if (_rolling) return;
    setState(() => _rolling = true);
    final app = context.read<AppState>();
    final result = await app.quickRoll!.roll(preset);
    if (!mounted) return;
    setState(() => _rolling = false);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickRollResultScreen(
          presetName: preset.name,
          items: result.items,
          totalMatched: result.totalMatched,
          onRollAgain: () {
            Navigator.pop(context);
            _roll(preset);
          },
        ),
      ),
    );
  }

  Future<void> _rollRandom([int? existingSampleSize]) async {
    if (_rolling) return;

    int sampleSize;
    if (existingSampleSize != null) {
      // Roll Again — skip dialog, reuse same size
      sampleSize = existingSampleSize;
    } else {
      final confirmed = await showDialog<int>(
        context: context,
        builder: (ctx) {
          int localSize = 10;
          return StatefulBuilder(
            builder: (ctx, setSt) => AlertDialog(
              title: const Text('Random Roll'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Pick a random selection from your entire library.'),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('How many items?'),
                      const SizedBox(width: 16),
                      _Stepper(
                        value: localSize,
                        min: 1,
                        max: 50,
                        onChanged: (v) => setSt(() => localSize = v),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, localSize), child: const Text('Roll')),
              ],
            ),
          );
        },
      );
      if (confirmed == null || !mounted) return;
      sampleSize = confirmed;
    }

    setState(() => _rolling = true);
    final app = context.read<AppState>();
    final result = await app.quickRoll!.rollRandom(sampleSize);
    if (!mounted) return;
    setState(() => _rolling = false);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickRollResultScreen(
          presetName: 'Random Roll',
          items: result.items,
          totalMatched: result.totalMatched,
          onRollAgain: () {
            Navigator.pop(context);
            _rollRandom(sampleSize);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!app.isReady) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              const Icon(Icons.shuffle, size: 22),
              const SizedBox(width: 10),
              Text('Quick Roll', style: theme.textTheme.titleLarge),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _rolling ? null : _rollRandom,
                icon: _rolling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.casino_outlined, size: 16),
                label: const Text('Random Roll'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _createPreset,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Preset'),
              ),
            ],
          ),
        ),
        const Divider(),

        // ── Body ──
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _presets.isEmpty
                  ? _buildEmpty(context)
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _presets.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (ctx, i) {
                        final preset = _presets[i];
                        return _PresetCard(
                          preset: preset,
                          rolling: _rolling,
                          onRoll: () => _roll(preset),
                          onEdit: () => _editPreset(preset),
                          onDelete: () => _deletePreset(preset),
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
          Icon(Icons.shuffle, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text('No presets yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Create a preset with tag filters and a sample size,\nor use Random Roll to pull from your whole library.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _rollRandom,
                icon: const Icon(Icons.casino_outlined, size: 16),
                label: const Text('Random Roll'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _createPreset,
                icon: const Icon(Icons.add),
                label: const Text('Create Preset'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Preset card ───────────────────────────────────────────────────────────────

class _PresetCard extends StatelessWidget {
  final QuickRollPreset preset;
  final bool rolling;
  final VoidCallback onRoll;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PresetCard({
    required this.preset,
    required this.rolling,
    required this.onRoll,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final app = context.watch<AppState>();

    final filterSummary = _buildFilterSummary(app);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.secondary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.shuffle, color: cs.secondary, size: 20),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(preset.name, style: theme.textTheme.titleSmall),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${preset.sampleSize} items',
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    filterSummary,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Roll button
            FilledButton.icon(
              onPressed: rolling ? null : onRoll,
              icon: rolling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.shuffle, size: 16),
              label: const Text('Roll'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(80, 34),
              ),
            ),

            // Options menu
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              tooltip: 'Options',
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildFilterSummary(AppState app) {
    if (preset.simpleTagIds.isEmpty &&
        preset.keyValueIds.isEmpty &&
        preset.categories.isEmpty) {
      return 'No filters — rolls from entire library';
    }
    final parts = <String>[];
    if (preset.simpleTagIds.isNotEmpty) {
      final names = preset.simpleTagIds
          .map((id) => app.tagList
              .firstWhere((t) => t.id == id, orElse: () => Tag(id: id, name: '?'))
              .name)
          .take(3)
          .join(', ');
      parts.add(names + (preset.simpleTagIds.length > 3 ? '…' : ''));
    }
    if (preset.keyValueIds.isNotEmpty) {
      parts.add('${preset.keyValueIds.length} custom tag(s)');
    }
    if (preset.categories.isNotEmpty) {
      parts.add('${preset.categories.length} category filter(s)');
    }
    return parts.join(' · ');
  }
}

// ─── Stepper widget ────────────────────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final void Function(int) onChanged;

  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove, size: 16),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          style: IconButton.styleFrom(
            minimumSize: const Size(28, 28),
            padding: EdgeInsets.zero,
          ),
        ),
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 16),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          style: IconButton.styleFrom(
            minimumSize: const Size(28, 28),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

// ─── Preset editor dialog ──────────────────────────────────────────────────────

class _PresetEditorResult {
  final String name;
  final int sampleSize;
  final Set<String> simpleTagIds;
  final Set<String> keyValueIds;
  final List<RaffleSegmentCategory> categories;

  _PresetEditorResult({
    required this.name,
    required this.sampleSize,
    required this.simpleTagIds,
    required this.keyValueIds,
    required this.categories,
  });
}

Future<_PresetEditorResult?> _showPresetEditor(
  BuildContext context, {
  QuickRollPreset? existing,
}) async {
  return showDialog<_PresetEditorResult>(
    context: context,
    builder: (ctx) => _PresetEditorDialog(existing: existing),
  );
}

class _PresetEditorDialog extends StatefulWidget {
  final QuickRollPreset? existing;
  const _PresetEditorDialog({this.existing});

  @override
  State<_PresetEditorDialog> createState() => _PresetEditorDialogState();
}

class _PresetEditorDialogState extends State<_PresetEditorDialog> {
  late final TextEditingController _nameController;
  late int _sampleSize;
  late final Set<String> _simpleTagIds;
  late final Set<String> _kvIds;
  late final List<RaffleSegmentCategory> _categories;
  bool _categoryExpanded = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _nameController.addListener(() => setState(() {}));
    _sampleSize = widget.existing?.sampleSize ?? 10;
    _simpleTagIds = widget.existing?.simpleTagIds.toSet() ?? {};
    _kvIds = widget.existing?.keyValueIds.toSet() ?? {};
    _categories = List.from(widget.existing?.categories ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isValid => _nameController.text.trim().isNotEmpty;

  void _save() {
    if (!_isValid) return;
    Navigator.pop(
      context,
      _PresetEditorResult(
        name: _nameController.text.trim(),
        sampleSize: _sampleSize,
        simpleTagIds: _simpleTagIds,
        keyValueIds: _kvIds,
        categories: _categories,
      ),
    );
  }

  void _toggleCategory(String categoryId, String? subcategoryId) {
    setState(() {
      final idx = _categories.indexWhere(
          (c) => c.categoryId == categoryId && c.subcategoryId == subcategoryId);
      if (idx >= 0) {
        _categories.removeAt(idx);
      } else {
        _categories.add(RaffleSegmentCategory(
            categoryId: categoryId, subcategoryId: subcategoryId));
      }
    });
  }

  bool _isCategorySelected(String categoryId, String? subcategoryId) =>
      _categories.any(
          (c) => c.categoryId == categoryId && c.subcategoryId == subcategoryId);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.existing == null ? 'New Preset' : 'Edit Preset'),
      content: SizedBox(
        width: 760,
        height: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Name + sample size row ──
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Preset name'),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sample size', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 4),
                    _Stepper(
                      value: _sampleSize,
                      min: 1,
                      max: 50,
                      onChanged: (v) => setState(() => _sampleSize = v),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Tag filters ──
            Text('Tag Filters', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(
              child: TagPickerBody(
                simpleSelected: _simpleTagIds,
                kvSelected: _kvIds,
                onSimpleChanged: (id, v) => setState(() {
                  if (v) { _simpleTagIds.add(id); } else { _simpleTagIds.remove(id); }
                }),
                onKvChanged: (id, v) => setState(() {
                  if (v) { _kvIds.add(id); } else { _kvIds.remove(id); }
                }),
              ),
            ),

            const SizedBox(height: 12),
            const Divider(),

            // ── Category filters ──
            InkWell(
              onTap: () => setState(() => _categoryExpanded = !_categoryExpanded),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(_categoryExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
                    const SizedBox(width: 6),
                    Text('Category Filters (optional)', style: theme.textTheme.titleSmall),
                    const SizedBox(width: 8),
                    if (_categories.isNotEmpty)
                      Chip(
                        label: Text('${_categories.length} selected'),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
            if (_categoryExpanded)
              SizedBox(
                height: 160,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final cat in app.categoryList) ...[
                        CheckboxListTile(
                          dense: true,
                          title: Text(cat.name, style: theme.textTheme.titleSmall),
                          value: _isCategorySelected(cat.id, null),
                          onChanged: (_) => _toggleCategory(cat.id, null),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        for (final sub in app.subcategoriesFor(cat.id))
                          Padding(
                            padding: const EdgeInsets.only(left: 24),
                            child: CheckboxListTile(
                              dense: true,
                              title: Text(sub.name, style: theme.textTheme.bodyMedium),
                              value: _isCategorySelected(cat.id, sub.id),
                              onChanged: (_) => _toggleCategory(cat.id, sub.id),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => setState(() {
            _simpleTagIds.clear();
            _kvIds.clear();
            _categories.clear();
          }),
          child: const Text('Clear filters'),
        ),
        FilledButton(onPressed: _isValid ? _save : null, child: const Text('Save')),
      ],
    );
  }
}