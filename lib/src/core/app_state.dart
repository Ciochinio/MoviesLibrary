import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db.dart';
import 'models.dart';
import 'portable_paths.dart';
import 'repositories.dart';
import 'app_settings.dart';

class AppState extends ChangeNotifier {
  PortablePaths? paths;
  AppDb? _appDb;
  Database? _db;

  CategoryRepo? categories;
  TagRepo? tags;
  ItemRepo? items;
  NoteRepo? notes;


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

  String? stashCategoryId;
  String? stashSubcategoryId; // default "Do przypisania"

  bool get isReady => _db != null && paths != null;

  List<Category> get categoryList => _categoryList;
  List<Subcategory> subcategoriesFor(String categoryId) => _subByCat[categoryId] ?? [];
  List<Tag> get tagList => _tagList;

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
    final res = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Wybierz folder Library (lub utwórz nowy)');
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

    await _ensureDefaults();
    await refreshAll();

    // default selection: stash
    selectedCategoryId = stashCategoryId;
    selectedSubcategoryId = stashSubcategoryId;
    notifyListeners();
  }

  Future<void> _ensureDefaults() async {
    final cats = await _db!.query('categories');
    if (cats.isNotEmpty) return;

    final defaults = ['Dramat', 'Komedia', 'Akcja', 'Aktor', 'Aktorka', 'Reżyser', 'Stash'];
    for (final name in defaults) {
      await _db!.insert('categories', {'id': _id(), 'name': name});
    }

    final stashRows = await _db!.query('categories', where: 'name=?', whereArgs: ['Stash'], limit: 1);
    final stashId = stashRows.first['id'] as String;

    await _db!.insert('subcategories', {'id': _id(), 'category_id': stashId, 'name': 'Do przypisania'});
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toString() +
      '-' +
      (DateTime.now().millisecondsSinceEpoch % 1000).toString();

  Future<void> refreshAll() async {
    if (!isReady) return;
    _categoryList = await categories!.listCategories();
    _subByCat.clear();
    for (final c in _categoryList) {
      _subByCat[c.id] = await categories!.listSubcategories(c.id);
    }
    _tagList = await tags!.listTags();

    stashCategoryId = _categoryList
        .firstWhere((c) => c.name.toLowerCase() == 'stash', orElse: () => _categoryList.first)
        .id;
    final stashSubs = _subByCat[stashCategoryId!] ?? [];
    stashSubcategoryId = stashSubs.isNotEmpty ? stashSubs.first.id : null;

    notifyListeners();
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

  Future<void> createCategory(String name) async {
    await categories!.createCategory(name);
    await refreshAll();
  }

  Future<void> renameCategory(String id, String newName) async {
    await categories!.renameCategory(id, newName);
    await refreshAll();
  }

  Future<void> deleteCategoryMoveToStash(String id) async {
    await categories!.deleteCategoryMoveItems(id, stashSubcategoryId!);
    await refreshAll();
    selectedCategoryId = stashCategoryId;
    selectedSubcategoryId = stashSubcategoryId;
    notifyListeners();
  }

  Future<void> createSubcategory(String categoryId, String name) async {
    await categories!.createSubcategory(categoryId, name);
    await refreshAll();
  }

  Future<void> renameSubcategory(String id, String newName) async {
    await categories!.renameSubcategory(id, newName);
    await refreshAll();
  }

  Future<void> deleteSubcategoryMoveToStash(String subId) async {
    await categories!.deleteSubcategoryMoveItems(subId, stashSubcategoryId!);
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
    notifyListeners();
    return (inserted: res.item, existingDuplicate: res.duplicateOf, sha256: hash);
  }


Future<String> _hashFile(File f) async {
  final digest = await sha256.bind(f.openRead()).first;
  return digest.toString();
}

  Future<void> moveSelectedItems(String newSubcategoryId) async {
    if (selectedItemIds.isEmpty) return;
    await items!.bulkMove(selectedItemIds.toList(), newSubcategoryId);
    clearItemSelection();
    notifyListeners();
  }

  Future<void> bulkAddTagToSelected(String tagId) async {
    if (selectedItemIds.isEmpty) return;
    await items!.bulkAddTag(selectedItemIds.toList(), tagId);
    notifyListeners();
  }

  Future<void> bulkRemoveTagFromSelected(String tagId) async {
    if (selectedItemIds.isEmpty) return;
    await items!.bulkRemoveTag(selectedItemIds.toList(), tagId);
    notifyListeners();
  }

    Future<({List<MediaItem> deleted, List<MediaItem> failed})> deleteSelectedItems(List<MediaItem> loadedItems) async {
    if (selectedItemIds.isEmpty) return (deleted: <MediaItem>[], failed: <MediaItem>[]);

    final toDelete = loadedItems.where((i) => selectedItemIds.contains(i.id)).toList();
    final res = await items!.deleteItems(toDelete);

    // Remove successfully deleted from selection; keep failed selected so user can retry.
    for (final it in res.deleted) {
      selectedItemIds.remove(it.id);
    }
    notifyListeners();
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

  Future<({List<MediaItem> deleted, List<MediaItem> failed})> deleteOneItem(MediaItem item) async {
    final res = await items!.deleteItems([item]);
    notifyListeners();
    return res;
  }

}
