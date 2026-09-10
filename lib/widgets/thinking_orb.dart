import 'dart:math' as math;

import 'package:flutter/material.dart';

enum ThinkingOrbState { idle, thinking, searching, done }

class ThinkingOrb extends StatefulWidget {
  const ThinkingOrb({
    super.key,
    this.state = ThinkingOrbState.searching,
    this.size = 64,
    this.color = const Color(0xFF1BB9CE),
    this.orbCount = 5,
  });

  final ThinkingOrbState state;
  final double size;
  final Color color;
  final int orbCount;

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final duration = switch (widget.state) {
      ThinkingOrbState.done => const Duration(milliseconds: 900),
      ThinkingOrbState.searching => const Duration(milliseconds: 1300),
      ThinkingOrbState.thinking => const Duration(milliseconds: 2100),
      ThinkingOrbState.idle => const Duration(milliseconds: 1600),
    };
    _controller = AnimationController(vsync: this, duration: duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.state != ThinkingOrbState.idle;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ThinkingOrbPainter(
              progress: active ? _controller.value : 0,
              color: widget.color,
              active: active,
              done: widget.state == ThinkingOrbState.done,
              orbCount: widget.orbCount,
            ),
          );
        },
      ),
    );
  }
}

class _ThinkingOrbPainter extends CustomPainter {
  _ThinkingOrbPainter({
    required this.progress,
    required this.color,
    required this.active,
    required this.done,
    required this.orbCount,
  });

  final double progress;
  final Color color;
  final bool active;
  final bool done;
  final int orbCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;

    final coreRadius = r * (done ? 0.34 : 0.20);
    canvas.drawCircle(
      center,
      coreRadius,
      Paint()
        ..color =
            color.withValues(alpha: active ? (done ? 0.95 : 0.65) : 0.30),
    );

    final haloRadius = r * (done ? 0.05 : 0.18);
    final haloProgress = (progress * 3) % 1.0;
    canvas.drawCircle(
      center,
      coreRadius + haloRadius + haloProgress * r * 0.55,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(
            alpha: (1 - haloProgress) * (done ? 0.75 : 0.45)),
    );

    for (var i = 0; i < orbCount; i++) {
      final phase = i / orbCount;
      final angle = progress * math.pi * 2 + phase * math.pi * 2;

      final breathe = (math.sin(progress * 4 + phase * math.pi * 4) * 0.5 + 0.5);
      final orbitRadius = switch (done) {
        true => r * (0.30 + 0.16 * breathe),
        false => r * (0.20 + 0.30 * breathe),
      };

      final px = center.dx + math.cos(angle) * orbitRadius;
      final py = center.dy + math.sin(angle) * orbitRadius * 0.85;

      final orbRadius = switch (done) {
        true => r * (0.05 + 0.03 * breathe),
        false => r * (0.13 + 0.05 * breathe),
      };
      final alpha = active
          ? (0.55 + 0.40 * breathe)
          : 0.20;

      canvas.drawCircle(
        Offset(px, py),
        orbRadius,
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ThinkingOrbPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.active != active ||
        oldDelegate.done != done ||
        oldDelegate.orbCount != orbCount;
  }
}