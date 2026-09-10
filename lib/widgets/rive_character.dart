import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

/// Reusable animated Rive character.
///
/// Keeps the character playing its state machine. Tap fires any trigger
/// inputs the asset actually exposes (never invents new ones). Increment
/// [pulse] externally to fire triggers again (e.g. on agent status changes).
class RiveCharacter extends StatefulWidget {
  final String asset;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final int pulse;

  const RiveCharacter({
    super.key,
    required this.asset,
    required this.width,
    required this.height,
    this.onTap,
    this.pulse = 0,
  });

  @override
  State<RiveCharacter> createState() => _RiveCharacterState();
}

class _RiveCharacterState extends State<RiveCharacter> {
  RiveWidgetController? _controller;
  int _lastPulse = 0;

  void _handleOnLoaded(RiveLoaded state) {
    _controller = state.controller;
  }

  void _fireTriggers() {
    final controller = _controller;
    if (controller == null) return;
    final stateMachine = controller.stateMachine;
    for (var i = 0;; i++) {
      final input = stateMachine.inputAt(i);
      if (input == null) break;
      if (input is TriggerInput) {
        input.fire();
      }
    }
  }

  @override
  void didUpdateWidget(covariant RiveCharacter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse != _lastPulse) {
      _lastPulse = widget.pulse;
      _fireTriggers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _fireTriggers();
        widget.onTap?.call();
      },
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: RiveWidgetBuilder(
          fileLoader: FileLoader.fromAsset(
            widget.asset,
            riveFactory: Factory.rive,
          ),
          onLoaded: _handleOnLoaded,
          onFailed: (error, stackTrace) {
            debugPrint('Failed to load Rive ${widget.asset}: $error');
          },
          builder: (context, state) {
            if (state is RiveLoading) {
              return const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF1BB9CE),
                  ),
                ),
              );
            }
            if (state is RiveFailed) {
              return const Center(
                child: Icon(Icons.error_outline, color: Colors.grey),
              );
            }
            return RiveWidget(
              controller: (state as RiveLoaded).controller,
              fit: Fit.contain,
            );
          },
        ),
      ),
    );
  }
}