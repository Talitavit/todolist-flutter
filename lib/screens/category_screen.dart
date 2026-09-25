import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../state/task_store.dart';
import '../widgets/feedback.dart';

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TaskStore>();
    final categories = store.categories;

    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.add),
        label: const Text('Nova categoria'),
      ),
      body: categories.isEmpty
          ? const Center(child: Text('Nenhuma categoria.'))
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = categories[i];
                return ListTile(
                  leading: CircleAvatar(backgroundColor: Color(c.colorValue), radius: 10),
                  title: Text(c.name),
                  onTap: () => _rename(context, c),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Renomear',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _rename(context, c),
                      ),
                      IconButton(
                        tooltip: 'Excluir',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(context, c),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await _askName(context, title: 'Nova categoria');
    if (name == null || !context.mounted) return;
    try {
      await context.read<TaskStore>().addCategory(name);
      if (context.mounted) showSnack(context, 'Categoria "$name" criada.');
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e));
    }
  }

  Future<void> _rename(BuildContext context, Category c) async {
    final name = await _askName(context, title: 'Renomear categoria', initial: c.name);
    if (name == null || name == c.name || !context.mounted) return;
    try {
      await context.read<TaskStore>().renameCategory(c, name);
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e));
    }
  }

  Future<void> _delete(BuildContext context, Category c) async {
    final store = context.read<TaskStore>();
    int count;
    try {
      count = await store.countTasksInCategory(c.id!);
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e));
      return;
    }
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir "${c.name}"?'),
        content: Text(count == 0
            ? 'Nenhuma tarefa usa esta categoria.'
            : count == 1
                ? '1 tarefa usa esta categoria e ficará sem categoria. A tarefa não será excluída.'
                : '$count tarefas usam esta categoria e ficarão sem categoria. As tarefas não serão excluídas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await store.deleteCategory(c);
      if (context.mounted) showSnack(context, 'Categoria excluída.');
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e));
    }
  }
}

/// Returns the trimmed name, or null if canceled.
Future<String?> _askName(BuildContext context, {required String title, String initial = ''}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial),
  );
}

class _NameDialog extends StatefulWidget {
  final String title;
  final String initial;
  const _NameDialog({required this.title, required this.initial});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe um nome.' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Salvar')),
      ],
    );
  }
}
