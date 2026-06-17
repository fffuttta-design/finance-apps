import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart';

import '../../data/app_mode.dart';
import '../../data/subscription_repository.dart';
import '../../data/transaction_repository.dart';
import '../../utils/formatters.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// 新デザイン（リッチUI）の業績／集計タブ。
///
/// 既存の PL 月次表（V2ReportScreen）には手を入れず、トグルで切替える独立画面。
/// ダッシュボード型: 売上/経費/利益のKPI → 月別の利益推移 → 支出カテゴリ内訳。
class RichReportScreen extends StatefulWidget {
  final Color accent;
  const RichReportScreen({super.key, required this.accent});

  @override
  State<RichReportScreen> createState() => _RichReportScreenState();
}

class _RichReportScreenState extends State<RichReportScreen>
    with ModeAwareMixin {
  final _txRepo = TransactionRepository.instance;

  StreamSubscription<List<Transaction>>? _sub;
  List<Transaction> _transactions = [];
  List<Subscription> _subs = [];
  bool _loading = true;

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void onModeChanged() => _load();

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _txRepo.stream.listen((list) {
      if (!mounted) return;
      setState(() => _transactions = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await (() async {
        final txns = await _txRepo.loadAll();
        final subs = await SubscriptionRepository.instance.load();
        return (txns, subs);
      })()
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _transactions = data.$1;
        _subs = data.$2.subscriptions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  int _incomeOf(DateTime m) => _transactions
      .where((t) =>
          t.type == TransactionType.income &&
          t.date.year == m.year &&
          t.date.month == m.month)
      .fold<int>(0, (s, t) => s + t.amount);

  int _subsOf(DateTime m) {
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    return _subs.fold<int>(0, (s, sub) => s + sub.plAmountForMonth(ym, curYm));
  }

  int _expenseOf(DateTime m) {
    final tx = _transactions
        .where((t) =>
            t.type == TransactionType.expense &&
            t.date.year == m.year &&
            t.date.month == m.month)
        .fold<int>(0, (s, t) => s + t.amount);
    return tx + _subsOf(m);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final isBusiness = AppModeManager.instance.current == AppMode.business;
    final accent = widget.accent;

    final income = _incomeOf(_month);
    final expense = _expenseOf(_month);
    final profit = income - expense;

    // 直近6ヶ月（_month を末尾に）の収支推移。
    final months = <DateTime>[
      for (int i = 5; i >= 0; i--)
        DateTime(_month.year, _month.month - i),
    ];
    final trend = [
      for (final m in months)
        (month: m, income: _incomeOf(m), expense: _expenseOf(m)),
    ];

    // 支出カテゴリ内訳（当月・大カテゴリ別・固定費込み）。
    final byMajor = <String, int>{};
    for (final t in _transactions) {
      if (t.type != TransactionType.expense) continue;
      if (t.date.year != _month.year || t.date.month != _month.month) continue;
      final major =
          t.category.major.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
      if (major.isEmpty) continue;
      byMajor[major] = (byMajor[major] ?? 0) + t.amount;
    }
    final subTotal = _subsOf(_month);
    if (subTotal > 0) {
      byMajor['固定費・サブスク'] = (byMajor['固定費・サブスク'] ?? 0) + subTotal;
    }
    final majorEntries = byMajor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final byMajorTotal = byMajor.values.fold<int>(0, (s, v) => s + v);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          vertical: V2Spacing.xl, horizontal: V2Spacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 月切替ヘッダー
              Row(
                children: [
                  Text(isBusiness ? '業績' : '集計',
                      style: V2Typography.h1
                          .copyWith(color: V2Colors.textPrimary)),
                  const Spacer(),
                  _MonthStepper(
                    label: '${_month.year}年${_month.month}月',
                    onPrev: () => _shiftMonth(-1),
                    onNext: () => _shiftMonth(1),
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.lg),
              // KPI 3枚
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: isBusiness ? '当月売上' : '当月収入',
                      value: formatYen(income),
                      valueColor: V2Colors.textPrimary,
                      accentBar: V2Colors.positive,
                    ),
                  ),
                  const SizedBox(width: V2Spacing.md),
                  Expanded(
                    child: _MetricCard(
                      label: isBusiness ? '当月経費' : '当月支出',
                      value: formatYen(expense),
                      valueColor: V2Colors.textPrimary,
                      accentBar: V2Colors.negative,
                    ),
                  ),
                  const SizedBox(width: V2Spacing.md),
                  Expanded(
                    child: _MetricCard(
                      label: isBusiness ? '当月利益' : '当月収支',
                      value: formatYen(profit, withSign: true),
                      valueColor: profit >= 0
                          ? V2Colors.positive
                          : V2Colors.negative,
                      accentBar: accent,
                      highlight: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.lg),
              // 月別収支推移
              _Panel(
                title: '月別の収支推移',
                trailing: const _LegendDots(),
                child: _TrendChart(trend: trend),
              ),
              const SizedBox(height: V2Spacing.lg),
              // カテゴリ内訳
              _Panel(
                title: isBusiness ? '経費カテゴリ内訳' : '支出カテゴリ内訳',
                child: majorEntries.isEmpty || byMajorTotal == 0
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('この月の支出はまだありません',
                            style: V2Typography.caption
                                .copyWith(color: V2Colors.textSecondary)),
                      )
                    : Column(
                        children: [
                          for (final e in majorEntries.take(8))
                            _CategoryBar(
                              name: e.key,
                              value: e.value,
                              ratio: e.value / byMajorTotal,
                              accent: accent,
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthStepper extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _MonthStepper(
      {required this.label, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: V2Colors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: const Icon(Icons.chevron_left,
                color: V2Colors.textSecondary),
            onPressed: onPrev,
          ),
          Text(label,
              style: V2Typography.bodyStrong
                  .copyWith(color: V2Colors.textPrimary)),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: const Icon(Icons.chevron_right,
                color: V2Colors.textSecondary),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color accentBar;
  final bool highlight;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.accentBar,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.lg),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: highlight ? accentBar.withValues(alpha: 0.45) : V2Colors.border,
            width: highlight ? 1.4 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: accentBar,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: V2Typography.caption
                        .copyWith(color: V2Colors.textSecondary),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                    fontFeatures: V2Typography.tabularNums)),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  const _Panel({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.lg),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: V2Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(title,
                  style:
                      V2Typography.h2.copyWith(color: V2Colors.textPrimary)),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: V2Spacing.lg),
          child,
        ],
      ),
    );
  }
}

class _LegendDots extends StatelessWidget {
  const _LegendDots();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 5),
            Text(label,
                style: V2Typography.micro
                    .copyWith(color: V2Colors.textSecondary)),
          ],
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(V2Colors.positive, '収入'),
        const SizedBox(width: 12),
        dot(V2Colors.negative, '支出'),
      ],
    );
  }
}

