# FutaFinance 仕様書

> **最終更新: 2026-07-08 / v1.0.500+501**
> 変更があるたびにこのファイルを編集してバージョンを更新すること。
>
> **v1.0.500 の主な変更（2026-07-08）**（個人モードの支出タブ）
>
> - **家賃を除外して見るトグルを追加**（個人モードの支出タブのみ・`RichExpensesScreen`）。
>   家賃はハズレ値（金額が大きく他の支出が霞む）なので、ワンタップで表示/非表示を切替え、
>   他の支出を冷静に見られるようにした。設定は `UiPreferences.hideRent` で端末に永続化。
>   - 判定：取引は大／小カテゴリに「家賃」を含むもの（`_isRentTx`）、固定費（サブスク）は
>     名称／カテゴリ／会計科目に「家賃」を含むもの（`_isRentSub`）。
>   - 除外は「表示」だけに効く：支出合計・カテゴリ内訳・支払方法別・毎月の固定費・支出明細から
>     家賃を除く（`_visibleSubs`/`_rentHidden`）。**クレカ/口座の引落照合**は実額が要るため家賃を
>     含んだまま（`CreditCardBillingSection` は `_subs` 全件を使用）。
>   - **締めスナップショットは常に家賃込みの実額を記録**（隠していても正しい額を残す：
>     `snapshotExpenseFull`）。事業モードには影響なし。
>
> **v1.0.499 の主な変更（2026-07-07）**（通帳＝口座詳細画面）
>
> - **明細の列を「収入 → 支出 → 振替」の順に統一**（従来は 支出→収入→振替）。
>   ヘッダー・各行・月初/月末の仮想行すべて同順（`_ledgerHeaderRow`/`_txnRow`）。
> - **種別（入金/出金/振替）をタップでポップアップ変更できる**（`_typeCell`）。
>   - 入金・出金：この口座の取引として即付け替え（`paymentMethod` をこの口座に設定）。
>   - 振替：相手口座を選ぶダイアログ（登録口座＋現金＋カード）。現在の向き
>     （出金＝この口座から出る／入金＝入る）で `transferFromAccount`／
>     `transferToAccount` を自動セット。書き込みは裏で（画面は即反映）。
>   - 締め済みの月の取引は変更前に確認アラート（`_confirmEditClosed`）。
> - **明細が1件も無いウォレット×月でも「締める」ことができる**（`_closeMonthBar`）。
>   例：2月の PayPay に取引ゼロでも締められる。締めバーは明細ゼロでも表示し、
>   「明細なしで締める」旨のダイアログで確定する（`_closeMonth`）。
>
> **v1.0.498 の主な変更（2026-07-07）**
>
> _ページ内検索（Ctrl+F／🔍）を追加_
> - **通帳（口座詳細）・クレカ明細・支出一覧**で、Chrome の Ctrl+F のような
>   ページ内検索ができる（`widgets/find_in_page.dart`＝共通部品）。
>   - **一致した文字を黄色マーカー**で強調（`HiliteText`）。
>   - **現在の1件はオレンジ枠**で囲み、Enter／↑↓で前後にジャンプ（その行まで
>     自動スクロール＝`Scrollable.ensureVisible`）。「n / m」件数表示。
>   - **Ctrl+F または各画面の🔍アイコン**で開き、Esc／✕で閉じる。
>   - 検索対象は画面に見えている列（内容・場所・カテゴリ・支払方法・金額）。
>     金額は数字だけで照合（`1304`＝`¥1,304`）。
>   - **表記ゆれを吸収**：大文字小文字／全角半角／ひらがな⇔カタカナ／半角カナ⇒全角カナ
>     （`フタムラ`＝`ﾌﾀﾑﾗ`＝`ふたむら`）。
> - クレカ明細の既存の**絞り込み検索（該当行だけ表示）はそのまま残す**（併用）。
> - ※HOMEの「最近の取引」は当月の直近8件のみを出すカードのため、ページ内検索は
>   フル明細のある上記3画面に載せている。
>
> **v1.0.497 の主な変更（2026-07-07）**
>
> _GMOあおぞらネット銀行のCSVにも対応（取込画面を汎用化）_
> - 通帳のCSV取り込みを、銀行ごとに画面を分けず **CSVのヘッダー行から列と文字コードを
>   自動判別**する方式に一本化（`bank_csv_import_screen.dart`。旧 `shinsei_csv_import_screen.dart`
>   はこれに統合・削除）。ユーザーは銀行を選ぶ必要なし。
> - 対応形式：
>   - 新生銀行（SBI新生）: UTF-8(BOM) / `取引日,摘要,出金金額,入金金額,残高,メモ`
>   - GMOあおぞらネット銀行: Shift-JIS / `日付,摘要,入金金額,出金金額,残高,メモ`
>     （**入金・出金の列順が新生と逆**、かつ日付が `YYYYMMDD` 区切りなし）
> - 入金/出金は列の**位置ではなくヘッダー名**で特定するため、両行とも正しく振り分く。
>   半角カナは全角化（文字化け防止）、本人名（フタムラ タクミ 等）を含む振込は既定で振替。
>   仕様の大枠（対象月のみ・既存クリアして置換・振替トグル）は新生と同じ。
>
> **v1.0.488 の主な変更（2026-07-07）**
>
> - **カード明細の固定費（予定行）は「当月以降」のみ表示**（`_cardFixedRows`）。
>   過去の月は実際に発行された明細（実取引）だけを見る。開始月が未設定の固定費が
>   過去に遡って計上され、**利用合計を膨らませていた問題**を解消。
>   ※利用合計 = 実明細合計 ＋ 固定費（予定）合計（`card_detail_screen.dart`）。
> - **記録ポップアップが保存・削除で閉じない不具合を修正**（Windows等）。
>   非同期処理の後に `context` 経由で閉じると不発になるため、`Navigator` を await の
>   前にキャプチャして閉じる方式に変更（`expense_input_screen.dart`）。
>

> **v1.0.483 の主な変更（2026-07-07）**
>
> _新生銀行CSV取り込み_
> - 通帳（口座詳細）の右上に **CSV取り込みボタン** を追加（`shinsei_csv_import_screen.dart`）。
>   新生銀行（SBI新生）の入出金明細CSV（`取引日,摘要,出金金額,入金金額,残高,メモ`・UTF-8 BOM）を
>   **表示中の月ぶんだけ取り込む**。取り込み時はその口座・その月の既存明細を一度クリアして置き換え。
> - 各行を **「振替」かどうかトグルで選択可**。摘要に本人名（ﾌﾀﾑﾗ ﾀｸﾐ）を含む振込は
>   自分の口座間移動なので **既定で振替判定**（収支に入れない）。出金→振替元＝この口座、
>   入金→振替先＝この口座。振替相手は未指定（後から明細で設定可）。
>

> **v1.0.465-476 の主な変更（2026-07-07）**
>
> _通帳・カスタム順_
> - 各ウォレットは **カスタム順でも残高を表示**。並び替えると **残高を再計算**。
>   カスタム順を **確定するとその並びに切替**（`account_detail_screen.dart`）。
> - クレカ明細のカスタム順を **ハンドルドラッグ**（銀行と同じ1行スタイル）に統一。
>   編集・削除もカスタム順のまま可能。
> - **カスタム順トグルを「締める」ボタンの隣に固定配置**（スクロールしても消えない。
>   カード詳細の締めバー内。`card_detail_screen.dart`・`expense_detail_table.dart`）。
>
> _月締め_
> - 締め済みの月の金額・明細を **編集しようとするとアラート**（`_confirmEditClosed`）。
> - **未締めウォレットがある状態では全体締めをブロック**（未締め一覧をダイアログ表示）。
> - 締め済み月には **引落明細を自動生成しない**（`card_settlement_service.dart`）。
> - 締め済み表示色を **暖色セピア（0xFFF6E7C9・不透明度0.72）** に変更（青は見にくいため）。
>
> _総資産・その他_
> - 総資産タブの銀行残高を **月末残高（通帳と一致）** に統一（`v2_home_topnav.dart`）。
> - 6月のGMO振替の移動先にクレカが出ない不具合を修正（休眠カードも候補化）。
> - 振替備考のプレースホルダを削除。明細の支払方法アイコンを右端揃えに統一。
>
> **v1.0.448-464 の主な変更（2026-07-06）**
>
> _通帳（ウォレット詳細）_
> - 通帳に **「種別」列**（入金=緑／出金=赤／振替=青の色ラベル・表示専用）を追加。
> - 通帳に **「振替」列** を新設し、実支出・実収入と分離。上部サマリーも
>   **「実収入／実支出／振替」の3本** に分割（`account_detail_screen.dart`）。
> - 銀行/現金/電子マネーの通帳も **ハンドルをドラッグで並び替え**（クレカと統一）。
>   カスタム順に **「日付順に並べ直す」** ボタン追加。
>
> _クレカ引落_
> - 自動生成される引落明細の **カテゴリをカード編集で選択可**
>   （`RegisteredCreditCard.settlementCategoryMajor/Sub`・引落は振替のまま二重計上せず）。
> - 振替の **「移動先」にクレジットカード** を追加（休眠でも前月利用があれば表示）。
> - **引落/固定費の自動記録メッセージが毎回出る問題** を修正
>   （通知済みIDを prefs に記録し、同じ明細は再通知しない。`v2_root.dart`）。
> - **カード詳細の「利用合計」がウォレット一覧と一致しない不具合** を修正
>   （`_cardFixedRows` が実明細化済み固定費も出して二重計上していた。除外して一致）。
>
> _「集計」→「業績」タブ_
> - タブ名を事業・個人とも **「業績」** に統一。
> - 個人業績に **年間サマリーKPI（収入/支出/収支/貯蓄率＋前年比）**、
>   **大きい出費TOP5**、**日別支出のカレンダーヒートマップ**（GitHub風）を追加。
> - 支出の内訳を **カテゴリ別／場所別** で切替表示（`v2_report.dart`）。
>
> _場所マスタ・入力・UI_
> - 場所マスタに **ドラッグ並び替え＋セクション分け**（作成/割当/改名/削除）。
>   保存形式を配列→オブジェクト（`{stores,sections,assign}`）に拡張（旧配列も後方互換）。
> - 支出フォームの場所欄に **「場所マスタ編集」** ボタン。
> - 明細の一括編集に **「タイトル（取引内容）一括変更」** を追加。
> - **月表示をトップバー**（事業/個人の並び）へ移設。ホーム/支出/収入で共有
>   （`GlobalMonthNav`・各タブの重複月ナビは撤去。業績は月/年ナビを持つため対象外）。
>
> _不具合・パフォーマンス_
> - **スマホの支出明細が真っ白（ErrorWidget）になる不具合を根治**：v2タブ本文の外側は
>   `SingleChildScrollView` に固定（シェルが本文へ渡す制約と ListView が非互換）。
> - **PC/Windows のみスクロール高速化**：画面幅≥700（サイドバー版シェル）のときだけ
>   画面外を間引く `ListView` を使用。幅<700（スマホ）は従来の `SingleChildScrollView`
>   のままで挙動不変（`rich_expenses.dart _buildBody`）。

