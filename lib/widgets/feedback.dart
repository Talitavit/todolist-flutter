import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../services/notification_service.dart';

void showSnack(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

/// Human-readable message for an exception thrown by a store/repository call.
String errorMessage(Object error) {
  if (error is DatabaseException) {
    if (error.isUniqueConstraintError()) return 'Já existe um item com esse nome.';
    return 'Erro no banco de dados. Tente novamente.';
  }
  return 'Algo deu errado. Tente novamente.';
}

/// Feedback text for a reminder outcome, or null when nothing needs saying.
String? reminderMessage(ReminderOutcome outcome) => switch (outcome) {
      ReminderOutcome.none => null,
      ReminderOutcome.scheduled => 'Lembrete agendado.',
      ReminderOutcome.scheduledInexact =>
        'Lembrete agendado, mas pode atrasar alguns minutos (permissão de alarmes exatos desativada).',
      ReminderOutcome.notificationsDisabled =>
        'Tarefa salva, mas as notificações estão desativadas — o lembrete não aparecerá.',
      ReminderOutcome.failed => 'Tarefa salva, mas não foi possível agendar o lembrete.',
    };

final _dateTimeFormat = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
final dateFormat = DateFormat('EEE, dd/MM/yyyy', 'pt_BR');

String formatDateTime(DateTime d) => _dateTimeFormat.format(d);
