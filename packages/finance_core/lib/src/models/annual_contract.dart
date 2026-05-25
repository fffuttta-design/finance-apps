/// 年単位で請求される固定費契約。月次集計には混ぜず、別管理する。
class AnnualContract {
  final String id;
  final String name;
  final int amount;

  /// 次回請求予定日（不明なら null）。
  final DateTime? nextChargeDate;

  /// 備考。
  final String? memo;

  const AnnualContract({
    required this.id,
    required this.name,
    required this.amount,
    this.nextChargeDate,
    this.memo,
  });

  /// 次回請求日まで残り何日か。nextChargeDateがnullなら null を返す。
  int? daysUntilCharge(DateTime today) {
    final next = nextChargeDate;
    if (next == null) return null;
    return next.difference(DateTime(today.year, today.month, today.day)).inDays;
  }
}
