import 'package:flutter/material.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/widgets/morph_hint.dart';

/// Minimal bottom-docked shopping search bar.
///
/// [The morph effects]
/// - The placeholder softly morphs between example queries (blur/fade).
/// - The whole bar morphs shape + glow when focused.
/// - When the agent is running the bar + button morph into the "working" state.
class CommerceControls extends StatefulWidget {
  final TextEditingController queryController;
  final bool isAgentRunning;
  final VoidCallback onStartAgent;
  final VoidCallback onStopAgent;

  const CommerceControls({
    super.key,
    required this.queryController,
    required this.isAgentRunning,
    required this.onStartAgent,
    required this.onStopAgent,
  });

  @override
  State<CommerceControls> createState() => _CommerceControlsState();
}

class _CommerceControlsState extends State<CommerceControls> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _onSubmitted(String _) {
    if (widget.isAgentRunning) {
      widget.onStopAgent();
    } else {
      widget.onStartAgent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.isAgentRunning;
    final focused = _focus.hasFocus;

    final barColor = running
        ? const Color(0xFF1C1E20)
        : (focused ? const Color(0xFF232629) : AppColors.searchBar);
    final barBorder = running
        ? const Color(0xFF34C77B)
        : (focused ? AppColors.accent : AppColors.searchBarBorder);
    final glow = running || focused;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status / hint caption that morphs with the agent state.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: running
              ? Padding(
                  key: const ValueKey('running'),
                  padding: const EdgeInsets.only(left: 6, bottom: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 8,
                        height: 8,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFF34C77B)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Agent is shopping...',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                )
              : Padding(
                  key: const ValueKey('idle'),
                  padding: const EdgeInsets.only(left: 6, bottom: 8),
                  child: Text(
                    'Ask me and I will find the best 2-3 options for you.',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ),
        ),
        // The morphing search bar.
        AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(18, running ? 10 : 12, 8, running ? 10 : 12),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(focused ? 16 : 28),
            border: Border.all(color: barBorder, width: focused || running ? 1.4 : 1),
            boxShadow: glow
                ? [
                    BoxShadow(
                      color: (running ? const Color(0xFF34C77B) : AppColors.accent)
                          .withValues(alpha: 0.22),
                      blurRadius: running ? 18 : 12,
                      spreadRadius: running ? 1 : 0,
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              // Morph icon: search when idle, auto-awesome highlight on focus.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  focused && !running ? Icons.auto_awesome : Icons.search,
                  key: ValueKey(focused && !running),
                  size: 20,
                  color: running ? const Color(0xFF34C77B) : AppColors.iconGrey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.queryController,
                  builder: (context, value, _) {
                    const style = TextStyle(color: Colors.white, fontSize: 13);
                    return Stack(
                      children: [
                        if (value.text.isEmpty)
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: MorphHint(
                                phrases: const [
                                  'Wireless earbuds under ₹5000...',
                                  'A 65W GaN charger...',
                                  'Sneakers that match my gym bag...',
                                  'Best budget mechanical keyboard...',
                                ],
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        TextField(
                          controller: widget.queryController,
                          focusNode: _focus,
                          style: style,
                          enabled: !running,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintStyle: TextStyle(color: Colors.white, fontSize: 13),
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: _onSubmitted,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // The morphing run/stop button.
              _ActionButton(
                running: running,
                onPressed: running ? widget.onStopAgent : widget.onStartAgent,
                empty: widget.queryController.text.trim().isEmpty,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Circular pill that morphs between the idle "start" state and the running
/// "stop" state (icon, color, glow).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.running,
    required this.onPressed,
    required this.empty,
  });

  final bool running;
  final VoidCallback onPressed;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final enabled = running || !empty;
    return Tooltip(
      message: running ? 'Stop agent' : 'Start search',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: running ? const Color(0xFFE5484D) : AppColors.submitButton,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: (running ? const Color(0xFFE5484D) : AppColors.accent)
                  .withValues(alpha: enabled ? 0.35 : 0),
              blurRadius: 14,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: running
                    ? const Icon(Icons.stop, key: ValueKey('stop'), color: Colors.white, size: 22)
                    : Icon(
                        Icons.arrow_forward,
                        key: const ValueKey('send'),
                        color: enabled ? AppColors.background : Colors.white24,
                        size: 20,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}