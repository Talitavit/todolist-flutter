import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/category.dart';

/// Opens the single SQLite database file used by the app and owns its schema.
class AppDatabase {
  static const _fileName = 'todo.db';
  static const _version = 1;

  static Future<Database> open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, _fileName),
      version: _version,
      // Foreign keys are off by default in SQLite; ON DELETE SET NULL needs them.
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        name  TEXT NOT NULL UNIQUE COLLATE NOCASE,
        color INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE tasks (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        title         TEXT NOT NULL CHECK (length(trim(title)) > 0),
        description   TEXT NOT NULL DEFAULT '',
        completed     INTEGER NOT NULL DEFAULT 0,
        due_date_time INTEGER,
        created_at    INTEGER NOT NULL,
        category_id   INTEGER REFERENCES categories(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_tasks_category ON tasks(category_id)');

    const defaults = ['Pessoal', 'Trabalho', 'Estudos', 'Compras'];
    for (var i = 0; i < defaults.length; i++) {
      await db.insert(
        'categories',
        Category(name: defaults[i], colorValue: Category.palette[i]).toMap(),
      );
    }
  }
}
