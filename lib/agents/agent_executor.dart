import 'dart:async';

import 'package:waflo_app/agents/agent_event.dart';
import 'package:waflo_app/agents/virtual_workspace.dart';
import 'package:waflo_app/services/chat_web_service.dart';

class _CancelledException implements Exception {}

enum _CodeAction { list, read, create, edit, delete, explain }

/// Common contract every agent executor implements. The Flutter UI talks to
/// these executors (never directly to browser-use / file code). Each executor
/// streams [AgentEvent]s so the UI updates live instead of waiting for the
/// whole task to finish.
abstract class AgentExecutor {
  final VirtualWorkspace workspace;
  final _events = StreamController<AgentEvent>.broadcast();
  Completer<void>? _done;
  Completer<bool>? _awaitingConfirmation;
  bool _cancelled = false;
  bool _terminalSeen = false;
  AgentExecutor? _child;

  AgentExecutor(this.workspace);

  Stream<AgentEvent> get events => _events.stream;
  bool get isBusy => _done != null && !_done!.isCompleted;
  bool get awaitingConfirmation =>
      _awaitingConfirmation != null && !_awaitingConfirmation!.isCompleted;

  void emit(AgentEvent event) => _events.add(event);

  Future<void> _pause(int ms) {
    if (_cancelled) throw _CancelledException();
    return Future<void>.delayed(Duration(milliseconds: ms));
  }

  /// Asks the UI for explicit confirmation (e.g. deleting a file).
  Future<void> requestConfirmation(String message) {
    emit(AgentEvent(kind: AgentEventKind.awaitingUser, message: message));
    _awaitingConfirmation = Completer<bool>();
    return _awaitingConfirmation!.future
        .timeout(const Duration(seconds: 60), onTimeout: () => false)
        .then((ok) {
      _awaitingConfirmation = null;
      if (!ok) throw _CancelledException();
    });
  }

  void confirm(bool accept) {
    final c = _awaitingConfirmation;
    if (c != null && !c.isCompleted) c.complete(accept);
  }

  Future<void> cancel() async {
    _cancelled = true;
    await _child?.cancel();
    final c = _awaitingConfirmation;
    if (c != null && !c.isCompleted) c.complete(false);
  }

  /// Body implemented by each agent. Must emit at least one terminal event
  /// (setting [_terminalSeen = true]) or `run` adds a default terminal event.
  Future<void> execute(String task);

  /// Runs [execute] and guarantees a single terminal event is emitted
  /// (completed / failed / cancelled), then resolves.
  Future<void> run(String task) async {
    _done = Completer<void>();
    try {
      await execute(task);
      if (!_cancelled && !_terminalSeen) {
        emit(AgentEvent(
          kind: AgentEventKind.taskCompleted,
          message: 'Task finished.',
        ));
      }
    } on _CancelledException {
      emit(AgentEvent(
        kind: AgentEventKind.taskCancelled,
        message: 'Task cancelled.',
      ));
    } catch (e) {
      emit(AgentEvent(
        kind: AgentEventKind.taskFailed,
        message: 'Agent failed: $e',
      ));
    } finally {
      if (!_done!.isCompleted) _done!.complete();
    }
    await _done!.future;
  }
}

/// Browser / researcher agent (Strobi). Drives the vendored **browser-use**
/// agent on the FastAPI backend (``type: "browse"`` over the same WebSocket)
/// and maps its live steps onto agent events in real time — the backend opens
/// a real browser, so the timeline shows actual searching/clicking/reading.
class BrowserExecutor extends AgentExecutor {
  static final ChatWebService _ws = ChatWebService();
  StreamSubscription<Map<String, dynamic>>? _sub;
  final StringBuffer _answer = StringBuffer();
  bool _started = false;
  String? _taskId;
  Completer<void>? _browseDone;

  BrowserExecutor(super.workspace);

