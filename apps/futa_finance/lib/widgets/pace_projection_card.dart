import 'package:flutter/material.dart';

import '../mock/dashboard_summary.dart';
import '../utils/formatters.dart';
import 'pulse_widget.dart';

/// 「このペースだと月末いくら？」を脈打つ大文字で表示。
/// 設計思想の核心: 数字を読むのでなく感覚で掴めるよう、脈動 + 色温度を組み合わせる。
class PaceProjectionCard extends StatelessWidget {
  final DashboardSummary summary;

  const PaceProjectionCard({super.key, required this.summary});

  /// 着地予測額から色温度を決める（仮の閾値、後で過去平均と比較する設計に差し替え予定）。
  Color _temperatureColor() {
    final p = summary.paceProjection;
    if (p < 100000) return const Color(0xFF66BB6A); // green
    if (p < 150000) return const Color(0xFFFFB74D); // amber
    return const Color(0xFFEF5350); // red
  }

  String _temperatureLabel() {
    final p = summary.paceProjection;
    if (p < 100000) return '健全';
    if (p < 150000) return '注意';
    return '使いすぎ';
  }

  @override
  Widget build(BuildContext context) {
    final color = _temperatureColor();
    final progress = summary.monthProgress;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, size: 16, color: color),
                  const SizedBox(width: 6),
                  const Text(
                    'このペースだと月末',
                    style: TextStyle(fontSize: 12, color: Color(0xFFE5E7EB)),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _temperatureLabel(),
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: PulseWidget(
              amplitude: 0.025,
              period: const Duration(seconds: 3),
              child: Text(
                formatYen(summary.paceProjection),
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontFamily: 'monospace',
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 月の進捗バー
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF1F2937),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${summary.daysElapsed}/${summary.daysInMonth}日経過',
                style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
              ),
              Text(
                '月末残高 ${formatYen(summary.monthEndProjectedBalance)}',
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFE5E7EB),
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
