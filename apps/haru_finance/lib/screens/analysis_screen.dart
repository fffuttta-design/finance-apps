import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/categories.dart';
import '../data/household_service.dart';
import '../data/tx_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/settings_button.dart';
import '../widgets/simple_pie_chart.dart';
import 'category_trend_screen.dart';

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
                    _sectionTitle('今月の支出内訳'),
                    const SizedBox(height: 8),
                    _pieCard(all),
                    const SizedBox(height: 12),
                    _engelCard(all),
                    const SizedBox(height: 16),
                    _sectionTitle('カテゴリ別（タップで1年の推移）'),
                    const SizedBox(height: 8),
                    _categoryCard(context, all),
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

  /// 今月の支出カテゴリ内訳（円グラフ）。
  Widget _pieCard(List<core.Transaction> all) {
    final entries = _thisMonthByCat(all);
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.pinkSoft, width: 1.2),
        ),
        child: const Text('今月の支出はまだないよ',
            style: TextStyle(color: AppColors.textSub, fontSize: 12)),
      );
    }
    // 上位6カテゴリ＋残りを「その他」にまとめてスライス化。
    final top = entries.take(6).toList();
    final restSum =
        entries.skip(6).fold<int>(0, (s, e) => s + e.value);
    final slices = <PieSlice>[
      for (final e in top)
        PieSlice(e.key, e.value, categoryFor(e.key, income: false).color),
      if (restSum > 0) PieSlice('その他', restSum, AppColors.textSub),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.pinkSoft, width: 1.2),
      ),
      child: Column(
        children: [
          SimplePieChart(
            slices: slices,
            size: 170,
            centerTop: '支出合計',
            centerBottom: formatYen(total),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final s in slices)
                _legend(s.color,
                    '${s.label} ${((s.value / total) * 100).round()}%'),
            ],
          ),
        ],
      ),
    );
  }

  /// エンゲル係数カード（食料費 ÷ 支出合計）。
  /// 食料費＝「食費」＋「外食」。
  Widget _engelCard(List<core.Transaction> all) {
    final now = DateTime.now();
    var food = 0, total = 0;
    for (final t in all) {
      if (t.type != core.TransactionType.expense) continue;
      if (t.date.year != now.year || t.date.month != now.month) continue;
      total += t.amount;
      if (t.category.major == '食費' || t.category.major == '外食') {
        food += t.amount;
      }
    }
    final pct = total == 0 ? 0.0 : (food / total * 100);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE2EA), Color(0xFFFFF1F4)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.pinkSoft, width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.restaurant_rounded,
              size: 26, color: AppColors.pinkDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('エンゲル係数（今月）',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                Text('食費＋外食 ${formatYen(food)} / 支出 ${formatYen(total)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ),
          Text('${pct.toStringAsFixed(1)}%',
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.pinkDark)),
        ],
      ),
    );
  }

  /// 今月のカテゴリ別支出を金額の多い順で返す。
  List<MapEntry<String, int>> _thisMonthByCat(List<core.Transaction> all) {
    final now = DateTime.now();
    final byCat = <String, int>{};
    for (final t in all) {
      if (t.type != core.TransactionType.expense) continue;
      if (t.date.year != now.year || t.date.month != now.month) continue;
      byCat[t.category.major] = (byCat[t.category.major] ?? 0) + t.amount;
    }
    return byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  Widget _categoryCard(BuildContext context, List<core.Transaction> all) {
    final entries = _thisMonthByCat(all);
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        alignment: Alignment.center,
        child: const Text('今月の支出はまだないよ',
            style: TextStyle(color: AppColors.textSub, fontSize: 12)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.pinkSoft, width: 1.2),
      ),
      child: Column(
        children: [
          for (final e in entries) _catRow(context, e.key, e.value, total),
        ],
      ),
    );
  }

  Widget _catRow(
      BuildContext context, String name, int amount, int total) {
    final c = categoryFor(name, income: false);
    final ratio = total == 0 ? 0.0 : amount / total;
    final pct = (ratio * 100).round();
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CategoryTrendScreen(category: name)),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textSub),
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
