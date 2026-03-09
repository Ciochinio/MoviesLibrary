import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db.dart';
import 'models.dart';
import 'portable_paths.dart';
import 'repositories.dart';
import 'raffle_repository.dart';
import 'quick_roll_repository.dart';
import 'app_settings.dart';
import 'library_folders.dart';

class AppState extends ChangeNotifier {
  PortablePaths? paths;
  AppDb? _appDb;
  Database? _db;

  CategoryRepo? categories;
  TagRepo? tags;
  ItemRepo? items;
  NoteRepo? notes;
  RaffleRepository? raffle;
  QuickRollRepository? quickRoll;


  AppSettings settings = AppSettings.defaults;

  // UI state
  String? selectedCategoryId;
  String? selectedSubcategoryId;
  final Set<String> selectedItemIds = {}; // bulk selection

  // Global tag search (across all folders)
  final Set<String> globalSearchTagIds = {};
  bool globalSearchActive = false;

  // cached
  List<Category> _categoryList = [];
  final Map<String, List<Subcategory>> _subByCat = {};
  List<Tag> _tagList = [];
  List<TagGroup> _tagGroupList = [];
  List<TagKey> _tagKeyList = [];
  List<NameOrderEntry> _nameOrderList = [];
  final Map<String, List<TagKeyValue>> _tagValuesByKey = {};

  String? stashCategoryId;
  String? stashSubcategoryId; // default "Unassigned"

  bool get isReady => _db != null && paths != null;

  List<Category> get categoryList => _categoryList;
  List<Subcategory> subcategoriesFor(String categoryId) => _subByCat[categoryId] ?? [];
  List<Tag> get tagList => _tagList;
  List<TagGroup> get tagGroupList => _tagGroupList;
  List<TagKey> get tagKeyList => _tagKeyList;
  List<NameOrderEntry> get nameOrderList => _nameOrderList;
  List<TagKeyValue> valuesForKey(String keyId) => _tagValuesByKey[keyId] ?? const [];

  Future<void> bootstrap() async {
    // 1) detect sibling library
    final sibling = await PortablePaths.tryDetectSiblingLibrary();

    // 2) if no sibling, try settings inside ./Library (dev)
    String? libPath = sibling;
    if (libPath == null) {
      final tmp = await PortablePaths.forLibraryPath(p.join(Directory.current.path, 'Library'));
      final saved = await PortablePaths.loadSelectedLibraryPath(tmp.settingsFile);
      libPath = saved;
    }

    if (libPath != null) {
      await openLibrary(libPath);
    }
  }

  Future<void> promptAndCreateOrOpenLibrary() async {
    final res = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select Library folder (or create new)');
    if (res == null) return;
    await openLibrary(res);
  }

  Future<void> openLibrary(String libraryPath) async {
    paths = await PortablePaths.forLibraryPath(libraryPath);

    // Save selection into settings.json inside library
    await PortablePaths.saveSelectedLibraryPath(paths!.settingsFile, libraryPath);

    settings = await AppSettings.load(paths!.settingsFile);
    await AppSettings.save(paths!.settingsFile, settings);

    _appDb = AppDb(paths!.dbFile.path);
    _db = await _appDb!.open();

    categories = CategoryRepo(_db!);
    tags = TagRepo(_db!);
    items = ItemRepo(_db!, paths!.filesDir);
    notes = NoteRepo(_db!, paths!.attachmentsDir);
    raffle = RaffleRepository(_db!);
    quickRoll = QuickRollRepository(_db!);

    await _ensureDefaults();
    await _rebuildFromSidecarsIfEmpty();
    await _syncFolderNamesFromDisk();
    await refreshAll();
    await _ensureFolderMarkers();
    await _migrateItemsToFolderStructure();
    await refreshAll();

    // default selection: stash
    selectedCategoryId = stashCategoryId;
    selectedSubcategoryId = stashSubcategoryId;
    notifyListeners();
  }