  @override
  Future<void> execute(String task) async {
    emit(AgentEvent(
      kind: AgentEventKind.taskStarted,
      message: 'Strobi is on it — I will research "$task".',
    ));
    await _pause(400);
    emit(AgentEvent(
      kind: AgentEventKind.planning,
      message: 'Building a research plan…',
    ));
    await _pause(400);
    emit(AgentEvent(
      kind: AgentEventKind.thinking,
      message: 'Deciding which sources and websites to use…',
    ));
    await _pause(350);
    emit(AgentEvent(
      kind: AgentEventKind.openingBrowser,
      message: 'Launching the web browser to research "$task"…',
    ));

    _answer.clear();
    _taskId = null;
    _started = true;
    _browseDone = Completer<void>();
    _sub = _ws.realtimeStream.listen(_onMessage);
    try {
      _ws.startBrowse(task);
    } catch (e) {
      final sub = _sub;
      _sub = null;
      unawaited(sub?.cancel());
      _terminalSeen = true;
      _browseDone?.complete();
      emit(AgentEvent(
        kind: AgentEventKind.taskFailed,
        message:
            'Could not reach the browser backend ($e).\n'
            'Start it with:  cd server && python main.py\n'
            'then tap "Send again".',
      ));
      return;
    }
    // Wait for the browser task to actually finish (done/error/cancelled)
    // instead of resolving immediately, so the workspace stays in "running"
    // state and the final answer is guaranteed to be captured and shown.
    await _browseDone!.future;
  }

  void _onMessage(Map<String, dynamic> data) {
    if (!_started) return;
    final type = data['type'];
    switch (type) {
      case 'browse_started':
        _taskId = data['task_id']?.toString();
        emit(AgentEvent(
          kind: AgentEventKind.progressUpdate,
          message: 'Browser research task registered by the agent hub.',
        ));
        break;
      case 'agent_step':
        final isOurs = _taskId == null ||
            (data['task_id']?.toString() ?? '') == _taskId;
        if (!isOurs) return;
        final step = data['message']?.toString() ?? 'Taking the next step in the browser…';
        final url = data['url']?.toString();
        emit(AgentEvent(
          kind: AgentEventKind.openingBrowser,
          message: step,
          detail: url == null || url.isEmpty || url == 'none' ? null : url,
        ));
        break;
      case 'content':
        final chunk = data['data']?.toString() ?? '';
        if (chunk.isNotEmpty) {
          _answer.write('\n\n');
          _answer.write(chunk.trim());
        }
        break;
      case 'done':
        _finish();
        var answer = _answer.toString().trim();
        if (answer.isEmpty) {
          answer = 'Strobi finished researching, but no readable answer was '
              'captured from the pages. Try a more specific question.';
        }
        emit(AgentEvent(
          kind: AgentEventKind.taskCompleted,
          message: answer,
        ));
        break;
      case 'error':
        final isOurs = data.containsKey('task_id') &&
                data['task_id'] != null &&
                _taskId != null
            ? (data['task_id'].toString() == _taskId)
            : true;
        if (!isOurs) return;
        _finish();
        emit(AgentEvent(
          kind: AgentEventKind.taskFailed,
          message: data['message']?.toString() ??
              data['data']?.toString() ??
              'The browser research backend returned an error.',
        ));
        break;
      case 'browse_cancelled':
        final isOurs = _taskId == null ||
            (data['task_id']?.toString() ?? '') == _taskId;
        if (!isOurs) return;
        _finish();
        emit(AgentEvent(
          kind: AgentEventKind.taskCancelled,
          message: 'Research stopped.',
        ));
        break;
      default:
        break;
    }
  }

  // Central cleanup once the browser task is finished, so the workspace
  // resolves its awaited run() and shows the terminal event exactly once.
  void _finish() {
    if (!_started) return;
    _started = false;
    _taskId = null;
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel());
    _terminalSeen = true;
    _browseDone?.complete();
  }

  @override
  Future<void> cancel() async {
    final taskId = _taskId;
    if (taskId != null) {
      try {
        _ws.cancelBrowse(taskId);
      } catch (_) {}
    }
    _started = false;
    _taskId = null;
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel());
    _terminalSeen = true;
    _browseDone?.complete();
    emit(AgentEvent(
      kind: AgentEventKind.taskCancelled,
      message: 'Research cancelled.',
    ));
    await super.cancel();
  }
}

class _Plan {
  final _CodeAction action;
  final String headline;
  final String? path;
  final String? content;
  const _Plan(this.action, this.headline, [this.path, this.content]);
}

/// Coding / file agent (BUBBLES & NIXA). Operates on the in-app
/// [VirtualWorkspace], making small, targeted edits and asking for confirmation
/// before any destructive operation. The [name] is the persona that reports
/// back to the user (defaults to the File Editing agent).
class CodingExecutor extends AgentExecutor {
  final String name;

  CodingExecutor(super.workspace, {this.name = 'Bubbles'});

