import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 円グラフ1スライス分のデータ。
class PieSlice {
  final String label;
  final int value;
  final Color color;
  const PieSlice(this.label, this.value, this.color);
}

/// 依存ライブラリなしの自前ドーナツ円グラフ。
/// 中央に合計などのテキスト（[centerTop]/[centerBottom]）を表示できる。
class SimplePieChart extends StatelessWidget {
  final List<PieSlice> slices;
  final double size;
  final String? centerTop;
  final String? centerBottom;

  const SimplePieChart({
    super.key,
    required this.slices,
    this.size = 160,
    this.centerTop,
    this.centerBottom,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DonutPainter(slices),
          ),
          if (centerTop != null || centerBottom != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (centerTop != null)
                  Text(centerTop!,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9E8A92))),
                if (centerBottom != null)
                  Text(centerBottom!,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<PieSlice> slices;
  _DonutPainter(this.slices);

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (s, e) => s + e.value);
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2;
    final stroke = radius * 0.42; // ドーナツの太さ
    final r = radius - stroke / 2;

    if (total <= 0) {
      final paint = Paint()
        ..color = const Color(0xFFF3E1E7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke;
      canvas.drawCircle(center, r, paint);
      return;
    }

    var start = -math.pi / 2; // 12時方向から開始
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = (s.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        start,
        sweep - 0.012, // スライス間に細い隙間
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices;
}
