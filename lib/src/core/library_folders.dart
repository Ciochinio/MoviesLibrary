import 'dart:io';

import 'package:path/path.dart' as p;

/// Helper for keeping Library/files structure aligned with category/subcategory names.
///
/// Structure (directly under filesDir):
///   <CategoryName>/<SubcategoryName>/<uuid.ext>
///
/// Each category folder contains a `.pml_id` marker with `category:<id>`.
/// Each subcategory folder contains a `.pml_id` marker with `subcategory:<id>`.
class LibraryFolders {
  static const markerFileName = '.pml_id';

  /// Resolve a stored POSIX relative path (using '/') against filesDir.
  static String absPath(Directory filesDir, String relPosix) {
    final norm = relPosix.replaceAll('\\', '/');
    return p.joinAll([filesDir.path, ...p.posix.split(norm)]);
  }


  /// Make a filesystem-safe path segment (Windows + macOS + exFAT).
  /// We keep it human-readable and close to the original name.
  static String safeSegment(String name) {
    var s = name.trim();

    // Replace path separators and Windows-forbidden characters.
    // Windows forbids: < > : " / \ | ? * plus control chars.
    final forbidden = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
    s = s.replaceAll(forbidden, '_');

    // Avoid trailing dots/spaces (Windows quirk).
    s = s.replaceAll(RegExp(r'[ .]+$'), '');

    if (s.isEmpty) s = '_';

    // Avoid Windows reserved device names.
    final upper = s.toUpperCase();
    const reserved = {
      'CON','PRN','AUX','NUL',
      'COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9',
      'LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9',
    };
    if (reserved.contains(upper)) {
      s = '_$s';
    }
    return s;
  }

  static File _markerIn(Directory dir) => File(p.join(dir.path, markerFileName));

  static Future<void> ensureCategoryFolder({
    required Directory filesDir,
    required String categoryId,
    required String categoryName,
  }) async {
    final safe = safeSegment(categoryName);
    final dir = Directory(p.join(filesDir.path, safe));
    await dir.create(recursive: true);
    await _writeMarkerIfMissing(_markerIn(dir), 'category:$categoryId');
  }

  static Future<void> ensureSubcategoryFolder({
    required Directory filesDir,
    required String categoryName,
    required String subcategoryId,
    required String subcategoryName,
  }) async {
    final catSafe = safeSegment(categoryName);
    final subSafe = safeSegment(subcategoryName);
    final dir = Directory(p.join(filesDir.path, catSafe, subSafe));
    await dir.create(recursive: true);
    await _writeMarkerIfMissing(_markerIn(dir), 'subcategory:$subcategoryId');
  }

  static Future<void> renameFolder({
    required Directory parent,
    required String oldName,
    required String newName,
  }) async {
    final oldSafe = safeSegment(oldName);
    final newSafe = safeSegment(newName);
    if (oldSafe == newSafe) return;
    final from = Directory(p.join(parent.path, oldSafe));
    if (!await from.exists()) {
      // If folder missing, just ensure new exists.
      await Directory(p.join(parent.path, newSafe)).create(recursive: true);
      return;
    }
    final to = Directory(p.join(parent.path, newSafe));
    if (await to.exists()) {
      // Name collision: do not overwrite. Leave both.
      return;
    }
    await from.rename(to.path);
  }

  static Future<Map<String, Directory>> scanCategoryFoldersById(Directory filesDir) async {
    final out = <String, Directory>{};
    if (!await filesDir.exists()) return out;

    await for (final ent in filesDir.list(followLinks: false)) {
      if (ent is! Directory) continue;
      final marker = _markerIn(ent);
      if (!await marker.exists()) continue;
      try {
        final txt = (await marker.readAsString()).trim();
        if (txt.startsWith('category:')) {
          final id = txt.substring('category:'.length).trim();
          if (id.isNotEmpty) out[id] = ent;
        }
      } catch (_) {}
    }
    return out;
  }

  static Future<Map<String, Directory>> scanSubcategoryFoldersById(Directory categoryDir) async {
    final out = <String, Directory>{};
    if (!await categoryDir.exists()) return out;
    await for (final ent in categoryDir.list(followLinks: false)) {
      if (ent is! Directory) continue;
      final marker = _markerIn(ent);
      if (!await marker.exists()) continue;
      try {
        final txt = (await marker.readAsString()).trim();
        if (txt.startsWith('subcategory:')) {
          final id = txt.substring('subcategory:'.length).trim();
          if (id.isNotEmpty) out[id] = ent;
        }
      } catch (_) {}
    }
    return out;
  }

  static Future<void> _writeMarkerIfMissing(File marker, String content) async {
    if (await marker.exists()) return;
    try {
      await marker.writeAsString(content);
    } catch (_) {
      // ignore
    }
  }
}