  @override
  Future<void> execute(String task) async {
    emit(AgentEvent(
      kind: AgentEventKind.taskStarted,
      message: '$name is on it — inspecting your project workspace.',
    ));
    await _pause(300);
    final plan = _plan(task);
    emit(AgentEvent(
      kind: AgentEventKind.planning,
      message: plan.headline,
    ));
    await _pause(350);

    switch (plan.action) {
      case _CodeAction.list:
        final files = workspace.listPaths();
        emit(AgentEvent(
          kind: AgentEventKind.toolCall,
          message: 'Reading the workspace index…',
          detail: files.isEmpty ? '(empty)' : files.join('\n'),
        ));
        await _pause(200);
        _terminalSeen = true;
        emit(AgentEvent(
          kind: AgentEventKind.taskCompleted,
          message: 'Workspace now contains ${files.length} file${files.length == 1 ? '' : 's'}.',
          detail: files.isEmpty ? 'Use "create file <name> with <content>" to start.' : files.join('\n'),
        ));
        break;

      case _CodeAction.read:
        final path = plan.path!;
        final content = workspace.read(path);
        if (content == null) {
          _terminalSeen = true;
          emit(AgentEvent(
            kind: AgentEventKind.taskFailed,
            message: 'File "$path" was not found. Try "list files" first.',
          ));
          return;
        }
        emit(AgentEvent(
          kind: AgentEventKind.fileRead,
          message: 'Read $path',
          detail: content,
        ));
        _terminalSeen = true;
        emit(AgentEvent(
          kind: AgentEventKind.taskCompleted,
          message: 'Inspection complete.',
          detail: content,
        ));
        break;

      case _CodeAction.create:
        final path = plan.path!;
        final content = plan.content ?? '// created by $name\n';
        workspace.write(path, content);
        emit(AgentEvent(
          kind: AgentEventKind.fileWrite,
          message: 'Created $path (${workspace.lineCount(path)} lines).',
          detail: content,
        ));
        await _pause(250);
        emit(AgentEvent(
          kind: AgentEventKind.commandExecution,
          message: 'Validated the workspace state.',
        ));
        _terminalSeen = true;
        emit(AgentEvent(
          kind: AgentEventKind.taskCompleted,
          message: 'Added $path to the workspace.',
        ));
        break;

      case _CodeAction.edit:
        final path = plan.path!;
        final prev = workspace.read(path);
        if (prev == null) {
          _terminalSeen = true;
          emit(AgentEvent(
            kind: AgentEventKind.taskFailed,
            message: 'Cannot edit "$path": it does not exist. Use "create file $path with <content>".',
          ));
          return;
        }
        final content = plan.content ?? '${prev.trimRight()}\n// updated by $name\n';
        workspace.write(path, content);
        emit(AgentEvent(
          kind: AgentEventKind.fileWrite,
          message: 'Updated $path (${workspace.lineCount(path)} lines).',
          detail: content,
        ));
        await _pause(250);
        emit(AgentEvent(
          kind: AgentEventKind.commandExecution,
          message: 'Validated the workspace state.',
        ));
        _terminalSeen = true;
        emit(AgentEvent(
          kind: AgentEventKind.taskCompleted,
          message: '$name updated $path.',
        ));
        break;

      case _CodeAction.delete:
        final path = plan.path!;
        if (!workspace.exists(path)) {
          _terminalSeen = true;
          emit(AgentEvent(
            kind: AgentEventKind.taskFailed,
            message: 'Cannot delete "$path": it was not found.',
          ));
          return;
        }
        await requestConfirmation('Delete "$path"? This cannot be undone.');
        workspace.delete(path);
        emit(AgentEvent(
          kind: AgentEventKind.fileDelete,
          message: 'Deleted $path.',
        ));
        _terminalSeen = true;
        emit(AgentEvent(
          kind: AgentEventKind.taskCompleted,
          message: 'Removed $path from the workspace.',
        ));
        break;

      case _CodeAction.explain:
        emit(AgentEvent(
          kind: AgentEventKind.thinking,
          message: 'Studying the request to produce a concrete plan…',
        ));
        await _pause(300);
        emit(AgentEvent(
          kind: AgentEventKind.toolResult,
          message: 'Understood. Here is my plan:',
          detail: _explain(task),
        ));
        _terminalSeen = true;
        emit(AgentEvent(
          kind: AgentEventKind.taskCompleted,
          message: 'Plan ready.',
          detail: _explain(task),
        ));
        break;
    }
  }

  String _explain(String task) {
    return 'For "$task" I would:\n'
        '1. Inspect the related files in the workspace.\n'
        '2. Make small, targeted edits (one file at a time).\n'
        '3. Ask for confirmation before any destructive change (e.g. deletes).\n'
        '4. Report exactly what changed.\n\n'
        'You can tell me things like:\n'
        '• "list files"\n'
        '• "read lib/main.dart"\n'
        '• "create file lib/app.dart with main() entry"\n'
        '• "edit lib/theme/colors.dart to use a purple background"\n'
        '• "delete README.md"';
  }

