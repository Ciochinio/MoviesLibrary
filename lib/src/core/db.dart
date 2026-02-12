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
        version: 2,
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
        name TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE subcategories (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL,
        name TEXT NOT NULL,
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
        name TEXT NOT NULL UNIQUE
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

    // Key:Value tags
    await db.execute('''
      CREATE TABLE tag_keys (
        id TEXT PRIMARY KEY,
        key TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE tag_key_values (
        id TEXT PRIMARY KEY,
        key_id TEXT NOT NULL,
        value TEXT NOT NULL,
        created_at INTEGER NOT NULL,
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
}
