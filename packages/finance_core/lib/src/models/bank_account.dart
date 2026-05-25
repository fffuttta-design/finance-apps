import 'dart:convert';

/// 銀行口座の登録情報（ユーザー設定）。
class RegisteredBankAccount {
  final String id;
  final String name;

  /// 口座番号下4桁（プライバシー配慮で末尾のみ）。
  final String? last4;

  /// 開始時残高（円）。任意。
  final int? startingBalance;

  const RegisteredBankAccount({
    required this.id,
    required this.name,
    this.last4,
    this.startingBalance,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'last4': last4,
        'startingBalance': startingBalance,
      };

  factory RegisteredBankAccount.fromJson(Map<String, dynamic> j) =>
      RegisteredBankAccount(
        id: j['id'] as String,
        name: j['name'] as String,
        last4: j['last4'] as String?,
        startingBalance: j['startingBalance'] as int?,
      );

  RegisteredBankAccount copyWith({
    String? name,
    String? last4,
    int? startingBalance,
  }) =>
      RegisteredBankAccount(
        id: id,
        name: name ?? this.name,
        last4: last4 ?? this.last4,
        startingBalance: startingBalance ?? this.startingBalance,
      );
}

/// クレジットカードの登録情報。
class RegisteredCreditCard {
  final String id;
  final String name;

  /// カード番号下4桁。
  final String? last4;

  /// ブランドカラー（HEX値、UIで色分け表示するため）。
  final int? brandColorValue;

  const RegisteredCreditCard({
    required this.id,
    required this.name,
    this.last4,
    this.brandColorValue,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'last4': last4,
        'brandColorValue': brandColorValue,
      };

  factory RegisteredCreditCard.fromJson(Map<String, dynamic> j) =>
      RegisteredCreditCard(
        id: j['id'] as String,
        name: j['name'] as String,
        last4: j['last4'] as String?,
        brandColorValue: j['brandColorValue'] as int?,
      );

  RegisteredCreditCard copyWith({
    String? name,
    String? last4,
    int? brandColorValue,
  }) =>
      RegisteredCreditCard(
        id: id,
        name: name ?? this.name,
        last4: last4 ?? this.last4,
        brandColorValue: brandColorValue ?? this.brandColorValue,
      );
}

/// 銀行口座・クレジットカードのまとまった設定。
class PaymentMethodsConfig {
  final List<RegisteredBankAccount> bankAccounts;
  final List<RegisteredCreditCard> creditCards;

  const PaymentMethodsConfig({
    required this.bankAccounts,
    required this.creditCards,
  });

  factory PaymentMethodsConfig.empty() =>
      const PaymentMethodsConfig(bankAccounts: [], creditCards: []);

  String toJsonString() => jsonEncode({
        'bankAccounts': bankAccounts.map((b) => b.toJson()).toList(),
        'creditCards': creditCards.map((c) => c.toJson()).toList(),
      });

  factory PaymentMethodsConfig.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return PaymentMethodsConfig(
      bankAccounts: (json['bankAccounts'] as List)
          .map((b) =>
              RegisteredBankAccount.fromJson(b as Map<String, dynamic>))
          .toList(),
      creditCards: (json['creditCards'] as List)
          .map((c) =>
              RegisteredCreditCard.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  PaymentMethodsConfig copyWith({
    List<RegisteredBankAccount>? bankAccounts,
    List<RegisteredCreditCard>? creditCards,
  }) =>
      PaymentMethodsConfig(
        bankAccounts: bankAccounts ?? this.bankAccounts,
        creditCards: creditCards ?? this.creditCards,
      );
}
