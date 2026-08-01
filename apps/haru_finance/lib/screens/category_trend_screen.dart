import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// あるカテゴリの直近12ヶ月の支出推移を見る画面。
/// 分析タブのカテゴリ内訳をタップして開く。
class CategoryTrendScreen extends StatelessWidget {
  final String category;
  const CategoryTrendScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    final c = categoryFor(category, income: false);
    return Scaffold(
      appBar: AppBar(title: Text('$category の推移')),
      body: hid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<core.Transaction>>(
              stream: TxRepository.instance.watch(hid),
              builder: (context, snap) {
                final all = snap.data ?? const <core.Transaction>[];
                // ※ DateTime.now() は build 内で都度評価（描画時点の今日基準でOK）。
                final now = DateTime.now();
                final months = List.generate(
                    12, (i) => DateTime(now.year, now.month - (11 - i)));
                final amounts = <int>[];
                for (final m in months) {
                  var sum = 0;
                  for (final t in all) {
                    if (t.type == core.TransactionType.expense &&
                        t.category.major == category &&
                        t.date.year == m.year &&
                        t.date.month == m.month) {
                      sum += t.amount;
                    }
                  }
                  amounts.add(sum);
                }
                final total = amounts.fold<int>(0, (s, v) => s + v);
                final avg = (total / 12).round();
                final maxV = amounts.fold<int>(1, (s, v) => v > s ? v : s);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    // ヘッダー（カテゴリ＋年間合計・月平均）
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: c.color.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(c.icon, color: c.color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('この1年の合計',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSub)),
                                Text(formatYen(total),
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900)),
                                Text('月平均 ${formatYen(avg)}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSub)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('月別の推移',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 16, 8, 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: AppColors.pinkSoft, width: 1.2),
                      ),
                      child: SizedBox(
                        height: 160,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (int i = 0; i < months.length; i++)
                              Expanded(
                                child: _barColumn(
                                    months[i], amounts[i], maxV, c.color),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('月別の金額',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    for (int i = months.length - 1; i >= 0; i--)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                  '${months[i].year}年${months[i].month}月',
                                  style: const TextStyle(fontSize: 13)),
                            ),
                            Text(
                              amounts[i] == 0
                                  ? '—'
                                  : formatYen(amounts[i]),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: amounts[i] == 0
                                    ? AppColors.textSub
                                    : AppColors.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _barColumn(DateTime m, int amount, int maxV, Color color) {
    const barArea = 120.0;
    final h = maxV == 0 ? 0.0 : (amount / maxV) * barArea;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (amount > 0)
          Text(
            amount >= 10000
                ? '${(amount / 10000).toStringAsFixed(1)}万'
                : '${(amount / 1000).round()}k',
            style: const TextStyle(fontSize: 8, color: AppColors.textSub),
          ),
        const SizedBox(height: 2),
        Container(
          width: 12,
          height: h < 2 && h > 0 ? 2 : h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
        const SizedBox(height: 4),
        Text('${m.month}',
            style: const TextStyle(fontSize: 9, color: AppColors.textSub)),
      ],
    );
  }
}
