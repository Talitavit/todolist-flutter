import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'data/app_database.dart';
import 'data/task_repository.dart';
import 'screens/task_editor_screen.dart';
import 'screens/task_list_screen.dart';
import 'services/notification_service.dart';
import 'state/task_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');

  final notifications = NotificationService();
  await notifications.init();

  final db = await AppDatabase.open();
  final store = TaskStore(TaskRepository(db), CategoryRepository(db), notifications);
  await store.load();

  runApp(TodoApp(store: store, notifications: notifications));
}

class TodoApp extends StatefulWidget {
  final TaskStore store;
  final NotificationService notifications;

  const TodoApp({super.key, required this.store, required this.notifications});

  @override
  State<TodoApp> createState() => _TodoAppState();
}

class _TodoAppState extends State<TodoApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    widget.notifications.openedTaskId.addListener(_openTaskFromNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _openTaskFromNotification();
      // Ask once at startup (Android 13+). Denial is fine: the app keeps working
      // and the editor explains that reminders won't be shown.
      await widget.notifications.requestPermission();
      await widget.store.resyncReminders();
    });
  }

  @override
  void dispose() {
    widget.notifications.openedTaskId.removeListener(_openTaskFromNotification);
    super.dispose();
  }

  void _openTaskFromNotification() {
    final id = widget.notifications.openedTaskId.value;
    final nav = _navigatorKey.currentState;
    if (id == null || nav == null) return;
    widget.notifications.openedTaskId.value = null;
    nav.push(MaterialPageRoute(builder: (_) => TaskEditorScreen(taskId: id)));
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.store),
        Provider.value(value: widget.notifications),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Tarefas',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const TaskListScreen(),
      ),
    );
  }
}
