import 'package:flutter/material.dart';

/// The kind of activity an agent is performing. Mapped 1:1 to the timeline
/// UI by [iconFor] / [colorFor].
enum AgentEventKind {
  taskStarted,
  planning,
  thinking,
  searching,
  openingBrowser,
  readingPage,
  clicking,
  extracting,
  comparing,
  toolCall,
  toolResult,
  fileRead,
  fileWrite,
  fileDelete,
  commandExecution,
  progressUpdate,
  awaitingUser,
  taskCompleted,
  taskFailed,
  taskCancelled,
}

/// Overall agent lifecycle status.
enum AgentStatus { idle, running, completed, failed, cancelled }

class AgentEvent {
  final AgentEventKind kind;
  final String message;
  final String? detail;
  final DateTime at;

  AgentEvent({
    required this.kind,
    required this.message,
    this.detail,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  bool get isError =>
      kind == AgentEventKind.taskFailed;
  bool get isTerminal =>
      kind == AgentEventKind.taskCompleted ||
      kind == AgentEventKind.taskFailed ||
      kind == AgentEventKind.taskCancelled;
  bool get isRunning =>
      kind == AgentEventKind.thinking ||
      kind == AgentEventKind.planning ||
      kind == AgentEventKind.searching ||
      kind == AgentEventKind.openingBrowser ||
      kind == AgentEventKind.readingPage ||
      kind == AgentEventKind.clicking ||
      kind == AgentEventKind.extracting ||
      kind == AgentEventKind.comparing ||
      kind == AgentEventKind.toolCall ||
      kind == AgentEventKind.fileRead ||
      kind == AgentEventKind.fileWrite ||
      kind == AgentEventKind.commandExecution ||
      kind == AgentEventKind.progressUpdate;
}

IconData iconFor(AgentEventKind kind) {
  switch (kind) {
    case AgentEventKind.taskStarted:
      return Icons.play_circle_outline;
    case AgentEventKind.planning:
      return Icons.event_note;
    case AgentEventKind.thinking:
      return Icons.psychology;
    case AgentEventKind.searching:
      return Icons.search;
    case AgentEventKind.openingBrowser:
    case AgentEventKind.clicking:
      return Icons.open_in_new;
    case AgentEventKind.readingPage:
      return Icons.web;
    case AgentEventKind.extracting:
      return Icons.content_copy;
    case AgentEventKind.comparing:
      return Icons.compare;
    case AgentEventKind.toolCall:
      return Icons.widgets_outlined;
    case AgentEventKind.toolResult:
      return Icons.output;
    case AgentEventKind.fileRead:
      return Icons.description_outlined;
    case AgentEventKind.fileWrite:
      return Icons.edit_document;
    case AgentEventKind.fileDelete:
      return Icons.delete_outline;
    case AgentEventKind.commandExecution:
      return Icons.terminal;
    case AgentEventKind.progressUpdate:
      return Icons.sync;
    case AgentEventKind.awaitingUser:
      return Icons.person_outline;
    case AgentEventKind.taskCompleted:
      return Icons.check_circle;
    case AgentEventKind.taskFailed:
      return Icons.error;
    case AgentEventKind.taskCancelled:
      return Icons.cancel;
  }
}

Color colorFor(AgentEventKind kind, {Color accent = const Color(0xFF1BB9CE)}) {
  switch (kind) {
    case AgentEventKind.taskCompleted:
      return const Color(0xFF34C77B);
    case AgentEventKind.taskFailed:
      return const Color(0xFFE5484D);
    case AgentEventKind.taskCancelled:
      return const Color(0xFF909090);
    case AgentEventKind.taskStarted:
    case AgentEventKind.planning:
    case AgentEventKind.thinking:
      return accent;
    case AgentEventKind.searching:
    case AgentEventKind.openingBrowser:
    case AgentEventKind.readingPage:
    case AgentEventKind.clicking:
    case AgentEventKind.extracting:
      return const Color(0xFF4E9BFF);
    case AgentEventKind.comparing:
      return const Color(0xFF9D6CFF);
    case AgentEventKind.toolCall:
      return const Color(0xFF00B3A6);
    case AgentEventKind.toolResult:
      return const Color(0xFF00B3A6);
    case AgentEventKind.fileRead:
      return const Color(0xFF6BB8E8);
    case AgentEventKind.fileWrite:
      return const Color(0xFFF5A623);
    case AgentEventKind.fileDelete:
      return const Color(0xFFE5484D);
    case AgentEventKind.commandExecution:
      return const Color(0xFF5AC8FA);
    case AgentEventKind.progressUpdate:
      return const Color(0xFF909090);
    case AgentEventKind.awaitingUser:
      return const Color(0xFFF5A623);
  }
}

String statusLabel(AgentStatus status) {
  switch (status) {
    case AgentStatus.idle:
      return 'Idle';
    case AgentStatus.running:
      return 'Working';
    case AgentStatus.completed:
      return 'Completed';
    case AgentStatus.failed:
      return 'Failed';
    case AgentStatus.cancelled:
      return 'Cancelled';
  }
}