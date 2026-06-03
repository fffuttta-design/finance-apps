import 'dart:convert';

/// サブスクリプションの請求サイクル。
enum SubscriptionCycle {
  /// 月払い。
  monthly,

  /// 年払い。
  annually,
}

/// 金額の性質。
enum SubscriptionAmountType {
  /// 定額（毎回同じ金額。例: ChatGPT $20/月）
  fixed,

  /// 変動（月によって金額が変わる。例: 電気代）
  variable,
}

/// 固定費(継続課金)の登録情報。
///
/// 月払い/年払いの継続課金を一覧管理。金額タイプ(定額/変動)で振り分け。
/// 旧称はサブスクリプションだが、電気代などの変動費も含むため "固定費" として運用。
class Subscription {
  final String id;
  final String name;

  /// 1回の請求金額（円）。変動費の場合は目安額。
  final int amount;

  /// 請求サイクル。
  final SubscriptionCycle cycle;

  /// 金額の性質（定額 vs 変動）。デフォルトは fixed。
  final SubscriptionAmountType amountType;

  /// 月払いの場合の請求日（1〜31）。年払いでは未使用。
  final int? billingDay;

  /// 年払いの場合の次回請求日。月払いでは未使用（任意で「次回予定」として使ってもOK）。
  final DateTime? nextBillingDate;

  /// 支払方法（任意。例: "三井住友カード"）。
  final String? paymentMethod;

  /// 備考。
  final String? memo;

  /// ロゴ画像URL（任意）。中部電力/ChatGPT/Netflix等のサービスロゴ。
  final String? iconUrl;

  /// ユーザー定義カテゴリ（任意。例: "住居系", "娯楽系", "通信"）。
  /// 一覧画面のセクション分けに使用。null/空欄なら「未分類」扱い。
  final String? category;

  /// 紐づける会計科目（PL科目）。任意。例: "通信費", "賃借料", "水道光熱費"。
  /// 業績PLでこの科目に合算される（「固定費」自体は会計科目ではなく支払形態なので、
  /// 実体の科目をここで指定する）。null/空欄なら PL 未集計。
  /// 値は CategoryConfig の大カテゴリ名（番号プレフィックス無しの素の名前）。
  final String? plMajor;

  /// 計上開始年月（"YYYY-MM"）。任意。
  /// 業績PLでこの月より前には計上しない（契約開始前の過大計上を防ぐ）。
  /// null なら下限なし。なお未来月は常に計上しない（当月まで）。
  final String? startYearMonth;

  /// 計上終了年月（"YYYY-MM"）。任意。
  /// 業績PLでこの月より後には計上しない（解約済みの固定費が計上され続けるのを防ぐ）。
  /// null なら上限なし（継続中）。
  final String? endYearMonth;

  /// 変動費の「その月の実額」。キー = "YYYY-MM"（例: "2026-06"）→ 金額(円)。
  /// 未入力の月は 0 扱い。固定費では未使用。月ごとに独立（翌月は未入力=0）。
  final Map<String, int> monthlyActuals;

  const Subscription({
    required this.id,
    required this.name,
    required this.amount,
    required this.cycle,
    this.amountType = SubscriptionAmountType.fixed,
    this.billingDay,
    this.nextBillingDate,
    this.paymentMethod,
    this.memo,
    this.iconUrl,
    this.category,
    this.plMajor,
    this.startYearMonth,
    this.endYearMonth,
    this.monthlyActuals = const {},
  });

  /// 指定月("YYYY-MM")の表示金額。変動費は未入力なら0、固定費は定額。
  int amountForMonth(String ym) =>
      isVariable ? (monthlyActuals[ym] ?? 0) : amount;

  /// 業績PLに計上する、指定月([ym]="YYYY-MM")の金額。
  /// - 未来月（[ym] が [currentYm] より後）は 0（まだ来ていないので計上しない）
  /// - [startYearMonth] より前は 0（契約開始前は計上しない）
  /// - 月次: 定額=amount / 変動=その月の実額(monthlyActuals)
  /// - 年払い: 次回請求日の月だけ全額（それ以外の月は 0）
  int plAmountForMonth(String ym, String currentYm) {
    if (ym.compareTo(currentYm) > 0) return 0;
    if (startYearMonth != null && ym.compareTo(startYearMonth!) < 0) {
      return 0;
    }
    if (endYearMonth != null && ym.compareTo(endYearMonth!) > 0) {
      return 0;
    }
    if (cycle == SubscriptionCycle.monthly) {
      return isVariable ? (monthlyActuals[ym] ?? 0) : amount;
    }
    final nb = nextBillingDate;
    if (nb == null) return 0;
    final nbYm =
        '${nb.year}-${nb.month.toString().padLeft(2, '0')}';
    return nbYm == ym ? amount : 0;
  }

