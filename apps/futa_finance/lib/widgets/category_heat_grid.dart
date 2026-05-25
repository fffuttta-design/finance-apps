import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../data/settings_repository.dart';
import '../mock/dashboard_summary.dart';
import '../utils/category_icons.dart';
import '../utils/formatters.dart';

/// カテゴリ別の集計グリッド（旧: カテゴリ別熱量）。
///
/// 使いすぎ感を色＋絵文字、各大カテゴリのアイコン付きで表示。
/// CategoryConfig をロードしてユーザー編集後の最新カテゴリ一覧に追従する。
class CategoryHeatGrid extends StatefulWidget {
  final DashboardSummary summary;

  const CategoryHeatGrid({super.key, required this.summary});

  @override
  State<CategoryHeatGrid> createState() => _CategoryHeatGridState();
}

class _CategoryHeatGridState extends State<CategoryHeatGrid> {
  final _settings = SettingsRepository();
  CategoryConfig? _config;

  // 各カテゴリの「普段」値（モック。本来は過去平均から算出）。
  // 名前ベースでマッチング（番号プレフィックス無し）。
  static const _baseline = <String, int>{
    '固定費(定額)': 50000,
    '固定費(変動)': 14000,
    '消耗品費': 15000,
    '旅費交通費': 5000,
    '交際費': 8000,
    '研修費': 10000,
    '会議費': 2000,
    '雑費': 3000,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _settings.loadCategories();
    if (!mounted) return;
    setState(() => _config = c);
  }

  ({Color color, String emoji}) _heatOf(String majorName, int amount) {
    final base = _baseline[majorName] ?? 1;
    final ratio = amount / base;
    if (ratio < 0.5) return (color: const Color(0xFF3B82F6), emoji: '🟦');
    if (ratio < 1.1) return (color: const Color(0xFF16A34A), emoji: '🟢');
    if (ratio < 1.5) return (color: const Color(0xFFF59E0B), emoji: '🟡');
    if (ratio < 2.0) return (color: const Color(0xFFEA580C), emoji: '🟠');
    return (color: const Color(0xFFDC2626), emoji: '🔥');
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (config == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // CategoryConfig 上のカテゴリで totals を再構築
    // (summary.expenseByMajor は FutaCategories.allMajor で生成されているため、
    //  ユーザー編集に追従するためここで作り直す)
    final totals = <String, int>{};
    for (int i = 0; i < config.majors.length; i++) {
      totals[config.majors[i].displayName(i)] = 0;
    }
    for (final t in widget.summary.currentMonthTransactions
        .where((x) => x.type == TransactionType.expense)) {
      totals[t.category.major] =
          (totals[t.category.major] ?? 0) + t.amount;
    }

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
              Icon(Icons.category, size: 16, color: Color(0xFF1A237E)),
              SizedBox(width: 6),
              Text(
                'カテゴリ別集計',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(config.majors.length, (i) {
            final major = config.majors[i];
            final displayName = major.displayName(i);
            final amount = totals[displayName] ?? 0;
            final heat = _heatOf(major.name, amount);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(iconForKey(major.iconKey),
                      size: 18, color: heat.color),
                  const SizedBox(width: 8),
                  Text(heat.emoji, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      displayName,
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