---

## 1. アプリ概要

| 項目 | 内容 |
|---|---|
| **名称** | FutaFinance |
| **対象ユーザー** | 二村（個人事業主・小規模事業者） |
| **目的** | 日々の事業収支管理・月次PL生成・固定費（サブスク）管理 |
| **対応プラットフォーム** | Android（メイン）/ Web / Windows Desktop（Electron） |
| **Firebase プロジェクト** | futa-finance |
| **Android パッケージ** | com.futamura.finance（futa_finance） |
| **リポジトリ** | fffuttta-design/finance-apps（Private・main ブランチ） |

---

## 2. 技術スタック

| 層 | 技術 | バージョン |
|---|---|---|
| フレームワーク | Flutter | ^3.11.4 |
| 言語 | Dart | ^3.11.4 |
| モノレポ管理 | melos | - |
| 認証 | Firebase Auth + Google OAuth2 (PKCE) | firebase_auth ^6.0.0 |
| データベース | Cloud Firestore（オフラインキャッシュ付き） | cloud_firestore ^6.0.0 |
| OCR | Gemini Vision API (gemini-2.5-flash) | - |
| HTTP | dio ^5.7.0 / http ^1.2.2 | - |
| ローカル保存 | shared_preferences ^2.3.5 | - |
| デスクトップ | Electron ^32.0.0 + electron-builder | - |
| デスクトップ起動ポート | 50873（IndexedDB オリジン安定化） | - |

**環境変数（ビルド時 --dart-define で注入）**:
- `GEMINI_API_KEY`: Gemini Vision API キー（OCR・カテゴリ予測）

---

## 3. データ構造（Firestore / SharedPreferences）

### 3.1 Firestore パス構成

```
users/{uid}/
  business/
    transactions/{txId}   # 事業用取引
    config/
      categories          # カテゴリ設定
      payments            # 支払方法（口座・カード）
      subscriptions       # 固定費・サブスク
      income_sources      # 収入マスタ
      snapshots           # 月初残高スナップショット
      closings            # 月末締め
      checklists          # 月末チェックリスト
      budget_items        # 税金・保険の支払予定（business_budget_items 等・モード別）
      compliance_tasks    # 手続き・届出の締切（business_compliance_tasks 等・モード別）
  personal/
    transactions/{txId}   # 個人用取引
    config/               # （同上・個人モード）
```

### 3.2 Transaction（取引）型定義

```dart
class Transaction {
  final String id;                   // ドキュメントID
  final DateTime date;               // 取引日
  final TransactionType type;        // expense / income / transfer
  final Category category;           // {major, sub}
  final String paymentMethod;        // "三井住友カード" 等
  final String description;          // 内容・摘要
  final int amount;                  // 金額（円・税込・常に正）
  final String? receiptUrl;          // Firebase Storage/Drive URL
  final String? receiptId;           // 親レシートへの参照（OCR取込時）
  final String? memo;                // 備考・品目一覧
  final String? store;               // 店舗名
  final String? incomeSourceId;      // 収入マスタへの参照
  final String? originalCurrency;   // "USD" 等（null=JPY）
  final double? originalAmount;     // 元通貨での金額
  final String? transferFromAccount; // 振替元口座
  final String? transferToAccount;   // 振替先口座
  final bool isPending;              // 見込み額フラグ（発生主義）
  final String? recordedBy;          // 記録者UID
  final String? paidBy;              // 支払者UID
  final int commentCount;            // チャット件数（読み取り専用）
}

enum TransactionType { expense, income, transfer }
```

### 3.3 Category（カテゴリ）体系

**事業モード（PL科目準拠）:**

| 番号 | 大カテゴリ | 主な小カテゴリ | PLセクション |
|---|---|---|---|
| 0 | 外注費 | - | 売上原価 |
| 1 | 仕入 | - | 売上原価 |
| 2 | 役員報酬 | - | 人件費 |
| 3 | 給与 | - | 人件費 |
| 4〜6 | 雑給与・賞与・法定福利 | - | 人件費 |
| 7 | 福利厚生費 | - | 販管費 |
| 8 | 広告宣伝費 | - | 販管費 |
| 9 | 交際費 | 会食 | 販管費 |
| 10 | 会議費 | セルフカフェ・コワーキング・軽食 | 販管費 |
| 11 | 旅費交通費 | タクシー・新幹線 | 販管費 |
| 12 | 通信費 | ソフトウェア・ライセンス料金 | 販管費 |
| 13 | 消耗品費 | 機材・資材・装飾品 | 販管費 |
| 14〜21 | 修繕・光熱・新聞図書・諸会費・支払手数料・賃借料・保険・租税公課 | - | 販管費 |
| 22 | 支払報酬 | コンサル・顧問経費 | 販管費 |
| 23 | 減価償却費 | - | その他費用 |
| 24 | 雑費 | 営業用等 | その他費用 |
| 25 | 支払利息 | - | 営業外費用 |
| 26 | 雑損失 | - | 営業外費用 |

```dart
class Category {
  final String major;  // "12.通信費"
  final String sub;    // "ソフトウェア"
  int get majorOrder;  // プレフィックス番号を整数化
}
```

### 3.4 PaymentMethodsConfig（支払方法）

```dart
class RegisteredBankAccount {
  final String id;
  final String name;              // "住信SBIネット銀行"
  final String? last4;            // 口座末尾4桁
  final int? startingBalance;     // 開始残高
  final int? currentBalance;      // 現在残高（入出金で更新）
  final AccountType accountType;  // bank / cash / emoney
  final bool inactive;            // 未使用フラグ
}

class RegisteredCreditCard {
  final String id;
  final String name;              // "三井住友カード"
  final String? last4;
  final int? currentBalance;      // 累積利用額（月次リセット）
  final int? paymentDay;          // 月の引き落とし日（1〜31）
  final bool inactive;
}
```

**保存先**: `config/payments`（JSON）

### 3.5 Subscription（固定費・サブスク）

```dart
class Subscription {
  final String id;
  final String name;                   // "ChatGPT Plus"
  final int amount;                    // 金額（円）
  final SubscriptionCycle cycle;       // monthly / annually
  final SubscriptionAmountType amountType; // fixed / variable
  final int? billingDay;               // 月払い時の請求日
  final DateTime? nextBillingDate;     // 年払い時の次回請求日
  final String? paymentMethod;         // 支払方法名
  final String? plMajor;               // PL科目（"通信費" 等）
  final String? startYearMonth;        // 計上開始年月 "YYYY-MM"
  final String? endYearMonth;          // 計上終了年月（解約時）
  final Map<String, int> monthlyActuals; // 変動費の月実績 {"2026-06": 5500}

  int plAmountForMonth(String ym, String currentYm);
  // ym > currentYm → 0（未来は計上しない）
  // ym < startYearMonth → 0
  // ym > endYearMonth → 0
  // 月払い: fixed→amount / variable→monthlyActuals[ym]
  // 年払い: nextBillingDate の月のみ全額
}
```

**保存先**: `config/subscriptions`（JSON）

### 3.6 IncomeSource（収入マスタ）

```dart
class IncomeSource {
  final String id;
  final String name;           // "Aクライアント月額顧問"
  final String? clientName;
  final int? expectedAmount;   // 想定金額（記録時の初期値）
  final IncomeCycle cycle;     // oneTime / monthly / quarterly / semiAnnually / annually
  final int? dayOfMonth;
  final bool archived;
}
```

**保存先**: `config/income_sources`（JSON）

### 3.7 MonthlySnapshot（月初残高）

```dart
class MonthlySnapshot {
  final String yearMonth;     // "2026-06"
  final int initialBalance;   // 月初の全資金合算残高
  final DateTime recordedAt;
}
// 推定残高 = initialBalance + 当月収入 - 当月支出
```

**保存先**: `config/snapshots`（JSON）

### 3.8 その他の設定ドキュメント

| ドキュメント | 型 | 用途 |
|---|---|---|
| `config/closings` | MonthClosingConfig | 月末締めの状態管理 |
| `config/checklists` | ChecklistConfig | 月末チェックリスト項目 |

---

## 4. 認証の仕組み

### 4.1 プラットフォーム別 Google OAuth

| Platform | 方式 |
|---|---|
| Android | `google_sign_in` プラグイン（Google Play Services 経由） |
| Web | `firebase_auth.signInWithPopup()` |
| Windows | `WindowsGoogleAuth`（自前・ループバック + PKCE） |
| Electron | `main.js` の OAuth Bridge（Node.js で http サーバ起動） |

**OAuth クライアントID**: `746983928581-1pg8giqolvjim3v4gogqaf5jh0f0pncf.apps.googleusercontent.com`

### 4.2 Electron の OAuth ブリッジ

```
1. ユーザーがログインをクリック
2. main.js が localhost でエフェメラルポートの http サーバを起動
3. デフォルトブラウザで Google OAuth 認可ページを開く
4. redirect_uri (http://127.0.0.1:{port}) で code を受け取る
5. access_token / id_token を取得 → preload.js 経由で Flutter へ渡す
6. refresh_token を app.userData/auth.json に永続化
```

### 4.3 IPC チャネル（main.js ↔ Flutter）

| チャネル名 | 役割 |
|---|---|
| `futa:signIn` | 対話的ログイン（ブラウザ起動） |
| `futa:silent` | 自動ログイン（refresh_token 使用） |
| `futa:driveToken` | Drive API 用 access_token 取得 |
| `futa:signOut` | ログアウト（auth.json クリア） |
| `futa:checkUpdate` | 手動での更新確認 |

---

## 5. 収支入力の仕様

### 5.1 支出（Expense）入力

**必須**: 日付・カテゴリ（大/小）・内容・支払方法・金額

**オプション**: 備考（既定表示）・多通貨（USD等）

- **v1.0.346〜**: 入力フォームを簡素化。**店舗名フィールドを廃止**（OCR取込からの店舗値は引き続き保存）、
  **備考はデフォルト表示**（旧「詳細を追加 ▾」の折りたたみを廃止）、**領収書のギャラリー/カメラ添付ボタン・
  「レシートを開く」ボタンを廃止**。OCR由来のレシートは上部「レシートを見る」から従来どおり閲覧可。

