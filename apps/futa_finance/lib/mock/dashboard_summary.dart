import 'package:finance_core/finance_core.dart';

/// ダッシュボード表示用の集計結果。モックデータから算出される。
class DashboardSummary {
  final Account account;
  final List<Transaction> transactions;
  final List<AnnualContract> annualContracts;
  final DateTime today;

  DashboardSummary({
    required this.account,
    required this.transactions,
    required this.annualContracts,
    required this.today,
  });

  /// 当月の総支出。
  int get monthTotal =>
      transactions.fold(0, (sum, t) => sum + t.amount);

  /// 月末想定残高（現時点の支出を引いた値）。
  int get projectedRemaining => account.monthStartBalance - monthTotal;

  /// 月の日数。
  int get daysInMonth => DateTime(today.year, today.month + 1, 0).day;

  /// 月の経過日数（今日を含む）。
  int get daysElapsed => today.day;

  /// 月の経過比率（0.0〜1.0）。
  double get monthProgress => daysElapsed / daysInMonth;

  /// このペースで行った場合の月末支出予測。
  int get paceProjection {
    if (daysElapsed == 0) return 0;
    return (monthTotal / daysElapsed * daysInMonth).round();
  }

  /// このペースで行った場合の月末残高予測。
  int get monthEndProjectedBalance =>
      account.monthStartBalance - paceProjection;

  /// 大カテゴリ別の小計。
  Map<String, int> get totalByMajor {
    final result = <String, int>{};
    for (final major in FutaCategories.allMajor) {
      result[major] = 0;
    }
    for (final t in transactions) {
      result[t.category.major] = (result[t.category.major] ?? 0) + t.amount;
    }
    return result;
  }

  /// 直近の取引（新しい順）。
  List<Transaction> recentTransactions({int limit = 5}) {
    final sorted = [...transactions];
    sorted.sort((a, b) => b.date.compareTo(a.date));
    return sorted.take(limit).toList();
  }
}
