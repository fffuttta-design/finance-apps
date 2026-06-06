import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/settings_button.dart';

/// 分析：月別の収支推移（6ヶ月）と今月のカテゴリ内訳（自前描画・依存なし）。
class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(
          title: const Text('分析'), actions: const [SettingsButton()]),
      body: hid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<core.Transaction>>(
              stream: TxRepository.instance.watch(hid),
              builder: (context, snap) {
                final all = snap.data ?? const <core.Transaction>[];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    _sectionTitle('月別の収支（6ヶ月）'),
                    const SizedBox(height: 8),
                    _trendCard(all),
                    const SizedBox(height: 20),
                    _sectionTitle('今月のカテゴリ内訳'),
                    const SizedBox(height: 8),
                    _categoryCard(all),
                  ],
                );
              },
            ),
    );
  }

  Widget _trendCard(List<core.Transaction> all) {
    final now = DateTime.now();
    final months =
        List.generate(6, (i) => DateTime(now.year, now.month - (5 - i)));
    final exp = <int>[];
    final inc = <int>[];
    for (final m in months) {
      int e = 0, ic = 0;
      for (final t in all) {
        if (t.date.year == m.year && t.date.month == m.month) {
          if (t.type == core.TransactionType.expense) {
            e += t.amount;
          } else if (t.type == core.TransactionType.income) {
            ic += t.amount;
          }
        }
      }
      exp.add(e);
      inc.add(ic);
    }
    final maxV = [...exp, ...inc].fold<int>(1, (s, v) => v > s ? v : s);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.pinkSoft, width: 1.2),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < months.length; i++)
                  Expanded(
                    child: _monthColumn(months[i], inc[i], exp[i], maxV),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend(AppColors.income, '収入'),
              const SizedBox(width: 16),
              _legend(AppColors.expense, '支出'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthColumn(DateTime m, int income, int expense, int maxV) {
    const barArea = 96.0;
    double h(int v) => maxV == 0 ? 0 : (v / maxV) * barArea;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(h(income), AppColors.income),
            const SizedBox(width: 3),
            _bar(h(expense), AppColors.expense),
          ],
        ),
        const SizedBox(height: 6),
        Text('${m.month}月',
            style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
      ],
    );
  }

  Widget _bar(double height, Color color) {
    return Container(
      width: 11,
      height: height < 2 && height > 0 ? 2 : height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
      ],
    );
  }

  Widget _categoryCard(List<core.Transaction> all) {
    final now = DateTime.now();
    final month = all.where((t) =>
        t.date.year == now.year &&
        t.date.month == now.month &&
        t.type == core.TransactionType.expense);
    final byCat = <String, int>{};
    var total = 0;
    for (final t in month) {
      byCat[t.category.major] = (byCat[t.category.major] ?? 0) + t.amount;
      total += t.amount;
    }
    final entries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        alignment: Alignment.center,
        child: const Text('今月の支出はまだないよ',
            style: TextStyle(color: AppColors.textSub, fontSize: 12)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.pinkSoft, width: 1.2),
      ),
      child: Column(
        children: [
          for (final e in entries) _catRow(e.key, e.value, total),
        ],
      ),
    );
  }

  Widget _catRow(String name, int amount, int total) {
    final c = categoryFor(name, income: false);
    final ratio = total == 0 ? 0.0 : amount / total;
    final pct = (ratio * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: c.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(c.icon, size: 16, color: c.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600))),
              Text('$pct%　${formatYen(amount)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: AppColors.pinkSoft,
              valueColor: AlwaysStoppedAnimation(c.color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
      );
}
