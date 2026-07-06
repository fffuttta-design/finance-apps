import 'category.dart';

/// 取引種別。
enum TransactionType {
  /// 支出（経費・購入など）。
  expense,

  /// 収入（売上・入金など）。
  income,

  /// 振替（口座間移動）。収支には影響せず、口座の残高だけが付け替わる。
  /// transferFromAccount / transferToAccount を必ず指定する。
  /// 例: GMOあおぞら → 三井住友、銀行 → 現金、銀行 → クレカ累積額への引落 など。
  transfer,
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

  /// アプリ内ビューア用に Firebase Storage に置いたコピーのパス
  /// （例 receipts/{uid}/xxx.pdf）。receiptUrl(Driveの正本リンク)とは別枠。
  /// 値があればアプリ内で表示、無ければ従来どおり receiptUrl を外部で開く。
  final String? receiptStoragePath;

  /// 親レシート（Receipt）への参照ID。任意・後方互換。
  /// まとめ1件でも品目ごとでも、同じレシートから作られた取引は同じ
  /// receiptId を持つ（単品登録でも親レシートに辿れる）。
  final String? receiptId;

  /// 備考。
  final String? memo;

  /// 支払店舗（例: "ファミリーマート"）。任意。
  /// レシート1枚を品目ごとに複数記録した時に「どこで買ったか」を保持する。
  final String? store;

  /// この取引が紐づく収入マスタID（収入時のみ）。
  final String? incomeSourceId;

  /// 元通貨コード（例: "USD"）。null なら JPY。
  final String? originalCurrency;

  /// 元通貨での金額（例: 94.78 USD）。null なら JPY のみ。
  /// amount フィールド側には常に円換算値を入れる。
  final double? originalAmount;

  /// 振替元（type=transfer のみ使用）。
  /// 銀行口座名/カード名/「現金」等。paymentMethod と同じ命名規則。
  final String? transferFromAccount;

  /// 振替先（type=transfer のみ使用）。
  final String? transferToAccount;

  /// 見込みフラグ（発生主義・案A の運用拡張）。
  /// true: 発生月の売上を見込み額で計上（実際の入金は来月以降）。
  /// 月末締めの「入金締め処理」で実額に確定したら false に切り替える。
  /// デフォルトは false（=確定）。既存データは false で読まれる。
  final bool isPending;

  /// この取引を登録したユーザーの uid（世帯共有アプリで使用・任意）。
  /// 「相手が登録したら通知」等に使う。単独利用のアプリでは null。
  final String? recordedBy;

  /// 実際に支払った（立て替えた）ユーザーの uid（世帯共有アプリで使用・任意）。
  /// 割り勘の精算に使う。null の場合は recordedBy を支払者とみなす。
  final String? paidBy;

  /// 「個人わく」対象のユーザー uid（世帯共有アプリで使用・任意）。
  /// 非nullなら、この支出はそのユーザーの個人わく（例: 個人食費 月8,000円）から
  /// 引かれるものとして集計する。共用財布から出る前提なので通常の支出合計にも含める。
  /// null なら通常の共用支出。
  final String? personalFor;

  /// この取引に付いたチャット（コメント）の件数。
  /// 読み取り専用（toJson には含めない＝編集保存で上書きされないようにする）。
  /// 値はチャット投稿時に別途インクリメントされる。
  final int commentCount;

  /// データの登録日時（初回保存時に自動セット）。
  /// 既存データは null。編集保存では上書きしない（toJson に含めるが copyWith では引き継ぐ）。
  final DateTime? createdAt;

  /// 領収書/レシートを保存済みか（事業モードの手動チェック・税理士提出用）。
  /// 領収書URLを保存した・現物レシートを保管した等を、ユーザーが手動でチェックする。
  /// デフォルト false。既存データは false で読まれる。
  final bool receiptSaved;

  /// 同じ日付の中での手動並び順（小さいほど上）。
  /// null は「未設定」＝従来どおりの並び。ユーザーが明細をドラッグで並び替えると
  /// その日の全取引にこの値が振られ、日付ソートし直しても順序が保持される。
  final double? sortOrder;

  /// 確認済み（検収済み）フラグ。締め処理で1件ずつチェックする用途。
  /// true の行は明細で薄くグレーアウト表示。デフォルト false。
  final bool reviewed;

  /// 領収書の保管形態。'drive'=ドライブ保存 / 'paper'=紙で保管（現物を税理士へ）/ null=未設定。
  /// receiptSaved（対応済みチェック）とは別に、詳細画面で種類を記録・表示する。
  final String? receiptType;

  /// 立替精算で「あとで戻ってくる額（立替回収額）」。支出のみ・任意。
  /// 例: 合計1,200円を立て替え、自己負担600円なら reimbursed=600。
  /// amount(1,200) はカード明細と一致させるため満額のまま保持し、
  /// 「実質のコスト」= amount - reimbursed（=effectiveAmount）を集計に使う。
  /// null/0 は立替なし（実質コスト=amount）。
  final int? reimbursed;

  /// 実質のコスト（集計・PL・収支で「いくら使ったか」に使う額）。
  /// 支出で立替回収額があればそのぶん差し引く。収入/振替や立替なしは amount と同じ。
  /// 口座残高・カード請求・クレカ突合は amount（満額）を使うこと。
  int get effectiveAmount => (type == TransactionType.expense &&
          reimbursed != null &&
          reimbursed! > 0)
      ? (amount - reimbursed! < 0 ? 0 : amount - reimbursed!)
      : amount;

