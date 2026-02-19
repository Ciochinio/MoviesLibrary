import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/import_controller.dart';

/// Docked bottom-right overlay panel for import progress.
/// Shows queue, speed, per-file skip, cancel-all.
/// Minimizable to a thin bar.
class ImportOverlayPanel extends StatelessWidget {
  const ImportOverlayPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ImportController>();
    if (!ctrl.visible) return const SizedBox.shrink();

    if (ctrl.minimized) {
      return _MinimizedBar(ctrl: ctrl);
    }

    return _ExpandedPanel(ctrl: ctrl);
  }
}

class _MinimizedBar extends StatelessWidget {
  final ImportController ctrl;
  const _MinimizedBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      right: 0,
      child: GestureDetector(
        onTap: () => ctrl.minimized = false,
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(-2, -2))],
          ),
          child: Row(
            children: [
              Icon(
                ctrl.isRunning ? Icons.downloading : Icons.check_circle,
                size: 16,
                color: ctrl.isRunning
                    ? Theme.of(context).colorScheme.primary
                    : Colors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ctrl.isRunning
                      ? 'Importing ${ctrl.currentIndex + 1}/${ctrl.queue.length}'
                      : 'Import done: ${ctrl.imported} files',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              if (ctrl.isRunning)
                Text('${ctrl.speedMBps.toStringAsFixed(1)} MB/s',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandedPanel extends StatelessWidget {
  final ImportController ctrl;
  const _ExpandedPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned(
      bottom: 0,
      right: 0,
      child: Container(
        width: 340,
        constraints: const BoxConstraints(maxHeight: 320),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(12)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12, offset: const Offset(-2, -2))],
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── Header ───
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(
                    ctrl.isRunning ? Icons.downloading : Icons.check_circle,
                    size: 16,
                    color: ctrl.isRunning ? theme.colorScheme.primary : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ctrl.isRunning
                          ? 'Importing ${ctrl.currentIndex + 1}/${ctrl.queue.length}'
                          : 'Import complete',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  InkWell(
                    onTap: () => ctrl.minimized = true,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.minimize, size: 16),
                    ),
                  ),
                  if (!ctrl.isRunning)
                    InkWell(
                      onTap: () => ctrl.dismiss(),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 16),
                      ),
                    ),
                ],
              ),
            ),
            // ─── Progress bar ───
            if (ctrl.isRunning)
              LinearProgressIndicator(value: ctrl.progress),
            // ─── Stats row ───
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Text('${ctrl.speedMBps.toStringAsFixed(1)} MB/s',
                      style: TextStyle(fontSize: 11, color: theme.hintColor)),
                  const Spacer(),
                  Text(
                    '${ctrl.imported} imported'
                    '${ctrl.skippedCount > 0 ? ', ${ctrl.skippedCount} skipped' : ''}'
                    '${ctrl.failedCount > 0 ? ', ${ctrl.failedCount} failed' : ''}',
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ─── Queue list ───
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: ctrl.queue.length,
                itemBuilder: (_, i) {
                  final entry = ctrl.queue[i];
                  return _QueueRow(entry: entry, index: i, ctrl: ctrl);
                },
              ),
            ),
            // ─── Cancel button ───
            if (ctrl.isRunning)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => ctrl.cancelAll(),
                      icon: const Icon(Icons.cancel, size: 14),
                      label: const Text('Cancel All', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final ImportFileEntry entry;
  final int index;
  final ImportController ctrl;

  const _QueueRow({required this.entry, required this.index, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData icon;
    Color color;
    switch (entry.status) {
      case ImportFileStatus.done:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case ImportFileStatus.importing:
        icon = Icons.downloading;
        color = theme.colorScheme.primary;
        break;
      case ImportFileStatus.skipped:
        icon = Icons.skip_next;
        color = Colors.grey;
        break;
      case ImportFileStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        break;
      case ImportFileStatus.pending:
      default:
        icon = Icons.schedule;
        color = Colors.grey;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              entry.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: entry.status == ImportFileStatus.skipped ? Colors.grey : null,
                decoration: entry.status == ImportFileStatus.skipped ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (entry.status == ImportFileStatus.pending && ctrl.isRunning)
            InkWell(
              onTap: () => ctrl.skipFile(index),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 12, color: Colors.grey),
              ),
            ),
          if (entry.status == ImportFileStatus.failed && entry.error != null)
            Tooltip(
              message: entry.error!,
              child: const Icon(Icons.info_outline, size: 12, color: Colors.red),
            ),
        ],
      ),
    );
  }
}