#### 立替精算— v1.0.347〜

「自分が一括で支払い（主にクレカ）、他人から現金をもらう」ケースを1回の支出記録で処理する。
支払方法の下の **「立替精算」トグル**を ON にして使う（新規記録時のみ）。

- 入力：**自分の負担額**（円）。**もらう現金 = 入力金額 − 自分の負担**（自動計算で表示）。
- **受け取り先ウォレット**を選ぶ（非カードの有効な現金/口座/電子マネー。既定は現金口座）。
- 保存時の挙動（ユーザー要件で確定）：
  - **経費は全額を計上**（PL・支出一覧・カード請求はそのまま。例：1万円）。
  - **もらう現金は「収入」にせず**、受け取り先ウォレットに **振替取引（PL非計上・`transferFromAccount='立替精算'`／`transferToAccount=受け取り先`）** として +金額。
    口座台帳（startingBalance＋取引差分）と クイック残高（currentBalance）の両方に反映。
  - 受け取りは **即時**（後日精算の保留機能は持たない）。
  - 純資産の増減は「カード債務 +1万円・現金 +6千円 ＝ 実質 −4千円」で正しく、**PL上の経費だけ全額（1万円）**になる点に注意。
- 実装：`expense_input_screen.dart` の `_treatSplitSection()` ＋ `_save()`。立替回収の振替取引は支出とは独立レコード（紐づけメモ付き）。
  支出を後から削除しても回収の振替は自動削除されない（必要なら手動削除）。

### 5.2 収入（Income）入力

**必須**: 日付・収入マスタ選択 or 手入力名・金額

**オプション**: 備考

### 5.3 振替（Transfer）入力

口座間の移動（収支に影響しない）。

例: 銀行 → クレジットカード累積額へ振替

- **名前（任意）（v1.0.352〜）**: 振替に任意の名前を付けられる（例「カード引落用」「生活費の移動」）。
  名前を入れるとそれが `description` になり、未入力なら従来どおり `移動元 → 移動先` を自動命名。
  通帳の振替表示（`振替 移動元 → 移動先`）は `transferFromAccount/ToAccount` から組むため名前と両立する。

**「+記録」メニュー（`_RecordMenuButton`）**: レシートで記録 / 経費（支出）を記録 / 売上（収入）を記録 / 振替を記録。
※ **「明細を分けて記録」は v1.0.352 で廃止**（レシートOCR経由の品目分割は継続）。

### 5.4 支払方法の分類

```
クレジットカード（RegisteredCreditCard）
銀行口座（RegisteredBankAccount, accountType=bank）
現金（RegisteredBankAccount, accountType=cash）
電子マネー（RegisteredBankAccount, accountType=emoney）
```

---

## 6. OCR レシート読み取り仕様

### 6.1 フロー

```
記録メニュー → "レシートを読取"
  → ReceiptCameraScreen（自前カメラ or ギャラリー）
  → 画像 (品質55%, 最大幅1024px) を取得
  → Gemini gemini-2.5-flash へ base64 送信
  → ReceiptOcrResult を解析
  → Drive へ画像を並行アップロード（裏実行）
  → 記録方法の選択（まとめて1件 / 品目ごと）
  → ExpenseInputScreen or ReceiptSplitScreen
  → 保存
```

### 6.2 Gemini が返す JSON

```json
{
  "store": "店名",
  "date": "YYYY-MM-DD",
  "total": 1234,
  "categoryMajor": "12.通信費",
  "categorySub": "ソフトウェア",
  "items": [
    { "name": "品名", "price": 1234, "quantity": 1, "unitPrice": 1234 }
  ]
}
```

### 6.3 カテゴリ自動予測

- Gemini にユーザーのカテゴリ一覧 `Map<String, List<String>>` を渡す
- Gemini はその一覧から `categoryMajor` / `categorySub` を選択して返す
- タイムアウト: 30秒 / 429レート制限: 最大3回リトライ

### 6.4 まとめて1件 vs 品目ごと

| モード | 動作 |
|---|---|
| まとめて1件 | 合計金額で1件の支出。品目一覧を memo に記入 |
| 品目ごと | 各品目を独立した支出として記録。品目別カテゴリ指定可 |

---

## 7. 貼付取り込み（TSV インポート）仕様

**画面**: `PasteImportScreen`

**入力フォーマット**（タブ区切り・Excel/Sheets からコピペ）:

```
日付      [曜日]  大カテゴリ  小カテゴリ  内容        支払方法  金額
01/15            消耗品費   機材        MacBook     クレカ    ¥300,000
01/16    水      通信費     ソフトウェア  ChatGPT     銀行      $20
```

**仕様**:
- 日付: `MM/DD`（年は画面指定）or `YYYY/MM/DD`
- 曜日列: あってもなくても対応
- 通貨: ¥/円→JPY / $/＄→USD（画面の `rate` で円換算、デフォ150）
- 動作: **追加のみ**（既存データは消えない）
- 取込前に自動スナップショット保存

### 7-2. 請求書PDF 一括取り込み（v1.0.319〜）

**画面**: `InvoiceImportScreen`（開発中タブ「取込」の下部から起動）

**目的**: 売上／支払（外注）の請求書PDFを複数まとめて読み取り、取引として一括記帳する。

**フロー**:
1. `file_picker`（`allowMultiple: true, withData: true, allowedExtensions: ['pdf']`）でPDFを複数選択。
2. 1枚ずつ順次 Gemini に投げて抽出（`InvoiceExtractor` / `data/invoice_extractor.dart`）。
   PDFバイトを `inline_data`（`mime_type: application/pdf`）で送信。スキャンPDFも可。
3. 抽出結果（種別・取引先・日付・税込金額・摘要・支出科目候補）をプレビュー行に展開。
4. 各行を確認・修正（種別トグル／取引内容／日付／金額／会計科目／支払・受取方法／除外）。
5. 「○件を記帳する」で `core.Transaction` を生成し `TransactionRepository.add` で追加。

**仕様**:
- **種別**: 売上請求書 → 収入 / 支払・外注請求書 → 支出。画面上部のバッチ既定トグルで初期種別を指定でき、
  Gemini の推定（`isSales`）で上書きされ、各行で個別に切替も可能。
- **取引先**: 支出=発行元（請求してきた相手）/ 収入=宛先（請求した顧客）を取引内容に初期セット。
- **会計科目（支出）**: Gemini が現モードの大カテゴリ候補から選択。未確定時は「外注費」を既定。
- 収入は取引内容（取引先/売上区分）を大カテゴリに入れる（収入源別PL集計に合わせる）。
- 支払/受取方法: 現モードの口座・カードのドロップダウン（未登録なら自由入力、既定は先頭口座）。
- 動作: **追加のみ**。モード別カットオフ（事業=2025/10・個人=2026/01）より前の日付はスキップ。
- APIキー（`GEMINI_API_KEY`）が無い環境（Web自動ビルド）は `InvoiceExtractor.available==false` でボタン非表示
  （Android / Windows 版で利用）。

---

## 8. PL（損益計算書）表示仕様

**画面**: `V2ReportScreen`

| PL行 | 集計対象 |
|---|---|
| 売上高 | `TransactionType.income` の合計 |
| 売上原価 | "0.外注費" + "1.仕入" |
| **粗利** | 売上 - 原価 |
| 人件費 | "2〜6" 系カテゴリ |
| 販管費 | "7〜22" 系カテゴリ + 固定費の `plMajor` 計上分 |
| その他費用 | "23.減価償却費" + "24.雑費" |
| **営業利益** | 粗利 - 販管費合計 |
| 営業外収益/費用 | "25.支払利息" 等 |
| **当期純利益** | 営業利益 ± 営業外 |

**固定費（Subscription）のPL計上**:
- `plMajor` が設定されたサブスクは該当科目に月次計上
- `startYearMonth` / `endYearMonth` で計上期間を限定
- 変動費は `monthlyActuals[ym]` の実額を使用

---

### UI/設定の整理（v1.0.366〜）
- **新デザイン（リッチUI）に固定**。`UiPreferences.richUi` は常に true、設定の「新デザイン」トグルを廃止（旧デザインの切替は不可に。`V2HomeTopNavScreen` 等の旧画面コードは未使用＝今後物理削除可）。
- 設定「データ管理」から **「明細の貼り付け取込・開発ラボ」（devLab）を削除**（未使用のため）。
- **AppBar のスクロール時グレー化（M3 surfaceTint）を全体で無効化**（`V2Theme.light()` の `appBarTheme` ＋設定のフルスクリーンパネルで `scrolledUnderElevation:0 / surfaceTintColor: transparent`）。
- **マウス「進む」ボタンの暫定対応（v1.0.367〜）**: Flutter Web/Navigator 1.0 は「戻る」はできるが「進む」で直前の画面を復元できない。go_router 化（大改修）を避けつつ、`NavHistory`（`lib/data/nav_history.dart`）で主要なフルスクリーン遷移だけを `push` 経由で開き、戻ったら "進む候補" として記憶 → 進むボタンで開き直す簡易フォワードスタックを実装。
  - 対応範囲: **設定の各サブ画面（`_openPanelScreen`）/ 支出カテゴリ→小カテゴリ編集 / ウォレットからの口座・カード詳細**。モーダルやPCの2ペイン切替は対象外。
  - 配線: `main.dart` に `navigatorKey` 設置＋`Listener` で `kForwardMouseButton` を拾う。Web/Electron は `window.futaGoForward`（`nav_history_hook_web.dart`、条件付きimport `dart.library.js_interop`）を生やし、`main.js` の `browser-forward` から呼ぶ（無ければ `history.forward()` にフォールバック）。

### Drive領収書の一覧→紐付け（B方式・v1.0.376〜）
- 事業モードの支出入力フォームに **「Driveから選ぶ」** ボタンを追加。`showDriveReceiptPicker`（`lib/widgets/drive_receipt_picker.dart`）で、その取引の月フォルダ（事業用/YYYY年/MM月）にある領収書を一覧表示（サムネ＋ファイル名＋保存日、プレビュー可）→ タップで `receiptUrl` に紐付け。
- `DriveReceiptService.listMonthReceipts({date, isBusiness})` ＋ `_findMonthFolderOnly`（作らず探すだけ）＋ `DriveReceiptFile` を追加。
- **制約（drive.file 権限）**: 一覧に出るのは**このアプリが保存した領収書のみ**（手でDriveに入れたファイルはAPI仕様で取得不可）。全件連携が必要なら `drive.readonly` への拡張が別途必要（同意画面が変わる）。領収書運用は**事業モードのみ**。

