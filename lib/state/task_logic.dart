import '../models/task.dart';

/// Pure functions kept free of Flutter/SQLite so they can be unit tested.

enum StatusFilter { all, pending, completed }

/// Category filter: `null` = all categories, [uncategorized] = tasks without
/// a category, any other value = that category id. SQLite AUTOINCREMENT ids
/// start at 1, so 0 can never collide with a real category.
const int uncategorized = 0;

List<Task> filterTasks(List<Task> tasks, StatusFilter status, int? categoryId) {
  return tasks.where((t) {
    final statusOk = switch (status) {
      StatusFilter.all => true,
      StatusFilter.pending => !t.completed,
      StatusFilter.completed => t.completed,
    };
    final categoryOk = categoryId == null ||
        (categoryId == uncategorized ? t.categoryId == null : t.categoryId == categoryId);
    return statusOk && categoryOk;
  }).toList();
}

/// A reminder exists only for pending tasks whose due date is still ahead.
bool shouldHaveReminder(Task task, DateTime now) =>
    !task.completed && task.dueDateTime != null && task.dueDateTime!.isAfter(now);
