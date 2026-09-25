import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';
import '../state/task_logic.dart';

/// What happened when the app tried to make a task's reminder match its state.
enum ReminderOutcome {
  /// No reminder needed (no due date, past date or completed) — any old one was canceled.
  none,
  scheduled,

  /// Scheduled, but the exact-alarm permission is missing so Android may delay it.
  scheduledInexact,

  /// The user has notifications turned off; nothing will be shown.
  notificationsDisabled,
  failed,
}

/// Wraps flutter_local_notifications. The notification id is the task id,
/// so no extra column is needed to find/cancel a task's reminder.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  /// Task id from a notification tap (cold start or while running).
  final ValueNotifier<int?> openedTaskId = ValueNotifier(null);

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'task_reminders',
      'Lembretes de tarefas',
      channelDescription: 'Avisos no horário de vencimento das tarefas',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Scheduling uses absolute instants, so UTC still fires at the right moment.
      debugPrint('Timezone lookup failed, falling back to UTC: $e');
      tz.setLocalLocation(tz.UTC);
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) => _handlePayload(r.payload),
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _handlePayload(launch!.notificationResponse?.payload);
    }
  }

  void _handlePayload(String? payload) {
    final id = int.tryParse(payload ?? '');
    if (id != null) openedTaskId.value = id;
  }

  /// Asks for POST_NOTIFICATIONS (Android 13+). Returns false if denied; never throws.
  Future<bool> requestPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      return false;
    }
  }

  Future<bool> notificationsEnabled() async {
    try {
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> canScheduleExact() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "Alarms & reminders" screen for this app.
  Future<void> requestExactAlarms() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('Exact alarm request failed: $e');
    }
  }

  /// Cancels any existing reminder for [task] and schedules a new one if the
  /// task still needs it. Safe to call after every create/edit/toggle.
  Future<ReminderOutcome> sync(Task task) async {
    final id = task.id;
    if (id == null) return ReminderOutcome.none;
    try {
      await _plugin.cancel(id: id);
      if (!shouldHaveReminder(task, DateTime.now())) return ReminderOutcome.none;

      final exact = await canScheduleExact();
      await _plugin.zonedSchedule(
        id: id,
        title: 'Lembrete de tarefa',
        body: task.title,
        payload: '$id',
        scheduledDate: tz.TZDateTime.from(task.dueDateTime!, tz.local),
        notificationDetails: _details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
      if (!await notificationsEnabled()) return ReminderOutcome.notificationsDisabled;
      return exact ? ReminderOutcome.scheduled : ReminderOutcome.scheduledInexact;
    } catch (e) {
      debugPrint('Failed to sync reminder for task $id: $e');
      return ReminderOutcome.failed;
    }
  }

  Future<void> cancel(int taskId) async {
    try {
      await _plugin.cancel(id: taskId);
    } catch (e) {
      debugPrint('Failed to cancel reminder $taskId: $e');
    }
  }
}
