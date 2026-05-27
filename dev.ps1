# 開発用 Flutter Web 起動スクリプト
#
# ⚠ このファイルは「開発時のみ」の便利スクリプト。
# 本番Android配布(deploy.ps1)とは完全に独立、テスト終了したら以下を削除すればOK:
#   - このファイル (dev.ps1)
#   - .chrome-dev-profile/ ディレクトリ
#   - .gitignore の "/.chrome-dev-profile/" 行
#
# 何をしているか:
#   flutter run -d chrome を、Chrome の永続プロファイルで起動する。
#   通常の `flutter run -d chrome` は毎回新規プロファイルで起動するため
#   localStorage(=shared_preferences) がリセットされ、登録データ
#   (クレカ・銀行口座・取引等) が再起動の度に消えてしまう問題があった。
#   --user-data-dir で永続ディレクトリを指定すれば解決する。
#
# 使い方:
#   .\dev.ps1               # ポート8081で起動
#   .\dev.ps1 -Port 8082    # 別ポートで起動

param(
  [int]$Port = 8081
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot

$env:Path = "$env:Path;$env:LOCALAPPDATA\Pub\Cache\bin"

# 永続Chromeプロファイル用ディレクトリ（gitignore対象）
$profileDir = Join-Path $root ".chrome-dev-profile"
New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

# 既存の dev-profile Chrome を閉じる
# (ユーザー通常Chromeには触らない — CommandLine に profileDir を含むプロセスだけ対象)
$escapedDir = [regex]::Escape($profileDir)
$existing = Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match $escapedDir }
if ($existing) {
  Write-Host "既存のdev-profile Chromeを閉じます ($($existing.Count) プロセス)" -ForegroundColor DarkGray
  $existing | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Milliseconds 500
}

# 既存の dart/flutter プロセスも掃除（ポート競合防止）
Get-Process -Name "dart" -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " Flutter Web Dev (永続プロファイル)" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " URL:      http://localhost:$Port" -ForegroundColor Green
Write-Host " Profile:  $profileDir" -ForegroundColor DarkGray
Write-Host " 停止:     Ctrl+C" -ForegroundColor DarkGray
Write-Host ""

Set-Location (Join-Path $root "apps\futa_finance")
flutter run -d chrome --web-port=$Port --web-browser-flag="--user-data-dir=$profileDir"
