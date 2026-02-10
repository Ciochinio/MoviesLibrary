\
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
        version: 1,
        onCreate: (db, version) async {
          await _createSchema(db);
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
  }
}
