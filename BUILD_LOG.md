# BUILD_LOG.md — Mobile To-Do App (Flutter)

Running development history for the Flutter version of the to-do app. Entries are
appended chronologically and are never rewritten after the fact. If a decision is later
reversed, the old entry stays and a new entry documents the correction.

---

## Entry 1 — Project kickoff and environment survey

### Prompt / Request
> "Vamos iniciar uma aplicação nativa em dart, flutter, lembrando que quando compilar,
> compile para meu celular que está conectado via wifi, a ideia da aplicação é:"
> followed by the full *Mobile To-Do App — Implementation Specification* (SQLite,
> 3 screens, categories, filtering, optional due date/time, scheduled local
> notifications, continuous `BUILD_LOG.md`).

### Decision Summary
- New Flutter project lives in `todolist/todolist-flutter/`, next to the existing
  Kotlin/Compose implementation in the parent folder (which has its own BUILD_LOG).
  The two apps are independent; this log only covers the Flutter version.
- Android application id: `com.todolist.flutter_app` — different from the Kotlin app's
  `com.todolist.app`, so both can be installed side by side on the phone.
- Build target: the physical phone already paired over wireless ADB
  (Samsung SM-A146M, `adb-RQCW50ALT9H-...._adb-tls-connect._tcp`).

### Environment survey performed
- `flutter`/`dart` not on PATH, no Flutter SDK found in common locations.
- Android SDK present at `%LOCALAPPDATA%\Android\Sdk`; `adb devices -l` lists the
  phone over TLS/Wi-Fi.
- With the user's approval, cloned Flutter **stable** (`git clone --depth 1 -b stable`)
  into `C:\Users\Talita\flutter`. The system PATH was not modified; the SDK is invoked
  by its full path.

### Result
- SDK cloned; first-run bootstrap (Dart SDK download, `flutter doctor`) in progress.

### Current Status
Partially completed

---

## Entry 2 — Flutter bootstrap and project scaffold

### Prompt / Request
Same kickoff request (Entry 1): build the spec'd app in Flutter, deploy to the phone.

### Decision Summary
- Flutter **3.47.5 stable** / Dart 3.13.4. `flutter doctor` reports `cmdline-tools`
  missing and "license status unknown", but `%LOCALAPPDATA%\Android\Sdk\licenses\android-sdk-license`
  already exists (the Kotlin app was built on this machine), so Gradle is expected to
  build anyway. Chrome/Visual Studio missing is irrelevant (Android only).
- `flutter create --org com.todolist --project-name flutter_app --platforms android .`
  → application id `com.todolist.flutter_app`. Android-only for now; iOS would need a Mac.
- App label on the phone: **"Tarefas Flutter"** (to distinguish from the Kotlin app).
- UI language: **pt-BR** (the user writes in Portuguese and the Kotlin version was
  translated to pt-BR). Code, comments and this log stay in English.

### Actions Performed
- Created the Flutter project in `todolist-flutter/` (BUILD_LOG.md was moved aside and
  back so `flutter create` would run on an empty dir).
- `flutter config --android-sdk %LOCALAPPDATA%\Android\Sdk --no-analytics`.

### Result
Project scaffold generated. Phone is visible to Flutter as
`SM A146M (wireless) • android-arm64 • Android 15 (API 35)`.

### Current Status
Completed

---

## Entry 3 — Architecture, dependencies, SQLite schema, screens, notifications

### Prompt / Request
Implement the specification (sections 2–16).

### Decision Summary

**Architecture** — small layered structure, no Clean-Architecture ceremony:
```
lib/
  models/      Task, Category (plain immutable classes + toMap/fromMap)
  data/        AppDatabase (open + schema), TaskRepository, CategoryRepository (direct SQL via sqflite)
  services/    NotificationService (flutter_local_notifications wrapper)
  state/       TaskStore (ChangeNotifier), task_logic.dart (pure filter + reminder rule)
  screens/     TaskListScreen, TaskEditorScreen, CategoryScreen
  widgets/     feedback.dart (snackbars, error/reminder messages, date formats)
```

**Dependencies**

