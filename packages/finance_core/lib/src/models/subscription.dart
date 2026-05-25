import 'dart:convert';

/// サブスクリプションの請求サイクル。
enum SubscriptionCycle {
  /// 月払い。
  monthly,

  /// 年払い。
  annually,
}

/// サブスクリプションの登録情報。
///
/// 月払い/年払いの継続課金を一覧管理し、次回請求日や合計コストを把握する。
class Subscription {
  final String id;
  final String name;

  /// 1回の請求金額（円）。
  final int amount;

  /// 請求サイクル。
  final SubscriptionCycle cycle;

  /// 月払いの場合の請求日（1〜31）。年払いでは未使用。
  final int? billingDay;

  /// 年払いの場合の次回請求日。月払いでは未使用（任意で「次回予定」として使ってもOK）。
  final DateTime? nextBillingDate;

  /// 支払方法（任意。例: "三井住友カード"）。
  final String? paymentMethod;

  /// 備考。
  final String? memo;

  const Subscription({
    required this.id,
    required this.name,
    required this.amount,
    required this.cycle,
    this.billingDay,
    this.nextBillingDate,
    this.paymentMethod,
    this.memo,
  });

  /// サイクル表示名。
  String get cycleLabel =>
      cycle == SubscriptionCycle.monthly ? '月払い' : '年払い';

  /// 月あたり換算金額（年払いは ÷12）。
  int get monthlyEquivalent =>
      cycle == SubscriptionCycle.monthly ? amount : (amount / 12).round();

  /// 年あたり換算金額（月払いは ×12）。
  int get annualEquivalent =>
      cycle == SubscriptionCycle.monthly ? amount * 12 : amount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'cycle': cycle.name,
        'billingDay': billingDay,
        'nextBillingDate': nextBillingDate?.toIso8601String(),
        'paymentMethod': paymentMethod,
        'memo': memo,
      };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'] as String,
        name: j['name'] as String,
        amount: j['amount'] as int,
        cycle: SubscriptionCycle.values.firstWhere(
          (c) => c.name == (j['cycle'] as String? ?? 'monthly'),
          orElse: () => SubscriptionCycle.monthly,
        ),
        billingDay: j['billingDay'] as int?,
        nextBillingDate: j['nextBillingDate'] == null
            ? null
            : DateTime.parse(j['nextBillingDate'] as String),
        paymentMethod: j['paymentMethod'] as String?,
        memo: j['memo'] as String?,
      );

  Subscription copyWith({
    String? name,
    int? amount,
    SubscriptionCycle? cycle,
    int? billingDay,
    DateTime? nextBillingDate,
    String? paymentMethod,
    String? memo,
  }) =>
      Subscription(
        id: id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        cycle: cycle ?? this.cycle,
        billingDay: billingDay ?? this.billingDay,
        nextBillingDate: nextBillingDate ?? this.nextBillingDate,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        memo: memo ?? this.memo,
      );
}

/// サブスクリプションの一覧（永続化用）。
class SubscriptionConfig {
  final List<Subscription> subscriptions;

  const SubscriptionConfig({required this.subscriptions});

  factory SubscriptionConfig.empty() =>
      const SubscriptionConfig(subscriptions: []);

  /// 月払いの合計（月あたり）。
  int get monthlyTotal => subscriptions
      .where((s) => s.cycle == SubscriptionCycle.monthly)
      .fold(0, (sum, s) => sum + s.amount);

  /// 年払いの合計（年あたり）。
  int get annualTotal => subscriptions
      .where((s) => s.cycle == SubscriptionCycle.annually)
      .fold(0, (sum, s) => sum + s.amount);

  /// 年間総コスト（月払い×12 + 年払い）。
  int get totalAnnualCost => subscriptions.fold(
      0, (sum, s) => sum + s.annualEquivalent);

  String toJsonString() => jsonEncode({
        'subscriptions':
            subscriptions.map((s) => s.toJson()).toList(),
      });

  factory SubscriptionConfig.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return SubscriptionConfig(
      subscriptions: (json['subscriptions'] as List)
          .map((s) => Subscription.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  SubscriptionConfig copyWith({List<Subscription>? subscriptions}) =>
      SubscriptionConfig(subscriptions: subscriptions ?? this.subscriptions);
}
