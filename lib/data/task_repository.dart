import 'package:sqflite/sqflite.dart';

import '../models/category.dart';
import '../models/task.dart';

class TaskRepository {
  final Database _db;
  TaskRepository(this._db);

  /// Pending tasks first, then by due date (tasks without one last), then newest.
  Future<List<Task>> getAll() async {
    final rows = await _db.query(
      'tasks',
      orderBy: 'completed ASC, due_date_time IS NULL, due_date_time ASC, created_at DESC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<Task?> getById(int id) async {
    final rows = await _db.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  /// Returns the task with its generated id.
  Future<Task> insert(Task task) async {
    final id = await _db.insert('tasks', task.toMap()..remove('id'));
    return task.copyWith(id: id);
  }

  Future<void> update(Task task) async {
    await _db.update('tasks', task.toMap(), where: 'id = ?', whereArgs: [task.id]);
  }

  Future<void> delete(int id) async {
    await _db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }
}

class CategoryRepository {
  final Database _db;
  CategoryRepository(this._db);

  Future<List<Category>> getAll() async {
    final rows = await _db.query('categories', orderBy: 'name COLLATE NOCASE');
    return rows.map(Category.fromMap).toList();
  }

  Future<Category> insert(Category category) async {
    final id = await _db.insert('categories', category.toMap()..remove('id'));
    return category.copyWith(id: id);
  }

  Future<void> update(Category category) async {
    await _db.update('categories', category.toMap(),
        where: 'id = ?', whereArgs: [category.id]);
  }

  /// Tasks referencing the category become uncategorized (FK ON DELETE SET NULL).
  Future<void> delete(int id) async {
    await _db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countTasks(int categoryId) async {
    final result = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM tasks WHERE category_id = ?', [categoryId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
