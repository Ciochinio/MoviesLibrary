import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class PortablePaths {
  final Directory libraryDir;
  final Directory dbDir;
  final Directory filesDir;
  final Directory thumbsDir;
  final Directory attachmentsDir;
  final File settingsFile;       // Library/settings.json  — library-specific
  final File globalSettingsFile; // <exeDir>/global_settings.json — app-wide
  final File dbFile;

  PortablePaths._({
    required this.libraryDir,
    required this.dbDir,
    required this.filesDir,
    required this.thumbsDir,
    required this.attachmentsDir,
    required this.settingsFile,
    required this.globalSettingsFile,
    required this.dbFile,
  });

  static const _settingsName = 'settings.json';
  static const _globalSettingsName = 'global_settings.json';

  static Future<PortablePaths> forLibraryPath(String libraryPath) async {
    final libraryDir = Directory(libraryPath);
    await libraryDir.create(recursive: true);

    final dbDir = Directory(p.join(libraryDir.path, 'db'));
    final filesDir = Directory(p.join(libraryDir.path, 'files'));
    final thumbsDir = Directory(p.join(libraryDir.path, 'thumbs'));
    final attachmentsDir = Directory(p.join(libraryDir.path, 'attachments'));

    await dbDir.create(recursive: true);
    await filesDir.create(recursive: true);
    await thumbsDir.create(recursive: true);
    await attachmentsDir.create(recursive: true);

    final settingsFile = File(p.join(libraryDir.path, _settingsName));
    final dbFile = File(p.join(dbDir.path, 'library.sqlite'));

    // Global settings live next to the executable so they survive library switches.
    final exeDir = Directory(p.dirname(Platform.resolvedExecutable));
    final globalSettingsFile = File(p.join(exeDir.path, _globalSettingsName));

    return PortablePaths._(
      libraryDir: libraryDir,
      dbDir: dbDir,
      filesDir: filesDir,
      thumbsDir: thumbsDir,
      attachmentsDir: attachmentsDir,
      settingsFile: settingsFile,
      globalSettingsFile: globalSettingsFile,
      dbFile: dbFile,
    );
  }

  /// Tries to locate a sibling /Library folder next to the executable.
  
/// Tries to locate a sibling /Library folder next to the app.
///
/// Windows (portable):  <drive>/App/<exe>  => sibling <drive>/Library
/// macOS (bundle):      <drive>/App/My.app/Contents/MacOS/<exe> => sibling <drive>/Library
static Future<String?> tryDetectSiblingLibrary() async {
  try {
    final exePath = Platform.resolvedExecutable;
    final exeDir = Directory(p.dirname(exePath));

    // Case 1: Windows/Linux portable exe in /App
    final winLikeSibling = Directory(p.normalize(p.join(exeDir.path, '..', 'Library')));
    if (await winLikeSibling.exists()) return winLikeSibling.path;

    // Case 2: macOS .app bundle: go up from Contents/MacOS -> Contents -> .app -> /App folder
    final macSibling = Directory(p.normalize(p.join(exeDir.path, '..', '..', '..', '..', 'Library')));
    if (await macSibling.exists()) return macSibling.path;

    // Fallback: if running from repo, allow ./Library
    final local = Directory(p.join(Directory.current.path, 'Library'));
    if (await local.exists()) return local.path;
  } catch (_) {
    // ignore
  }
  return null;
}

  
static Future<void> saveSelectedLibraryPath(File settingsFile, String libraryPath) async {
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
  data['libraryPath'] = libraryPath;
  await settingsFile.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}

  
static Future<String?> loadSelectedLibraryPath(File settingsFile) async {
  if (!await settingsFile.exists()) return null;
  try {
    final txt = await settingsFile.readAsString();
    final json = jsonDecode(txt);
    if (json is Map<String, dynamic>) {
      final v = json['libraryPath'];
      if (v is String && v.trim().isNotEmpty) return v;
    }
  } catch (_) {}
  return null;
}
}