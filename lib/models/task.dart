/// A to-do item, persisted in the `tasks` table.
///
/// Dates are stored in SQLite as INTEGER milliseconds since epoch.
class Task {
  final int? id;
  final String title;
  final String description;
  final bool completed;
  final DateTime? dueDateTime;
  final DateTime createdAt;
  final int? categoryId;

  const Task({
    this.id,
    required this.title,
    this.description = '',
    this.completed = false,
    this.dueDateTime,
    required this.createdAt,
    this.categoryId,
  });

  /// `copyWith` cannot express "set to null" with plain optional params, so the
  /// nullable fields use explicit `clear*` flags.
  Task copyWith({
    int? id,
    String? title,
    String? description,
    bool? completed,
    DateTime? dueDateTime,
    bool clearDueDateTime = false,
    int? categoryId,
    bool clearCategory = false,
  }) =>
      Task(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        completed: completed ?? this.completed,
        dueDateTime: clearDueDateTime ? null : (dueDateTime ?? this.dueDateTime),
        createdAt: createdAt,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'description': description,
        'completed': completed ? 1 : 0,
        'due_date_time': dueDateTime?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'category_id': categoryId,
      };

  factory Task.fromMap(Map<String, Object?> map) {
    final due = map['due_date_time'] as int?;
    return Task(
      id: map['id'] as int,
      title: map['title'] as String,
      description: (map['description'] as String?) ?? '',
      completed: (map['completed'] as int) == 1,
      dueDateTime: due == null ? null : DateTime.fromMillisecondsSinceEpoch(due),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      categoryId: map['category_id'] as int?,
    );
  }
}
