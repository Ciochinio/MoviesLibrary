import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDb {
  final String dbPath;
  Database? _db;

  AppDb(this.dbPath);

  Future<Database> open() async {
    if (_db != null) return _db!;
    _db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 14,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _upgradeToV2(db);
          if (oldVersion < 3) await _upgradeToV3(db);
          if (oldVersion < 4) await _upgradeToV4(db);
          if (oldVersion < 5) await _upgradeToV5(db);
          if (oldVersion < 6) await _upgradeToV6(db);
          if (oldVersion < 7) await _upgradeToV7(db);
          if (oldVersion < 8) await _upgradeToV8(db);
          if (oldVersion < 9) await _upgradeToV9(db);
          if (oldVersion < 10) await _upgradeToV10(db);
          if (oldVersion < 11) await _upgradeToV11(db);
          if (oldVersion < 12) await _upgradeToV12(db);
          if (oldVersion < 13) await _upgradeToV13(db);
          if (oldVersion < 14) await _upgradeToV14(db);
        },
      ),
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        sort_order INTEGER DEFAULT 0
      );
    ''');

    await db.execute('''
      CREATE TABLE subcategories (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        sort_order INTEGER DEFAULT 0,
        FOREIGN KEY(category_id) REFERENCES categories(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE items (
        id TEXT PRIMARY KEY,
        subcategory_id TEXT NOT NULL,
        type TEXT NOT NULL,
        original_name TEXT NOT NULL,
        stored_rel_path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        sha256 TEXT NOT NULL,
        duration_ms INTEGER,
        created_at INTEGER NOT NULL,
        is_duplicate INTEGER NOT NULL DEFAULT 0,
        duplicate_of_id TEXT,
        is_favourite INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(subcategory_id) REFERENCES subcategories(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE tag_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        description TEXT DEFAULT '',
        sort_order INTEGER DEFAULT 0,
        group_id TEXT REFERENCES tag_groups(id) ON DELETE SET NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE item_tags (
        item_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (item_id, tag_id),
        FOREIGN KEY(item_id) REFERENCES items(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE tag_keys (
        id TEXT PRIMARY KEY,
        key TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        description TEXT DEFAULT '',
        sort_order INTEGER DEFAULT 0
      );
    ''');

    await db.execute('''
      CREATE TABLE tag_key_values (
        id TEXT PRIMARY KEY,
        key_id TEXT NOT NULL,
        value TEXT NOT NULL,
        description TEXT DEFAULT '',
        created_at INTEGER NOT NULL,
        sort_order INTEGER DEFAULT 0,
        FOREIGN KEY(key_id) REFERENCES tag_keys(id) ON DELETE CASCADE,
        UNIQUE(key_id, value)
      );
    ''');

    await db.execute('''
      CREATE TABLE item_tag_key_values (
        item_id TEXT NOT NULL,
        key_value_id TEXT NOT NULL,
        PRIMARY KEY (item_id, key_value_id),
        FOREIGN KEY(item_id) REFERENCES items(id) ON DELETE CASCADE,
        FOREIGN KEY(key_value_id) REFERENCES tag_key_values(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE note_attachments (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        stored_rel_path TEXT NOT NULL,
        original_name TEXT NOT NULL,
        mime TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('CREATE INDEX idx_subcategories_category_id ON subcategories(category_id);');
    await db.execute('CREATE INDEX idx_items_subcategory_id ON items(subcategory_id);');
    await db.execute('CREATE INDEX idx_item_tags_tag_id ON item_tags(tag_id);');
    await db.execute('CREATE INDEX idx_item_tags_item_id ON item_tags(item_id);');
    await db.execute('CREATE INDEX idx_tags_group_id ON tags(group_id);');
    await db.execute('CREATE INDEX idx_tag_key_values_key_id ON tag_key_values(key_id);');
    await db.execute('CREATE INDEX idx_item_kv_kv_id ON item_tag_key_values(key_value_id);');
    await db.execute('CREATE INDEX idx_item_kv_item_id ON item_tag_key_values(item_id);');
    await db.execute('CREATE INDEX idx_notes_updated_at ON notes(updated_at);');

    await db.execute('''
      CREATE TABLE subcategory_auto_tags (
        subcategory_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (subcategory_id, tag_id),
        FOREIGN KEY(subcategory_id) REFERENCES subcategories(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE subcategory_auto_key_values (
        subcategory_id TEXT NOT NULL,
        key_value_id TEXT NOT NULL,
        PRIMARY KEY (subcategory_id, key_value_id),
        FOREIGN KEY(subcategory_id) REFERENCES subcategories(id) ON DELETE CASCADE,
        FOREIGN KEY(key_value_id) REFERENCES tag_key_values(id) ON DELETE CASCADE
      );
    ''');

    // Raffle tables
    await db.execute('''
      CREATE TABLE raffle_playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE raffle_playlist_segments (
        id TEXT PRIMARY KEY,
        playlist_id TEXT NOT NULL,
        label TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(playlist_id) REFERENCES raffle_playlists(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE raffle_segment_simple_tags (
        segment_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (segment_id, tag_id),
        FOREIGN KEY(segment_id) REFERENCES raffle_playlist_segments(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE raffle_segment_key_values (
        segment_id TEXT NOT NULL,
        key_value_id TEXT NOT NULL,
        PRIMARY KEY (segment_id, key_value_id),
        FOREIGN KEY(segment_id) REFERENCES raffle_playlist_segments(id) ON DELETE CASCADE,
        FOREIGN KEY(key_value_id) REFERENCES tag_key_values(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE raffle_segment_categories (
        segment_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        subcategory_id TEXT,
        FOREIGN KEY(segment_id) REFERENCES raffle_playlist_segments(id) ON DELETE CASCADE,
        FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE,
        FOREIGN KEY(subcategory_id) REFERENCES subcategories(id) ON DELETE SET NULL
      );
    ''');

    await db.execute('CREATE INDEX idx_raffle_segments_playlist ON raffle_playlist_segments(playlist_id);');
    await db.execute('CREATE INDEX idx_raffle_seg_tags ON raffle_segment_simple_tags(segment_id);');
    await db.execute('CREATE INDEX idx_raffle_seg_kv ON raffle_segment_key_values(segment_id);');
    await db.execute('CREATE INDEX idx_raffle_seg_cats ON raffle_segment_categories(segment_id);');

    // Quick Roll tables
    await db.execute('''
      CREATE TABLE quick_roll_presets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sample_size INTEGER NOT NULL DEFAULT 10,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE quick_roll_simple_tags (
        preset_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (preset_id, tag_id),
        FOREIGN KEY(preset_id) REFERENCES quick_roll_presets(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE quick_roll_key_values (
        preset_id TEXT NOT NULL,
        key_value_id TEXT NOT NULL,
        PRIMARY KEY (preset_id, key_value_id),
        FOREIGN KEY(preset_id) REFERENCES quick_roll_presets(id) ON DELETE CASCADE,
        FOREIGN KEY(key_value_id) REFERENCES tag_key_values(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE quick_roll_categories (
        preset_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        subcategory_id TEXT,
        FOREIGN KEY(preset_id) REFERENCES quick_roll_presets(id) ON DELETE CASCADE,
        FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE,
        FOREIGN KEY(subcategory_id) REFERENCES subcategories(id) ON DELETE SET NULL
      );
    ''');

    await db.execute('CREATE INDEX idx_qr_preset_tags ON quick_roll_simple_tags(preset_id);');
    await db.execute('CREATE INDEX idx_qr_preset_kv ON quick_roll_key_values(preset_id);');
    await db.execute('CREATE INDEX idx_qr_preset_cats ON quick_roll_categories(preset_id);');
  }

  Future<void> _upgradeToV2(Database db) async {
    await db.execute('ALTER TABLE items ADD COLUMN duration_ms INTEGER;');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tag_keys (
        id TEXT PRIMARY KEY,
        key TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tag_key_values (
        id TEXT PRIMARY KEY,
        key_id TEXT NOT NULL,
        value TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(key_id) REFERENCES tag_keys(id) ON DELETE CASCADE,
        UNIQUE(key_id, value)
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_tag_key_values (
        item_id TEXT NOT NULL,
        key_value_id TEXT NOT NULL,
        PRIMARY KEY (item_id, key_value_id),
        FOREIGN KEY(item_id) REFERENCES items(id) ON DELETE CASCADE,
        FOREIGN KEY(key_value_id) REFERENCES tag_key_values(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tag_key_values_key_id ON tag_key_values(key_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_item_kv_kv_id ON item_tag_key_values(key_value_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_item_kv_item_id ON item_tag_key_values(item_id);');
  }

  Future<void> _upgradeToV3(Database db) async {
    try { await db.execute("ALTER TABLE categories ADD COLUMN description TEXT DEFAULT ''"); } catch (_) {}
    try { await db.execute("ALTER TABLE subcategories ADD COLUMN description TEXT DEFAULT ''"); } catch (_) {}
    try { await db.execute("ALTER TABLE tags ADD COLUMN description TEXT DEFAULT ''"); } catch (_) {}
    try { await db.execute("ALTER TABLE tag_keys ADD COLUMN description TEXT DEFAULT ''"); } catch (_) {}
    try { await db.execute("ALTER TABLE tag_keys ADD COLUMN sort_order INTEGER DEFAULT 0"); } catch (_) {}
    try { await db.execute("ALTER TABLE tags ADD COLUMN sort_order INTEGER DEFAULT 0"); } catch (_) {}
  }

  Future<void> _upgradeToV4(Database db) async {
    try { await db.execute("ALTER TABLE tags ADD COLUMN sort_order INTEGER DEFAULT 0"); } catch (_) {}
    try { await db.execute("ALTER TABLE tag_key_values ADD COLUMN description TEXT DEFAULT ''"); } catch (_) {}
  }

  Future<void> _upgradeToV5(Database db) async {
    try { await db.execute("ALTER TABLE tag_key_values ADD COLUMN description TEXT DEFAULT ''"); } catch (_) {}
  }

  Future<void> _upgradeToV6(Database db) async {
    try { await db.execute("ALTER TABLE categories ADD COLUMN sort_order INTEGER DEFAULT 0"); } catch (_) {}
    try { await db.execute("ALTER TABLE subcategories ADD COLUMN sort_order INTEGER DEFAULT 0"); } catch (_) {}
    final cats = await db.query('categories', orderBy: 'name COLLATE NOCASE');
    for (int i = 0; i < cats.length; i++) {
      await db.update('categories', {'sort_order': i}, where: 'id=?', whereArgs: [cats[i]['id']]);
    }
    final allSubs = await db.query('subcategories', orderBy: 'name COLLATE NOCASE');
    final byCat = <String, List<Map<String, Object?>>>{};
    for (final s in allSubs) {
      byCat.putIfAbsent(s['category_id'] as String, () => []).add(s);
    }
    for (final subs in byCat.values) {
      for (int i = 0; i < subs.length; i++) {
        await db.update('subcategories', {'sort_order': i}, where: 'id=?', whereArgs: [subs[i]['id']]);
      }
    }
    final tags = await db.query('tags', orderBy: 'sort_order ASC, name COLLATE NOCASE');
    for (int i = 0; i < tags.length; i++) {
      await db.update('tags', {'sort_order': i}, where: 'id=?', whereArgs: [tags[i]['id']]);
    }
    final keys = await db.query('tag_keys', orderBy: 'sort_order ASC, key COLLATE NOCASE');
    for (int i = 0; i < keys.length; i++) {
      await db.update('tag_keys', {'sort_order': i}, where: 'id=?', whereArgs: [keys[i]['id']]);
    }
  }

  Future<void> _upgradeToV7(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS subcategory_auto_tags (
        subcategory_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (subcategory_id, tag_id),
        FOREIGN KEY(subcategory_id) REFERENCES subcategories(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS subcategory_auto_key_values (
        subcategory_id TEXT NOT NULL,
        key_value_id TEXT NOT NULL,
        PRIMARY KEY (subcategory_id, key_value_id),
        FOREIGN KEY(subcategory_id) REFERENCES subcategories(id) ON DELETE CASCADE,
        FOREIGN KEY(key_value_id) REFERENCES tag_key_values(id) ON DELETE CASCADE
      );
    ''');
  }

  Future<void> _upgradeToV8(Database db) async {
    try { await db.execute('ALTER TABLE tag_key_values ADD COLUMN sort_order INTEGER DEFAULT 0'); } catch (_) {}
    final keys = await db.query('tag_keys', columns: ['id']);
    for (final key in keys) {
      final keyId = key['id'] as String;
      final values = await db.query('tag_key_values',
          where: 'key_id=?', whereArgs: [keyId], orderBy: 'value COLLATE NOCASE');
      for (int i = 0; i < values.length; i++) {
        await db.update('tag_key_values', {'sort_order': i},
            where: 'id=?', whereArgs: [values[i]['id']]);
      }
    }
  }

  Future<void> _upgradeToV9(Database db) async {
    try { await db.execute('ALTER TABLE items ADD COLUMN is_favourite INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
  }

  Future<void> _upgradeToV10(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS raffle_playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS raffle_playlist_segments (
        id TEXT PRIMARY KEY,
        playlist_id TEXT NOT NULL,
        label TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(playlist_id) REFERENCES raffle_playlists(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS raffle_segment_simple_tags (
        segment_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (segment_id, tag_id),
        FOREIGN KEY(segment_id) REFERENCES raffle_playlist_segments(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS raffle_segment_key_values (
        segment_id TEXT NOT NULL,
        key_value_id TEXT NOT NULL,
        PRIMARY KEY (segment_id, key_value_id),
        FOREIGN KEY(segment_id) REFERENCES raffle_playlist_segments(id) ON DELETE CASCADE,
        FOREIGN KEY(key_value_id) REFERENCES tag_key_values(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS raffle_segment_categories (
        segment_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        subcategory_id TEXT,
        FOREIGN KEY(segment_id) REFERENCES raffle_playlist_segments(id) ON DELETE CASCADE,
        FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE,
        FOREIGN KEY(subcategory_id) REFERENCES subcategories(id) ON DELETE SET NULL
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_raffle_segments_playlist ON raffle_playlist_segments(playlist_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_raffle_seg_tags ON raffle_segment_simple_tags(segment_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_raffle_seg_kv ON raffle_segment_key_values(segment_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_raffle_seg_cats ON raffle_segment_categories(segment_id);');
  }

  Future<void> _upgradeToV11(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quick_roll_presets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sample_size INTEGER NOT NULL DEFAULT 10,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quick_roll_simple_tags (
        preset_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (preset_id, tag_id),
        FOREIGN KEY(preset_id) REFERENCES quick_roll_presets(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quick_roll_key_values (
        preset_id TEXT NOT NULL,
        key_value_id TEXT NOT NULL,
        PRIMARY KEY (preset_id, key_value_id),
        FOREIGN KEY(preset_id) REFERENCES quick_roll_presets(id) ON DELETE CASCADE,
        FOREIGN KEY(key_value_id) REFERENCES tag_key_values(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quick_roll_categories (
        preset_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        subcategory_id TEXT,
        FOREIGN KEY(preset_id) REFERENCES quick_roll_presets(id) ON DELETE CASCADE,
        FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE,
        FOREIGN KEY(subcategory_id) REFERENCES subcategories(id) ON DELETE SET NULL
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_qr_preset_tags ON quick_roll_simple_tags(preset_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_qr_preset_kv ON quick_roll_key_values(preset_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_qr_preset_cats ON quick_roll_categories(preset_id);');
  }

  Future<void> _upgradeToV12(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tag_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      );
    ''');
    try { await db.execute('ALTER TABLE tags ADD COLUMN group_id TEXT REFERENCES tag_groups(id) ON DELETE SET NULL'); } catch (_) {}
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tags_group_id ON tags(group_id);');
  }

  Future<void> _upgradeToV13(Database db) async {
    try { await db.execute("ALTER TABLE tag_keys ADD COLUMN type TEXT NOT NULL DEFAULT 'chips'"); } catch (_) {}
  }

  Future<void> _upgradeToV14(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS name_order (
        id TEXT NOT NULL,
        type TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id, type)
      );
    ''');
  }
}