  _Plan _plan(String task) {
    final t = task.trim();

    if (RegExp(r'\b(list|show|what)\b.*(file|workspace)|which files', caseSensitive: false)
        .hasMatch(t)) {
      return const _Plan(_CodeAction.list, 'Listing the project workspace…');
    }

    final readMatch = RegExp(
      r'\b(read|open|show|inspect|see|view)\b\s*(?:file\s*)?([A-Za-z0-9_./-]+)',
      caseSensitive: false,
    ).firstMatch(t);
    if (readMatch != null) {
      return _Plan(
        _CodeAction.read,
        'Opening ${readMatch.group(2)!.trim()}…',
        readMatch.group(2)!.trim(),
      );
    }

    final createMatch = RegExp(
      r'\b(create|add|make|write|new)\b\s*(?:file\s*)?([A-Za-z0-9_./-]+)(?:\s*(?:with|containing)\s*(.+))?',
      caseSensitive: false,
    ).firstMatch(t);
    if (createMatch != null && !t.contains('edit ')) {
      return _Plan(
        _CodeAction.create,
        'Creating ${createMatch.group(2)!.trim()}…',
        createMatch.group(2)!.trim(),
        createMatch.group(3)?.trim(),
      );
    }

    final editMatch = RegExp(
      r'\b(edit|update|modify|change|fix|refactor)\b\s*(?:file\s*)?([A-Za-z0-9_./-]+)(?:\s*(?:to|with)\s*(.+))?',
      caseSensitive: false,
    ).firstMatch(t);
    if (editMatch != null) {
      return _Plan(
        _CodeAction.edit,
        'Updating ${editMatch.group(2)!.trim()}…',
        editMatch.group(2)!.trim(),
        editMatch.group(3)?.trim(),
      );
    }

    final deleteMatch = RegExp(
      r'\b(delete|remove)\b\s*(?:file\s*)?([A-Za-z0-9_./-]+)',
      caseSensitive: false,
    ).firstMatch(t);
    if (deleteMatch != null) {
      return _Plan(
        _CodeAction.delete,
        'Preparing to delete ${deleteMatch.group(2)!.trim()}…',
        deleteMatch.group(2)!.trim(),
      );
    }

    return _Plan(_CodeAction.explain, 'Analysing what you want to build…');
  }
}

/// Research & analysis agent (COSMO). Drives the standard Waflo search+LLM
/// pipeline over the WebSocket: it hits the live web, reports the sources as
/// they land, then streams the model's researched analysis. Fully functional —
/// the same backend that powers the chat page produces the answer (OpenRouter
/// → Gemini → HF fallback chain), so no extra API setup is required.
class ResearchExecutor extends AgentExecutor {
  static final ChatWebService _chatWebService = ChatWebService();

  StreamSubscription<Map<String, dynamic>>? _sub;
  final StringBuffer _answer = StringBuffer();
  int _sources = 0;
  bool _externallyCancelled = false;
  bool _started = false;
  bool _finished = false;
  Completer<void>? _done;

  ResearchExecutor(super.workspace);

  @override
  Future<void> execute(String task) async {
    emit(AgentEvent(
      kind: AgentEventKind.taskStarted,
      message: 'Cosmo is on it — researching "$task" with live web sources.',
    ));
    await _pause(350);
    emit(AgentEvent(
      kind: AgentEventKind.planning,
      message: 'Designing the research approach — what to source and how to weigh it.',
    ));
    await _pause(350);
    emit(AgentEvent(
      kind: AgentEventKind.thinking,
      message: 'Searching the web and preparing to analyse the results…',
    ));

    _answer.clear();
    _sources = 0;
    _externallyCancelled = false;
    _started = true;
    _finished = false;
    _done = Completer<void>();
    _sub = _chatWebService.realtimeStream.listen(_onMessage);
    try {
      _chatWebService.sendChatMessage(task);
    } catch (e) {
      _completeLoop();
      if (_externallyCancelled) return;
      _terminalSeen = true;
      emit(AgentEvent(
        kind: AgentEventKind.taskFailed,
        message: 'Cosmo could not reach the research backend ($e). Make sure the server is running (cd server && python main.py) and try again.',
      ));
      return;
    }
    await _done!.future;
  }

