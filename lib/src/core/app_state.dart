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

class AppState extends ChangeNotifier {
  PortablePaths? paths;
  AppDb? _appDb;
  Database? _db;

  CategoryRepo? categories;
  TagRepo? tags;
  ItemRepo? items;
  NoteRepo? notes;

  // UI state
  String? selectedCategoryId;
  String? selectedSubcategoryId;
  final Set<String> selectedTagIds = {};
  final Set<String> selectedItemIds = {}; // bulk selection

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
    selectedCategoryId = categoryId;
    selectedSubcategoryId = subcategoryId;
    selectedItemIds.clear();
    notifyListeners();
  }

  void toggleTagFilter(String tagId) {
    if (selectedTagIds.contains(tagId)) {
      selectedTagIds.remove(tagId);
    } else {
      selectedTagIds.add(tagId);
    }
    notifyListeners();
  }

  void clearTagFilters() {
    selectedTagIds.clear();
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

  Future<List<MediaItem>> loadCurrentItems() async {
    if (!isReady || selectedSubcategoryId == null) return [];
    return await items!.listItemsInSubcategory(selectedSubcategoryId!, tagIds: selectedTagIds.toList());
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
    selectedTagIds.remove(id);
    await refreshAll();
  }

  Future<({MediaItem? inserted, MediaItem? existingDuplicate})> importSingleWithDuplicateDecision({
    required File source,
    required String targetSubcategoryId,
    required bool addDuplicateAsSeparateFile,
  }) async {
    if (!isReady) return (inserted: null, existingDuplicate: null);

    // Pre-check for UI decision; import will re-check too.
    final existing = await items!.findByHash(await _hashFile(source));
    if (existing != null && !addDuplicateAsSeparateFile) {
      return (inserted: null, existingDuplicate: existing);
    }

    final res = await items!.importFile(
      source: source,
      targetSubcategoryId: targetSubcategoryId,
      forceAddDuplicateAsSeparateFile: addDuplicateAsSeparateFile,
      stashSubcategoryId: stashSubcategoryId!,
    );
    notifyListeners();
    return (inserted: res.item, existingDuplicate: res.duplicateOf);
  }

  Future<String> _hashFile(File f) async {
    final bytes = await f.readAsBytes();
    return sha256.convert(bytes).toString();
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

  Future<void> deleteSelectedItems(List<MediaItem> loadedItems) async {
    if (selectedItemIds.isEmpty) return;
    final toDelete = loadedItems.where((i) => selectedItemIds.contains(i.id)).toList();
    await items!.deleteItems(toDelete);
    clearItemSelection();
    notifyListeners();
  }
}
