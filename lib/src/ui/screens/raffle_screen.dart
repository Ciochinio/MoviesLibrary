import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import 'wheel_screen.dart';

class RaffleScreen extends StatefulWidget {
  const RaffleScreen({super.key});

  @override
  State<RaffleScreen> createState() => _RaffleScreenState();
}

class _RaffleScreenState extends State<RaffleScreen> {
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
    // Open wheel screen immediately after creation
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WheelScreen(playlist: playlist)),
    );
    await _load();
  }

  Future<void> _renamePlaylist(RafflePlaylist playlist) async {
    final name = await _promptName(
      context,
      title: 'Rename Playlist',
      hint: playlist.name,
      initial: playlist.name,
    );
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
        content: Text(
          '"${playlist.name}" and all its segments will be permanently deleted.',
        ),
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
              const Icon(Icons.casino, size: 22),
              const SizedBox(width: 10),
              Text('Wheel of Fortune', style: theme.textTheme.titleLarge),
              const Spacer(),
              FilledButton.icon(
                onPressed: _createPlaylist,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Playlist'),
              ),
            ],
          ),
        ),
        const Divider(),

        // ── Body ──
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
          FilledButton.icon(
            onPressed: _createPlaylist,
            icon: const Icon(Icons.add),
            label: const Text('Create First Playlist'),
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
                    Text(
                      'Updated ${_formatDate(playlist.updatedAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
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
