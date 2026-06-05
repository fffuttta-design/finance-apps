/// 固定費の頻度。
enum SubFrequency { monthly, yearly }

/// 固定費・サブスク（毎月/毎年の決まった支出）。
class Subscription {
  final String id;
  final String name;
  final int amount;
  final String category;
  final SubFrequency frequency;

  /// 毎年の場合の支払月（1-12）。毎月の場合は無視。
  final int? yearlyMonth;

  /// 支払日（1-31・任意）。
  final int? payDay;

  /// 誰が払うか（uid・任意）。
  final String? paidBy;

  /// 有効フラグ（false なら集計対象外・休止）。
  final bool active;

  const Subscription({
    required this.id,
    required this.name,
    required this.amount,
    required this.category,
    this.frequency = SubFrequency.monthly,
    this.yearlyMonth,
    this.payDay,
    this.paidBy,
    this.active = true,
  });

  /// 指定の年月に計上されるか。
  bool appliesTo(int year, int month) {
    if (!active) return false;
    if (frequency == SubFrequency.monthly) return true;
    return yearlyMonth == month;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'category': category,
        'frequency': frequency.name,
        'yearlyMonth': yearlyMonth,
        'payDay': payDay,
        'paidBy': paidBy,
        'active': active,
      };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        category: (j['category'] ?? 'その他') as String,
        frequency: SubFrequency.values.firstWhere(
          (f) => f.name == j['frequency'],
          orElse: () => SubFrequency.monthly,
        ),
        yearlyMonth: (j['yearlyMonth'] as num?)?.toInt(),
        payDay: (j['payDay'] as num?)?.toInt(),
        paidBy: j['paidBy'] as String?,
        active: j['active'] as bool? ?? true,
      );

  Subscription copyWith({
    String? name,
    int? amount,
    String? category,
    SubFrequency? frequency,
    int? yearlyMonth,
    int? payDay,
    String? paidBy,
    bool? active,
  }) =>
      Subscription(
        id: id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        category: category ?? this.category,
        frequency: frequency ?? this.frequency,
        yearlyMonth: yearlyMonth ?? this.yearlyMonth,
        payDay: payDay ?? this.payDay,
        paidBy: paidBy ?? this.paidBy,
        active: active ?? this.active,
      );
}
