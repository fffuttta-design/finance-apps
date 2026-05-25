import 'dart:async';

import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

import '../data/transaction_repository.dart';
import '../mock/dashboard_summary.dart';
import '../mock/mock_data.dart';
import '../widgets/category_heat_grid.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _repo = TransactionRepository.instance;
  StreamSubscription<List<core.Transaction>>? _sub;
  List<core.Transaction> _transactions = [];

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _repo.stream.listen((list) {
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
    final list = await _repo.loadAll();
    if (!mounted) return;
    setState(() => _transactions = list);
  }

  /// 過去6ヶ月分の月次サマリ。
  List<_MonthSummary> get _last6Months {
    final now = DateTime.now();
    final result = <_MonthSummary>[];
    for (int i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i);
      final txns = _transactions
          .where((t) => t.date.year == m.year && t.date.month == m.month);
      final income = txns
          .where((t) => t.type == core.TransactionType.income)
          .fold(0, (s, t) => s + t.amount);
      final expense = txns
          .where((t) => t.type == core.TransactionType.expense)
          .fold(0, (s, t) => s + t.amount);
      result.add(_MonthSummary(month: m, income: income, expense: expense));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final monthly = _last6Months;
    final maxAmount = monthly.fold<int>(0, (m, s) {
      final v = s.income > s.expense ? s.income : s.expense;
      return v > m ? v : m;
    });

    // CategoryHeatGrid 用に DashboardSummary を構築（残高情報は不要なので0でOK）
    final today = DateTime.now();
    final summary = DashboardSummary(
      today: today,
      allTransactions: _transactions,
      monthStartBalance: 0,
      accountName: '',
      annualContracts: MockData.annualContracts,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'レポート',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827)),
        ),
      ),
      body: SafeArea(
        child: _transactions.isEmpty
            ? _empty()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 過去6ヶ月の収支トレンド
                  _card(
                    title: '過去6ヶ月の収支',
                    icon: Icons.timeline,
                    child: SizedBox(
                      height: 160,
                      child: _MonthlyBarChart(
                          months: monthly, maxAmount: maxAmount),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // カテゴリ別集計（移管: ホーム → ここ）
                  CategoryHeatGrid(summary: summary),
                ],
              ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.bar_chart, size: 72, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Text('まだ取引がありません',
                style: TextStyle(fontSize: 16, color: Color(0xFF6B7280))),
            SizedBox(height: 4),
            Text('取引を記録するとレポートが表示されます',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          ],
        ),
      );

  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF1A237E)),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MonthSummary {
  final DateTime month;
  final int income;
  final int expense;
  _MonthSummary(
      {required this.month, required this.income, required this.expense});
}

/// シンプルな月別収支棒グラフ（外部パッケージなし）。
class _MonthlyBarChart extends StatelessWidget {
  final List<_MonthSummary> months;
  final int maxAmount;

  const _MonthlyBarChart({required this.months, required this.maxAmount});

  @override
  Widget build(BuildContext context) {
    if (maxAmount == 0) {
      return const Center(
        child: Text('データなし',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: months.map((m) {
        final inH = (m.income / maxAmount) * 120;
        final exH = (m.expense / maxAmount) * 120;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 10,
                      height: inH.clamp(2, 120),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2)),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      width: 10,
                      height: exH.clamp(2, 120),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${m.month.month}月',
                    style: const TextStyle(
                        fontSize: 9, color: Color(0xFF6B7280))),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
