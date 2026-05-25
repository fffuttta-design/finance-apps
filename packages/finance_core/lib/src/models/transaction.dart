import 'category.dart';

/// 取引種別。
enum TransactionType {
  /// 支出（経費・購入など）。
  expense,

  /// 収入（売上・入金など）。
  income,
}

/// 1件の取引（収支記録）。
class Transaction {
  final String id;

  /// 取引日。
  final DateTime date;

  /// 取引種別。
  final TransactionType type;

  /// カテゴリ（大/小）。支出と収入の両方で使う。
  final Category category;

  /// 支払方法／受取方法（例: "三井住友カード", "銀行引落", "住信SBI入金"）。
  final String paymentMethod;

  /// 取引内容（例: "ChatGPT", "Aクライアント請求"）。
  final String description;

  /// 金額（円、税込）。常に正の値。typeで符号扱いを決める。
  final int amount;

  /// 領収書画像 URL（Firebase Storage パス or 外部リンク）。
  final String? receiptUrl;

  /// 備考。
  final String? memo;

  /// この取引が紐づく収入マスタID（収入時のみ）。
  final String? incomeSourceId;

  const Transaction({
    required this.id,
    required this.date,
    required this.type,
    required this.category,
    required this.paymentMethod,
    required this.description,
    required this.amount,
    this.receiptUrl,
    this.memo,
    this.incomeSourceId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'type': type.name,
        'categoryMajor': category.major,
        'categorySub': category.sub,
        'paymentMethod': paymentMethod,
        'description': description,
        'amount': amount,
        'receiptUrl': receiptUrl,
        'memo': memo,
        'incomeSourceId': incomeSourceId,
      };

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        type: TransactionType.values.firstWhere(
          (t) => t.name == (j['type'] as String? ?? 'expense'),
          orElse: () => TransactionType.expense,
        ),
        category: Category(
          major: j['categoryMajor'] as String,
          sub: j['categorySub'] as String,
        ),
        paymentMethod: j['paymentMethod'] as String,
        description: j['description'] as String,
        amount: j['amount'] as int,
        receiptUrl: j['receiptUrl'] as String?,
        memo: j['memo'] as String?,
        incomeSourceId: j['incomeSourceId'] as String?,
      );

  Transaction copyWith({
    DateTime? date,
    TransactionType? type,
    Category? category,
    String? paymentMethod,
    String? description,
    int? amount,
    String? receiptUrl,
    String? memo,
    String? incomeSourceId,
  }) =>
      Transaction(
        id: id,
        date: date ?? this.date,
        type: type ?? this.type,
        category: category ?? this.category,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        receiptUrl: receiptUrl ?? this.receiptUrl,
        memo: memo ?? this.memo,
        incomeSourceId: incomeSourceId ?? this.incomeSourceId,
      );
}