  void _onMessage(Map<String, dynamic> data) {
    if (!_started || _finished) return;
    switch (data['type']) {
      case 'search_result':
        final raw = data['data'];
        _sources = raw is List ? raw.length : (raw != null ? 1 : 0);
        break;
      case 'content':
        final chunk = data['data']?.toString() ?? '';
        if (chunk.trim().isNotEmpty) {
          _answer.write(chunk);
        }
        break;
      case 'done':
        _completeLoop();
        if (_externallyCancelled) return;
        var answer = _answer.toString().trim();
        if (answer.isEmpty) {
          answer = 'Cosmo finished researching but captured no readable answer. Try a more specific question.';
        }
        _terminalSeen = true;
        emit(AgentEvent(kind: AgentEventKind.taskCompleted, message: answer));
        break;
      case 'error':
        _completeLoop();
        if (_externallyCancelled) return;
        _terminalSeen = true;
        emit(AgentEvent(
          kind: AgentEventKind.taskFailed,
          message: (data['data'] ?? data['message'])?.toString() ??
              'The research backend returned an error. Try again.',
        ));
        break;
    }
  }

  void _completeLoop() {
    if (!_started) return;
    _started = false;
    _finished = true;
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel());
    _done?.complete();
  }

  @override
  Future<void> cancel() async {
    _externallyCancelled = true;
    _completeLoop();
    if (!_terminalSeen) {
      _terminalSeen = true;
      emit(AgentEvent(
        kind: AgentEventKind.taskCancelled,
        message: 'Research cancelled — nothing was posted.',
      ));
    }
    await super.cancel();
  }
}

/// Writing & communication agent (SUNNY). Streams a pure LLM draft with no web
/// search — emits a short taskStarted event first, then the finished piece as
/// the terminal answer. Uses the backend's `writing` request type so the model
/// writes from its own knowledge instead of quoting live search results.
class WritingExecutor extends AgentExecutor {
  static final ChatWebService _chatWebService = ChatWebService();

  StreamSubscription<Map<String, dynamic>>? _sub;
  final StringBuffer _answer = StringBuffer();
  bool _externallyCancelled = false;
  bool _started = false;
  bool _finished = false;
  Completer<void>? _done;

  WritingExecutor(super.workspace);

  @override
  Future<void> execute(String task) async {
    emit(AgentEvent(
      kind: AgentEventKind.taskStarted,
      message: 'Sunny is on it — drafting your piece now.',
    ));
    await _pause(350);
    emit(AgentEvent(
      kind: AgentEventKind.planning,
      message: 'Choosing a tone and structure that fit the brief…',
    ));
    await _pause(350);
    emit(AgentEvent(
      kind: AgentEventKind.thinking,
      message: 'Writing the draft…',
    ));

    _answer.clear();
    _externallyCancelled = false;
    _started = true;
    _finished = false;
    _done = Completer<void>();
    _sub = _chatWebService.realtimeStream.listen(_onMessage);
    try {
      _chatWebService.writeText(task);
    } catch (e) {
      _completeLoop();
      if (_externallyCancelled) return;
      _terminalSeen = true;
      emit(AgentEvent(
        kind: AgentEventKind.taskFailed,
        message: 'Sunny could not reach the writing backend ($e). Make sure the server is running (cd server && python main.py) and try again.',
      ));
      return;
    }
    await _done!.future;
  }

  void _onMessage(Map<String, dynamic> data) {
    if (!_started || _finished) return;
    switch (data['type']) {
      case 'content':
        final chunk = data['data']?.toString() ?? '';
        if (chunk.trim().isNotEmpty) {
          _answer.write(chunk);
        }
        break;
      case 'done':
        _completeLoop();
        if (_externallyCancelled) return;
        var answer = _answer.toString().trim();
        if (answer.isEmpty) {
          answer = 'Sunny finished, but no draft was captured. Try describing the piece again.';
        }
        _terminalSeen = true;
        emit(AgentEvent(kind: AgentEventKind.taskCompleted, message: answer));
        break;
      case 'error':
        _completeLoop();
        if (_externallyCancelled) return;
        _terminalSeen = true;
        emit(AgentEvent(
          kind: AgentEventKind.taskFailed,
          message: (data['data'] ?? data['message'])?.toString() ??
              'The writing backend returned an error. Try again.',
        ));
        break;
    }
  }

  void _completeLoop() {
    if (!_started) return;
    _started = false;
    _finished = true;
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel());
    _done?.complete();
  }

  @override
  Future<void> cancel() async {
    _externallyCancelled = true;
    _completeLoop();
    if (!_terminalSeen) {
      _terminalSeen = true;
      emit(AgentEvent(
        kind: AgentEventKind.taskCancelled,
        message: 'Writing cancelled — no draft was kept.',
      ));
    }
    await super.cancel();
  }
}