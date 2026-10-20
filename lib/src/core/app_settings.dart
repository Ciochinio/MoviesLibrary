import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

enum ImportMode { copy, move }

// ─────────────────────────────────────────────────────────────────────────────
// AppSettings
//
// Single class consumed by the rest of the app. Internally split into two
// storage buckets:
//
//   Library settings  → Library/settings.json
//     importMode, confirmDelete, tagDialogSimpleCols, tagDialogCustomCols
//
//   Global settings   → <exeDir>/global_settings.json
//     gifAutoplay, showTypeMarkers, showUntaggedIndicator, themeMode,
//     videoAutostartInPanel, startMuted, taggerPath
// ─────────────────────────────────────────────────────────────────────────────

class AppSettings {
  // ── Library-specific ───────────────────────────────────────────────────────
  final ImportMode importMode;
  final bool confirmDelete;
  final int tagDialogSimpleCols;
  final int tagDialogCustomCols;

  // ── Global (app-wide) ──────────────────────────────────────────────────────
  final bool gifAutoplay;
  final bool showTypeMarkers;
  final bool showUntaggedIndicator;
  final ThemeMode themeMode;
  final bool videoAutostartInPanel;
  final bool startMuted;
  final Set<String> hiddenNavItems;
  /// Folder of the Python auto-tagger ('' = auto-detect next to the app/library).
  final String taggerPath;

  const AppSettings({
    required this.importMode,
    required this.confirmDelete,
    this.tagDialogSimpleCols = 6,
    this.tagDialogCustomCols = 4,
    required this.gifAutoplay,
    required this.showTypeMarkers,
    required this.showUntaggedIndicator,
    required this.themeMode,
    this.videoAutostartInPanel = false,
    this.startMuted = false,
    this.hiddenNavItems = const {},
    this.taggerPath = '',
  });

  AppSettings copyWith({
    ImportMode? importMode,
    bool? confirmDelete,
    int? tagDialogSimpleCols,
    int? tagDialogCustomCols,
    bool? gifAutoplay,
    bool? showTypeMarkers,
    bool? showUntaggedIndicator,
    ThemeMode? themeMode,
    bool? videoAutostartInPanel,
    bool? startMuted,
    Set<String>? hiddenNavItems,
    String? taggerPath,
  }) {
    return AppSettings(
      importMode: importMode ?? this.importMode,
      confirmDelete: confirmDelete ?? this.confirmDelete,
      tagDialogSimpleCols: tagDialogSimpleCols ?? this.tagDialogSimpleCols,
      tagDialogCustomCols: tagDialogCustomCols ?? this.tagDialogCustomCols,
      gifAutoplay: gifAutoplay ?? this.gifAutoplay,
      showTypeMarkers: showTypeMarkers ?? this.showTypeMarkers,
      showUntaggedIndicator: showUntaggedIndicator ?? this.showUntaggedIndicator,
      themeMode: themeMode ?? this.themeMode,
      videoAutostartInPanel: videoAutostartInPanel ?? this.videoAutostartInPanel,
      startMuted: startMuted ?? this.startMuted,
      hiddenNavItems: hiddenNavItems ?? this.hiddenNavItems,
      taggerPath: taggerPath ?? this.taggerPath,
    );
  }

  Map<String, Object?> _libraryJson() => {
        'importMode': importMode.name,
        'confirmDelete': confirmDelete,
        'tagDialogSimpleCols': tagDialogSimpleCols,
        'tagDialogCustomCols': tagDialogCustomCols,
      };

  Map<String, Object?> _globalJson() => {
        'gifAutoplay': gifAutoplay,
        'showTypeMarkers': showTypeMarkers,
        'showUntaggedIndicator': showUntaggedIndicator,
        'themeMode': themeMode.name,
        'videoAutostartInPanel': videoAutostartInPanel,
        'startMuted': startMuted,
        'hiddenNavItems': hiddenNavItems.toList(),
        'taggerPath': taggerPath,
      };

  static AppSettings _fromJsonPair(
    Map<String, Object?> lib,
    Map<String, Object?> global,
  ) {
    return AppSettings(
      importMode: ImportMode.values.firstWhere(
        (e) => e.name == (lib['importMode'] as String?),
        orElse: () => ImportMode.copy,
      ),
      confirmDelete: (lib['confirmDelete'] as bool?) ?? true,
      tagDialogSimpleCols: (lib['tagDialogSimpleCols'] as int?) ?? 6,
      tagDialogCustomCols: (lib['tagDialogCustomCols'] as int?) ?? 4,
      gifAutoplay: (global['gifAutoplay'] as bool?) ?? false,
      showTypeMarkers: (global['showTypeMarkers'] as bool?) ?? true,
      showUntaggedIndicator: (global['showUntaggedIndicator'] as bool?) ?? true,
      themeMode: ThemeMode.values.firstWhere(
        (e) => e.name == (global['themeMode'] as String?),
        orElse: () => ThemeMode.system,
      ),
      videoAutostartInPanel: (global['videoAutostartInPanel'] as bool?) ?? false,
      startMuted: (global['startMuted'] as bool?) ?? false,
      hiddenNavItems: ((global['hiddenNavItems'] as List?)?.cast<String>().toSet()) ?? const {},
      taggerPath: (global['taggerPath'] as String?) ?? '',
    );
  }

  static Future<AppSettings> load({
    required File librarySettingsFile,
    required File globalSettingsFile,
  }) async {
    final lib = await _readJson(librarySettingsFile);
    final global = await _readJson(globalSettingsFile);
    return _fromJsonPair(lib, global);
  }

  static Future<void> saveLibrary(File file, AppSettings settings) async {
    await _mergeAndWrite(file, settings._libraryJson());
  }

  static Future<void> saveGlobal(File file, AppSettings settings) async {
    await _mergeAndWrite(file, settings._globalJson());
  }

  static Future<Map<String, Object?>> _readJson(File file) async {
    if (!await file.exists()) return {};
    try {
      final txt = await file.readAsString();
      final decoded = jsonDecode(txt);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((k, v) => MapEntry(k, v as Object?));
      }
    } catch (_) {}
    return {};
  }

  static Future<void> _mergeAndWrite(File file, Map<String, Object?> data) async {
    final existing = await _readJson(file);
    existing.addAll(data);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(existing));
  }

  static const defaults = AppSettings(
    importMode: ImportMode.copy,
    confirmDelete: true,
    tagDialogSimpleCols: 6,
    tagDialogCustomCols: 4,
    gifAutoplay: false,
    showTypeMarkers: true,
    showUntaggedIndicator: true,
    themeMode: ThemeMode.system,
    videoAutostartInPanel: false,
    startMuted: false,
    hiddenNavItems: {},
  );
}