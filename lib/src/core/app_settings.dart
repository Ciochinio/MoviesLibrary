import 'dart:convert';
import 'dart:io';

enum ImportMode { copy, move }

class AppSettings {
  final ImportMode importMode;
  final bool confirmDelete;

  const AppSettings({
    required this.importMode,
    required this.confirmDelete,
  });

  AppSettings copyWith({ImportMode? importMode, bool? confirmDelete}) {
    return AppSettings(
      importMode: importMode ?? this.importMode,
      confirmDelete: confirmDelete ?? this.confirmDelete,
    );
  }

  Map<String, Object?> toJson() => {
        'importMode': importMode.name,
        'confirmDelete': confirmDelete,
      };

  static AppSettings fromJson(Map<String, Object?> json) {
    final modeStr = (json['importMode'] as String?) ?? 'copy';
    final mode = ImportMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => ImportMode.copy,
    );
    final confirm = (json['confirmDelete'] as bool?) ?? true;
    return AppSettings(importMode: mode, confirmDelete: confirm);
  }

  static const defaults = AppSettings(importMode: ImportMode.copy, confirmDelete: true);

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
