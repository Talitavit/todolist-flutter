# Perguntas sobre Engenharia Reversa de Aplicativo Móvel

## 1. Estrutura do Projeto

A estrutura principal está organizada da seguinte forma:

- UI/screens
    - lib/screens/
        - task_list_screen.dart 
        - task_editor_screen.dart 
        - category_screen.dart 
    - lib/widgets/
        - feedback.dart (snackbars, mensagens de erro/lembrete, formatação de datas)

- Modelos e persistência
    - lib/models/
        - task.dart
        - category.dart 
    - lib/data/
        - app_database.dart 
        - task_repository.dart 

- Estado
    - lib/state/
        - task_store.dart 
        - task_logic.dart 

- Navegação
    - Navigator.push com MaterialPageRoute, chamado direto nas telas
    - lib/main.dart → navigatorKey (abre o editor a partir do toque na notificação)

- Notificações
    - lib/services/
        - notification_service.dart 
        - android/app/src/main/AndroidManifest.xml
        - ScheduledNotificationReceiver
        - ScheduledNotificationBootReceiver

- Injeção/dependências
    - lib/main.dart
        - main() abre o banco e cria os repositories, o NotificationService e o TaskStore
        - MultiProvider (pacote provider) disponibiliza o TaskStore e o NotificationService para as telas

---

## 2. Arquitetura e Estado

A arquitetura é uma estrutura em camadas simples:

screens → TaskStore → repositories → SQLite

O BUILD_LOG descreve a estrutura como "small layered structure, no Clean-Architecture ceremony". As telas falam com o TaskStore, que fala direto com os repositories concretos.

O gerenciamento de estado usa um único TaskStore, que estende ChangeNotifier e é disponibilizado pelo pacote provider. As telas usam context.watch<TaskStore>() e são reconstruídas sempre que o store chama notifyListeners(). Riverpod e Bloc foram considerados e descartados por serem mais complexos do que o necessário.

A estratégia não é reativa a partir do banco: o sqflite não avisa a interface quando os dados mudam. Por isso, toda alteração segue o mesmo fluxo explícito:

escrever no SQLite → sincronizar o lembrete → recarregar as listas do SQLite → notifyListeners()


- Criar uma tarefa

O TaskStore.saveTask() recebe uma tarefa sem ID e chama TaskRepository.insert(), que devolve a tarefa com o ID gerado pelo SQLite. Em seguida, o NotificationService.sync() agenda o lembrete (se necessário), o store chama load() para recarregar tarefas e categorias e a tela é notificada.

- Editar uma tarefa

O mesmo método saveTask() é usado; como a tarefa já tem ID, é chamado TaskRepository.update(). Depois vêm o sync() do lembrete, o load() e o notifyListeners().

- Concluir uma tarefa

O checkbox da lista chama TaskStore.setCompleted(), que faz task.copyWith(completed: true) e reutiliza saveTask(). Como o sync() sempre cancela o lembrete antes de decidir se agenda outro, uma tarefa concluída fica sem notificação.

---

## 3. Persistência com SQLite

O aplicativo usa o pacote sqflite com SQL direto, sem ORM nem geração de código. O BUILD_LOG justifica que drift/floor seriam exagero para duas tabelas e que o SQL escrito à mão deixa o esquema visível.

A camada de dados fica em:

lib/data/

O banco é um único arquivo, todo.db, com esquema versão 1, criado em AppDatabase._onCreate(). As datas são guardadas como INTEGER (milissegundos desde epoch).

### Tarefas

O modelo é Task (lib/models/task.dart), gravado na tabela tasks

com os campos:

id
title
description
completed (INTEGER 0/1)
dueDateTime (coluna due_date_time, opcional)
createdAt (coluna created_at)
categoryId (coluna category_id, opcional)

O título é validado no formulário e também no banco, com CHECK (length(trim(title)) > 0).

### Categorias

O modelo é Category (lib/models/category.dart), gravado na tabela categories

com os campos:

id
name (UNIQUE COLLATE NOCASE, impede nomes repetidos ignorando maiúsculas/minúsculas)
colorValue (coluna color) ( decisão adicional do agente para permitir a representação visual das categorias.)

Na criação do banco são inseridas quatro categorias padrão: Pessoal, Trabalho, Estudos e Compras.

### CRUD

O acesso aos dados é feito pelos repositories, que executam as queries do sqflite:

TaskRepository → tabela tasks
CategoryRepository → tabela categories

Os dois ficam no mesmo arquivo, lib/data/task_repository.dart.

O banco é aberto por:

AppDatabase.open()

em lib/main.dart, e o objeto Database é passado aos repositories pelo construtor.

A exclusão de categorias usa uma decisão interessante: category_id possui uma foreign key com ON DELETE SET NULL. Portanto, se uma categoria for excluída, as tarefas que a utilizavam não são excluídas; elas ficam sem categoria. Como o SQLite vem com foreign keys desativadas, foi necessário executar PRAGMA foreign_keys = ON no onConfigure. Antes de excluir, a CategoryScreen conta quantas tarefas usam a categoria (CategoryRepository.countTasks()) e mostra esse número no diálogo de confirmação. Se a categoria excluída era o filtro ativo da lista, o filtro volta para "todas".