  Future<void> _ensureDefaults() async {
    final cats = await _db!.query('categories');
    if (cats.isNotEmpty) return;

    final defaults = ['Drama', 'Comedy', 'Action', 'Actor', 'Actress', 'Director', 'Stash'];
    for (final name in defaults) {
      await _db!.insert('categories', {'id': _id(), 'name': name});
    }

    final stashRows = await _db!.query('categories', where: 'name=?', whereArgs: ['Stash'], limit: 1);
    final stashId = stashRows.first['id'] as String;

    await _db!.insert('subcategories', {'id': _id(), 'category_id': stashId, 'name': 'Unassigned'});
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toString() +
      '-' +
      (DateTime.now().millisecondsSinceEpoch % 1000).toString();

  Future<String> suggestName(String itemId, String originalName) async {
    if (tags == null || items == null) return originalName;
    return items!.suggestNameForItem(
      itemId,
      originalName,
      tagRepo: tags!,
      allGroups: _tagGroupList,
      allKeys: _tagKeyList,
      allTags: _tagList,
    );
  }

  Future<void> saveNameOrder(List<NameOrderEntry> entries) async {
    if (tags == null) return;
    await tags!.saveNameOrder(entries);
    await refreshAll();
  }

  Future<void> refreshAll() async {
    if (!isReady) return;
    _categoryList = await categories!.listCategories();
    _subByCat.clear();
    for (final c in _categoryList) {
      _subByCat[c.id] = await categories!.listSubcategories(c.id);
    }
    _tagList = await tags!.listTags();
    _tagGroupList = await tags!.listTagGroups();

    _tagKeyList = await tags!.listTagKeys();
    _nameOrderList = await tags!.listNameOrder(
      allGroups: _tagGroupList,
      allKeys: _tagKeyList,
    );
    _tagValuesByKey.clear();
    for (final k in _tagKeyList) {
      _tagValuesByKey[k.id] = await tags!.listValuesForKey(k.id);
    }

    stashCategoryId = _categoryList
        .firstWhere((c) => c.name.toLowerCase() == 'stash', orElse: () => _categoryList.first)
        .id;
    final stashSubs = _subByCat[stashCategoryId!] ?? [];
    stashSubcategoryId = stashSubs.isNotEmpty ? stashSubs.first.id : null;

    notifyListeners();
  }

  // ─── Reordering ──────────────────────────────

  Future<void> reorderCategories(List<String> orderedIds) async {
    await categories!.reorderCategories(orderedIds);
    await refreshAll();
  }

  Future<void> reorderSubcategories(String categoryId, List<String> orderedIds) async {
    await categories!.reorderSubcategories(orderedIds);
    await refreshAll();
  }

  Future<void> reorderTags(List<String> orderedIds) async {
    await tags!.reorderTags(orderedIds);
    await refreshAll();
  }

  Future<void> reorderTagKeys(List<String> orderedIds) async {
    await tags!.reorderTagKeys(orderedIds);
    await refreshAll();
  }

  Future<void> reorderTagKeyValues(List<String> orderedIds) async {
    await tags!.reorderTagKeyValues(orderedIds);
    await refreshAll();
  }
  Future<void> createTagGroup(String name) async {
  await tags!.createTagGroup(name);
  await refreshAll();
}

Future<void> renameTagGroup(String id, String newName) async {
  await tags!.renameTagGroup(id, newName);
  await refreshAll();
}

Future<void> deleteTagGroup(String groupId) async {
  await tags!.deleteTagGroup(groupId);
  await refreshAll();
}

Future<void> reorderTagGroups(List<String> orderedIds) async {
  await tags!.reorderTagGroups(orderedIds);
  await refreshAll();
}

Future<void> setTagGroup(String tagId, String? groupId) async {
  await tags!.setTagGroup(tagId, groupId);
  await refreshAll();
}
  Future<void> selectSubcategory(String categoryId, String subcategoryId) async {
  // Switching folders exits global search mode.
  globalSearchTagIds.clear();
  globalSearchActive = false;

  selectedCategoryId = categoryId;
  selectedSubcategoryId = subcategoryId;
  selectedItemIds.clear();
  notifyListeners();
}



  void toggleItemSelection(String itemId) {
    if (selectedItemIds.contains(itemId)) {
      selectedItemIds.remove(itemId);
    } else {
      selectedItemIds.add(itemId);
    }
    notifyListeners();
  }

  void clearItemSelection() {
    selectedItemIds.clear();
    notifyListeners();
  }


Future<void> setGlobalTagSearch(List<String> tagIds) async {
  globalSearchTagIds
    ..clear()
    ..addAll(tagIds);
  globalSearchActive = globalSearchTagIds.isNotEmpty;
  selectedItemIds.clear();
  notifyListeners();
}

void clearGlobalTagSearch() {
  globalSearchTagIds.clear();
  globalSearchActive = false;
  selectedItemIds.clear();
  notifyListeners();
}

    Future<List<MediaItem>> loadCurrentItems() async {
    if (!isReady) return [];
    if (globalSearchActive) {
      return await items!.listItemsByTagsGlobal(tagIds: globalSearchTagIds.toList());
    }
    if (selectedSubcategoryId == null) return [];
    return await items!.listItemsInSubcategory(selectedSubcategoryId!, tagIds: const []);
  }

  /// Global search across the whole library, AND semantics across all selected filters.
  Future<List<MediaItem>> searchItems({
    required List<String> simpleTagIds,
    required List<String> keyValueIds,
  }) async {
    if (!isReady) return [];
    return await items!.searchItemsGlobal(simpleTagIds: simpleTagIds, keyValueIds: keyValueIds);
  }


  Future<void> createCategory(String name) async {
    final c = await categories!.createCategory(name);
    // Keep folder structure in sync.
    await LibraryFolders.ensureCategoryFolder(filesDir: paths!.filesDir, categoryId: c.id, categoryName: c.name);
    await refreshAll();
  }

  Future<void> renameCategory(String id, String newName) async {
    final old = _categoryList.firstWhere((c) => c.id == id).name;
    await categories!.renameCategory(id, newName);
    await LibraryFolders.renameFolder(parent: paths!.filesDir, oldName: old, newName: newName);
    await _migrateItemsToFolderStructure();
    await refreshAll();
  }

  Future<void> deleteCategoryMoveToStash(String id) async {
    await categories!.deleteCategoryMoveItems(id, stashSubcategoryId!);
    await _migrateItemsToFolderStructure();
    await refreshAll();
    selectedCategoryId = stashCategoryId;
    selectedSubcategoryId = stashSubcategoryId;
    notifyListeners();
  }

  Future<void> createSubcategory(String categoryId, String name) async {
    final s = await categories!.createSubcategory(categoryId, name);
    final cat = _categoryList.firstWhere((c) => c.id == categoryId);
    await LibraryFolders.ensureSubcategoryFolder(
      filesDir: paths!.filesDir,
      categoryName: cat.name,
      subcategoryId: s.id,
      subcategoryName: s.name,
    );
    await refreshAll();
  }

  Future<void> renameSubcategory(String id, String newName) async {
    // Find current category + names from cache.
    String? categoryId;
    String? oldSubName;
    for (final c in _categoryList) {
      final subs = subcategoriesFor(c.id);
      for (final s in subs) {
        if (s.id == id) {
          categoryId = c.id;
          oldSubName = s.name;
          break;
        }
      }
      if (categoryId != null) break;
    }

    await categories!.renameSubcategory(id, newName);

    if (categoryId != null && oldSubName != null) {
      final cat = _categoryList.firstWhere((c) => c.id == categoryId);
      final catDir = Directory(p.join(paths!.filesDir.path, LibraryFolders.safeSegment(cat.name)));
      await LibraryFolders.renameFolder(parent: catDir, oldName: oldSubName!, newName: newName);
    }

    await _migrateItemsToFolderStructure();
    await refreshAll();
  }

  Future<void> deleteSubcategoryMoveToStash(String subId) async {
    await categories!.deleteSubcategoryMoveItems(subId, stashSubcategoryId!);
    await _migrateItemsToFolderStructure();
    await refreshAll();
    selectedCategoryId = stashCategoryId;
    selectedSubcategoryId = stashSubcategoryId;
    notifyListeners();
  }

  Future<void> createTag(String name) async {
    await tags!.createTag(name);
    await refreshAll();
  }

  Future<void> renameTag(String id, String newName) async {
    await tags!.renameTag(id, newName);
    await refreshAll();
  }

  Future<int> countTagUsage(String id) async => tags!.countTagUsage(id);

  Future<void> deleteTag(String id) async {
    await tags!.deleteTag(id);
    // If the deleted tag is currently used in global search, remove it.
    globalSearchTagIds.remove(id);
    if (globalSearchTagIds.isEmpty) {
      globalSearchActive = false;
    }
    await refreshAll();
  }

  // --- Key:Value tags (global) ---
  Future<void> createTagKey(String key) async {
    await tags!.createTagKey(key);
    await refreshAll();
  }

  Future<void> renameTagKey(String id, String newKey) async {
    await tags!.renameTagKey(id, newKey);
    await refreshAll();
  }

  Future<int> countTagKeyUsage(String keyId) async => tags!.countTagKeyUsage(keyId);

  Future<void> deleteTagKey(String keyId) async {
    await tags!.deleteTagKey(keyId);
    await refreshAll();
  }

  Future<void> createTagKeyValue(String keyId, String value) async {
    await tags!.createValue(keyId, value);
    await refreshAll();
  }

  Future<void> renameTagKeyValue(String valueId, String newValue) async {
    await tags!.renameValue(valueId, newValue);
    await refreshAll();
  }

  Future<int> countTagKeyValueUsage(String valueId) async => tags!.countValueUsage(valueId);

  Future<void> deleteTagKeyValue(String valueId) async {
    await tags!.deleteValue(valueId);
    await refreshAll();
  }

    Future<({MediaItem? inserted, MediaItem? existingDuplicate, String? sha256})> importSingleWithDuplicateDecision({
    required File source,
    required String targetSubcategoryId,
    required bool addDuplicateAsSeparateFile,
    String? precomputedSha256,
    MediaItem? preexistingDuplicate,
  }) async {
    if (!isReady) return (inserted: null, existingDuplicate: null, sha256: null);

    // Approach A: hash first (streaming), decide on duplicate, then import without re-hashing.
    final hash = precomputedSha256 ?? await _hashFile(source);
    final existing = preexistingDuplicate ?? await items!.findByHash(hash);

    if (existing != null && !addDuplicateAsSeparateFile) {
      return (inserted: null, existingDuplicate: existing, sha256: hash);
    }

    final res = await items!.importFile(
      source: source,
      targetSubcategoryId: targetSubcategoryId,
      forceAddDuplicateAsSeparateFile: addDuplicateAsSeparateFile,
      stashSubcategoryId: stashSubcategoryId!,
      importMode: settings.importMode,
      precomputedSha256: hash,
      preexistingDuplicate: existing,
    );

    // Apply auto-tags for the target subcategory
    final actualSubId = res.duplicateOf != null && !addDuplicateAsSeparateFile
        ? null  // not inserted
        : (existing != null ? stashSubcategoryId! : targetSubcategoryId);
    if (actualSubId != null) {
      await applyAutoTagsToItem(res.item.id, actualSubId);
    }

    notifyListeners();
    return (inserted: res.item, existingDuplicate: res.duplicateOf, sha256: hash);
  }


Future<String> _hashFile(File f) async {
  final digest = await sha256.bind(f.openRead()).first;
  return digest.toString();
}

  Future<void> moveSelectedItems(String newSubcategoryId) async {
    if (selectedItemIds.isEmpty) return;
    final list = await items!.listItemsByIds(selectedItemIds.toList());
    await items!.moveItemsToSubcategory(list, newSubcategoryId);
    // Apply auto-tags for the destination subcategory
    for (final item in list) {
      await applyAutoTagsToItem(item.id, newSubcategoryId);
    }
    await refreshFromDiskAndMigrate();
    clearItemSelection();
    await refreshAll();
  }

  /// Applies auto-tags configured for a subcategory to a single item.
  /// For custom tags (key-value), removes any existing value for the same key
  /// before applying the new one, enforcing single-pick per key.
  Future<void> applyAutoTagsToItem(String itemId, String subcategoryId) async {
    if (!isReady) return;
    final autoTagIds = await categories!.getAutoTagIds(subcategoryId);
    final autoKvIds = await categories!.getAutoKeyValueIds(subcategoryId);
    if (autoTagIds.isEmpty && autoKvIds.isEmpty) return;

    for (final tagId in autoTagIds) {
      await items!.addTagToItem(itemId, tagId);
    }
    for (final kvId in autoKvIds) {
      // Find which key this value belongs to
      final keyId = await tags!.getKeyIdForValue(kvId);
      if (keyId != null) {
        // Remove any existing value the item has for this key
        final existingKvIds = await items!.listKeyValueIdsForItem(itemId);
        final valuesForKey = await tags!.listValuesForKey(keyId);
        final valuesForKeyIds = valuesForKey.map((v) => v.id).toSet();
        for (final existing in existingKvIds) {
          if (valuesForKeyIds.contains(existing)) {
            await items!.removeKeyValueFromItem(itemId, existing);
          }
        }
      }
      await items!.addKeyValueToItem(itemId, kvId);
    }
    // Update sidecar with new tags
    await items!.writeSidecarForItemId(itemId);
  }

  Future<void> bulkAddTagToSelected(String tagId) async {
    if (selectedItemIds.isEmpty) return;
    await items!.bulkAddTag(selectedItemIds.toList(), tagId);
    for (final id in selectedItemIds) {
      await items!.writeSidecarForItemId(id);
    }
    await refreshAll();
  }

  Future<void> bulkRemoveTagFromSelected(String tagId) async {
    if (selectedItemIds.isEmpty) return;
    await items!.bulkRemoveTag(selectedItemIds.toList(), tagId);
    for (final id in selectedItemIds) {
      await items!.writeSidecarForItemId(id);
    }
    await refreshAll();
  }

  Future<void> setTagsForItem({
    required String itemId,
    required Set<String> simpleTagIds,
    required Set<String> keyValueIds,
  }) async {
    if (!isReady) return;

    final curSimple = await items!.listTagIdsForItem(itemId);
    final curKv = await items!.listKeyValueIdsForItem(itemId);

    final addSimple = simpleTagIds.difference(curSimple);
    final removeSimple = curSimple.difference(simpleTagIds);

    final addKv = keyValueIds.difference(curKv);
    final removeKv = curKv.difference(keyValueIds);

    await _db!.transaction((txn) async {
      for (final id in addSimple) {
        await txn.insert('item_tags', {'item_id': itemId, 'tag_id': id}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final id in removeSimple) {
        await txn.delete('item_tags', where: 'item_id=? AND tag_id=?', whereArgs: [itemId, id]);
      }
      for (final id in addKv) {
        await txn.insert('item_tag_key_values', {'item_id': itemId, 'key_value_id': id}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final id in removeKv) {
        await txn.delete('item_tag_key_values', where: 'item_id=? AND key_value_id=?', whereArgs: [itemId, id]);
      }
    });

    await items!.writeSidecarForItemId(itemId);
    await refreshAll();
  }

    Future<({List<MediaItem> deleted, List<MediaItem> failed})> deleteSelectedItems(List<MediaItem> loadedItems) async {
    if (selectedItemIds.isEmpty) return (deleted: <MediaItem>[], failed: <MediaItem>[]);

    final toDelete = loadedItems.where((i) => selectedItemIds.contains(i.id)).toList();
    final res = await items!.deleteItems(toDelete);

    // Remove successfully deleted from selection; keep failed selected so user can retry.
    for (final it in res.deleted) {
      selectedItemIds.remove(it.id);
    }
    await refreshFromDiskAndMigrate();
    await refreshAll();
    return res;
  }


Future<void> setImportMode(ImportMode mode) async {
  settings = settings.copyWith(importMode: mode);
  await AppSettings.save(paths!.settingsFile, settings);
  notifyListeners();
}

Future<void> setConfirmDelete(bool value) async {
  settings = settings.copyWith(confirmDelete: value);
  await AppSettings.save(paths!.settingsFile, settings);
  notifyListeners();
}

Future<void> setGifAutoplay(bool value) async {
  settings = settings.copyWith(gifAutoplay: value);
  await AppSettings.save(paths!.settingsFile, settings);
  notifyListeners();
}

Future<void> setShowTypeMarkers(bool value) async {
  settings = settings.copyWith(showTypeMarkers: value);
  await AppSettings.save(paths!.settingsFile, settings);
  notifyListeners();
}

Future<void> setShowUntaggedIndicator(bool value) async {
  settings = settings.copyWith(showUntaggedIndicator: value);
  await AppSettings.save(paths!.settingsFile, settings);
  notifyListeners();
}

Future<void> setThemeMode(ThemeMode mode) async {
  settings = settings.copyWith(themeMode: mode);
  await AppSettings.save(paths!.settingsFile, settings);
  notifyListeners();
}

Future<void> setVideoAutostartInPanel(bool value) async {
  settings = settings.copyWith(videoAutostartInPanel: value);
  await AppSettings.save(paths!.settingsFile, settings);
  notifyListeners();
}

Future<void> setStartMuted(bool value) async {
  settings = settings.copyWith(startMuted: value);
  await AppSettings.save(paths!.settingsFile, settings);
  notifyListeners();
}

  Future<void> toggleFavourite(String itemId, bool value) async {
    if (!isReady) return;
    await items!.toggleFavourite(itemId, value);
    // No notifyListeners() here — callers handle UI update locally to avoid grid flash.
  }

  Future<List<MediaItem>> loadFavourites() async {
    if (!isReady) return [];
    return await items!.listFavourites();
  }

  Future<({List<MediaItem> deleted, List<MediaItem> failed})> deleteOneItem(MediaItem item) async {
    final res = await items!.deleteItems([item]);
    await refreshFromDiskAndMigrate();
    await refreshAll();
    return res;
  }

  Future<void> _rebuildFromSidecarsIfEmpty() async {
    if (!isReady) return;

    final c = await _db!.rawQuery('SELECT COUNT(*) as c FROM items');
    final count = (c.first['c'] as int?) ?? 0;
    if (count > 0) return;

    // Look for sidecar files (*.pml.json) under /Library/files.
    final sidecars = <File>[];
    await for (final ent in paths!.filesDir.list(recursive: true, followLinks: false)) {
      if (ent is File && ent.path.endsWith('.pml.json')) {
        sidecars.add(ent);
      }
    }
    if (sidecars.isEmpty) return;

    for (final sc in sidecars) {
      try {
        final raw = await sc.readAsString();
        final json = (raw.isEmpty) ? null : (jsonDecode(raw) as Map<String, dynamic>);
        if (json == null) continue;

        final mediaPath = sc.path.substring(0, sc.path.length - '.pml.json'.length);
        final mediaFile = File(mediaPath);
        if (!await mediaFile.exists()) continue;

        final rel = p.posix
            .joinAll(p.split(p.relative(mediaFile.path, from: paths!.filesDir.path)));

        final itemId = p.basenameWithoutExtension(mediaFile.path);

        final sha = (json['sha256'] as String?) ?? '';
        if (sha.isEmpty) continue;

        final originalName = (json['original_name'] as String?) ?? p.basename(mediaFile.path);
        final typeStr = (json['type'] as String?) ?? 'other';
        final type = switch (typeStr) {
          'video' => ItemType.video,
          'image' => ItemType.image,
          _ => ItemType.other,
        };

        final catName = LibraryFolders.safeSegment((json['category'] as String?) ?? 'Stash');
        final subName = LibraryFolders.safeSegment((json['subcategory'] as String?) ?? 'Unassigned');

        // Ensure category
        String catId;
        final catRows = await _db!.query('categories', where: 'name=?', whereArgs: [catName], limit: 1);
        if (catRows.isNotEmpty) {
          catId = catRows.first['id'] as String;
        } else {
          catId = _id();
          await _db!.insert('categories', {'id': catId, 'name': catName});
        }

        // Ensure subcategory
        String subId;
        final subRows = await _db!.query('subcategories', where: 'category_id=? AND name=?', whereArgs: [catId, subName], limit: 1);
        if (subRows.isNotEmpty) {
          subId = subRows.first['id'] as String;
        } else {
          subId = _id();
          await _db!.insert('subcategories', {'id': subId, 'category_id': catId, 'name': subName});
        }

        // Insert item if missing.
        final exists = await _db!.query('items', where: 'id=?', whereArgs: [itemId], limit: 1);
        if (exists.isEmpty) {
          final stat = await mediaFile.stat();
          await _db!.insert('items', {
            'id': itemId,
            'subcategory_id': subId,
            'type': typeStr,
            'original_name': originalName,
            'stored_rel_path': rel,
            'size_bytes': stat.size,
            'sha256': sha,
            'duration_ms': null,
            'created_at': stat.modified.millisecondsSinceEpoch,
            'is_duplicate': 0,
            'duplicate_of_id': null,
          });
        }

        // Apply tags
        final tagsList = (json['tags'] as List?)?.whereType<String>().toList() ?? const <String>[];
        for (final t in tagsList) {
          final tagId = await tags!.getOrCreateTagId(t);
          await _db!.insert('item_tags', {'item_id': itemId, 'tag_id': tagId}, conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        // Apply kv tags
        final kv = json['kv'];
        if (kv is Map) {
          for (final entry in kv.entries) {
            final key = entry.key?.toString();
            if (key == null || key.trim().isEmpty) continue;
            final keyId = await tags!.getOrCreateTagKeyId(key.trim());
            final values = (entry.value is List) ? (entry.value as List).whereType<String>().toList() : const <String>[];
            for (final v in values) {
              if (v.trim().isEmpty) continue;
              final valueId = await tags!.getOrCreateKeyValueId(keyId, v.trim());
              await _db!.insert('item_tag_key_values', {'item_id': itemId, 'key_value_id': valueId}, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        }
      } catch (_) {
        // Skip malformed sidecars.
      }
    }
  }


  // --- Folder structure + disk sync (categories/subcategories folders) ---

  Future<void> refreshFromDiskAndMigrate() async {
    if (!isReady) return;
    await _syncFolderNamesFromDisk();
    await refreshAll();
    await _ensureFolderMarkers();

    // Post-operation reconcile: if DB points to a path that does not exist
    // (e.g. interrupted move, manual folder changes), try to find the file on disk
    // by its stored filename and heal DB.
    await _reconcileStoredPathsAgainstDisk();

    await _migrateItemsToFolderStructure();
    await refreshAll();
  }

  Future<void> _reconcileStoredPathsAgainstDisk() async {
    if (!isReady) return;
    final filesDir = paths!.filesDir;

    // Build an index of actual media files in /Library/files (relative posix path by basename).
    final byBase = <String, String>{};
    await for (final ent in filesDir.list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;
      final name = p.basename(ent.path);
      if (name.endsWith('.pml.json') || name.endsWith('.part')) continue;
      // Store only the first occurrence for a basename.
      byBase.putIfAbsent(name, () {
        final rel = p.relative(ent.path, from: filesDir.path).replaceAll('\\', '/');
        return p.posix.joinAll(p.split(rel));
      });
    }

    final rows = await _db!.query('items', columns: ['id', 'stored_rel_path']);
    for (final r in rows) {
      final itemId = r['id'] as String;
      final relRaw = (r['stored_rel_path'] as String);
      final rel = relRaw.replaceAll('\\', '/');
      final abs = LibraryFolders.absPath(filesDir, rel);
      if (await File(abs).exists()) {
        // Normalize slashes for portability.
        if (relRaw != rel) {
          await _db!.update('items', {'stored_rel_path': rel}, where: 'id=?', whereArgs: [itemId]);
        }
        continue;
      }

      final base = p.posix.basename(rel);
      final found = byBase[base];
      if (found != null && found != rel) {
        await _db!.update('items', {'stored_rel_path': found}, where: 'id=?', whereArgs: [itemId]);
      }
    }
  }

  Future<void> _syncFolderNamesFromDisk() async {
    if (!isReady) return;
    final filesDir = paths!.filesDir;

    // Categories
    final catDirs = await LibraryFolders.scanCategoryFoldersById(filesDir);
    for (final e in catDirs.entries) {
      final catId = e.key;
      final dir = e.value;
      final folderName = p.basename(dir.path);
      final rows = await _db!.query('categories', where: 'id=?', whereArgs: [catId], limit: 1);
      if (rows.isEmpty) continue;
      final current = rows.first['name'] as String;
      if (current != folderName) {
        await _db!.update('categories', {'name': folderName}, where: 'id=?', whereArgs: [catId]);
      }

      // Subcategories under this category folder
      final subDirs = await LibraryFolders.scanSubcategoryFoldersById(dir);
      for (final se in subDirs.entries) {
        final subId = se.key;
        final subDir = se.value;
        final subFolderName = p.basename(subDir.path);
        final subRows = await _db!.query('subcategories', where: 'id=?', whereArgs: [subId], limit: 1);
        if (subRows.isEmpty) continue;
        final currentSub = subRows.first['name'] as String;
        if (currentSub != subFolderName) {
          await _db!.update('subcategories', {'name': subFolderName}, where: 'id=?', whereArgs: [subId]);
        }
      }
    }
  }

  Future<void> _ensureFolderMarkers() async {
    if (!isReady) return;
    final filesDir = paths!.filesDir;

    final cats = await _db!.query('categories');
    for (final c in cats) {
      final catId = c['id'] as String;
      final catName = c['name'] as String;
      await LibraryFolders.ensureCategoryFolder(filesDir: filesDir, categoryId: catId, categoryName: catName);

      final subs = await _db!.query('subcategories', where: 'category_id=?', whereArgs: [catId]);
      for (final s in subs) {
        final subId = s['id'] as String;
        final subName = s['name'] as String;
        await LibraryFolders.ensureSubcategoryFolder(
          filesDir: filesDir,
          categoryName: catName,
          subcategoryId: subId,
          subcategoryName: subName,
        );
      }
    }
  }

  Future<void> _migrateItemsToFolderStructure() async {
    if (!isReady) return;
    final filesDir = paths!.filesDir;

    final rows = await _db!.rawQuery('''
      SELECT i.id as item_id, i.stored_rel_path as rel, i.subcategory_id as sub_id,
             c.name as cat_name, s.name as sub_name
      FROM items i
      JOIN subcategories s ON s.id = i.subcategory_id
      JOIN categories c ON c.id = s.category_id
    ''');

    for (final r0 in rows) {
      final r = r0.cast<String, Object?>();
      final itemId = r['item_id'] as String;
      final storedRelRaw = (r['rel'] as String);
      final storedRel = storedRelRaw.replaceAll('\\', '/');
      final baseName = p.posix.basename(storedRel);
      final catName = r['cat_name'] as String;
      final subName = r['sub_name'] as String;

      final catFolder = LibraryFolders.safeSegment(catName);
      final subFolder = LibraryFolders.safeSegment(subName);
      final expectedRel = p.posix.join(catFolder, subFolder, baseName);

      if (storedRel != expectedRel) {
        final src = File(LibraryFolders.absPath(filesDir, storedRel));
        final dest = File(LibraryFolders.absPath(filesDir, expectedRel));

        if (await src.exists()) {
          await dest.parent.create(recursive: true);
          try {
            // Best-effort move (same drive).
            await src.rename(dest.path);
          } catch (_) {
            await _copyFileAtomic(src, dest);
            try { await src.delete(); } catch (_) {}
          }
        }

        // Always normalize DB path to expectedRel (even if src missing),
        // so future operations point to the intended structure.
        await _db!.update('items', {'stored_rel_path': expectedRel}, where: 'id=?', whereArgs: [itemId]);
      } else if (storedRelRaw != storedRel) {
        // Normalize slashes for portability.
        await _db!.update('items', {'stored_rel_path': storedRel}, where: 'id=?', whereArgs: [itemId]);
      }
    }
  }

  Future<void> _copyFileAtomic(File source, File dest) async {
    await dest.parent.create(recursive: true);
    final tmp = File(dest.path + '.part');
    if (await tmp.exists()) {
      try { await tmp.delete(); } catch (_) {}
    }
    final sink = tmp.openWrite();
    try {
      await source.openRead().pipe(sink);
    } finally {
      await sink.close();
    }
    await tmp.rename(dest.path);
  }

  // --- Export whole folders ---

  Future<int> exportCurrentSubcategoryToFolder(String destRoot) async {
    if (!isReady || selectedCategoryId == null || selectedSubcategoryId == null) return 0;
    return exportSubcategoryToFolder(
      categoryId: selectedCategoryId!,
      subcategoryId: selectedSubcategoryId!,
      destRoot: destRoot,
    );
  }

  Future<int> exportSubcategoryToFolder({
    required String categoryId,
    required String subcategoryId,
    required String destRoot,
  }) async {
    if (!isReady) return 0;
    final cat = _categoryList.firstWhere((c) => c.id == categoryId);
    final sub = subcategoriesFor(categoryId).firstWhere((s) => s.id == subcategoryId);

    final outDir = Directory(p.join(destRoot, LibraryFolders.safeSegment(cat.name), LibraryFolders.safeSegment(sub.name)));
    await outDir.create(recursive: true);

    final toExport = await items!.listItemsInSubcategory(subcategoryId, tagIds: const []);
    int ok = 0;

    for (final item in toExport) {
      final src = File(LibraryFolders.absPath(paths!.filesDir, item.storedRelPath.replaceAll('\\', '/')));
      if (!await src.exists()) continue;

      final destPath = _uniquePath(p.join(outDir.path, item.originalName));
      await src.copy(destPath);
      ok++;
    }
    return ok;
  }

  Future<int> exportCategoryToFolder({
    required String categoryId,
    required String destRoot,
  }) async {
    if (!isReady) return 0;
    final subs = subcategoriesFor(categoryId);
    int ok = 0;
    for (final s in subs) {
      ok += await exportSubcategoryToFolder(categoryId: categoryId, subcategoryId: s.id, destRoot: destRoot);
    }
    return ok;
  }

  String _uniquePath(String basePath) {
    if (!File(basePath).existsSync()) return basePath;
    final dir = p.dirname(basePath);
    final name = p.basenameWithoutExtension(basePath);
    final ext = p.extension(basePath);
    int i = 1;
    while (true) {
      final cand = p.join(dir, '$name ($i)$ext');
      if (!File(cand).existsSync()) return cand;
      i++;
    }
  }


}