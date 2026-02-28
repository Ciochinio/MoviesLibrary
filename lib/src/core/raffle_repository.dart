import 'dart:math';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();

class RaffleRepository {
  final Database db;
  RaffleRepository(this.db);

  // ─── Playlists ─────────────────────────────────────────────────────────────

  Future<List<RafflePlaylist>> listPlaylists() async {
    final rows = await db.query(
      'raffle_playlists',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_rowToPlaylist).toList();
  }

  Future<RafflePlaylist> createPlaylist(String name) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('raffle_playlists', {
      'id': id,
      'name': name,
      'created_at': now,
      'updated_at': now,
    });
    return RafflePlaylist(
      id: id,
      name: name,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  Future<void> renamePlaylist(String id, String name) async {
    await db.update(
      'raffle_playlists',
      {'name': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> deletePlaylist(String id) async {
    // Segments and their tags cascade via FK
    await db.delete('raffle_playlists', where: 'id=?', whereArgs: [id]);
  }

  Future<void> _touchPlaylist(String playlistId) async {
    await db.update(
      'raffle_playlists',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id=?',
      whereArgs: [playlistId],
    );
  }

  // ─── Segments ──────────────────────────────────────────────────────────────

  /// Load all segments for a playlist, with their filters attached.
  Future<List<RaffleSegment>> listSegments(String playlistId) async {
    final rows = await db.query(
      'raffle_playlist_segments',
      where: 'playlist_id=?',
      whereArgs: [playlistId],
      orderBy: 'sort_order ASC',
    );

    final segments = <RaffleSegment>[];
    for (final r in rows) {
      final segId = r['id'] as String;
      final simpleTagIds = await _loadSimpleTagIds(segId);
      final keyValueIds = await _loadKeyValueIds(segId);
      final categories = await _loadCategories(segId);

      segments.add(RaffleSegment(
        id: segId,
        playlistId: playlistId,
        label: r['label'] as String,
        sortOrder: (r['sort_order'] as int?) ?? 0,
        simpleTagIds: simpleTagIds,
        keyValueIds: keyValueIds,
        categories: categories,
      ));
    }
    return segments;
  }

  Future<RaffleSegment> createSegment({
    required String playlistId,
    required String label,
    required List<String> simpleTagIds,
    required List<String> keyValueIds,
    required List<RaffleSegmentCategory> categories,
  }) async {
    final id = _uuid.v4();

    final maxRows = await db.rawQuery(
      'SELECT MAX(sort_order) as m FROM raffle_playlist_segments WHERE playlist_id=?',
      [playlistId],
    );
    final maxOrder = (maxRows.first['m'] as int?) ?? -1;
    final sortOrder = maxOrder + 1;

    await db.transaction((txn) async {
      await txn.insert('raffle_playlist_segments', {
        'id': id,
        'playlist_id': playlistId,
        'label': label,
        'sort_order': sortOrder,
      });
      await _insertFilters(txn, id, simpleTagIds, keyValueIds, categories);
    });

    await _touchPlaylist(playlistId);

    return RaffleSegment(
      id: id,
      playlistId: playlistId,
      label: label,
      sortOrder: sortOrder,
      simpleTagIds: simpleTagIds,
      keyValueIds: keyValueIds,
      categories: categories,
    );
  }

  Future<void> updateSegment({
    required String segmentId,
    required String playlistId,
    required String label,
    required List<String> simpleTagIds,
    required List<String> keyValueIds,
    required List<RaffleSegmentCategory> categories,
  }) async {
    await db.transaction((txn) async {
      await txn.update(
        'raffle_playlist_segments',
        {'label': label},
        where: 'id=?',
        whereArgs: [segmentId],
      );

      // Replace all filters atomically
      await txn.delete('raffle_segment_simple_tags', where: 'segment_id=?', whereArgs: [segmentId]);
      await txn.delete('raffle_segment_key_values', where: 'segment_id=?', whereArgs: [segmentId]);
      await txn.delete('raffle_segment_categories', where: 'segment_id=?', whereArgs: [segmentId]);

      await _insertFilters(txn, segmentId, simpleTagIds, keyValueIds, categories);
    });
    await _touchPlaylist(playlistId);
  }

  Future<void> deleteSegment(String segmentId, String playlistId) async {
    await db.delete('raffle_playlist_segments', where: 'id=?', whereArgs: [segmentId]);
    await _touchPlaylist(playlistId);
  }

  Future<void> reorderSegments(String playlistId, List<String> orderedIds) async {
    await db.transaction((txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'raffle_playlist_segments',
          {'sort_order': i},
          where: 'id=?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
    await _touchPlaylist(playlistId);
  }

  // --- Auto-generate & sync ---

  /// Returns all categories with subcategory item counts for the generate dialog.
  Future<List<Map<String, dynamic>>> listCategoriesWithCounts() async {
    final cats = await db.query('categories', orderBy: 'sort_order ASC, name COLLATE NOCASE');
    final result = <Map<String, dynamic>>[];
    for (final cat in cats) {
      final catId = cat['id'] as String;
      final subs = await db.query('subcategories',
          where: 'category_id=?',
          whereArgs: [catId],
          orderBy: 'sort_order ASC, name COLLATE NOCASE');
      final subList = <Map<String, dynamic>>[];
      for (final sub in subs) {
        final subId = sub['id'] as String;
        final countRows = await db.rawQuery(
            'SELECT COUNT(*) as c FROM items WHERE subcategory_id=?', [subId]);
        final count = (countRows.first['c'] as int?) ?? 0;
        subList.add({
          'subcategoryId': subId,
          'subcategoryName': sub['name'] as String,
          'itemCount': count,
        });
      }
      result.add({
        'categoryId': catId,
        'categoryName': cat['name'] as String,
        'subcategories': subList,
      });
    }
    return result;
  }

  /// Creates a playlist with one segment per qualifying subcategory.
  Future<RafflePlaylist> generateFromSubcategories({
    required String playlistName,
    required List<String> categoryIds,
    int minItemCount = 2,
  }) async {
    final playlist = await createPlaylist(playlistName);
    int sortOrder = 0;
    for (final catId in categoryIds) {
      final subs = await db.query('subcategories',
          where: 'category_id=?',
          whereArgs: [catId],
          orderBy: 'sort_order ASC, name COLLATE NOCASE');
      for (final sub in subs) {
        final subId = sub['id'] as String;
        final subName = sub['name'] as String;
        final countRows = await db.rawQuery(
            'SELECT COUNT(*) as c FROM items WHERE subcategory_id=?', [subId]);
        final count = (countRows.first['c'] as int?) ?? 0;
        if (count < minItemCount) continue;
        final segId = _uuid.v4();
        await db.transaction((txn) async {
          await txn.insert('raffle_playlist_segments', {
            'id': segId,
            'playlist_id': playlist.id,
            'label': subName,
            'sort_order': sortOrder,
          });
          await txn.insert('raffle_segment_categories', {
            'segment_id': segId,
            'category_id': catId,
            'subcategory_id': subId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        });
        sortOrder++;
      }
    }
    await _touchPlaylist(playlist.id);
    return playlist;
  }

  /// Creates a playlist with mixed segments — each segment randomly combines
  /// [categoriesPerSegment] subcategories from the qualifying pool.
  Future<RafflePlaylist> generateMixed({
    required String playlistName,
    required List<String> categoryIds,
    required int segmentCount,
    required int categoriesPerSegment,
    int minItemCount = 2,
  }) async {
    final playlist = await createPlaylist(playlistName);
    final rng = Random();

    // Build pool of qualifying subcategories
    final pool = <Map<String, String>>[];  // {subId, subName, catId}
    for (final catId in categoryIds) {
      final subs = await db.query('subcategories',
          where: 'category_id=?',
          whereArgs: [catId],
          orderBy: 'sort_order ASC, name COLLATE NOCASE');
      for (final sub in subs) {
        final subId = sub['id'] as String;
        final countRows = await db.rawQuery(
            'SELECT COUNT(*) as c FROM items WHERE subcategory_id=?', [subId]);
        final count = (countRows.first['c'] as int?) ?? 0;
        if (count < minItemCount) continue;
        pool.add({
          'subId': subId,
          'subName': sub['name'] as String,
          'catId': catId,
        });
      }
    }

    if (pool.isEmpty) {
      await _touchPlaylist(playlist.id);
      return playlist;
    }

    // Clamp categoriesPerSegment to pool size
    final perSeg = categoriesPerSegment.clamp(1, pool.length);

    for (int i = 0; i < segmentCount; i++) {
      // Shuffle pool and pick perSeg unique entries
      final shuffled = List<Map<String, String>>.from(pool)..shuffle(rng);
      final picked = shuffled.take(perSeg).toList();

      final label = picked.map((e) => e['subName']!).join(' · ');
      final segId = _uuid.v4();

      await db.transaction((txn) async {
        await txn.insert('raffle_playlist_segments', {
          'id': segId,
          'playlist_id': playlist.id,
          'label': label,
          'sort_order': i,
        });
        for (final entry in picked) {
          await txn.insert('raffle_segment_categories', {
            'segment_id': segId,
            'category_id': entry['catId']!,
            'subcategory_id': entry['subId']!,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });
    }

    await _touchPlaylist(playlist.id);
    return playlist;
  }

  /// Adds segments for subcategories not already covered. Never removes.
  /// Returns count of segments added.
  Future<int> syncWithLibrary({
    required String playlistId,
    int minItemCount = 2,
  }) async {
    final existingSegments = await listSegments(playlistId);
    final coveredSubIds = <String>{};
    for (final seg in existingSegments) {
      for (final cat in seg.categories) {
        if (cat.subcategoryId != null) coveredSubIds.add(cat.subcategoryId!);
      }
    }
    final allSubs = await db.query('subcategories',
        orderBy: 'sort_order ASC, name COLLATE NOCASE');
    final maxRows = await db.rawQuery(
        'SELECT MAX(sort_order) as m FROM raffle_playlist_segments WHERE playlist_id=?',
        [playlistId]);
    int sortOrder = (maxRows.first['m'] as int?) ?? -1;
    int added = 0;
    for (final sub in allSubs) {
      final subId = sub['id'] as String;
      if (coveredSubIds.contains(subId)) continue;
      final countRows = await db.rawQuery(
          'SELECT COUNT(*) as c FROM items WHERE subcategory_id=?', [subId]);
      final count = (countRows.first['c'] as int?) ?? 0;
      if (count < minItemCount) continue;
      sortOrder++;
      final segId = _uuid.v4();
      await db.transaction((txn) async {
        await txn.insert('raffle_playlist_segments', {
          'id': segId,
          'playlist_id': playlistId,
          'label': sub['name'] as String,
          'sort_order': sortOrder,
        });
        await txn.insert('raffle_segment_categories', {
          'segment_id': segId,
          'category_id': sub['category_id'] as String,
          'subcategory_id': subId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      });
      added++;
    }
    if (added > 0) await _touchPlaylist(playlistId);
    return added;
  }

  // ─── Query items for a segment ─────────────────────────────────────────────

  /// Returns matching MediaItems for a segment.
  /// Category filters narrow the pool first, tag filters apply within.
  /// Returns empty list if no filters are configured.
  Future<List<MediaItem>> querySegmentItems(RaffleSegment segment) async {
    final hasCategories = segment.categories.isNotEmpty;
    final hasSimple = segment.simpleTagIds.isNotEmpty;
    final hasKv = segment.keyValueIds.isNotEmpty;

    if (!hasCategories && !hasSimple && !hasKv) return [];

    // Build subcategory ID pool from category filters
    List<String>? subcategoryIdPool;
    if (hasCategories) {
      subcategoryIdPool = [];
      for (final cat in segment.categories) {
        if (cat.subcategoryId != null) {
          subcategoryIdPool.add(cat.subcategoryId!);
        } else {
          // All subcategories in this category
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

    // Build query
    final whereParts = <String>[];
    final args = <Object?>[];
    var joinSql = 'FROM items i';

    if (subcategoryIdPool != null) {
      final ph = List.filled(subcategoryIdPool.length, '?').join(',');
      whereParts.add('i.subcategory_id IN ($ph)');
      args.addAll(subcategoryIdPool);
    }

    if (hasSimple) {
      final ph = List.filled(segment.simpleTagIds.length, '?').join(',');
      joinSql += ' JOIN item_tags it ON it.item_id = i.id';
      whereParts.add('it.tag_id IN ($ph)');
      args.addAll(segment.simpleTagIds);
    }

    if (hasKv) {
      final ph = List.filled(segment.keyValueIds.length, '?').join(',');
      joinSql += ' JOIN item_tag_key_values itk ON itk.item_id = i.id';
      whereParts.add('itk.key_value_id IN ($ph)');
      args.addAll(segment.keyValueIds);
    }

    final whereSql = whereParts.isEmpty ? '' : 'WHERE ${whereParts.join(' AND ')}';

    // HAVING: item must match ALL selected tags
    final countParts = <String>[];
    if (hasSimple) countParts.add('COUNT(DISTINCT it.tag_id)');
    if (hasKv) countParts.add('COUNT(DISTINCT itk.key_value_id)');
    final totalRequired = segment.simpleTagIds.length + segment.keyValueIds.length;
    final havingSql = countParts.isNotEmpty
        ? 'HAVING ${countParts.join(' + ')} >= ?'
        : '';
    if (countParts.isNotEmpty) args.add(totalRequired);

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

  // ─── Private helpers ───────────────────────────────────────────────────────

  Future<void> _insertFilters(
    DatabaseExecutor txn,
    String segmentId,
    List<String> simpleTagIds,
    List<String> keyValueIds,
    List<RaffleSegmentCategory> categories,
  ) async {
    for (final tagId in simpleTagIds) {
      await txn.insert(
        'raffle_segment_simple_tags',
        {'segment_id': segmentId, 'tag_id': tagId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    for (final kvId in keyValueIds) {
      await txn.insert(
        'raffle_segment_key_values',
        {'segment_id': segmentId, 'key_value_id': kvId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    for (final cat in categories) {
      await txn.insert(
        'raffle_segment_categories',
        {
          'segment_id': segmentId,
          'category_id': cat.categoryId,
          'subcategory_id': cat.subcategoryId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<List<String>> _loadSimpleTagIds(String segmentId) async {
    final rows = await db.query(
      'raffle_segment_simple_tags',
      columns: ['tag_id'],
      where: 'segment_id=?',
      whereArgs: [segmentId],
    );
    return rows.map((r) => r['tag_id'] as String).toList();
  }

  Future<List<String>> _loadKeyValueIds(String segmentId) async {
    final rows = await db.query(
      'raffle_segment_key_values',
      columns: ['key_value_id'],
      where: 'segment_id=?',
      whereArgs: [segmentId],
    );
    return rows.map((r) => r['key_value_id'] as String).toList();
  }

  Future<List<RaffleSegmentCategory>> _loadCategories(String segmentId) async {
    final rows = await db.query(
      'raffle_segment_categories',
      where: 'segment_id=?',
      whereArgs: [segmentId],
    );
    return rows
        .map((r) => RaffleSegmentCategory(
              categoryId: r['category_id'] as String,
              subcategoryId: r['subcategory_id'] as String?,
            ))
        .toList();
  }

  RafflePlaylist _rowToPlaylist(Map<String, Object?> r) {
    return RafflePlaylist(
      id: r['id'] as String,
      name: r['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    );
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