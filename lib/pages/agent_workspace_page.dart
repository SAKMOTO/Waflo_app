import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:waflo_app/agents/agent_controller.dart';
import 'package:waflo_app/agents/agent_event.dart';
import 'package:waflo_app/agents/agent_type.dart';
import 'package:waflo_app/controllers/avatar_controller.dart';
import 'package:waflo_app/controllers/chat_history_controller.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/widgets/avatar_view.dart';
import 'package:waflo_app/widgets/strobi_assistant_message.dart';

/// Reusable workspace for any agent. One is opened per agent type; the agent
/// identity drives the character, accent colour and the executor under the hood.
///
/// The screen is dynamically bound to [AvatarController.instance] — the same
/// character the user selected on the Home Screen is the one whose animation,
/// name, role and accent colour are shown here while the agent runs. The
/// underlying executor stays bound to [AgentIdentity.type], so the task
/// execution / browser / streaming logic is untouched by the character choice.
class AgentWorkspacePage extends StatefulWidget {
  final AgentIdentity agent;

  /// If provided, the task is run automatically when the workspace opens —
  /// e.g. when the home-screen Browser Agent toggle is enabled.
  final String? initialTask;

  const AgentWorkspacePage({super.key, required this.agent, this.initialTask});

  @override
  State<AgentWorkspacePage> createState() => _AgentWorkspacePageState();
}

class _AgentWorkspacePageState extends State<AgentWorkspacePage> {
  late final AgentController _agent;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  AgentIdentity get identity => widget.agent;

  // Persisted-chat state for this workspace session.
  bool _persistenceStarted = false;
  AgentStatus _lastSavedStatus = AgentStatus.idle;

