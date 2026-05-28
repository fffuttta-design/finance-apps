# FutaFinance / たくはるファイナンス 開発メモ

このファイルは「将来の運用案・検討中の構想・記憶しておきたいこと」を蓄積する場所。  
セッションが切れても次回作業時に Claude が読めるようにする。

---

## 🌐 マルチデバイス前提の設計（最重要）

**FutaFinance はマルチネイティブ前提**:
- Android（現在メイン）
- Web（GitHub Pages 公開予定）
- Windows デスクトップ（後日対応）

**同じデータをどの端末でも扱う**ため、**クラウド同期は前提条件**（Tier 0 / 最優先）。

---

## 🛡️ データ保護/同期ロードマップ

### Tier 0（最優先・実装中）

- [ ] **Firestore リアルタイム同期**
  - Auth: Google Sign-In のみ
  - データ構造: `users/{uid}/business/...` と `users/{uid}/personal/...`
  - FutaFinance（事業+個人）は `futa-finance` プロジェクト
  - たくはるファイナンスは `takuharu-finance` プロジェクト（別アプリ）
  - オフライン対応: Firestore SDK built-in
  - 競合解決: ドキュメント単位 last-write-wins (updatedAt フィールド)
  - 認証必須（未ログインだとアプリ使えない）

### Tier 1（Tier 0 完了後）

- [x] **インポート前の自動スナップショット** ✅ v1.0.41
- [x] **月末締め完了時の自動エクスポート提案** ✅ v1.0.42
- [x] **破壊的操作の前に自動スナップショット** ✅ v1.0.43
- [ ] **14日経過リマインダー**
  - 最終バックアップから14日経過 → 起動時に通知

### Tier 2（中期）

- [ ] **複数世代スナップショット（クラウド側）**
  - Firestore に履歴コレクション
  - 月1スナップショット自動取得
  - 1年間保持

- [ ] **データ整合性チェック**
  - 起動時にパース検証
  - 壊れていたら警告 → 自動復元案内

- [ ] **JSON書き出しに署名/ハッシュ追加**
  - SHA-256 添付
  - 改ざん/破損検知

- [ ] **スプシ書き込み運用**
  - データを Google Sheets にも書き込み（履歴・俯瞰・保険）
  - Google Sheets API v4
  - Tier 0 完成後の追加層として実装

### Tier 3（長期）

- [ ] **暗号化対応**
- [ ] **変更履歴（changelog）+ undo/redo**

---

## 🔐 Firestore データモデル設計

### futa-finance プロジェクト

```
users/{uid}/
  business/                       ← 事業モード
    transactions/{txId}             ← 1取引1ドキュメント
    config/payments                 ← bankAccounts + creditCards
    config/categories               ← CategoryConfig
    config/subscriptions            ← SubscriptionConfig
    config/income_sources           ← IncomeSourceConfig
    config/checklist                ← ChecklistConfig
    monthly_snapshots/{yyyy-MM}     ← 月初残高
    month_closings/{yyyy-MM}        ← 月末締め
  personal/                       ← 個人モード（同じ構造）
    transactions/...
    config/...
```

設計判断:
- 個別取引は1ドキュメント1取引（数百〜数千件のため）
- 設定系（カテゴリ・支払方法・サブスク等）は config 配下に1ドキュメント
- 月別データは {yyyy-MM} を key に

### Repository アーキテクチャ

```
abstract class XxxRepository {
  static XxxRepository instance = LocalXxxRepository();
  static void useLocal() { ... }
  static void useFirestore(String uid) { ... } // 後で
}

class LocalXxxRepository implements XxxRepository {
  // SharedPreferences ベース（既存）
}

class FirestoreXxxRepository implements XxxRepository {
  // Firestore + offline cache（後で）
}
```

UI 側は `XxxRepository.instance.foo()` のままで、起動時にどちらを使うか切替。

---

## 📊 スプシ書き込み運用（Tier 2 候補）

**コンセプト**: アプリ内の取引/サブスク/口座データを Google Sheets にもリアルタイム or 定期で書き込み、**履歴として残す**。

Tier 0（Firestore 同期）完成後に検討。

### 利点
- スプシは長年使い慣れているツール（俯瞰しやすい、ピボット集計等）
- Firestore + スプシで二重保管 → 最強保険
- スプシ側で月次/年次サマリを自由に作れる

### 想定構成
- Google Sheets API v4
- リアルタイム or 日次バッチ
- シート構成:
  - 「取引履歴」シート: 1行1取引
  - 「サブスク」「口座」「カード」シート
  - 「変更履歴」シート

---

## 🗃️ JSON バックアップファイル命名規則（運用ルール）

Tier 0 実装後も、念のためのアーカイブとして JSON 書き出しは残す（年次保険）。

```
H:\マイドライブ\ツール開発\FutaFinance\
├── futa-finance-data-{概要}.json       ← 最新（アプリ取り込み先）
├── apks\                               ← APK 一式
└── archive\
    └── data-{YYYYMMDD-HHMM}-{元タグ}.json
```

スクリプト実行時の概要タグの付け方:
- データ追加: `個人モードに資金口座5つ追加`
- アイコン変更: `オリコ-JCBアイコン更新`
- 機能追加: `カード備考機能-PayPay追加`
- 修正: `家賃の月額修正`

---

## 📝 その他の将来アイデア

- 事業モードの税金予測機能（長年の夢、優先度低）
- OCR レシート読み取り（Gemini API、Tier 1 候補だったが保留）
- カレンダー連携（Google Calendar に予定された支出を出す）
- 通知連動（家賃引落日の前日にプッシュ通知）
- Windows デスクトップ対応（Flutter Desktop で）

---

## 💡 構想メモ（v1.0.61 時点で追加）

### 事業の財務管理を本格化

- **PL（損益計算書）の簡易管理**
  - 月次 / 年次の売上・経費・利益を一画面で確認
  - カテゴリ別の経費を「会計科目」っぽくグルーピング
  - 既存の事業モードの transactions ＋ subscriptions から自動集計でほぼ作れる
  - 出力先: 集計タブの中に「PL ビュー」追加 or 専用画面

- **BS（貸借対照表）の簡易管理**
  - 資産（銀行/現金/電子マネー） − 負債（クレカ未払・借入金）= 純資産
  - 「負債」モデルが現状ない → 借入金マスタを新設する必要あり
  - 月次スナップショットで時系列推移も見たい

- **事業の調子の可視化（ダッシュボード）**
  - 月次売上の前年同月比、移動平均、トレンド
  - 利益率、固定費比率、変動費比率
  - 売掛 / 買掛の残高（将来）
  - "ホーム画面の事業モード時の上半分" に置くイメージ

### 月末棚卸し関連

- **チェックリスト項目: ドル決済明細を円換算に置き換える**
  - クレカ会社の明細を見れば、確定の円換算額が分かる
  - 月末締め時に「USD で入力した取引を、クレカ明細の円額で上書き」する作業
  - 既存の `transactions.originalCurrency == 'USD'` のものを抽出 → 一覧表示 → 円額を入力で上書き、というフローが理想
  - 月末締めチェックリストに「USD取引の円確定」項目を自動で生やせると便利

---

最終更新: v1.0.61 リリース時点（残高0非表示+エンゲル係数追加）
