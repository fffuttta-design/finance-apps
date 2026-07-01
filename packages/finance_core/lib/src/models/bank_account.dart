import 'dart:convert';

/// 資金保有元の種別。
/// 銀行口座だけでなく現金(財布)や電子マネー(PayPay等)も同じモデルで扱う。
enum AccountType {
  /// 銀行口座
  bank,

  /// 現金（財布）
  cash,

  /// 電子マネー（PayPay/Suica/楽天Pay等）
  emoney,
}

extension AccountTypeX on AccountType {
  String get label {
    switch (this) {
      case AccountType.bank:
        return '銀行口座';
      case AccountType.cash:
        return '現金（財布）';
      case AccountType.emoney:
        return '電子マネー';
    }
  }

  String get shortLabel {
    switch (this) {
      case AccountType.bank:
        return '銀行';
      case AccountType.cash:
        return '現金';
      case AccountType.emoney:
        return '電子';
    }
  }

  String get emoji {
    switch (this) {
      case AccountType.bank:
        return '🏦';
      case AccountType.cash:
        return '👛';
      case AccountType.emoney:
        return '📱';
    }
  }
}

/// 資金口座（銀行/現金/電子マネー）の登録情報。
/// 互換性のため class 名は RegisteredBankAccount のままだが、accountType で識別する。
class RegisteredBankAccount {
  final String id;
  final String name;

  /// 口座番号下4桁（プライバシー配慮で末尾のみ）。銀行口座のみ意味あり。
  final String? last4;

  /// 開始時残高（円）。任意。
  /// 過去の参照用、入金/出金時に変動しない初期値。
  final int? startingBalance;

  /// 現在残高（円）。任意。
  /// 入出金が発生するたびに最新値で更新される。
  /// null の場合は startingBalance を現在残高として扱う。
  final int? currentBalance;

  /// 種別。デフォルトは銀行（後方互換）。
  final AccountType accountType;

  /// ロゴ画像URL（任意）。三井住友/中部電力等のブランドロゴを表示する用途。
  final String? iconUrl;

  /// 備考（任意）。「家賃振込専用」「貯蓄用」など、口座の役割を補足する。
  final String? memo;

  /// 未使用フラグ。true=休眠中。
  /// 残高がたまたま 0 のアクティブ口座と区別するため、明示的に設定する。
  /// UI 設定で「未使用を隠す」が ON の時に表示から除外される。
  final bool inactive;

  /// 月ごとの「実際に使った/引き落とされた額」（円）。キー: "YYYY-MM"。
  /// ウォレット照合（予定＝記録した明細合計 vs 実際）の手入力値。カードと同じ用途。
  final Map<String, int> monthlyActualBillings;

  const RegisteredBankAccount({
    required this.id,
    required this.name,
    this.last4,
    this.startingBalance,
    this.currentBalance,
    this.accountType = AccountType.bank,
    this.iconUrl,
    this.memo,
    this.inactive = false,
    this.monthlyActualBillings = const {},
  });

  /// 表示用の現在残高（currentBalance > startingBalance の優先順）。
  int? get displayBalance => currentBalance ?? startingBalance;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'last4': last4,
        'startingBalance': startingBalance,
        'currentBalance': currentBalance,
        'accountType': accountType.name,
        'iconUrl': iconUrl,
        'memo': memo,
        'inactive': inactive,
        'monthlyActualBillings': monthlyActualBillings,
      };

  factory RegisteredBankAccount.fromJson(Map<String, dynamic> j) =>
      RegisteredBankAccount(
        id: j['id'] as String,
        name: j['name'] as String,
        last4: j['last4'] as String?,
        startingBalance: j['startingBalance'] as int?,
        currentBalance: j['currentBalance'] as int?,
        accountType: AccountType.values.firstWhere(
          (t) => t.name == (j['accountType'] as String? ?? 'bank'),
          orElse: () => AccountType.bank,
        ),
        iconUrl: j['iconUrl'] as String?,
        memo: j['memo'] as String?,
        inactive: j['inactive'] as bool? ?? false,
        monthlyActualBillings:
            (j['monthlyActualBillings'] as Map<String, dynamic>?)
                    ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
                const {},
      );

  RegisteredBankAccount copyWith({
    String? name,
    String? last4,
    int? startingBalance,
    int? currentBalance,
    AccountType? accountType,
    String? iconUrl,
    String? memo,
    bool? inactive,
    Map<String, int>? monthlyActualBillings,
    bool clearMemo = false,
  }) =>
      RegisteredBankAccount(
        id: id,
        name: name ?? this.name,
        last4: last4 ?? this.last4,
        startingBalance: startingBalance ?? this.startingBalance,
        currentBalance: currentBalance ?? this.currentBalance,
        accountType: accountType ?? this.accountType,
        iconUrl: iconUrl ?? this.iconUrl,
        memo: clearMemo ? null : (memo ?? this.memo),
        inactive: inactive ?? this.inactive,
        monthlyActualBillings:
            monthlyActualBillings ?? this.monthlyActualBillings,
      );
}