---

## 4. Acompanhamento de uma Operação

Ponto de partida: o usuário tocou em "Nova tarefa" (FAB da TaskListScreen), que abriu TaskEditorScreen() sem taskId. Os valores do formulário ficam no próprio State da tela: controllers de título e descrição, _date, _time, _categoryId e _completed.

1. **Salvar** — o botão "Salvar" da AppBar chama _TaskEditorScreenState._save() (lib/screens/task_editor_screen.dart).
    - Se já estiver salvando (_saving), a chamada é ignorada; em seguida roda _formKey.currentState!.validate(), que exige um título.
    - _saving = true desabilita Salvar/Excluir, evitando salvar duas vezes.
    - Monta o objeto: Task(title: '', createdAt: DateTime.now()).copyWith(...) com os valores do formulário. O getter _due junta data e hora; se só houver data, a hora padrão é 09:00.
    - O ScaffoldMessenger é guardado antes do await (para mostrar o snackbar depois de fechar a tela) e a tela chama context.read<TaskStore>().saveTask(task).

2. **Gravação no SQLite** — TaskStore.saveTask() (lib/state/task_store.dart):
    - Como task.id == null, chama TaskRepository.insert() (lib/data/task_repository.dart), que faz _db.insert('tasks', task.toMap()..remove('id')). O SQLite gera o id (AUTOINCREMENT) e o método devolve task.copyWith(id: id).
    - Se o banco rejeitar a tarefa (por exemplo, pelo CHECK do título), a exceção sobe até o _save(), que mostra errorMessage(e) num snackbar e reativa o botão.

3. **Agendamento do lembrete** — o store chama NotificationService.sync(saved) com a tarefa **já com o id** (sem id, o sync() retornaria none, porque o id da tarefa é o id da notificação):
    - cancel(id), por segurança;
    - shouldHaveReminder() (lib/state/task_logic.dart): pendente e com data futura? Se não, retorna ReminderOutcome.none;
    - se sim, zonedSchedule(id: id, payload: '$id', scheduledDate: TZDateTime.from(dueDateTime, tz.local)), em modo exato ou inexato conforme canScheduleExact();
    - devolve um ReminderOutcome (scheduled, scheduledInexact, notificationsDisabled ou failed).

4. **Atualização da lista** — o store chama load(): TaskRepository.getAll() lê de novo com ORDER BY completed, due_date_time, created_at; em seguida lê as categorias e chama notifyListeners().
    - A TaskListScreen, que usa context.watch<TaskStore>(), é reconstruída; o getter visibleTasks aplica filterTasks() com os filtros ativos, e a nova tarefa aparece em um _TaskTile.
    - Se um filtro ativo excluir a tarefa (ex.: "Concluídas"), ela está no banco mas não aparece na lista.

5. **Retorno** — de volta ao _save(): Navigator.pop() fecha o editor e o snackbar mostra reminderMessage(outcome) (lib/widgets/feedback.dart). Se não houver mensagem de lembrete, mostra "Tarefa criada.".

Resumo: TaskEditorScreen._save → TaskStore.saveTask → TaskRepository.insert → NotificationService.sync → TaskStore.load → notifyListeners → TaskListScreen rebuild → pop + SnackBar.

---

## 5. Navegação

A navegação usa o Navigator imperativo do Flutter (Navigator.push com MaterialPageRoute), sem pacote de rotas. Não existe um arquivo central de rotas: cada tela abre a próxima diretamente.

Existem três áreas principais:

Task List
    |
Task Editor
    |
Category Management

A lista abre o editor (nova tarefa pelo botão "+", ou tarefa existente pelo toque no item) e, pelo ícone no topo, a tela de categorias.

Para editar uma tarefa existente, o aplicativo não passa o objeto inteiro da tarefa. Ele passa somente o ID (int) no construtor: TaskEditorScreen(taskId: id).

A TaskEditorScreen usa esse ID para buscar a tarefa novamente no SQLite (TaskStore.getTask()). Com isso, o formulário sempre mostra os valores gravados, e o editor consegue tratar o caso de a tarefa não existir mais (por exemplo, ao tocar numa notificação antiga): mostra uma mensagem e volta para a lista.

A navigatorKey definida em lib/main.dart permite que o toque na notificação abra diretamente o editor daquela tarefa, mesmo fora de uma tela.

---

## 6. Notificações

As notificações são locais, sem servidor externo.

A implementação utiliza:

flutter_local_notifications (zonedSchedule)
    |
ScheduledNotificationReceiver (receiver do plugin)
    |
notificação exibida pelo Android

O NotificationService funciona como uma abstração sobre o plugin. Os pacotes timezone e flutter_timezone são usados para criar o TZDateTime exigido pelo zonedSchedule; se não for possível descobrir o fuso do aparelho, é usado UTC.

