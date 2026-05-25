import 'package:finance_core/finance_core.dart';

/// ダッシュボード表示用の集計結果。Transactionリストと残高情報から派生する。
class DashboardSummary {
  /// 表示中の年月。
  final DateTime today;

  /// 全取引（年月フィルタ前）。
  final List<Transaction> allTransactions;

  /// 月初時点の残高（円）。登録銀行口座の startingBalance を合算した値など。
  final int monthStartBalance;

  /// 表示する口座名（複数銀行ある場合は集計表示するなどの判断は呼び出し側で）。
  final String accountName;

  /// 年間払い契約。
  final List<AnnualContract> annualContracts;

  DashboardSummary({
    required this.today,
    required this.allTransactions,
    required this.monthStartBalance,
    required this.accountName,
    required this.annualContracts,
  });

  /// 当月の取引のみ。
  List<Transaction> get currentMonthTransactions {
    return allTransactions
        .where((t) => t.date.year == today.year && t.date.month == today.month)
        .toList();
  }

  /// 当月の支出合計（収入は含まない）。
  int get monthExpenseTotal => currentMonthTransactions
      .where((t) => t.type == TransactionType.expense)
      .fold(0, (sum, t) => sum + t.amount);

  /// 当月の収入合計。
  int get monthIncomeTotal => currentMonthTransactions
      .where((t) => t.type == TransactionType.income)
      .fold(0, (sum, t) => sum + t.amount);

  /// 月末想定残高（収支の差し引きを反映）。
  int get projectedRemaining =>
      monthStartBalance + monthIncomeTotal - monthExpenseTotal;

  /// 月の日数。
  int get daysInMonth => DateTime(today.year, today.month + 1, 0).day;

  /// 月の経過日数（今日を含む）。
  int get daysElapsed => today.day;

  /// 月の経過比率（0.0〜1.0）。
  double get monthProgress => daysElapsed / daysInMonth;

  /// 大カテゴリ別の支出小計。
  Map<String, int> get expenseByMajor {
    final result = <String, int>{};
    for (final major in FutaCategories.allMajor) {
      result[major] = 0;
    }
    for (final t in currentMonthTransactions
        .where((x) => x.type == TransactionType.expense)) {
      result[t.category.major] = (result[t.category.major] ?? 0) + t.amount;
    }
    return result;
  }

  /// 直近の取引（新しい順、上限指定）。
  List<Transaction> recentTransactions({int limit = 5}) {
    final sorted = [...allTransactions];
    sorted.sort((a, b) => b.date.compareTo(a.date));
    return sorted.take(limit).toList();
  }
}
