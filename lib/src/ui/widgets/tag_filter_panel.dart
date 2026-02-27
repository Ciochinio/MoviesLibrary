import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';

/// Side panel for filtering by tags (Letterboxd-style)
/// Shows Custom Tags (grouped by key) and Simple Tags with search
class TagFilterPanel extends StatefulWidget {
  final Set<String> selectedSimpleTags;
  final Set<String> selectedKeyValues;
  final void Function(int minMatch) onApply;
  final VoidCallback onClear;
  final VoidCallback onClose;

  const TagFilterPanel({
    super.key,
    required this.selectedSimpleTags,
    required this.selectedKeyValues,
    required this.onApply,
    required this.onClear,
    required this.onClose,
  });

  @override
  State<TagFilterPanel> createState() => _TagFilterPanelState();
}

class _TagFilterPanelState extends State<TagFilterPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _minMatch = 0; // 0 = "all" sentinel

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Tag> _filterSimpleTags(List<Tag> tags) {
    if (_searchQuery.isEmpty) return tags;
    final query = _searchQuery.toLowerCase();
    return tags.where((t) => t.name.toLowerCase().contains(query)).toList();
  }

  List<TagKey> _filterTagKeys(List<TagKey> keys) {
    if (_searchQuery.isEmpty) return keys;
    final query = _searchQuery.toLowerCase();
    return keys.where((k) => k.key.toLowerCase().contains(query)).toList();
  }

  List<TagKeyValue> _filterTagValues(List<TagKeyValue> values) {
    if (_searchQuery.isEmpty) return values;
    final query = _searchQuery.toLowerCase();
    return values.where((v) => v.value.toLowerCase().contains(query) || v.key.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          left: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Filter by Tags',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          // Search box
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search tags...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),

          // Tags list (scrollable)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Custom Tags section
                if (app.tagKeyList.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Custom Tags',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ..._filterTagKeys(app.tagKeyList).map((key) {
                    final values = _filterTagValues(app.valuesForKey(key.id));
                    if (values.isEmpty && _searchQuery.isNotEmpty) {
                      return const SizedBox.shrink();
                    }

                    return ExpansionTile(
                      title: Text(key.key),
                      initiallyExpanded: _searchQuery.isNotEmpty,
                      children: [
                        if (values.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No values', style: TextStyle(fontStyle: FontStyle.italic)),
                          )
                        else
                          ...values.map((v) => CheckboxListTile(
                                dense: true,
                                value: widget.selectedKeyValues.contains(v.id),
                                title: Text(v.value),
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      widget.selectedKeyValues.add(v.id);
                                    } else {
                                      widget.selectedKeyValues.remove(v.id);
                                    }
                                  });
                                },
                              )),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                ],

                // Simple Tags section
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Simple Tags',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (app.tagList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No tags. Add some in Tags screen.', style: TextStyle(fontStyle: FontStyle.italic)),
                  )
                else
                  ..._filterSimpleTags(app.tagList).map((tag) => CheckboxListTile(
                        dense: true,
                        value: widget.selectedSimpleTags.contains(tag.id),
                        title: Text(tag.name),
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              widget.selectedSimpleTags.add(tag.id);
                            } else {
                              widget.selectedSimpleTags.remove(tag.id);
                            }
                          });
                        },
                      )),
              ],
            ),
          ),

          // Bottom actions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Selected: ${widget.selectedSimpleTags.length} tags, ${widget.selectedKeyValues.length} custom',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                // Min-match stepper — only show when 2+ tags selected
                Builder(builder: (ctx) {
                  final total = widget.selectedSimpleTags.length + widget.selectedKeyValues.length;
                  if (total < 2) return const SizedBox(height: 8);
                  // Clamp _minMatch to valid range
                  final effective = _minMatch == 0 ? total : _minMatch.clamp(1, total);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Min match:', style: Theme.of(ctx).textTheme.bodySmall),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.remove, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: effective > 1
                              ? () => setState(() => _minMatch = effective - 1)
                              : null,
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '$effective / $total',
                            textAlign: TextAlign.center,
                            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: effective < total
                              ? () => setState(() => _minMatch = effective + 1)
                              : null,
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: (widget.selectedSimpleTags.isEmpty && widget.selectedKeyValues.isEmpty)
                            ? null
                            : () {
                                setState(() => _minMatch = 0);
                                widget.onClear();
                              },
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: (widget.selectedSimpleTags.isEmpty && widget.selectedKeyValues.isEmpty)
                            ? null
                            : () {
                                final total = widget.selectedSimpleTags.length + widget.selectedKeyValues.length;
                                final effective = _minMatch == 0 ? total : _minMatch.clamp(1, total);
                                widget.onApply(effective);
                              },
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