  @override
  void initState() {
    super.initState();
    // Show the avatar character that the launched agent belongs to (Cosmo for
    // research, Nixa for coding, …) so the personality on screen always matches
    // the executor running underneath.
    AvatarController.instance.selectCharacter(characterIdOf(identity.type));
    _agent = AgentController(type: identity.type);
    _agent.addListener(_onAgentChanged);
    final initial = widget.initialTask;
    if (initial != null && initial.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_persistUserTask(initial));
        unawaited(_agent.run(initial));
        _scrollToBottom();
      });
    }
  }

  @override
  void dispose() {
    _agent.removeListener(_onAgentChanged);
    _agent.dispose();
    _input.dispose();
    _scroll.dispose();
    // Let the companion avatar settle back to its ambient idle state.
    AvatarController.instance.settle();
    super.dispose();
  }

  /// Save the user's task to history. The first task of a workspace session
  /// opens a brand-new conversation; follow-ups continue the same one.
  Future<void> _persistUserTask(String task) async {
    final history = ChatHistoryController.instance;
    if (!_persistenceStarted) {
      _persistenceStarted = true;
      await history.startNewChat();
    }
    await history.saveUserMessage(task);
  }

  void _onAgentChanged() {
    _syncAvatarToAgent();
    if (_agent.status == _lastSavedStatus) return;
    _lastSavedStatus = _agent.status;

    final history = ChatHistoryController.instance;
    if (_agent.status == AgentStatus.completed ||
        _agent.status == AgentStatus.failed) {
      final kind = _agent.status == AgentStatus.completed
          ? AgentEventKind.taskCompleted
          : AgentEventKind.taskFailed;
      AgentEvent? terminal;
      for (final event in _agent.events.reversed) {
        if (event.kind == kind) {
          terminal = event;
          break;
        }
      }
      if (terminal != null && terminal.message.trim().isNotEmpty) {
        unawaited(history.saveAssistantMessage(terminal.message));
      }
    }
  }

  /// Maps the agent lifecycle onto the selected character's animation states
  /// so the avatar visibly thinks / works / celebrates / frowns while running.
  void _syncAvatarToAgent() {
    final controller = AvatarController.instance;
    switch (_agent.status) {
      case AgentStatus.idle:
        controller.setState(AvatarEvent.idle, force: true);
      case AgentStatus.completed:
        controller.setState(AvatarEvent.success, force: true);
      case AgentStatus.failed:
      case AgentStatus.cancelled:
        controller.setState(AvatarEvent.error, force: true);
      case AgentStatus.running:
        final events = _agent.events;
        final last = events.isNotEmpty ? events.last : null;
        final thinking =
            last != null &&
            (last.kind == AgentEventKind.thinking ||
                last.kind == AgentEventKind.planning);
        controller.setState(
          thinking ? AvatarEvent.thinking : AvatarEvent.working,
          force: true,
        );
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _agent.running) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    await _persistUserTask(text);
    await _agent.run(text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// Responsive avatar size: grows with the viewport but stays inside limits.
  double _avatarSize(BuildContext context, {double max = 200}) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    return (shortest * 0.24).clamp(120.0, max);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListenableBuilder(
        listenable: Listenable.merge([_agent, AvatarController.instance]),
        builder: (context, _) {
          final display = AvatarController.instance.currentCharacter;
          final accent = display.color ?? AppColors.submitButton;
          final showIdle =
              _agent.events.isEmpty &&
              (_agent.activeTask == null || _agent.status == AgentStatus.idle);
          return Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: showIdle
                    ? _buildIdleScreen(context, display, accent)
                    : _buildRunScreen(context, display, accent),
              ),
              _buildBottomBar(display, accent),
            ],
          );
        },
      ),
    );
  }

  // ──────────────────────────────── Top bar ────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.sideNav,
        border: Border(
          bottom: BorderSide(color: AppColors.searchBarBorder),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          Text(
            'Agent Workspace',
            style: GoogleFonts.ibmPlexMono(
              color: Colors.white70,
              fontSize: 12,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          const Icon(Icons.lock_outline, color: Colors.white24, size: 14),
          const SizedBox(width: 6),
          const Text(
            'executing',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────── Identity panels ─────────────────────────

  /// Glowing circular stage + the selected character's live animation.
  Widget _agentStage(AvatarCharacter display, Color accent, double size) {
    final name = display.name;
    return SizedBox(
      width: size + 48,
      height: size + 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft ambient glow in the character's accent colour.
          Container(
            width: size + 42,
            height: size + 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.30),
                  accent.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          Container(
            width: size + 28,
            height: size + 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.28)),
            ),
          ),
          Container(
            width: size + 12,
            height: size + 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.14)),
            ),
          ),
          if (kIsWeb)
            AvatarView(width: size, height: size)
          else
            CircleAvatar(
              radius: size / 2,
              backgroundColor: accent.withValues(alpha: 0.18),
              child: Text(
                name.isEmpty ? '?' : name[0].toUpperCase(),
                style: TextStyle(
                  color: accent,
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _agentName(String name, Color accent, {double fontSize = 30}) {
    return Text(
      name.isEmpty ? 'AGENT' : name.toUpperCase(),
      textAlign: TextAlign.center,
      style: GoogleFonts.ibmPlexMono(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: 3,
      ),
    );
  }

  Widget _agentRole(String role, Color accent) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            role,
            textAlign: TextAlign.center,
            style: GoogleFonts.ibmPlexMono(
              color: accent,
              fontSize: 12,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────── Idle / empty state ──────────────────────

  Widget _buildIdleScreen(
    BuildContext context,
    AvatarCharacter display,
    Color accent,
  ) {
    final size = _avatarSize(context, max: 220);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _agentStage(display, accent, size),
                const SizedBox(height: 18),
                _agentName(display.name, accent),
                const SizedBox(height: 10),
                _agentRole(display.role, accent),
                const SizedBox(height: 20),
                Text(
                  identity.description,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.footerGrey, fontSize: 12),
                ),
                const SizedBox(height: 22),
                _buildSuggestions(context, accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context, Color accent) {
    final suggestions = switch (identity.type) {
      AgentType.researcher => const [
          'Find the latest iPad Pro specs and price in India',
          'Compare 3 budget Android phones under ₹25,000',
          'What is the best laptop for coding in 2026?',
        ],
      AgentType.fileEditing => const [
          'list files',
          'read lib/main.dart',
          'create file lib/app.dart with main() entry',
        ],
      AgentType.coding => const [
          'read lib/main.dart',
          'create file lib/utils/helpers.dart with a sum function',
          'list files and summarize the project structure',
        ],
      AgentType.research => const [
          'Best laptops under ₹60,000 in India right now',
          'Research 5G internet plans in Bangalore',
          'Compare electric scooters for daily commuting',
        ],
      AgentType.writing => const [
          'Write a polite follow-up email to a job recruiter',
          'Write an Instagram caption for a new coffee product',
          'Write a 3-line LinkedIn bio for a Flutter developer',
        ],
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final s in suggestions)
          ActionChip(
            label: Text(s, style: const TextStyle(fontSize: 12)),
            backgroundColor: AppColors.cardColor,
            side: BorderSide(color: accent.withValues(alpha: 0.4)),
            labelStyle: TextStyle(color: accent),
            onPressed: () {
              _input.text = s;
              _send();
            },
          ),
      ],
    );
  }

  // ──────────────────────────────── Running screen ──────────────────────────

  Widget _buildRunScreen(
    BuildContext context,
    AvatarCharacter display,
    Color accent,
  ) {
    final size = _avatarSize(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Column(
            children: [
              _agentStage(display, accent, size),
              const SizedBox(height: 12),
              _agentName(display.name, accent, fontSize: 24),
              const SizedBox(height: 8),
              _agentRole(display.role, accent),
              const SizedBox(height: 10),
              _StatusPill(status: _agent.status, accent: accent),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            border: Border(
              top: BorderSide(color: accent.withValues(alpha: 0.18)),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt, size: 13, color: accent),
              const SizedBox(width: 8),
              Text(
                'LIVE ACTIVITY',
                style: GoogleFonts.ibmPlexMono(
                  color: Colors.white54,
                  fontSize: 11,
                  letterSpacing: 2.5,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildTimeline(context, display, accent)),
      ],
    );
  }

  Widget _buildTimeline(
    BuildContext context,
    AvatarCharacter display,
    Color accent,
  ) {
    final events = _agent.events;
    final showErrorBanner =
        _agent.status == AgentStatus.failed && _agent.error != null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: events.length + 1 + (showErrorBanner ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          final task = _agent.activeTask;
          if (task == null) return const SizedBox.shrink();
          return _TaskChip(text: task, accent: accent);
        }
        if (index >= events.length + 1) {
          return _buildErrorBanner();
        }
        final event = events[index - 1];
        final isActive =
            index == events.length &&
            !event.isTerminal &&
            _agent.status == AgentStatus.running;
        if (event.kind == AgentEventKind.awaitingUser &&
            _agent.status == AgentStatus.running) {
          return _buildConfirmationCard(event.message);
        }
        final showsAnswerCard = identity.type == AgentType.researcher ||
            identity.type == AgentType.research ||
            identity.type == AgentType.writing;
        if (event.isTerminal && showsAnswerCard) {
          return _AgentAnswerCard(
            text: event.message,
            accent: accent,
            agentName: display.name,
            role: display.role,
            isError: event.kind == AgentEventKind.taskFailed,
          );
        }
        return _ActivityTile(
          event: event,
          accent: accent,
          isActive: isActive,
        );
      },
    );
  }

  // ──────────────────────────────── Bottom controls ─────────────────────────

  Widget _buildBottomBar(AvatarCharacter display, Color accent) {
    final running = _agent.status == AgentStatus.running;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.sideNav,
        border: Border(top: BorderSide(color: AppColors.searchBarBorder)),
      ),
      child: running
          ? _RunningStatusBar(
              name: display.name,
              accent: accent,
              onStop: _agent.cancel,
            )
          : _buildInputBar(accent),
    );
  }

  Widget _buildInputBar(Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            onSubmitted: (_) => _send(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'What would you like me to do?',
              hintStyle: TextStyle(color: AppColors.footerGrey),
              filled: true,
              fillColor: AppColors.searchBar,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.searchBarBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.searchBarBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          onPressed: _send,
          icon: const Icon(Icons.send, color: Colors.white),
          tooltip: 'Send',
          style: IconButton.styleFrom(
            backgroundColor: accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1517),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5484D).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: Color(0xFFE5484D), size: 18),
              SizedBox(width: 8),
              Text(
                'Task failed',
                style: TextStyle(
                  color: Color(0xFFE5484D),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (_agent.error != null) ...[
            const SizedBox(height: 6),
            Text(
              stripMarkdownSyntax(_agent.error!),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _agent.retry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFE5484D)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationCard(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2413),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF5A623).withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber, color: Color(0xFFF5A623), size: 18),
              SizedBox(width: 8),
              Text(
                'Waiting for your confirmation',
                style: TextStyle(
                  color: Color(0xFFF5A623),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stripMarkdownSyntax(message.isEmpty ? 'May I proceed?' : message),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _agent.confirmAction(false),
                child: const Text('Deny'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _agent.confirmAction(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF5A623),
                  foregroundColor: Colors.black,
                ),
                child: const Text('Allow'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Status pill shown under the agent identity ("● Working", "✓ Completed"…).
class _StatusPill extends StatelessWidget {
  final AgentStatus status;
  final Color accent;

  const _StatusPill({required this.status, required this.accent});

  @override
  Widget build(BuildContext context) {
    final (color, idle) = switch (status) {
      AgentStatus.idle => (AppColors.footerGrey, true),
      AgentStatus.running => (accent, false),
      AgentStatus.completed => (const Color(0xFF34C77B), false),
      AgentStatus.failed => (const Color(0xFFE5484D), false),
      AgentStatus.cancelled => (AppColors.iconGrey, false),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == AgentStatus.running)
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: idle ? Colors.transparent : color,
                shape: BoxShape.circle,
                border: idle ? Border.all(color: color, width: 1.4) : null,
              ),
            ),
          const SizedBox(width: 7),
          Text(
            statusLabel(status),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small right-aligned pill showing the user's current task.
class _TaskChip extends StatelessWidget {
  final String text;
  final Color accent;

  const _TaskChip({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 15, color: accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact vertical-timeline activity row: completed steps get a subtle ✓,
/// the currently running step gets an animated loader in the accent colour.
class _ActivityTile extends StatelessWidget {
  final AgentEvent event;
  final Color accent;
  final bool isActive;

  const _ActivityTile({
    required this.event,
    required this.accent,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final kind = event.kind;
    final failed = kind == AgentEventKind.taskFailed;
    final cancelled = kind == AgentEventKind.taskCancelled;
    final errorColor = const Color(0xFFE5484D);
    final successColor = const Color(0xFF34C77B);

    final Widget leading;
    if (isActive) {
      leading = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
      );
    } else if (failed || cancelled) {
      leading = Icon(
        failed ? Icons.error : Icons.cancel,
        size: 16,
        color: errorColor,
      );
    } else if (kind == AgentEventKind.awaitingUser) {
      leading = Icon(Icons.more_horiz, size: 16, color: AppColors.footerGrey);
    } else {
      leading = Icon(Icons.check_circle, size: 16, color: successColor);
    }

    final title = stripMarkdownSyntax(event.message);
    final detail = event.detail;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Center(
                child: isActive
                    ? _PulsingLoader(size: 18, color: accent)
                    : leading,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isActive
                    ? accent.withValues(alpha: 0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isActive
                    ? Border.all(color: accent.withValues(alpha: 0.30))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isActive
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.82),
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      height: 1.35,
                    ),
                  ),
                  if (detail != null && detail.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      detail,
                      style: GoogleFonts.ibmPlexMono(
                        color: AppColors.textGrey,
                        fontSize: 10.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated pulsing loader for the "currently running" activity step.
class _PulsingLoader extends StatefulWidget {
  final double size;
  final Color color;

  const _PulsingLoader({required this.size, required this.color});

  @override
  State<_PulsingLoader> createState() => _PulsingLoaderState();
}

class _PulsingLoaderState extends State<_PulsingLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CircularProgressIndicator(strokeWidth: 2, color: widget.color),
      ),
    );
  }
}

/// Bottom-left running status (``<Name> is working…``) + red STOP button.
class _RunningStatusBar extends StatelessWidget {
  final String name;
  final Color accent;
  final VoidCallback onStop;

  const _RunningStatusBar({
    required this.name,
    required this.accent,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final label = name.isEmpty ? 'AGENT' : name;
    return Row(
      children: [
        _PulsingLoader(size: 16, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$label is working…',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: onStop,
          icon: const Icon(Icons.stop, size: 18),
          label: const Text('Stop'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE5484D),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

/// Terminal chat-style answer card (kept for the researcher/browser agent);
/// name and role are fed dynamically from the selected character.
class _AgentAnswerCard extends StatelessWidget {
  final String text;
  final Color accent;
  final String agentName;
  final String role;
  final bool isError;

  const _AgentAnswerCard({
    required this.text,
    required this.accent,
    required this.agentName,
    required this.role,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    return StrobiAssistantMessage(
      text: text,
      accent: accent,
      agentName: agentName,
      role: role,
      isError: isError,
    );
  }
}