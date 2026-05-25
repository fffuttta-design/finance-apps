# FutaFinance フルデプロイスクリプト (GitHub Releases配信)
#
# フロー:
# 1. pubspec.yaml からバージョン取得
# 2. APKビルド (debug)
# 3. 実機(USB接続中)にインストール
# 4. release/futa-version.json をバージョン情報で更新
# 5. git commit & push (version.json + コミット履歴更新)
# 6. gh release create で GitHub Release 作成 + APK アセット添付
#
# 使い方: pubspec.yaml の version を +1 してから本スクリプト実行。
# 引数:
#   -ReleaseNotes "リリースノート"  (省略時は "v{version} リリース")
#   -SkipInstall                  (実機インストールをスキップ)
#   -SkipRelease                  (GitHub Releaseとgit pushをスキップ)
#
# 前提:
#   - gh CLI ログイン済 (gh auth status)
#   - git origin が fffuttta-design/finance-apps に設定済

param(
  [string]$ReleaseNotes = "",
  [switch]$SkipInstall,
  [switch]$SkipRelease
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

# --- 共通設定 ---
$appDir = Join-Path $root "apps\futa_finance"
$apkSrc = Join-Path $appDir "build\app\outputs\flutter-apk\app-debug.apk"
$versionJson = Join-Path $root "release\futa-version.json"
$repo = "fffuttta-design/finance-apps"

# --- パス確保 ---
$env:Path = "$env:Path;$env:LOCALAPPDATA\Pub\Cache\bin;$env:LOCALAPPDATA\Android\Sdk\platform-tools"

# === 1. バージョン取得 ===
$pubspecPath = Join-Path $appDir "pubspec.yaml"
$content = Get-Content $pubspecPath -Raw
if ($content -notmatch '(?m)^version:\s*([\d\.]+)\+(\d+)\s*$') {
  Write-Error "pubspec.yaml から version を取得できませんでした"
  exit 1
}
$version = $Matches[1]
$buildNumber = $Matches[2]
$fullVersion = "$version+$buildNumber"
$tag = "futa-v$version"
$assetName = "futa-finance-v$version.apk"
$downloadUrl = "https://github.com/$repo/releases/download/$tag/$assetName"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " FutaFinance Deploy: v$fullVersion" -ForegroundColor Cyan
Write-Host " Tag:        $tag" -ForegroundColor DarkGray
Write-Host " Asset:      $assetName" -ForegroundColor DarkGray
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
  $ReleaseNotes = "v$fullVersion リリース"
}

# === 2. APKビルド ===
Write-Host "[1/5] APKビルド..." -ForegroundColor Yellow
Set-Location $appDir
flutter build apk --debug
if ($LASTEXITCODE -ne 0) {
  Set-Location $root
  Write-Error "ビルド失敗"
  exit 1
}
Set-Location $root

$apkSize = [math]::Round((Get-Item $apkSrc).Length / 1MB, 1)
Write-Host "  OK APK生成: $apkSize MB" -ForegroundColor Green

# === 3. 実機インストール ===
if (-not $SkipInstall) {
  Write-Host ""
  Write-Host "[2/5] 実機インストール..." -ForegroundColor Yellow
  $devices = adb devices 2>$null | Select-String "device$"
  if ($devices) {
    $device = ($devices[0] -split '\s+')[0]
    adb -s $device install -r $apkSrc
    if ($LASTEXITCODE -eq 0) {
      Write-Host "  OK インストール成功 ($device)" -ForegroundColor Green
    } else {
      Write-Host "  -- インストール失敗 (スキップして続行)" -ForegroundColor Yellow
    }
  } else {
    Write-Host "  -- 接続中のAndroid端末なし (スキップ)" -ForegroundColor Yellow
  }
} else {
  Write-Host "[2/5] 実機インストール: スキップ" -ForegroundColor DarkGray
}

# === 4. version.json 更新 ===
Write-Host ""
Write-Host "[3/5] release/futa-version.json 更新..." -ForegroundColor Yellow
$json = [PSCustomObject]@{
  version = $version
  buildNumber = $buildNumber
  downloadUrl = $downloadUrl
  releaseNotes = $ReleaseNotes
} | ConvertTo-Json -Depth 5
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($versionJson, $json, $utf8NoBom)
Write-Host "  OK version: $version+$buildNumber" -ForegroundColor Green
Write-Host "  OK downloadUrl: $downloadUrl" -ForegroundColor Green

if ($SkipRelease) {
  Write-Host ""
  Write-Host "[4/5] git push: スキップ" -ForegroundColor DarkGray
  Write-Host "[5/5] GitHub Release: スキップ" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "===============================================" -ForegroundColor Green
  Write-Host " ローカル更新のみ完了: v$fullVersion" -ForegroundColor Green
  Write-Host "===============================================" -ForegroundColor Green
  exit 0
}

# === 5. git commit & push ===
Write-Host ""
Write-Host "[4/5] git commit and push..." -ForegroundColor Yellow
git add release/futa-version.json
$gitStatus = git status --porcelain release/futa-version.json
if ($gitStatus) {
  git commit -m "release(futa): v$fullVersion - $ReleaseNotes"
  if ($LASTEXITCODE -ne 0) {
    Write-Error "git commit 失敗"
    exit 1
  }
}
git push origin main
if ($LASTEXITCODE -ne 0) {
  Write-Error "git push 失敗"
  exit 1
}
Write-Host "  OK push完了" -ForegroundColor Green

# === 6. GitHub Release作成 ===
Write-Host ""
Write-Host "[5/5] GitHub Release 作成 (tag: $tag)..." -ForegroundColor Yellow

# 既存タグがあれば削除（同じバージョンで再リリースする場合の事故防止）
gh release view $tag --repo $repo 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host "  既存リリース $tag を削除して再作成します" -ForegroundColor Yellow
  gh release delete $tag --repo $repo --yes --cleanup-tag
}

gh release create $tag "$apkSrc#$assetName" `
  --repo $repo `
  --title "FutaFinance v$fullVersion" `
  --notes $ReleaseNotes
if ($LASTEXITCODE -ne 0) {
  Write-Error "gh release create 失敗"
  exit 1
}
Write-Host "  OK Release作成完了" -ForegroundColor Green

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host " Deploy完了: v$fullVersion" -ForegroundColor Green
Write-Host " Release:    https://github.com/$repo/releases/tag/$tag" -ForegroundColor Green
Write-Host " APK直リン:  $downloadUrl" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