A associação entre notificação e tarefa é o próprio ID da tarefa usado como ID da notificação. O ID também vai no payload, para que o toque abra a tarefa certa. Portanto, não foi necessário adicionar uma coluna específica para armazenar o ID da notificação.

O ponto central é um único método, NotificationService.sync(task), chamado depois de criar, editar, concluir e reabrir. Ele sempre cancela o lembrete antigo e só agenda outro se shouldHaveReminder() for verdadeiro (tarefa pendente e com data futura).

### Com data futura

Se a tarefa:
- não estiver concluída;
- tiver uma data futura;

o sync() agenda o lembrete para o horário de vencimento, com o título "Lembrete de tarefa" e o título da tarefa no corpo.

### Data alterada

O lembrete anterior é cancelado e uma nova notificação é agendada para a nova data.

### Data removida

A notificação existente é cancelada.

### Tarefa concluída

A notificação é cancelada.

### Tarefa reaberta

Se a tarefa voltar a ficar pendente e sua data ainda estiver no futuro, o lembrete é agendado novamente.

### Tarefa excluída

A notificação é cancelada com NotificationService.cancel().

### Permissões

- POST_NOTIFICATIONS é pedida ao abrir o app (Android 13+). Se o usuário negar, as tarefas continuam sendo salvas, e o editor avisa que o lembrete não aparecerá.
- Para alarmes exatos foi usada SCHEDULE_EXACT_ALARM (e não USE_EXACT_ALARM, reservada pela política da Play Store para apps de alarme/calendário). Sem essa permissão, o lembrete é agendado como inexato e pode atrasar alguns minutos; o editor oferece o botão "Permitir alarmes exatos".
- Depois de reiniciar o celular, o ScheduledNotificationBootReceiver do plugin reagenda os lembretes. Além disso, ao abrir o app, resyncReminders() passa todas as tarefas pelo sync() novamente.
- Toda chamada ao plugin fica dentro de try/catch e devolve um ReminderOutcome (none, scheduled, scheduledInexact, notificationsDisabled, failed), para que uma falha no lembrete nunca derrube o app.

---

## 7. Decisões do Agente

#### Escolha do sqflite com SQL direto

A especificação permitia várias abordagens: SQLite direto, DAO, ORM, repository etc.

O agente escolheu:

sqflite + SQL direto + Repository

A justificativa registrada foi que, para duas tabelas, um ORM seria exagero, e o SQL direto deixa o esquema visível. A consequência é que o banco não avisa a interface sobre mudanças, e por isso o TaskStore recarrega os dados depois de cada operação.

#### Filtragem em memória

O agente decidiu carregar todas as tarefas e filtrar em memória com a função pura filterTasks() (em lib/state/task_logic.dart, coberta por testes unitários). A ordenação (pendentes primeiro, depois pela data de vencimento) continua sendo feita no SQL. A justificativa foi o volume pequeno de dados e a troca de filtro instantânea, sem nova consulta ao banco. O filtro "Sem categoria" usa o ID 0, que nunca coincide com uma categoria real porque o AUTOINCREMENT começa em 1.

---

## 8. Análise do BUILD_LOG

### Ambiente sem Flutter

O primeiro problema registrado não foi de código: o Flutter SDK não estava instalado na máquina (flutter e dart não estavam no PATH). Com a autorização do usuário, o agente clonou o canal stable (Flutter 3.47.5 / Dart 3.13.4) em C:\Users\Talita\flutter, sem alterar o PATH do sistema; o SDK passou a ser chamado pelo caminho completo.

O flutter doctor apontou cmdline-tools ausente e licenças com status desconhecido. O agente verificou que o arquivo de licença do Android SDK já existia na máquina e seguiu em frente, e o build de fato não foi bloqueado.

### Conflito de nomes com Category 

- **Problema:** na primeira análise estática (flutter analyze, Entry 3) apareceram 9 erros de ambiguous_import. O package:flutter/foundation.dart também exporta uma classe chamada Category (uma anotação), que entrava em conflito com o modelo Category do app dentro de lib/state/task_store.dart.
- **Tentativa de solução:** importar o foundation escondendo esse nome:

  import 'package:flutter/foundation.dart' hide Category;

  Esse import continua no código final, com o comentário "foundation.dart also exports an unrelated `Category` annotation." (task_store.dart:1-2).
- **A primeira solução funcionou?** Sim. O log marca como "fixed" e não registra uma segunda tentativa.
- **Resultado final:** flutter analyze sem problemas e 8/8 testes passando (test/widget_test.dart: 4 de shouldHaveReminder, 3 de filterTasks e 1 de Task.copyWith).

Na mesma análise também apareceu um aviso use_build_context_synchronously no editor (context.read depois de um await). A correção foi ler o TaskStore do context antes do primeiro await em _load(), e também funcionou na primeira tentativa. É por isso que _load() começa com `final store = context.read<TaskStore>();` antes de qualquer await.

Observação: nenhum problema do BUILD_LOG exigiu uma segunda tentativa. O log só registra correções que funcionaram de primeira, ou problemas que ficaram pendentes (o teste no aparelho).
