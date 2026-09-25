import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../services/notification_service.dart';
import '../state/task_store.dart';
import '../widgets/feedback.dart';

/// Creates a task (`taskId == null`) or edits one. Only the id is passed in;
/// the task is re-read from SQLite so the form always shows persisted values.
class TaskEditorScreen extends StatefulWidget {
  final int? taskId;
  const TaskEditorScreen({super.key, this.taskId});

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  static const _defaultTime = TimeOfDay(hour: 9, minute: 0);

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();

  Task? _original;
  bool _loading = true;
  bool _saving = false;
  DateTime? _date; // date part only
  TimeOfDay? _time;
  int? _categoryId;
  bool _completed = false;
  bool _notificationsEnabled = true;
  bool _exactAllowed = true;

  bool get _isNew => widget.taskId == null;

  DateTime? get _due {
    final d = _date;
    if (d == null) return null;
    final t = _time ?? _defaultTime;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notifications = context.read<NotificationService>();
    final store = context.read<TaskStore>();
    _notificationsEnabled = await notifications.notificationsEnabled();
    _exactAllowed = await notifications.canScheduleExact();

    if (!_isNew) {
      Task? task;
      try {
        task = await store.getTask(widget.taskId!);
      } catch (_) {}
      if (!mounted) return;
      if (task == null) {
        showSnack(context, 'Tarefa não encontrada.');
        Navigator.of(context).pop();
        return;
      }
      _original = task;
      _title.text = task.title;
      _description.text = task.description;
      _completed = task.completed;
      _categoryId = task.categoryId;
      final due = task.dueDateTime;
      if (due != null) {
        _date = DateTime(due.year, due.month, due.day);
        _time = TimeOfDay.fromDateTime(due);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _dirty {
    final o = _original;
    if (o == null) {
      return _title.text.trim().isNotEmpty ||
          _description.text.trim().isNotEmpty ||
          _date != null ||
          _categoryId != null ||
          _completed;
    }
    return o.title != _title.text.trim() ||
        o.description != _description.text.trim() ||
        o.dueDateTime != _due ||
        o.categoryId != _categoryId ||
        o.completed != _completed;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time ?? _defaultTime);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final task = (_original ?? Task(title: '', createdAt: DateTime.now())).copyWith(
      title: _title.text.trim(),
      description: _description.text.trim(),
      completed: _completed,
      dueDateTime: _due,
      clearDueDateTime: _due == null,
      categoryId: _categoryId,
      clearCategory: _categoryId == null,
    );

    final messenger = ScaffoldMessenger.of(context);
    try {
      final outcome = await context.read<TaskStore>().saveTask(task);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(reminderMessage(outcome) ?? (_isNew ? 'Tarefa criada.' : 'Tarefa salva.')),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, errorMessage(e));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir tarefa?'),
        content: Text('"${_original!.title}" será excluída permanentemente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<TaskStore>().deleteTask(_original!);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Tarefa excluída.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, errorMessage(e));
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar alterações?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuar editando')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Descartar')),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _cancel() async {
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<TaskStore>().categories;
    // The dropdown must not reference a category deleted meanwhile.
    if (_categoryId != null && !categories.any((c) => c.id == _categoryId)) {
      _categoryId = null;
    }

    return PopScope(
      canPop: _loading || _saving || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Cancelar',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : _cancel,
          ),
          title: Text(_isNew ? 'Nova tarefa' : 'Editar tarefa'),
          actions: [
            if (!_isNew && !_loading)
              IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : _delete,
              ),
            TextButton(
              onPressed: _loading || _saving ? null : _save,
              child: const Text('Salvar'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _title,
                      autofocus: _isNew,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Título *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Informe um título.' : null,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _description,
                      minLines: 3,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Descrição (opcional)',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int?>(
                      initialValue: _categoryId,
                      decoration: const InputDecoration(
                        labelText: 'Categoria',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Sem categoria')),
                        for (final c in categories)
                          DropdownMenuItem(
                            value: c.id,
                            child: Row(children: [
                              CircleAvatar(backgroundColor: Color(c.colorValue), radius: 6),
                              const SizedBox(width: 8),
                              Text(c.name),
                            ]),
                          ),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                    const SizedBox(height: 16),
                    _dueSection(context),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Concluída'),
                      value: _completed,
                      onChanged: (v) => setState(() => _completed = v),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _dueSection(BuildContext context) {
    final theme = Theme.of(context);
    final due = _due;
    final inPast = due != null && !due.isAfter(DateTime.now());

    String? hint;
    if (due != null && !_completed) {
      if (inPast) {
        hint = 'Data/hora no passado: nenhum lembrete será agendado.';
      } else if (!_notificationsEnabled) {
        hint = 'Notificações desativadas para o app: o lembrete não será exibido.';
      }
    } else if (due != null && _completed) {
      hint = 'Tarefas concluídas não recebem lembrete.';
    }

    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.event),
              title: Text(_date == null ? 'Sem data de vencimento' : dateFormat.format(_date!)),
              subtitle: const Text('Data'),
              onTap: _pickDate,
              trailing: _date == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      tooltip: 'Remover data',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _date = null;
                        _time = null;
                      }),
                    ),
            ),
            ListTile(
              enabled: _date != null,
              leading: const Icon(Icons.schedule),
              title: Text(_date == null
                  ? '—'
                  : (_time ?? _defaultTime).format(context) + (_time == null ? ' (padrão)' : '')),
              subtitle: const Text('Hora'),
              onTap: _pickTime,
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(hint,
                    style: TextStyle(color: inPast ? theme.colorScheme.error : null, fontSize: 13)),
              ),
            if (due != null && !inPast && !_completed && !_exactAllowed)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: TextButton.icon(
                  icon: const Icon(Icons.alarm),
                  label: const Text('Permitir alarmes exatos (lembrete pontual)'),
                  onPressed: () async {
                    final n = context.read<NotificationService>();
                    await n.requestExactAlarms();
                    final allowed = await n.canScheduleExact();
                    if (mounted) setState(() => _exactAllowed = allowed);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