/// 月別の収入/支出グループ棒グラフ（チャートライブラリ不使用・自前）。
class _TrendChart extends StatelessWidget {
  final List<({DateTime month, int income, int expense})> trend;
  const _TrendChart({required this.trend});

  @override
  Widget build(BuildContext context) {
    final maxVal = trend.fold<int>(1, (m, e) {
      final hi = e.income > e.expense ? e.income : e.expense;
      return hi > m ? hi : m;
    });
    const chartH = 130.0;
    return SizedBox(
      height: chartH + 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in trend)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: chartH,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _bar(e.income / maxVal, chartH, V2Colors.positive),
                        const SizedBox(width: 4),
                        _bar(e.expense / maxVal, chartH, V2Colors.negative),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${e.month.month}月',
                      style: V2Typography.micro
                          .copyWith(color: V2Colors.textSecondary)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(double ratio, double maxH, Color color) {
    final h = (ratio.clamp(0.0, 1.0)) * maxH;
    return Container(
      width: 12,
      height: h < 3 ? 3 : h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String name;
  final int value;
  final double ratio;
  final Color accent;
  const _CategoryBar({
    required this.name,
    required this.value,
    required this.ratio,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: V2Typography.body, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text('${(ratio * 100).round()}%',
                  style: V2Typography.micro
                      .copyWith(color: V2Colors.textMuted)),
              const SizedBox(width: 10),
              Text(formatYen(value),
                  style: V2Typography.caption.copyWith(
                      color: V2Colors.textSecondary,
                      fontFeatures: V2Typography.tabularNums)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: V2Colors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ],
      ),
    );
  }
}
