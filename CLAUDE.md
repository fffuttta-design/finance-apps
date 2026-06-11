# CLAUDE.md - FutaFinance プロジェクト指示書

このリポジトリで開発する全ての Claude セッションが**必ず開発開始時にこのドキュメントを参照する**こと。違反したらやり直し。

---

## 🚨 絶対ルール（破ったら即やり直し）

### ① このドキュメントを必ず参照
- 開発開始時に `CLAUDE.md` を読む
- 不明点があれば最初にここを確認
- ルールに反する操作はしない

### ② 改修したら必ずバージョンを上げる
- **例外なし**。小さな typo 修正でも上げる。
- `apps/futa_finance/pubspec.yaml` の `version: X.Y.Z+B` で:
  - `X.Y.Z` のパッチ番号（Z）を +1
  - `+B` の build 番号も +1
- コミットメッセージ冒頭に `vX.Y.Z` を明記
  - 例: `feat(futa): v1.0.57 - ホーム画面の色調整`
- レスポンス冒頭に **`✅ vX.Y.Z デプロイ完了`** を明記

### ③ 対象デバイス全てに配信
改修が完了したら、以下 3 環境への配信を確実に:

| 環境 | 配信方法 | 自動 or 手動 |
|---|---|---|
| **Web** | `git push origin main` | GitHub Actions が自動で gh-pages 更新 |
| **Android** | `pwsh deploy.ps1` | 手動実行。APK ビルド + GitHub Release + version.json |
| **Windows Desktop** | **Electron版**（`apps/futa_finance/desktop`）。`desktop/Scripts/build_desktop.ps1 -Version X.Y.Z -Publish` で NSIS インストーラをビルド → Drive `FutaFinance-Desktop` へ配布（自動更新あり） | 手動実行 |

> ※ Windows は Flutter ネイティブ版を**退役**（日本語IMEのカーソル飛び対策で Electron 化）。`flutter build windows` 用の `windows/` と `deploy_windows.ps1` は削除済み。詳細はメモリ「FutaFinance Electronデスクトップ版」。

- Web は git push で自動完了（数分で反映）
- Android は `deploy.ps1` を実行しないとリリースされない。バージョンは pubspec.yaml から読まれる
- Windows は将来対応

---

## 配信フロー（手順）

```bash
# 1. pubspec.yaml の version を +1
# 2. 改修コードを stage
git add <changed files>

# 3. コミット（メッセージ冒頭に vX.Y.Z）
git commit -m "v1.0.X - <summary>"

# 4. Web 配信（自動）
git push origin main
# → GitHub Actions が gh-pages を更新
# → https://fffuttta-design.github.io/finance-apps/ に反映

# 5. Android 配信（手動、リリースしたい時のみ）
pwsh deploy.ps1
# → APK release ビルド + 実機インストール + GitHub Release 作成
# → アプリ起動時の更新チェックが新版を検出
```

---

## プロジェクト構造

```
finance-apps/
├── apps/
│   ├── futa_finance/        FutaFinance アプリ（メイン）
│   │   ├── lib/screens/     画面群
│   │   ├── lib/data/        Repository/Notifier
│   │   ├── lib/widgets/     共通 widget
│   │   ├── lib/utils/       ユーティリティ
│   │   └── pubspec.yaml     ← version はここ
│   └── takuharu_finance/    たくはるファイナンス（別アプリ）
├── packages/
│   └── finance_core/        共通モデル・ロジック
├── scripts/
│   └── generate_initial_backup.py   マスタデータ JSON 生成
├── firebase/futa/           Firestore Security Rules
├── release/
│   ├── futa-version.json    Android 更新チェック用（deploy.ps1 が更新）
│   └── apks/                APK 配信先
├── hosting/                 静的ホスティング雛形
└── deploy.ps1               Android リリーススクリプト
```

---

## アーキテクチャの要点

### Repository パターン
- 各データ種類（Transaction / Settings / Subscription / etc）に abstract Repository
- Local（SharedPreferences）/ Firestore で実装切替
- 認証状態で `RepositoryProvider.useLocal()` / `useFirestore(uid)` 切替

### AppMode（事業/個人 切替）
- `AppModeManager` で全画面のモードを統一切替
- 各 Repository のキー/コレクションパスは modePrefix で分離
- `ModeAwareMixin` で State 内のモード変更通知を受ける

### 変更通知
- `TransactionRepository.stream`: 取引の変更
- `PaymentsChangeNotifier`: payments（ウォレット/カード）の変更
  - 通帳画面で残高保存 → ホームの残高セクションが自動更新

### Web 専用対応
- レスポンシブレイアウト: 幅 ≥ 900px でサイドバーモード
- 画像 CORS 対策: `BrandLogo` は Web で HtmlElementView を使用
- バックアップ取り込み: D&D ゾーン + 自動リロード

---

## 主要画面

| 画面 | 役割 |
|---|---|
| HomeScreen | 残高/月次収支/支出内訳サマリー |
| ExpensesScreen | 支出タブ（リスト/カテゴリ/行/チャート） |
| IncomeScreen | 収入タブ |
| AssetScreen | 資産タブ（銀行/現金/電子マネーの入出金） |
| CardsScreen | クレカタブ（一覧 + 月別請求合算） |
| ReportScreen | 集計タブ |
| SettingsScreen | 設定 |
| TableViewScreen | テーブルビュー（Web 専用） |
| AccountDetailScreen | 通帳画面（口座詳細） |
| CardDetailScreen | クレカ詳細（明細 + 請求推移タブ） |

---

## バージョン履歴の参照
- `git log --oneline | head -50` で最近の改修確認
- 各コミットメッセージに変更内容記載

---

## トラブル時のチェックリスト

| 症状 | 確認 |
|---|---|
| 画面が灰色 | 開発者ツールのコンソールでエラー確認、`late` 初期化漏れチェック |
| 変更が反映されない | `Ctrl+Shift+R` で強制リロード、PaymentsChangeNotifier の listen 漏れ確認 |
| 取り込み失敗 | `_Namespace` エラー = Web で path_provider 呼んでる、kIsWeb 分岐確認 |
| Firestore 書き込まれない | TransactionRepository / SettingsRepository が Firestore 実装になってるか確認 |
| バージョンが上がってない | **このルール違反**。即 +1 して再コミット |

---

## このドキュメント自体の更新

- 新しいルールができたら追記
- 古いルールが変わったら更新
- 削除する時はユーザーに必ず確認
