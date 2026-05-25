import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../mock/dashboard_summary.dart';
import '../utils/formatters.dart';

/// カテゴリ別の熱量グリッド。使いすぎ感を色＋絵文字で。
class CategoryHeatGrid extends StatelessWidget {
  final DashboardSummary summary;

  const CategoryHeatGrid({super.key, required this.summary});

  // 各カテゴリの「普段」値（モック。本来は過去平均から算出）。
  static const _baseline = <String, int>{
    FutaCategories.fixedFlat: 50000,
    FutaCategories.fixedVariable: 14000,
    FutaCategories.supplies: 15000,
    FutaCategories.travel: 5000,
    FutaCategories.entertainment: 8000,
    FutaCategories.training: 10000,
    FutaCategories.meeting: 2000,
    FutaCategories.misc: 3000,
  };

  ({Color color, String emoji}) _heatOf(String major, int amount) {
    final base = _baseline[major] ?? 1;
    final ratio = amount / base;
    if (ratio < 0.5) return (color: const Color(0xFF3B82F6), emoji: '🟦');
    if (ratio < 1.1) return (color: const Color(0xFF16A34A), emoji: '🟢');
    if (ratio < 1.5) return (color: const Color(0xFFF59E0B), emoji: '🟡');
    if (ratio < 2.0) return (color: const Color(0xFFEA580C), emoji: '🟠');
    return (color: const Color(0xFFDC2626), emoji: '🔥');
  }

  @override
  Widget build(BuildContext context) {
    final totals = summary.totalByMajor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_fire_department,
                  size: 16, color: Color(0xFFEA580C)),
              SizedBox(width: 6),
              Text(
                'カテゴリ別熱量',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...FutaCategories.allMajor.map((major) {
            final amount = totals[major] ?? 0;
            final heat = _heatOf(major, amount);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(heat.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      major,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF111827)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatYen(amount),
                    style: TextStyle(
                      fontSize: 13,
                      color: amount == 0
                          ? const Color(0xFFD1D5DB)
                          : heat.color,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
