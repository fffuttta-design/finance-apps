import 'dart:convert';

/// 予算項目の種別。
enum BudgetKind {
  tax, // 税金
  insurance, // 保険料
  pension, // 年金
  other, // その他（年会費・契約料 等）
}

extension BudgetKindX on BudgetKind {
  String get label {
    switch (this) {
      case BudgetKind.tax:
        return '税金';
      case BudgetKind.insurance:
        return '保険料';
      case BudgetKind.pension:
        return '年金';
      case BudgetKind.other:
        return 'その他';
    }
  }

  String get emoji {
    switch (this) {
      case BudgetKind.tax:
        return '📋';
      case BudgetKind.insurance:
        return '🛡️';
      case BudgetKind.pension:
        return '👴';
      case BudgetKind.other:
        return '📝';
    }
  }
}

/// 予算の支払スケジュール。1回分の支払予定。
/// 月日のみ持ち、年は持たない（毎年同じ月日に繰り返す前提）。
class ScheduledPayment {
  final int month; // 1-12
  final int day; // 1-31
  final int amount; // 円

  const ScheduledPayment({
    required this.month,
    required this.day,
    required this.amount,
  });

  Map<String, dynamic> toJson() =>
      {'month': month, 'day': day, 'amount': amount};

  factory ScheduledPayment.fromJson(Map<String, dynamic> j) =>
      ScheduledPayment(
        month: j['month'] as int,
        day: j['day'] as int,
        amount: j['amount'] as int,
      );

  /// 指定年で次の支払予定日を返す。
  DateTime nextDateFrom(DateTime now) {
    var y = now.year;
    var date = DateTime(y, month, day);
    if (date.isBefore(DateTime(now.year, now.month, now.day))) {
      // 今年の該当日が過ぎていれば来年扱い
      y++;
      date = DateTime(y, month, day);
    }
    return date;
  }
}

/// 1回分の実績支払い記録（予定に対して実際に払ったマーク）。
class ActualPayment {
  final DateTime date;
  final int amount;
  final String? note;

  const ActualPayment({
    required this.date,
    required this.amount,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'amount': amount,
        'note': note,
      };

  factory ActualPayment.fromJson(Map<String, dynamic> j) => ActualPayment(
        date: DateTime.parse(j['date'] as String),
        amount: j['amount'] as int,
        note: j['note'] as String?,
      );
}

/// 予算項目（税金/保険料/年金など）。
/// 年額は schedule の合計から自動算出。
class BudgetItem {
  final String id;
  final String name;
  final BudgetKind kind;
  final List<ScheduledPayment> schedule;
  final List<ActualPayment> actuals;
  final String? note;

  const BudgetItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.schedule,
    this.actuals = const [],
    this.note,
  });

  /// 年額（schedule の合計）
  int get annualAmount =>
      schedule.fold<int>(0, (s, p) => s + p.amount);

  /// 実績合計（今年度に限定したい場合は filter を渡す）
  int actualTotal({int? year}) {
    if (year == null) {
      return actuals.fold<int>(0, (s, a) => s + a.amount);
    }
    return actuals
        .where((a) => a.date.year == year)
        .fold<int>(0, (s, a) => s + a.amount);
  }

  /// 今年度の達成率（0.0 〜 1.0+）
  double progress({int? year}) {
    if (annualAmount == 0) return 0;
    return actualTotal(year: year) / annualAmount;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'schedule': schedule.map((p) => p.toJson()).toList(),
        'actuals': actuals.map((a) => a.toJson()).toList(),
        'note': note,
      };

  factory BudgetItem.fromJson(Map<String, dynamic> j) => BudgetItem(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: BudgetKind.values.firstWhere(
          (k) => k.name == (j['kind'] as String? ?? 'other'),
          orElse: () => BudgetKind.other,
        ),
        schedule: (j['schedule'] as List)
            .map((p) =>
                ScheduledPayment.fromJson(p as Map<String, dynamic>))
            .toList(),
        actuals: (j['actuals'] as List? ?? [])
            .map((a) => ActualPayment.fromJson(a as Map<String, dynamic>))
            .toList(),
        note: j['note'] as String?,
      );

  BudgetItem copyWith({
    String? name,
    BudgetKind? kind,
    List<ScheduledPayment>? schedule,
    List<ActualPayment>? actuals,
    String? note,
    bool clearNote = false,
  }) =>
      BudgetItem(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        schedule: schedule ?? this.schedule,
        actuals: actuals ?? this.actuals,
        note: clearNote ? null : (note ?? this.note),
      );
}

/// BudgetItem の集合。永続化単位。
class BudgetItemsConfig {
  final List<BudgetItem> items;

  const BudgetItemsConfig({required this.items});

  factory BudgetItemsConfig.empty() => const BudgetItemsConfig(items: []);

  String toJsonString() =>
      jsonEncode({'items': items.map((i) => i.toJson()).toList()});

  factory BudgetItemsConfig.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return BudgetItemsConfig(
      items: (json['items'] as List)
          .map((i) => BudgetItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}