  /// 固定費フラグ。固定費（サブスク）から明細化した取引に付く目印。
  /// 大/小カテゴリは普通のカテゴリを使い、「固定費かどうか」はこのフラグで判別する。
  /// デフォルト false。既存データは false で読まれる。
  final bool isFixed;

  const Transaction({
    required this.id,
    required this.date,
    required this.type,
    required this.category,
    required this.paymentMethod,
    required this.description,
    required this.amount,
    this.receiptUrl,
    this.receiptStoragePath,
    this.receiptId,
    this.memo,
    this.store,
    this.incomeSourceId,
    this.originalCurrency,
    this.originalAmount,
    this.transferFromAccount,
    this.transferToAccount,
    this.isPending = false,
    this.recordedBy,
    this.paidBy,
    this.personalFor,
    this.commentCount = 0,
    this.createdAt,
    this.receiptSaved = false,
    this.sortOrder,
    this.reviewed = false,
    this.receiptType,
    this.reimbursed,
    this.isFixed = false,
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
        'receiptStoragePath': receiptStoragePath,
        'receiptId': receiptId,
        'memo': memo,
        'store': store,
        'incomeSourceId': incomeSourceId,
        'originalCurrency': originalCurrency,
        'originalAmount': originalAmount,
        'transferFromAccount': transferFromAccount,
        'transferToAccount': transferToAccount,
        'isPending': isPending,
        'recordedBy': recordedBy,
        'paidBy': paidBy,
        'personalFor': personalFor,
        'receiptSaved': receiptSaved,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (sortOrder != null) 'sortOrder': sortOrder,
        if (reviewed) 'reviewed': reviewed,
        if (receiptType != null) 'receiptType': receiptType,
        if (reimbursed != null && reimbursed! > 0) 'reimbursed': reimbursed,
        if (isFixed) 'isFixed': isFixed,
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
        receiptStoragePath: j['receiptStoragePath'] as String?,
        receiptId: j['receiptId'] as String?,
        memo: j['memo'] as String?,
        store: j['store'] as String?,
        incomeSourceId: j['incomeSourceId'] as String?,
        originalCurrency: j['originalCurrency'] as String?,
        originalAmount: (j['originalAmount'] as num?)?.toDouble(),
        transferFromAccount: j['transferFromAccount'] as String?,
        transferToAccount: j['transferToAccount'] as String?,
        isPending: j['isPending'] as bool? ?? false,
        recordedBy: j['recordedBy'] as String?,
        paidBy: j['paidBy'] as String?,
        personalFor: j['personalFor'] as String?,
        commentCount: (j['commentCount'] as num?)?.toInt() ?? 0,
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'] as String)
            : null,
        receiptSaved: j['receiptSaved'] as bool? ?? false,
        sortOrder: (j['sortOrder'] as num?)?.toDouble(),
        reviewed: j['reviewed'] as bool? ?? false,
        receiptType: j['receiptType'] as String?,
        reimbursed: (j['reimbursed'] as num?)?.toInt(),
        isFixed: j['isFixed'] as bool? ?? false,
      );

  Transaction copyWith({
    DateTime? date,
    TransactionType? type,
    Category? category,
    String? paymentMethod,
    String? description,
    int? amount,
    String? receiptUrl,
    String? receiptStoragePath,
    String? receiptId,
    String? memo,
    String? store,
    String? incomeSourceId,
    String? originalCurrency,
    double? originalAmount,
    String? transferFromAccount,
    String? transferToAccount,
    bool? isPending,
    String? recordedBy,
    String? paidBy,
    String? personalFor,
    /// true にすると personalFor を null に戻す（個人わくの解除）。
    /// copyWith は通常 null を「変更なし」と解釈するため、明示クリア用に用意。
    bool clearPersonalFor = false,
    DateTime? createdAt,
    bool forceCreatedAt = false,
    bool? receiptSaved,
    double? sortOrder,
    bool? reviewed,
    String? receiptType,
    int? reimbursed,
    /// true にすると reimbursed を null に戻す（立替の解除）。
    bool clearReimbursed = false,
    bool? isFixed,
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
        receiptStoragePath: receiptStoragePath ?? this.receiptStoragePath,
        receiptId: receiptId ?? this.receiptId,
        memo: memo ?? this.memo,
        store: store ?? this.store,
        incomeSourceId: incomeSourceId ?? this.incomeSourceId,
        originalCurrency: originalCurrency ?? this.originalCurrency,
        originalAmount: originalAmount ?? this.originalAmount,
        transferFromAccount: transferFromAccount ?? this.transferFromAccount,
        transferToAccount: transferToAccount ?? this.transferToAccount,
        isPending: isPending ?? this.isPending,
        recordedBy: recordedBy ?? this.recordedBy,
        paidBy: paidBy ?? this.paidBy,
        personalFor: clearPersonalFor ? null : (personalFor ?? this.personalFor),
        commentCount: commentCount,
        createdAt: forceCreatedAt ? createdAt : (createdAt ?? this.createdAt),
        receiptSaved: receiptSaved ?? this.receiptSaved,
        sortOrder: sortOrder ?? this.sortOrder,
        reviewed: reviewed ?? this.reviewed,
        receiptType: receiptType ?? this.receiptType,
        reimbursed: clearReimbursed ? null : (reimbursed ?? this.reimbursed),
        isFixed: isFixed ?? this.isFixed,
      );
}
