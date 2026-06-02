import 'dart:convert';

/// 負債の種別。
enum LiabilityKind {
  loan, // 借入金（銀行借入・役員借入 等）
  payable, // 未払金・買掛金
  lease, // リース債務
  other, // その他
}

extension LiabilityKindX on LiabilityKind {
  String get label {
    switch (this) {
      case LiabilityKind.loan:
        return '借入金';
      case LiabilityKind.payable:
        return '未払金';
      case LiabilityKind.lease:
        return 'リース';
      case LiabilityKind.other:
        return 'その他';
    }
  }

  String get emoji {
    switch (this) {
      case LiabilityKind.loan:
        return '🏦';
      case LiabilityKind.payable:
        return '🧾';
      case LiabilityKind.lease:
        return '🚗';
      case LiabilityKind.other:
        return '📝';
    }
  }
}

/// 借入金・負債1件。BS（貸借対照表）の負債側に計上する。
/// [balance] は現在の残高（円）。資金繰り用に [monthlyRepayment] も任意で持つ。
class Liability {
  final String id;
  final String name;
  final LiabilityKind kind;

  /// 現在残高（円）。BS の負債合計に算入される。
  final int balance;

  /// 借入先（任意。例: "○○銀行", "代表者"）。
  final String? lender;

  /// 年利（％, 任意）。
  final double? interestRate;

  /// 毎月の返済額（円, 任意）。将来の資金繰り表で使用。
  final int? monthlyRepayment;

  final String? note;

  const Liability({
    required this.id,
    required this.name,
    required this.kind,
    required this.balance,
    this.lender,
    this.interestRate,
    this.monthlyRepayment,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'balance': balance,
        'lender': lender,
        'interestRate': interestRate,
        'monthlyRepayment': monthlyRepayment,
        'note': note,
      };

  factory Liability.fromJson(Map<String, dynamic> j) => Liability(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: LiabilityKind.values.firstWhere(
          (k) => k.name == (j['kind'] as String? ?? 'loan'),
          orElse: () => LiabilityKind.loan,
        ),
        balance: (j['balance'] as num?)?.toInt() ?? 0,
        lender: j['lender'] as String?,
        interestRate: (j['interestRate'] as num?)?.toDouble(),
        monthlyRepayment: (j['monthlyRepayment'] as num?)?.toInt(),
        note: j['note'] as String?,
      );

  Liability copyWith({
    String? name,
    LiabilityKind? kind,
    int? balance,
    String? lender,
    bool clearLender = false,
    double? interestRate,
    bool clearInterestRate = false,
    int? monthlyRepayment,
    bool clearMonthlyRepayment = false,
    String? note,
    bool clearNote = false,
  }) =>
      Liability(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        balance: balance ?? this.balance,
        lender: clearLender ? null : (lender ?? this.lender),
        interestRate:
            clearInterestRate ? null : (interestRate ?? this.interestRate),
        monthlyRepayment: clearMonthlyRepayment
            ? null
            : (monthlyRepayment ?? this.monthlyRepayment),
        note: clearNote ? null : (note ?? this.note),
      );
}

/// Liability の集合。永続化単位。
class LiabilitiesConfig {
  final List<Liability> items;

  const LiabilitiesConfig({required this.items});

  factory LiabilitiesConfig.empty() => const LiabilitiesConfig(items: []);

  /// 負債残高の合計（円）。
  int get totalBalance => items.fold<int>(0, (s, i) => s + i.balance);

  /// 毎月の返済額の合計（円）。資金繰り用。
  int get monthlyRepaymentTotal =>
      items.fold<int>(0, (s, i) => s + (i.monthlyRepayment ?? 0));

  String toJsonString() =>
      jsonEncode({'items': items.map((i) => i.toJson()).toList()});

  factory LiabilitiesConfig.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return LiabilitiesConfig(
      items: (json['items'] as List)
          .map((i) => Liability.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}
