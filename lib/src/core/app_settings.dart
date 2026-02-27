import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

enum ImportMode { copy, move }

class AppSettings {
  final ImportMode importMode;
  final bool confirmDelete;
  final bool gifAutoplay;
  final bool showTypeMarkers;
  final bool showUntaggedIndicator;
  final ThemeMode themeMode;
  final bool videoAutostartInPanel;
  final bool startMuted;

  const AppSettings({
    required this.importMode,
    required this.confirmDelete,
    required this.gifAutoplay,
    required this.showTypeMarkers,
    required this.showUntaggedIndicator,
    required this.themeMode,
    this.videoAutostartInPanel = false,
    this.startMuted = false,
  });

  AppSettings copyWith({
    ImportMode? importMode,
    bool? confirmDelete,
    bool? gifAutoplay,
    bool? showTypeMarkers,
    bool? showUntaggedIndicator,
    ThemeMode? themeMode,
    bool? videoAutostartInPanel,
    bool? startMuted,
  }) {
    return AppSettings(
      importMode: importMode ?? this.importMode,
      confirmDelete: confirmDelete ?? this.confirmDelete,
      gifAutoplay: gifAutoplay ?? this.gifAutoplay,
      showTypeMarkers: showTypeMarkers ?? this.showTypeMarkers,
      showUntaggedIndicator: showUntaggedIndicator ?? this.showUntaggedIndicator,
      themeMode: themeMode ?? this.themeMode,
      videoAutostartInPanel: videoAutostartInPanel ?? this.videoAutostartInPanel,
      startMuted: startMuted ?? this.startMuted,
    );
  }

  Map<String, Object?> toJson() => {
        'importMode': importMode.name,
        'confirmDelete': confirmDelete,
        'gifAutoplay': gifAutoplay,
        'showTypeMarkers': showTypeMarkers,
        'showUntaggedIndicator': showUntaggedIndicator,
        'themeMode': themeMode.name,
        'videoAutostartInPanel': videoAutostartInPanel,
        'startMuted': startMuted,
      };

  static AppSettings fromJson(Map<String, Object?> json) {
    final modeStr = (json['importMode'] as String?) ?? 'copy';
    final mode = ImportMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => ImportMode.copy,
    );
    final confirm = (json['confirmDelete'] as bool?) ?? true;
    final gifAuto = (json['gifAutoplay'] as bool?) ?? false;
    final typeMarkers = (json['showTypeMarkers'] as bool?) ?? true;
    final untaggedIndicator = (json['showUntaggedIndicator'] as bool?) ?? true;
    final themeModeStr = (json['themeMode'] as String?) ?? 'system';
    final themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == themeModeStr,
      orElse: () => ThemeMode.system,
    );
    final videoAutostart = (json['videoAutostartInPanel'] as bool?) ?? false;
    final startMuted = (json['startMuted'] as bool?) ?? false;
    return AppSettings(
      importMode: mode,
      confirmDelete: confirm,
      gifAutoplay: gifAuto,
      showTypeMarkers: typeMarkers,
      showUntaggedIndicator: untaggedIndicator,
      themeMode: themeMode,
      videoAutostartInPanel: videoAutostart,
      startMuted: startMuted,
    );
  }

  static const defaults = AppSettings(
    importMode: ImportMode.copy,
    confirmDelete: true,
    gifAutoplay: false,
    showTypeMarkers: true,
    showUntaggedIndicator: true,
    themeMode: ThemeMode.system,
    videoAutostartInPanel: false,
    startMuted: false,
  );

  static Future<AppSettings> load(File settingsFile) async {
    if (!await settingsFile.exists()) return defaults;
    try {
      final txt = await settingsFile.readAsString();
      final map = jsonDecode(txt);
      if (map is Map<String, dynamic>) {
        return fromJson(map.map((k, v) => MapEntry(k, v as Object?)));
      }
    } catch (_) {}
    return defaults;
  }

  static Future<void> save(File settingsFile, AppSettings settings) async {
    Map<String, Object?> data = {};
    if (await settingsFile.exists()) {
      try {
        final txt = await settingsFile.readAsString();
        final json = jsonDecode(txt);
        if (json is Map<String, dynamic>) {
          data = json.map((k, v) => MapEntry(k, v as Object?));
        }
      } catch (_) {}
    }
    data.addAll(settings.toJson());
    final jsonTxt = const JsonEncoder.withIndent('  ').convert(data);
    await settingsFile.writeAsString(jsonTxt);
  }
}
