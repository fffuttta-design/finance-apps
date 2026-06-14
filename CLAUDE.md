# CLAUDE.md - FutaFinance プロジェクト指示書

このリポジトリで開発する全ての Claude セッションが**必ず開発開始時にこのドキュメントを参照する**こと。違反したらやり直し。

---

## 📋 仕様書（必ず読む）

**作業開始時に必ず読むこと:**

- **FutaFinance（事業・個人）** → `仕様書/FutaFinance仕様書.md`
- **たくはるファイナンス（カップル家計簿）** → `仕様書/たくはるファイナンス仕様書.md`

各アプリの仕様（データ構造・API・UI・機能・バージョン管理）が網羅されている。

**仕様書の更新ルール（必須）**:
機能を追加・変更したら **その場で** 該当アプリの仕様書の該当箇所を編集すること。
バージョン更新時は仕様書冒頭の「最終更新」とバージョン表も更新する。

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

### ③ 改修のたびに必ずデプロイ（例外なし）
**コード改修が終わったら、毎回・必ず・自動でデプロイまで完了させること。**
ユーザーに「デプロイして」と言わせない。改修完了 = デプロイ完了。

### ④ 対象デバイス全てに配信
改修が完了したら、以下の環境への配信を確実に:

| 環境 | 配信方法 | 実行者 |
|---|---|---|
| **Web** | `git push origin main` | Claude（push で自動） |
| **Android (FutaFinance)** | Bash で flutter build → gh release → version.json push | Claude が直接実行 |
| **Android (たくはる)** | Bash で flutter build → gh release → version.json push | Claude が直接実行 |
| **Windows Desktop** | `cd apps/futa_finance/desktop/Scripts && powershell -ExecutionPolicy Bypass -File build_desktop.ps1 -Publish` | Claude が直接実行 |

---

## FutaFinance 配信フロー（Claude が直接実行）

### ⚠️ 権限設定（初回のみ・ユーザーが設定）
`gh release create` は Claude の auto mode 分類器にブロックされる場合がある。
`C:\Users\visit\.claude\settings.json` の allow に以下を追加しておくこと：
```json
"Bash(gh release create:*)"
```
→ これで以後 Claude が自動実行できる。

```bash
# 1. pubspec.yaml の version を +1（apps/futa_finance/pubspec.yaml）

# 2. コミット & Web 配信
git add <changed files>
git commit -m "feat(futa): vX.Y.Z - 内容"
git push origin main
# → GitHub Actions が自動で Web (gh-pages) を更新

# 3. Android APK ビルド
cd apps/futa_finance
flutter build apk --release --dart-define=GEMINI_API_KEY=$(cat gemini.key | tr -d '[:space:]')

# 4. APK を versioned 名にコピー
cp build/app/outputs/flutter-apk/app-release.apk build/futa-finance-vX.Y.Z.apk

# 5. GitHub Release 作成（APK アップロード）
gh release create futa-vX.Y.Z build/futa-finance-vX.Y.Z.apk \
  --repo fffuttta-design/finance-apps \
  --title "FutaFinance vX.Y.Z+B" \
  --notes "リリースノート"

# 6. release/futa-version.json を更新して push
# (downloadUrl = https://github.com/fffuttta-design/finance-apps/releases/download/futa-vX.Y.Z/futa-finance-vX.Y.Z.apk)
git add release/futa-version.json
git commit -m "release(futa): vX.Y.Z+B - リリースノート"
git push origin main
```

### Windows Desktop 配信（ユーザーが実行）

デスクトップ版は **GitHub Releases** で配信する（Drive非依存）。
更新チェック: アプリ起動時に `release/futa-windows-version.json` を GitHub raw から fetch。

```powershell
# ユーザーの実機で実行（デスクトップアプリのビルドは Claude の Bash では不可）
cd C:\dev\CoreBusinessTools\finance-apps\apps\futa_finance\desktop\Scripts
.\build_desktop.ps1 -Publish
# → zip 作成 → gh release create futa-win-vX.Y.Z → futa-windows-version.json 更新 → git push
```

初回インストール手順（他PC）:
1. GitHub Releases から `futa-desktop-vX.Y.Z.zip` をダウンロード
2. 任意の場所に解凍
3. `FutaFinance.exe` を一度実行 → `%LOCALAPPDATA%\FutaFinance` へ自動インストール
4. 以降は `%LOCALAPPDATA%\FutaFinance\FutaFinance.exe`（またはデスクトップのショートカット）から起動

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

## たくはるファイナンス（apps/takuharu_finance）

FutaFinance とは別アプリ。改修・配信手順は以下の通り。

### バージョン管理
- `apps/takuharu_finance/pubspec.yaml` の `version: X.Y.Z+B` を +1
- コミットメッセージ: `feat(takuharu): vX.Y.Z - 内容`

### Android 配信手順（Claudeが直接実行する）
```bash
# 1. APK ビルド
cd apps/takuharu_finance
flutter build apk --release --dart-define=GEMINI_API_KEY=$(cat gemini.key | tr -d '[:space:]')

# 2. GitHub Release 作成（APK アップロード）
gh release create takuharu-vX.Y.Z \
  apps/takuharu_finance/build/takuharu-finance-vX.Y.Z.apk \
  --repo fffuttta-design/finance-apps \
  --title "takuharu-finance vX.Y.Z+B" \
  --notes "リリースノート"

# 3. release/takuharu-version.json を更新して push
git add release/takuharu-version.json
git commit -m "release(takuharu): vX.Y.Z+B - リリースノート"
git push origin main
```

- APK は `release/takuharu-version.json` の `downloadUrl` 経由でアプリが自動検知・OTA配信
- ユーザーにスクリプト実行を頼まず、Claude が Bash で直接実行する

---

## このドキュメント自体の更新

- 新しいルールができたら追記
- 古いルールが変わったら更新
- 削除する時はユーザーに必ず確認
