# Release Distribution

このディレクトリはアプリのリリース配信メタデータを格納する。

## ファイル

- `futa-version.json` — FutaFinance の最新版情報（GitHub raw でアプリが fetch）
- `takuharu-version.json` — たくはるファイナンス用（将来）

## APK配信

APK 本体は GitHub Releases に置く（このディレクトリには入れない）。

- リリースタグ: `futa-v{major}.{minor}.{patch}` (例: `futa-v1.0.13`)
- アセット名: `futa-finance-v{version}.apk`
- ダウンロードURL（公開）:
  `https://github.com/fffuttta-design/finance-apps/releases/download/futa-v{version}/futa-finance-v{version}.apk`

## version.json のフォーマット

```json
{
  "version": "1.0.13",
  "buildNumber": "14",
  "downloadUrl": "https://github.com/fffuttta-design/finance-apps/releases/download/futa-v1.0.13/futa-finance-v1.0.13.apk",
  "releaseNotes": "リリース内容"
}
```

## 更新の流れ

`deploy.ps1` が自動的に：
1. pubspec.yaml の version を取得
2. APK ビルド
3. 実機インストール
4. `release/futa-version.json` 更新
5. git commit & push
6. `gh release create` で GitHub Release 作成 + APK アセット添付
