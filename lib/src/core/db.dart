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
        version: 8,
        onConfigure: (db) async {
          // Enforce foreign keys (needed for ON DELETE CASCADE).
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _upgradeToV2(db);
          }
          if (oldVersion < 3) {
            await _upgradeToV3(db);
          }
          if (oldVersion < 4) {
            await _upgradeToV4(db);
          }
          if (oldVersion < 5) {
            await _upgradeToV5(db);
          }
          if (oldVersion < 6) {
            await _upgradeToV6(db);
          }
          if (oldVersion < 7) {
            await _upgradeToV7(db);
          }
          if (oldVersion < 8) {
            await _upgradeToV8(db);
          }
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
        FOREIGN KEY(subcategory_id) REFERENCES subcategories(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        description TEXT DEFAULT '',
        sort_order INTEGER DEFAULT 0
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

    // Custom tags (formerly Key:Value tags)
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


// Indexes for faster browsing & tag search
await db.execute('CREATE INDEX idx_subcategories_category_id ON subcategories(category_id);');
await db.execute('CREATE INDEX idx_items_subcategory_id ON items(subcategory_id);');
await db.execute('CREATE INDEX idx_item_tags_tag_id ON item_tags(tag_id);');
await db.execute('CREATE INDEX idx_item_tags_item_id ON item_tags(item_id);');
await db.execute('CREATE INDEX idx_tag_key_values_key_id ON tag_key_values(key_id);');
await db.execute('CREATE INDEX idx_item_kv_kv_id ON item_tag_key_values(key_value_id);');
await db.execute('CREATE INDEX idx_item_kv_item_id ON item_tag_key_values(item_id);');
await db.execute('CREATE INDEX idx_notes_updated_at ON notes(updated_at);');

    // Auto-tags: tags automatically applied to new items in a subcategory
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

  }

  Future<void> _upgradeToV2(Database db) async {
    // Items: add duration_ms if missing.
    await db.execute('ALTER TABLE items ADD COLUMN duration_ms INTEGER;');

    // Key:Value tags tables
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

    // Indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tag_key_values_key_id ON tag_key_values(key_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_item_kv_kv_id ON item_tag_key_values(key_value_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_item_kv_item_id ON item_tag_key_values(item_id);');
  }

  Future<void> _upgradeToV3(Database db) async {
    // Add description columns to categories, subcategories, tags, and tag_keys
    // Add sort_order to tag_keys
    
    // Check and add columns if they don't exist (safe migration)
    try {
      await db.execute("ALTER TABLE categories ADD COLUMN description TEXT DEFAULT ''");
    } catch (_) {
      // Column already exists
    }
    
    try {
      await db.execute("ALTER TABLE subcategories ADD COLUMN description TEXT DEFAULT ''");
    } catch (_) {}
    
    try {
      await db.execute("ALTER TABLE tags ADD COLUMN description TEXT DEFAULT ''");
    } catch (_) {}
    
    try {
      await db.execute("ALTER TABLE tag_keys ADD COLUMN description TEXT DEFAULT ''");
    } catch (_) {}
    
    try {
      await db.execute("ALTER TABLE tag_keys ADD COLUMN sort_order INTEGER DEFAULT 0");
    } catch (_) {}
    
    try {
      await db.execute("ALTER TABLE tags ADD COLUMN sort_order INTEGER DEFAULT 0");
    } catch (_) {}
  }

  Future<void> _upgradeToV4(Database db) async {
    try {
      await db.execute("ALTER TABLE tags ADD COLUMN sort_order INTEGER DEFAULT 0");
    } catch (_) {
      // Column already exists
    }
    
    try {
      await db.execute("ALTER TABLE tag_key_values ADD COLUMN description TEXT DEFAULT ''");
    } catch (_) {
      // Column already exists
    }
  }

  Future<void> _upgradeToV5(Database db) async {
    try {
      await db.execute("ALTER TABLE tag_key_values ADD COLUMN description TEXT DEFAULT ''");
    } catch (_) {
      // Column already exists
    }
  }

  Future<void> _upgradeToV6(Database db) async {
    // 1. Add sort_order to categories and subcategories
    try {
      await db.execute("ALTER TABLE categories ADD COLUMN sort_order INTEGER DEFAULT 0");
    } catch (_) {}
    
    try {
      await db.execute("ALTER TABLE subcategories ADD COLUMN sort_order INTEGER DEFAULT 0");
    } catch (_) {}

    // 2. Normalize sort_order for categories (assign 0, 1, 2, ... based on current name order)
    final cats = await db.query('categories', orderBy: 'name COLLATE NOCASE');
    for (int i = 0; i < cats.length; i++) {
      await db.update('categories', {'sort_order': i}, where: 'id=?', whereArgs: [cats[i]['id']]);
    }

    // 3. Normalize sort_order for subcategories per category
    final allSubs = await db.query('subcategories', orderBy: 'name COLLATE NOCASE');
    // Group by category
    final byCat = <String, List<Map<String, Object?>>>{};
    for (final s in allSubs) {
      final catId = s['category_id'] as String;
      byCat.putIfAbsent(catId, () => []).add(s);
    }
    for (final subs in byCat.values) {
      for (int i = 0; i < subs.length; i++) {
        await db.update('subcategories', {'sort_order': i}, where: 'id=?', whereArgs: [subs[i]['id']]);
      }
    }

    // 4. Normalize sort_order for tags (THE FIX for all-zero sort_order bug)
    final tags = await db.query('tags', orderBy: 'sort_order ASC, name COLLATE NOCASE');
    for (int i = 0; i < tags.length; i++) {
      await db.update('tags', {'sort_order': i}, where: 'id=?', whereArgs: [tags[i]['id']]);
    }

    // 5. Normalize sort_order for tag_keys
    final keys = await db.query('tag_keys', orderBy: 'sort_order ASC, key COLLATE NOCASE');
    for (int i = 0; i < keys.length; i++) {
      await db.update('tag_keys', {'sort_order': i}, where: 'id=?', whereArgs: [keys[i]['id']]);
    }
  }

  Future<void> _upgradeToV8(Database db) async {
    // Add sort_order to tag_key_values for reorderable values within keys.
    try {
      await db.execute('ALTER TABLE tag_key_values ADD COLUMN sort_order INTEGER DEFAULT 0');
    } catch (_) {
      // Column already exists — safe to ignore.
    }

    // Normalize: assign sequential sort_order (0, 1, 2...) per key, alphabetically.
    // This ensures existing values have a deterministic order from day one
    // rather than all sitting at 0.
    final keys = await db.query('tag_keys', columns: ['id']);
    for (final key in keys) {
      final keyId = key['id'] as String;
      final values = await db.query(
        'tag_key_values',
        where: 'key_id=?',
        whereArgs: [keyId],
        orderBy: 'value COLLATE NOCASE',
      );
      for (int i = 0; i < values.length; i++) {
        await db.update(
          'tag_key_values',
          {'sort_order': i},
          where: 'id=?',
          whereArgs: [values[i]['id']],
        );
      }
    }
  }

  Future<void> _upgradeToV7(Database db) async {
    // Auto-tags: tags automatically applied to new items in a subcategory
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
}