/// クレジットカードの登録情報。
class RegisteredCreditCard {
  final String id;
  final String name;

  /// カード番号下4桁。
  final String? last4;

  /// ブランドカラー（HEX値）。レガシー。新UIでは未使用だが、既存データの
  /// 互換性のためにフィールド自体は残してある（読み書きはする）。
  final int? brandColorValue;

  /// 累積利用額（円）。当月の請求がまだ落ちていない分の合計。
  /// 引き落とし日にリセット or マイナス操作する（運用は手動）。
  final int? currentBalance;

  /// ロゴ画像URL（任意）。三井住友/楽天/JCB等のカードブランドロゴ。
  final String? iconUrl;

  /// 備考（任意）。「サブスク専用」「高額利用専用」など、カードの役割を補足する。
  final String? memo;

  /// 月の引き落とし日（1〜31）。null は未設定。
  /// 月末締めチェックリスト等で「来月X日に引き落とし」のリマインド用。
  final int? paymentDay;

  /// 引き落とし口座（RegisteredBankAccount.id）。null は未設定。
  /// 引落日に、対象月のカード利用額をこの口座から自動で差し引く（自動引落）。
  final String? settlementAccountId;

  /// 未使用フラグ。true=休眠中。
  /// 当月利用が偶々 0 円のアクティブカードと区別するため明示設定。
  final bool inactive;

  /// カード会社通知の実際の引落金額（月ごと）。
  /// キー: "YYYY-MM"（利用月）、値: カード会社通知の請求金額（円）。
  /// 予定金額（明細の合計）との差分で棚卸しに使う。
  final Map<String, int> monthlyActualBillings;

  const RegisteredCreditCard({
    required this.id,
    required this.name,
    this.last4,
    this.brandColorValue,
    this.currentBalance,
    this.iconUrl,
    this.memo,
    this.paymentDay,
    this.settlementAccountId,
    this.inactive = false,
    this.monthlyActualBillings = const {},
  });

  /// 表示用の累積額（null は 0扱い）。
  int get displayBalance => currentBalance ?? 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'last4': last4,
        'brandColorValue': brandColorValue,
        'currentBalance': currentBalance,
        'iconUrl': iconUrl,
        'memo': memo,
        'paymentDay': paymentDay,
        'settlementAccountId': settlementAccountId,
        'inactive': inactive,
        'monthlyActualBillings': monthlyActualBillings,
      };

  factory RegisteredCreditCard.fromJson(Map<String, dynamic> j) =>
      RegisteredCreditCard(
        id: j['id'] as String,
        name: j['name'] as String,
        last4: j['last4'] as String?,
        brandColorValue: j['brandColorValue'] as int?,
        currentBalance: j['currentBalance'] as int?,
        iconUrl: j['iconUrl'] as String?,
        memo: j['memo'] as String?,
        paymentDay: j['paymentDay'] as int?,
        settlementAccountId: j['settlementAccountId'] as String?,
        inactive: j['inactive'] as bool? ?? false,
        monthlyActualBillings: (j['monthlyActualBillings'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
            const {},
      );

  RegisteredCreditCard copyWith({
    String? name,
    String? last4,
    int? brandColorValue,
    int? currentBalance,
    String? iconUrl,
    String? memo,
    int? paymentDay,
    String? settlementAccountId,
    bool? inactive,
    Map<String, int>? monthlyActualBillings,
    bool clearMemo = false,
    bool clearPaymentDay = false,
    bool clearSettlementAccount = false,
  }) =>
      RegisteredCreditCard(
        id: id,
        name: name ?? this.name,
        last4: last4 ?? this.last4,
        brandColorValue: brandColorValue ?? this.brandColorValue,
        currentBalance: currentBalance ?? this.currentBalance,
        iconUrl: iconUrl ?? this.iconUrl,
        memo: clearMemo ? null : (memo ?? this.memo),
        paymentDay:
            clearPaymentDay ? null : (paymentDay ?? this.paymentDay),
        settlementAccountId: clearSettlementAccount
            ? null
            : (settlementAccountId ?? this.settlementAccountId),
        inactive: inactive ?? this.inactive,
        monthlyActualBillings:
            monthlyActualBillings ?? this.monthlyActualBillings,
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
