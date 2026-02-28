import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();

class QuickRollRepository {
  final Database db;
  QuickRollRepository(this.db);

  // ─── Presets ───────────────────────────────────────────────────────────────

  Future<List<QuickRollPreset>> listPresets() async {
    final rows = await db.query('quick_roll_presets', orderBy: 'updated_at DESC');
    final presets = <QuickRollPreset>[];
    for (final r in rows) {
      final id = r['id'] as String;
      presets.add(QuickRollPreset(
        id: id,
        name: r['name'] as String,
        sampleSize: (r['sample_size'] as int?) ?? 10,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
        simpleTagIds: await _loadSimpleTagIds(id),
        keyValueIds: await _loadKeyValueIds(id),
        categories: await _loadCategories(id),
      ));
    }
    return presets;
  }

  Future<QuickRollPreset> createPreset({
    required String name,
    required int sampleSize,
    required List<String> simpleTagIds,
    required List<String> keyValueIds,
    required List<RaffleSegmentCategory> categories,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.insert('quick_roll_presets', {
        'id': id,
        'name': name,
        'sample_size': sampleSize,
        'created_at': now,
        'updated_at': now,
      });
      await _insertFilters(txn, id, simpleTagIds, keyValueIds, categories);
    });
    return QuickRollPreset(
      id: id,
      name: name,
      sampleSize: sampleSize,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
      simpleTagIds: simpleTagIds,
      keyValueIds: keyValueIds,
      categories: categories,
    );
  }

  Future<void> updatePreset({
    required String id,
    required String name,
    required int sampleSize,
    required List<String> simpleTagIds,
    required List<String> keyValueIds,
    required List<RaffleSegmentCategory> categories,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update(
        'quick_roll_presets',
        {'name': name, 'sample_size': sampleSize, 'updated_at': now},
        where: 'id=?',
        whereArgs: [id],
      );
      await txn.delete('quick_roll_simple_tags', where: 'preset_id=?', whereArgs: [id]);
      await txn.delete('quick_roll_key_values', where: 'preset_id=?', whereArgs: [id]);
      await txn.delete('quick_roll_categories', where: 'preset_id=?', whereArgs: [id]);
      await _insertFilters(txn, id, simpleTagIds, keyValueIds, categories);
    });
  }

  Future<void> renamePreset(String id, String name) async {
    await db.update(
      'quick_roll_presets',
      {'name': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> deletePreset(String id) async {
    await db.delete('quick_roll_presets', where: 'id=?', whereArgs: [id]);
  }

  // ─── Roll ──────────────────────────────────────────────────────────────────

  /// Query all matching items for a preset, then return a random sample of sampleSize.
  /// If fewer items match than sampleSize, returns all of them.
  Future<({List<MediaItem> items, int totalMatched})> roll(QuickRollPreset preset) async {
    final all = await _queryItems(preset);
    final totalMatched = all.length;
    if (all.isEmpty) return (items: <MediaItem>[], totalMatched: 0);

    final rng = Random();
    final shuffled = List<MediaItem>.from(all)..shuffle(rng);
    final sample = shuffled.take(preset.sampleSize).toList();
    return (items: sample, totalMatched: totalMatched);
  }

  /// Roll with no filters — random sample from the entire library.
  Future<({List<MediaItem> items, int totalMatched})> rollRandom(int sampleSize) async {
    final rows = await db.query('items', orderBy: 'RANDOM()', limit: sampleSize * 3);
    final all = rows.map((r) => _rowToItem(r.cast<String, Object?>())).toList();
    final totalMatched = all.length;
    if (all.isEmpty) return (items: <MediaItem>[], totalMatched: 0);

    final rng = Random();
    final shuffled = List<MediaItem>.from(all)..shuffle(rng);
    final sample = shuffled.take(sampleSize).toList();
    return (items: sample, totalMatched: totalMatched);
  }

  // ─── Private helpers ───────────────────────────────────────────────────────

  Future<List<MediaItem>> _queryItems(QuickRollPreset preset) async {
    final hasCategories = preset.categories.isNotEmpty;
    final hasSimple = preset.simpleTagIds.isNotEmpty;
    final hasKv = preset.keyValueIds.isNotEmpty;

    // Pure random — no filters at all
    if (!hasCategories && !hasSimple && !hasKv) {
      final rows = await db.query('items');
      return rows.map((r) => _rowToItem(r.cast<String, Object?>())).toList();
    }

    // Build subcategory pool from category filters
    List<String>? subcategoryIdPool;
    if (hasCategories) {
      subcategoryIdPool = [];
      for (final cat in preset.categories) {
        if (cat.subcategoryId != null) {
          subcategoryIdPool.add(cat.subcategoryId!);
        } else {
          final rows = await db.query(
            'subcategories',
            columns: ['id'],
            where: 'category_id=?',
            whereArgs: [cat.categoryId],
          );
          subcategoryIdPool.addAll(rows.map((r) => r['id'] as String));
        }
      }
      if (subcategoryIdPool.isEmpty) return [];
    }

    final whereParts = <String>[];
    final args = <Object?>[];
    var joinSql = 'FROM items i';

    if (subcategoryIdPool != null) {
      final ph = List.filled(subcategoryIdPool.length, '?').join(',');
      whereParts.add('i.subcategory_id IN ($ph)');
      args.addAll(subcategoryIdPool);
    }

    if (hasSimple) {
      final ph = List.filled(preset.simpleTagIds.length, '?').join(',');
      joinSql += ' JOIN item_tags it ON it.item_id = i.id';
      whereParts.add('it.tag_id IN ($ph)');
      args.addAll(preset.simpleTagIds);
    }

    if (hasKv) {
      final ph = List.filled(preset.keyValueIds.length, '?').join(',');
      joinSql += ' JOIN item_tag_key_values itk ON itk.item_id = i.id';
      whereParts.add('itk.key_value_id IN ($ph)');
      args.addAll(preset.keyValueIds);
    }

    final whereSql = whereParts.isEmpty ? '' : 'WHERE ${whereParts.join(' AND ')}';

    final countParts = <String>[];
    if (hasSimple) countParts.add('COUNT(DISTINCT it.tag_id)');
    if (hasKv) countParts.add('COUNT(DISTINCT itk.key_value_id)');
    final totalRequired = preset.simpleTagIds.length + preset.keyValueIds.length;
    final havingSql = countParts.isNotEmpty ? 'HAVING ${countParts.join(' + ')} >= ?' : '';
    if (countParts.isNotEmpty) args.add(totalRequired);

    final sql = '''
      SELECT i.*
      $joinSql
      $whereSql
      GROUP BY i.id
      $havingSql
    ''';

    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => _rowToItem(r.cast<String, Object?>())).toList();
  }

  Future<void> _insertFilters(
    DatabaseExecutor txn,
    String presetId,
    List<String> simpleTagIds,
    List<String> keyValueIds,
    List<RaffleSegmentCategory> categories,
  ) async {
    for (final tagId in simpleTagIds) {
      await txn.insert('quick_roll_simple_tags',
          {'preset_id': presetId, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final kvId in keyValueIds) {
      await txn.insert('quick_roll_key_values',
          {'preset_id': presetId, 'key_value_id': kvId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final cat in categories) {
      await txn.insert('quick_roll_categories', {
        'preset_id': presetId,
        'category_id': cat.categoryId,
        'subcategory_id': cat.subcategoryId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<List<String>> _loadSimpleTagIds(String presetId) async {
    final rows = await db.query('quick_roll_simple_tags',
        columns: ['tag_id'], where: 'preset_id=?', whereArgs: [presetId]);
    return rows.map((r) => r['tag_id'] as String).toList();
  }

  Future<List<String>> _loadKeyValueIds(String presetId) async {
    final rows = await db.query('quick_roll_key_values',
        columns: ['key_value_id'], where: 'preset_id=?', whereArgs: [presetId]);
    return rows.map((r) => r['key_value_id'] as String).toList();
  }

  Future<List<RaffleSegmentCategory>> _loadCategories(String presetId) async {
    final rows = await db.query('quick_roll_categories',
        where: 'preset_id=?', whereArgs: [presetId]);
    return rows.map((r) => RaffleSegmentCategory(
          categoryId: r['category_id'] as String,
          subcategoryId: r['subcategory_id'] as String?,
        )).toList();
  }

  MediaItem _rowToItem(Map<String, Object?> r) {
    return MediaItem(
      id: r['id'] as String,
      subcategoryId: r['subcategory_id'] as String,
      type: _itemTypeFromDb(r['type'] as String),
      originalName: r['original_name'] as String,
      storedRelPath: r['stored_rel_path'] as String,
      sizeBytes: r['size_bytes'] as int,
      sha256: r['sha256'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      isDuplicate: (r['is_duplicate'] as int) == 1,
      duplicateOfId: r['duplicate_of_id'] as String?,
      isFavourite: ((r['is_favourite'] as int?) ?? 0) == 1,
    );
  }

  ItemType _itemTypeFromDb(String s) => switch (s) {
        'video' => ItemType.video,
        'image' => ItemType.image,
        _ => ItemType.other,
      };
}