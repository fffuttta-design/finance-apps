/// 検針票などの「使用量」メタ情報（水道・将来は電気/ガス）。
///
/// 金額の内訳は品目Transactionで表すので、ここは非金額のメタに絞る。
/// additive・後方互換のみ（既存データは usage 無しで普通に読める）。
class UsageDetail {
  /// 今回使用量（例 31）。
  final double? amount;

  /// 単位 'm3' / 'kWh'（水道は 'm3'）。
  final String unit;

  /// 前年同期の使用量（例 32）。無ければ null。
  final double? prevAmount;

  /// 使用期間 開始。
  final DateTime? periodFrom;

  /// 使用期間 終了。
  final DateTime? periodTo;

  /// 種別 'water'（将来 'electricity' / 'gas'）。
  final String kind;

  const UsageDetail({
    this.amount,
    this.unit = 'm3',
    this.prevAmount,
    this.periodFrom,
    this.periodTo,
    this.kind = 'water',
  });

  Map<String, dynamic> toJson() => {
        if (amount != null) 'amount': amount,
        'unit': unit,
        if (prevAmount != null) 'prevAmount': prevAmount,
        if (periodFrom != null) 'periodFrom': periodFrom!.toIso8601String(),
        if (periodTo != null) 'periodTo': periodTo!.toIso8601String(),
        'kind': kind,
      };

  factory UsageDetail.fromJson(Map<String, dynamic> j) => UsageDetail(
        amount: (j['amount'] as num?)?.toDouble(),
        unit: j['unit'] as String? ?? 'm3',
        prevAmount: (j['prevAmount'] as num?)?.toDouble(),
        periodFrom: j['periodFrom'] != null
            ? DateTime.tryParse(j['periodFrom'] as String)
            : null,
        periodTo: j['periodTo'] != null
            ? DateTime.tryParse(j['periodTo'] as String)
            : null,
        kind: j['kind'] as String? ?? 'water',
      );

  UsageDetail copyWith({
    double? amount,
    String? unit,
    double? prevAmount,
    DateTime? periodFrom,
    DateTime? periodTo,
    String? kind,
  }) =>
      UsageDetail(
        amount: amount ?? this.amount,
        unit: unit ?? this.unit,
        prevAmount: prevAmount ?? this.prevAmount,
        periodFrom: periodFrom ?? this.periodFrom,
        periodTo: periodTo ?? this.periodTo,
        kind: kind ?? this.kind,
      );
}