| Package | Purpose | Why |
|---|---|---|
| `sqflite` | SQLite access | De-facto standard SQLite plugin for Flutter; plain SQL keeps the schema visible (no codegen like drift/floor, overkill for 2 tables). |
| `path` | Build DB file path | Tiny, recommended with sqflite. |
| `provider` | State management / DI | Officially recommended simple approach; one `ChangeNotifier` is enough for 3 screens. Riverpod/Bloc considered and rejected as unnecessary complexity. |
| `flutter_local_notifications` | Scheduled local notifications | Most mature local-notification plugin; `zonedSchedule` with exact/inexact alarms and reboot re-scheduling. |
| `timezone` | `TZDateTime` required by `zonedSchedule` | Required by the plugin API. |
| `flutter_timezone` | Device IANA timezone name | To set `tz.local`; falls back to UTC on failure (still fires at the right instant since scheduling uses absolute time). |
| `intl` + `flutter_localizations` | pt-BR date formatting and pt-BR date/time pickers | Standard. |

**SQLite strategy** — direct SQL through sqflite, single DB file `todo.db`, schema v1:
- `categories(id INTEGER PK AUTOINCREMENT, name TEXT NOT NULL UNIQUE COLLATE NOCASE, color INTEGER NOT NULL)`
- `tasks(id INTEGER PK AUTOINCREMENT, title TEXT NOT NULL CHECK (length(trim(title)) > 0), description TEXT NOT NULL DEFAULT '', completed INTEGER 0/1, due_date_time INTEGER NULL (epoch ms), created_at INTEGER (epoch ms), category_id INTEGER NULL REFERENCES categories(id) ON DELETE SET NULL)`
- `PRAGMA foreign_keys = ON` in `onConfigure` (SQLite has FKs off by default).
- Four default categories seeded on creation: Pessoal, Trabalho, Estudos, Compras.
- Extra field beyond the spec: `Category.color` (ARGB int) for chips/badges. No extra
  task fields were needed.

**Category deletion** — tasks become **uncategorized** (FK `ON DELETE SET NULL`).
Before deleting, the screen counts affected tasks and the confirmation dialog says how
many tasks will lose their category (and that they are not deleted). If the deleted
category was the active list filter, the filter resets to "all" (lesson carried over
from the Kotlin version, commit 4bbb739). Duplicate names (case-insensitive) are
rejected by the UNIQUE constraint and shown as a friendly snackbar.

**State management** — one `TaskStore extends ChangeNotifier` provided at the root.
Every mutation: write SQLite → sync reminder → reload lists from SQLite →
`notifyListeners()`. SQLite stays the source of truth; screens `watch` the store so the
list refreshes after create/edit/delete/toggle/category changes/filter changes.

**Filtering** — **in memory** over the loaded task list (`filterTasks` in
`task_logic.dart`, a pure, unit-tested function). Status: SegmentedButton
(Todas/Pendentes/Concluídas). Category: horizontal ChoiceChips ("Todas as categorias",
each category, "Sem categoria"). "Sem categoria" uses sentinel id `0`, safe because
AUTOINCREMENT ids start at 1. Rationale: small dataset, instant filter changes with no
DB round-trip; ordering (pending first, then by due date) is still done in SQL.

**Navigation** — imperative `Navigator.push(MaterialPageRoute(...))`: list → editor,
list → categories. Editing passes **only the task id**; the editor re-reads the task
from SQLite, so it always shows persisted values and handles "task no longer exists"
(e.g. opened from an old notification) by showing a message and popping. A root
`navigatorKey` lets a notification tap open the editor for that task.

**Task editor** — title required (validator + DB CHECK), description optional, date
picker + time picker (time defaults to 09:00 if only a date is chosen), "remove date"
button, category dropdown with "Sem categoria", "Concluída" switch. Save / Cancel
(X button; asks to discard unsaved changes, also on system back via `PopScope`) /
Delete (with confirmation). A past date is **allowed** (tasks can be overdue) but the
editor warns that no reminder will be scheduled.

**Notification strategy**
- Notification id = task id (SQLite INTEGER PK) → no extra column needed to cancel.
- `NotificationService.sync(task)` is the single entry point: always `cancel(id)` first,
  then schedule only if `shouldHaveReminder` (pending AND due date in the future).
  Called after create, edit, complete and reopen, so: date changed → old canceled, new
  scheduled; date removed → canceled; completed → canceled; reopened with future
  date → scheduled again. Delete calls `cancel(id)`.