### パレット24色化（v1.0.375〜）
- **`CategoryColors.palette` を16→24色に拡張**（暖色/寒色交互・かぶりさらに低減）。色ピッカーも24色。

### パレット16色化＋既定時の並び替え矢印を非表示（v1.0.374〜）
- **`CategoryColors.palette` を10→16色に拡張**（暖色/寒色を交互配置でかぶり低減）。色ピッカーの選択肢も16色に。
- **明細テーブルの並び替え矢印を「未操作時は非表示」に**（`_sortTouched`）。既定の日付順では `日付` に矢印・アクセント色を出さず、ヘッダー/チップを一度タップしてから現在列を強調する（PC・スマホ両方）。

### カテゴリ色の即時反映バグ修正＋階段状の色割当（v1.0.373〜）
- **色変更が即反映されないバグを修正**：カテゴリ編集の行が `CategoryColors.effective`（保存後に更新されるキャッシュ）を見ていたため、色を選んでも即時に変わらなかった。行は `major.colorValue`（`_config` の生値）を直接読むようにして即時反映。
- **`autoColor` を「並び順インデックスで階段状にパレット割当」に変更**：`CategoryColors._order`（config.majors の並び順）を使い、隣同士が必ず別色になるよう `palette[index % 10]` を割り当て（キーワード一致＝食=オレンジ等は優先）。事業の多数カテゴリが似た色に潰れる問題を解消し「このカテゴリ＝この色」を安定化（手動色は従来どおり最優先）。

### 領収書リンク/画像入力＋金額列リサイズ＋固定費ヘッダー調整（v1.0.372〜）
- **事業モードの支出入力/編集フォームに「領収書（任意・税理士提出用）」欄を復活**（`ExpenseInputScreen`）。リンク貼付（`receiptUrl`）と「画像を保存」（`ReceiptCameraScreen`で撮影/選択→`DriveReceiptService.uploadReceiptImage`でDrive保存→URL自動セット）の両方が選べる。保存時、領収書リンク/画像があれば `receiptSaved` を自動ON（無ければ既存の手動チェックを維持）。**編集時に receiptSaved が消えないよう保持も修正**。
- **支出明細テーブルの「金額」列も可変列化**（中央5列＝大/小/内容/支払方法/金額）。支払方法↔金額の境界にリサイズハンドル追加。保存キー `..._v3`。
- **「毎月の固定費」ヘッダーの右合計のはみ出しを修正**（右パディング32で下の各行金額に揃える）。

### 自動引落明細のカテゴリを選択可能に（v1.0.448〜）
- カード編集（`card_editor_screen`）に **「引落明細のカテゴリ」**（大カテゴリ）ドロップダウンを追加。`RegisteredCreditCard.settlementCategoryMajor`/`settlementCategorySub` を新設。自動生成される引落明細（`CardSettlementService`）が、設定があればそのカテゴリ名で表示される（未設定は「振替」）。
- **引落は振替扱いのまま（収支/PL非計上・二重計上しない）**。カテゴリは明細の表示ラベル。カード保存後に既存の引落明細へ `CardSettlementService.syncCategory` で一括反映。

### 振替フォームのデザインを他フォームと統一（v1.0.447〜）
- 振替を記録（`transfer_input_screen`）を、支出/収入フォームと同じデザインに統一。**floating labelの `InputDecorator`/`labelText` → 見出し（`_label`）＋素の入力欄（`_inputDecoration`）** に変更（プレースホルダーで項目名を表さない）。AppBarを **✕ 閉じる**、保存を**下部バー→末尾の「記録する/更新する」ボタン**に、金額を**一番上**に移動。旧 `_bottomActions` は削除。

### 締め済みウォレットの画面グレーアウト／収入フォームの金額を上部に（v1.0.446〜）
- **締め済みウォレットは画面全体をグレーアウト（①）**: 口座詳細（`account_detail_screen`）・カード詳細（`card_detail_screen`）で、その月が締め済みなら本文（残高カード＋明細）を `Opacity 0.5` で薄く表示（締めバー/月ナビは通常）。
- **収入フォームの金額を最上部に（②）**: 収入を記録（`income_input_screen`）で「入金額（円）」を一番上に移動（支出フォームと同じく金額を最初に目立たせる）。

### 場所マスタの固定入力／HOMEの月表示統一／検索行に場所（v1.0.445〜）
- **場所マスタの固定入力（①）**: 支出保存時、入力した場所が**場所マスタに無ければ確認ダイアログで弾く**（「場所を選び直す／マスタに追加して保存」）。表記ゆれを入口で防ぐ。候補は従来どおり出る。設定→マスタデータ→**場所マスタ**で管理・統合（既存）。
- **HOMEの月表示を他タブと統一（②）**: ホームの月切替を、収支カード右上 → **他タブと同じ上部・中央の大きな月表示（`MonthNavBar`）** に移動。
- **明細検索の行に場所を表示（④）**: 検索結果の各行のサブテキストに「📍場所」を追加（カテゴリ ・ 📍場所 ・ 支払方法）。

### 集計タブに支出内訳の円グラフ＋カード引落の確実発行/二重計上修正（v1.0.444〜）
- **集計タブに「支出の内訳」円グラフ（②-B）**: 個人の集計（`v2_report._personalReport`）に、その年の大カテゴリ別支出（実質コスト）を **ドーナツ円グラフ＋凡例（カテゴリ/％/金額）** で表示（自前描画 `_PieBreakdown`/`_DonutPainter`・上位8＋その他）。
- **カード自動引落の確実発行（別件③）**: `CardSettlementService` の生成範囲を、直近62日窓 → **利用月の下限(2025-11)まで遡って生成**に拡大（引落口座を後から設定しても過去分まで発行）。未到来の引落は作らない。`_planned` の固定費二重計上も修正（実明細化済みは加算しない）。※引落口座は必須化済み（v1.0.443）、引落口座＝設定口座から振替。

### カード/口座編集：ロゴURLの折りたたみ＋引落口座を必須に（v1.0.443〜）
- **ロゴURLの折りたたみ（①）**: カード編集（`card_editor_screen`）・口座編集（`account_editor_screen`）の `_logoUrlField` に `editing`/`onToggleEdit` を追加。**既にロゴ設定済みなら URL入力を毎回出さず、ロゴ＋「ロゴを編集」ボタンだけ**表示（押すと展開）。固定費編集シートと同じ挙動に統一。
- **引落口座を必須に（②）**: カード編集の「引き落とし口座」を **任意→必須**（`isValid` に `selectedSettlementId != null` を追加・保存ボタンは未設定だと押せない）。ラベルの「（任意）」を削除し「引き落とし口座」に、「— 自動引落しない —」選択肢を撤去。

### 明細検索に場所の一括変更／収入マスタ編集ボタン／記録メニューをポップアップに（v1.0.442〜）
- **明細検索に「場所変更」（①）**: 一括編集に**場所（店舗）の一括変更**を追加（`transaction_search_screen._bulkChangeStore`）。場所マスタからチップで選ぶ＋手入力可、適用時にマスタへ自動追加。アクションバーは3ボタン（カテゴリ/場所/支払方法）で Wrap。
- **収入マスタ編集ボタン（④）**: 収入を記録の「収入マスタ」欄に「収入マスタ編集」ボタンを追加（`_openIncomeMasterEditor` → `IncomeMasterScreen`、戻ったら候補を再読込）。
- **記録メニューをポップアップに（③）**: 口座詳細の「記録」ボタンを、中央ダイアログ（SimpleDialog）→ **HOMEと同じボタン脇のポップアップメニュー**（`PopupMenuButton`）に変更（画面中央を奪わない）。`_openRecord(kind)` で入金/出金/振替を開く。旧 `_showAddMenu`/`_addMenuTile` は削除。

### 編集時のカテゴリ復元／固定費編集の明細反映／ウォレット金額の二重計上修正（v1.0.441〜）
- **編集時に現在のカテゴリを表示（④）**: 支出編集で、保存済みの大カテゴリが番号ズレ/素名でもドロップダウンの項目に解決して表示（`_resolveMajorName`・素の名前一致で照合）。一覧に無い値も選択肢として残す。小カテゴリは空なら null に。「選択してください」のまま出る不具合を解消。
- **固定費編集を明細化済みの取引にも反映（②）**: `FixedCostMaterializer.syncMaterialized(sub)` を追加。`fixedcost_{subId}_*` の取引を、編集後の大/小カテゴリ・支払方法・名前・固定費フラグ・領収書受取方に一括更新（金額は月次実績なので不変）。固定費編集の保存後に呼ぶ（`v2_expenses._editSubscription`／`subscription_list_screen._edit`）。
- **ウォレット金額の二重計上を修正（①）**: `CreditCardBillingSection._planned` で、既に実明細化された固定費（`fixedcost_{subId}_{ym}` 取引が存在）は**サブスク側で加算しない**（取引側で計上済み）。例：新生銀行が固定費ぶんを二重に出て230,000になっていたのを解消。

### 締めたウォレットは支出タブの一覧でグレーアウト（v1.0.440〜）
- 支出タブのウォレット一覧（`CreditCardBillingSection`/`_BillingRow`）で、**その月を締め済みのウォレットの行を薄く（Opacity 0.5）＋「締め済」バッジ**表示。締め状態は口座/カードの複合キー（`w:`/`card:`）から抽出（`rich_expenses._closedWalletNames`）→ `closedWalletNames` で受け渡し。例：PayPayを締めるとウォレット一覧のPayPay行がグレーアウト。

### ウォレットの月締めを「明示ボタン」方式に（自動締めを廃止）（v1.0.439〜）
- 口座詳細/カード詳細の月締めを、**「全チェックが入ったら締め済み」→「ユーザーが締めボタンを押したときだけ締め済み」**に変更。締め状態を **明示フラグ**で保持（`MonthClosingRepository` に `w:{口座名}:{YYYY-MM}` / `card:{カード名}:{YYYY-MM}` の複合キーで `closedAt` を記録・月グローバルの締めと衝突しない）。`_isMonthClosed`/`_isCardMonthClosed`/`_setClosedFlag`/`_setCardClosedFlag`。
- 締める＝取引(＋固定費)を全部確認済みにして締めフラグON。締め解除＝**フラグを外すだけ**（確認チェックは残す）。チェックを全部手で入れても、締めボタンを押すまでは締め済みにならない。

