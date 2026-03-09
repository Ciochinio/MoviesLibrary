import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'app_settings.dart';
import 'library_folders.dart';

const _uuid = Uuid();


Future<String> _sha256HexOfFile(File f) async {
  final digest = await sha256.bind(f.openRead()).first;
  return digest.toString();
}

Future<void> _copyFileStreaming(File source, File dest) async {
  await dest.parent.create(recursive: true);
  final sink = dest.openWrite();
  try {
    await source.openRead().pipe(sink);
  } finally {
    await sink.close();
  }
}


Future<void> _copyFileStreamingAtomic(File source, File dest) async {
  await dest.parent.create(recursive: true);
  final tmp = File(dest.path + '.part');
  // Best-effort cleanup if a previous interrupted copy left a temp file.
  if (await tmp.exists()) {
    try { await tmp.delete(); } catch (_) {}
  }
  final sink = tmp.openWrite();
  try {
    await source.openRead().pipe(sink);
  } catch (e) {
    // Ensure temp file is not left open/locked.
    rethrow;
  } finally {
    await sink.close();
  }

  // Rename temp file into place (same directory => practical atomicity).
  await tmp.rename(dest.path);
}

ItemType _guessType(String filePath) {
  final ext = p.extension(filePath).toLowerCase();
  if (['.mp4', '.mkv', '.mov', '.avi', '.webm'].contains(ext)) return ItemType.video;
  if (['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'].contains(ext)) return ItemType.image;
  return ItemType.other;
}

String _itemTypeToDb(ItemType t) => switch (t) { ItemType.video => 'video', ItemType.image => 'image', ItemType.other => 'other' };
ItemType _itemTypeFromDb(String s) => switch (s) { 'video' => ItemType.video, 'image' => ItemType.image, _ => ItemType.other };

class CategoryRepo {
  final Database db;
  CategoryRepo(this.db);

  Future<List<Category>> listCategories() async {
    final rows = await db.query('categories', orderBy: 'sort_order ASC, name COLLATE NOCASE');
    return rows.map((r) => Category(
      id: r['id'] as String,
      name: r['name'] as String,
      description: (r['description'] as String?) ?? '',
      sortOrder: (r['sort_order'] as int?) ?? 0,
    )).toList();
  }

  Future<List<Subcategory>> listSubcategories(String categoryId) async {
    final rows = await db.query('subcategories', where: 'category_id=?', whereArgs: [categoryId], orderBy: 'sort_order ASC, name COLLATE NOCASE');
    return rows.map((r) => Subcategory(
      id: r['id'] as String,
      categoryId: r['category_id'] as String,
      name: r['name'] as String,
      description: (r['description'] as String?) ?? '',
      sortOrder: (r['sort_order'] as int?) ?? 0,
    )).toList();
  }

