import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Rotates through hint phrases with a blur-and-fade cross-morph, so an empty
/// search/input field's placeholder softly "morphs" between examples.
class MorphHint extends StatefulWidget {
  const MorphHint({super.key, required this.phrases, required this.style});

  final List<String> phrases;
  final TextStyle style;

  @override
  State<MorphHint> createState() => _MorphHintState();
}

class _MorphHintState extends State<MorphHint>
    with SingleTickerProviderStateMixin {
  static const double _hold = 3.0;
  static const double _morph = 0.8;
  static const double _blur = 16.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );
  int _index = 0;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTick);
    _controller.repeat();
  }

  void _onTick() {
    final v = _controller.value;
    if (v < _last) {
      setState(() => _index++);
    }
    _last = v;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  double _morphK(double t) {
    final holdFrac = _hold / (_hold + _morph);
    return t <= holdFrac ? 0.0 : (t - holdFrac) / (1 - holdFrac);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final n = widget.phrases.length;
        final cur = widget.phrases[_index % n];
        final nxt = widget.phrases[(_index + 1) % n];
        final raw = _morphK(_controller.value);
        final k = Curves.easeInOut.transform(raw);
        final exit = 1 - k;
        return Stack(
          fit: StackFit.expand,
          children: [
            _morphText(cur, exit, _blur * k),
            _morphText(nxt, k, _blur * exit),
          ],
        );
      },
    );
  }

  Widget _morphText(String text, double opacity, double blur) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.style,
            ),
          ),
        ),
      ),
    );
  }
}