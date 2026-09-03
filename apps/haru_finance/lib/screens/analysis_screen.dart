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

import '../widgets/web_layout.dart';
/// 分析：月で見るか年で見るかを、上のボタンで切り替える（自前描画・依存なし）。
///
/// - 月で見る：直近6ヶ月の収支と、今月のカテゴリ内訳
/// - 年で見る：その年の総収入・総支出・差引、12ヶ月の推移、年のカテゴリ内訳、
///             そして記録し始めてからの累計（ためた合計）
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  /// 年で見るモードかどうか（false なら月で見る）。
  bool _yearly = false;

  /// 年モードで表示している年。
  int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final hid = HouseholdService.instance.householdId;
    return Scaffold(
      appBar: AppBar(
          title: const Text('分析'), actions: const [SettingsButton()]),
      body: WebCenterFill(
        maxWidth: 1040,
        child: hid == null
            ? const Center(child: CircularProgressIndicator())
            : StreamBuilder<List<core.Transaction>>(
                stream: TxRepository.instance.watch(hid),
                builder: (context, snap) {
                  final all = snap.data ?? const <core.Transaction>[];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      _modeSwitch(),
                      const SizedBox(height: 16),
                      if (_yearly)
                        ..._yearlyBody(context, all)
                      else
                        ..._monthlyBody(context, all),
                    ],
                  );
                },
              ),
      ),
    );
  }

  // ── 月で見る / 年で見る の切替 ──────────────────────────────

  Widget _modeSwitch() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.pinkSoft, width: 1.2),
        ),
        child: Row(
          children: [
            _modeTab('月で見る', false),
            _modeTab('年で見る', true),
          ],
        ),
      );

  Widget _modeTab(String label, bool yearly) {
    final selected = _yearly == yearly;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _yearly = yearly),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.pink : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppColors.textSub)),
        ),
      ),
    );
  }

  // ── 月で見るモード ─────────────────────────────────────────

  List<Widget> _monthlyBody(BuildContext context, List<core.Transaction> all) {
    final now = DateTime.now();
    final months =
        List.generate(6, (i) => DateTime(now.year, now.month - (5 - i)));
    return [
      _sectionTitle('月別の収支（6ヶ月）'),
      const SizedBox(height: 8),
      _trendCard(all, months),
      const SizedBox(height: 20),
      _sectionTitle('今月の支出内訳'),
      const SizedBox(height: 8),
      _pieCard(_byCat(all, now.year, now.month), '今月の支出はまだないよ'),
      const SizedBox(height: 12),
      _engelCard(all),
      const SizedBox(height: 16),
      _sectionTitle('カテゴリ別（タップで1年の推移）'),
      const SizedBox(height: 8),
      _categoryCard(context, _byCat(all, now.year, now.month), '今月の支出はまだないよ'),
    ];
  }

  // ── 年で見るモード ─────────────────────────────────────────

  List<Widget> _yearlyBody(BuildContext context, List<core.Transaction> all) {
    var income = 0, expense = 0;
    for (final t in all) {
      if (t.date.year != _year) continue;
      if (t.type == core.TransactionType.income) {
        income += t.amount;
      } else if (t.type == core.TransactionType.expense) {
        expense += t.amount;
      }
    }
    final months = List.generate(12, (i) => DateTime(_year, i + 1));
    return [
      _yearBar(),
      const SizedBox(height: 12),
      _yearSummaryCard(income, expense),
      const SizedBox(height: 16),
      _sectionTitle('これまでの累計'),
      const SizedBox(height: 8),
      _lifetimeCard(all),
      const SizedBox(height: 20),
      _sectionTitle('月別の収支（$_year年）'),
      const SizedBox(height: 8),
      _trendCard(all, months, compact: true),
      const SizedBox(height: 20),
      _sectionTitle('$_year年の支出内訳'),
      const SizedBox(height: 8),
      _pieCard(_byCat(all, _year, null), '$_year年の支出はまだないよ'),
      const SizedBox(height: 16),
      _sectionTitle('カテゴリ別（タップで1年の推移）'),
      const SizedBox(height: 8),
      _categoryCard(context, _byCat(all, _year, null), '$_year年の支出はまだないよ'),
    ];
  }

  /// 年の切替バー。
  Widget _yearBar() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => setState(() => _year--)),
          Text('$_year年',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
          IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => setState(() => _year++)),
        ],
      );

  /// その年の「貯まった分（収入−支出）」と、1年の総収入・総支出。
  Widget _yearSummaryCard(int income, int expense) {
    final diff = income - expense;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6FD0F5), Color(0xFF1E9FD9)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: AppColors.pink.withValues(alpha: 0.3),
              blurRadius: 18,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Text('$_year年に貯まった分',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text('${diff >= 0 ? '+' : ''}${formatYen(diff)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _whiteStat('1年の収入', income)),
              Container(width: 1, height: 34, color: Colors.white24),
              Expanded(child: _whiteStat('1年の支出', expense)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _whiteStat(String label, int value) => Column(
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 2),
          Text(formatYen(value),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
        ],
      );

  /// 記録し始めてからの累計（収入−支出）＝ためた合計。
  Widget _lifetimeCard(List<core.Transaction> all) {
    var income = 0, expense = 0;
    DateTime? first;
    for (final t in all) {
      if (t.type == core.TransactionType.income) {
        income += t.amount;
      } else if (t.type == core.TransactionType.expense) {
        expense += t.amount;
      } else {
        continue;
      }
      if (first == null || t.date.isBefore(first)) first = t.date;
    }
    final diff = income - expense;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.pinkSoft, width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.savings_rounded,
                  size: 26, color: AppColors.pinkDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ためた合計（収入−支出）',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text)),
                    Text(
                        first == null
                            ? '記録がまだないよ'
                            : '${first.year}年${first.month}月から今まで',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSub)),
                  ],
                ),
              ),
              Text('${diff >= 0 ? '+' : ''}${formatYen(diff)}',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: diff >= 0 ? AppColors.income : AppColors.expense)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _smallStat('ぜんぶの収入', income, AppColors.income)),
              Expanded(
                  child: _smallStat('ぜんぶの支出', expense, AppColors.expense)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallStat(String label, int value, Color color) => Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
          const SizedBox(height: 2),
          Text(formatYen(value),
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        ],
      );

  // ── 収支の棒グラフ（月モードは6本・年モードは12本）──────────

  /// 渡した月ぶんの収支を並べた棒グラフ。
  /// [compact] は12ヶ月ぶんを1画面に収めるための細めの表示。
  Widget _trendCard(List<core.Transaction> all, List<DateTime> months,
      {bool compact = false}) {
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
                    child: _monthColumn(
                        months[i], inc[i], exp[i], maxV, compact),
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

  Widget _monthColumn(
      DateTime m, int income, int expense, int maxV, bool compact) {
    const barArea = 96.0;
    double h(int v) => maxV == 0 ? 0 : (v / maxV) * barArea;
    final barWidth = compact ? 6.0 : 11.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(h(income), AppColors.income, barWidth),
            SizedBox(width: compact ? 2 : 3),
            _bar(h(expense), AppColors.expense, barWidth),
          ],
        ),
        const SizedBox(height: 6),
        Text('${m.month}月',
            style: TextStyle(
                fontSize: compact ? 9 : 10, color: AppColors.textSub)),
      ],
    );
  }

  Widget _bar(double height, Color color, double width) {
    return Container(
      width: width,
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

  // ── カテゴリ内訳（円グラフ／一覧）───────────────────────────

  /// 支出カテゴリ内訳の円グラフ。
  Widget _pieCard(List<MapEntry<String, int>> entries, String emptyText) {
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
        child: Text(emptyText,
            style: const TextStyle(color: AppColors.textSub, fontSize: 12)),
      );
    }
    // 上位6カテゴリ＋残りを「その他」にまとめてスライス化。
    final top = entries.take(6).toList();
    final restSum = entries.skip(6).fold<int>(0, (s, e) => s + e.value);
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

  /// エンゲル係数カード（食料費 ÷ 支出合計）。食料費＝「食費」＋「外食」。
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
          colors: [Color(0xFFDDF3FD), Color(0xFFEFF9FE)],
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

  /// カテゴリ別支出を金額の多い順で返す。
  /// [month] に null を渡すとその年ぜんぶ（＝年集計）。
  List<MapEntry<String, int>> _byCat(
      List<core.Transaction> all, int year, int? month) {
    final byCat = <String, int>{};
    for (final t in all) {
      if (t.type != core.TransactionType.expense) continue;
      if (t.date.year != year) continue;
      if (month != null && t.date.month != month) continue;
      byCat[t.category.major] = (byCat[t.category.major] ?? 0) + t.amount;
    }
    return byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  Widget _categoryCard(BuildContext context,
      List<MapEntry<String, int>> entries, String emptyText) {
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        alignment: Alignment.center,
        child: Text(emptyText,
            style: const TextStyle(color: AppColors.textSub, fontSize: 12)),
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

  Widget _catRow(BuildContext context, String name, int amount, int total) {
    final c = categoryFor(name, income: false);
    final ratio = total == 0 ? 0.0 : amount / total;
    final pct = (ratio * 100).round();
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CategoryTrendScreen(category: name)),
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