  Future<Subcategory?> getSubcategory(String subcategoryId) async {
    final rows = await db.query('subcategories', where: 'id=?', whereArgs: [subcategoryId], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Subcategory(
      id: r['id'] as String,
      categoryId: r['category_id'] as String,
      name: r['name'] as String,
      description: (r['description'] as String?) ?? '',
      sortOrder: (r['sort_order'] as int?) ?? 0,
    );
  }

  Future<Category?> getCategory(String categoryId) async {
    final rows = await db.query('categories', where: 'id=?', whereArgs: [categoryId], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Category(
      id: r['id'] as String,
      name: r['name'] as String,
      description: (r['description'] as String?) ?? '',
      sortOrder: (r['sort_order'] as int?) ?? 0,
    );
  }

  Future<void> updateCategoryDescription(String id, String description) async {
    await db.update('categories', {'description': description}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> updateSubcategoryDescription(String id, String description) async {
    await db.update('subcategories', {'description': description}, where: 'id=?', whereArgs: [id]);
  }

  Future<Category> createCategory(String name) async {
    final id = _uuid.v4();
    final safe = LibraryFolders.safeSegment(name);
    final maxRows = await db.rawQuery('SELECT MAX(sort_order) as m FROM categories');
    final maxOrder = (maxRows.first['m'] as int?) ?? 0;
    await db.insert('categories', {'id': id, 'name': safe, 'sort_order': maxOrder + 1});
    return Category(id: id, name: safe, sortOrder: maxOrder + 1);
  }

  Future<void> renameCategory(String id, String newName) async {
    final safe = LibraryFolders.safeSegment(newName);
    await db.update('categories', {'name': safe}, where: 'id=?', whereArgs: [id]);
  }

  Future<Subcategory> createSubcategory(String categoryId, String name) async {
    final id = _uuid.v4();
    final safe = LibraryFolders.safeSegment(name);
    final maxRows = await db.rawQuery('SELECT MAX(sort_order) as m FROM subcategories WHERE category_id=?', [categoryId]);
    final maxOrder = (maxRows.first['m'] as int?) ?? 0;
    await db.insert('subcategories', {'id': id, 'category_id': categoryId, 'name': safe, 'sort_order': maxOrder + 1});
    return Subcategory(id: id, categoryId: categoryId, name: safe, sortOrder: maxOrder + 1);
  }

  Future<void> renameSubcategory(String id, String newName) async {
    final safe = LibraryFolders.safeSegment(newName);
    await db.update('subcategories', {'name': safe}, where: 'id=?', whereArgs: [id]);
  }

  /// Reorder categories: pass the full list of category IDs in their new order.
  Future<void> reorderCategories(List<String> orderedIds) async {
    await db.transaction((txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update('categories', {'sort_order': i}, where: 'id=?', whereArgs: [orderedIds[i]]);
      }
    });
  }

  /// Reorder subcategories within a category: pass list of subcategory IDs in new order.
  Future<void> reorderSubcategories(List<String> orderedIds) async {
    await db.transaction((txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update('subcategories', {'sort_order': i}, where: 'id=?', whereArgs: [orderedIds[i]]);
      }
    });
  }

  // ─── Auto-tags per subcategory ──────────────

  Future<Set<String>> getAutoTagIds(String subcategoryId) async {
    final rows = await db.query('subcategory_auto_tags', where: 'subcategory_id=?', whereArgs: [subcategoryId]);
    return rows.map((r) => r['tag_id'] as String).toSet();
  }

  Future<Set<String>> getAutoKeyValueIds(String subcategoryId) async {
    final rows = await db.query('subcategory_auto_key_values', where: 'subcategory_id=?', whereArgs: [subcategoryId]);
    return rows.map((r) => r['key_value_id'] as String).toSet();
  }

  Future<void> setAutoTags(String subcategoryId, Set<String> tagIds, Set<String> keyValueIds) async {
    await db.transaction((txn) async {
      await txn.delete('subcategory_auto_tags', where: 'subcategory_id=?', whereArgs: [subcategoryId]);
      await txn.delete('subcategory_auto_key_values', where: 'subcategory_id=?', whereArgs: [subcategoryId]);
      for (final tagId in tagIds) {
        await txn.insert('subcategory_auto_tags', {'subcategory_id': subcategoryId, 'tag_id': tagId}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final kvId in keyValueIds) {
        await txn.insert('subcategory_auto_key_values', {'subcategory_id': subcategoryId, 'key_value_id': kvId}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> clearAutoTags(String subcategoryId) async {
    await db.delete('subcategory_auto_tags', where: 'subcategory_id=?', whereArgs: [subcategoryId]);
    await db.delete('subcategory_auto_key_values', where: 'subcategory_id=?', whereArgs: [subcategoryId]);
  }

  /// Returns true if this subcategory has any auto-tags configured.
  Future<bool> hasAutoTags(String subcategoryId) async {
    final t = await db.rawQuery('SELECT COUNT(*) as c FROM subcategory_auto_tags WHERE subcategory_id=?', [subcategoryId]);
    final k = await db.rawQuery('SELECT COUNT(*) as c FROM subcategory_auto_key_values WHERE subcategory_id=?', [subcategoryId]);
    return ((t.first['c'] as int?) ?? 0) > 0 || ((k.first['c'] as int?) ?? 0) > 0;
  }

  /// Deletes subcategory and moves its items to stashSubcategoryId.
  Future<void> deleteSubcategoryMoveItems(String subcategoryId, String stashSubcategoryId) async {
    await db.transaction((txn) async {
      await txn.update('items', {'subcategory_id': stashSubcategoryId}, where: 'subcategory_id=?', whereArgs: [subcategoryId]);
      await txn.delete('subcategories', where: 'id=?', whereArgs: [subcategoryId]);
    });
  }

  /// Deletes a category and all its subcategories, moving items to stashSubcategoryId.
  Future<void> deleteCategoryMoveItems(String categoryId, String stashSubcategoryId) async {
    await db.transaction((txn) async {
      final subs = await txn.query('subcategories', columns: ['id'], where: 'category_id=?', whereArgs: [categoryId]);
      for (final s in subs) {
        await txn.update('items', {'subcategory_id': stashSubcategoryId}, where: 'subcategory_id=?', whereArgs: [s['id']]);
      }
      await txn.delete('subcategories', where: 'category_id=?', whereArgs: [categoryId]);
      await txn.delete('categories', where: 'id=?', whereArgs: [categoryId]);
    });
  }
}

class TagRepo {
  final Database db;
  TagRepo(this.db);

Future<List<Tag>> listTags() async {
  final rows = await db.query('tags', orderBy: 'sort_order ASC, name COLLATE NOCASE');
  return rows.map((r) => Tag(
    id: r['id'] as String,
    name: r['name'] as String,
    description: (r['description'] as String?) ?? '',
    sortOrder: (r['sort_order'] as int?) ?? 0,
    groupId: r['group_id'] as String?,
  )).toList();
}

  Future<Tag> createTag(String name, {String description = ''}) async {
    final id = _uuid.v4();
    // Get max sort_order and add 1
    final maxRows = await db.rawQuery('SELECT MAX(sort_order) as max_order FROM tags');
    final maxOrder = (maxRows.first['max_order'] as int?) ?? 0;
    final sortOrder = maxOrder + 1;
    
    await db.insert('tags', {
      'id': id,
      'name': name,
      'description': description,
      'sort_order': sortOrder,
    });
    return Tag(id: id, name: name, description: description, sortOrder: sortOrder);
  }

  Future<void> renameTag(String id, String newName) async {
    await db.update('tags', {'name': newName}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> updateTagDescription(String id, String description) async {
    await db.update('tags', {'description': description}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> moveTagUp(String id) async {
    // 1. Normalize sort_order values (fixes the all-zero bug)
    await _normalizeTagSortOrders();
    // 2. Re-read after normalization
    final tags = await listTags();
    final index = tags.indexWhere((t) => t.id == id);
    if (index <= 0) return; // Already at top or not found
    
    // Swap sort_order with previous item
    final current = tags[index];
    final previous = tags[index - 1];
    
    await db.transaction((txn) async {
      await txn.update('tags', {'sort_order': previous.sortOrder}, where: 'id=?', whereArgs: [current.id]);
      await txn.update('tags', {'sort_order': current.sortOrder}, where: 'id=?', whereArgs: [previous.id]);
    });
  }

  Future<void> moveTagDown(String id) async {
    await _normalizeTagSortOrders();
    final tags = await listTags();
    final index = tags.indexWhere((t) => t.id == id);
    if (index < 0 || index >= tags.length - 1) return; // Already at bottom or not found
    
    final current = tags[index];
    final next = tags[index + 1];
    
    await db.transaction((txn) async {
      await txn.update('tags', {'sort_order': next.sortOrder}, where: 'id=?', whereArgs: [current.id]);
      await txn.update('tags', {'sort_order': current.sortOrder}, where: 'id=?', whereArgs: [next.id]);
    });
  }

  /// Reorder simple tags: pass the full list of tag IDs in their new order.
  Future<void> reorderTags(List<String> orderedIds) async {
    await db.transaction((txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update('tags', {'sort_order': i}, where: 'id=?', whereArgs: [orderedIds[i]]);
      }
    });
  }

  /// Ensures every tag has a unique, sequential sort_order.
  Future<void> _normalizeTagSortOrders() async {
    final tags = await db.query('tags', orderBy: 'sort_order ASC, name COLLATE NOCASE');
    for (int i = 0; i < tags.length; i++) {
      final current = (tags[i]['sort_order'] as int?) ?? 0;
      if (current != i) {
        await db.update('tags', {'sort_order': i}, where: 'id=?', whereArgs: [tags[i]['id']]);
      }
    }
  }

  Future<int> countTagUsage(String tagId) async {
    final rows = await db.rawQuery('SELECT COUNT(*) as c FROM item_tags WHERE tag_id=?', [tagId]);
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> deleteTag(String tagId) async {
    await db.transaction((txn) async {
      await txn.delete('item_tags', where: 'tag_id=?', whereArgs: [tagId]);
      await txn.delete('tags', where: 'id=?', whereArgs: [tagId]);
    });
  }

  // ----------------------
  // Custom Tags (formerly Key:Value tags)
  // ----------------------
  Future<List<TagKey>> listTagKeys() async {
    final rows = await db.query('tag_keys', orderBy: 'sort_order ASC, key COLLATE NOCASE');
    return rows
        .map((r) => TagKey(
              id: r['id'] as String,
              key: r['key'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
              description: (r['description'] as String?) ?? '',
              sortOrder: (r['sort_order'] as int?) ?? 0,
              keyType: (r['type'] as String?) == 'search' ? TagKeyType.search : TagKeyType.chips,
            ))
        .toList();
  }

  Future<TagKey> createTagKey(String key, {String description = '', TagKeyType keyType = TagKeyType.chips}) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    // Get max sort_order and add 1
    final maxRows = await db.rawQuery('SELECT MAX(sort_order) as max_order FROM tag_keys');
    final maxOrder = (maxRows.first['max_order'] as int?) ?? 0;
    final sortOrder = maxOrder + 1;
    
    await db.insert('tag_keys', {
      'id': id,
      'key': key,
      'created_at': now,
      'description': description,
      'sort_order': sortOrder,
      'type': keyType == TagKeyType.search ? 'search' : 'chips',
    });
    return TagKey(
      id: id,
      key: key,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      description: description,
      sortOrder: sortOrder,
      keyType: keyType,
    );
  }

  Future<void> renameTagKey(String id, String newKey) async {
    await db.update('tag_keys', {'key': newKey}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> updateTagKeyDescription(String id, String description) async {
    await db.update('tag_keys', {'description': description}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> updateTagKeySortOrder(String id, int sortOrder) async {
    await db.update('tag_keys', {'sort_order': sortOrder}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> moveTagKeyUp(String id) async {
    await _normalizeTagKeySortOrders();
    final keys = await listTagKeys();
    final index = keys.indexWhere((k) => k.id == id);
    if (index <= 0) return; // Already at top or not found
    
    final current = keys[index];
    final previous = keys[index - 1];
    
    await db.transaction((txn) async {
      await txn.update('tag_keys', {'sort_order': previous.sortOrder}, where: 'id=?', whereArgs: [current.id]);
      await txn.update('tag_keys', {'sort_order': current.sortOrder}, where: 'id=?', whereArgs: [previous.id]);
    });
  }

  Future<void> moveTagKeyDown(String id) async {
    await _normalizeTagKeySortOrders();
    final keys = await listTagKeys();
    final index = keys.indexWhere((k) => k.id == id);
    if (index < 0 || index >= keys.length - 1) return; // Already at bottom or not found
    
    final current = keys[index];
    final next = keys[index + 1];
    
    await db.transaction((txn) async {
      await txn.update('tag_keys', {'sort_order': next.sortOrder}, where: 'id=?', whereArgs: [current.id]);
      await txn.update('tag_keys', {'sort_order': current.sortOrder}, where: 'id=?', whereArgs: [next.id]);
    });
  }

  /// Reorder custom tag keys: pass the full list of key IDs in their new order.
  Future<void> reorderTagKeys(List<String> orderedIds) async {
    await db.transaction((txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update('tag_keys', {'sort_order': i}, where: 'id=?', whereArgs: [orderedIds[i]]);
      }
    });
  }

  /// Reorder values within a key: pass the full list of value IDs in their new order.
  Future<void> reorderTagKeyValues(List<String> orderedIds) async {
    await db.transaction((txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update('tag_key_values', {'sort_order': i}, where: 'id=?', whereArgs: [orderedIds[i]]);
      }
    });
  }
 Future<List<TagGroup>> listTagGroups() async {
  final rows = await db.query('tag_groups', orderBy: 'sort_order ASC, name COLLATE NOCASE');
  return rows.map((r) => TagGroup(
    id: r['id'] as String,
    name: r['name'] as String,
    sortOrder: (r['sort_order'] as int?) ?? 0,
  )).toList();
}

Future<TagGroup> createTagGroup(String name) async {
  final id = _uuid.v4();
  final maxRows = await db.rawQuery('SELECT MAX(sort_order) as m FROM tag_groups');
  final maxOrder = (maxRows.first['m'] as int?) ?? 0;
  await db.insert('tag_groups', {'id': id, 'name': name, 'sort_order': maxOrder + 1});
  return TagGroup(id: id, name: name, sortOrder: maxOrder + 1);
}

Future<void> renameTagGroup(String id, String newName) async {
  await db.update('tag_groups', {'name': newName}, where: 'id=?', whereArgs: [id]);
}

Future<void> deleteTagGroup(String groupId) async {
  await db.update('tags', {'group_id': null}, where: 'group_id=?', whereArgs: [groupId]);
  await db.delete('tag_groups', where: 'id=?', whereArgs: [groupId]);
}

Future<void> reorderTagGroups(List<String> orderedIds) async {
  await db.transaction((txn) async {
    for (int i = 0; i < orderedIds.length; i++) {
      await txn.update('tag_groups', {'sort_order': i}, where: 'id=?', whereArgs: [orderedIds[i]]);
    }
  });
}

Future<void> setTagGroup(String tagId, String? groupId) async {
  await db.update('tags', {'group_id': groupId}, where: 'id=?', whereArgs: [tagId]);
}
  /// Ensures every tag key has a unique, sequential sort_order.
  Future<void> _normalizeTagKeySortOrders() async {
    final keys = await db.query('tag_keys', orderBy: 'sort_order ASC, key COLLATE NOCASE');
    for (int i = 0; i < keys.length; i++) {
      final current = (keys[i]['sort_order'] as int?) ?? 0;
      if (current != i) {
        await db.update('tag_keys', {'sort_order': i}, where: 'id=?', whereArgs: [keys[i]['id']]);
      }
    }
  }

  Future<int> countTagKeyUsage(String keyId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) as c FROM item_tag_key_values itk '
      'JOIN tag_key_values kv ON kv.id = itk.key_value_id '
      'WHERE kv.key_id=?',
      [keyId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> deleteTagKey(String keyId) async {
    // Cascades to values and mappings.
    await db.delete('tag_keys', where: 'id=?', whereArgs: [keyId]);
  }

  Future<List<TagKeyValue>> listValuesForKey(String keyId) async {
    final rows = await db.rawQuery(
      'SELECT kv.id, kv.key_id, k.key as key, kv.value, kv.description, kv.created_at '
      'FROM tag_key_values kv JOIN tag_keys k ON k.id = kv.key_id '
      'WHERE kv.key_id=? '
      'ORDER BY kv.sort_order ASC, kv.value COLLATE NOCASE',
      [keyId],
    );
    return rows
        .map((r) => TagKeyValue(
              id: r['id'] as String,
              keyId: r['key_id'] as String,
              key: r['key'] as String,
              value: r['value'] as String,
              description: (r['description'] as String?) ?? '',
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
            ))
        .toList();
  }

  Future<TagKeyValue> createValue(String keyId, String value, {String description = ''}) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxRows = await db.rawQuery('SELECT MAX(sort_order) as m FROM tag_key_values WHERE key_id=?', [keyId]);
    final maxOrder = (maxRows.first['m'] as int?) ?? 0;
    await db.insert('tag_key_values', {
      'id': id,
      'key_id': keyId,
      'value': value,
      'description': description,
      'created_at': now,
      'sort_order': maxOrder + 1,
    });
    final keyRow = await db.query('tag_keys', where: 'id=?', whereArgs: [keyId], limit: 1);
    final keyName = keyRow.isEmpty ? '' : (keyRow.first['key'] as String);
    return TagKeyValue(
      id: id,
      keyId: keyId,
      key: keyName,
      value: value,
      description: description,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  Future<void> renameValue(String valueId, String newValue) async {
    await db.update('tag_key_values', {'value': newValue}, where: 'id=?', whereArgs: [valueId]);
  }

  Future<void> updateValueDescription(String valueId, String description) async {
    await db.update('tag_key_values', {'description': description}, where: 'id=?', whereArgs: [valueId]);
  }

  Future<int> countValueUsage(String valueId) async {
    final rows = await db.rawQuery('SELECT COUNT(*) as c FROM item_tag_key_values WHERE key_value_id=?', [valueId]);
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> deleteValue(String valueId) async {
    // Cascades to mappings.
    await db.delete('tag_key_values', where: 'id=?', whereArgs: [valueId]);
  }

  // Helpers for rebuild/import
  Future<String> getOrCreateTagId(String name) async {
    final existing = await db.query('tags', where: 'name=?', whereArgs: [name], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as String;
    final t = await createTag(name);
    return t.id;
  }

  /// Returns the key_id for a given key_value id, or null if not found.

  // ─── Name Order ──────────────────────────────────────────────────────────

  /// Returns the unified name order list (tag groups + tag keys interleaved).
  /// Entries not yet in name_order are appended at the end.
  Future<List<NameOrderEntry>> listNameOrder({
    required List<TagGroup> allGroups,
    required List<TagKey> allKeys,
  }) async {
    final rows = await db.query('name_order', orderBy: 'sort_order ASC');
    final entries = rows.map((r) => NameOrderEntry(
      id: r['id'] as String,
      type: (r['type'] as String) == 'tag_group' ? NameOrderEntryType.tagGroup : NameOrderEntryType.tagKey,
      sortOrder: r['sort_order'] as int,
    )).toList();

    // Collect IDs already in name_order
    final ordered = <NameOrderEntry>[...entries];
    final seenIds = entries.map((e) => e.id).toSet();

    // Append any groups/keys not yet in the table (new ones fall to the bottom)
    int next = (entries.isNotEmpty ? entries.last.sortOrder : 0) + 1;
    for (final g in allGroups) {
      if (!seenIds.contains(g.id)) {
        ordered.add(NameOrderEntry(id: g.id, type: NameOrderEntryType.tagGroup, sortOrder: next++));
      }
    }
    for (final k in allKeys) {
      if (!seenIds.contains(k.id)) {
        ordered.add(NameOrderEntry(id: k.id, type: NameOrderEntryType.tagKey, sortOrder: next++));
      }
    }
    return ordered;
  }

  Future<void> saveNameOrder(List<NameOrderEntry> entries) async {
    final batch = db.batch();
    batch.delete('name_order');
    for (int i = 0; i < entries.length; i++) {
      batch.insert('name_order', {
        'id': entries[i].id,
        'type': entries[i].type == NameOrderEntryType.tagGroup ? 'tag_group' : 'tag_key',
        'sort_order': i,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<String?> getKeyIdForValue(String keyValueId) async {
    final rows = await db.query('tag_key_values', columns: ['key_id'], where: 'id=?', whereArgs: [keyValueId], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['key_id'] as String?;
  }

  Future<String> getOrCreateTagKeyId(String key) async {
    final existing = await db.query('tag_keys', where: 'key=?', whereArgs: [key], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as String;
    final k = await createTagKey(key);
    return k.id;
  }

  Future<String> getOrCreateKeyValueId(String keyId, String value) async {
    final existing = await db.query(
      'tag_key_values',
      where: 'key_id=? AND value=?',
      whereArgs: [keyId, value],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as String;
    final kv = await createValue(keyId, value);
    return kv.id;
  }
}

class ItemRepo {
  final Database db;
  final Directory filesDir;
  ItemRepo(this.db, this.filesDir);

  // Sidecar file extension
  String _sidecarPathForAbs(String absMediaPath) => absMediaPath + '.pml.json';

  Future<void> _writeSidecarForItem(MediaItem item) async {
    // Fetch category/subcategory names + tags.
    final subInfo = await _getSubAndCategoryNames(item.subcategoryId);
    final simple = await listTagsForItem(item.id);
    final kv = await listKeyValuesForItem(item.id);

    final kvMap = <String, List<String>>{};
    for (final v in kv) {
      kvMap.putIfAbsent(v.key, () => <String>[]).add(v.value);
    }

    final meta = {
      'schema': 1,
      'sha256': item.sha256,
      'original_name': item.originalName,
      'type': _itemTypeToDb(item.type),
      'category': subInfo.categoryName,
      'subcategory': subInfo.subcategoryName,
      'tags': simple.map((t) => t.name).toList(),
      'kv': kvMap,
    };

    final abs = LibraryFolders.absPath(filesDir, item.storedRelPath);
    final sidecar = File(_sidecarPathForAbs(abs));
    await sidecar.parent.create(recursive: true);
    final tmp = File(sidecar.path + '.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(meta));
    await tmp.rename(sidecar.path);
  }


  Future<({String categoryName, String subcategoryName})> _getSubAndCategoryNames(String subcategoryId) async {
    final rows = await db.rawQuery(
      'SELECT c.name AS category_name, s.name AS subcategory_name '
      'FROM subcategories s '
      'JOIN categories c ON c.id = s.category_id '
      'WHERE s.id = ? '
      'LIMIT 1',
      [subcategoryId],
    );
    if (rows.isEmpty) {
      return (categoryName: 'Unknown', subcategoryName: 'Unknown');
    }
    final r = rows.first;
    return (
      categoryName: r['category_name'] as String,
      subcategoryName: r['subcategory_name'] as String,
    );
  }


  Future<MediaItem?> findByHash(String sha256hex) async {
    final rows = await db.query('items', where: 'sha256=?', whereArgs: [sha256hex], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return _rowToItem(r);
  }

  Future<List<MediaItem>> listItemsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery('SELECT * FROM items WHERE id IN ($placeholders)', ids);
    return rows.map((r) => _rowToItem(r.cast<String, Object?>())).toList();
  }

  Future<List<MediaItem>> listItemsInSubcategory(String subcategoryId, {List<String> tagIds = const []}) async {
    if (tagIds.isEmpty) {
      final rows = await db.query('items', where: 'subcategory_id=?', whereArgs: [subcategoryId], orderBy: 'created_at DESC');
      return rows.map(_rowToItem).toList();
    }

    // AND filter: item must have ALL selected tags
    final placeholders = List.filled(tagIds.length, '?').join(',');
    final sql = '''
      SELECT i.*
      FROM items i
      JOIN item_tags it ON it.item_id = i.id
      WHERE i.subcategory_id = ? AND it.tag_id IN ($placeholders)
      GROUP BY i.id
      HAVING COUNT(DISTINCT it.tag_id) = ?
      ORDER BY i.created_at DESC
    ''';
    final args = <Object?>[subcategoryId, ...tagIds, tagIds.length];
    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => _rowToItem(r.cast<String, Object?>())).toList();
  }

  /// Returns the set of item IDs (from the given list) that have zero tags.
  /// Used by the grid to show the untagged dot indicator without N+1 queries.
  Future<Set<String>> listUntaggedItemIds(List<String> itemIds) async {
    if (itemIds.isEmpty) return {};
    final placeholders = List.filled(itemIds.length, '?').join(',');
    final sql = '''
      SELECT id FROM items
      WHERE id IN ($placeholders)
      AND NOT EXISTS (SELECT 1 FROM item_tags WHERE item_id = items.id)
      AND NOT EXISTS (SELECT 1 FROM item_tag_key_values WHERE item_id = items.id)
    ''';
    final rows = await db.rawQuery(sql, itemIds);
    return rows.map((r) => r['id'] as String).toSet();
  }

  /// Count items in a subcategory that have no tags at all (simple tags + custom tags)
  Future<int> countUntaggedItems(String subcategoryId) async {
    final sql = '''
      SELECT COUNT(*) as count
      FROM items i
      WHERE i.subcategory_id = ?
      AND NOT EXISTS (SELECT 1 FROM item_tags WHERE item_id = i.id)
      AND NOT EXISTS (SELECT 1 FROM item_tag_key_values WHERE item_id = i.id)
    ''';
    final rows = await db.rawQuery(sql, [subcategoryId]);
    return (rows.first['count'] as int?) ?? 0;
  }


/// Global tag search across the whole library (all folders).
/// AND semantics: item must have ALL tagIds.
Future<List<MediaItem>> listItemsByTagsGlobal({required List<String> tagIds}) async {
  if (tagIds.isEmpty) return [];
  final placeholders = List.filled(tagIds.length, '?').join(',');
  final sql = '''
    SELECT i.*
    FROM items i
    JOIN item_tags it ON it.item_id = i.id
    WHERE it.tag_id IN ($placeholders)
    GROUP BY i.id
    HAVING COUNT(DISTINCT it.tag_id) = ?
    ORDER BY i.created_at DESC
  ''';
  final args = <Object?>[...tagIds, tagIds.length];
  final rows = await db.rawQuery(sql, args);
  return rows.map((r) => _rowToItem(r.cast<String, Object?>())).toList();
}

  Future<List<Tag>> listTagsForItem(String itemId) async {
    final rows = await db.rawQuery('''
      SELECT t.* FROM tags t
      JOIN item_tags it ON it.tag_id = t.id
      WHERE it.item_id = ?
      ORDER BY t.name COLLATE NOCASE
    ''', [itemId]);
    return rows.map((r) => Tag(id: r['id'] as String, name: r['name'] as String)).toList();
  }

  /// Builds a suggested filename from item tags following name_order.
  Future<String> suggestNameForItem(
    String itemId,
    String originalName, {
    required TagRepo tagRepo,
    required List<TagGroup> allGroups,
    required List<TagKey> allKeys,
    required List<Tag> allTags,
  }) async {
    final order = await tagRepo.listNameOrder(allGroups: allGroups, allKeys: allKeys);
    final simpleTagIds = await listTagIdsForItem(itemId);
    final kvValues = await listKeyValuesForItem(itemId);
    final kvByKeyId = <String, List<TagKeyValue>>{};
    for (final kv in kvValues) {
      kvByKeyId.putIfAbsent(kv.keyId, () => []).add(kv);
    }

    final parts = <String>[];
    for (final entry in order) {
      if (entry.type == NameOrderEntryType.tagGroup) {
        final groupTags = allTags
            .where((t) => t.groupId == entry.id && simpleTagIds.contains(t.id))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        parts.addAll(groupTags.map((t) => t.name));
      } else {
        final vals = kvByKeyId[entry.id] ?? [];
        parts.addAll(vals.map((v) => v.value));
      }
    }

    // Ungrouped simple tags appended at the end
    final ungroupedTags = allTags
        .where((t) => t.groupId == null && simpleTagIds.contains(t.id))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    parts.addAll(ungroupedTags.map((t) => t.name));

    if (parts.isEmpty) return originalName;
    final ext = originalName.contains('.') ? originalName.substring(originalName.lastIndexOf('.')) : '';
    return parts.join(' ') + ext;
  }

  Future<Set<String>> listTagIdsForItem(String itemId) async {
    final rows = await db.query('item_tags', columns: ['tag_id'], where: 'item_id=?', whereArgs: [itemId]);
    return rows.map((r) => r['tag_id'] as String).toSet();
  }

  // ----------------------
  // Key:Value tags on items
  // ----------------------
  Future<List<TagKeyValue>> listKeyValuesForItem(String itemId) async {
    final rows = await db.rawQuery(
      'SELECT kv.id, kv.key_id, k.key as key, kv.value, kv.created_at '
      'FROM item_tag_key_values itk '
      'JOIN tag_key_values kv ON kv.id = itk.key_value_id '
      'JOIN tag_keys k ON k.id = kv.key_id '
      'WHERE itk.item_id=? '
      'ORDER BY k.key COLLATE NOCASE, kv.value COLLATE NOCASE',
      [itemId],
    );
    return rows
        .map((r) => TagKeyValue(
              id: r['id'] as String,
              keyId: r['key_id'] as String,
              key: r['key'] as String,
              value: r['value'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
            ))
        .toList();
  }

  Future<Set<String>> listKeyValueIdsForItem(String itemId) async {
    final rows = await db.query('item_tag_key_values', columns: ['key_value_id'], where: 'item_id=?', whereArgs: [itemId]);
    return rows.map((r) => r['key_value_id'] as String).toSet();
  }

  Future<void> addKeyValueToItem(String itemId, String keyValueId) async {
    await db.insert(
      'item_tag_key_values',
      {'item_id': itemId, 'key_value_id': keyValueId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeKeyValueFromItem(String itemId, String keyValueId) async {
    await db.delete('item_tag_key_values', where: 'item_id=? AND key_value_id=?', whereArgs: [itemId, keyValueId]);
  }

  /// Writes/updates portable sidecar metadata for an item.
  Future<void> writeSidecarForItemId(String itemId) async {
    final rows = await db.query('items', where: 'id=?', whereArgs: [itemId], limit: 1);
    if (rows.isEmpty) return;
    await _writeSidecarForItem(_rowToItem(rows.first));
  }

  /// Global search with AND semantics across:
  /// - simpleTagIds (tags)
  /// - keyValueIds (tag_key_values)
  /// [minTagMatch] — minimum number of the combined tags an item must have.
  /// null / 0 means require ALL selected tags (original behaviour).
  Future<List<MediaItem>> searchItemsGlobal({
    required List<String> simpleTagIds,
    required List<String> keyValueIds,
    String? filename,
    int? minTagMatch,
  }) async {
    if (simpleTagIds.isEmpty && keyValueIds.isEmpty && (filename == null || filename.trim().isEmpty)) return [];

    final totalTags = simpleTagIds.length + keyValueIds.length;
    // effectiveMin: if minTagMatch is set and less than total, use it; else require all
    final effectiveMin = (minTagMatch != null && minTagMatch > 0 && minTagMatch < totalTags)
        ? minTagMatch
        : totalTags;

    final whereParts = <String>[];
    final args = <Object?>[];
    String joinSql = 'FROM items i';

    if (simpleTagIds.isNotEmpty) {
      final p1 = List.filled(simpleTagIds.length, '?').join(',');
      joinSql += ' JOIN item_tags it ON it.item_id = i.id';
      whereParts.add('it.tag_id IN ($p1)');
      args.addAll(simpleTagIds);
    }

    if (keyValueIds.isNotEmpty) {
      final p2 = List.filled(keyValueIds.length, '?').join(',');
      joinSql += ' JOIN item_tag_key_values itk ON itk.item_id = i.id';
      whereParts.add('itk.key_value_id IN ($p2)');
      args.addAll(keyValueIds);
    }

    if (filename != null && filename.trim().isNotEmpty) {
      whereParts.add('i.original_name LIKE ?');
      args.add('%${filename.trim()}%');
    }

    final whereSql = whereParts.isEmpty ? '' : ('WHERE ' + whereParts.join(' AND '));

    // Build unified count across both simple and kv joins, use >= for min-match
    final countParts = <String>[];
    if (simpleTagIds.isNotEmpty) countParts.add('COUNT(DISTINCT it.tag_id)');
    if (keyValueIds.isNotEmpty) countParts.add('COUNT(DISTINCT itk.key_value_id)');
    final countExpr = countParts.join(' + ');
    final havingSql = countParts.isNotEmpty ? 'HAVING $countExpr >= ?' : '';
    if (countParts.isNotEmpty) args.add(effectiveMin);

    final sql = '''
      SELECT i.*
      $joinSql
      $whereSql
      GROUP BY i.id
      $havingSql
      ORDER BY i.created_at DESC
    ''';

    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => _rowToItem(r.cast<String, Object?>())).toList();
  }

  // ----------------------
  // Move items (disk + DB) into a different subcategory
  // ----------------------
  Future<void> moveItemsToSubcategory(List<MediaItem> toMove, String newSubcategoryId) async {
    if (toMove.isEmpty) return;

    final destInfo = await _getSubAndCategoryNames(newSubcategoryId);
    final destCat = LibraryFolders.safeSegment(destInfo.categoryName);
    final destSub = LibraryFolders.safeSegment(destInfo.subcategoryName);

    for (final item in toMove) {
      final srcAbs = LibraryFolders.absPath(filesDir, item.storedRelPath);
      final srcFile = File(srcAbs);
      final fileName = p.posix.basename(item.storedRelPath);
      final newRel = p.posix.join(destCat, destSub, fileName);
      final dstAbs = LibraryFolders.absPath(filesDir, newRel);
      final dstFile = File(dstAbs);

      // Sidecar paths
      final srcSide = File(_sidecarPathForAbs(srcAbs));
      final dstSide = File(_sidecarPathForAbs(dstAbs));

      // Ensure destination directory.
      await dstFile.parent.create(recursive: true);

      // 1) Move media file first.
      bool movedByRename = false;
      try {
        try {
          await srcFile.rename(dstFile.path);
          movedByRename = true;
        } catch (_) {
          await _copyFileStreamingAtomic(srcFile, dstFile);
          // Only delete after DB commit below.
        }

        // 2) Update DB (subcategory_id + stored_rel_path + created_at reset so item sorts as newest)
        try {
          await db.update(
            'items',
            {
              'subcategory_id': newSubcategoryId,
              'stored_rel_path': newRel,
              'created_at': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id=?',
            whereArgs: [item.id],
          );
        } catch (e) {
          // Rollback file move as best-effort.
          try {
            if (movedByRename) {
              await dstFile.rename(srcFile.path);
            } else {
              // Copied: remove destination copy.
              if (await dstFile.exists()) await dstFile.delete();
            }
          } catch (_) {}
          rethrow;
        }

        // 3) If this was copy+delete, delete source now.
        if (!movedByRename) {
          try {
            if (await srcFile.exists()) await srcFile.delete();
          } catch (_) {}
        }

        // 4) Move sidecar if exists, otherwise regenerate in new location.
        if (await srcSide.exists()) {
          try {
            await dstSide.parent.create(recursive: true);
            await srcSide.rename(dstSide.path);
          } catch (_) {
            // fallback: regenerate
          }
        }

        // 5) Ensure sidecar reflects new folder metadata.
        await writeSidecarForItemId(item.id);
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<void> addTagToItem(String itemId, String tagId) async {
    await db.insert('item_tags', {'item_id': itemId, 'tag_id': tagId}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeTagFromItem(String itemId, String tagId) async {
    await db.delete('item_tags', where: 'item_id=? AND tag_id=?', whereArgs: [itemId, tagId]);
  }

  Future<void> bulkAddTag(List<String> itemIds, String tagId) async {
    await db.transaction((txn) async {
      for (final id in itemIds) {
        await txn.insert('item_tags', {'item_id': id, 'tag_id': tagId}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> bulkRemoveTag(List<String> itemIds, String tagId) async {
    await db.transaction((txn) async {
      for (final id in itemIds) {
        await txn.delete('item_tags', where: 'item_id=? AND tag_id=?', whereArgs: [id, tagId]);
      }
    });
  }

  /// Bulk add tags to all items in a subcategory
  Future<int> bulkAddTagToSubcategory(String subcategoryId, String tagId) async {
    final items = await listItemsInSubcategory(subcategoryId);
    if (items.isEmpty) return 0;
    
    await db.transaction((txn) async {
      for (final item in items) {
        await txn.insert('item_tags', {'item_id': item.id, 'tag_id': tagId}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    
    return items.length;
  }

  /// Bulk add key-value tags to all items in a subcategory
  Future<int> bulkAddKeyValueToSubcategory(String subcategoryId, String keyValueId) async {
    final items = await listItemsInSubcategory(subcategoryId);
    if (items.isEmpty) return 0;
    
    await db.transaction((txn) async {
      for (final item in items) {
        await txn.insert('item_tag_key_values', {'item_id': item.id, 'key_value_id': keyValueId}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    
    return items.length;
  }

  Future<void> bulkMove(List<String> itemIds, String newSubcategoryId) async {
    await db.transaction((txn) async {
      for (final id in itemIds) {
        await txn.update('items', {'subcategory_id': newSubcategoryId}, where: 'id=?', whereArgs: [id]);
      }
    });
  }

  /// Rename a media item (both in database and on disk)
  /// Returns true if successful, false if failed
  Future<bool> renameItem(MediaItem item, String newName) async {
    // Clean the new name (remove path separators, etc.)
    final safeName = newName.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
    if (safeName.isEmpty) return false;
    
    // Keep the original extension
    final oldExt = p.extension(item.originalName);
    final newExt = p.extension(safeName);
    final finalName = newExt.isEmpty ? '$safeName$oldExt' : safeName;
    
    // Build new paths
    final oldAbsPath = LibraryFolders.absPath(filesDir, item.storedRelPath);
    final oldFile = File(oldAbsPath);
    
    // New stored name uses same UUID but new filename
    final dir = p.dirname(item.storedRelPath);
    final storedName = p.basename(item.storedRelPath); // UUID-based filename
    final newStoredExt = p.extension(finalName);
    final uuid = p.basenameWithoutExtension(storedName);
    final newStoredName = '$uuid$newStoredExt';
    final newStoredRelPath = p.posix.join(dir, newStoredName);
    final newAbsPath = LibraryFolders.absPath(filesDir, newStoredRelPath);
    final newFile = File(newAbsPath);
    
    // Check if file exists
    if (!await oldFile.exists()) return false;
    
    try {
      // 1. Rename file on disk
      await oldFile.rename(newAbsPath);
      
      // 2. Update database
      await db.update(
        'items',
        {
          'original_name': finalName,
          'stored_rel_path': newStoredRelPath,
        },
        where: 'id=?',
        whereArgs: [item.id],
      );
      
      // 3. Update sidecar file
      final oldSidecar = File(_sidecarPathForAbs(oldAbsPath));
      final newSidecar = File(_sidecarPathForAbs(newAbsPath));
      if (await oldSidecar.exists()) {
        try {
          await oldSidecar.rename(newSidecar.path);
        } catch (_) {
          // Sidecar rename failed, not critical
        }
      }
      
      // Update the sidecar content with new name
      await writeSidecarForItemId(item.id);
      
      return true;
    } catch (e) {
      // If database update failed, try to rename file back
      try {
        if (await newFile.exists() && !await oldFile.exists()) {
          await newFile.rename(oldAbsPath);
        }
      } catch (_) {
        // Best effort rollback failed
      }
      return false;
    }
  }

  Future<({List<MediaItem> deleted, List<MediaItem> failed})> deleteItems(List<MediaItem> items) async {
    final deleted = <MediaItem>[];
    final failed = <MediaItem>[];

    // 1) Physical delete first (disk is the source of truth).
    for (final item in items) {
      final f = File(LibraryFolders.absPath(filesDir, item.storedRelPath));
      final sidecar = File(_sidecarPathForAbs(f.path));
      if (!await f.exists()) {
        // Treat missing file as "already deleted" and allow DB cleanup.
        // Also best-effort delete sidecar.
        try { if (await sidecar.exists()) await sidecar.delete(); } catch (_) {}
        deleted.add(item);
        continue;
      }
      try {
        await f.delete();
        try { if (await sidecar.exists()) await sidecar.delete(); } catch (_) {}
        deleted.add(item);
      } catch (_) {
        // Keep DB record so user can retry later.
        failed.add(item);
      }
    }

    // 2) DB cleanup only for successfully deleted (or missing) files.
    if (deleted.isNotEmpty) {
      await db.transaction((txn) async {
        for (final item in deleted) {
          await txn.delete('item_tags', where: 'item_id=?', whereArgs: [item.id]);
          await txn.delete('items', where: 'id=?', whereArgs: [item.id]);
        }
      });
    }

    return (deleted: deleted, failed: failed);
  }


Future<({MediaItem item, MediaItem? duplicateOf})> importFile({
  required File source,
  required String targetSubcategoryId,
  required bool forceAddDuplicateAsSeparateFile,
  required String stashSubcategoryId,
  required ImportMode importMode,
  String? precomputedSha256,
  MediaItem? preexistingDuplicate,
}) async {
  final hash = precomputedSha256 ?? await _sha256HexOfFile(source);

  final existing = preexistingDuplicate ?? await findByHash(hash);
  if (existing != null && !forceAddDuplicateAsSeparateFile) {
    // Caller should decide; return existing in duplicateOf slot but do not insert.
    return (item: existing, duplicateOf: existing);
  }

  final id = _uuid.v4();
  final type = _guessType(source.path);
  final originalName = p.basename(source.path);
  final sizeBytes = await source.length();

  final isDup = existing != null;
  final subId = (existing != null) ? stashSubcategoryId : targetSubcategoryId;

  // Stored file name: <uuid><ext>
  final ext = p.extension(source.path);
  final storedName = '$id$ext';

  // Folder structure under /Library/files matches category/subcategory names:
  //   <CategoryName>/<SubcategoryName>/<uuid.ext>
  final subInfo = await _getSubAndCategoryNames(subId);
  final catFolder = LibraryFolders.safeSegment(subInfo.categoryName);
  final subFolder = LibraryFolders.safeSegment(subInfo.subcategoryName);
  final storedRelPath = p.posix.join(catFolder, subFolder, storedName);

  final dest = File(LibraryFolders.absPath(filesDir, storedRelPath));

  // Copy/move the file in a crash-resilient way (Approach A: hash first, then decide, then transfer).
  // - For copy: stream to "<dest>.part" then rename into place.
  // - For move (same volume): rename to dest; if DB insert fails, best-effort rename back.
  // - For move (cross-volume): stream copy to "<dest>.part" -> rename; only then delete source.
  final sourcePathBeforeMove = source.path;
  var movedByRename = false;

  try {
    if (importMode == ImportMode.move) {
      // Try fast move (same volume).
      try {
        await source.rename(dest.path);
        movedByRename = true;
      } catch (_) {
        // Cross-volume or blocked: do atomic copy, then (after DB success) delete source.
        await _copyFileStreamingAtomic(source, dest);
      }
    } else {
      await _copyFileStreamingAtomic(source, dest);
    }

    final now = DateTime.now();

    try {
      await db.insert('items', {
        'id': id,
        'subcategory_id': subId,
        'type': _itemTypeToDb(type),
        'original_name': originalName,
        'stored_rel_path': storedRelPath,
        'size_bytes': sizeBytes,
        'sha256': hash,
        'created_at': now.millisecondsSinceEpoch,
        'is_duplicate': isDup ? 1 : 0,
        'duplicate_of_id': existing?.id,
      });
    } catch (e) {
      // DB failed: rollback file move/copy as safely as possible.
      if (movedByRename) {
        try {
          // Try to return the source back to its original location.
          await dest.rename(sourcePathBeforeMove);
        } catch (_) {
          // If rollback rename fails, best-effort remove the moved file.
          try { if (await dest.exists()) await dest.delete(); } catch (_) {}
        }
      } else {
        try { if (await dest.exists()) await dest.delete(); } catch (_) {}
      }
      rethrow;
    }

    // If this was a cross-volume "move", only now delete the source.
    if (importMode == ImportMode.move && !movedByRename) {
      try {
        await source.delete();
      } catch (_) {
        // Keep the imported copy if we cannot delete the source.
      }
    }

    final inserted = MediaItem(
      id: id,
      subcategoryId: subId,
      type: type,
      originalName: originalName,
      storedRelPath: storedRelPath,
      sizeBytes: sizeBytes,
      sha256: hash,
      createdAt: now,
      isDuplicate: isDup,
      duplicateOfId: existing?.id,
    );

    // Create portable metadata sidecar.
    try {
      await _writeSidecarForItem(inserted);
    } catch (_) {
      // Sidecar is best-effort; do not fail import.
    }

    return (item: inserted, duplicateOf: existing);
  } catch (e) {
    // If the copy/move failed mid-way, best-effort cleanup any leftover temp file.
    final tmp = File(dest.path + '.part');
    if (await tmp.exists()) {
      try { await tmp.delete(); } catch (_) {}
    }
    rethrow;
  }
}



  MediaItem _rowToItem(Map<String, Object?> r) {
    return MediaItem(
      id: r['id'] as String,
      subcategoryId: r['subcategory_id'] as String,
      type: _itemTypeFromDb(r['type'] as String),
      originalName: r['original_name'] as String,
      storedRelPath: r['stored_rel_path'] as String,
      sizeBytes: (r['size_bytes'] as int),
      sha256: r['sha256'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      isDuplicate: (r['is_duplicate'] as int) == 1,
      duplicateOfId: r['duplicate_of_id'] as String?,
      isFavourite: ((r['is_favourite'] as int?) ?? 0) == 1,
    );
  }

  Future<void> toggleFavourite(String itemId, bool value) async {
    await db.update('items', {'is_favourite': value ? 1 : 0}, where: 'id=?', whereArgs: [itemId]);
  }

  Future<List<MediaItem>> listFavourites() async {
    final rows = await db.query('items', where: 'is_favourite=1', orderBy: 'created_at DESC');
    return rows.map(_rowToItem).toList();
  }
}

class NoteRepo {
  final Database db;
  final Directory attachmentsDir;
  NoteRepo(this.db, this.attachmentsDir);

  Future<List<Note>> listNotes() async {
    final rows = await db.query('notes', orderBy: 'updated_at DESC');
    return rows.map((r) => Note(
      id: r['id'] as String,
      title: r['title'] as String,
      content: r['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    )).toList();
  }

  Future<Note> createNote(String title) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final note = Note(id: id, title: title, content: '', createdAt: now, updatedAt: now);
    await db.insert('notes', {
      'id': id,
      'title': title,
      'content': '',
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return note;
  }

  Future<void> updateNote(Note note) async {
    await db.update('notes', {
      'title': note.title,
      'content': note.content,
      'updated_at': note.updatedAt.millisecondsSinceEpoch,
    }, where: 'id=?', whereArgs: [note.id]);
  }


Future<void> deleteNote(String noteId) async {
  // Collect attachment paths before deleting note rows (FK cascade would remove them).
  final rows = await db.query('note_attachments', where: 'note_id=?', whereArgs: [noteId]);
  final relPaths = rows.map((r) => r['stored_rel_path'] as String).toList();

  await db.delete('notes', where: 'id=?', whereArgs: [noteId]);

  // Physical cleanup after DB deletion.
  for (final rel in relPaths) {
    final f = File(p.join(attachmentsDir.path, rel));
    if (await f.exists()) {
      await f.delete();
    }
  }
}

  Future<List<NoteAttachment>> listAttachments(String noteId) async {
    final rows = await db.query('note_attachments', where: 'note_id=?', whereArgs: [noteId]);
    return rows.map((r) => NoteAttachment(
      id: r['id'] as String,
      noteId: r['note_id'] as String,
      storedRelPath: r['stored_rel_path'] as String,
      originalName: r['original_name'] as String,
      mime: r['mime'] as String,
      sizeBytes: r['size_bytes'] as int,
    )).toList();
  }

  Future<NoteAttachment> addAttachmentFromFile(String noteId, File source) async {
    final id = _uuid.v4();
    final bytes = await source.readAsBytes();
    final ext = p.extension(source.path);
    final rel = '$id$ext';
    final dest = File(p.join(attachmentsDir.path, rel));
    await dest.writeAsBytes(bytes);

    final mime = _mimeFor(source.path) ?? 'application/octet-stream';
    final sizeBytes = bytes.length;

    await db.insert('note_attachments', {
      'id': id,
      'note_id': noteId,
      'stored_rel_path': rel,
      'original_name': p.basename(source.path),
      'mime': mime,
      'size_bytes': sizeBytes,
    });

    return NoteAttachment(
      id: id,
      noteId: noteId,
      storedRelPath: rel,
      originalName: p.basename(source.path),
      mime: mime,
      sizeBytes: sizeBytes,
    );
  }

  Future<void> deleteAttachment(String attachmentId) async {
    final rows = await db.query('note_attachments', where: 'id=?', whereArgs: [attachmentId], limit: 1);
    if (rows.isNotEmpty) {
      final rel = rows.first['stored_rel_path'] as String;
      final f = File(p.join(attachmentsDir.path, rel));
      if (await f.exists()) await f.delete();
    }
    await db.delete('note_attachments', where: 'id=?', whereArgs: [attachmentId]);
  }

  String? _mimeFor(String path) {
    final ext = p.extension(path).toLowerCase();
    if (['.png'].contains(ext)) return 'image/png';
    if (['.jpg', '.jpeg'].contains(ext)) return 'image/jpeg';
    if (['.webp'].contains(ext)) return 'image/webp';
    if (['.gif'].contains(ext)) return 'image/gif';
    return null;
  }
}