### クレジットカードにも月締めボタン（全ウォレット対応）（v1.0.438〜）
- カード詳細（`card_detail_screen`）の月モードに締めバーを追加（`_cardCloseMonthBar`）。「この月を締める」で、その月の**取引(reviewed)＋固定費(reviewedMonths[ym])を全部確認済み**にする（`_closeCardMonth`/`_reopenCardMonth`/`_setCardMonthReviewed`・取引は `updateMany`、固定費はサブスクを1回で保存）。全件確認済みなら「締め済み」＋締め解除。これで銀行/現金/電子マネー（v1.0.434）に続き**クレカも含む全ウォレットで月締め**が可能に。

### 場所マスタ（購入場所のマスタ化・統合で過去も一括書き換え）（v1.0.437〜）
- **場所マスタ**: `data/store_master_repository.dart`（`StoreMasterRepository`・**事業/個人で共通＝モード非依存**・Firestore `users/{uid}/config/store_master` の json／未ログインは prefs）。場所名の List<String>。`add`/`addAll`/`save`/`load`。
- **管理画面**: `screens/store_master_screen.dart`（`StoreMasterScreen`）。追加／名前変更／削除／**統合（merge）**／**履歴から取込**。設定 → マスタデータ →「場所マスタ」（`v2_settings` に `storeMaster` ケース追加）。
  - **統合・名前変更は過去の明細も一括書き換え**（`_rewriteStore`：`t.store==from` の取引を全部 `to` に `update`）。表記ゆれ（ファミマ→ファミリーマート）を過去分ごと揃えられる。ユーザー確定＝共通・過去も書き換え。
- **支出入力との連携**: 場所欄の候補にマスタ登録名を含める（`_storeSuggestions` に `StoreMasterRepository.instance.cached` を加点）。保存時に入力した場所を**自動でマスタ登録**（`_save` で `add`）。フォーム表示後に裏でマスタを `load`。

### 未登録支払方法の一覧表示＋締め済みの月をグレーアウト（v1.0.436〜）
- **未登録の支払方法だけを絞り込み**: 明細検索（`transaction_search_screen`）の支払方法フィルタに「⚠ 未登録のみ」を追加。登録済み口座/カードに無い支払方法（例「クレカ」）の明細だけを一覧表示 → 正しいカードに付け替えできる（`_registeredNames`/`_unregSentinel`）。
- **締め済みの月をグレーアウト**: 支出タブ（`rich_expenses`）で、その月が締め処理済み（`MonthClosing.isClosed`）なら本文（サマリー/カテゴリ内訳/明細）を `Opacity 0.5` で薄く表示（`_grey`/`_isMonthClosed`）。締めバー(`MonthClosingBar`)は締め/取消時に `onChanged` コールバックで即再読込しグレーアウトを更新。

### 月末残高の強制変更＋差額調整行／未登録支払方法の付け替え（v1.0.435〜）
- **月末残高の強制変更＋差額調整**: 口座詳細（`account_detail_screen`）で月末残高を手入力し計算が合わないとき、整合性ダイアログに **「差額調整を追加して合わせる」** を追加。選ぶと、その月末に **「差額調整（強制変更）」** を1件作り、入力した月末残高にぴったり合わせる（アプリ導入前のズレ合わせ用）。実装＝収支/PLに載せない**振替扱い**（相手＝擬似口座「差額調整」）で口座台帳だけを差額ぶん動かす（`_addBalanceAdjustment`）。台帳では**赤字＋太字**で表示（`_txnRow` の `isAdjust`）。従来の「月初優先で保存」も残置。
- **未登録の支払方法を付け替え可能に**: 明細検索（`transaction_search_screen`）の支払方法フィルタに、**取引に出てくる未登録の支払方法（例「クレカ」）も候補として表示**。検索→選択→「支払方法を一括変更」で正しいカードに付け替えれば、ウォレット一覧の未登録エントリを掃除できる。

### ウォレット別の月締めボタン＋月表示の大型化（v1.0.434〜）
- **ウォレット別「この月を締める」**: 口座詳細（`account_detail_screen`）に、月選択時だけ出る締めバーを追加。ボタンで **その月・そのウォレットの取引を全部「確認済み(reviewed=true)」** にする（確認ダイアログあり）。全件確認済みなら「締め済み」バッジ＋「締め解除」。`_monthRelatedTxns`/`_closeMonth`/`_reopenMonth`/`_closeMonthBar`。専用モデルは足さず既存の reviewed フラグを使用。
- **月表示を大きく**: 共通の月ナビ `MonthNavBar` の月ラベルを 20px 太字に、矢印を26pxに拡大（ホーム/支出/収入/業績/口座詳細で共通に大きく表示）。

### 場所ラベルの「（必須）」削除＋口座の「記録する」メニューをリッチ化（v1.0.433〜）
- 支出入力の「場所（必須）」ラベルを **「場所」** に変更（入力は引き続き必須だが表記をすっきり）。
- 口座詳細（`account_detail_screen`）の「記録する」メニュー（入金/出金/振替）を、素の `ListTile` から **丸アイコン＋枠付きタイル＋シェブロン** のリッチUIに刷新。ダイアログも角丸16px。

### 固定費を「大カテゴリ」でなく「フラグ」に（v1.0.432〜）
- **方針**: 固定費（サブスク）を明細化するとき、大カテゴリを「固定費(定額)/(変動)」にするのをやめ、**普通の大/小カテゴリ**を適用。「固定費かどうか」は取引の **`isFixed` フラグ** で表す。
- **Transaction**: `bool isFixed`（既定false）を追加（toJson/fromJson/copyWith）。
- **Subscription**: `categoryMajor`（明細に付ける大カテゴリ＝表示名）／`categorySub`（小カテゴリ）を追加。編集で大カテゴリを選ぶと `plMajor`／`category`（セクション/PL用）にはその素の名前を兼用セット（既存PL集計と整合）。
- **明細化（`fixed_cost_materializer`）**: `categoryMajor` があれば `Category(major: categoryMajor, sub: categorySub)`＋`isFixed:true` で生成。無い旧固定費は従来どおり「固定費(定額)/(変動)」。重複判定（`_isSameFixed`/`_template`）も `isFixed` を見るよう更新。
- **編集UI**: 固定費編集（共通シート `subscription_edit_sheet` ＋ 設定画面 `subscription_list_screen`）の「会計科目1個選択」を、**大カテゴリ＋小カテゴリのプルダウン**（支出記録と同じ）に変更。呼び出し元（`v2_expenses`）は `categoryOptions`（大＝表示名／小＝その小一覧）を渡す。
- **検索**: 明細検索（`transaction_search_screen`）に **「固定費」フィルタ**（すべて/固定費のみ/固定費以外）を追加。
- **移行**: 既存の「大カテゴリ＝固定費」の過去明細は今後分から新方式（過去は検索・一括編集で手動修正）＝ユーザー決定。

### 取引内容の履歴サジェストがタップで反映されない不具合を修正（v1.0.431〜）
- 取引内容（`_descCtrl`）のサジェストを、自前の「フォーカス中だけ表示するリスト」から **`RawAutocomplete` 方式** に変更（場所欄と同じ）。候補をタップした瞬間にフォーカスが外れてリストが消え、選択が成立しなかった不具合を解消。`_StoreOptionsView` に `icon` 引数を追加して取引内容（履歴アイコン）でも再利用。旧 `_applyDescSuggestion`/`_descSuggestionList` は削除。

### 集計タブに「明細を検索・一括編集」（v1.0.430〜）
- 集計タブ（`v2_report`）上部に **「明細を検索・一括編集」ボタン** を追加（事業/個人 両モード）。押すと `TransactionSearchScreen`（`screens/transaction_search_screen.dart`）を開く。
- **検索（絞り込み）**: キーワード（内容/店舗/メモ/カテゴリ）・期間（開始/終了）・種別（支出/収入/振替）・大カテゴリ・支払方法・検収（済/未）。全取引 `loadAll` を対象に AND 条件で絞り込み、日付降順表示。
- **選択**: 各行チェックボックス＋「全選択/全解除」。行タップで取引詳細へ。
- **一括更新**: 選択した明細に対して〈**カテゴリを一括変更**（大/小カテゴリを選ぶ）／**支払方法を一括変更**〉を適用（`copyWith` → `TransactionRepository.update` を各件に実行、完了後に再読込）。※削除・検収一括ON/OFF はユーザー要望により今回は含めない。

### 取引を編集しても検収チェック（reviewed）等が外れないように（v1.0.429〜）
- 支出/収入/振替の編集保存（`_save`）で、取引を新規 `Transaction(...)` で作り直す際に **既存メタ情報（`reviewed`＝検収チェック・`sortOrder`・`receiptType`・`createdAt`、収入は `receiptSaved`/`receiptUrl` も）を引き継ぐ** よう修正。編集すると明細の検収チェックが外れてしまう不具合を解消（`expense_input_screen`/`income_input_screen`/`transfer_input_screen`）。

### 支出入力の高速化＋カテゴリ提案ボタン化＋固定費の会計科目プルダウン化（v1.0.428〜）
- **支出入力/編集の高速化**: `_load` を2段階に分割。先に「カテゴリ/支払方法」だけ読んでフォームを即描画し、**過去の全取引(loadAll)＝サジェスト/提案用は表示後に裏読み**（従来は全取引を待ってから描画＝開くのが重かった）。
- **カテゴリ自動予測 → 「カテゴリを提案」ボタンに変更**: 入力途中で毎回自動予測していたのをやめ（重さ＆誤爆＝タイミング問題の解消）、大カテゴリ欄に「カテゴリを提案」ボタンを追加。押したときだけ店舗/取引内容の履歴（完全一致）から予測。見つからなければトースト。`_autoPredictCategory` は成否を bool 返却＋`manual` フラグ対応、`_suggestCategory()` から呼ぶ。過去内容サジェストを選んだ時の自動反映は従来どおり。
- **固定費（サブスク）編集の会計科目をプルダウン化**: チップ（ChoiceChip 群）から `DropdownButtonFormField`（先頭「指定なし」＝null・一覧に無い旧値も選択肢として保持）へ変更。「支出を記録」と同じ操作感に統一。`subscription_edit_sheet.dart` と `subscription_list_screen.dart` の両方。

