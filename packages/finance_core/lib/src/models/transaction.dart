import 'category.dart';

/// 1件の取引（収支記録）。
class Transaction {
  final String id;

  /// 取引日。
  final DateTime date;

  /// カテゴリ（大/小）。
  final Category category;

  /// 支払方法（例: "三井住友カード", "銀行引落"）。
  final String paymentMethod;

  /// 取引内容（例: "ChatGPT", "Claude Pro"）。
  final String description;

  /// 金額（円、税込）。支出はプラス値で表現する。
  final int amount;

  /// 領収書画像 URL（Firebase Storage パス or 外部リンク）。
  final String? receiptUrl;

  /// 備考（例: "毎月X日計上"）。
  final String? memo;

  const Transaction({
    required this.id,
    required this.date,
    required this.category,
    required this.paymentMethod,
    required this.description,
    required this.amount,
    this.receiptUrl,
    this.memo,
  });
}
