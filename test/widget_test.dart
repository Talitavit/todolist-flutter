import 'package:flutter_app/models/task.dart';
import 'package:flutter_app/state/task_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 24, 12);
  Task task({bool completed = false, DateTime? due, int? categoryId}) => Task(
        id: 1,
        title: 't',
        completed: completed,
        dueDateTime: due,
        createdAt: now,
        categoryId: categoryId,
      );

  group('shouldHaveReminder', () {
    test('future due date on pending task', () {
      expect(shouldHaveReminder(task(due: now.add(const Duration(hours: 1))), now), isTrue);
    });
    test('no due date', () => expect(shouldHaveReminder(task(), now), isFalse));
    test('past due date', () {
      expect(shouldHaveReminder(task(due: now.subtract(const Duration(minutes: 1))), now), isFalse);
    });
    test('completed task', () {
      expect(
          shouldHaveReminder(task(completed: true, due: now.add(const Duration(days: 1))), now),
          isFalse);
    });
  });

  group('filterTasks', () {
    final tasks = [
      task(categoryId: 1),
      task(completed: true, categoryId: 1),
      task(categoryId: 2),
      task(completed: true),
    ];

    test('status', () {
      expect(filterTasks(tasks, StatusFilter.all, null).length, 4);
      expect(filterTasks(tasks, StatusFilter.pending, null).length, 2);
      expect(filterTasks(tasks, StatusFilter.completed, null).length, 2);
    });
    test('category', () {
      expect(filterTasks(tasks, StatusFilter.all, 1).length, 2);
      expect(filterTasks(tasks, StatusFilter.all, uncategorized).length, 1);
    });
    test('status and category combined', () {
      expect(filterTasks(tasks, StatusFilter.pending, 1).length, 1);
      expect(filterTasks(tasks, StatusFilter.completed, 2), isEmpty);
    });
  });

  test('copyWith clears nullable fields only when asked', () {
    final t = task(due: now, categoryId: 3);
    expect(t.copyWith(title: 'x').dueDateTime, now);
    expect(t.copyWith(clearDueDateTime: true).dueDateTime, isNull);
    expect(t.copyWith(clearCategory: true).categoryId, isNull);
  });
}