### カテゴリ明細ビュー＋小カテゴリ編集ボタン＋デスクトップでレシート非表示（v1.0.427〜）
- **カテゴリの「明細◯件」をタップで中身を表示**: 大カテゴリ編集（`category_editor_screen`）・小カテゴリ編集（`category_sub_editor_screen`）の「明細◯件」を青リンク化。タップで共通の `CategoryTxnsScreen`（`screens/category_txns_screen.dart`）にそのカテゴリの取引一覧を表示（日付/内容/金額・立替は実質バッジ）。行タップで取引詳細（編集/削除）へ。編集/削除して戻ると件数を再読込。
- **支出入力の小カテゴリにも「小カテゴリ編集」ボタン**: 大カテゴリの「カテゴリ編集」に加え、小カテゴリ欄の見出し右に「小カテゴリ編集」を追加（`expense_input_screen._openSubCategoryEditor`）。押すと選択中の大カテゴリの `CategorySubEditorScreen` を直接開く（大カテゴリ未選択ならトーストで促す）。戻ると小カテゴリ候補を再読込。
- **デスクトップ/ブラウザでは「レシートで記録」を出さない**: 記録メニューの「レシートで記録」を `ReceiptOcrCloud.available && !kIsWeb` に変更。端末カメラ前提のためAndroidのみ表示（Electronデスクトップは中身がWeb＝kIsWebが真なので除外）。

### 立替精算に「実質負担額」＋カテゴリ予測の誤爆修正（v1.0.426〜）
- **立替精算の実質コスト化**: `Transaction` に `reimbursed`（立替回収額・任意）と `effectiveAmount`（= 支出なら `amount - reimbursed`、他は `amount`）を追加。`amount` はカード明細/クレカ突合と一致させるため**満額のまま保持**し、**集計・PL・収支・支出合計・カテゴリ/支払方法別内訳は `effectiveAmount`（実質コスト）で計算**する。口座残高・カード請求・クレカ突合・通帳は `amount`（満額）のまま。
  - 集計を effectiveAmount 化した箇所: `v2_report`（PL `_monthlyForCategory`/`_monthlyForItem`・家庭用月別収支）, `v2_home_topnav`（当月支出・支払方法別・大カテゴリ別）, `rich_home`, `v2_expenses`（合計・諸経費/外注費）, `rich_expenses`, `dev_lab_screen`（年度PL/BS・カテゴリ集計）。
  - 表示: 取引詳細に「実質のあなたの負担 ¥○」＋「立替精算」内訳（支払合計/立替/実質）を表示（`transaction_detail_screen.dart`）。支出明細一覧の行に「立替・実質 ¥○」バッジ（`expense_list_screen.dart` `_reimbursedChip`）。
  - 入力: `expense_input_screen._save` で立替ON時に `reimbursed = amount - 自己負担額` を支出取引へ保存（現金回収の振替はこれまで通り別レコードで作成）。
- **カテゴリ自動予測の誤爆修正**: `_autoPredictCategory` の履歴学習から「あいまいな部分一致(contains, weight=1)」を撤去。入力途中の文字（例「あつた」）が別カテゴリの履歴（タクシー「→あつた皮膚科」）に部分一致して交通費を誤提案する事象を解消。**店舗/取引内容の完全一致のみ**で予測（確実な一致が無ければ無提案）。

### 取引詳細の領収書セクションを事業モード限定に（v1.0.425〜）
- 取引詳細画面（`transaction_detail_screen.dart`）の**領収書/請求書ブロック（閲覧ボタン・「紙のレシートで保管済み」チェック・保管状態バッジ）を事業モードのみ表示**に変更。個人モードでは領収書の保管が税務上不要なため丸ごと非表示（`AppModeManager.instance.current == AppMode.business` で `if (isBusiness)` ガード）。支出入力フォーム側は元から事業モード限定だったのに合わせた。

### 領収書保存チェック列＋テーブルヘッダー色付け（v1.0.371〜）
- **`Transaction.receiptSaved`（bool・既定false）を追加**（toJson/fromJson/copyWith・Firestore永続化対応）。領収書URL保存済み or 現物レシート保管済みを手動チェックする税理士提出用フラグ。
- **支出明細テーブルに「領収書」チェック列を追加**（`ExpenseDetailTable.showReceiptCheck` / `onToggleReceipt`）。**事業モードのみ表示**（`rich_expenses` が `_isBusiness` で渡す）。チェック切替で `TransactionRepository.update` 保存＋再読込。緑チェックボックス。PC/スマホ両対応。
- **テーブルヘッダーをアクセント色の淡いトーンで色付け**（`Color.alphaBlend(accent 12%, white)`）。

### 支出明細テーブルの罫線＋大カテゴリのアイコン撤去（v1.0.370〜）
- **大カテゴリのバッジから色ドット（■）を撤去**（名前のみのバッジに）。
- **縦の薄い罫線（セル区切り）を追加**し表らしく。行を固定高さ（`_kRowH=40` / ヘッダー `_kHeadH=34`）にして、各列境界に1px罫線（`_kGridLine=0xFFEDF0F3`）を引く。リサイズハンドルもヘッダー高いっぱいの罫線兼用に。

### 支出明細テーブルの大/小カテゴリ列分割＋セクション余白（v1.0.369〜）
- **`ExpenseDetailTable`（支出明細・クレカ明細で共用）のカテゴリ列を「大カテゴリ」「小カテゴリ」の2列に分割**。大カテゴリは色付きバッジ（番号プレフィックスは非表示）、小カテゴリはプレーンテキスト。
  - 中央列が3→**4列**（大/小/内容/支払方法）。列幅配分 `_colFrac` を4要素化（既定 `[0.18,0.20,0.37,0.25]`）、保存キーを `futa.exp_table_col_frac_v2` に更新（旧3列設定とは非互換のため別キー）。リサイズハンドルは3本。
  - 並び替え列挙 `_SortCol` の `category` を `major`/`sub` に分割（大=majorOrder→sub、小=sub→majorOrder）。狭幅の並び替えバーも「大カテゴリ/小カテゴリ」チップに。
- **支出タブのセクション間余白**を `V2Spacing.md(12)` → `xl(24)` に広げ、カテゴリ内訳/ウォレット/固定費/明細の区切りを明確化。

### 支出タブのレイアウト整理（v1.0.368〜・rich_expenses）
- **セクション順**を「支出合計 → カテゴリ内訳 → ウォレット（クレカ照合）→ 毎月の固定費 → 各種明細」に変更（カテゴリ内訳をウォレットの上へ）。
- **カテゴリ内訳のトグル矢印（▼）を撤去**。行クリックで開閉（`_CatBar` の expand アイコン削除、onTap 開閉は維持）。
- 支出合計カードの**サブ文「明細◯件 ＋ 固定費◯円」を削除**（内訳を開けば分かるため）。
- 内訳「種類別」の**並びと表記を変更**：`固定費（サブスク）` を上、`変動費（各種支出◯件）`（件数付き）を下に。

### カテゴリ色の自動付与（v1.0.367〜）
- 大カテゴリに**手動色が無くても、名前から「それっぽい」既定色を自動付与**（食費=オレンジ、交通=ブルー、病院/薬=エメラルド、美容/衣服=ピンク、固定費=インディゴ、交際=バイオレット 等）。`CategoryColors.autoColor` がキーワード一致で色を返し、未一致は名前ハッシュでパレットから安定色。手動指定があれば従来どおりそちら優先（`CategoryColors.effective` = 手動 ?? autoColor）。
- `expenseCatColor`（支出明細・内訳の色）も従来のHSLハッシュから `CategoryColors.effective` に統一。
- **支出カテゴリ一覧（`CategoryEditorScreen`）の各行の背景・枠線・アイコン**を、そのカテゴリ色の薄いトーンに（ひと目で色が分かるように）。色アイコン（パレットボタン）は手動指定の有無を示すため未指定時はグレーのまま。

## 9. UI タブ構成

**事業モード（上タブ）**:

| タブ | 画面 | 内容 |
|---|---|---|
| ホーム | V2HomeTopNavScreen | 総資産・残高・月収支サマリー |
| 経費（事業）/ 支出（個人） | V2ExpensesScreen | 支出一覧・固定費引落予定・クレカ照合 |
| 売上（事業）/ 収入（個人） | V2IncomeScreen | 収入一覧 |
| 業績 | V2ReportScreen | 月次 PL |
| 設定 | V2SettingsScreen | マスタデータ管理 |
| 開発中 | V2DevLabScreen | 明細取込・PL/BS 等プロトタイプ |

**事業モードの経費タブ**: 「諸経費」「外注費」の2サブタブに分割
- 諸経費: 外注費カテゴリ以外の支出 + 固定費 + クレカ照合
- 外注費: カテゴリ大が「0.外注費」の支出のみ

**個人モード**: 開発中タブは「明細取込」のみ表示

**月末締めチェックリスト編集（`checklist_editor_screen`）**: メイン項目に加え、**サブ項目（子）もドラッグで並び替え可能**（v1.0.357〜。各サブ項目の左にドラッグハンドル）。

**口座詳細（通帳・`AccountDetailScreen`）の上部（v1.0.358〜）**: 月選択時は **「月初残高 → ＋入金/−出金 → 月末残高（＋差引バッジ）」の残高フロー帯**で表示（案A）。全期間時は入金/出金/差引のみ。明細は従来どおり台帳テーブル（取引日/摘要/出金/入金/残高）で、月初/月末行から残高を編集できる。

**デスクトップ（Electron）のマウス戻る/進むボタン（v1.0.357〜）**: `main.js` で `app-command`（`browser-backward`/`browser-forward`）を受け、レンダラの `history.back()/forward()` を呼ぶ。Flutter Web は `Navigator.push` でブラウザ履歴を積むため、押下で直前の画面に戻れる。
※ 設定のワイド表示（サイドバー＋右パネル）は画面遷移ではなく状態切替で詳細を出すため、その範囲ではマウス戻るは効かない（要：パネルもルート化する追加対応）。

**月末締めボタンの配置（v1.0.356〜）**: 旧来の全幅「○月を締める」バーは廃止し、**各タブ（支出/収入/ホーム）の右上に小さな操作チップ**（`MonthClosingBar(dense:true)`）で統一。未締め→「○月を締める」、締め済→「○月 締め済／取消」。目立ちすぎを解消。

**支出合計カードの内訳（v1.0.356〜）**: 展開時の内訳を **「種類別（変動費/固定費）」** と **「支払方法別」** の2セクションに、小見出し＋区切り線でハッキリ分けて表示。

**カテゴリ色の手動指定（v1.0.359〜）**: 大カテゴリに `colorValue`（ARGB int）を追加。カテゴリ編集画面の各行の**パレットアイコン**から**10色プリセット**で色を選べる（「自動（指定なし）」で解除）。
指定色は `utils/category_colors.dart`（`CategoryColors`）の中央キャッシュに保持し、`SettingsRepository.loadCategories/saveCategories` 時に更新。支出明細・内訳・一覧などの色リゾルバ（`_richCatColor`／`_catColor`／`_categoryColor`）が**指定色を最優先**し、未指定は従来の名前ベース自動色にフォールバック。

