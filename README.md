# finance-apps

2つの財務系Flutterアプリのmonorepo。

## アプリ
- **FutaFinance** (`apps/futa_finance`) — 事業用財務管理アプリ（個人用）
- **たくはるファイナンス** (`apps/takuharu_finance`) — カップル家計簿アプリ（2人で使用）

## 共通パッケージ
- **finance_core** (`packages/finance_core`) — 収支記録・カテゴリ・OCR・DB抽象などの共通処理

## セットアップ

```powershell
# 依存関係のインストール（初回およびpubspec変更時）
melos bootstrap

# FutaFinanceを実機で起動
melos run run:futa

# たくはるファイナンスを実機で起動
melos run run:takuharu
```

## バージョン管理ルール
改修ごとに該当アプリの `pubspec.yaml` の `version` のパッチ番号を +1 してコミットする。
（例: `1.0.0+1` → `1.0.1+2`）
