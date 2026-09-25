// foundation.dart also exports an unrelated `Category` annotation.
import 'package:flutter/foundation.dart' hide Category;

import '../data/task_repository.dart';
import '../models/category.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import 'task_logic.dart';

/// Single app-wide state holder (ChangeNotifier exposed through `provider`).
///
/// Every mutation goes: SQLite write → reminder sync → reload from SQLite →
/// notifyListeners(). The database is the source of truth; the in-memory lists
/// are just the latest snapshot for the UI.
class TaskStore extends ChangeNotifier {
  final TaskRepository _tasks;
  final CategoryRepository _categories;
  final NotificationService _notifications;

  TaskStore(this._tasks, this._categories, this._notifications);

  List<Task> _allTasks = [];
  List<Category> _allCategories = [];
  bool _loading = true;
  String? _loadError;
  StatusFilter _status = StatusFilter.all;
  int? _categoryFilter;

  bool get loading => _loading;
  String? get loadError => _loadError;
  List<Category> get categories => List.unmodifiable(_allCategories);
  StatusFilter get statusFilter => _status;
  int? get categoryFilter => _categoryFilter;
  int get totalCount => _allTasks.length;
  List<Task> get visibleTasks => filterTasks(_allTasks, _status, _categoryFilter);

  Category? categoryById(int? id) {
    if (id == null) return null;
    for (final c in _allCategories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> load() async {
    try {
      _allTasks = await _tasks.getAll();
      _allCategories = await _categories.getAll();
      _loadError = null;
    } catch (e) {
      debugPrint('Load failed: $e');
      _loadError = 'Não foi possível carregar os dados.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Re-applies reminders for every task (idempotent: same id replaces).
  /// Covers reminders lost after reinstall/data restore or a changed timezone.
  Future<void> resyncReminders() async {
    for (final t in _allTasks) {
      await _notifications.sync(t);
    }
  }

  void setStatusFilter(StatusFilter f) {
    _status = f;
    notifyListeners();
  }

  void setCategoryFilter(int? id) {
    _categoryFilter = id;
    notifyListeners();
  }

  // ---- Tasks -------------------------------------------------------------

  Future<Task?> getTask(int id) => _tasks.getById(id);

  /// Inserts or updates, then syncs the reminder. DB errors propagate to the UI.
  Future<ReminderOutcome> saveTask(Task task) async {
    final saved = task.id == null ? await _tasks.insert(task) : task;
    if (task.id != null) await _tasks.update(task);
    final outcome = await _notifications.sync(saved);
    await load();
    return outcome;
  }

  Future<ReminderOutcome> setCompleted(Task task, bool completed) =>
      saveTask(task.copyWith(completed: completed));

  Future<void> deleteTask(Task task) async {
    await _tasks.delete(task.id!);
    await _notifications.cancel(task.id!);
    await load();
  }

  // ---- Categories --------------------------------------------------------

  Future<void> addCategory(String name) async {
    final color = Category.palette[_allCategories.length % Category.palette.length];
    await _categories.insert(Category(name: name.trim(), colorValue: color));
    await load();
  }

  Future<void> renameCategory(Category c, String name) async {
    await _categories.update(c.copyWith(name: name.trim()));
    await load();
  }

  Future<int> countTasksInCategory(int id) => _categories.countTasks(id);

  Future<void> deleteCategory(Category c) async {
    await _categories.delete(c.id!);
    if (_categoryFilter == c.id) _categoryFilter = null;
    await load();
  }
}
