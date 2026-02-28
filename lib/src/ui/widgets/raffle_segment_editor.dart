import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import 'tag_manager_dialog.dart';

/// Result returned when the user saves a segment.
class RaffleSegmentEditResult {
  final String label;
  final Set<String> simpleTagIds;
  final Set<String> keyValueIds;
  final List<RaffleSegmentCategory> categories;

  RaffleSegmentEditResult({
    required this.label,
    required this.simpleTagIds,
    required this.keyValueIds,
    required this.categories,
  });
}

/// Shows a dialog for creating or editing a raffle segment.
/// Returns null if cancelled.
Future<RaffleSegmentEditResult?> showRaffleSegmentEditor(
  BuildContext context, {
  String? initialLabel,
  Set<String>? initialSimpleTagIds,
  Set<String>? initialKeyValueIds,
  List<RaffleSegmentCategory>? initialCategories,
}) async {
  return showDialog<RaffleSegmentEditResult>(
    context: context,
    builder: (ctx) => _RaffleSegmentEditorDialog(
      initialLabel: initialLabel ?? '',
      initialSimpleTagIds: initialSimpleTagIds ?? {},
      initialKeyValueIds: initialKeyValueIds ?? {},
      initialCategories: initialCategories ?? [],
    ),
  );
}

class _RaffleSegmentEditorDialog extends StatefulWidget {
  final String initialLabel;
  final Set<String> initialSimpleTagIds;
  final Set<String> initialKeyValueIds;
  final List<RaffleSegmentCategory> initialCategories;

  const _RaffleSegmentEditorDialog({
    required this.initialLabel,
    required this.initialSimpleTagIds,
    required this.initialKeyValueIds,
    required this.initialCategories,
  });

  @override
  State<_RaffleSegmentEditorDialog> createState() =>
      _RaffleSegmentEditorDialogState();
}

class _RaffleSegmentEditorDialogState
    extends State<_RaffleSegmentEditorDialog> {
  late final TextEditingController _labelController;
  late final Set<String> _simpleTagIds;
  late final Set<String> _kvIds;
  late final List<RaffleSegmentCategory> _categories;

  // Track expanded state for category picker section
  bool _categoryExpanded = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.initialLabel);
    _labelController.addListener(() => setState(() {}));
    _simpleTagIds = widget.initialSimpleTagIds.toSet();
    _kvIds = widget.initialKeyValueIds.toSet();
    _categories = List.from(widget.initialCategories);
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  bool get _isValid => _labelController.text.trim().isNotEmpty;

  void _save() {
    if (!_isValid) return;
    Navigator.pop(
      context,
      RaffleSegmentEditResult(
        label: _labelController.text.trim(),
        simpleTagIds: _simpleTagIds,
        keyValueIds: _kvIds,
        categories: _categories,
      ),
    );
  }

  void _toggleCategory(String categoryId, String? subcategoryId) {
    setState(() {
      final existing = _categories.indexWhere(
        (c) => c.categoryId == categoryId && c.subcategoryId == subcategoryId,
      );
      if (existing >= 0) {
        _categories.removeAt(existing);
      } else {
        _categories.add(RaffleSegmentCategory(
          categoryId: categoryId,
          subcategoryId: subcategoryId,
        ));
      }
    });
  }

  bool _isCategorySelected(String categoryId, String? subcategoryId) {
    return _categories.any(
      (c) => c.categoryId == categoryId && c.subcategoryId == subcategoryId,
    );
  }

  String _summaryText() {
    final parts = <String>[];
    if (_simpleTagIds.isNotEmpty) parts.add('${_simpleTagIds.length} tag(s)');
    if (_kvIds.isNotEmpty) parts.add('${_kvIds.length} custom tag(s)');
    if (_categories.isNotEmpty) parts.add('${_categories.length} category filter(s)');
    if (parts.isEmpty) return 'No filters — segment will match nothing';
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.initialLabel.isEmpty ? 'New Segment' : 'Edit Segment'),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Label ──
            TextField(
              controller: _labelController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Segment name',
                hintText: 'e.g. Friday Action Night',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),

            // ── Filter summary ──
            Text(
              _summaryText(),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // ── Tag filters (reuse TagPickerBody) ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Tag Filters', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TagPickerBody(
                      simpleSelected: _simpleTagIds,
                      kvSelected: _kvIds,
                      onSimpleChanged: (id, v) => setState(() {
                        if (v) {
                          _simpleTagIds.add(id);
                        } else {
                          _simpleTagIds.remove(id);
                        }
                      }),
                      onKvChanged: (id, v) => setState(() {
                        if (v) {
                          _kvIds.add(id);
                        } else {
                          _kvIds.remove(id);
                        }
                      }),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(),

            // ── Category filters (collapsible) ──
            InkWell(
              onTap: () => setState(() => _categoryExpanded = !_categoryExpanded),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _categoryExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Category Filters (optional)',
                      style: theme.textTheme.titleSmall,
                    ),
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
                        // Whole category toggle
                        CheckboxListTile(
                          dense: true,
                          title: Text(
                            cat.name,
                            style: theme.textTheme.titleSmall,
                          ),
                          value: _isCategorySelected(cat.id, null),
                          onChanged: (_) =>
                              _toggleCategory(cat.id, null),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        // Individual subcategory toggles
                        for (final sub in app.subcategoriesFor(cat.id))
                          Padding(
                            padding: const EdgeInsets.only(left: 24),
                            child: CheckboxListTile(
                              dense: true,
                              title: Text(
                                sub.name,
                                style: theme.textTheme.bodyMedium,
                              ),
                              value: _isCategorySelected(cat.id, sub.id),
                              onChanged: (_) =>
                                  _toggleCategory(cat.id, sub.id),
                              controlAffinity:
                                  ListTileControlAffinity.leading,
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _simpleTagIds.clear();
            _kvIds.clear();
            _categories.clear();
          }),
          child: const Text('Clear filters'),
        ),
        FilledButton(
          onPressed: _isValid ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}