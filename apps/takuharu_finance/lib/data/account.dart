import 'package:flutter/material.dart';
import 'package:finance_core/finance_core.dart' as core;

/// 口座・クレカの種別（アイコン/見た目用）。残高の扱いは全種別で共通（支出で減る）。
enum AccountType { bank, card, cash, emoney }

extension AccountTypeX on AccountType {
  String get label {
    switch (this) {
      case AccountType.bank:
        return '銀行';
      case AccountType.card:
        return 'クレカ';
      case AccountType.cash:
        return '現金';
      case AccountType.emoney:
        return '電子マネー';
    }
  }

  IconData get icon {
    switch (this) {
      case AccountType.bank:
        return Icons.account_balance_rounded;
      case AccountType.card:
        return Icons.credit_card_rounded;
      case AccountType.cash:
        return Icons.payments_rounded;
      case AccountType.emoney:
        return Icons.smartphone_rounded;
    }
  }
}

/// 口座・クレカ（残高を持つ支払元）。households/{hid}/accounts。
class Account {
  final String id;
  final String name;
  final AccountType type;

  /// 初期残高（登録時点の残高）。以後は収支で増減して現在残高を出す。
  final int initialBalance;
  final bool active;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.initialBalance = 0,
    this.active = true,
  });

  /// 取引リストからこの口座の現在残高を計算（名前一致で集計）。
  /// 支出は減算・収入は加算。振替は対象外。
  int balanceFrom(Iterable<core.Transaction> txns) {
    var b = initialBalance;
    for (final t in txns) {
      if (t.paymentMethod != name) continue;
      if (t.type == core.TransactionType.expense) {
        b -= t.amount;
      } else if (t.type == core.TransactionType.income) {
        b += t.amount;
      }
    }
    return b;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'initialBalance': initialBalance,
        'active': active,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        type: AccountType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => AccountType.bank,
        ),
        initialBalance: (j['initialBalance'] as num?)?.toInt() ?? 0,
        active: j['active'] as bool? ?? true,
      );

  Account copyWith({
    String? name,
    AccountType? type,
    int? initialBalance,
    bool? active,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        initialBalance: initialBalance ?? this.initialBalance,
        active: active ?? this.active,
      );
}
