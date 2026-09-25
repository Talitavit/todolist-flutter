import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/task.dart';
import '../state/task_logic.dart';
import '../state/task_store.dart';
import '../widgets/feedback.dart';
import 'category_screen.dart';
import 'task_editor_screen.dart';

class TaskListScreen extends StatelessWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TaskStore>();
    final tasks = store.visibleTasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minhas tarefas'),
        actions: [
          IconButton(
            tooltip: 'Categorias',
            icon: const Icon(Icons.label_outline),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const CategoryScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const TaskEditorScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Nova tarefa'),
      ),
      body: Column(
        children: [
          const _Filters(),
          const Divider(height: 1),
          Expanded(
            child: store.loading
                ? const Center(child: CircularProgressIndicator())
                : store.loadError != null
                    ? _Message(icon: Icons.error_outline, text: store.loadError!)
                    : tasks.isEmpty
                        ? _Message(
                            icon: Icons.checklist,
                            text: store.totalCount == 0
                                ? 'Nenhuma tarefa ainda.\nToque em "Nova tarefa" para começar.'
                                : 'Nenhuma tarefa corresponde aos filtros.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: tasks.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (_, i) => _TaskTile(task: tasks[i]),
                          ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TaskStore>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<StatusFilter>(
            segments: const [
              ButtonSegment(value: StatusFilter.all, label: Text('Todas')),
              ButtonSegment(value: StatusFilter.pending, label: Text('Pendentes')),
              ButtonSegment(value: StatusFilter.completed, label: Text('Concluídas')),
            ],
            selected: {store.statusFilter},
            showSelectedIcon: false,
            onSelectionChanged: (s) => store.setStatusFilter(s.first),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _categoryChip(context, store, null, 'Todas as categorias'),
                for (final c in store.categories)
                  _categoryChip(context, store, c.id, c.name, color: Color(c.colorValue)),
                _categoryChip(context, store, uncategorized, 'Sem categoria'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(BuildContext context, TaskStore store, int? id, String label,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        avatar: color == null ? null : CircleAvatar(backgroundColor: color, radius: 6),
        selected: store.categoryFilter == id,
        onSelected: (_) => store.setCategoryFilter(id),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final Task task;
  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final store = context.read<TaskStore>();
    final category = context.select<TaskStore, Category?>((s) => s.categoryById(task.categoryId));
    final theme = Theme.of(context);
    final due = task.dueDateTime;
    final overdue = due != null && !task.completed && due.isBefore(DateTime.now());

    return ListTile(
      leading: Checkbox(
        value: task.completed,
        onChanged: (v) async {
          try {
            await store.setCompleted(task, v ?? false);
          } catch (e) {
            if (context.mounted) showSnack(context, errorMessage(e));
          }
        },
      ),
      title: Text(
        task.title,
        style: task.completed
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: (category == null && due == null)
          ? Text(task.completed ? 'Concluída' : 'Pendente')
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(task.completed ? 'Concluída' : 'Pendente'),
                if (category != null) _CategoryBadge(category: category),
                if (due != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule,
                          size: 14, color: overdue ? theme.colorScheme.error : null),
                      const SizedBox(width: 2),
                      Text(
                        formatDateTime(due),
                        style: overdue ? TextStyle(color: theme.colorScheme.error) : null,
                      ),
                    ],
                  ),
              ],
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TaskEditorScreen(taskId: task.id)),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final Category category;
  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(category.name, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