- Fires at the due date/time itself, title "Lembrete de tarefa", body = task title,
  payload = task id (tap opens the editor).
- At startup all tasks are re-synced (idempotent) to recover reminders after a
  reinstall/restore. Reboot persistence is handled by the plugin's
  `ScheduledNotificationBootReceiver`.
- Android setup: `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`
  permissions, the plugin's two receivers, core library desugaring
  (`desugar_jdk_libs 2.1.4`) as required by the plugin.

**Permissions**
- `POST_NOTIFICATIONS` (Android 13+) requested once after the first frame. Denial is
  not an error: tasks still save; the editor shows "notificações desativadas" and the
  save snackbar says the reminder won't appear.
- Exact alarms: `SCHEDULE_EXACT_ALARM` (not `USE_EXACT_ALARM`, which Play policy
  reserves for alarm/calendar apps). If not granted, reminders use
  `inexactAllowWhileIdle` (may be a few minutes late) and the editor offers a
  "Permitir alarmes exatos" button that opens the system setting.
- Every plugin call is wrapped in try/catch and reported as a `ReminderOutcome`
  (none/scheduled/scheduledInexact/notificationsDisabled/failed), never a crash.

**Error handling** — repository exceptions propagate to the UI, which shows a snackbar
(`errorMessage`: unique-constraint → "Já existe um item com esse nome", other DB
errors → generic message). Load failure shows an error state on the list. The editor
disables Save/Delete while an operation runs to avoid double submits.

### Actions Performed
- Added dependencies (table above) via `flutter pub add`, plus `flutter_localizations`.
- `android/app/build.gradle.kts`: `isCoreLibraryDesugaringEnabled = true` + desugar dependency.
- `AndroidManifest.xml`: permissions, receivers, label "Tarefas Flutter".
- Created all files under `lib/` listed above; replaced template `test/widget_test.dart`
  with unit tests for `shouldHaveReminder`, `filterTasks` and `Task.copyWith`.

### Problems / Errors
- `flutter analyze` → 9 errors `ambiguous_import`: **`Category` is also exported by
  `package:flutter/foundation.dart`** (an annotation class), clashing with the model in
  `task_store.dart`. Also one `use_build_context_synchronously` info in the editor
  (`context.read` after an `await`).

### Fixes Attempted
- `import 'package:flutter/foundation.dart' hide Category;` in `task_store.dart` — fixed.
- Read the `TaskStore` from context before the first `await` in the editor's `_load` — fixed.

### Result
`flutter analyze`: no issues. `flutter test`: 8/8 passed.

### Current Status
Needs testing (on device)

---

## Entry 4 — First build and install on the phone (Wi-Fi ADB)

### Prompt / Request
> "ok, me avisa quando instalar no celular"

### Decision Summary
- Built with `flutter build apk --debug`, then installed with
  `adb install -r` over the existing wireless ADB connection instead of `flutter run`,
  so the build doesn't depend on keeping an interactive session attached.

### Actions Performed
- `flutter build apk --debug` → `build/app/outputs/flutter-apk/app-debug.apk`.
- `adb install -r app-debug.apk` → `Success`; launched `com.todolist.flutter_app/.MainActivity`.

### Result
- Build succeeded, but the first build took **~26 min (1543.9 s)**: Gradle
  auto-installed missing SDK components (NDK 28.2.13676358 ~2 GB, Android SDK
  Platforms 35 and 36, CMake 3.22.1). Licenses were already accepted, so
  `cmdline-tools` being missing (doctor warning) did not block it.
- App process started (pid alive) and logcat shows no `FATAL`/`AndroidRuntime` errors.
- Could not visually verify the UI: the phone was **locked with the screen off**
  (`mWakefulness=Dozing`, `isKeyguardShowing=true`); screencap returned a black image.

### Problems / Errors
- Build warning: some plugins still apply the Kotlin Gradle Plugin (KGP); "future
  versions of Flutter will fail to build" — not an error today. Plugins will need
  upgrades when their authors migrate to Built-in Kotlin.

### Current Status
Needs testing — installed; manual on-device test of the flows pending (phone locked).
