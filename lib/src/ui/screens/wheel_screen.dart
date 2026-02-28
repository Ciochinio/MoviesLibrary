import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../widgets/tag_manager_dialog.dart';
import 'raffle_result_screen.dart';
import '../widgets/wheel_painter.dart';
import '../widgets/raffle_segment_editor.dart';

class WheelScreen extends StatefulWidget {
  final RafflePlaylist playlist;

  const WheelScreen({super.key, required this.playlist});

  @override
  State<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends State<WheelScreen>
    with TickerProviderStateMixin {
  List<RaffleSegment> _segments = [];
  bool _loading = true;
  bool _spinning = false;
  String? _error;

  late AnimationController _spinController;
  late Animation<double> _spinAnimation;
  double _currentAngle = 0.0;
  int? _winnnerIndex;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );
    _spinAnimation = _spinController;
    _loadSegments();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _loadSegments() async {
    final app = context.read<AppState>();
    if (!app.isReady) return;
    setState(() => _loading = true);
    final segs = await app.raffle!.listSegments(widget.playlist.id);
    if (mounted) setState(() { _segments = segs; _loading = false; });
  }

  Future<void> _spin() async {
    if (_segments.isEmpty || _spinning) return;

    final app = context.read<AppState>();
    setState(() { _spinning = true; _error = null; _winnnerIndex = null; });

    // Pre-check which segments have items (skip empty ones)
    final validSegments = <({RaffleSegment segment, List<MediaItem> items})>[];
    for (final seg in _segments) {
      final items = await app.raffle!.querySegmentItems(seg);
      if (items.isNotEmpty) validSegments.add((segment: seg, items: items));
    }

    if (validSegments.isEmpty) {
      setState(() { _spinning = false; _error = 'All segments are empty — no items matched any filters.'; });
      return;
    }

    // Pick winner
    final rng = Random();
    final winner = validSegments[rng.nextInt(validSegments.length)];

    // Find the visual index of the winning segment in full segments list
    final winnerVisualIndex = _segments.indexWhere((s) => s.id == winner.segment.id);

    // Calculate target angle so the winner segment aligns with the pointer (top)
    final segmentAngle = (2 * pi) / _segments.length;
    final segmentMidAngle = segmentAngle * winnerVisualIndex + segmentAngle / 2;
    // We want segmentMidAngle to align at the top (0), so we rotate by -segmentMidAngle
    // Add multiple full rotations for dramatic effect (5-8 full spins)
    final spins = 5 + rng.nextInt(3);
    final targetAngle = _currentAngle - segmentMidAngle - _currentAngle.remainder(2 * pi) + spins * 2 * pi;

    _spinAnimation = Tween<double>(
      begin: _currentAngle,
      end: targetAngle,
    ).animate(CurvedAnimation(
      parent: _spinController,
      curve: Curves.easeInOutCubic,
    ));

    _spinController.reset();
    await _spinController.forward();

    _currentAngle = targetAngle;

    if (!mounted) return;
    setState(() => _spinning = false);

    // Navigate to results
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RaffleResultScreen(
          segmentLabel: winner.segment.label,
          items: winner.items,
          onSpinAgain: () {
            Navigator.pop(context);
            _spin();
          },
        ),
      ),
    );
  }

  Future<void> _addSegment() async {
    final result = await showRaffleSegmentEditor(context);
    if (result == null || !mounted) return;

    final app = context.read<AppState>();
    await app.raffle!.createSegment(
      playlistId: widget.playlist.id,
      label: result.label,
      simpleTagIds: result.simpleTagIds.toList(),
      keyValueIds: result.keyValueIds.toList(),
      categories: result.categories,
    );
    await _loadSegments();
  }

  Future<void> _editSegment(RaffleSegment segment) async {
    final result = await showRaffleSegmentEditor(
      context,
      initialLabel: segment.label,
      initialSimpleTagIds: segment.simpleTagIds.toSet(),
      initialKeyValueIds: segment.keyValueIds.toSet(),
      initialCategories: segment.categories,
    );
    if (result == null || !mounted) return;

    final app = context.read<AppState>();
    await app.raffle!.updateSegment(
      segmentId: segment.id,
      playlistId: segment.playlistId,
      label: result.label,
      simpleTagIds: result.simpleTagIds.toList(),
      keyValueIds: result.keyValueIds.toList(),
      categories: result.categories,
    );
    await _loadSegments();
  }

  Future<void> _deleteSegment(RaffleSegment segment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete segment?'),
        content: Text('"${segment.label}" will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final app = context.read<AppState>();
    await app.raffle!.deleteSegment(segment.id, segment.playlistId);
    await _loadSegments();
  }

  String _segmentSubtitle(RaffleSegment seg) {
    final app = context.read<AppState>();
    final parts = <String>[];

    if (seg.simpleTagIds.isNotEmpty) {
      final names = seg.simpleTagIds
          .map((id) => app.tagList.firstWhere((t) => t.id == id, orElse: () => Tag(id: id, name: '?')).name)
          .take(3)
          .join(', ');
      parts.add(names + (seg.simpleTagIds.length > 3 ? '…' : ''));
    }

    if (seg.keyValueIds.isNotEmpty) {
      final names = seg.keyValueIds
          .map((id) {
            for (final key in app.tagKeyList) {
              final vals = app.valuesForKey(key.id);
              final match = vals.where((v) => v.id == id).cast<TagKeyValue?>().firstOrNull;
              if (match != null) return '${key.key}:${match.value}';
            }
            return '?';
          })
          .take(2)
          .join(', ');
      parts.add(names + (seg.keyValueIds.length > 2 ? '…' : ''));
    }

    if (seg.categories.isNotEmpty) {
      parts.add('${seg.categories.length} category filter(s)');
    }

    return parts.isEmpty ? 'No filters configured' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add segment',
            onPressed: _addSegment,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // ── Left: segments list ──
                SizedBox(
                  width: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text('Segments', style: theme.textTheme.titleMedium),
                      ),
                      if (_segments.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No segments yet.\nAdd one with the + button.',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      else
                        Expanded(
                          child: ReorderableListView.builder(
                            itemCount: _segments.length,
                            onReorder: (oldIndex, newIndex) async {
                              if (newIndex > oldIndex) newIndex--;
                              final updated = List<RaffleSegment>.from(_segments);
                              final item = updated.removeAt(oldIndex);
                              updated.insert(newIndex, item);
                              setState(() => _segments = updated);
                              final app = context.read<AppState>();
                              await app.raffle!.reorderSegments(
                                widget.playlist.id,
                                updated.map((s) => s.id).toList(),
                              );
                            },
                            itemBuilder: (ctx, i) {
                              final seg = _segments[i];
                              return ListTile(
                                key: ValueKey(seg.id),
                                title: Text(seg.label),
                                subtitle: Text(
                                  _segmentSubtitle(seg),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                leading: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: _segmentColor(i),
                                  child: Text(
                                    (i + 1).toString(),
                                    style: const TextStyle(fontSize: 10, color: Colors.white),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 16),
                                      tooltip: 'Edit',
                                      onPressed: () => _editSegment(seg),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 16),
                                      tooltip: 'Delete',
                                      onPressed: () => _deleteSegment(seg),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: OutlinedButton.icon(
                          onPressed: _addSegment,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Segment'),
                        ),
                      ),
                    ],
                  ),
                ),

                const VerticalDivider(width: 1),

                // ── Right: wheel + spin button ──
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _error!,
                            style: TextStyle(color: cs.error),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      // Wheel
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: _segments.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.casino_outlined,
                                          size: 64, color: cs.outline),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Add segments to spin the wheel',
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                )
                              : Stack(
                                  alignment: Alignment.topCenter,
                                  children: [
                                    // Pointer triangle at top
                                    Positioned(
                                      top: 0,
                                      child: CustomPaint(
                                        size: const Size(24, 20),
                                        painter: WheelPointerPainter(
                                          color: cs.primary,
                                        ),
                                      ),
                                    ),
                                    // Wheel
                                    Padding(
                                      padding: const EdgeInsets.only(top: 16),
                                      child: AnimatedBuilder(
                                        animation: _spinAnimation,
                                        builder: (_, __) => AspectRatio(
                                          aspectRatio: 1,
                                          child: CustomPaint(
                                            painter: WheelPainter(
                                              labels: _segments
                                                  .map((s) => s.label)
                                                  .toList(),
                                              rotationAngle: _spinAnimation.value,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      // Spin button
                      Padding(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: FilledButton.icon(
                          onPressed: (_spinning || _segments.isEmpty) ? null : _spin,
                          icon: _spinning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.casino),
                          label: Text(_spinning ? 'Spinning…' : 'Spin the Wheel'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(200, 48),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Color _segmentColor(int index) {
    const colors = [
      Color(0xFF7C3AED),
      Color(0xFF9D5CF6),
      Color(0xFF5B21B6),
      Color(0xFFBB8AF8),
      Color(0xFF4C1D95),
      Color(0xFF6D28D9),
    ];
    return colors[index % colors.length];
  }
}
