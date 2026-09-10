import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:waflo_app/agents/agent_event.dart';
import 'package:waflo_app/agents/agent_executor.dart';
import 'package:waflo_app/agents/agent_type.dart';
import 'package:waflo_app/agents/virtual_workspace.dart';

/// Lives for the duration of one workspace screen. Owns the agent executor for
/// the selected agent and exposes the state the UI renders reactively:
///   - event history (the live execution timeline)
///   - overall status + current task
///   - retry / cancel / confirm actions
class AgentController extends ChangeNotifier {
  final AgentType type;
  final VirtualWorkspace workspace;
  AgentExecutor? _executor;
  StreamSubscription<AgentEvent>? _sub;

  final List<AgentEvent> _events = [];
  AgentStatus _status = AgentStatus.idle;
  String? _activeTask;
  String? _error;
  int _pulseTick = 0;

  AgentController({required this.type})
      : workspace = VirtualWorkspace();

  AgentStatus get status => _status;
  String? get activeTask => _activeTask;
  String? get error => _error;
  List<AgentEvent> get events => List.unmodifiable(_events);
  bool get running => _status == AgentStatus.running;
  bool get awaitingConfirmation => _executor?.awaitingConfirmation ?? false;
  /// Incremented to retrigger the character's tap/pulse animation.
  int get pulseTick => _pulseTick;

  AgentExecutor _buildExecutor() {
    switch (type) {
      case AgentType.researcher:
        return BrowserExecutor(workspace);
      case AgentType.fileEditing:
        return CodingExecutor(workspace, name: 'Bubbles');
      case AgentType.coding:
        return CodingExecutor(workspace, name: 'Nixa');
      case AgentType.research:
        return ResearchExecutor(workspace);
      case AgentType.writing:
        return WritingExecutor(workspace);
    }
  }

  void _attach(AgentExecutor executor) {
    _sub?.cancel();
    _sub = executor.events.listen(_onEvent);
  }

  void _onEvent(AgentEvent event) {
    _events.add(event);
    switch (event.kind) {
      case AgentEventKind.taskCompleted:
        _status = AgentStatus.completed;
        break;
      case AgentEventKind.taskFailed:
        _status = AgentStatus.failed;
        _error = event.message;
        break;
      case AgentEventKind.taskCancelled:
        _status = AgentStatus.cancelled;
        break;
      case AgentEventKind.taskStarted:
        _status = AgentStatus.running;
        _error = null;
        break;
      default:
        if (_status == AgentStatus.idle) _status = AgentStatus.running;
    }
    notifyListeners();
  }

  Future<void> run(String task) async {
    final trimmed = task.trim();
    if (trimmed.isEmpty || running) return;
    _executor?.cancel();
    _activeTask = trimmed;
    _error = null;
    _events.clear();
    _status = AgentStatus.running;
    _executor = _buildExecutor();
    _attach(_executor!);
    notifyListeners();
    await _executor!.run(trimmed);
    notifyListeners();
  }

  Future<void> retry() async {
    final task = _activeTask;
    if (task == null) return;
    _error = null;
    _executor?.cancel();
    _executor = _buildExecutor();
    _attach(_executor!);
    _events.clear();
    _status = AgentStatus.running;
    notifyListeners();
    await _executor!.run(task);
    notifyListeners();
  }

  Future<void> cancel() async {
    if (!running && !awaitingConfirmation) return;
    _error = null;
    await _executor?.cancel();
    notifyListeners();
  }

  Future<void> confirmAction(bool accept) async {
    _executor?.confirm(accept);
    notifyListeners();
  }

  void pulse() {
    _pulseTick++;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _executor?.cancel();
    super.dispose();
  }
}