  /// サイクル表示名。
  String get cycleLabel =>
      cycle == SubscriptionCycle.monthly ? '月払い' : '年払い';

  /// 金額タイプ表示名。
  String get amountTypeLabel =>
      amountType == SubscriptionAmountType.fixed ? '定額' : '変動';

  bool get isVariable => amountType == SubscriptionAmountType.variable;

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
        'amountType': amountType.name,
        'billingDay': billingDay,
        'nextBillingDate': nextBillingDate?.toIso8601String(),
        'paymentMethod': paymentMethod,
        'memo': memo,
        'iconUrl': iconUrl,
        'category': category,
        'plMajor': plMajor,
        'startYearMonth': startYearMonth,
        'endYearMonth': endYearMonth,
        'monthlyActuals': monthlyActuals,
      };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'] as String,
        name: j['name'] as String,
        amount: j['amount'] as int,
        cycle: SubscriptionCycle.values.firstWhere(
          (c) => c.name == (j['cycle'] as String? ?? 'monthly'),
          orElse: () => SubscriptionCycle.monthly,
        ),
        amountType: SubscriptionAmountType.values.firstWhere(
          (t) => t.name == (j['amountType'] as String? ?? 'fixed'),
          orElse: () => SubscriptionAmountType.fixed,
        ),
        billingDay: j['billingDay'] as int?,
        nextBillingDate: j['nextBillingDate'] == null
            ? null
            : DateTime.parse(j['nextBillingDate'] as String),
        paymentMethod: j['paymentMethod'] as String?,
        memo: j['memo'] as String?,
        iconUrl: j['iconUrl'] as String?,
        category: j['category'] as String?,
        plMajor: j['plMajor'] as String?,
        startYearMonth: j['startYearMonth'] as String?,
        endYearMonth: j['endYearMonth'] as String?,
        monthlyActuals: (j['monthlyActuals'] as Map<String, dynamic>?)
                ?.map((k, v) =>
                    MapEntry(k, (v as num?)?.toInt() ?? 0)) ??
            const {},
      );

  Subscription copyWith({
    String? name,
    int? amount,
    SubscriptionCycle? cycle,
    SubscriptionAmountType? amountType,
    int? billingDay,
    DateTime? nextBillingDate,
    String? paymentMethod,
    String? memo,
    String? iconUrl,
    String? category,
    bool clearCategory = false,
    String? plMajor,
    bool clearPlMajor = false,
    String? startYearMonth,
    bool clearStartYearMonth = false,
    String? endYearMonth,
    bool clearEndYearMonth = false,
    Map<String, int>? monthlyActuals,
  }) =>
      Subscription(
        id: id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        cycle: cycle ?? this.cycle,
        amountType: amountType ?? this.amountType,
        billingDay: billingDay ?? this.billingDay,
        nextBillingDate: nextBillingDate ?? this.nextBillingDate,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        memo: memo ?? this.memo,
        iconUrl: iconUrl ?? this.iconUrl,
        category: clearCategory ? null : (category ?? this.category),
        plMajor: clearPlMajor ? null : (plMajor ?? this.plMajor),
        startYearMonth: clearStartYearMonth
            ? null
            : (startYearMonth ?? this.startYearMonth),
        endYearMonth: clearEndYearMonth
            ? null
            : (endYearMonth ?? this.endYearMonth),
        monthlyActuals: monthlyActuals ?? this.monthlyActuals,
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

  /// 月額換算の合計（月払いはそのまま、年払いは ÷12）。
  int get monthlyEquivalentTotal => subscriptions
      .fold(0, (sum, s) => sum + s.monthlyEquivalent);

  /// 未分類用のキー（UI内部で使う擬似カテゴリ名）。
  static const uncategorizedKey = '未分類';

  /// カテゴリの登場順（最初に現れた順）でユニーク化したリスト。
  /// 「未分類」（category == null）の場合は uncategorizedKey が末尾に追加される。
  List<String> get categoriesInOrder {
    final seen = <String>{};
    final list = <String>[];
    var hasUncategorized = false;
    for (final s in subscriptions) {
      final c = s.category;
      if (c == null || c.isEmpty) {
        hasUncategorized = true;
        continue;
      }
      if (seen.add(c)) list.add(c);
    }
    if (hasUncategorized) list.add(uncategorizedKey);
    return list;
  }

  /// カテゴリ別にグルーピングしたマップ（カテゴリ未指定は uncategorizedKey）。
  /// 各値の List は subscriptions の元の順序を保つ。
  Map<String, List<Subscription>> get groupedByCategory {
    final map = <String, List<Subscription>>{};
    for (final s in subscriptions) {
      final key = (s.category == null || s.category!.isEmpty)
          ? uncategorizedKey
          : s.category!;
      map.putIfAbsent(key, () => []).add(s);
    }
    return map;
  }

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
