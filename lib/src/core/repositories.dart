import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();

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
    final rows = await db.query('categories', orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => Category(id: r['id'] as String, name: r['name'] as String)).toList();
  }

  Future<List<Subcategory>> listSubcategories(String categoryId) async {
    final rows = await db.query('subcategories', where: 'category_id=?', whereArgs: [categoryId], orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => Subcategory(id: r['id'] as String, categoryId: r['category_id'] as String, name: r['name'] as String)).toList();
  }

  Future<Category> createCategory(String name) async {
    final id = _uuid.v4();
    await db.insert('categories', {'id': id, 'name': name});
    return Category(id: id, name: name);
  }

  Future<void> renameCategory(String id, String newName) async {
    await db.update('categories', {'name': newName}, where: 'id=?', whereArgs: [id]);
  }

  Future<Subcategory> createSubcategory(String categoryId, String name) async {
    final id = _uuid.v4();
    await db.insert('subcategories', {'id': id, 'category_id': categoryId, 'name': name});
    return Subcategory(id: id, categoryId: categoryId, name: name);
  }

  Future<void> renameSubcategory(String id, String newName) async {
    await db.update('subcategories', {'name': newName}, where: 'id=?', whereArgs: [id]);
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
    final rows = await db.query('tags', orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => Tag(id: r['id'] as String, name: r['name'] as String)).toList();
  }

  Future<Tag> createTag(String name) async {
    final id = _uuid.v4();
    await db.insert('tags', {'id': id, 'name': name});
    return Tag(id: id, name: name);
  }

  Future<void> renameTag(String id, String newName) async {
    await db.update('tags', {'name': newName}, where: 'id=?', whereArgs: [id]);
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
}

class ItemRepo {
  final Database db;
  final Directory filesDir;
  ItemRepo(this.db, this.filesDir);

  Future<MediaItem?> findByHash(String sha256hex) async {
    final rows = await db.query('items', where: 'sha256=?', whereArgs: [sha256hex], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return _rowToItem(r);
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

  Future<List<Tag>> listTagsForItem(String itemId) async {
    final rows = await db.rawQuery('''
      SELECT t.* FROM tags t
      JOIN item_tags it ON it.tag_id = t.id
      WHERE it.item_id = ?
      ORDER BY t.name COLLATE NOCASE
    ''', [itemId]);
    return rows.map((r) => Tag(id: r['id'] as String, name: r['name'] as String)).toList();
  }

  Future<void> setItemSubcategory(String itemId, String newSubcategoryId) async {
    await db.update('items', {'subcategory_id': newSubcategoryId}, where: 'id=?', whereArgs: [itemId]);
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

  Future<void> bulkMove(List<String> itemIds, String newSubcategoryId) async {
    await db.transaction((txn) async {
      for (final id in itemIds) {
        await txn.update('items', {'subcategory_id': newSubcategoryId}, where: 'id=?', whereArgs: [id]);
      }
    });
  }

  Future<void> deleteItems(List<MediaItem> items) async {
    await db.transaction((txn) async {
      for (final item in items) {
        await txn.delete('item_tags', where: 'item_id=?', whereArgs: [item.id]);
        await txn.delete('items', where: 'id=?', whereArgs: [item.id]);
      }
    });

    // Physical delete after DB deletion
    for (final item in items) {
      final f = File(p.join(filesDir.path, item.storedRelPath));
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  Future<({MediaItem item, MediaItem? duplicateOf})> importFile({
    required File source,
    required String targetSubcategoryId,
    required bool forceAddDuplicateAsSeparateFile,
    required String stashSubcategoryId,
  }) async {
    final bytes = await source.readAsBytes();
    final hash = sha256.convert(bytes).toString();

    final existing = await findByHash(hash);
    if (existing != null && !forceAddDuplicateAsSeparateFile) {
      // caller should decide; return existing in duplicateOf slot but do not insert
      return (item: existing, duplicateOf: existing);
    }

    final id = _uuid.v4();
    final type = _guessType(source.path);
    final originalName = p.basename(source.path);
    final sizeBytes = await source.length();

    // stored file name: <uuid><ext>
    final ext = p.extension(source.path);
    final storedName = '$id$ext';
    final storedRelPath = storedName;

    final dest = File(p.join(filesDir.path, storedRelPath));
    await dest.writeAsBytes(bytes);

    final now = DateTime.now();
    final isDup = existing != null;
    final subId = (existing != null) ? stashSubcategoryId : targetSubcategoryId;

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

    return (item: inserted, duplicateOf: existing);
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
    );
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
    await db.delete('notes', where: 'id=?', whereArgs: [noteId]);
    // attachments are deleted by FK cascade on rows, but physical files need manual cleanup
    final rows = await db.query('note_attachments', where: 'note_id=?', whereArgs: [noteId]);
    for (final r in rows) {
      final rel = r['stored_rel_path'] as String;
      final f = File(p.join(attachmentsDir.path, rel));
      if (await f.exists()) await f.delete();
    }
    await db.delete('note_attachments', where: 'note_id=?', whereArgs: [noteId]);
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
