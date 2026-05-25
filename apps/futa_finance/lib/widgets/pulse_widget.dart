import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 子ウィジェットを呼吸するようにゆっくり脈動させる。
/// 「肌で感じる」設計思想 — 静的な数字でなく、動的に "生きている" 表現にするための部品。
class PulseWidget extends StatefulWidget {
  final Widget child;

  /// 脈動の振幅（0.0 = 動かない, 0.05 = 5%スケール変動）。
  final double amplitude;

  /// 1サイクルにかける時間。
  final Duration period;

  const PulseWidget({
    super.key,
    required this.child,
    this.amplitude = 0.03,
    this.period = const Duration(seconds: 3),
  });

  @override
  State<PulseWidget> createState() => _PulseWidgetState();
}

class _PulseWidgetState extends State<PulseWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final wave = 0.5 - 0.5 * math.cos(_controller.value * 2 * math.pi);
        final scale = 1.0 + widget.amplitude * wave;
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}
