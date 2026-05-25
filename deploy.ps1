# FutaFinance フルデプロイスクリプト
# 1. pubspec.yaml からバージョン取得
# 2. APKビルド (debug)
# 3. 実機(USB接続中)にインストール
# 4. hosting/futa/public/version.json をバージョン情報で更新
# 5. Firebase Hosting にデプロイ (https://futa-finance.web.app)
#
# 注: APK本体は Firebase Hosting (Sparkプラン) では配信不可(実行可能ファイル禁止)。
# 配信先は GitHub Releases等を別途構築、URLを version.json の downloadUrl に手動設定する。
#
# 使い方: pubspec.yaml の version を +1 してから本スクリプト実行。
# 引数:
#   -ReleaseNotes "リリースノート"  (省略時は "v{version} リリース")
#   -SkipInstall                  (実機インストールをスキップ)
#   -SkipDeploy                   (Firebase Hostingデプロイをスキップ)

param(
  [string]$ReleaseNotes = "",
  [switch]$SkipInstall,
  [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

# --- 共通設定 ---
$appDir = Join-Path $root "apps\futa_finance"
$hostingDir = Join-Path $root "hosting\futa"
$publicDir = Join-Path $hostingDir "public"
$apkSrc = Join-Path $appDir "build\app\outputs\flutter-apk\app-debug.apk"
$versionJson = Join-Path $publicDir "version.json"
$firebaseAccount = "contact@run-strategy.jp"
$hostingUrl = "https://futa-finance.web.app"

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

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " FutaFinance Deploy: v$fullVersion" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
  $ReleaseNotes = "v$fullVersion リリース"
}

# === 2. APKビルド ===
Write-Host "[1/4] APKビルド..." -ForegroundColor Yellow
Set-Location $appDir
flutter build apk --debug
if ($LASTEXITCODE -ne 0) {
  Set-Location $root
  Write-Error "ビルド失敗"
  exit 1
}
Set-Location $root

$apkSize = [math]::Round((Get-Item $apkSrc).Length / 1MB, 1)
Write-Host "  ✓ APK生成: $apkSize MB" -ForegroundColor Green

# === 3. 実機インストール ===
if (-not $SkipInstall) {
  Write-Host ""
  Write-Host "[2/4] 実機インストール..." -ForegroundColor Yellow
  $devices = adb devices 2>$null | Select-String "device$"
  if ($devices) {
    $device = ($devices[0] -split '\s+')[0]
    adb -s $device install -r $apkSrc
    if ($LASTEXITCODE -eq 0) {
      Write-Host "  ✓ インストール成功 ($device)" -ForegroundColor Green
    } else {
      Write-Host "  ! インストール失敗（スキップして続行）" -ForegroundColor Yellow
    }
  } else {
    Write-Host "  ! 接続中のAndroid端末なし（スキップ）" -ForegroundColor Yellow
  }
} else {
  Write-Host "[2/4] 実機インストール: スキップ" -ForegroundColor DarkGray
}

# === 4. version.json更新 ===
# 注: APK本体は Firebase Hosting (Sparkプラン) では実行可能ファイル禁止のため配信不可。
# downloadUrl は GitHub Releases等の別配信先のURLを手動で設定するか、null のままにする。
Write-Host ""
Write-Host "[3/4] version.json を更新..." -ForegroundColor Yellow
$existingDownloadUrl = $null
if (Test-Path $versionJson) {
  try {
    $existing = Get-Content $versionJson -Raw | ConvertFrom-Json
    $existingDownloadUrl = $existing.downloadUrl
  } catch {}
}
$json = [PSCustomObject]@{
  version = $version
  buildNumber = $buildNumber
  downloadUrl = $existingDownloadUrl
  releaseNotes = $ReleaseNotes
} | ConvertTo-Json -Depth 5
# UTF8 (BOMなし) で書き出し
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($versionJson, $json, $utf8NoBom)
Write-Host "  ✓ version: $version+$buildNumber" -ForegroundColor Green
if ($existingDownloadUrl) {
  Write-Host "  ✓ downloadUrl: $existingDownloadUrl (既存値を保持)" -ForegroundColor Green
} else {
  Write-Host "  ! downloadUrl: 未設定（version.json手動で配信先URLを書くか、別配信を構築）" -ForegroundColor Yellow
}

# === 5. Firebase Hosting デプロイ ===
if (-not $SkipDeploy) {
  Write-Host ""
  Write-Host "[4/4] Firebase Hosting にデプロイ..." -ForegroundColor Yellow
  Set-Location $hostingDir
  firebase deploy --only hosting --account $firebaseAccount
  $deployExit = $LASTEXITCODE
  Set-Location $root
  if ($deployExit -ne 0) {
    Write-Error "Firebase deploy 失敗"
    exit 1
  }
  Write-Host "  ✓ Deploy完了: $hostingUrl" -ForegroundColor Green
} else {
  Write-Host "[4/4] Firebase Hosting デプロイ: スキップ" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host " Deploy完了: v$fullVersion" -ForegroundColor Green
Write-Host " バージョンJSON: $hostingUrl/version.json" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
