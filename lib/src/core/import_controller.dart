import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_state.dart';
import 'vr_format.dart';

enum ImportFileStatus { pending, importing, done, skipped, failed }

class ImportFileEntry {
  final File file;
  final String name;
  ImportFileStatus status;
  String? error;

  ImportFileEntry(this.file) : name = p.basename(file.path), status = ImportFileStatus.pending;
}

/// Manages a background import queue with progress tracking.
class ImportController extends ChangeNotifier {
  final AppState appState;

  ImportController(this.appState);

  List<ImportFileEntry> _queue = [];
  List<ImportFileEntry> get queue => List.unmodifiable(_queue);

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  bool _cancelRequested = false;
  bool _skipCurrentRequested = false;

  bool _minimized = false;
  bool get minimized => _minimized;
  set minimized(bool v) { _minimized = v; notifyListeners(); }

  bool _visible = false;
  bool get visible => _visible;

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  int _imported = 0;
  int get imported => _imported;
  int _skippedCount = 0;
  int get skippedCount => _skippedCount;
  int _failedCount = 0;
  int get failedCount => _failedCount;

  int _totalBytes = 0;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _uiRefreshTimer;

  double get speedMBps {
    final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;
    if (elapsed <= 0) return 0;
    return (_totalBytes / 1024 / 1024) / elapsed;
  }

  double get progress {
    if (_queue.isEmpty) return 0;
    final doneCount = _queue.where((e) =>
        e.status == ImportFileStatus.done ||
        e.status == ImportFileStatus.skipped ||
        e.status == ImportFileStatus.failed).length;
    return doneCount / _queue.length;
  }

  String get currentFileName {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return '';
    return _queue[_currentIndex].name;
  }

  /// Callback for when a duplicate is detected. Set by the UI.
  Future<bool> Function(File file, String existingName)? onDuplicateDetected;

  /// Callback to refresh the library screen after import completes.
  VoidCallback? onImportComplete;

  /// Start importing a list of files.
  void startImport(List<File> files) {
    if (_isRunning) {
      // Append to existing queue
      for (final f in files) {
        _queue.add(ImportFileEntry(f));
      }
      notifyListeners();
      return;
    }

    _queue = files.map((f) => ImportFileEntry(f)).toList();
    _isRunning = true;
    _cancelRequested = false;
    _skipCurrentRequested = false;
    _currentIndex = 0;
    _imported = 0;
    _skippedCount = 0;
    _failedCount = 0;
    _totalBytes = 0;
    _minimized = false;
    _visible = true;
    _stopwatch.reset();
    _stopwatch.start();

    // Periodic UI refresh for real-time speed updates
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isRunning) notifyListeners();
    });

    notifyListeners();
    _processQueue();
  }

  /// Skip a specific pending file by index.
  void skipFile(int index) {
    if (index >= _queue.length) return;
    final entry = _queue[index];

    if (entry.status == ImportFileStatus.pending) {
      entry.status = ImportFileStatus.skipped;
      _skippedCount++;
      notifyListeners();
    } else if (entry.status == ImportFileStatus.importing) {
      // Cancel the currently importing file
      _skipCurrentRequested = true;
      notifyListeners();
    }
  }

  /// Cancel the entire remaining queue.
  void cancelAll() {
    _cancelRequested = true;
    _skipCurrentRequested = true;
    for (int i = 0; i < _queue.length; i++) {
      if (_queue[i].status == ImportFileStatus.pending) {
        _queue[i].status = ImportFileStatus.skipped;
        _skippedCount++;
      }
    }
    notifyListeners();
  }

  /// Dismiss the panel after completion.
  void dismiss() {
    _visible = false;
    _isRunning = false;
    _queue = [];
    _uiRefreshTimer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _processQueue() async {
    for (int i = 0; i < _queue.length; i++) {
      if (_cancelRequested) break;

      final entry = _queue[i];
      if (entry.status == ImportFileStatus.skipped) continue;

      _currentIndex = i;
      _skipCurrentRequested = false;
      entry.status = ImportFileStatus.importing;
      notifyListeners();

      try {
        final fileSize = await entry.file.length();

        // Check if skip was requested before starting the heavy work
        if (_skipCurrentRequested) {
          entry.status = ImportFileStatus.skipped;
          _skippedCount++;
          notifyListeners();
          continue;
        }

        final target = appState.selectedSubcategoryId ?? appState.stashSubcategoryId!;

        final pre = await appState.importSingleWithDuplicateDecision(
          source: entry.file,
          targetSubcategoryId: target,
          addDuplicateAsSeparateFile: false,
        );

        // Check skip again after the import call
        if (_skipCurrentRequested) {
          entry.status = ImportFileStatus.skipped;
          _skippedCount++;
          _totalBytes += fileSize;
          notifyListeners();
          continue;
        }

        if (pre.existingDuplicate != null && pre.inserted == null) {
          bool addAnyway = false;
          if (onDuplicateDetected != null) {
            addAnyway = await onDuplicateDetected!(entry.file, pre.existingDuplicate!.originalName);
          }

          if (addAnyway) {
            await appState.importSingleWithDuplicateDecision(
              source: entry.file,
              targetSubcategoryId: target,
              addDuplicateAsSeparateFile: true,
              precomputedSha256: pre.sha256,
              preexistingDuplicate: pre.existingDuplicate,
            );
            entry.status = ImportFileStatus.done;
            _imported++;
          } else {
            entry.status = ImportFileStatus.skipped;
            _skippedCount++;
          }
        } else {
          entry.status = ImportFileStatus.done;
          _imported++;
          if (pre.inserted != null) {
            try {
              await autoTagVr(appState, pre.inserted!);
            } catch (_) {
              // VR detection is a nicety; never fail the import over it
            }
          }
        }

        _totalBytes += fileSize;
      } catch (e) {
        if (_skipCurrentRequested) {
          entry.status = ImportFileStatus.skipped;
          _skippedCount++;
        } else {
          entry.status = ImportFileStatus.failed;
          entry.error = e.toString();
          _failedCount++;
        }
      }

      notifyListeners();
    }

    _stopwatch.stop();
    _uiRefreshTimer?.cancel();
    _isRunning = false;
    notifyListeners();

    onImportComplete?.call();
  }
}