**支出カテゴリ編集（`category_editor_screen`）**: 大カテゴリはPLセクション（売上原価/人件費/販管費…）ごとに見出しを付けて表示。
ただし **PLセクション未設定（個人モード等で全カテゴリが「その他」になる場合）は、見出しを出さずフラット表示**する（v1.0.355〜。「全部その他に入って見える」違和感を解消）。

**支出明細テーブル（PC幅リッチUI・`rich_expenses`）**:
- 列順は **日付 → カテゴリ → 内容 → 支払方法 → 金額**（v1.0.351〜。旧：日付→内容→カテゴリ→…）。
- **並び替え（日付 新/古・金額 高/安）と検索（内容・カテゴリ・支払方法・備考・店舗）をこのセクション内で完結**（v1.0.351〜）。
  従来の別画面「○○明細一覧」（`ExpenseListScreen`）への導線はPCリッチUIから廃止（モバイル幅・ホーム等では引き続き使用）。
  ※検索・並び替えは明細リストのみに作用し、上のカテゴリ内訳・要約合計には影響しない。
- **カテゴリ列はカテゴリ色の淡い背景（セルのみ・行全体は塗らない）**（v1.0.353〜）。
- **並び替えは表ヘッダーのクリック**（v1.0.361〜・バッジは廃止）：日付/カテゴリ/内容/支払方法/金額の見出しをタップで並び替え、同じ列の再タップで昇順⇄降順を切替（現在列は矢印＋アクセント色）。既定は日付の降順（新しい順）。
- **日付列に曜日**（v1.0.361〜）：「06/29(月)」のように曜日を表示。**土＝青／日＝赤**、平日はグレー。
- **列幅をドラッグで変更可能**（v1.0.354〜）：中央3列（カテゴリ/内容/支払方法）の境界をヘッダーでドラッグして幅を調整。
  配分は端末に保存（`SharedPreferences` `futa.exp_table_col_frac`・全画面共通）。日付・金額列は固定幅。
- **共通ウィジェット化（v1.0.360〜）**：この表を `v2/widgets/expense_detail_table.dart` の `ExpenseDetailTable` に集約。支出タブ（rich_expenses）とクレカ詳細（`CardDetailScreen` の明細タブ）で共用。
- **レスポンシブ2行表示（v1.0.363〜）**：`ExpenseDetailTable` は**狭い幅（< 560px・スマホ）で自動的に2行のスリム表示**に切替（1行目＝日付(曜日)＋内容＋金額／2行目＝カテゴリ＋支払方法）。並び替えは上部の横スクロール「並び替えバー」で（列ラベルをタップ＝昇順/降順）。広い幅は従来の1行テーブル。

**クレカ詳細のサマリー（v1.0.362〜）**: 上部サマリーから**件数ボックスを削除**（件数は下の明細セクションに表示済み）し、**「利用合計」と「引落予定日」を高さを揃えて横並び**に。明細/請求推移タブと期間セレクタを**コンパクト化**（タブ高さ38・アイコン＋テキスト横並び、期間は余白縮小）して明細リストの表示領域を広げた。

**口座詳細（通帳）の台帳テーブル（v1.0.360〜）**: `DataTable`（列幅が内容依存で不揃い）をやめ、**列幅固定の `Table`**（取引日108／摘要flex／出金・入金100／残高124／編集40）に置換。出金=赤・入金=緑・残高=太字、月初/月末行は色付き。列が常に揃う。
**v1.0.361〜**: 月初/月末残高の数字も他行と同じ右端に揃え（編集鉛筆は編集列へ移動）、桁が一直線に並ぶようにした。

### ウォレット（経費／支出タブ上部・事業/個人 両モード）

- **v1.0.363〜**: 見出しを「ウォレット照合」→**「ウォレット」**に。照合（予定vs実際）は廃止済みのため、各行の**「予定（明細合計）」の金額表示も削除**（ウォレット名＋サブ＋「›」のみ）。行タップで各ウォレットの詳細画面へ。
- **v1.0.365〜**: カードの副題を引落日表示から**「クレジットカード」**に統一（他行の「銀行口座／現金／電子マネー」と表記を揃える。引落日はカード詳細で確認）。
- **v1.0.366〜**: 各行の右側に**合計金額（当月の明細合計）**を再表示（従来どおり）。

**カテゴリ内訳のバー（v1.0.365〜）**: 各カテゴリ行に**カテゴリのアイコン（色付き丸背景）**を表示し、**進捗バーをカテゴリ色**に（従来は一律アクセント色）。アイコンは `loadCategories` の `iconKey`、色は `expenseCatColor`（手動指定色を最優先）。「固定費・サブスク」は合算なので汎用アイコン＋アクセント色。

クレカ・銀行口座・現金・PayPay（電子マネー）のウォレットごとに **「予定（明細合計）＝当月そのウォレット払いで記録した支出の合計」だけを表示**する（`ReconcileWallet` で一般化）。
- **v1.0.353〜 簡素化**：旧来の「実際（カード通知）」列・差額バッジ・超過警告を**廃止**し、**予定のみ**に。
  「あれ？違うな」と思ったら各ウォレットの詳細画面（行タップで遷移）から編集・確認する運用。
- **行タップ → 各ウォレットの詳細画面**（クレカ=`CardDetailScreen`／銀行・現金・電子マネー=`AccountDetailScreen`。v1.0.352〜）。
- **CSV明細の取り込み・突合は残す**が、入口は**クレジットカードの詳細画面の「クレカ棚卸し（突合）」ボタン**に集約（件数の多いカード向け。`showCardReconcileSheet`）。

**ウォレット種別ごとの仕様（v1.0.345 要件定義で確定）**:

| 種別 | 照合の意味 | CSV取込・置き換え/初期化 | 文言 |
|---|---|---|---|
| クレジットカード | 記録漏れ照合（予定＝明細合計／実際＝カード会社請求額） | あり（荒療治） | 「実際（カード通知）」「請求額」「明細合計」 |
| 銀行口座 | **記録漏れ照合（カードと同じ）** | **なし**（実際額の手入力のみ） | 「実際」「使った額」「記録合計」 |
| 現金・PayPay | **実際額メモ＋履歴閲覧のみ** | なし | 「実際」「使った額」「記録合計」 |

- **表示するウォレット**（v1.0.342〜）: 現金・PayPayは常時表示。カード・銀行は当月に活動（予定>0）or 実際入力済みのときだけ表示（休眠中は隠す）。
- **明細履歴は既定で非表示**（v1.0.344〜）: 棚卸しシートの「このウォレットの当月明細」一覧・初期化ボタン・固定費一覧は
  **「履歴を編集する（N件）」ボタン**を押したときだけ展開する（普段は予定/実際の照合だけ見える）。
- カード会社前提の文言（「実際（カード通知）」「カード会社通知の請求額」「明細合計」「クレカ棚卸し」）は、
  非カードウォレットでは「実際」「実際に使った額」「記録合計」「棚卸し」に出し分け（v1.0.345〜）。

- 実装は共有ウィジェット `lib/v2/widgets/credit_card_reconcile.dart`（`CreditCardBillingSection` ＋
  `showCardReconcileSheet()`）。**モバイル幅（`v2_expenses`）と PC幅リッチUI（`rich_expenses`・支出合計のすぐ下）の両方**で表示（v1.0.314〜）。
- `RegisteredCreditCard.monthlyActualBillings`（月キー `YYYY-MM` → 実際請求額・円）に保存。
- **行タップの遷移先（v1.0.352〜変更）**: ウォレット行をタップすると、**まず詳細画面（明細一覧）**を開く。
  - **クレジットカード → `CardDetailScreen`**（利用合計/件数/引落予定日＋明細）。同画面右上の **「クレカ棚卸し（突合）」ボタン**から棚卸しシートを開く（件数の多いカードはここで突合）。
  - **銀行/現金/電子マネー → `AccountDetailScreen`（通帳）**。CSV突合は持たない（自力で追える前提）。
  - **未登録の支払方法**（手入力のPayPay等）は詳細画面が無いので、従来どおり簡易の照合シートを直接開く。
  - 旧仕様（行タップで即・棚卸しシート）は廃止。棚卸しシートの中身（下記）は CardDetailScreen から開く形に。
- 棚卸しシート（`showCardReconcileSheet`）の中身（v1.0.313〜）：
  - そのカード払いの**当月明細を一覧**表示。各行タップで取引を編集、ゴミ箱で削除。
  - **実際請求額を入力**（予定との差額を即時計算）。
  - 差額 > 0（実際が多い＝記録漏れの疑い）: **「差額ぶんを支出として記録」**ボタンで、
    支払方法＝当カード／日付＝表示月末／内容「クレカ差額調整」をプリフィルした支出入力を開き、
    その場で調整取引を追加できる。
  - 差額 < 0（明細が多い＝二重計上・取消の疑い）: 注意バナーで明細の削除・修正を促す。
  - 差額 = 0: 「一致」表示。
  - **明細突合（v1.0.316〜 / CSV対応 v1.0.317〜）**: 棚卸しシートで明細を取り込み、記録済み取引と
    **金額で突合**。結果を「一致／記録漏れ（明細にあり記録なし）／要確認（記録にあり明細なし）」に分類。
    記録漏れは店名・日付・金額をプリフィルした**[追加]ボタンでワンタップ登録**でき、差額を解消できる。
    - 取り込みは **CSVファイル（主）** ＋ コピペ（補助）。CSVは `file_picker` で選択し、`charset` で
      **Shift-JIS/UTF-8 を自動判定**して復号（`_parseCardCsv`）。対応様式: ① Orico「ご利用明細」
      （ヘッダに「ご利用日」「ご利用金額」）② 三井住友 等（1列目=日付/2列目=店名/3列目=金額）。
      金額のみで突合するため店名の表記ゆれ・日付ズレの影響を受けない。
    - **請求月と利用月のズレ対策**: 突合対象は表示中の月に縛らず、貼り付け明細の**日付範囲（±2日）**に
      含まれるそのカード払いの取引を母集団にする。
  - **荒療治：この月を初期化（v1.0.323〜）**: 明細一覧のヘッダに **「N月の◯◯カードを初期化（X件を削除）」**
    ボタン（CSV不要・明細があるとき常時表示）。そのカード払いの表示月の取引を全削除。実行前に自動バックアップ＋確認。
    「全部消してから明細を正として入れ直す」運用の最初の一歩。
  - **荒療治：CSVで置き換え（取り込みプレビュー画面・v1.0.324〜）**: 棚卸しのコストが高すぎる時の手段。
    CSV読込後の「CSVで置き換える（プレビュー）」ボタンで **取り込みプレビュー画面**（`CardCsvImportScreen`）へ。
    - **各行を編集可能**: 日付／**店名（取引内容）をその場で編集**（Amazon.co.jp 等の丸めを直せる・編集名が取引内容になる）／
      金額／**会計科目（取り込み前にAIが提案・ドロップダウンで変更可）**／行ごと除外。
    - **AI科目提案**: 開いた時に店名から科目を一括推定（`StoreCategoryClassifier`・Gemini 1回）。右上の✨で再提案。
    - **下書き保存／復元／削除**（`CardImportDraftRepository`・端末ローカル・カード×月ごと）。件数が多い時に途中保存して後で続行。
      画面を開いた時に下書きがあれば復元するか確認。
    - 「取り込む」で **CSV期間内のそのカードの既存取引を削除 → 編集後の内容で一括記帳**。
      **実行直前に自動バックアップ**（`savePreImportSnapshot`）・確認ダイアログ・カットオフ前はスキップ。
    - 旧来の「ブラインド置き換え（プレビュー無し）」は廃止し、このプレビュー画面に一本化。
  - **記録漏れリストのインライン編集（v1.0.325〜・主導線）**: CSV読込後の「記録漏れ」一覧で、**各行の店名をその場で編集**し、
    **会計科目をAIが提案（ドロップダウンで変更可）**してから **[追加]** で記帳できる。上部「AIで科目提案」で再推定、
    下部「記録漏れ ○件をまとめて追加」で一括登録。店名（Amazon.co.jp等の丸め）を直してから入れたい時はこちらが主導線。
    追加すると即・実データに保存されるため、途中で中断しても追加済みは残る（＝下書き相当）。
    `_LineEdit`（明細行ごとの店名Ctrl＋科目）を `_edits` に保持、`StoreCategoryClassifier` で一括AI提案。

