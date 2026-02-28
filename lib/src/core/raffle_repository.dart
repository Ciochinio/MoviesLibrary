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
