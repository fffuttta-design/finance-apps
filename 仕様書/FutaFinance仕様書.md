# FutaFinance 仕様書

> **最終更新: 2026-06-25 / v1.0.342+343**
> 変更があるたびにこのファイルを編集してバージョンを更新すること。

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

**オプション**: 領収書画像・店舗名・備考・多通貨（USD等）

### 5.2 収入（Income）入力

**必須**: 日付・収入マスタ選択 or 手入力名・金額

**オプション**: 備考

### 5.3 振替（Transfer）入力

口座間の移動（収支に影響しない）。

例: 銀行 → クレジットカード累積額へ振替

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

### クレカ引落照合・棚卸し（経費／支出タブ上部・事業/個人 両モード）

クレカごとに「**予定（明細合計）**＝当月そのカード払いで記録した支出の合計」と
「**実際（カード通知）**＝月末に実際に引き落とされた請求額（手入力）」を並べ、差額で棚卸しを促す。

- 実装は共有ウィジェット `lib/v2/widgets/credit_card_reconcile.dart`（`CreditCardBillingSection` ＋
  `showCardReconcileSheet()`）。**モバイル幅（`v2_expenses`）と PC幅リッチUI（`rich_expenses`・支出合計のすぐ下）の両方**で表示（v1.0.314〜）。
- `RegisteredCreditCard.monthlyActualBillings`（月キー `YYYY-MM` → 実際請求額・円）に保存。
- 一覧の各カード行をタップ → **棚卸しシート**を開く（v1.0.313〜）。
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
| マスタデータ | 支出カテゴリ・支払方法・残高調整・収入マスタ・固定費・変換マスタ・チェックリスト |
| データ管理 | バックアップ・取り込み・明細の貼り付け取込 |
| アプリ情報 | バージョン・更新確認 |
| アカウント | ログイン管理・サインアウト |

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
| Flutter アプリ | 1.0.342+343 |
| Electron Desktop | 1.0.278 / buildNumber 279 |
