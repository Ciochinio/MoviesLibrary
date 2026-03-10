import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';


import '../../core/app_state.dart';
import '../../core/app_settings.dart';
import '../../core/thumbnail_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _ffmpegAvailable;
  String? _ffmpegPath;

  @override
  void initState() {
    super.initState();
    _checkFfmpeg();
  }

  Future<void> _checkFfmpeg() async {
    final available = await ThumbnailService.isFfmpegAvailable();
    final path = await ThumbnailService.resolvedFfmpegPath();
    if (mounted) setState(() { _ffmpegAvailable = available; _ffmpegPath = path; });
  }

  Future<void> _downloadFfmpeg() async {
    bool success = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String statusText = 'Starting download...';
        return StatefulBuilder(
          builder: (ctx, setStateSB) {
            if (statusText == 'Starting download...') {
              Future.microtask(() async {
                success = await ThumbnailService.downloadFfmpeg(
                  onProgress: (status) { if (ctx.mounted) setStateSB(() => statusText = status); },
                );
                await Future.delayed(const Duration(milliseconds: 800));
                if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
              });
            }
            return AlertDialog(
              title: const Text('Downloading ffmpeg'),
              content: SizedBox(height: 100, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (!statusText.startsWith('Done')) const CircularProgressIndicator(),
                if (statusText.startsWith('Done')) const Icon(Icons.check_circle, color: Colors.green, size: 40),
                const SizedBox(height: 12),
                Text(statusText, textAlign: TextAlign.center),
              ])),
            );
          },
        );
      },
    );
    await _checkFfmpeg();
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ffmpeg downloaded successfully!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lib = app.paths?.libraryDir.path ?? '(none)';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),

          // ─── Theme mode ───
          Card(
            child: ListTile(
              title: const Text('Appearance'),
              subtitle: const Text('Choose between light, dark, or follow system setting.'),
              trailing: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode, size: 16),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto, size: 16),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode, size: 16),
                    label: Text('Dark'),
                  ),
                ],
                selected: {app.settings.themeMode},
                onSelectionChanged: (s) =>
                    context.read<AppState>().setThemeMode(s.first),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ─── Import mode ───
          Card(
            child: ListTile(
              title: const Text('Import mode'),
              subtitle: Text(app.settings.importMode == ImportMode.copy
                  ? 'Copy files to /Library/files'
                  : 'Move files to /Library/files'),
              trailing: SegmentedButton<ImportMode>(
                segments: const [
                  ButtonSegment(value: ImportMode.copy, label: Text('Copy')),
                  ButtonSegment(value: ImportMode.move, label: Text('Move')),
                ],
                selected: {app.settings.importMode},
                onSelectionChanged: (s) => context.read<AppState>().setImportMode(s.first),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ─── Confirm delete ───
          Card(
            child: SwitchListTile(
              title: const Text('Confirm before deleting'),
              subtitle: const Text('If disabled, deletion will proceed without confirmation.'),
              value: app.settings.confirmDelete,
              onChanged: (v) => context.read<AppState>().setConfirmDelete(v),
            ),
          ),
          const SizedBox(height: 12),

          // ─── Video autostart in panel ───
          Card(
            child: SwitchListTile(
              title: const Text('Autoplay video in side panel'),
              subtitle: const Text('Video starts playing automatically when selected. Off = manual play.'),
              value: app.settings.videoAutostartInPanel,
              onChanged: (v) => context.read<AppState>().setVideoAutostartInPanel(v),
            ),
          ),
          const SizedBox(height: 12),

          // ─── Start muted ───
          Card(
            child: SwitchListTile(
              title: const Text('Start player muted'),
              subtitle: const Text('All players start with volume muted until you unmute.'),
              value: app.settings.startMuted,
              onChanged: (v) => context.read<AppState>().setStartMuted(v),
            ),
          ),
          const SizedBox(height: 12),

          // ─── GIF Autoplay ───
          Card(
            child: SwitchListTile(
              title: const Text('GIF autoplay'),
              subtitle: const Text('Enable animated GIF playback in the grid. Disable for better performance.'),
              value: app.settings.gifAutoplay,
              onChanged: (v) => context.read<AppState>().setGifAutoplay(v),
            ),
          ),
          const SizedBox(height: 12),

          // ─── Type markers ───
          Card(
            child: SwitchListTile(
              title: const Text('Show type markers'),
              subtitle: const Text('Show Image / GIF / Video / Other badge on each grid item.'),
              value: app.settings.showTypeMarkers,
              onChanged: (v) => context.read<AppState>().setShowTypeMarkers(v),
            ),
          ),
          const SizedBox(height: 12),

          // ─── Untagged indicator ───
          Card(
            child: SwitchListTile(
              title: const Text('Show untagged indicator'),
              subtitle: const Text('Show a dot on grid items that have no tags assigned.'),
              value: app.settings.showUntaggedIndicator,
              onChanged: (v) => context.read<AppState>().setShowUntaggedIndicator(v),
            ),
          ),
          const SizedBox(height: 12),

          // ─── Tag dialog layout ───
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tag Dialog Layout', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _ColsRow(
                    label: 'Simple tags — chips per row',
                    value: app.settings.tagDialogSimpleCols,
                    min: 3, max: 10,
                    onChanged: (v) => context.read<AppState>().updateSettings(
                      app.settings.copyWith(tagDialogSimpleCols: v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ColsRow(
                    label: 'Custom tags — chips per row',
                    value: app.settings.tagDialogCustomCols,
                    min: 2, max: 8,
                    onChanged: (v) => context.read<AppState>().updateSettings(
                      app.settings.copyWith(tagDialogCustomCols: v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ─── Library path ───
          Card(
            child: ListTile(
              title: const Text('Library path'),
              subtitle: Text(lib),
              trailing: FilledButton.icon(
                onPressed: () async => await context.read<AppState>().promptAndCreateOrOpenLibrary(),
                icon: const Icon(Icons.folder_open),
                label: const Text('Change'),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ─── ffmpeg info ───
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('ffmpeg', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: 12),
                      if (_ffmpegAvailable == null)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      else if (_ffmpegAvailable == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                          child: const Text('Found', style: TextStyle(color: Colors.white, fontSize: 12)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                          child: const Text('Not found', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Required for video/GIF thumbnail extraction.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (_ffmpegPath != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Location: $_ffmpegPath',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: 'Copy path',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _ffmpegPath!));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Path copied')));
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.folder_open, size: 16),
                          tooltip: 'Open folder',
                          onPressed: () async {
                            final dir = Directory(_ffmpegPath!).parent.path;
                            if (Platform.isWindows) {
                              await Process.run('explorer', [dir]);
                            } else if (Platform.isMacOS) {
                              await Process.run('open', [dir]);
                            } else {
                              await Process.run('xdg-open', [dir]);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (_ffmpegAvailable != true && ThumbnailService.isAutoDownloadSupported) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Download location: ${ThumbnailService.bundledDirPath}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _downloadFfmpeg,
                      icon: const Icon(Icons.download),
                      label: const Text('Download ffmpeg (~90MB)'),
                    ),
                  ],
                  if (_ffmpegAvailable == true) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _checkFfmpeg();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(_ffmpegAvailable == true ? 'ffmpeg is working' : 'ffmpeg not found'),
                          ));
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Re-check'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          const Text(
            'Portable tip:\n'
            '• Copy app build to /App\n'
            '• Create /Library next to /App\n'
            '• Run the app from /App — it will auto-detect /Library\n',
          ),
        ],
      ),
    );
  }
}
class _ColsRow extends StatefulWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final void Function(int) onChanged;

  const _ColsRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_ColsRow> createState() => _ColsRowState();
}

class _ColsRowState extends State<_ColsRow> {
  late int _localValue;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
  }

  @override
  void didUpdateWidget(_ColsRow old) {
    super.didUpdateWidget(old);
    // Only sync from outside if no pending debounce (user not currently clicking)
    if (_debounce == null || !_debounce!.isActive) {
      _localValue = widget.value;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _tap(int delta) {
    final next = (_localValue + delta).clamp(widget.min, widget.max);
    if (next == _localValue) return;
    setState(() => _localValue = next);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      widget.onChanged(_localValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(widget.label, style: const TextStyle(fontSize: 13))),
        IconButton(
          icon: const Icon(Icons.remove, size: 16),
          onPressed: _localValue > widget.min ? () => _tap(-1) : null,
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$_localValue',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 16),
          onPressed: _localValue < widget.max ? () => _tap(1) : null,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}