**モード別の配色（リッチUI・PC幅サイドバー）**: アクセント色は事業=ネイビー / 個人=オレンジ。
v1.0.312〜、**個人モードはサイドバー背景もオレンジ基調**（`V2Colors.sidebarPersonal` 系）に切替わり、
事業=ネイビー（`V2Colors.sidebar`）と対になる。`RichSidebarShell(personal: …)` で出し分け。
（スマホ幅は下タブのため対象外）

---

## 10. 設定パネル（V2SettingsScreen）

| グループ | 項目 |
|---|---|
| 表示・UI | 表示設定・サイドバー並び順 |
| マスタデータ | 支出カテゴリ・支払方法・残高調整・収入マスタ・固定費・**税金・保険**・**手続き・届出カレンダー**・変換マスタ・チェックリスト |
| データ管理 | バックアップ・取り込み・明細の貼り付け取込 |
| アプリ情報 | バージョン・更新確認 |
| アカウント | ログイン管理・サインアウト |

### 税金・保険マスタ（マスタデータ・v1.0.349〜）

法人税・消費税・社会保険料など、**金額が大きく時期がバラバラな支払い**を「支払予定」として登録するマスタ。
実装は `screens/budget_items_screen.dart` ＋ 既存の `BudgetItem`／`BudgetItemRepository`（事業/個人でモード別・端末ローカル保存）。

- 1項目＝**名前・種別（税金/保険料/年金/その他）・支払予定（月＋金額の複数行。「毎月にする」で12ヶ月一括）・支払日・メモ**。
- **法人プリセット**：法人税・地方法人税／法人住民税（均等割含む・既定7万）／法人事業税／消費税／社会保険料（会社負担・毎月）を一括追加（金額0は後で見積もり入力、支払月は決算期に合わせ調整）。
- 登録した予定は**資金繰り表（開発ラボの「資金繰り」）＝ランウェイ予測の臨時支出**に自動で織り込まれる（月が一致する `schedule` 金額を加算）。
- 金額は**手入力の見積もり**。売上連動（消費税）・利益連動（法人税）の自動計算は今後の拡張余地。
- **v1.0.350〜 Firestore同期対応**：ログイン中は `users/{uid}/config/{mode}_budget_items` に保存され全端末で同期。
  未ログインは端末ローカル。`RepositoryProvider` で認証連動。初回同期時、リモートが空でローカルに既存があれば自動で引き上げる。

### 手続き・届出カレンダー（マスタデータ・v1.0.350〜）

算定基礎届・労働保険の年度更新・各種申告期限など、**会社の手続きの締切**を管理する（お金ではなくTODO/締切）。
実装は `screens/compliance_calendar_screen.dart` ＋ `data/compliance_task.dart`／`compliance_task_repository.dart`。
保存は税金・保険と同じく **Firestore同期**（`{mode}_compliance_tasks`）／未ログイン時ローカル。

- 1件＝**名前・分類（税務/社会保険/労働保険/登記・会社/その他）・繰り返し（毎年/毎月/随時）・期限（月日）・メモ・参考URL**。
- 一覧は**期限が近い順**に表示（あとN日／期限超過を色分け）。随時タスクは別枠。毎年タスクは**チェックで今年ぶん完了→翌年送り**。
- **法人プリセット**：源泉所得税の納付（納期特例 上期7/10・下期1/20）／社会保険料の納付（毎月）／社会保険 算定基礎届（7/10）／労働保険 年度更新（7/10）／賞与支払届（随時）／年末調整（12月）／給与支払報告書・法定調書合計表（1/31）／償却資産申告（1/31）／法人税・消費税・地方税の申告納付（決算後2ヶ月＝11/30）／決算公告・定時株主総会。期限は一般的目安で、決算期・納期特例に合わせ調整可。

---

## 11. Electron デスクトップ版

**形式**: Flutter Web ビルド を Electron で包んだデスクトップアプリ

**配信先**: Google Drive `FutaFinance-Desktop/app/` フォルダ

**自動更新フロー**:
```
起動 → Drive の version.json を確認
  → buildNumber が新しければ更新ダイアログ
  → 同じく Drive からコピー → %LOCALAPPDATA%\FutaFinance へ反映
  → explorer.exe で新プロセス起動（旧プロセスの道連れを防ぐ）
```

**version.json（Desktop）**:
```json
{ "version": "1.0.278", "buildNumber": 279 }
```

**Windows ビルド**: `desktop/Scripts/build_desktop.ps1 -Version X.Y.Z -Publish`（ユーザーが実行）
- ASCII-only スクリプト（PS5.1 の日本語崩壊回避）
- 配信先は pubspec.yaml のバージョンに自動で合わせる

---

## 12. Android APK 配信

**署名鍵**: Drive `_signing/` にバックアップ済み。`android/key.properties` で指定（gitignore）。

**配信フロー（Claude が直接実行）**:

```bash
# 1. pubspec.yaml のバージョンを +1

# 2. ビルド
cd apps/futa_finance
flutter build apk --release --dart-define=GEMINI_API_KEY=$(cat gemini.key | tr -d '[:space:]')

# 3. APK をコピー
cp build/app/outputs/flutter-apk/app-release.apk build/futa-finance-vX.Y.Z.apk

# 4. GitHub Release 作成
gh release create futa-vX.Y.Z build/futa-finance-vX.Y.Z.apk \
  --repo fffuttta-design/finance-apps \
  --title "FutaFinance vX.Y.Z+B" \
  --notes "リリースノート"

# 5. release/futa-version.json を更新して push
git add release/futa-version.json
git commit -m "release(futa): vX.Y.Z+B"
git push origin main
```

**OTA 更新検知**: アプリが起動時に `release/futa-version.json` の `buildNumber` を比較

**ドライブ配信**: `H:\マイドライブ\ツール開発\FutaFinance\apks\` には最新APK1つだけ残す（古いものは削除）

---

## 13. バージョン管理ルール

**ファイル**: `apps/futa_finance/pubspec.yaml`

```yaml
version: 1.0.278+279
#        ↑X.Y.Z  ↑B（build番号 = Android versionCode）
```

- 改修のたびに Z と B を必ず +1（typo修正でも例外なし）
- コミットメッセージ冒頭に `vX.Y.Z` を明記
- 改修完了 = デプロイ完了（ユーザーに「デプロイして」と言わせない）

---

## 14. アーキテクチャの要点

### Repository パターン

```dart
abstract class TransactionRepository {
  static TransactionRepository instance = LocalTransactionRepository();
  static void useLocal();
  static void useFirestore(String uid);
  Stream<List<Transaction>> get stream;
  Future<void> add(Transaction t);
  Future<void> update(Transaction t);
  Future<void> delete(String id);
}
// UI 側は instance を経由（実装が切り替わっても変わらない）
```

### AppMode（事業/個人 切替）

```dart
class AppModeManager extends ChangeNotifier {
  AppMode current; // business / personal
  // 切替時に全 Repository のキー/コレクションパスが変わる
  // SharedPreferences: "futa.b.*" / "futa.p.*"
}

// アクセント色
// business → Color(0xFF1A237E)（紺）
// personal → Color(0xFFEA580C)（オレンジ）
```

### 変更通知

- `TransactionRepository.stream`: 取引変更 → 収支一覧画面が自動更新
- `PaymentsChangeNotifier`: ウォレット残高変更 → ホーム残高セクションが自動更新

---

## 15. バックアップ仕様

**JSON バックアップ形式**:
```json
{
  "appVersion": "1.0.278",
  "exportedAt": "2026-06-13T10:30:00Z",
  "schema": 1,
  "data": {
    "business": { "categories": {}, "payments": {}, "transactions": [] },
    "personal": {}
  }
}
```

**自動スナップショット**:
- 取込操作前に `Documents/auto_snapshots/` へ保存
- 最新10世代を保持

---

## 16. 多通貨対応

- `Transaction.originalCurrency`: "USD" 等（null=JPY）
- `Transaction.originalAmount`: 元通貨での金額
- `Transaction.amount`: 常に円換算値
- UI では「¥14,217（$94.78）」と両方表示

---

## 17. デバイス別対応表

| 機能 | Android | Web | Electron |
|---|---|---|---|
| Google OAuth | ✅ | ✅ Popup | ✅ OAuth Bridge |
| Firestore | ✅ | ✅ | ✅ |
| レシート OCR | ✅ カメラ | ❌ | ❌ |
| Drive 保存 | ✅ | ❌ | ✅ |
| バックアップ取込 | ✅ | ✅ D&D | ✅ D&D |
| 自動更新 | ✅ APK | ❌ | ✅ Drive 監視 |
| レスポンシブレイアウト | ✅（縦） | ✅（幅≥900px でサイドバー） | ✅ |

---

## 18. 現在のバージョン

| 種別 | バージョン |
|---|---|
| Flutter アプリ（Web/Android） | 1.0.464+465 |
| Electron Desktop（Windows） | 1.0.464（pubspec版に同期） |
